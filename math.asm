;-------------------------------------------------------------------------------
; z80 Math Helper Routines

#data _RAM

MATH32_ACCL:	DW	0
MATH32_ACCH:	DW	0

#code _ROM

#local

;=======================================================================
;; Internal helper functions for accumulator

; Load 32-bit value at (HL) into ACC
; Corrupts BC, DE, HL
LOAD_ACC:
	LD	DE, MATH32_ACCL
	LDI				; Low byte, low word
	LDI
	LDI
	LDI				; High byte, high word
	RET

; Save 32-bit value from ACC to (DE)
; Corrupts BC, DE, HL
SAVE_ACC:
	LD	HL, MATH32_ACCL
	LDI
	LDI
	LDI
	LDI
	RET

; Clear ACC
; Corrupts NONE
CLEAR_ACC:
	PUSH	HL
	LD	HL, 0
	LD	(MATH32_ACCL), HL
	LD	(MATH32_ACCH), HL
	POP	HL
	RET
;=======================================================================
	
;--------------------------------------------------------
;
; 32-bit Add
; Pointer arguments
;  Add LONG (HL) to LONG (DE)
; Corrupts DE, HL
ADD32::
	AND	A		; Clear carry
	; Skip clearing carry for ADC32
ADC32::
	PUSH	BC
	LD	B, 4		; 4 bytes to add
ADD32_LOOP:
	LD	A, (DE)
	ADC	A, (HL)
	LD	(DE), A
	INC	DE
	INC	HL
	DJNZ	ADD32_LOOP
	POP	BC
	RET

;--------------------------------------------------------
; 32-bit sub
; Pointer arguments
;  Subtracts LONG (HL) from LONG (DE)
; Corrupts DE, HL, A
SUB32::
	AND	A		; Clear carry (borrow)
	; Skip clearing carry for SBC32
SBC32::
	PUSH	BC		; Save B
	LD	B, 4
SUB32_LOOP:
	LD	A, (DE)
	SBC	A, (HL)
	LD	(DE), A
	INC	DE
	INC	HL
	DJNZ	SUB32_LOOP
	POP	BC
	RET
	
;--------------------------------------------------------
; Add a 16-bit value to a 32-bit value
;   Adds DE to LONG (HL)
;   Corrupts HL, A
ADD32_16::
	AND	A		; Clear carry
ADC32_16::
	LD	A, (HL)		; Low byte
	ADC	A, E
	LD	(HL), A
	INC	HL
	
	LD	A, (HL)		; High byte
	ADC	A, D
	LD	(HL), A
	INC	HL

	LD	A, (HL)		; Propgate carries
	ADC	0
	LD	(HL), A
	INC	HL

	LD	A, (HL)		; Propogate carries
	ADC	0
	LD	(HL), A
	INC	HL
	RET

;--------------------------------------------------------
; Subtract a 16-bit value from a 32-bit value
;   Subtracts DE from LONG (HL)
;   Corrupts HL, A
SUB32_16::
	AND	A		; Clear carry
SBC32_16::
	LD	A, (HL)		; Low byte
	SBC	A, E
	LD	(HL), A
	INC	HL
	
	LD	A, (HL)		; High byte
	SBC	A, D
	LD	(HL), A
	INC	HL

	LD	A, (HL)		; Propgate carries
	SBC	0
	LD	(HL), A
	INC	HL

	LD	A, (HL)		; Propogate carries
	SBC	0
	LD	(HL), A
	INC	HL
	RET
	
;--------------------------------------------------------
; Shift LONG (HL) right by 1 (into carry)
;   Corrupts NONE
SRL32::
	INC	HL		;+1
	INC	HL		;+2
	INC	HL		;+3 Start with most significant byte
	SRL	(HL)		; Shift top
	DEC	HL
	RR	(HL)		; Rotate next
	DEC	HL
	RR	(HL)		; Rotate next
	DEC	HL
	RR	(HL)		; Rotate last
	RET
	
;--------------------------------------------------------
; Shift LONG (HL) left by 1 (into carry)
; Corrupts HL
SLL32::
	SLA	(HL)		; Shift bottom
	INC	HL
	RL	(HL)		; Rotate next
	INC	HL
	RL	(HL)		; Rotate next
	INC	HL
	RL	(HL)		; Rotate top
	RET

;--------------------------------------------------------
; Check if LONG (HL) is 0
; Corrupts A
CHKCLR32::
	INC	HL
	INC	HL
	INC	HL		; Start with MSB so we don't corrupt HL
	LD	A, (HL)
	DEC	HL
	OR	(HL)
	DEC	HL
	OR	(HL)
	DEC	HL
	OR	(HL)
	RET
	
;--------------------------------------------------------
; 32-bit Multiply
; Multiplies LONG (HL) by LONG (BC), result in LONG (HL)
; Upper 32-bits of result discarded
MUL32::
	CALL	CLEAR_ACC		; Clear accumulator
MUL32_LOOP:
	CALL	SRL32		; Get next bit of multiplier (HL)
	PUSH	HL		; Preserve HL
	JR	NC, MUL32_NOADD	; If 0 then don't add
	
	PUSH	BC		; Move
	POP	HL		; Current multiplicand (addr) into HL
	LD	DE, MATH32_ACCL	; Accumulator for result
	CALL	ADD32		; Add current value to ACC
MUL32_NOADD:
	; Need to shift (BC) to the left by one
	PUSH	BC
	POP	HL		; Current multiplicand (addr) into HL
	CALL	SLL32		; Shift left
	
	POP	HL		; Restore HL
	CALL	CHKCLR32	; Check if (HL) is 0 yet
	JR	NZ, MUL32_LOOP
	; We're done, multiplier contains no more bits
	EX	DE, HL		; Address of where to store result
	CALL	SAVE_ACC		; Save accumulator to result
	RET
;-----

; Copy 32-bit values
; Copy LONG (HL) into LONG (DE)
COPY32::
	PUSH	BC
	LDI
	LDI
	LDI
	LDI
	POP	BC
	RET

; Copy 16-bit value
; Copy WORD (HL) into WORD (DE)
COPY16::
	PUSH	BC
	LDI
	LDI
	POP	BC
	RET
	
; Copy WORD DE into LONG (HL)
; Corrupts DE and HL
COPY32_16::
	LD	(HL), E
	INC	HL
	LD	(HL), D
	INC	HL
	LD	D, 0
	LD	(HL), D
	INC	HL
	LD	(HL), D
	RET

CLEAR32::
	XOR	A
	LD	(HL), A
	INC	HL
	LD	(HL), A
	INC	HL
	LD	(HL), A
	INC	HL
	LD	(HL), A
	INC	HL
	RET
#endlocal
