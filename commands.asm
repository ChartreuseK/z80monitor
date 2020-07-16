;-----------------------------------------------------------------------
; Monitor interactive command line commands
;-----------------------------------------------------------------------
#local	; Avoid polluting namespace

#data _RAM

CMDARGS:: DW 0 				; Pointer to command line arguments

#code _ROM


; Long string commands table
; Commands which are prefixes of others must come last
; Longest match must be tested first
CMDSTBL::
	DM ".",0 \ DW CMD_CHADDR	; Change address
	DM "?",0 \ DW CMD_HELP		; Help
	DM "DEL",0 \ DW CMD_TEMP_DFILE	; Delete file
	DM "DIR",0 \ DW CMD_LIST	; List root directory
	DM "DIS",0 \ DW CMD_DISASS	; Disassemble
	DM "DL",0 \ DW CMD_PROGRAM	; Disk load
	DM "D",0 \ DW CMD_DEPOSIT	; Deposit
	DM "E",0 \ DW CMD_EXAMINE	; Examine
	DM "GO",0 \ DW CMD_RUN		; Run (goto address)
	DM "HELP",0 \ DW CMD_HELP
	DM "NEW",0 \ DW CMD_TEMP_CFILE	; Create new file
	DM "PL",0 \ DW CMD_PC_LOAD	; PC load
	DM "READ",0 \ DW CMD_COPYFILE	; Read file into memory
	DM "TIME",0 \ DW CMD_TIME	; Time
	DB 0 \ DW CMD_INVAL		; Invalid command (catchall)


STR_HELP:
	.ascii "Current address is shown in prompt.",10,13
	.ascii "Addresses and numbers are hexadecimal",10,13
	.ascii ".       - Change current address",10,13
	.ascii "?       - Display this help screen",10,13
	.ascii "DEL fn  - Delete file fn",10,13
	.ascii "DIR     - List directory on CF card",10,13
	.ascii "DIS [n] - Disassembly n instructions",10,13
	.ascii "DL fn   - Load fn from disk and run",10,13
	.ascii "D       - Enter deposit mode",10,13
	.ascii "E [n]   - Examine n bytes ",10,13
	.ascii "GO [a]  - Execute at addr a or current",10,13
	.ascii "HELP    - Display this help screen",10,13
	.ascii "NEW fn  - Create a new empty file fn",10,13
	.ascii "PL fn   - Load fn from PC and run",10,13
	.ascii "READ fn - Read file fn into memory",10,13
	.ascii "TIME    - Displays the current time",10,13
	db 0



;-----------------------------------------------------------------------
; Change current address 
;-----------------------------------------------------------------------
CMD_CHADDR:
	INC	HL		; Skip over command
	CALL	SKIPWHITE	; Skip any whitespace
	CALL	PARSENUM	; Parse up to a 16-bit address
	LD	A, C
	LD	(CURADDR), A	;
	LD	A, B
	LD	(CURADDR+1), A	; Store address as current
	RET
;-----------------------------------------------------------------------


;-----------------------------------------------------------------------
; Examine bytes of memory
;	E		- Enter interactive examine mode
;	E 8		- Examine 8 bytes from curaddr
;-----------------------------------------------------------------------
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
	JR	NZ, ENOUGH	; > 256 no issue
	LD	A, C
	AND	A
	JR	Z, DONE		; 0 left, we're done
	
	LD	A, (HDROWL)
	LD	E, A
	LD	A, C
	CP	E
	
	JR	C, SHORT
	
ENOUGH:
	; Subtract 16 from BC
	LD	A, (HDROWL)
	LD	E, A
	
	LD	A, C
	SUB	E
	LD	C, A
	LD	A, B
	SBC	0
	LD	B, A
	
	
	LD	A, (HDROWL)
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
	LD	A, (HDROWL)
	CALL	HEXDUMPROW	; Dump row, HL is advanced by count
	LD	(CURADDR), HL
	RET
#endlocal
;-----------------------------------------------------------------------


;-----------------------------------------------------------------------
; Dump one row of memory, up to 'A' bytes
;-----------------------------------------------------------------------
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
	LD	A, (HDROWL)
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
	LD	A, (DISPMODE)
	AND	1		; Check if 40 or 80 cols
	JR	Z, COL1		; 40 columns
	LD	A, '|'
	JR	COL2
COL1:
	LD	A, ' '
COL2:
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
	
	; Printable ASCII
	LD	A, (DISPMODE)
	AND	1		; Check if 40 or 80 cols
	JR	Z, COL3		; 40 columns
	LD	A, '|'
	CALL	PRINTCH
