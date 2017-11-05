;---------------------------------------
; Get Scancode
KBD_GETSCAN:
	LD	B, 0x01			; Start at row 0
	LD	A, 0			; Row offset in decode table
KBD_GETSCAN_LOOP:
	LD	C, PORT_KBD
	IN	C, (C)			
	JR	NZ, KBD_GETSCAN_FND	; Found a keypress
	ADD	A, 8			; Next row
	SLA	B			; Shift to next row
	JR	NC, KBD_GETSCAN_LOOP	; Loop till we find a keycode or run out of rows
	LD	A, 0			; No key pressed
	RET
KBD_GETSCAN_FND:
	LD	B, A			; Save our row offset into B
	LD	A, 0	
KBD_GETSCAN_FND_LOOP:
	RR	C			; Rotate C until we find the bit# of the match
	JR	C, KBD_GETSCAN_BIT
	INC	A			; Next bit
	JR	KBD_GETSCAN_FND_LOOP	; Fine to loop since we know a bit is set
KBD_GETSCAN_BIT:
	OR	A, B			; Or with the row offset 
	RET
	
;---------------------------------------
; Convert scancode to ASCII(ish)
SCAN2KEY:
	LD	C, A			; Scancode as the offset
	LD	B, 0
	LD	HL, KBD_DECODE		; Load the decode table address
	ADD	HL, BC			; Offset into table
	LD	A, (HL)			; Read in the value
	RET
	
	
	
;---------------------------------------
; Waits for a key to be pressed, and returns the ASCII value
KBD_GETKEY:
	CALL	KBD_GETSCAN
	AND	A
	JR	Z, KBD_GETKEY		; Wait for a keypress
	
	LD	BC, 50			; Give some delay for debounce
	CALL	DELAY	
	
	CALL	SCAN2KEY
	RET
	
	
	
	
	
;===============================================================================
; Static Data
KBD_DECODE:
	DB $80, $81, $82, $83, $84, $08, $0A, $20	; Row 0  (00000001)
	DB $85, $86, 's', 'x', $87, $88, '2', 'w'  	; Row 1	 (00000010)
	DB 'n', 'm', 'j', 'h', 'u', '6', '7', 'y' 	; Row 2  (00000100)
	DB ',', '.', 'k', 'l', 'i', '9', '8', 'o'  	; Row 3  (00001000)
	DB  $89, $8A, 'd', 'c', $8B, $8C, '3', 'e'  	; Row 4  (00010000)
	DB '/', ';', $27, '[', '=', '0', 'p', '-'  	; Row 5  (00100000)
	DB  $8D, 'z', $8E, 'a', 'q', $1B, '1', $09	; Row 6  (01000000)
	DB  'b', 'v', 'g', 'f', 't', '5', '4', 'r'  	; Row 7  (10000000)

