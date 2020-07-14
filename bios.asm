; To support the BIOS, the bank in the low 32kb must contain the BIOS entry code during the reset handlers
; this code goes from 0-0x100. The code will swap banks back to Monitor ROM+RAM, and enter the BIOS handler
;
; Programs MUST use BIOS to change banks, otherwise BIOS will break. This is because we can't read the 
; current bank setup from the hardware.
;

#data _RAM
CURBANK		DS	1	; Programs current bank switching. Programs MUST use BIOS to change banks
OLDSP		DS	2	; Save the programs stack
BIOSSTKBTM	DS	32*2	; BIOS's stack
BIOSSTK:
ARG0		DS	1	; 8-bit arg - B
ARG1		DS	2	; 16-bit arg - HL
ARG2		DS	2	; 16-bit arg - DE
RETCODE		DS	1 	; Program return code
BIOS_FS		DS	FSLEN	; User FS is copied into here when performing FS operations
NAMEBUF		DS	13	; 8.3 + NULL
#code _ROM

;---------------------------------------
BIOSTBL:
	DW	B_PUTCH		; 0  - Put character [in B]
	DW	B_PUTS		; 1  - Put string (null terminated) [addr in HL]
	DW	B_GETCH		; 2  - Get character, block till available  [ret in B]
	DW	B_GETCHNB	; 3  - Get character, return 0 if none available [ret in B]
	DW	B_CPOS		; 4  - Set cursor position. [X in H, Y in L]
	DW	B_GETLINE	; 5  - Get a line of user input [addr in HL, max length in B]
	DW	B_CLRSCR	; 6  - Clear screen, home cursor
	DW	B_BANKSW	; 7  - Bank switch, [Change to bank configuration in B]
	DW	B_DLINEMOD	; 8  - Set display line mode [in B]
	DW	B_DISPWRITE	; 9  - Write raw character to display, unescaped [in B]
	DW	B_PUTPX		; 10 - Put pixel [X in H, Y in L, set/reset in B]
	DW	B_EXIT		; 11 - Exit program to monitor [return code in B]
	DW	B_DELAY		; 12 - Delay for [HL] milliseconds
	; File calls
	DW	B_OPEN		; 13 - Open file [pointer to FS in HL]
	DW	B_CLOSE		; 14 - Close file [pointer to FS in HL]
	; Data MUST NOT CROSS PAGE BOUNDARY
	DW	B_READ		; 15 - Read sector from file [pointer to FS in HL, data target in DE]
	DW	B_WRITE		; 16 - Write sector to file [pointer to FS in HL, data source in DE]
	DW	B_REWIND	; 17 - Rewind file to start [pointer to FS in HL]
	DW	B_CREATE	; 18 - Create a file [pointer to FS in HL]
	DW	B_DELETE	; 19 - Delete a file [pointer to FS in HL]
	DW	B_SETNAME	; 20 - Set file name in FS [pointer to FS in HL, pointer to null term string in DE]
BIOS_MAXCALL	equ ((.-BIOSTBL)/2)
;---------------------------------------

;---------------------------------------
; BIOS Entry Point
; We've already reset the banks back to the Monitor's ROM+RAM setup
; during the RST handler code. 
; A cannot be used as an argument since we corrupt it during bank switching
; Arguments are:
;  C - BIOS Call #
;  B - 8-bit arg
;  HL - 16-bit arg/addr
;  DE - extra 16-bit arg
BIOS:
	LD	A, B
	LD	(ARG0), A	; Save 8-bit arg
	LD	(ARG1), HL	; 16-bit arg
	LD	(ARG2), DE	; 2nd 16-bit arg

	LD	(OLDSP), SP	; Save programs stack pointer
	LD	SP, BIOSSTK	; Use our stack
	
	LD	A, C
	CP	BIOS_MAXCALL	; Check if beyond the max call
	JR	NC, BIOSEXIT	; If beyond then ignore the call
	
	; Set-up for jump into table
	LD	HL, BIOSTBL
	LD	B, 0		; Clear upper of BIOS Call #
	ADD	HL, BC
	ADD	HL, BC		; 2 times call # to get index
	; HL now points to an address to call
	LD	DE, (HL)	; Read in address
	EX	DE, HL		; Get address in HL
	LD	DE, BIOSEXIT
	PUSH	DE		; Push a return address for us
	JP	(HL)		; Jump to BIOS function
