
; 16-bit compare HL with register
; CMP16 DE   ==   CMP HL, DE
CMP16	macro	&RP
	AND	A		; Clear carry
	SBC	HL, &RP		
	ADD	HL, &RP		; Set flags
	endm

PUSHALL macro
	PUSH	AF
	PUSH	BC
	PUSH	DE
	PUSH	HL
	PUSH	IX
	PUSH	IY
	endm
POPALL	macro
	POP	IY
	POP	IX
	POP	HL
	POP	DE
	POP	BC
	POP	AF
	endm
