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
#local
	PUSH	BC
	LD	B, A
LOOP:
	IN	A, (SER_SRA)
	BIT	2, A
	JP	Z, LOOP
	LD	A, B
	OUT	(SER_TBA), A
	
	POP	BC
	RET
#endlocal
;---------------------------------------

;---------------------------------------
; Write a null terminated string to Serial A
; Addr to string in HL
SERIAL_PUTS:
#local
	LD	A,(HL)
	AND	0xFF				
	JR	Z, END		; End if we hit null terminator
	CALL	SERIAL_WRITE	; Write char
	INC	HL
	JR	SERIAL_PUTS	; Loop till we hit null
END:
	RET
#endlocal

SERIAL_NL:
	LD	HL, SNL
	JR	SERIAL_PUTS
	
SNL:
	DB 10,13,0



;--------
; Print a 1-byte hex number
;  B - number
SERIAL_WRHEX8:
	LD	A, '$'
	CALL	SERIAL_WRITE
SERIAL_WRHEX8_NP:
	LD	A, B
	SRL	A
	SRL	A
	SRL	A
	SRL	A	; Extract high nybble
	CALL	SERIAL_WRNYB
	LD	A, B
	AND	$0F
	; Fall into PUSHNYB (Tail call)
;--------
; Push a nybble from A (low 4-bits, high must be 0)
SERIAL_WRNYB:
#local
	ADD	'0'
	CP	'9'+1	; Check if A-F
	JR	C, NOFIX
	ADD	'A'-('9'+1)	; Diff between 'A' and ':'
NOFIX:
	JP	SERIAL_WRITE		; Tail call
#endlocal
	
	
;--------
; Print a 2-byte hex number
;  BC - number
SERIAL_WRHEX16:
	CALL	SERIAL_WRHEX8
	LD	B, C
	JP	SERIAL_WRHEX8_NP	; Tail call
