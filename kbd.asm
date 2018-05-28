
#data _RAM
LAST_SCAN:	DS 1	; Last pressed key

#code _ROM


;---------------------------------------
; Get Scancode
KBD_GETSCAN:
#local
	LD	B, 0x01		; Start at row 0
	LD	A, 0		; Row offset in decode table
LOOP:
	LD	C, PORT_KBD
	IN	C, (C)		; Read from port BC, B used for scanning key rows
	JR	NZ, FND		; Found a keypress
	ADD	A, 8		; Next row
	SLA	B		; Shift to next row
	JR	NC, LOOP	; Loop till we find a keycode or run out of rows
	LD	A, 0		; No key pressed
	RET
FND:
	LD	B, A		; Save our row offset into B
	LD	A, 0	
FND_LOOP:
	RR	C		; Rotate C until we find the bit# of the match
	JR	C, BIT
	INC	A		; Next bit
	JR	FND_LOOP	; Fine to loop since we know a bit is set
BIT:
	OR	A, B		; Or with the row offset -  00 rrr bbb
	PUSH	AF		; Save A
; Scan in modifiers
;Left Shift  J0 - Ctrl  J1 - Right Shift J5
; J is connected to IP2 on the 68681
; TODO: Optimize, this is way too big...
	XOR	A			; Modifiers
	
	LD	B, 0x02			; Scan Shift R
	CALL	SCANMOD
	JR	Z, NOSHIFTR
	OR	$40			; Shift mask
NOSHIFTR:
	LD	B, 0x20			; Scan Shift L
	CALL	SCANMOD
	JR	Z, NOSHIFT
	OR	$40
NOSHIFT:
	LD	B, 0x01			; Scan ctrl
	CALL	SCANMOD
	JR	Z, NOCTRL
	OR	$80
NOCTRL:
	
	LD	B, A
	POP	AF
	OR	B
	RET

; Scans modifier key 
; (68681 seems quite slow/inconsitant at detecting changes, our workaround
;  for now is to spam the scan a ton of times. Seems to work consistently.
;  We use IN opcodes from the 68681 since they're slightly longer than memory
;  reads due to the WAIT state circuitry for /DTACK) 
; Ideally we should add another buffer to read the state without the 68681
; or see if we can get the plain unbuffered input port on the 68681 to work
;
; UGLY UGLY HACK, Figure out a hardware fix....
; 
; Sets Z corresponding to the scanned bit
; Row/Rows to scan in B

SCANMOD:
#local
	PUSH	DE
	PUSH	BC
	LD	E, A
	LD	BC, 0x0000 | SER_IPCR
	IN	C, (C)			; Reset IPCR to start
	POP	BC
	
	LD	C, SER_SRA	; Use SRA so we don't affect the ports
	XOR	A			; Loop 256 times
SCANLOOP:
	IN	D, (C)			; Scan the row
	IN	D, (C)			; Scan the row
	IN	D, (C)			; Scan the row
	IN	D, (C)			; Scan the row
	IN	D, (C)			; Scan the row
	IN	D, (C)			; Scan the row
	IN	D, (C)			; Scan the row
	IN	D, (C)			; Scan the row
	
	IN	D, (C)			; Scan the row
	IN	D, (C)			; Scan the row
	IN	D, (C)			; Scan the row
	IN	D, (C)			; Scan the row
	
	IN	D, (C)			; Scan the row
	IN	D, (C)			; Scan the row
	IN	D, (C)			; Scan the row
	IN	D, (C)			; Scan the row
	SUB	1
	JR	NZ, SCANLOOP
	
	LD	BC, 0x0000 | SER_IPCR	; Scan in change register
	IN	C, (C)			; Re-read IPCR
	BIT	6, C			; Check IP2 change
	LD	A, E
	POP	DE
	RET
#endlocal



#endlocal


;---------------------------------------
; Convert scancode to ASCII(ish)
SCAN2KEY:
#local
	;PUSH	AF			; Save A
	BIT	6, A			; Test Shift
	JR	Z, NOSHIFT
	LD	HL, KBD_DECODE_SHIFT	; Shifted keys don't quite correspond
	JR	DECODE			; to ASCII shifts so can't just mask $20
NOSHIFT:
	LD	HL, KBD_DECODE
