; Minimal z80 diassesembler written in z80 assembly
;---------------------------------------------------
; z80 opcode decoding based on:
; http://www.z80.info/decoding.htm
;
; TODO: Try and optimize to < 2048 bytes (Personal goal)
;

; RAM Variables
#data _RAM
DISLINE:	DS 22		; Buffer for outputted line
	; Longest possible line is of the form: 'LD A, SET 1, (IX+$AB)'
	; 22 bytes including null terminator
DISLINECUR:	DS 2		; Cur index
PREFIX:		DS 1		; Current prefix
STADDR:		DS 2		; Start address for displacements
SVDISP:		DS 1		; Saved displacement for DDCB and FDCB

#code _ROM

; (HL) points to first byte of instruction
; Returns HL as pointing to next byte after instruction
; (Assumes HL is STADDR for instruction)
DISINST:
#local
	LD	BC, DISLINE
	LD	(DISLINECUR), BC ; Reset string index
	LD	A, 0
	LD	(DISLINE), A	; Start with null
	LD	(PREFIX), A	; Reset prefix
	LD	(STADDR), HL	; Save address for displacements
START:
	LD	A, (HL)	
	CP	$CB		; Check for prefixes
	JP	Z, CB_PRE
	CP	$DD		
	JP	Z, DD_PRE
	CP	$ED
	JP	Z, ED_PRE
	CP	$FD
	JR	Z, FD_PRE
	; No prefix
	AND	$C0		; Grab x (1st octal)
	JR	Z, X0		; 00 ... ...
	JP	P, X1		; 01 ... ...
	CP	$80		
	JR	Z, X2		; 10 ... ...
	; Fall into X3		; 11 ... ...
X3:
	LD	A, (HL)		; Reload instruction
	CALL	EXTRACT_Z
	ADD	A		; Double for index
	LD	DE, HL		; Save pointer
	LD	HL, X3_ZJMP
	LD	B, 0
	LD	C, A
	ADD 	HL, BC
	LD	BC, (HL)	; Read in address
	PUSH	BC		; Push address of handler (for RET)
	LD	HL, DE		; Restore pointer
	LD	A, (HL)		; Reload instruction
	RET			; Jump to handler (indirect Jump)
	;------------------------
X2:	; ALU[y], r[z] ALU + register
	LD	A, (HL)
	CALL	EXTRACT_Y
	LD	BC, ALU
	CALL	PUSHINDEXED
	LD	A, OSEP
	CALL	PUSHCH
	LD	A, (HL)
	CALL	EXTRACT_Z
	LD	BC, REG8
	CALL	PUSHINDEXED
	JR	DONE
	;------------------------
X1:	; 8-bit loading. (Exception LD (HL), (HL) = HALT)
	LD	A, (HL)
	CP	$76		; 0166 - HALT
	JR	Z, HALT
	LD	BC, SLD
	CALL	PUSHSTROSEP
	CALL	EXTRACT_Y
	LD	BC, REG8
	CALL	PUSHINDEXED
	CALL	PUSHCOMMA
	LD	A, (HL)
	CALL	EXTRACT_Z
	LD	BC, REG8
	CALL	PUSHINDEXED
	JR	DONE
	;------------------------
X0:
	LD	A, (HL)		; Reload instruction
	CALL	EXTRACT_Z
	ADD	A		; Double for index
	LD	DE, HL
	LD	HL, X0_ZJMP
	LD	B, 0
	LD	C, A
	ADD 	HL, BC
	LD	BC, (HL)	; Read in address
	PUSH	BC		; Push address of handler (for RET)
	LD	HL, DE		; Restore pointer
	LD	A, (HL)		; Reload instruction
	RET			; Jump to handler
	;------------------------
DD_PRE:
FD_PRE:
	PUSH	AF
	LD	A, (PREFIX)
	AND	A
	JR	Z, ADDPREFIX
	; Double prefix, mark first as a NONI and return
	LD	BC, SNONI
	CALL	PUSHSTR
	POP	AF
	JR	DONE_NOINC
ADDPREFIX:
	POP	AF
	LD	(PREFIX), A	; Store new prefix
	INC	HL		; Re-start on next byte
	JP	START
#endlocal

DONE:
	INC	HL
DONE_NOINC:
	LD	A, 0		; Null terminate string
	CALL	PUSHCH	
	CALL	PREFIXADJUST	; Handle any $DD/$FD prefix changes
	RET			; Actual return
HALT:
	LD	BC, SHALT
PUSHDONE:			; Push string and be done
	CALL	PUSHSTR
	JR	DONE
DISP8:
	INC	HL
	LD	A, (HL)		; Read in signed displacement
	LD	C, A		
	RLA			; Rotate 'sign bit' into Carry
	SBC	A, A		; 0 if no carry, 0xFF if carry
	LD	B, A		; B is now sign extended C
	PUSH	HL		; Save current addr
	LD	HL, (STADDR)	; Load starting addr
	ADD	HL, BC		; Add displacement to get target addr
	LD	BC, HL		; Swap into BC
	POP	HL		; Restore curaddr
	CALL	PUSHHEX16	; Push target addr
	JR	DONE
