; 
;-------------------------------------------------------------------------------
; Writen for zasm assembler:
;  https://k1.spdns.de/Develop/Projects/zasm/Distributions/
#target rom

CPU_FREQ	equ		4000000		; 4MHz

#data _RAM,0x8000,0x7000
#code _ROM,0,0x8000
;===============================================================================
;===============================================================================
; Reset Vectors
RESET:
	JP	START

	ORG	0x08		; RST $08
	JP	START
	ORG	0x10		; RST $10
	JP	START
	ORG	0x18		; RST $18
	JP	START
	ORG	0x20		; RST $20
	JP	START
	ORG	0x28		; RST $28
	JP	START
	ORG	0x30		; RST $30
	JP	START
	ORG	0x38		; RST $38
	JP	INT


	ORG 	0x66		; NMI vector
	JP	NMI


	ORG	0x80		; Entry point
;===============================================================================
;===============================================================================
; Program Entry Point
START:
#local	
	; First thing we need to do is set up the bank switch register to map
	; some RAM. By default we have the low 32kB of ROM in both 32kB banks.
	; 0x8B Map 1st page of ram to high 32kB, RAM Bank 3 to low (ROM emulation loader)
	LD	A, 0x8B		
	OUT	(PORT_BANK), A

	LD	SP, 0xFFFF	; Set stack to top of RAM
	
	; Clear RAM (0x8000-0xFFFF) before we use the stack
;	LD	HL, 0x8000
;	LD	B, 0
;CLRMEM:	LD	(HL), B
;	INC	HL
;	LD	A, H
;	OR	L
;	JR	NZ, CLRMEM	; Clear till 0xFFFF
	
	CALL	LCDINIT
	
	LD	HL, STR_LCDBANNER
	CALL	LCDPUTS
	NOP	; Required before CF_INIT otherwise will fail! (Why?!)
	CALL	CF_INIT
	CALL	SERIAL_INIT
	LD	A, 0
	CALL	SERIAL_WRITE	; Write a null to clear out the buffer
	
	LD	HL, STR_BANNER
	CALL	SERIAL_PUTS
	
	
	

	
CMD_LOOP:
	CALL 	DISP_PROMPT	; Display prompt + cur addr
	CALL	GET_LINE	; Read in user input
	CALL	PARSE_LINE	; Parse line and do actions
	JR	CMD_LOOP
	
	
HALT:	
	LD	A, 0x80
	OUT	(PORT_LCD), A
	JP	HALT
#endlocal

; A bunch of opcodes for testing the disassembler
DISTEST:
	LD	A, 0
	LD	B, 1
	LD	HL, $1234
	LD	IX, $5678
	LD	IY, $9ABC
	LD	A, (HL)
	LD	A, (IX+1)
	LD	A, (IY-$71)
	RR	(HL)
	RL	A
	LD	(HL), BC
	
	
	
	LD	(IY-$12), BC
	
	LD	(IX), DE
	
	INC	IX
	DEC	IY
	INC	IXL
	DEC	IXH
	LD	IXH, $21
	NOP
	NOP
	RR	(IX)	; DDCB prefix instruction
	RL	(IY)	; FDCB prefix instruction
	NOP
	NOP
	DB	$FD
	DB	$DD
	RETI
	OUT	(C), A
	IN	A, (C)
	DB	$ED,$70 ;0160 - IN (C)
	OUT	(C), 0
	LDI
	CPD
	INIR
	OTDR
TEST:
	SET 	5, (IX+$12), A	; DDCB illegal opcode
	RR 	(IY-$62), E	; FDCB legal? opcode
	BIT 	3, (IY+$7E)	; FDCB legal opcode
	DB	$DD,$CB,$00,$7B	; IX - prefix for BIT should be normal (BIT 7, E)
	NOP
	
	JR	TEST
	JP	PO, TEST
	JR	NC, TEST
;---------------------------------------
; Get a line of user input into LBUF
GET_LINE:
#local
	PUSH	BC
	LD	HL, LBUF
	LD	C, LBUFLEN