BIOSEXIT:
	; 
	LD	SP, (OLDSP)	; Restore stack
	JP	BIOSRET		; Return and bankswitch back to program
;---------------------------------------


	
;---------------------------------------
; 0 - Put character [in ARG0]
B_PUTCH:
	LD	A, (ARG0)
	CALL	PRINTCH
	RET
	
;---------------------------------------
; 1 - Put string (null terminated) [addr in ARG1]
B_PUTS:
#local
	LD	HL, (ARG1)	; String to print
LOOP:
	LD	A, (CURBANK)
	LD	B, A
	CALL	RAM_BANKPEEK	; Steal a byte from userspace
	LD	A, C		; Move byte
	AND	A
	JR	Z, DONE
	CALL	PRINTCH
	INC	HL		; Next char
	JR	LOOP
	
DONE:
	RET
#endlocal	
;---------------------------------------
; 2 - Get character, block till available
B_GETCH:
	CALL	KBD_GETKEY
	LD	B, A		; Return value in B
	RET

;---------------------------------------
; 3 - Get character, return 0 if none available [ret in B]
B_GETCHNB:
	CALL	KBD_GETKEYNB
	LD	B, A		; Return value in B
	RET
	
;---------------------------------------
; 4 - Set cursor position. [X in H, Y in L]
B_CPOS:
	LD	A, $0E		; Set column
	CALL	DISP_WRITE
	LD	A, H		; column #
	CALL	DISP_WRITE
	LD	A, $0F		; Set row
	CALL	DISP_WRITE
	LD	A, L		; Row #
	CALL	DISP_WRITE
	RET
	
;---------------------------------------
; 5 - Get a line of user input [addr in HL, max length in B]
B_GETLINE:
#local
	LD	HL, (ARG1)
	LD	A, (ARG0)
	LD	C, A
LINEL:
	CALL	KBD_GETKEY	; Get a character

	LD	B, A		; Save charaacter
	
	CP	$08		; BKSP
	JR	NZ, NOBKSP
BKSP:
	LD	A, (ARG0)
	CP	C	
	JR	Z, IGNORE	; Don't backspace if at beginning of line
	DEC	HL
	INC	C
	LD	A, B		; Restore character (BKSP)
	CALL	PRINTCH	
	LD	A, ' '
	CALL	PRINTCH		; Space
	LD	A, $08		; BKSP again 
	JR	NOSTORE
NOBKSP:	
	CP	$0A		; NEWLINE
	JR	Z, DONE		
	
	XOR	A		; Clear A
	CP	C		; Check if we have space to store
	JR	Z, IGNORE	; Ignore character if so
	
	PUSH	BC
	LD	A, (CURBANK)
	LD	C, B		; Restore character
	LD	B, A		; Bank
	CALL	RAM_BANKPOKE	; Write character
	POP	BC
	LD	A, B		; Restore character
	
	INC	HL
	DEC	C
NOSTORE:
	
	CALL	PRINTCH		; Echo character back
IGNORE:
	JR	LINEL
DONE:	LD	A, $0D		; CR
	CALL	PRINTCH
	LD	A, $0A		; NL
	CALL	PRINTCH
	
	LD	A, (CURBANK)
	LD	C, 0		; Add trailing null terminator
	LD	B, A		; Bank
	CALL	RAM_BANKPOKE	; Write character
	
	RET
#endlocal
	
;---------------------------------------
; 6 - Clear screen, home cursor
B_CLRSCR:
	LD	A, $0C		; Clear screen
	CALL	DISP_WRITE
	LD	A, $01		; Home cursor (just in case)
	CALL	DISP_WRITE
	RET
	
