;---------------------------------------
; Delay for ~1ms
DELAY_MS:			; 17 - CALL DELAY_MS
	PUSH	BC		; 11
	LD	B, MSDELAY	; 7  - Delay interations
DELAY_MSL:
	NOP			; 4
	NOP			; 4
	NOP			; 4
	NOP			; 4
	NOP			; 4
	NOP			; 4
	NOP			; 4
	NOP			; 4
	NOP			; 4
	NOP			; 4
	NOP			; 4
	NOP			; 4
	NOP			; 4
	DJNZ	DELAY_MSL	; 13/8
	POP	BC		; 10
	RET			; 10
;---------------------------------------

;---------------------------------------
; Delay for approx 'BC' milliseconds
DELAY:
	PUSH	AF
DELAY_L:
	CALL	DELAY_MS
	DEC	BC
	LD	A, B
	OR	C
	JP	NZ, DELAY_L
	POP	AF
	RET
;---------------------------------------
	