LINEL:
	CALL	KBD_GETKEY	; Get a character
	CALL	TO_UPPER	; Uppercase only

	LD	B, A		; Save charaacter
	
	CP	$08		; BKSP
	JR	NZ, NOBKSP
BKSP:
	LD	A, LBUFLEN
	CP	C	
	JR	Z, IGNORE	; Don't backspace if at beginning of line
	DEC	HL
	INC	C
	LD	A, B		; Restore character (BKSP)
	CALL	SERIAL_WRITE	
	LD	A, ' '
	CALL	SERIAL_WRITE	; Space
	LD	A, $08		; BKSP again 
	JR	NOSTORE
	
NOBKSP:	
	CP	$0A		; NEWLINE
	JR	Z, DONE		
	
	XOR	A		; Clear A
	CP	C		; Check if we have space to store
	JR	Z, IGNORE	; Ignore character if so
	
	LD	A, B		; Restore character
	LD	(HL), A		; Store into buffer
	INC	HL
	DEC	C
NOSTORE:
	CALL	SERIAL_WRITE	; Echo character back
IGNORE:
	JR	LINEL
DONE:	LD	A, $0D		; CR
	CALL	SERIAL_WRITE
	LD	A, $0A		; NL
	CALL	SERIAL_WRITE
	LD	(HL), 0		; Add trailing null terminator
	POP	BC
	RET
#endlocal





;---------------------------------------
; Parse line and handle commands
PARSE_LINE:
#local
	LD	HL, LBUF
	CALL 	SKIPWHITE	; Skip leading whitespace to be nice
	
	LD	IX, CMDTBL	
	LD	IY, CMDTBLJ	; Jump table
NEXTCMP:
	LD	A, (IX)		; Read in table entry
	CP	(HL)		; Compare with buffer character
	JR	Z, MATCH
	
	CP	0		; Check if end of table
	JR	Z, MATCH	; Match if end of table/invalid command
	
	INC	IX		; Next character
	INC 	IY		
	INC 	IY		; Next function
	JR	NEXTCMP
MATCH:
	LD	BC, (IY)
	PUSH	BC
	RET		; Jump into table, index into string in BC
#endlocal




;---------------------------------------
; Change current address 
CMD_CHADDR:
	INC	HL		; Skip over command
	CALL	SKIPWHITE	; Skip any whitespace
	CALL	PARSENUM	; Parse up to a 16-bit address
	LD	A, C
	LD	(CURADDR), A	;
	LD	A, B
	LD	(CURADDR+1), A	; Store address as current
	RET

;---------------------------------------
; Examine bytes of memory
;	E		- Enter interactive examine mode
;	E 8		- Examine 8 bytes from curaddr
CMD_EXAMINE:
#local
	INC	HL
	CALL	SKIPWHITE
	CALL	PARSENUM	; Check if we got a number
	JR	C, INTERACTIVE	; If no number, enter interactive mode
	
	; Count in BC
	LD	HL, (CURADDR)
	
MORE:
	; Check if BC > 16
	LD	A, B
	AND	A
	JR	NZ, ENOUGH
	LD	A, C
	AND	A
	JR	Z, DONE
	CP	HDROWL
	JR	C, SHORT
	
ENOUGH:
	; Subtract 16 from BC
	LD	A, -HDROWL
	ADD	C
	LD	C, A
	LD	A, $FF
	ADC	B		; Decrement B if no overflow happened
	LD	B, A
	
	LD	A, HDROWL
	CALL	HEXDUMPROW	; Dump row, HL is advanced by count
	JR	MORE		; Continue
SHORT:
	LD	A, C		; Last few bytes
	CALL	HEXDUMPROW
DONE:
	RET

	
	
INTERACTIVE:
	; TODO: Do we want this to be actually interactive?
	; For now just dump one line and advance CURADDR
	LD	HL, (CURADDR)
	LD	A, HDROWL
	CALL	HEXDUMPROW	; Dump row, HL is advanced by count
	LD	(CURADDR), HL
	RET
