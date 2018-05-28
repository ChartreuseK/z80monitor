;
; Simple ANSI serial terminal 'program' 
; 

#local

#data _RAM
LAST_SCAN:	DS 1	; Last pressed key
DEBOUNCE:	DS 1	;

#code _ROM

SERIALTERM::
	LD	HL, STR_SERTERM
	CALL	PRINT

	;CALL	SERIAL_INIT	; Initialize serial port
	; For now the above will setup port 1 as 9600 8N1
	XOR	A		; 0
	LD	(LAST_SCAN), A	; Reset scancode to blank
	LD	A, 1
	LD	(DEBOUNCE), A	; Reset debounce counter
	
	
	
TERMLOOP:
	CALL	SERIAL_READ
	CALL	SERIAL_WRITE
	JP	TERMLOOP
	
	;CALL	SERIAL_POLL	; Check if we have any serial data waiting
	;JR	Z, NOCHAR	; 
	;; Parse character
	;CALL	SERIAL_READ	; Read in character
	CALL	PRINTBYTE
	;CALL	DISP_WRITE	; Simply write to display for now
NOCHAR:
	LD	A, 0x41
	CALL	SERIAL_WRITE
	JP	TERMLOOP
	
	LD	HL, LAST_SCAN
	CP	(HL)		; Check if keypress has changed since last poll
	JR	Z, NOKBD	; If same, then ignore
	LD	B, A		; Save scancode
	
	LD	A, (DEBOUNCE)	; 
	AND	B		; Check if zero
	
	JP	TERMLOOP
	
	JR	Z, NEWKEY
	; Update debounce count
	DEC	A		; Decrement
	LD	(DEBOUNCE), A
	JP	NOKBD
NEWKEY:
	LD	A, 1		; Debounce count
	LD	(DEBOUNCE), A	; Update counter
	LD	A, B		; Restore scancode
	LD	(HL), A		; Save as LAST_SCAN
	AND	A		; Check if zero
	JR	Z, NOKBD	; If no press then ignore
	CALL	SCAN2KEY	; Convert scancode to ASCII
	
	CP	0x0A		; Newline
	JR	NZ, NORETFIX
	LD	A, 0x0D		; CR
NORETFIX:
	CALL	SERIAL_WRITE	; Write to serial port
NOKBD:
	JP	TERMLOOP	; Keep going
	
	
	

STR_SERTERM:
	.ascii 	"Serial Terminal Started. 9600 8N1",13,10
	.ascii  "=================================",13,10,0

#endlocal
