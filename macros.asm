
; 16-bit compare HL with register
; CMP16 DE   ==   CMP HL, DE
CMP16	macro	&RP
	AND	A		; Clear carry
	SBC	HL, &RP		
	ADD	HL, &RP		; Set flags
	endm