IMM16:
	INC	HL
	LD	C, (HL)
	INC	HL
	LD	B, (HL)
	CALL	PUSHHEX16
	JR	DONE
IMM8:	
	INC	HL
	LD	B, (HL)
	CALL	PUSHHEX8
	JR	DONE

IMM8P:				; Imm8 with post string in BC
	PUSH	BC
	INC	HL
	LD	B, (HL)
	CALL	PUSHHEX8
	POP	BC
	CALL	PUSHSTR		
	JR	DONE
	
IMM16P:				; Imm16 with post string in BC
	PUSH	BC
	INC	HL
	LD	C, (HL)
	INC	HL
	LD	B, (HL)
	CALL	PUSHHEX16
	POP	BC
	CALL	PUSHSTR		
	JR	DONE


;--------
; Replace HL/H/L/(HL) with IX/IXH/IXL/(IX+d) or IY/IYH/IYL/(IY+d) if the
; prefix byte calls for it
;  
PREFIXADJUST:
#local
	LD	A, (PREFIX)
	AND	A
	RET	Z		; If no prefix, then no change
	CP	$DD
	JR	Z, XPRE		; Replace prefix byte with letter representation
YPRE:	LD	A, 'Y'
	JR	PRE
XPRE:	LD	A, 'X'
PRE:	LD	(PREFIX), A
	
	
	
	PUSH	HL		; Save next byte
	; Re-walk disline, skip to operands
	LD	HL, DISLINE
WALK:
	LD	A, (HL)
	INC	HL
	CP	OSEP		; Look for operand seperator
	JR	NZ, WALK
	; Now need to find occurances of HL/H/L/(HL)
WALK2:
	LD	A, (HL)
	CP	'H'
	JR	Z, FOUNDH
	CP	'L'
	JR	Z, FOUNDL
	CP	'('
	JR	Z, INDIR
	AND	A		; Null terminator
	JR	Z, END
NEXT:
	INC	HL
	JR	WALK2
FOUNDH:
	; Peek if this is HL
	INC	HL
	LD	A, (HL)
	DEC	HL
	CP	'L'
	JR	Z, FOUNDHL
FOUNDL:
	; Replace H/L with IXH/IYH or IXL/IYL
	CALL	PUSHGAP		; Moves H/L forward
	LD	A, (PREFIX)	; Get prefix letter X/Y
	LD	(HL), A		; Store prefix now XH/YH or XL/YL
	CALL	PUSHGAP
	LD	A, 'I'
	LD	(HL), A		; Now IXH/IYH or IXL/IYL
	JR	END
FOUNDHL:
	; Replace HL with IX or IY
	LD	A, 'I'
	LD	(HL), A		; Now IL
	INC	HL
	LD	A, (PREFIX)
	LD	(HL), A		; Now IX/IY
	JR	END
