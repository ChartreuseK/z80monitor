;---------------------------------------
; Initialize the 68681 DUART
SERIAL_INIT:
	LD	A, $30
	OUT	(SER_CRA), A	; Reset Transmitter
	LD	A, $20
	OUT	(SER_CRA), A	; Reset Reciever
	LD	A, $10
	OUT	(SER_CRA), A	; Reset Mode Register Pointer
	
	LD	A, $80			
	OUT	(SER_ACR), A	; Baud Rate Set #2
	LD	A, $BB		; BB for 9600, 44 for 300
	OUT	(SER_CSRA), A	; 300 Tx and Rx
	LD	A, $13			
	OUT	(SER_MRA), A	; 8 bit, no parity
	LD	A, $07
	OUT	(SER_MRA), A	; Normal mode, no flow control, 1 stop bit
	
	LD	A, $00
	OUT	(SER_IMR), A	; No interrupts
	
	LD	A, $05
	OUT	(SER_CRA), A	; Enable Transmit/Recieve
	RET
;---------------------------------------

;---------------------------------------
; Read a character from serial port A, blocking if not available
SERIAL_READ:
	IN	A, (SER_SRA)
	BIT	0, A		; Check if recv ready bit et
	JR	Z, SERIAL_READ	
	IN	A, (SER_RBA)	; Read in character from A
	RET
;---------------------------------------

;---------------------------------------
; Write a character from serial port A, blocking till sent
SERIAL_WRITE:
	PUSH	BC
	LD	B, A
SERIAL_WRITE_L:
	IN	A, (SER_SRA)
	BIT	2, A
	JP	Z, SERIAL_WRITE_L
	LD	A, B
	OUT	(SER_TBA), A
	
	POP	BC
	RET
;---------------------------------------

;---------------------------------------
; Write a null terminated string to Serial A
; Addr to string in HL
SERIAL_PUTS:
	LD	A,(HL)
	AND	0xFF				
	JR	Z, SERIAL_PUTS_END	; End if we hit null terminator
	CALL	SERIAL_WRITE	; Write char
	INC	HL
	JR	SERIAL_PUTS	; Loop till we hit null
SERIAL_PUTS_END:
	RET

SERIAL_NL:
	LD	HL, SNL
	JR	SERIAL_PUTS
	
SNL:
	DB 10,13,0
