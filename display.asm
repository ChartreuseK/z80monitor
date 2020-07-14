; Display interface code with Grant Searle's AVR video controller
; http://searle.hostei.com/grant/MonitorKeyboard/index.html
; Attached to the same 8255 used for communication to the Teensy.
; 4-bit interface using Port B and Port C (low)
; B0 to B4 = Data nybble (out)
; B7 = AVAIL (out)
; C0 = ACK (in)
;



;--------
; Write a character in A to the display controller
DISP_WRITE:
#local
	PUSH	BC
	LD	B, A		; Save byte
	RRA
	RRA
	RRA
	RRA			; Shift high nybble to low
	AND	0x0F		; Mask off nybble
	OR	0x80		; Set avail
	OUT	(PIO_B),A	; Write to display
ACK1:
	IN	A, (PIO_C)	; Wait for ACK
	AND	1		; C0 = ACK
	JR	Z, ACK1
	
	LD	A, B		; Restore byte
	AND	0x0F		; Mask nybble, Set avail low
	OUT	(PIO_B),A	; Write to display
ACK2:
	IN	A, (PIO_C)	; Wait for /ACK
	AND	1		; C0 = ACK
	JR	NZ, ACK2

	POP	BC
	RET
#endlocal

; Set current line's mode to A
DISP_LMODE:
	PUSH	AF		; Save mode
	LD	A, 0x18		; Set font attribute byte
	CALL	DISP_WRITE
	POP	AF		; Restore mode
	JR	DISP_WRITE	; Tail call 
	
; Write character escaped from special chars
DISP_WRITE_ESC:
	PUSH	AF		; Save ch
	LD	A, 0x1A		; Escape next ch
	CALL	DISP_WRITE
	POP	AF
	JR	DISP_WRITE	; Tail call


DISP_INIT:
	LD	A, 0		; Write null to get into known state
	CALL	DISP_WRITE
	LD	A, 0		; Another
	CALL	DISP_WRITE	
	LD	A, $0C		; Clear screen
	CALL	DISP_WRITE
	LD	A, $01		; Home cursor
	CALL	DISP_WRITE
	RET
