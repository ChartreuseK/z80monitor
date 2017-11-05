;---------------------------------------
; Write a null terminated string to LCD
; Addr to string in HL
LCDPUTS:
	LD	A,(HL)
	AND	0xFF				
	JR	Z, LCDPUTS_END	; End if we hit null terminator
	SCF			; Set carry flag 
	CALL	LCDWRITE	; Write char, (Carry set at end)
	INC	HL
	JR	LCDPUTS		; Loop till we hit null
LCDPUTS_END:
	RET
	
;---------------------------------------
; Write A in binary to the LCD
LCDBIN:
	LD	B, 8
	LD	C, A
LCDBINL:
	LD	A, C
	AND	0x80
	JR	Z, LCDBIN0
LCDBIN1:
	PUSH 	BC
	LD	A, '1'
	JR	LCDBINN
LCDBIN0:
	PUSH	BC
	LD	A, '0'
LCDBINN:
	SCF
	CALL	LCDWRITE
	POP	BC
	SLA	C
	
	DJNZ	LCDBINL
	
	RET
	
;---------------------------------------
	
;---------------------------------------
; Initialize 44780 40x1 LCD in 4 bit mode
LCDINIT:
	CALL	LCDDEL_CMD	; Wait ~20ms for LCD inital setup
	CALL	LCDDEL_CMD

	; LCD is currently in 8-bit mode, swap it to 4 bit
	; Initialization of 3 Function set calls
	LD	A, 0x03		; Function set
	CALL	LCDWRITEN	; Write nybble (actually 8-bit command)
	
	; Might need slight delay > 4ms here if at high clock
	CALL	LCDDEL_CMD
	
	CALL	LCDWRITEN	; Write nybble (actually 8-bit command)
	CALL	LCDDEL_CMD
	
	CALL	LCDWRITEN	; Write nybble (actually 8-bit command)
	CALL	LCDDEL_CMD
	
	; Finally swap to 4 bit mode
	LD	A, 0x02		; Function set (4-bit mode)
	CALL	LCDWRITEN
	
	CALL	LCDDEL_CMD
	; Now we are in 4 bit mode:
	LD	A, 0x20		; Function set (4-bit, 1 lines, font 0)
	SCF							
	CCF			; RS = 0 / Command
	CALL	LCDWRITE
	CALL	LCDDEL_CMD
	; (Carry set by prev call to LCD)
	CCF
	LD	A, 0x08		; Display Off
	CALL	LCDWRITE
	CALL	LCDDEL_CMD
	; (Carry set by prev call to LCD)
	CCF
	LD	A, 0x01		; Clear display
	CALL	LCDWRITE
	CALL	LCDDEL_CMD
	; (Carry set by prev call to LCD)
	CCF
	LD	A, 0x06		; Entry mode: Move right, don't shift
	CALL	LCDWRITE
	CALL	LCDDEL_CMD
	; (Carry set by prev call to LCD)
	CCF
	LD	A, 0x0E		; Display on, with non-blinking cursor
	CALL	LCDWRITE
	CALL	LCDDEL_CMD
	RET
;---------------------------------------

;---------------------------------------
; Write nybble to LCD
;  Nybble in A(0:3) A(4) contains register select, A(5:7) are 0
LCDWRITEN:
	OR	0x20		; Set E bit to high
	OUT 	(PORT_LCD), A	; Write to port (E high)

	AND	0x1F		; Set E bit to low
	OUT	(PORT_LCD), A	; Write to port (E low) (signals transfer)

	RET
;---------------------------------------

;---------------------------------------
; Write byte data to LCD
;  Byte in A, Carry Flag is register select 
;  (clear = command, set = data). (B and C used)
LCDWRITE:
	LD	B, A		; Save byte into B
	
	RR	A	
	RR	A	
	RR	A		; Shift high nybble into low, and RS from C into
	RR	A		; bit 5
	AND	0x1F		; Clear high bits
	CALL 	LCDWRITEN	; Write nybble
	
	CALL	LCDDEL_NYB
	
	AND	0x10		; Save only RS bit
	LD	C,A		; Save RS bit in C
	LD	A,B		; Restore original byte
	AND	0x0F		; Only the low nybble
	OR	C		; Or with the RS bit
	
	CALL 	LCDWRITEN	; Write nybble
	CALL	LCDDEL_NYB
	SCF			; Leave with carry set (so RS=1 instr can chain)
	RET
;---------------------------------------

;---------------------------------------
; Clear LCD
LCDCLEAR:
	SCF
	CCF			; Write command
	LD	A, 0x01		; Clear display
	JP	LCDWRITE			
	; Tail call

;---------------------------------------
; Home cursor on LCD
LCDHOME:
	SCF
	CCF			; Write command
	LD	A, 0x02		; Home cursor
	JP	LCDWRITE	; Tail call
;---------------------------------------

;---------------------------------------
; Delay between LCD commands
LCDDEL_CMD:
	PUSH	BC
	LD	BC, 2		; Must be 2 or greater
	CALL	DELAY
	POP	BC
	RET
;---------------------------------------
	
;---------------------------------
; Delay between LCD nybbles
LCDDEL_NYB:
	JP	DELAY_MS
