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
	
	
	LD	HL, DISTEST	
	LD	(CURADDR), HL
	;CALL	DISINST
	
	
	LD	B, 50
DLOOP:
	PUSH	BC
	CALL	CMD_DISASS
	POP	BC
	DJNZ	DLOOP
	
	
	LD	HL, STR_AFTDIS
	CALL	SERIAL_PUTS
	
	
	
;CMD_LOOP:
	;CALL 	DISP_PROMPT	; Display prompt + cur addr
	;CALL	GET_LINE	; Read in user input
	;CALL	PARSE_LINE	; Parse line and do actions
;	JR	CMD_LOOP
	
	
HALT:	
	LD	A, 0x80
	OUT	(PORT_LCD), A
	JP	HALT
#endlocal


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
	RR	(IX)	; DDCB prefix instruction, not yet implemented
	; Glitches out since order is DDCB.disp.op instead of DDCB.op.disp
	RL	(IY)	; FDCB prefix instruction, not yet implemented
	; Glitches out since order is FDCB.disp.op instead of FDCB.op.disp
	NOP
	NOP
	NOP
;---------------------------------------
; Get a line of user input into LBUF
GET_LINE:
#local
	LD	HL, LBUF
	LD	C, LBUFLEN
LINEL:
	CALL	SERIAL_READ	; Get a character
	CALL	TO_UPPER	; Uppercase only
	LD	B, A		; Save charaacter
	CP	$08		; BKSP
	JR	NZ, NOBKSP
	LD	A, LBUFLEN
	CP	C	
	JR	Z, NOBKSP	; Don't backspace if at beginning of line
	DEC	HL
	INC	C
	LD	A, B		; Restore character
	CALL	SERIAL_WRITE	; BKSP
	LD	A, ' '
	CALL	SERIAL_WRITE	; Space
	LD	A, $08		; BKSP again 
	JR	NOSTORE
NOBKSP:	CP	$0A		; NEWLINE
	JR	Z, DONE		
	XOR	A		; Compare with 0
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
DONE:
	LD	(HL), 0		; Add trailing null terminator
	RET
#endlocal


;---------------------------------------
; Convert character in A to uppercase if lowercase
TO_UPPER:
#local
	CP	'a'
	JR	C, NOCHG	; ch < 'a'
	CP	'z'+1		
	
	JR	NC, NOCHG	; ch > 'z'
	; 'a' <= ch <= 'z'
	SUB	$20		; 'a' - 'A' convert to uppercase
NOCHG:
	RET
#endlocal


;---------------------------------------
; Parse line and handle commands
PARSE_LINE:
#local
	LD	BC, LBUF
	CALL 	SKIPWHITE	; Skip leading whitespace to be nice
	
	LD	IX, CMDTBL	
	LD	HL, CMDTBLJ	; Jump table
NEXTCMP:
	LD	A, (HL)		; Check character
	CP	(IX)		; Compare with table
	JR	Z, MATCH
	
	LD	A, 0
	CP	(IX)		; Check for end of table
	JR	Z, MATCH	; Match if end of table/invalid command
	
	INC	IX		; Next character
	INC 	HL		
	INC 	HL		; Next function
	JR	NEXTCMP
MATCH:
	JP	(HL)		; Jump into table, index into string in BC
#endlocal

;---------------------------------------
; Increments HL till non-whitespace in (HL)
SKIPWHITE:
#local
	LD	A, (HL)
	CALL	ISWHITE
	JR	NZ, END
	INC	HL
	JR	SKIPWHITE
END:
	RET
#endlocal

;---------------------------------------
; Is character in A whitespace? Sets Z if so
ISWHITE:
#local
	CP	' '		; Space
	JR	Z, END
	CP	$09		; TAB
	JR	Z, END
	CP	$0B		; Vert Tab
	JR	Z, END
	CP	$0C		; Form Feed
END:	
	RET
	
#endlocal


;---------------------------------------
; Change current address 
CMD_CHADDR:
	LD	HL, BC		; Transfer index
	INC	HL		; Skip over command
	CALL	SKIPWHITE	; Skip any whitespace
	;CALL	PARSEADDR	; Parse up to 2 byte address
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
	RET

;---------------------------------------
; Deposit bytes to memory
;	D		- Enter deposit mode at curaddr
CMD_DEPOSIT:
	RET
	
;---------------------------------------
; Dissassemble memory
; 	X		- Interactive dissassemble
;	X 10		- Disassemble 10 instructions from curaddr
CMD_DISASS:
	; Test disassemble at curaddr
	LD	HL, (CURADDR)
	CALL	DISINST
	LD	(CURADDR), HL	; Next instruction
	; Print string
	LD	HL, DISLINE
	CALL	SERIAL_PUTS
	CALL	SERIAL_NL
	RET
	
CMD_INVAL:
	RET
	
;---------------------------------------
; Jump to code in memory
;	R		- Call curaddr
; 	R 1E00		- Call $1E00
CMD_RUN:
	RET

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

#include "lcd.asm"	; LCD Routines
#include "delay.asm"	; Delay/sleep routines
#include "cf.asm"	; CF card routines
#include "serial.asm"	; Serial routines
#include "kbd.asm"	; Keyboard routines
#include "int.asm"	; Interrupt routines
#include "disass.asm"	

	
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

;===============================================================================
;===============================================================================
; Uninitialized Data in RAM
#data _RAM

LBA:		DS 4	; 4-byte (28-bit) little-endian LBA address for CF
LAST_KEY:	DS 1	; Last pressed key

LBUFLEN		equ 80
LBUF:		DS LBUFLEN+1	; Line buffer (space for null)

CURADDR:	DS 2	; Current address