COL3:
	CALL	PRINTNL
	POP	DE
	POP	BC
	RET
#endlocal
;-----------------------------------------------------------------------


;-----------------------------------------------------------------------
; Deposit bytes to memory
;	D		- Enter deposit mode at curaddr
;-----------------------------------------------------------------------
CMD_DEPOSIT::
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
;-----------------------------------------------------------------------
	
	
;-----------------------------------------------------------------------
; Dissassemble memory
; 	X		- Disassemble 1 inst (TODO:Interactive dissassemble)
;	X 10		- Disassemble 10 instructions from curaddr
;-----------------------------------------------------------------------
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
DODIS:
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
;-----------------------------------------------------------------------


;-----------------------------------------------------------------------
; Invalid command handler
;-----------------------------------------------------------------------
CMD_INVAL:
	; Let's try and load command name given as a disk COM file
	LD	HL, LBUF	; Return to start of line 
	CALL	SKIPWHITE	; Make sure we even have a command...
	LD	A, (HL)
	AND	A
	RET	Z		; No command, don't even try
	DEC	HL		; Minus 1 since
	JP	CMD_PROGRAM	; CMD_PROGRAM will increment
	RET
;-----------------------------------------------------------------------


;-----------------------------------------------------------------------
; Jump to code in memory
;	R		- Call curaddr
; 	R 1E00		- Call $1E00
; 	
; Never returns, if code that's run returns, perform a restart
;-----------------------------------------------------------------------
CMD_RUN:
#local
	INC	HL
	CALL	SKIPWHITE
	CALL	PARSENUM	; Check if we got a number
	JR	C, CUR		; If no number, run at current addr
	;LD	HL, START	; Do a cold start if run returns
	LD	HL, WARM	; Try and do a warm start if run returns
	PUSH	HL		; Return address
	PUSH	BC		; Address to jump to
	RET			; Jump to code
CUR:
	;LD	HL, START	; Do a cold start if run returns
	LD	HL, WARM	; Try and do a warm start if run returns
	PUSH	HL		; Return address
	LD	HL, (CURADDR)
	PUSH	HL		; Address to jump to
	RET
#endlocal
;-----------------------------------------------------------------------


;-----------------------------------------------------------------------
; Get time and date from Teensy's RTC
;-----------------------------------------------------------------------
CMD_TIME:
#local	
	LD	BC, 0x0013	; Day BCD
	CALL	TEENSY_RDDEV
	LD	B, A
	CALL	PRINTBYTE
	LD	A, '/'
	CALL	PRINTCH
	
	LD	BC, 0x0014	; Month BCD
	CALL	TEENSY_RDDEV
	LD	B, A
	CALL	PRINTBYTE
	LD	A, '/'
	CALL	PRINTCH
	
	LD	BC, 0x0015	; Year BCD
	CALL	TEENSY_RDDEV
	LD	B, A
	CALL	PRINTBYTE
	LD	A, ' '
	CALL	PRINTCH
	
	LD	BC, 0x0012	; Read hours (BCD) from RTC 
	CALL	TEENSY_RDDEV
	LD	B, A
	CALL	PRINTBYTE
	LD	A, ':'
	CALL	PRINTCH
	
	LD	BC, 0x0011	; Read minutes (BCD) from RTC
	CALL	TEENSY_RDDEV
	LD	B, A
	CALL	PRINTBYTE
	LD	A, ':'
	CALL	PRINTCH
	
	LD	BC, 0x0010	; Read seconds (BCD) from RTC
	CALL	TEENSY_RDDEV
	LD	B, A
	CALL	PRINTBYTE
	
	CALL	PRINTNL
	
	RET
#endlocal
;-----------------------------------------------------------------------


;-----------------------------------------------------------------------
; List root directory of CF card
;-----------------------------------------------------------------------
CMD_LIST:
	CALL	FAT_DIR_ROOT
	RET
;-----------------------------------------------------------------------
	
	