#endlocal

;--------
; Dump one row of memory, up to 'A' bytes
HEXDUMPROW:
#local
	PUSH 	BC
	PUSH	DE
	
	LD	E, A		; Save A
	
	LD	BC, HL
	CALL	PRINTWORD	; Address (BC preserved)
	
	LD	HL, STR_COLONSEP
	CALL	PRINT
	LD	HL, BC		; Restore address
	
	PUSH	HL		; Save inital addr
	; Byte values
	LD	B, E		; Count
BYTEL:
	LD	A, (HL)
	CALL	PRINTBYTE
	LD	A, ' '
	CALL	PRINTCH
	INC	HL
	DJNZ	BYTEL
	; Pad if short
	LD	A, HDROWL
	SUB	E
	LD	B, A
	JR	Z, NOPAD
PADB:
	LD	A, ' '
	CALL	PRINTCH
	CALL	PRINTCH
	CALL	PRINTCH
	DJNZ	PADB
NOPAD:
	
	; Printable ASCII
	LD	A, '|'
	CALL	PRINTCH
	LD	B, E
	POP	HL		; Restart address
ASCII:
	LD	A, (HL)
	INC	HL
	CP	127
	JR	NC, NOPRINT
	CP	32
	JR	NC, DOPRINT
NOPRINT:
	LD	A, '.'
DOPRINT:
	CALL	PRINTCH
	DJNZ	ASCII
	
	LD	A, '|'
	CALL	PRINTCH

	CALL	PRINTNL
	
	POP	DE
	POP	BC
	RET


#endlocal

;---------------------------------------
; Deposit bytes to memory
;	D		- Enter deposit mode at curaddr
CMD_DEPOSIT:
#local	
NEXTLINE:
	LD	HL, (CURADDR)
	LD	BC, HL
	CALL	PRINTWORD
	LD	HL, STR_COLONSEP
	CALL	PRINT


	CALL	GET_LINE	; Read in new line from user
	LD	HL, LBUF
	CALL	SKIPWHITE	; Skip any whitespace
	LD	A, (HL)	
	AND	A
	JR	Z, EXIT		; Exit on a blank line
LLOOP:
	; Otherwise start reading hex values and depositing
	CALL	HEX2BYTE
	JR	C, EXIT		; Stop on first bad byte
	
	LD	BC, HL
	LD	HL, (CURADDR)
	LD	(HL), A		; Store byte
	INC	HL
	LD	(CURADDR), HL
	LD	HL, BC
	
	CALL	SKIPWHITE
	LD	A, (HL)
	AND 	A
	JR	NZ, LLOOP
	JR	NEXTLINE	; Otherwise read another line in
EXIT:
	RET
#endlocal
	
	
;---------------------------------------
; Dissassemble memory
; 	X		- Disassemble 1 inst (TODO:Interactive dissassemble)
;	X 10		- Disassemble 10 instructions from curaddr
CMD_DISASS:
#local
	INC	HL		; Skip command
	CALL	SKIPWHITE
	LD	A, (HL)
	CP	0		; No more command
	JR	Z, DODIS	; Tail call, do one line
	
	CALL	PARSENUM
	JR	C, DODIS	; Any errors, just do one line
	LD	A, C		; Only care about low byte
	AND	A		; Test for 0
	RET	Z		; Don't disassemble any then
	
	LD	B, A
DISLOOP:
	PUSH	BC
	CALL	DODIS
	POP	BC
	DJNZ	DISLOOP
	
	RET

;--------
; Disassemble one instruction and print result
DODIS::
	; Test disassemble at curaddr
	LD	HL, (CURADDR)
	LD	BC, HL
	CALL	PRINTWORD
	LD	A, $09		; TAB
	CALL	PRINTCH
	
	CALL	DISINST
	LD	BC, (CURADDR)
	LD	(CURADDR), HL	; Next instruction
	
	; Determine number of bytes consumed (min 1, max 4)
	SCF
	CCF
	SBC	HL, BC		; L contains number of bytes consumed
	
	LD	A, L		; Number of bytes
	LD	HL, BC		; Old start addr
	LD	B, A		; Number of bytes
	LD	C, A		; Save copy in C
