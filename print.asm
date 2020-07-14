; Various console print format routines
;

;--------
; Print a hex byte to the console
;  A - byte
PRINTBYTE:
	PUSH	BC
	LD	B, A
	RRA
	RRA
	RRA
	RRA
	CALL	PRINTNYB	; Print high nybble
	LD	A, B
	POP	BC
	JP	PRINTNYB	; Print low Tail call

PRINTBYTE_DEC:
#local
	PUSH	BC
	LD	B, A		; Save byte
	CP	100		
	JR	NC, HUNDRED	; If >= 100 then print digit
	CP	10
	JR	NC, TENS	; If >= 10 then print digit
	JR	ONES
HUNDRED:
	LD	C, '1'
	SUB	100		
	CP	100			
	JR	C, NOINC100	; If < 200 then don't incrment
	INC	C
NOINC100:
	LD	B, A		; Save byte
	LD	A, C
	CALL	PRINTCH		; Print 100's digit
TENS:
	LD	C, '0'
	LD	A, B		; Restore #
TENSLOOP:
	CP	10
	JR	C, DOTENS	; If < 10 then print already
	INC	C
	SUB	10
	JR	TENSLOOP
DOTENS:
	LD	B, A		; Save result
	LD	A, C
	CALL	PRINTCH
ONES:
	LD	C, '0'
	LD	A, B		; Restore #
ONESLOOP:
	CP	1
	JR	C, DOONES	; If < 1 then print already
	INC	C
	SUB	1
	JR	ONESLOOP
DOONES:
	LD	B, A		; Save result
	LD	A, C
	CALL	PRINTCH
	
	POP	BC
	RET
#endlocal

;--------
; Print a hex word to the console
; BC - word
PRINTWORD:
	LD	A, B
	CALL	PRINTBYTE	; Print high byte
	LD	A, C
	JP	PRINTBYTE	; Print low byte, tail call

;--------
; Print a nybble to the console
; A - nybble (low 4 bits)
PRINTNYB:
#local
	AND	$0F		; Only take the low nybble
	ADD	'0'
	CP	'9'+1		; Check if A-F
	JR	C, NOADJ
	ADD	'A'-('9'+1)	; Diff between 'A' and ':'
NOADJ:
	JP	PRINTCH		; Tail call
#endlocal


;--------
; Print a character to console
; A - ch
PRINTCH:
	JP	DISP_WRITE	; Tail Call
	;JP	SERIAL_WRITE	; Tail call

;--------
; Print a null terminated string to console
; HL - string
PRINT:
#local
	LD	A,(HL)
	AND	0xFF				
	JR	Z, END		; End if we hit null terminator
	CALL	PRINTCH	; Write char
	INC	HL
	JR	PRINT		; Loop till we hit null
END:
	RET
#endlocal

;-------
; Print a fixed length string to console
; HL - string
; B - length (0 = 256)
PRINT_FIX:
	LD	A, (HL)
	CALL	PRINTCH
	INC	HL
	DJNZ	PRINT_FIX
	RET



PRINTN:
	CALL	PRINT
	JR	PRINTNL
	
PRINTNL:
	PUSH	AF
	LD	A, $0D
	CALL	PRINTCH
	LD	A, $0A
	CALL	PRINTCH
	POP	AF
	RET

; Print inline message (after call)
PRINTI:
#local
	POP	HL	; Start of string
LOOP:
	LD	A,(HL)
	AND	A
	JR	Z, END
	CALL	PRINTCH
	INC	HL
	JR	LOOP
END:
	INC	HL
	JP	HL
#endlocal