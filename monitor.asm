; 
;-------------------------------------------------------------------------------
; Writen for zasm assembler:
;  https://k1.spdns.de/Develop/Projects/zasm/Distributions/
#target rom

CPU_FREQ	equ		8000000		; 8MHz (4000000 = 4MHz)

; OLDROM: 0x80 Map 1st page of ram to high 32kB, ROM bank 0 to low
; NEWROM: 0xA0 Bank 2 to high 32kB, ROM Bank 0 to low
; OLD: 0x8B Map 1st page of ram to high 32kB, RAM Bank 3 to low (ROM emulation loader)
; 0xAB RAM Bank 2 to high 32kB, RAM Bank 3 to low (ROM emulation loader)
; (RAM BANK 0 and RAM BANK 1 for use of program
MONITOR_BANK	equ		0xAB		; NEWROM + emu loader

#data _RAM,0xF800,0x800		; Limit to top 2kB of RAM
; Space for BANKCOPY in memory
RAM_BANKCOPY	DS	BANKCOPYLEN
RAM_BANKPEEK	DS	BANKPEEKLEN
RAM_BANKPOKE	DS	BANKPOKELEN

MON_FS		DS	FSLEN	; FS stuct for monitor use

.align 2
#code _ROM,0x0000,0x8000	
#include "macros.asm"	; Assembler macros
;===============================================================================
;===============================================================================
; Reset Vectors
RESET:
	LD	A, MONITOR_BANK	; Monitor bank setup
	OUT	(PORT_BANK), A	; Bank switch
	JP	START
	
	; !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
	; This code must be preset in every bank that is to be loaded in the low slot
	ORG	0x08		; RST $08 -- BIOS call
	LD	A, MONITOR_BANK	; Load monitor bank setup
	OUT	(PORT_BANK), A	; Bank switch
	; We're now in the monitor ROM
	JP	BIOS
BIOSRET:
	LD	A, (CURBANK)	; DON't CALL RST $10, it's the first byte of address CURBANK
	OUT	(PORT_BANK), A
	RET		
BIOSSTART:	
	LD	A, (CURBANK)	; DON't CALL RST $18
	OUT	(PORT_BANK), A
	JP	0x0100			
	
	; !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
	ORG	0x20		; RST $20
	JP	START
	ORG	0x28		; RST $28
	JP	START
	ORG	0x30		; RST $30
	JP	START
	ORG	0x38		; RST $38 / Int vector
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
	LD	A, MONITOR_BANK		
	OUT	(PORT_BANK), A

	LD	SP, 0x0000	; Set stack to top of RAM
	
	; Init 8255
	LD	A, 0xC1		; Mode 2 on Port A (and ctrl on port C), C (low) input
				; Port B mode 0 output
	OUT	(PIO_CTRL), A
	
	LD	A, 0
	OUT	(PIO_B),A	; Clear port B

	; Clear RAM (0x8000-0xFFFF) before we use the stack
;	LD	HL, 0x8000
;	LD	B, 0
;CLRMEM:	LD	(HL), B
;	INC	HL
;	LD	A, H
;	OR	L
;	JR	NZ, CLRMEM	; Clear till 0xFFFF
	
	;CALL	LCDINIT
	
	LD	HL, STR_LCDBANNER
	;CALL	LCDPUTS
	
	CALL	DELAY_MS
	
	NOP	; Required before CF_INIT otherwise will fail! (Why?!)
	NOP
	CALL	CF_INIT
	CALL	SERIAL_INIT
	LD	A, 0
	CALL	SERIAL_WRITE	; Write a null to clear out the buffer
	
	CALL	DELAY_MS
	
	CALL	DISP_INIT
	
	LD	A, 0x81		; 80 col graphics
	CALL	DISP_LMODE
	
	LD	B, 80*3		; 3 lines of graphic data
	LD	HL, STR_GRAPHIC_BANNER
GRAPHBNR:
	LD	A,(HL)
	CALL	DISP_WRITE_ESC
	INC	HL
	DJNZ	GRAPHBNR
	
	LD	A, 0x03		; 80 col bold
	;LD	A, 0x02		; 40 col bold
	CALL	DISP_LMODE
	
	
	
	
	LD	HL, STR_BANNER
	CALL	PRINT
	
	; Copy bank  code into memory
	LD	HL, BANKCOPY
	LD	DE, RAM_BANKCOPY
	LD	BC, BANKCOPYLEN+BANKPEEKLEN+BANKPOKELEN
	LDIR
	
	CALL	CF_DETECT
	
	
	JR	NZ, DRVPRES
	LD	HL, STR_NODRIVE
	CALL	PRINTN
	
	JR	CMD_LOOP
DRVPRES:
	LD	HL, STR_DRIVE
	CALL	PRINTN
	CALL	FAT_INIT
	

	
WARM::
	LD	SP, 0x0000	; Reset stack on warm restart
	CALL	PRINTNL
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
	CALL	PRINTCH	
	LD	A, ' '
	CALL	PRINTCH	; Space
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
	CALL	PRINTCH	; Echo character back
IGNORE:
	JR	LINEL
DONE:	LD	A, $0D		; CR
	CALL	PRINTCH
	LD	A, $0A		; NL
	CALL	PRINTCH
	LD	(HL), 0		; Add trailing null terminator
	POP	BC
	RET
#endlocal



;-----------------------------------------------------------------------
; Parse line and handle commands
;-----------------------------------------------------------------------
; DM "TIME",0 \ DW CMD_TIME	; Time
PARSE_LINE:
#local
	LD	HL, LBUF
	CALL 	SKIPWHITE	; Skip leading whitespace to be nice
	LD	IX, CMDSTBL
LOOP:
	PUSH	HL		; Save start of user str
	LD	A, (IX)		; Check if at end of table
	AND	A
	JR	Z, NOMATCH	; End of table, no match found
CMP:
	LD	A, (IX)
	AND	A
	JR	Z, MATCH	; End of string in table, matched
	CP	(HL)
	INC	IX \ INC HL
	JR	Z, CMP		; While we match continue comparing
	; String doesn't match, advance to next entry
ADVLOOP:
	LD	A, (IX)
	INC	IX
	AND	A
	JR	NZ, ADVLOOP	; Advance to null terminator
	INC	IX \ INC IX	; Skip over address
	POP	HL		; Restore start of user string
	JR	LOOP		; Keep looping
MATCH:	; Commands matched and we're on the null terminator of the cmd
NOMATCH:; And the user string is pointing just after the matched string
	POP	BC		; Trash saved HL
	DEC	HL		; We're pointed one too far
	INC	IX		; Pointing at address of command
	LD	BC, (IX)	; Command to run
	PUSH	BC		; Push into return address
	RET		; Jump into table, index into string in BC

#endlocal
;-----------------------------------------------------------------------









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
#include "fatv3.asm"	; FAT filesystem and user filesystem commands
#include "util.asm"	; Utility functions
#include "math.asm"	; Math helper routines
#include "display.asm"	; AVR NTSC display routines
#include "bios.asm"	; BIOS call routines for userspace
#include "teensy.asm"	; Commands to talk with the Teensy peripheral
#include "commands.asm" ; Monitor interactive commands

;===============================================================================
;===============================================================================
; Constants
PORT_PIO	equ 0x00	; 8255 PIO (Teensy and display (atmega))
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
SER_ACR 	equ DUART+4     ; Aux. Control Register     (W)
SER_IPCR 	equ DUART+4     ; Input Port Change Register(R)
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
	.ascii "Chartreuse Z80 Monitor v0.3.4",10,13
	.ascii "========================================",10,13,0

STR_NL:
	.ascii 10,13,0
STR_PROMPTEND:
	.ascii '> ',0
STR_COLONSEP:
	.ascii ': ',0
	
STR_NODRIVE:
	.ascii "No IDE drive detected",0
STR_DRIVE:
	.ascii "IDE drive detected",0
STR_VOLLBL:
	.ascii "Volume Label: ",0
STR_VOLID:
	.ascii "Volume ID: ",0
STR_NOFILE:
	.ascii "No such file",0
STR_NOPROG:
	.ascii "No such program",0
STR_PREJUMP:
	.ascii "Long Jumping to program.",0
STR_HOSTFAIL:
	.ascii "Host failure while loading",0
STR_CHKFAIL:
	.ascii "Checksum failure",0

; 3 lines of 80 columns (240b) of graphics mode data
STR_GRAPHIC_BANNER:
	DB $00,$00,$00,$00,$00,$00,$00,$00,$fa,$e4,$40,$00,$00,$00,$00,$00 
	DB $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00 
	DB $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00 
	DB $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00 
	DB $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00 
	DB $80,$10,$e0,$84,$78,$04,$e0,$fe,$ff,$55,$00,$00,$a0,$0c,$10,$54 
	DB $a8,$a0,$0c,$50,$58,$a4,$08,$5c,$a0,$0c,$50,$58,$0c,$a8,$00,$54 
	DB $58,$0c,$a0,$0c,$04,$00,$08,$8c,$14,$98,$64,$a0,$0c,$50,$22,$66 
	DB $66,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00 
	DB $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00 
	DB $02,$2d,$9b,$f6,$e4,$be,$ff,$c7,$40,$2b,$d0,$00,$0a,$30,$04,$17 
	DB $2b,$2a,$03,$15,$17,$25,$00,$15,$2a,$0b,$10,$27,$31,$0a,$30,$05 
	DB $32,$19,$0a,$33,$10,$00,$28,$31,$10,$25,$1a,$0a,$30,$05,$22,$26 
	DB $26,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00 
	DB $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
	
;---------------------------------------
; DO NOT DIRECTLY USE, USE RAM_BANKCOPY
; Copy data from monitor bank to other bank
;
; A - target bank (Only LOW 4 bits matter)
; BC - # of bytes to copy (Must be < (32kB - DE)
; HL - This addr	(should be in high bank)
; DE - Destination addr (assuming destination is in low bank)
;;
;
; If HL is in low bank, and DE is in high bank, then this should
; work as a copy from banked memory to kernel memory
BANKCOPY:
	.phase	RAM_BANKCOPY
	AND	$0F		; Make sure bank doesn't contain data for upper
	OR	$A0		; Make sure upper contains our MONITOR RAM address
	
	
	OUT	(PORT_BANK), A	; Bank Switch! 
	; Now perform the copy
	LDIR
	LD	A, MONITOR_BANK	; Swap back to monitor configuration
	OUT	(PORT_BANK), A	; Bank switch!
	RET
BANKCOPYLEN	equ .-RAM_BANKCOPY
	.dephase
	
;---------------------------------------
; DO NOT DIRECTLY USE, USE RAM_BANKPEEK
; Read a byte at an address in the specified bank
; B - target bank (Both bits matter, if HL >= 0x8000 then we'll use the upper bits)
; HL - target address
; Byte in C
BANKPEEK:
#local
	.phase RAM_BANKPEEK
	LD	A, H		; Check high byte of address
	AND 	$80		; Check if we want the upper bank
	JR	Z, LOWER	; High bit not set, use lower bank
	; Addr is in the upper bank
	LD	A, H
	AND	$7F		; Change address to lower
	LD	H, A
	LD	A, B
	RRA
	RRA
	RRA
	RRA			; Move desired bank to low 4 bits
	LD	B, A
LOWER:
	LD	A, B
	AND	$0F
	OR	$A0		; Or with Monitor RAM bank (we're here!)
	OUT	(PORT_BANK), A	; Bank Switch! 
	LD	A, (HL)		; Read byte
	LD	C, A		; Save in C
	LD	A, MONITOR_BANK	; Swap back to Monitors bank setup
	OUT	(PORT_BANK), A	; Bank Switch! 
	RET
#endlocal
BANKPEEKLEN	equ .-RAM_BANKPEEK
	.dephase
	
;---------------------------------------
; DO NOT DIRECTLY USE, USE RAM_BANKPOKE
; Write a byte at an address in the specified bank
; B - target bank (Both bits matter, if HL >= 0x8000 then we'll use the upper bits)
; HL - target address
; C - byte to write
BANKPOKE:
#local
	.phase RAM_BANKPOKE
	PUSH	HL
	LD	A, H
	AND 	$80		; Check if we want the upper bank
	JR	Z, LOWER
	; Addr is in the upper bank
	LD	A, H
	AND	$7F		; Change address to lower
	LD	H, A
	LD	A, B
	RRA
	RRA
	RRA
	RRA			; Move desired bank to low 4 bits
	LD	B, A
LOWER:
	LD	A, B
	AND	$0F
	OR	$A0		; Or with Monitor RAM bank (we're here!)
	OUT	(PORT_BANK), A	; Bank Switch! 
	LD	(HL), C		; Write byte to memory
	LD	A, MONITOR_BANK	; Swap back to Monitors bank setup
	OUT	(PORT_BANK), A	; Bank Switch! 
	POP	HL
	RET
#endlocal
BANKPOKELEN	equ .-RAM_BANKPOKE
	.dephase
	
;===============================================================================
;===============================================================================
; Uninitialized Data in RAM
#data _RAM


DISPDEV:	DS 1	; Current display device
INDEV:		DS 1	; Current input device
LBUFLEN		equ 80
LBUF:		DS LBUFLEN+1	; Line buffer (space for null)

CURADDR:	DS 2	; Current address