BYTES:
	LD	A, (HL)
	CALL	PRINTBYTE
	LD	A, ' '
	CALL	PRINTCH
	INC	HL
	DJNZ	BYTES
	; Pad out spaces
	LD	A, 5		; One extra since we're doing DJNZ
	SUB	C		; Number of remaining padding
	LD	B, A
	JR	PADTEST
PAD:
	LD	A, ' '
	CALL	PRINTCH
	CALL	PRINTCH
	CALL	PRINTCH
PADTEST:
	DJNZ	PAD
	LD	A, $09		; TAB
	CALL	PRINTCH
	
	; Print string
	LD	HL, DISLINE
	CALL	PRINTN

	RET
#endlocal




CMD_INVAL:
	RET
	
;---------------------------------------
; Jump to code in memory
;	R		- Call curaddr
; 	R 1E00		- Call $1E00
; 	
; Never returns, if code that's run returns, perform a restart
CMD_RUN:
#local
	INC	HL
	CALL	SKIPWHITE
	CALL	PARSENUM	; Check if we got a number
	JR	C, CUR		; If no number, run at current addr
	LD	HL, START	; Do a cold start if run returns
	PUSH	HL		; Return address
	PUSH	BC		; Address to jump to
	RET			; Jump to code
CUR:
	LD	HL, START	; Do a cold start if run returns
	PUSH	HL		; Return address
	LD	HL, (CURADDR)
	PUSH	HL		; Address to jump to
	RET
#endlocal


CMDTBL:
	DB '.'	; Change address
	DB 'E'	; Examine
	DB 'D'	; Deposit
	DB 'R'	; Run
	DB 'X'	; Disassemble
	DB 0	; End of table/invalid command
CMDTBLJ:
	DW CMD_CHADDR
	DW CMD_EXAMINE
	DW CMD_DEPOSIT
	DW CMD_RUN
	DW CMD_DISASS
	DW CMD_INVAL	; Invalid command


; Display the prompt
;  '$ABCD> '
DISP_PROMPT:
	LD	A, '$'
	CALL	PRINTCH		
	LD	BC, (CURADDR)
	CALL	PRINTWORD	; Print current address
	LD	HL, STR_PROMPTEND
	JP	PRINT		; Tail call
	

#include "lcd.asm"	; LCD Routines
#include "delay.asm"	; Delay/sleep routines
#include "cf.asm"	; CF card routines
#include "serial.asm"	; Serial routines
#include "kbd.asm"	; Keyboard routines
#include "int.asm"	; Interrupt routines
#include "parse.asm"	; String parsing routines
#include "print.asm"	; Console printing routines
#include "disass.asm"	; Dissassembler

	
;===============================================================================
;===============================================================================
; Constants
PORT_PIO	equ 0x00	; 8255 PIO
PORT_LCD	equ 0x40	; Shared with KBD in port (Write only)
PORT_KBD	equ 0x40	; Shared with LCD out port (Read only)
PORT_CF		equ 0xC0	; 8-bit IDE interface, CF cards only
PORT_BANK	equ 0xE0	; Bank switch register
; Bank switch:
;       abcdefgh        - abcd controls upper 32kB, efgh controls lower 32kB
;       | ||            - efgh acts the same as abcd
;       | |+------------- \ Bank select (4 banks of 32KB) 
;       | +-------------- / (ROM only has first 2)
;       |
;       +---------------- ROM = 0, RAM = 1
	
;---------------------------------------
; 8255 PIO registers	
PIO_A		equ	PORT_PIO+0
PIO_B		equ	PORT_PIO+1
PIO_C		equ	PORT_PIO+2
PIO_CTRL	equ	PORT_PIO+3