DECODE:
	AND	0x3F			; Mask off ctrl and shift bits
	LD	C, A			; Scancode as the offset
	LD	B, 0
	ADD	HL, BC			; Offset into table
	LD	A, (HL)
	RET
	
	
	
	POP	AF			; Restore A
	LD	B, A			; Save scancode (so we can test ctrl)
	LD	A, (HL)			; Read in the value from table
	BIT	7, B			; Ctrl bit
	JR	Z, NOCTRL
	AND	$9F			; Mask $40 and $20, convert to CTRL keys
NOCTRL:
	RET
#endlocal
	
	
;---------------------------------------
; Waits for a key to be pressed, and returns the ASCII value
KBD_GETKEY:
#local
	PUSH	BC
	PUSH	HL
LOOP:
	CALL	KBD_GETSCAN
	
	LD	BC, 20			; Give some delay for debounce
	CALL	DELAY	
	
	LD	HL, LAST_SCAN		
	CP	(HL)			; Compare with last scancode
	JR	Z, LOOP		; If same as last key ignore
	
	LD	(HL), A			; Save as new last key (even if blank)
	
	AND	A			; Retest scancode
	JR	Z, LOOP		; Wait for a keypress
	
	CALL	SCAN2KEY		; Convert scancode to ASCII
	POP	HL
	POP	BC
	RET
#endlocal

;---------------------------------------
; Check if a key is being pressed, return ASCII value, or 0 if none pressed
KBD_GETKEYNB:
#local
	PUSH	BC
	PUSH	HL
LOOP:
	CALL	KBD_GETSCAN
	
	LD	BC, 20			; Give some delay for debounce
	CALL	DELAY	
	
	LD	HL, LAST_SCAN		
	CP	(HL)			; Compare with last scancode
	JR	Z, END2		; If same as last key ignore
	
	LD	(HL), A			; Save as new last key (even if blank)
	
	AND	A			; Retest scancode
	JR	Z, END2			; No key being pressed
	
	CALL	SCAN2KEY		; Convert scancode to ASCII
	
	POP	HL
	POP	BC
	RET
END2:				; Exit, no key pressed
	XOR	A
	POP	HL
	POP	BC
	RET
#endlocal


	

	
	
	
;===============================================================================
; Static Data

; Keyboard decoding matrix. For keyboard taken from Motorola Pager Terminal
; See KBDMAP.TXT for more information on keyboard decoding, and special
; keys (Values >= $80)
KBD_DECODE:
	DB $80, $81, $82, $83, $84, $08, $0A, $20	; Row 0  (00000001)
	DB $85, $86, 's', 'x', $87, $88, '2', 'w'  	; Row 1	 (00000010)
	DB 'n', 'm', 'j', 'h', 'u', '6', '7', 'y' 	; Row 2  (00000100)
	DB ',', '.', 'k', 'l', 'i', '9', '8', 'o'  	; Row 3  (00001000)
	DB $89, $8A, 'd', 'c', $8B, $8C, '3', 'e'  	; Row 4  (00010000)
	DB '/', ';', $27, '[', '=', '0', 'p', '-'  	; Row 5  (00100000)
	DB $8D, 'z', $8E, 'a', 'q', $1B, '1', $09	; Row 6  (01000000)
	DB 'b', 'v', 'g', 'f', 't', '5', '4', 'r'  	; Row 7  (10000000)
; Shifted keys, not quite a standard keyboard layout
KBD_DECODE_SHIFT:
	DB $80, $81, $82, $83, $84, $08, $0A, $20	; Row 0
	DB $85, $86, 'S', 'X', $87, $88, '@', 'W'	; Row 1
	DB 'N', 'M', 'J', 'H', 'U', '\', '&', 'Y'	; Row 2
	DB ',', '.', 'K', 'L', 'I', '(', '*', 'O'	; Row 3
	DB $89, $8A, 'D', 'C', $8B, $8C, '#', 'E'	; Row 4
	DB '?', ':', '"', ']', '+', ')', 'P', '_'	; Row 5
	DB $8D, 'Z', $8E, 'A', 'Q', $1B, '!', $09	; Row 6
	DB 'B', 'V', 'G', 'F', 'T', '%', '$', 'R'	; Row 7
