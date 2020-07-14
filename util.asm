
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

#endlocal