INDIR:
	INC	HL
	LD	A, (HL)
	CP	'H'		; Only care about (HL)
	JR	NZ, NEXT	; Something else, skip
	; We found (H, must be (HL)
	; Need to replace with (IX+d)
	LD	A, 'I'
	LD	(HL), A		; Now (IL)
	INC	HL
	LD	A, (PREFIX)
	LD	(HL), A		; Now (IX) or (IY)
	INC	HL
	CALL	PUSHGAP		; (IX )
	CALL	PUSHGAP		; (IX  )
	CALL	PUSHGAP		; (IX   )
	CALL	PUSHGAP		; (IX    )   Enough to fit (IX+$20) or (IX-$10)
	LD	(DISLINECUR), HL; Save pointer (byte after X/Y)
	POP	HL		; Restore byte pointer (we need a displacement
	LD	B, (HL)		; Displacement byte
	INC	HL
	PUSH	HL		; Save byte
	CALL	PUSHSIGNHEX8	; Push signed displacement
	; Fall into END
END:
	POP	HL		; Restore next byte
	RET
#endlocal


;--------
; Insert space into disline
;  HL - current spot, make space here, move forward till null
PUSHGAP:
#local
	PUSH	HL
	LD	A, (HL)		; Current spot
NEXT:
	INC	HL		; Next spot
	LD	B, (HL)		; Save next spot
	LD	(HL), A		; Save cur into next
	AND	A		; Check if we wrote the null
	JR	Z, FOUNDNULL	
	LD	A, B		; Make values from next the new cur
	JR	NEXT
FOUNDNULL:
	POP	HL		; Restore back to starting spot
	RET
#endlocal


;-------
; Extract p field from A
EXTRACT_P:
	; xx.PPx.xxx
	RRA			; xx.xPP.xxx
	RRA			; xx.xxP.Pxx
	RRA			; xx.xxx.PPx
	RRA			; xx.xxx.xPP
	AND	$03		; 00.000.0PP
	RET
;-------
; Extract y field from A
EXTRACT_Y:
	; xx.YYY.xxx
	RRA			; xx.xYY.Yxx
	RRA			; xx.xxY.YYx
	RRA			; xx.xxx.YYY
	AND	$07		; 00.000.YYY		
	RET

;--------
; Extract z field from A
EXTRACT_Z:
	AND	$07
	RET
	
;--------
; Pushes a string indexed from a string table
;  BC - String table
;  A  - index
PUSHINDEXED:
#local
	PUSH 	HL
	LD	HL, BC		
CHECK:	
	AND	A		; Check for end
	JR	Z, FOUND
	; Iterate to next string
ITEM:
	BIT	7, (HL)		; Check if end of string
	JR	NZ, ENDITEM
	INC	HL		; Iterate throught string
	JR	ITEM
ENDITEM:
	INC	HL
	DEC	A
	JR	CHECK
FOUND:
	LD	BC, HL
	POP	HL
	JP	PUSHSTR		; Tail call
#endlocal


;--------
; Push a high bit terminated string to buffer with operand seperator
;  BC - String
PUSHSTROSEP:
	CALL 	PUSHSTR
	PUSH	AF
	LD	A, OSEP
	CALL	PUSHCH
	POP	AF
	RET
	

;--------
; Push a high bit terminated string to buffer with space after
;  BC - String
PUSHSTRSP:
	CALL 	PUSHSTR
	PUSH	AF
	CALL	PUSHSP
	POP	AF
	RET
	
	
; Push a space to the buffer
PUSHSP:	
	LD	A, ' '
	; Fall into PUSHCH
;--------
; Push individual char (A) into buffer
PUSHCH:
	PUSH 	HL
	LD	HL, (DISLINECUR)
	LD	(HL), A			; Store character
	INC 	HL
	LD	(DISLINECUR), HL
	POP	HL
	RET
	
;-------
; Push a high bit terminated string to buffer 
;  BC - String
PUSHSTR:
#local
	PUSH	AF
	PUSH	HL
	LD	HL, (DISLINECUR); Pointer to current char
SLOOP:	
	LD	A, (BC)		; Read in character
	AND	$7F		; Mask off high bit
	LD	(HL), A		; Store to line
	INC 	HL
	LD	A, (BC)		; Reread character
	AND	$80		; Test high bit of string
	JR	NZ, DONE
	INC	BC		; Next character of string
	JR	SLOOP
DONE:
	LD	(DISLINECUR), HL
	POP	HL
	POP	AF
	RET
#endlocal

	

;--------
; Push argument seperator
PUSHCOMMA:
	LD	BC, SCOMMA
	JP	PUSHSTRSP
	
;-------
; Print a single digit decimal 0-9
PUSHDEC1:
	PUSH 	HL
	ADD	'0'
	LD	HL, (DISLINECUR)
	LD	(HL), A
	INC	HL
	LD	(DISLINECUR), HL
	POP	HL
	RET

	

;--------
; Print a 1-byte hex number as signed with sign prefix + or -
PUSHSIGNHEX8:
#local
	LD	A, B
	AND	A
	JP	P, POS
NEG:
	LD	A, '-'
	CALL	PUSHCH
	LD	A, B
	NEG			; Convert from negative to positive
	LD	B, A
	JR	PUSHHEX8	; Tail call push number
POS:
	LD	A, '+'
	CALL	PUSHCH
	JR	PUSHHEX8	; Tail call, push number
#endlocal


;--------
; Print a 1-byte hex number
;  B - number
PUSHHEX8:
	LD	A, '$'
	CALL	PUSHCH
PUSHHEX8_NP:
	LD	A, B
	SRL	A
	SRL	A
	SRL	A
	SRL	A	; Extract high nybble
	CALL	PUSHNYB
	LD	A, B
	AND	$0F
	; Fall into PUSHNYB (Tail call)
;--------
; Push a nybble from A (low 4-bits, high must be 0)
PUSHNYB:
#local
	ADD	'0'
	CP	'9'+1	; Check if A-F
	JR	C, NOFIX
	ADD	'A'-('9'+1)	; Diff between 'A' and ':'
NOFIX:
	JP	PUSHCH		; Tail call
#endlocal
	
	
;--------
; Print a 2-byte hex number
;  BC - number
PUSHHEX16:
	CALL	PUSHHEX8
	LD	B, C
	JP	PUSHHEX8_NP	; Tail call



	
;---------------------------------------
; X0 decodes
;---------------------------------------

;----------
; Relative jumps and assorted	00.xxx.000
RELASS:
#local
	AND	$38		; Grab y (2nd octal)
	JR	Z, NOP		; 00.000.000 = NOP
	CP	$08		
	JR	Z, EXAFAF	; 00.001.000 = EX AF, AF'
	CP	$10		
	JR	Z, DJNZ		; 00.010.000 = DJNZ
	CP	$18
	JR	Z, JRUN		; 00.011.000 = JR d
	; 00.1xx.000 = JR cc[xx],  d
JRCC:
	LD	BC, SJR
	CALL	PUSHSTROSEP
	LD	A, (HL)
	CALL	EXTRACT_Y
	AND	$03		; y-4
	LD	BC, CC		; Condition codes
	CALL	PUSHINDEXED
	CALL	PUSHCOMMA
	JP	DISP8
NOP:
	LD	BC, SNOP
	JP	PUSHDONE	; No operands
EXAFAF:
	LD	BC, SEXAFAF
	JP	PUSHDONE
DJNZ:
	LD	BC, SDJNZ
	CALL	PUSHSTROSEP
	JP	DISP8		; 8 bit displacement
JRUN:
	LD	BC, SJR
	CALL	PUSHSTROSEP
	JP	DISP8		; 8 bit displacement
#endlocal

;--------
; 16-bit load imm. / add to HL
LD16ADD:
#local
	CALL	EXTRACT_P	; Extract P field
	BIT	3, (HL)		; Test q 00.xxq.001
	JR	Z, LD16
	; Fall into ADD HL
ADDHL:				; Add to HL
	LD	BC, SADDHL
	CALL	PUSHSTRSP
	LD	BC, REG16	
	CALL	PUSHINDEXED
	JP	DONE
LD16:				; 16-bit load immediate
	LD	BC, SLD
	CALL	PUSHSTROSEP
	LD	BC, REG16
	CALL	PUSHINDEXED
	CALL	PUSHCOMMA
	JP	IMM16
#endlocal

;--------
; Indirect loading
INDIR:
#local
	BIT	3, A		; Test q
	JR	NZ, FROMMEM
	; To MEM
	LD	BC, SLDIN
	CALL	PUSHSTR
	CALL	EXTRACT_P
	CP	2
	JR	C, TOREG
	; To indirect mem
	CP	3
	JR	Z, FROMHL
	; From A
	LD	BC, SEA		; q=0 p=3
	JP	IMM16P
;-------------------
FROMHL:
	LD	BC, SEHL	; q=0 p=2
	JP	IMM16P
;-------------------
TOREG:
	AND	$01		; q=0 p=0/1
	LD	BC, REG16
	CALL	PUSHINDEXED	; LD (BC), A and LD (DE), A
	LD	BC, SEA
	CALL	PUSHSTR
	JP	DONE
;-------------------
FROMMEM:			; q=1
	CALL	EXTRACT_P
	CP	2
	JP	Z, TOHL
	LD	BC, SLDAIN
	CALL	PUSHSTRSP
	CP	2
	JP	C, FROMREG
	; LD A, (nn)
	LD	BC, SEBKT
	JP	IMM16P
;-------------------
TOHL:				; LD HL, (nn)
	LD	BC, SLDHLIN
	CALL	PUSHSTR
	LD	BC, SEBKT
	JP	IMM16P
;-------------------
FROMREG:
	AND	$01
	LD	BC, REG16
	CALL	PUSHINDEXED
	LD	BC, SEBKT
	CALL	PUSHSTR
	JP	DONE
;-------------------
#endlocal

;--------
; INC and DEC 16-bit regs
INCDEC16:
#local
	BIT	3, A		; Test q
	JR	NZ, DEC16
INC16:
	LD	BC, SINC
	CALL	PUSHSTROSEP
	JR	REG
DEC16:	
	LD	BC, SDEC
	CALL	PUSHSTROSEP
REG:
	CALL	EXTRACT_P	; Extract reg #
	LD	BC, REG16	; RP
	CALL	PUSHINDEXED
	JP	DONE	
#endlocal

;--------
; INC 8-bit regs
INC8:
	LD	BC, SINC
	JR	IDCOMMON
;--------
; DEC 8-bit regs
DEC8:
	LD	BC, SDEC
IDCOMMON:
	CALL	PUSHSTROSEP
	CALL	EXTRACT_Y
	LD	BC, REG8
	CALL	PUSHINDEXED
	JP	DONE

;--------
; LD 8-bit immediate
LDI8:
	LD	BC, SLD
	CALL	PUSHSTROSEP
	CALL	EXTRACT_Y
	LD	BC, REG8
	CALL	PUSHINDEXED
	CALL	PUSHCOMMA
	JP	IMM8


;--------
; Assorted Accumulator and Flags
ASSAF:
	CALL	EXTRACT_Y
	LD	BC, AAF
	CALL	PUSHINDEXED
	JP	DONE

;---------------------------------------
; X3 decodes
;---------------------------------------

;--------
; Return with condition
RETCC:
	LD	BC, SRET
	CALL	PUSHSTROSEP
	CALL	EXTRACT_Y
	LD	BC, CC
	CALL	PUSHINDEXED
	JP	DONE
	
;--------
; POP and various
POPVAR:
#local
	BIT	3, A		; Test Q
	JR	NZ, VARIOUS
	; POP rp2[p]
	LD	BC, SPOP
	CALL	PUSHSTROSEP
	CALL	EXTRACT_P
	LD	BC, REG16_2
	CALL	PUSHINDEXED
	JP	DONE
VARIOUS:
	CALL 	EXTRACT_P
	LD	BC, VARIOUSTBL
	CALL	PUSHINDEXED
	JP	DONE
#endlocal

;--------
; Conditional Jump
JPCC:
	LD	BC, SJP
	CALL	PUSHSTROSEP
	CALL	EXTRACT_Y
	LD	BC, CC
	CALL	PUSHINDEXED
	CALL	PUSHCOMMA
	JP	IMM16


;--------
; Assorted 
X3ASS:
#local
	CALL	EXTRACT_Y
	AND	A
	JR	Z, JPIMM
	CP	2
	JR	Z, OUT8
	CP	3
	JR	Z, IN8
	; 1 is $CB prefix, ignored. 4-7 are simple
	CP	5 		; EX DE, HL is special in that DD/FD doesn't affect
	JR	NZ, NOADJ
	PUSH	AF
	XOR	A
	LD	(PREFIX), A	; Pretend like we had no prefix byte if we're EX DE, HL
	POP	AF
NOADJ:
	AND	3		; Turn 4-7 to 0-3
	LD	BC, X3ASSTBL
	CALL	PUSHINDEXED
	JP	DONE
JPIMM:
	LD	BC, SJP
	CALL	PUSHSTROSEP
	JP	IMM16
OUT8:
	LD	BC, SOUT
	CALL	PUSHSTR
	LD	BC, SEOUT
	JP	IMM8P
IN8:
	LD	BC, SIN
	CALL	PUSHSTR
	LD	BC, SEBKT
	JP	IMM8P
#endlocal


;--------
; Call with CC
CCCALL:
	CALL	EXTRACT_Y
	LD	BC, SCALL
	CALL	PUSHSTROSEP
	LD	BC, CC
	CALL	PUSHINDEXED
	CALL	PUSHCOMMA
	JP	IMM16


;--------
; Push and Call/various
PUSHVAR:
#local
	BIT	3, A		; Test Q
	JP	Z, PUSH
	; p = 0. (1-3 are DD, ED, and FD prefixes)
	LD	BC, SCALL
	CALL	PUSHSTROSEP
	JP	IMM16	
PUSH:
	LD	BC, SPUSH
	CALL	PUSHSTROSEP
	CALL 	EXTRACT_P
	LD	BC, REG16_2
	CALL	PUSHINDEXED
	JP	DONE
#endlocal

;--------
; ALU immediate with A
ALUIMM:
	CALL	EXTRACT_Y
	LD	BC, ALU
	CALL	PUSHINDEXED
	LD	A, OSEP
	CALL	PUSHCH
	JP	IMM8
	
;--------
; Restart opcodes
RESTART:
	CALL	EXTRACT_Y
	LD	BC, SRESET
	CALL	PUSHSTROSEP
	ADD	A		; Y*2
	ADD	A		; Y*4
	ADD	A		; Y*8
	CALL	PUSHHEX8
	JP	DONE
;---------------------------------------




;--------
; CB prefixed opcodes
CB_PRE:
#local
	LD	A, (PREFIX)
	AND	A
	JR	NZ, PRE_CB_PRE
	INC	HL		; Read in opcode
	LD	A, (HL)
	AND	$C0		; Test X only
	JR	Z, X0
	CP	$40
	JR	Z, X1
	CP	$80
	JR	Z, X2
	; Fall into X3
X3:
	LD	BC, SBIT
COMMON:
	CALL	PUSHSTROSEP
	LD	A, (HL)
	CALL	EXTRACT_Y
	CALL	PUSHDEC1
	CALL	PUSHCOMMA
COMMON2:
	LD	A, (HL)
	CALL	EXTRACT_Z
	LD	BC, REG8
	CALL	PUSHINDEXED
	JP	DONE
X2:
	LD	BC, SRES
	JR	COMMON
X1:
	LD	BC, SSET
	JR	COMMON
X0:
	LD	A, (HL)
	CALL	EXTRACT_Y
	LD	BC, ROT
	CALL	PUSHINDEXED
	JR	COMMON2
#endlocal
;---------------------------------------

;--------
; Prefixed CB - Order is now PRE.CB.DISP.OP 
;		instead of   CB.OP
; Includes oddball illegal opcodes, doesn't use standard DONE termination
PRE_CB_PRE:
#local
	INC	HL
	LD	A, (HL)		; Read in displacement
	LD	(SVDISP), A	; Save displacement
	INC	HL		
	LD	A, (HL)		; Read in opcode
	AND	$C0		; Test X only
	JR	Z, X0
	CP	$40
	JR	Z, X1
	CP	$80
	JR	Z, X2
	; Fall into X3
X3:	; SET opcodes
	CALL	EXTESTZ6
	JR	Z, X3_6
	; Opcodes of form LD r[z], SET y, (IX+d)
	CALL	PUSHLDRZ
X3_6:	; No side-effect load
	LD	BC, SSET
X2X3COM:
	CALL	PUSHSTROSEP	
	LD	A, (HL)		; Reload opcode
	CALL	EXTRACT_Y
	CALL	PUSHDEC1	; Bit #
	CALL	PUSHCOMMA
	JR	INDEX_D
;--------
X2:	; RES opcodes
	CALL	EXTESTZ6
	JR	Z, X2_6
	; Opcodes of form LD r[z], RES y, (IX+d)
	CALL	PUSHLDRZ
X2_6:	; No side-effect load
	LD	BC, SRES
	JR	X2X3COM
;--------
X1:	; BIT opcodes
	LD	BC, SBIT
	CALL	PUSHSTROSEP
	LD	A, (HL)		; Reload opcode
	CALL	EXTRACT_Y
	CALL	PUSHDEC1	; Bit #
	CALL	PUSHCOMMA
	CALL	EXTESTZ6
	JR	Z, INDEX_D	; If would be (HL), push (IX/IY+d) instead
	LD	BC, REG8
	CALL	PUSHINDEXED	; r[z]
	JR	EXIT
;--------
X0:	; Rotate opcodes
	CALL	EXTESTZ6
	JR	Z, X0_6
	; Opcodes of form LD r[z], rot[y] (IX+d)
	CALL	PUSHLDRZ
X0_6:	; No side-effect load
	LD	A, (HL)
	CALL	EXTRACT_Y
	LD	BC, ROT		; rot[y]
	CALL	PUSHINDEXED
	; Fall into INDEX_D
;--------
INDEX_D:	; Push (IX/IY+d)
	LD	BC, SBKTI
	CALL	PUSHSTR
	LD	A, (PREFIX)
	CP	$DD
	JR	Z, IXPRE
IYPRE:	LD	A, 'Y'
	JR	INDEXCOM
IXPRE:	LD	A, 'X'
INDEXCOM:
	CALL	PUSHCH
	LD	A, (SVDISP)
	LD	B, A
	CALL	PUSHSIGNHEX8
	LD	A, ')'
	CALL	PUSHCH
EXIT:
	INC	HL		; Next byte
	LD	A, 0
	CALL	PUSHCH		; Push null terminator
	RET			; Exit DISINST
;--------
; Z in A already, helper subroutine
PUSHLDRZ:
	LD	BC, SLD
	CALL	PUSHSTRSP	; SP here since real op has OSEP
	LD	BC, REG8	; r[z]
	CALL	PUSHINDEXED
	JP	PUSHCOMMA	; Tail call
;--------
EXTESTZ6:
	LD	A, (HL)		; Reload opcode
	CALL	EXTRACT_Z
	CP	6		; 6 would have been (HL), normal 'legal' opcode
	RET
#endlocal
;---------------------------------------

;--------
; ED prefixed opcodes
ED_PRE:
#local
	; Check for invalid prefix combo
	LD	A, (PREFIX)
	AND	A
	JR	Z, NOPRE
	; Otherwise push out NONI for the invalid prefix 
	; Next entry will re-read the ED with no prefix
	LD	BC, SNONI
	CALL	PUSHSTR
	LD	A, 0		; Null terminate string
	CALL	PUSHCH
	RET			; Ret from DISINST
NOPRE:
	INC	HL		; Read in opcode
	LD	A, (HL)
	AND	$C0		; Test X only
	JR	Z, X0
	CP	$40
	JR	Z, X1
	CP	$80
	JR	Z, X2
	; Fall into X3
X3:	; Invalid (NONI+NOP)
X0:	; Invalid (NONI+NOP)
X2INVAL:; Invalid (NONI+NOP)
	LD	BC, SINVAL
	CALL	PUSHSTR
	JP	DONE
X1:
	LD	A, (HL)
	CALL	EXTRACT_Z
	ADD	A		; Double for index
	LD	DE, HL
	LD	HL, EDX1_ZJMP
	LD	B, 0
	LD	C, A
	ADD 	HL, BC
	LD	BC, (HL)	; Read in address
	PUSH	BC		; Push address of handler (for RET)
	LD	HL, DE		; Restore pointer
	LD	A, (HL)		; Reload instruction
	RET			; Jump to handler
X2:	; Block instructions
	LD	A, (HL)
	CALL	EXTRACT_Y
	CP	4
	JR	C, X2INVAL	; y < 4 invalid
	AND	3		; y-4
	ADD	A		; Y*2
	ADD	A		; Y*4
	LD	B, A		; Save
	LD	A, (HL)
	CALL	EXTRACT_Z
	ADD	B		; z + y*4 
	LD	BC, BLI
	CALL	PUSHINDEXED
	JP	DONE
#endlocal

;--------
; In port from 16-addr
INP16:
#local
	CALL	EXTRACT_Y
	CP	6
	JR	Z, NOREG
	; IN r[y], (C)
	LD	BC, SINP
	CALL	PUSHSTROSEP
	LD	BC, REG8
	CALL	PUSHINDEXED
	CALL	PUSHCOMMA
	LD	BC, SINDC
	CALL	PUSHSTR
	JP	DONE
NOREG:
	LD	BC, SINNOC
	CALL	PUSHSTR
	JP	DONE
#endlocal
	
;--------
; Output port 16-bit addr	
OUTP16:
#local
	CALL	EXTRACT_Y
	CP	6
	JR	Z, NOREG
	; OUT (C), r[y]
	LD	BC, SOUTC
	CALL	PUSHSTRSP
	LD	BC, REG8
	CALL	PUSHINDEXED
	JP	DONE
NOREG:
	LD	BC, SOUTNOC
	CALL	PUSHSTR
	JP	DONE
#endlocal

 

;--------
; Add/sub with carry 16-bit
ADCSBC16:
#local
	BIT	3, A		; Extract q
	JR	NZ, ADC16
SBC16:
	LD	BC, SSBCHL
	CALL	PUSHSTRSP
	JR	COMMON
ADC16:
	LD	BC, SADCHL
	CALL	PUSHSTRSP
COMMON:
	CALL	EXTRACT_P
	LD	BC, REG16
	CALL	PUSHINDEXED
	JP	DONE
#endlocal


;--------
; Load/Store register pair to imm16
RPIMM:
#local
	BIT	3, A		; Extract q
	JR	NZ, LOAD
STORE:
	LD	BC, SLDIN
	CALL	PUSHSTR
	; Special case, we're going to have to grab
	; the immediate 16-bit value ourselves since
	; the IMM16P helper can't handle a calculated suffix
	PUSH	AF
	INC	HL
	LD	C, (HL)
	INC	HL
	LD	B, (HL)
	CALL	PUSHHEX16
	POP	AF
	LD	BC, SBKTC
	CALL	PUSHSTR
	CALL	EXTRACT_P
	LD	BC, REG16
	CALL	PUSHINDEXED
	JP	DONE
LOAD:
	LD	BC, SLD
	CALL	PUSHSTROSEP
	CALL	EXTRACT_P
	LD	BC, REG16
	CALL	PUSHINDEXED
	LD	BC, SCOMBKT
	CALL	PUSHSTR
	LD	BC, SEBKT
	JP	IMM16P
#endlocal

;--------
; Negate A
NEGA:
	LD	BC, SNEG
	CALL	PUSHSTR
	JP	DONE

;--------
; Return from interrupt	
RETINT:
#local
	CALL	EXTRACT_Y
	CP	1
	JP	Z, RETI
RETN:
	LD	BC, SRETN
	JR	COMMON
RETI:
	LD	BC, SRETI
COMMON:
	CALL	PUSHSTR
	JP	DONE
#endlocal

;--------
; Set interrupt mode
SETI:
	LD	BC, SIM
	CALL	PUSHSTROSEP
	CALL	EXTRACT_Y
	LD	BC, IM
	CALL	PUSHINDEXED
	JP	DONE
	
;--------
; ED assorted
EDASSORT:
#local
	CALL	EXTRACT_Y
	CP	4
	JR	NC, NOLD
	LD	BC, SLD
	CALL	PUSHSTROSEP
NOLD:
	LD	BC, EDASSTBL
	CALL	PUSHINDEXED
	JP	DONE
#endlocal
;---------------------------------------
	
OSEP	equ $09	;TAB
	
X0_ZJMP:
	DW RELASS		; 00 ... 000
	DW LD16ADD		; 00 ... 001
	DW INDIR		; 00 ... 010
	DW INCDEC16		; 00 ... 011
	DW INC8			; 00 ... 100
	DW DEC8			; 00 ... 101
	DW LDI8			; 00 ... 110
	DW ASSAF		; 00 ... 111

X3_ZJMP:
	DW RETCC		; 11 ... 000
	DW POPVAR		; 11 ... 001
	DW JPCC			; 11 ... 010
	DW X3ASS		; 11 ... 011
	DW CCCALL		; 11 ... 100
	DW PUSHVAR		; 11 ... 101
	DW ALUIMM		; 11 ... 110
	DW RESTART		; 11 ... 111
	
EDX1_ZJMP:
	DW INP16
	DW OUTP16
	DW ADCSBC16
	DW RPIMM
	DW NEGA
	DW RETINT
	DW SETI
	DW EDASSORT
	
	
X3ASSTBL:
	DM "EX",OSEP,"(SP), HL"+$80
	DM "EX",OSEP,"DE, HL"+$80
	DM "DI"+$80
	DM "EI"+$80
	
VARIOUSTBL:
SRET:	DM "RET"+$80
	DM "EXX"+$80
	DM "JP",OSEP,"HL"+$80
	DM "LD",OSEP,"SP, HL"+$80
	
EDASSTBL:
	DM "I, A"+$80 ; Already prefixed by LD
	DM "R, A"+$80 ; "
	DM "A, I"+$80 ; "
	DM "A, R"+$80 ; "
	DM "RRD"+$80
	DM "RLD"+$80
	DM "NOP"+$80
	DM "NOP"+$80
	
SLD:	DM "LD"+$80
SHALT:	DM "HALT"+$80
SNOP:	DM "NOP"+$80
SDJNZ:	DM "DJNZ"+$80
SEXAFAF:DM "EX",OSEP,"AF, AF'"+$80
SJR:	DM "JR"+$80
SJP:	DM "JP"+$80
SADDHL:	DM "ADD",OSEP,"HL,"+$80
SINC:	DM "INC"+$80
SDEC:	DM "DEC"+$80
SPOP:	DM "POP"+$80
SOUT:	DM "OUT",OSEP,"("+$80
SEOUT:	DM "), A"+$80
SIN:	DM "IN",OSEP,"A, ("+$80
SINP:	DM "IN"+$80
SEBKT:	DM ")"+$80
SCALL:	DM "CALL"+$80
SPUSH:	DM "PUSH"+$80
SNEG:	DM "NEG"+$80
SRETI:	DM "RETI"+$80
SRETN:	DM "RETN"+$80
SIM:	DM "IM"+$80
SBIT:	DM "BIT"+$80
SRES:	DM "RES"+$80
SSET:	DM "SET"+$80
SINVAL:	DM "INVALID"+$80
SNONI:	DM "NONI"+$80

SBKTC:	DM ")" ; Fall into SCOMMA
SCOMMA:	DM ","+$80

SRESET: DM "RST"+$80
SLDIN:	DM "LD",OSEP,"("+$80
SLDHLIN:DM "LD",OSEP,"HL, ("+$80
SLDAIN: DM "LD",OSEP,"A" ; Fall into SCOMBKT
SCOMBKT:DM ", ("+$80
SEHL:	DM "), HL"+$80
SEA:	DM "), A"+$80
SINNOC:	DM "IN",OSEP,"(C)"+$80
SINDC:	DM "(C)"+$80
SOUTNOC:DM "OUT",OSEP,"(C), 0"+$80
SOUTC:	DM "OUT",OSEP,"(C),"+$80
SSBCHL:	DM "SBC",OSEP,"HL,"+$80
SADCHL:	DM "ADC",OSEP,"HL,"+$80
SBKTI:	DM "(I"+$80
AAF:
	DM "RLCA"+$80
	DM "RRCA"+$80
	DM "RLA"+$80
	DM "RRA"+$80
	DM "DAA"+$80
	DM "CPL"+$80
	DM "SCF"+$80
	DM "CCF"+$80

REG8:
	DM "B"+$80
	DM "C"+$80
	DM "D"+$80
	DM "E"+$80
	DM "H"+$80
	DM "L"+$80
	DM "(HL)"+$80
	DM "A"+$80
REG16:
SBC:	DM "BC"+$80
SDE:	DM "DE"+$80
	DM "HL"+$80
	DM "SP"+$80
REG16_2:
	DM "BC"+$80
	DM "DE"+$80
	DM "HL"+$80
	DM "AF"+$80
CC:
	DM "NZ"+$80
	DM "Z"+$80
	DM "NC"+$80
	DM "C"+$80
	DM "PO"+$80
	DM "PE"+$80
	DM "P"+$80
	DM "M"+$80
ALU:
	DM "ADD",OSEP,"A,"+$80
	DM "ADC",OSEP,"A,"+$80
	DM "SUB"+$80
	DM "SBC",OSEP,"A,"+$80
	DM "AND"+$80
	DM "XOR"+$80
	DM "OR"+$80
	DM "CP"+$80
ROT:
	DM "RLC",OSEP+$80
	DM "RRC",OSEP+$80
	DM "RL",OSEP+$80
	DM "RR",OSEP+$80
	DM "SLA",OSEP+$80
	DM "SRA",OSEP+$80
	DM "SLL",OSEP+$80
	DM "SRL",OSEP+$80
IM:
	DM "0"+$80
	DM "0/1"+$80
	DM "1"+$80
	DM "2"+$80
	DM "0"+$80
	DM "0/1"+$80
	DM "1"+$80
	DM "2"+$80

BLI:
	DM "LDI"+$80 ; Y = 4
	DM "CPI"+$80 
	DM "INI"+$80 
	DM "OUTI"+$80
	DM "LDD"+$80 ; Y = 5
	DM "CPD"+$80 
	DM "IND"+$80 
	DM "OUTD"+$80
	DM "LDIR"+$80 ; Y = 6
	DM "CPIR"+$80 
	DM "INIR"+$80 
	DM "OTIR"+$80
	DM "LDDR"+$80 ; Y = 7
	DM "CPDR"+$80 
	DM "INDR"+$80 
	DM "OTDR"+$80	

DISASSLEN	equ . - DISINST
