;-----------------------------------------------------------------------
; Routines for interacting with the Teensy 3.2 peripheral 
;-----------------------------------------------------------------------
#local

#code _ROM
;-----------------------------------------------------------------------
; Send a device and address to the Teensy
; B - device
; C - addr
;-----------------------------------------------------------------------
TEENSY_REQ::
	CALL	TEENSY_WRITE	; Send the device first
	LD	B, C
	JR	TEENSY_WRITE	; Then the address (tail call)
;-----------------------------------------------------------------------


;-----------------------------------------------------------------------
; Read a byte from device & addr from the Teensy
; B - device
; C - addr
; Returns:
; A - byte val
;-----------------------------------------------------------------------
TEENSY_RDDEV::
	CALL	TEENSY_REQ
	JR	TEENSY_READ
;-----------------------------------------------------------------------


;-----------------------------------------------------------------------
; Write a byte to a device & addr in the Teensy
; B - Device
; C - Addr
; A - Value
;-----------------------------------------------------------------------
TEENSY_WRDEV::
	PUSH	AF
	CALL	TEENSY_REQ
	POP	AF
	JR	TEENSY_WRITE
;-----------------------------------------------------------------------


;-----------------------------------------------------------------------
; Send a byte to the teensy
; B - byte
;-----------------------------------------------------------------------
TEENSY_WRITE::
	IN	A, (PIO_C)	; Read in status
	BIT	7,A		; Check if output buffer full
	JR	Z, TEENSY_WRITE

	LD	A, B
	OUT	(PIO_A), A
	RET
;-----------------------------------------------------------------------


;-----------------------------------------------------------------------
; Read a byte from the teensy
; Returns A - byte
;-----------------------------------------------------------------------
TEENSY_READ::
	IN	A, (PIO_C)	; Check status
	BIT	5, A		; Check if input buffer full
	JR	Z, TEENSY_READ
	
	IN	A, (PIO_A)
	RET
;-----------------------------------------------------------------------

#endlocal
