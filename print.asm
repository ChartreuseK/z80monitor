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
