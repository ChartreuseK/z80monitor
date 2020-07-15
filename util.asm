
#local

;--------
; Compare memory at (HL) to (DE) for B bytes
; Set's Z flag to results
; Pointers left on first byte not to match
MEMCMP::
	LD	A, (DE)
	CP	(HL)
	RET	NZ		; If bytes don't match return with Z flag clear
	INC	HL
	INC	DE
	DJNZ	MEMCMP
	RET			; Z flag still set from CP


;-----------------------------------------------------------------------
; Normalize far address C:HL to be in the low bank
; with C only being in the low 4 bits
;-----------------------------------------------------------------------
NORMAL_ADDR::
#local
	LD	A, H
	AND	80h
	JR	Z, LOWBANK
	SRL	C \ SRL	C
	SRL	C \ SRL	C	; High bank to low bank
	LD	A, H
	AND	7Fh		; Convert address to be for low bank
	LD	H, A
LOWBANK:
	LD	A, C
	AND	0Fh		; Make sure only low bank listed
	LD	C, A
	RET
#endlocal
;-----------------------------------------------------------------------

#endlocal
