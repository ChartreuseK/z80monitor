;
; Various parsing functions


;--------
; Parse up to 4 hex digits into a word.
; HL - points to first ascii digit
; On return HL points to next byte after digit
; Return word in BC
;----
; Carry set on invalid digit, HL points to invalid digit
PARSENUM:
#local
	LD	BC, 0
	LD	A, (HL)
	
	CALL	HEX2NYB
	JR	C, INVAL	; Must be at least 1 nybble
	LD	C, A	
	
	INC	HL		; Nyb 2?
	LD	A, (HL)
	CALL	HEX2NYB
	JR	C, DONE		; If not a nybble 
	CALL	SHIFTBCNYB	; Make room in BC
	OR	C		; 
	LD	C, A		; Or in new nybble
	
	INC	HL		; Nyb 3?
	LD	A, (HL)
	CALL	HEX2NYB
	JR	C, DONE		; If not a nybble 
	CALL	SHIFTBCNYB	; Make room in BC
	OR	C		; 
	LD	C, A		; Or in new nybble
	
	INC	HL		; Nyb 4?
	LD	A, (HL)
	CALL	HEX2NYB
	JR	C, DONE		; If not a nybble 
	CALL	SHIFTBCNYB	; Make room in BC
	OR	C		; 
	LD	C, A		; Or in new nybble
	SCF
DONE:
	CCF
	RET
INVAL:
	SCF
	RET

SHIFTBCNYB:
	SLA	C		
	RL	B
	SLA	C		
	RL	B
	SLA	C		
	RL	B
	SLA	C		
	RL	B
	RET
#endlocal
	RET

;--------
; Convert 4 ASCII hex digits to a word, must be uppercase
; HL - points to first ascii digit
; On return HL points to next byte after digit
; Return word in BC
;----
; Carry set on invalid digit, HL points to invalid digit
HEX2WORD:
#local
	CALL	HEX2BYTE
	JR	C, INVAL
	LD	B, A		; Save as high byte
	CALL	HEX2BYTE
	JR	C, INVAL
	LD	C, A		; Save as low byte
	; Carry already clear
	RET	
INVAL:
	SCF
	RET
#endlocal


;--------
; Convert 2 ASCII hex digits to a byte, must be uppercase
; HL - points to first ascii digit
; On return HL points to next byte after digit
; Return byte in A
;----
; Carry set on invalid digit, HL points to invalid digit
HEX2BYTE:
#local
	PUSH	BC
	LD	A, (HL)
	CALL	HEX2NYB
	JR	C, INVAL
	SLA	A
	SLA	A
	SLA	A
	SLA	A		; Move to high nybble
	LD	B, A		; Save in B
	INC	HL
	LD	A, (HL)		; Read low nybble
	CALL	HEX2NYB		; Convert
	JR	C, INVAL
	OR	B		; Combine into one
	POP	BC
	INC	HL		; Point to next 
	; Carry already clear from OR
	RET
INVAL:
	POP	BC
	LD	A, 0
	SCF
	RET
#endlocal

;--------
; Convert 1 ASCII hex digit to a nybble, must be uppercase
; A - ASCII Hex digit
; Carry set on invalid digit
HEX2NYB:
#local
	CP	'0'		; ch < 0
	JR	C, INVAL
	CP	'9'+1		; 0 <= ch <= 9
	JR	C, DECI
	CP	'A'
	JR	C, INVAL	; 9 < ch < 'A'
	CP	'F'+1
	JR	NC, INVAL	; 'F' < ch
LETR:	; A-F
	SUB	'A'-10		; Make 'A' -> $0A
	JR	DONE
DECI:	; 0-9
	SUB	'0'		; Make '0' -> $00
	JR	DONE
INVAL:
	LD	A, $80		; Set highbit if invalid
	SCF
	RET
DONE:
	SCF
	CCF
	RET
#endlocal
	
	
;--------
; Increments HL till non-whitespace in (HL)
SKIPWHITE:
#local
	LD	A, (HL)
	CALL	ISWHITE
	JR	NZ, END
	INC	HL
	JR	SKIPWHITE
END:
	RET
#endlocal

;----------
; Extract an argument string
; Replaces first whitespace character with NULL
; HL is set to 0 if end of string encountered
EXTRACTARG:
#local
	LD	A, (HL)
	AND	A
	JR	Z, ENDN		; Stop on NUL
	CALL	ISWHITE	
	JR	Z, END		; Or whitespace
	INC	HL
	JR	EXTRACTARG
ENDN:
	LD	HL, 0
	RET
END:
	XOR	A		; 0
	LD	(HL), A		; Null terminate
	RET

#endlocal
;--------
; Is character in A whitespace? Sets Z if so
ISWHITE:
#local
	CP	' '		; Space
	JR	Z, END
	CP	$09		; TAB
	JR	Z, END
	CP	$0B		; Vert Tab
	JR	Z, END
	CP	$0C		; Form Feed
END:	
	RET
	
#endlocal


;--------
; Convert character in A to uppercase if lowercase
TO_UPPER:
#local
	CP	'a'
	JR	C, NOCHG	; ch < 'a'
	CP	'z'+1		
	
	JR	NC, NOCHG	; ch > 'z'
	; 'a' <= ch <= 'z'
	SUB	$20		; 'a' - 'A' convert to uppercase
NOCHG:
	RET
#endlocal