;---------------------------------------
; 7 - Bank switch, [Change to bank configuration in ARG0]
B_BANKSW:
	LD	A, (ARG0)
	LD	(CURBANK), A	; Change calling bank, BIOSRET will swap for us
	RET


;---------------------------------------
; 8 - Set display line mode [in ARG0]
B_DLINEMOD:
	LD	A, $18		; Set line mode
	CALL	DISP_WRITE
	LD	A, (ARG0)
	CALL	DISP_WRITE
	RET

;---------------------------------------
; 9 - Write raw character to display, escaped [in ARG0]
B_DISPWRITE:
	LD	A, (ARG0)
	CALL	DISP_WRITE_ESC
	RET
	
;---------------------------------------
; 10 - Put pixel [X in H, Y in L, set/reset in B]
B_PUTPX:
#local
	LD	A, (ARG0)
	AND	A		; Check if we're to SET or clear
	LD	A, $05		; Clear
	JR	Z, DOPUT
	LD	A, $06		; Set
DOPUT:
	CALL	DISP_WRITE
	LD	A, (ARG1+1)	; H argument
	CALL	DISP_WRITE
	LD	A, (ARG1+0)	; L argument
	CALL	DISP_WRITE
	RET
#endlocal
	
;---------------------------------------
; 11 - Exit program to monitor [return code in B]
B_EXIT:
#local
	LD	A, (ARG0)
	LD	(RETCODE), A	; Copy return code
	LD	A, MONITOR_BANK	; Monitor Bank
	LD	(CURBANK), A	; Reset CURBANK
	JP	WARM		; Warm restart, will take care of stack
#endlocal

;---------------------------------------
; 12 - Delay for ARG1 milliseconds
B_DELAY:
#local
	LD	BC, (ARG1)
	CALL	DELAY
	RET
#endlocal


; Copy userspace FS (in ARG1) to BIOS FS
FS_USER_BIOS:
#local
	LD	IX, BIOS_FS
	LD	HL, (ARG1)
	LD	B, FSLEN
LOOP:
	PUSH	HL
	PUSH	BC
	 LD	A, (CURBANK)
	 LD	B, A
	 CALL	RAM_BANKPEEK
	 LD	(IX), C
	POP	BC
	POP	HL
	INC	HL
	INC	IX
	DJNZ	LOOP
	RET
#endlocal

; Copy  BIOS FS to userspace FS (in ARG1)
FS_BIOS_USER:
#local
	LD	IX, BIOS_FS
	LD	HL, (ARG1)
	LD	B, FSLEN
LOOP:
	PUSH	HL
	PUSH	BC
	 LD	A, (CURBANK)
	 LD	B, A
	 LD	C, (IX)
	 CALL	RAM_BANKPOKE
	POP	BC
	POP	HL
	INC	HL
	INC	IX
	DJNZ	LOOP
	RET
#endlocal


;---------------------------------------
; 13 - Open file [pointer to FS in ARG1]
B_OPEN:
#local
	CALL	FS_USER_BIOS
	
	LD	HL, BIOS_FS
	CALL	FS_OPEN
	LD	B, 0			; Return value
	JR	NC, SUCCESS
	INC	B			; 1 indicates failure
SUCCESS:
	PUSH	BC
	CALL	FS_BIOS_USER
	POP	BC
	RET
#endlocal
;---------------------------------------
; 14 - Close file [pointer to FS in ARG1]
B_CLOSE:
#local
	CALL	FS_USER_BIOS
	
	LD	HL, BIOS_FS
	CALL	FS_CLOSE
	LD	B, 0			; Return value
	JR	NC, SUCCESS
	INC	B			; 1 indicates failure
SUCCESS:
	PUSH	BC
	CALL	FS_BIOS_USER
	POP	BC
	RET
