
#data _RAM

LBA:		DS 4	; 4-byte (28-bit) little-endian LBA address for CF
SECTOR:		DS 512 	; Sector buffer


#code _ROM


;---------------------------------------
; Init CF card
;  Will work even if a card is not present, since LBUSY will get a zero
;  from the pulldowns and return
CF_INIT::
	CALL	CF_LBUSY
	LD	A, 0x01		; 8-bit mode
	OUT	(CF_FEAT_ERR), A; Write to features reg
	CALL	CF_LBUSY
	LD	A, 0xEF		; Set features command
	OUT	(CF_CMD_STAT), A	
	CALL	CF_LBUSY
	LD	A, 0x01		; 1 sector to read
	OUT	(CF_COUNT), A
	CALL	CF_LBUSY
	
	CALL	DELAY_MS
	
	LD	A, 0x01		; 8-bit mode
	OUT	(CF_FEAT_ERR), A; Write to features reg
	CALL	CF_LBUSY
	LD	A, 0xEF		; Set features command
	OUT	(CF_CMD_STAT), A	
	CALL	CF_LBUSY
	LD	A, 0x01		; 1 sector to read
	OUT	(CF_COUNT), A
	
	CALL	DELAY_MS
	
	LD	A, 0x01		; 8-bit mode
	OUT	(CF_FEAT_ERR), A; Write to features reg
	CALL	CF_LBUSY
	LD	A, 0xEF		; Set features command
	OUT	(CF_CMD_STAT), A	
	CALL	CF_LBUSY
	LD	A, 0x01		; 1 sector to read
	OUT	(CF_COUNT), A
	
	CALL	DELAY_MS
	
	LD	A, 0x01		; 8-bit mode
	OUT	(CF_FEAT_ERR), A; Write to features reg
	CALL	CF_LBUSY
	LD	A, 0xEF		; Set features command
	OUT	(CF_CMD_STAT), A	
	CALL	CF_LBUSY
	LD	A, 0x01		; 1 sector to read
	OUT	(CF_COUNT), A
	RET
;---------------------------------------


;---------------------------------------
; Detect if a CF card is actually present
; NZ if drive present
CF_DETECT:
	IN	A, (CF_CMD_STAT) ; If all bits of the status register are 0
	AND	A		; Then there is likely no device present
	RET

	
	
;---------------------------------------	
; Loops till CF card is not busy
CF_LBUSY:
	IN	A, (CF_CMD_STAT)
	AND	0x80		; High bit indicates busy
	JP	NZ, CF_LBUSY
	RET
;---------------------------------------

;---------------------------------------
; Loops till CF card is not busy and ready for commands
CF_LRDY:
	IN	A, (CF_CMD_STAT)
	AND	0xC0		; High bit indicates busy, bit 6 (high when rdy)
	XOR	0x40		; Invert bit 6
	JP	NZ, CF_LRDY
	RET
;---------------------------------------

;---------------------------------------
; Loops till CF card is not busy and has data ready (or is ready for data)
CF_LDATARDY:
	IN	A, (CF_CMD_STAT)
	LD	D, A
	
	AND	0x88		; High bit indicates busy, bit 3 (high when rdy)
	XOR	0x08		; Invert bit 3
	JP	NZ, CF_LDATARDY
	RET	
;---------------------------------------


;---------------------------------------
; Reads one 512-byte sector to RAM
; HL - Address to start storing to
; Var LBA: - 28 bit LBA address to read from
CF_READ::
#local
TRY:	
	CALL	CF_LBUSY	; Load LBA address to access
	LD	A, (LBA+0)
	OUT	(CF_LBA0), A
	CALL	CF_LBUSY
	LD	A, (LBA+1)
	OUT	(CF_LBA1), A
	CALL	CF_LBUSY
	LD	A, (LBA+2)
	OUT	(CF_LBA2), A
	CALL	CF_LBUSY
	LD	A, (LBA+3)
	OR	0xE0		; Set high bits to indicate LBA mode
	OUT	(CF_LBA3), A
	
	CALL	CF_LBUSY
	LD	A, 0x01		; 1 sector to read
	OUT	(CF_COUNT), A

	CALL	CF_LRDY
	LD	A, 0x20		; Read sector
	OUT	(CF_CMD_STAT), A		
	CALL	CF_LDATARDY	; Wait for data
	
	
	LD	A, (CF_CMD_STAT); Check status
	AND	0x01		; Check error bit
	;JP	NZ, TRY
	; FOR SOME REASON ERROR IS BEING SET EVEN WITH NO ERROR
	
	
	PUSH	HL		; Save start address
	LD	B, 0		; Read 256 words/512 bytes
LOOP:
	CALL	CF_LDATARDY	; Read even byte
	IN	A, (CF_DATA)
	LD	(HL), A
	INC 	HL

	CALL	CF_LDATARDY	; Read odd byte
	IN	A, (CF_DATA)
	LD	(HL), A
	INC 	HL
	
	DJNZ	LOOP
	
	POP	HL		; Restore start address
	RET
#endlocal

;---------------------------------------
; Write one 512-byte sector to disk
; HL - Address to start reading from
; Var LBA: - 28 bit LBA address to write to
CF_WRITE::
#local
TRY:	
	CALL	CF_LBUSY	; Load LBA address to access
	LD	A, (LBA+0)
	OUT	(CF_LBA0), A
	CALL	CF_LBUSY
	LD	A, (LBA+1)
	OUT	(CF_LBA1), A
	CALL	CF_LBUSY
	LD	A, (LBA+2)
	OUT	(CF_LBA2), A
	CALL	CF_LBUSY
	LD	A, (LBA+3)
	OR	0xE0		; Set high bits to indicate LBA mode
	OUT	(CF_LBA3), A
	
	CALL	CF_LBUSY
	LD	A, 0x01		; 1 sector to write
	OUT	(CF_COUNT), A

	CALL	CF_LRDY
	LD	A, 0x30		; Write sector
	OUT	(CF_CMD_STAT), A		
	CALL	CF_LDATARDY	; Wait for data
	
	
	LD	A, (CF_CMD_STAT); Check status
	AND	0x01		; Check error bit
	;JP	NZ, TRY
	; FOR SOME REASON ERROR IS BEING SET EVEN WITH NO ERROR
	
	
	PUSH	HL		; Save start address
	LD	B, 0		; Write 256 words/512 bytes
LOOP:
	CALL	CF_LDATARDY	; Write even byte
	LD	A, (HL)
	OUT	(CF_DATA), A
	INC 	HL

	CALL	CF_LDATARDY	; Read odd byte
	LD	A, (HL)
	OUT	(CF_DATA), A
	INC 	HL
	
	DJNZ	LOOP
	
	POP	HL		; Restore start address
	RET
#endlocal
