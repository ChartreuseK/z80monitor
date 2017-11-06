;---------------------------------------
; Delay for ~1ms
DELAY_MS:			; 17 - CALL DELAY_MS
#local
	PUSH	BC		; 11
	LD	B, MSDELAY	; 7  - Delay interations
LOOP:
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
	DJNZ	LOOP		; 13/8
	POP	BC		; 10
	RET			; 10
#endlocal
;---------------------------------------

;---------------------------------------
; Delay for approx 'BC' milliseconds
DELAY:
#local
	PUSH	AF
LOOP:
	CALL	DELAY_MS
	DEC	BC
	LD	A, B
	OR	C
	JP	NZ, LOOP
	POP	AF
	RET
#endlocal
;---------------------------------------
	