#endlocal
;---------------------------------------
; 15 - Read sector from file [pointer to FS in ARG1, data target in ARG2]
B_READ:
#local
	CALL	FS_USER_BIOS
	
	LD	IX, BIOS_FS
	
	LD	HL, (ARG2)
	LD	A, (CURBANK)
	LD	C, A
	CALL	NORMAL_ADDR
	
	CALL	FS_READ
	; Read also returns A=0 for EOF with carry set, or A=FF for error
	LD	B, 0			; Return value
	JR	NC, SUCCESS
	LD	B, A			; 
	INC	B \ INC B		; 1 indicates error, 2 indicates EOF
SUCCESS:
	PUSH	BC
	CALL	FS_BIOS_USER
	POP	BC
	RET
#endlocal
;---------------------------------------
; 16 - Write sector to file [pointer to FS in ARG1, data source in ARG2]
B_WRITE:
#local
	CALL	FS_USER_BIOS
	
	LD	IX, BIOS_FS
	
	LD	HL, (ARG2)
	LD	A, (CURBANK)
	LD	C, A
	CALL	NORMAL_ADDR
	
	CALL	FS_WRITE
	; Read also returns A=0 for out of space with carry set, or A=FF for error
	LD	B, 0			; Return value
	JR	NC, SUCCESS
	LD	B, A			; 
	INC	B \ INC B		; 1 indicates error, 2 indicates out of space
SUCCESS:
	PUSH	BC
	CALL	FS_BIOS_USER
	POP	BC
	RET
#endlocal
;---------------------------------------
; 17 - Rewind file to start [pointer to FS in ARG1]
B_REWIND:
#local
	CALL	FS_USER_BIOS
	
	LD	HL, BIOS_FS
	CALL	FS_REWIND
	LD	B, 0			; Return value
	JR	NC, SUCCESS
	INC	B			; 1 indicates failure
SUCCESS:
	PUSH	BC
	CALL	FS_BIOS_USER
	POP	BC
	RET
#endlocal
;---------------------------------------
; 18 - Create a file [pointer to FS in ARG1]
B_CREATE:
#local
	CALL	FS_USER_BIOS
	
	LD	HL, BIOS_FS

	CALL	FS_CREATE
	LD	B, 0			; Return value
	JR	NC, SUCCESS
	INC	B			; 1 indicates failure
SUCCESS:
	PUSH	BC
	CALL	FS_BIOS_USER
	POP	BC
	RET
#endlocal
;---------------------------------------
; 19 - Delete a file [pointer to FS in ARG1]
B_DELETE:
#local
	CALL	FS_USER_BIOS
	
	LD	HL, BIOS_FS
	CALL	FS_DELETE
	LD	B, 0			; Return value
	JR	NC, SUCCESS
	INC	B			; 1 indicates failure
SUCCESS:
	PUSH	BC
	CALL	FS_BIOS_USER
	POP	BC
	RET
#endlocal
;---------------------------------------
; 20 - Set file name in FS [pointer to FS in ARG1, pointer to null term string in ARG2]
B_SETNAME:
#local
	; Copy name from userspace
	LD	HL, (ARG2)
	LD	DE, NAMEBUF
	LD	B, 12
CNAME:
	PUSH	BC
	PUSH	HL
	LD	A, (CURBANK)
	LD	B, A
	CALL	RAM_BANKPEEK
	LD	A, C
	POP	HL
	POP	BC
	LD	(DE), A
	
	INC	DE
	INC	HL
	DJNZ	CNAME
	XOR	A
	LD	(DE), A			; Force null terminate
	
	CALL	FS_USER_BIOS
	
	LD	HL, NAMEBUF
	CALL	PRINTN
	
	LD	DE, BIOS_FS
	LD	HL, NAMEBUF
	CALL	FS_SETFILENAME
	LD	B, 0			; Return value
	JR	NC, SUCCESS
	INC	B			; 1 indicates failure
SUCCESS:
	PUSH	BC
	CALL	FS_BIOS_USER
	POP	BC
	RET
#endlocal