;-----------------------------------------------------------------------
; Read file in from CF card into memory
;-----------------------------------------------------------------------
CMD_COPYFILE:
#local
	INC	HL		; Skip command
	CALL	SKIPWHITE	; Skip whitespace
	LD	A, (HL)
	AND	A
	JR	Z, NOFILE	; If null terminator then no filename given
	
	PUSH	HL		; Save start pointer
	CALL	EXTRACTARG	; Extract argument (null terminate it)
	POP	HL		; Restart pointer to string
	
	PUSH	HL
	CALL	PRINTN		; Print filename
	POP	HL

	LD	DE, MON_FS
	CALL	FS_SETFILENAME	; Set filename
	
	LD	HL, MON_FS
	CALL	FS_OPEN
	JR	C, NOFILE	; If failure to open
	
	LD	HL, (CURADDR)	; Address to load to
	LD	A, (CURBANK)
	LD	C, A		; Bank to load to
	CALL	NORMAL_ADDR	; Normalize addr
	
	LD	IX, MON_FS
	CALL	FS_READFILE	; Read entire file to address

	RET
NOFILE:
	LD	HL, STR_NOFILE
	CALL	PRINTN
	RET
#endlocal
;-----------------------------------------------------------------------


;-----------------------------------------------------------------------
; Load and run a program from disk
;-----------------------------------------------------------------------
CMD_PROGRAM:
#local
	INC	HL		; Skip command
	CALL	SKIPWHITE	; Skip whitespace
	LD	A, (HL)
	AND	A
	JP	Z, NOFILE	; If null terminator then no filename given
	
	PUSH	HL		; Save start pointer
	CALL	EXTRACTARG	; Extract argument (null terminate it)
	; Save pointer to any arguments
	INC	HL
	LD	(CMDARGS), HL
	POP	HL		; Restart pointer to string
	
	LD	DE, MON_FS
	CALL	FS_SETFILENAME
	; Change extension to COM (Kind of cheating)
	LD	A, 'C'
	LD	(MON_FS+FS_FNAME+8), A
	LD	A, 'O'
	LD	(MON_FS+FS_FNAME+9), A
	LD	A, 'M'
	LD	(MON_FS+FS_FNAME+10), A
	; Try and open file
	LD	HL, MON_FS
	CALL	FS_OPEN
	JR	C, NOFILE	; If failure to open

	
	

	; Read the file into bank 0 (Max program size 32768 bytes)
	LD	HL, 0x100	; Base address to load to
	LD	C,  0x08	; Bank to load into (in LOW 4 bits)
	LD	IX, MON_FS
	CALL	FS_READFILE	; Read entire file to address
	
	LD	HL, MON_FS
	CALL	FS_CLOSE
	
	;RET	; Do nothing for now

	; Copy needed BIOS code into low 256 bytes
	LD	HL, 0x0000	; Copy vector table from rom
	LD	DE, SECTOR	; Use the SECTOR buffer as scratch (it's 512 bytes)
	LD	BC, 0x100	; 256 bytes
	LDIR
	; Now copy from RAM to the programs bank
	LD	A, 0x08
	LD	HL, SECTOR
	LD	DE, 0x0000
	LD	BC, 0x100
	CALL	RAM_BANKCOPY	; Copy between banks
	
	CALL	PRINTNL
	LD	HL, STR_PREJUMP
	CALL	PRINTN

	
	; Perform bankswitch and call program
	LD	A, 0x98		; Free RAM in upper, program RAM in lower
	LD	(CURBANK), A	; Set current bank
	; Alright, we're leaving forever
	LD	SP, 0xFFFF
	JP	BIOSSTART	; Bank switch and start!
	; We're gone
	
NOFILE:
	LD	HL, STR_NOPROG
	CALL	PRINTN
	RET
#endlocal
;-----------------------------------------------------------------------


;-----------------------------------------------------------------------
; Create a new file on CF card
;-----------------------------------------------------------------------
CMD_TEMP_CFILE:
	INC	HL		; Skip command
	CALL	SKIPWHITE	; Skip whitespace
	LD	A, (HL)
	AND	A
	RET	Z		; If null terminator then no filename given
	
	PUSH	HL		; Save start pointer
	CALL	EXTRACTARG	; Extract argument (null terminate it)
	POP	HL		; Restart pointer to string
	
	
	LD	DE, MON_FS
	CALL	FS_SETFILENAME
	LD	HL, MON_FS
	CALL	FS_CREATE
	RET	NC
	CALL	PRINTI
	.ascii "FS: Failed to create file", 10, 13, 0
	RET
;-----------------------------------------------------------------------


;-----------------------------------------------------------------------
; Delete file from CF card
;-----------------------------------------------------------------------
CMD_TEMP_DFILE:
	INC	HL		; Skip command
	CALL	SKIPWHITE	; Skip whitespace
	LD	A, (HL)
	AND	A
	RET	Z		; If null terminator then no filename given
	
	PUSH	HL		; Save start pointer
	CALL	EXTRACTARG	; Extract argument (null terminate it)
	POP	HL		; Restart pointer to string
	LD	DE, MON_FS
	CALL	FS_SETFILENAME
	LD	HL, MON_FS
	CALL	FS_DELETE
	RET	NC
	CALL	PRINTI
	.ascii "FS: Failed to delete file",10,13,0
	RET
;-----------------------------------------------------------------------


;-----------------------------------------------------------------------
; Load a program from the PC (through teensy) into memory and run
; Program NAME sent to PC, and NAME.COM is returned if it exists
;-----------------------------------------------------------------------
CMD_PC_LOAD:
#local
	INC	HL		; Skip command
	CALL	SKIPWHITE	; Skip whitespace
	LD	A, (HL)
	AND	A
	JP	Z, NOFILE	; If null terminator then no filename given
	
	PUSH	HL		; Save start pointer
	 CALL	EXTRACTARG	; Extract argument (null terminate it)
	 INC 	HL		; Skip null
	 LD	(CMDARGS), HL	; Save argument string
	POP	HL		; Restart pointer to string
	
	
	LD	B, 0x10		; Request for program load
	CALL	TEENSY_WRITE

	CALL	TEENSY_READ	; Wait for response
	CP	0x06		; ACK
	JP	NZ, FAIL

	; Send file name
FNAME_LOOP:
	LD	B, (HL)
	CALL	TEENSY_WRITE
	INC	HL
	LD	A, B
	AND	A
	JR	NZ, FNAME_LOOP

	CALL	TEENSY_READ	; Wait for response
	CP	0x06		; ACK
	JR	NZ, NOFILE

	CALL	TEENSY_READ	; Get # of pages to load
	AND	A		; If 0 then failure
	JR	Z, FAIL

	LD	C, A		; # of pages
	LD	DE, 0x0100	; Load address in D (e used as checksum)

	; We're going to reuse our CF card sector buffer to temporarilly load into here
READPAGE:
	LD	HL, SECTOR
	LD	B, 0		; 256 bytes to copy
READIN:
	CALL	TEENSY_READ	; (only corrupts A)
	LD	(HL), A
	ADD	A, E
	LD	E, A		; Store checksum
	INC	HL
	DJNZ	READIN

	; Verify checksum
	LD	B, E
	CALL	TEENSY_WRITE
	CALL	TEENSY_READ
	CP	0x06		; ACK
	JR	NZ, CHKFAIL

	; Copy data from sector buffer to ram
	PUSH	BC		; Save # of pages left (C)
	PUSH	DE		; Save destination address
	LD	E, 0		; Clear low address (checksum)
	LD	A,  0x08	; Bank to load into (in LOW 4 bits)
	LD	BC, 256		; # of bytes to copy
	LD	HL, SECTOR
	CALL	RAM_BANKCOPY	; Copy into program bank

	POP	DE
	INC	D		; Next page of destination
	POP	BC		; Restore pages left
	DEC	C
	JR	NZ, READPAGE
	; Program is in ram, perform final steps
	; Copy needed BIOS code into low 256 bytes
	LD	HL, 0x0000	; Copy vector table from rom
	LD	DE, SECTOR	; Use the SECTOR buffer as scratch (it's 512 bytes)
	LD	BC, 0x100	; 256 bytes
	LDIR
	; Now copy from RAM to the programs bank
	LD	A, 0x08
	LD	HL, SECTOR
	LD	DE, 0x0000
	LD	BC, 0x100
	CALL	RAM_BANKCOPY	; Copy between banks

	LD	HL, STR_PREJUMP
	CALL	PRINTN
	
	; Perform bankswitch and call program
	LD	A, 0x98		; Free RAM in upper, program RAM in lower
	LD	(CURBANK), A	; Set current bank
	; Alright, we're leaving forever
	LD	SP, 0xFFFF
	JP	BIOSSTART	; Bank switch and start!
	; We're gone
	;RET
NOFILE:
	LD	HL, STR_NOPROG
	CALL	PRINTN
	RET
FAIL:
	LD	HL, STR_HOSTFAIL
	CALL	PRINTN
	RET
CHKFAIL:
	LD	HL, STR_CHKFAIL
	CALL	PRINTN
	RET

#endlocal
;-----------------------------------------------------------------------


;-----------------------------------------------------------------------
; Display the help screen
;-----------------------------------------------------------------------
CMD_HELP:
	LD	HL, STR_HELP
	CALL	PRINTN
	RET
;-----------------------------------------------------------------------

#endlocal