;---------------------------------------
; Compact flash card registers
CF_DATA		equ PORT_CF+0	; Accessing CF card data
CF_FEAT_ERR	equ PORT_CF+1	; Features(W)/Error(R) register
CF_COUNT	equ PORT_CF+2	; Sector count register
CF_LBA0		equ PORT_CF+3	; LBA bits 0-7
CF_LBA1		equ PORT_CF+4	; LBA bits 8-15
CF_LBA2		equ PORT_CF+5	; LBA bits 16-23
CF_LBA3		equ PORT_CF+6	; LBA bits 24-27 (Rest of bits here are 1 for LBA)
CF_CMD_STAT	equ PORT_CF+7	; Command(W)/Status(R)

;---------------------------------------
; 68681 DUART registers/ports
DUART		equ $80
SER_MRA		equ DUART+0	; Mode Register A           (R/W)
SER_SRA		equ DUART+1	; Status Register A         (R)
SER_CSRA 	equ DUART+1     ; Clock Select Register A   (W)
SER_CRA 	equ DUART+2     ; Commands Register A       (W)
SER_RBA 	equ DUART+3     ; Receiver Buffer A         (R)
SER_TBA 	equ DUART+3     ; Transmitter Buffer A      (W)
SER_ACR 	equ DUART+4     ; Aux. Control Register     (R/W)
SER_ISR 	equ DUART+5     ; Interrupt Status Register (R)
SER_IMR 	equ DUART+5     ; Interrupt Mask Register   (W)
SER_CTU		equ DUART+6	; Counter/Timer Upper Val 	(R/W)
SER_CTL		equ DUART+7	; Counter/Timer Lower Val 	(R/W)
SER_MRB 	equ DUART+8     ; Mode Register B           (R/W)
SER_SRB 	equ DUART+9     ; Status Register B         (R)
SER_CSRB 	equ DUART+9     ; Clock Select Register B   (W)
SER_CRB 	equ DUART+10    ; Commands Register B       (W)
SER_RBB 	equ DUART+11    ; Reciever Buffer B         (R)
SER_TBB 	equ DUART+11    ; Transmitter Buffer B      (W)
SER_IVR 	equ DUART+12 	; Interrupt Vector Register (R/W)
SER_IPR		equ DUART+13	; Input port register (R)
SER_OPR		equ DUART+13	; Output port register (W)

;---------------------------------------
; Delay constant for DELAY_MS
; Delay calculation:
;	35 + 65*(B-1) + 60 + 20 cycles
;	B  = (CYCLES - 115)/65 + 1
; 4000 cycles @4MHz, B = 60.7 + 1  = 62
; 8000 cycles @8MHz, B = 121.3 + 1 = 122
; 16000 cycles @16Mhz, B= 244.4 + 1 = 245

#if 	CPU_FREQ == 8000000
MSDELAY		equ 122
#elif 	CPU_FREQ == 4000000
MSDELAY		equ 62
#elif 	CPU_FREQ == 16000000
MSDELAY		equ 245
#else
MSDELAY		equ 255			; If CPU_FREQ unknown, be conservative
#endif


; 8 will fit exactly 40 characters as is, though would need newline supressed
; 16 is 72 characters wide, fits nicely on a 80 column display
HDROWL		equ 16			; Row length for hexdump 


;===============================================================================
;===============================================================================
; Static Data
STR_LCDBANNER:
	.ascii "Chartreuse Z80 Booted",0
	
STR_BANNER:
	.ascii "Chartreuse Z80 Monitor v0.1",10,13
	.ascii "========================================",10,13,0

STR_AFTDIS:
	.ascii "---DISDONE---",10,13,0
STR_NL:
	.ascii 10,13,0
STR_PROMPTEND:
	.ascii '> ',0
STR_COLONSEP:
	.ascii ': ',0

;===============================================================================
;===============================================================================
; Uninitialized Data in RAM
#data _RAM

LBA:		DS 4	; 4-byte (28-bit) little-endian LBA address for CF


LBUFLEN		equ 80
LBUF:		DS LBUFLEN+1	; Line buffer (space for null)

CURADDR:	DS 2	; Current address
