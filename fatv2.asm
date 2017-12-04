

#data _RAM
; Parameters
FAT_CLUSTER	DS	4	; Custer to index (Little endian, 12, 16 or 32-bit)
FAT_CURSECT	DS	1	; Current sector within cluster
FAT_CLUSTLBA 	DS	4	; LBA of current cluster sector


; Calculated values
FAT_TYPE	DS	1	; Fat type. 12, 16, or 32
BPB_VER		DS	1	; BPB type. 34 (for 3.4) 40 (for 4.0) or 70 (for 7.0)	
FAT_CLUSTCNT	DS	4	; Number of clusters in volume	
FAT_SECTROOT	DS	3	; Number of sectors for fixed root directory
				; Max would be 4097 (for 65535 dirents)
				; But for calc, we might overflow 16-bit
FAT_DATASTART	DS	4	; Starting sector for data (first cluster)
FAT_ROOTLBA	DS	4	; LBA of Root directory if fixed

; Boot Parameter Block, read from disk
BPB_OFFSET	EQU	0x0B	; Offset from start of boot sector
; BPB 2.0 table
FAT_SECTSIZ	DS	2	; Bytes per sector
FAT_CLUSTSIZ	DS	1	; Sectors per cluster
FAT_RESVSECT	DS	2	; Reserved sectors
FAT_NFATS	DS	1	; Number of fats
FAT_DIRENTS	DS	2	; Root directory entries
FAT_TSECT	DS	2	; Total sectors 
FAT_MEDIA	DS	1	; Media byte
FAT_SECTFAT	DS	2	; Sectors per FAT if 0 then use FAT_SECTFAT32
; BPB 3.4 additions
FAT_SECTTRCK	DS	2	; Sectors per Track
FAT_NHEADS	DS	2	; Number of heads
FAT_HIDSECT	DS	4	; Number of hidden sectors
FAT_LGTSECT	DS	4	; Large total sectors (If TSECT=0)
BPB_SIZ		EQU	. - FAT_SECTSIZ
; Skipping some fields that we don't care about
; From BPB 7.0
FAT_SECTFAT32	DS	4	; 32-bit sectors per FAT
O_SECTFAT32	EQU	0x24
FAT_ROOTCLUS	DS	4	; Root directory start cluster (FAT32)
O_ROOTCLUS	EQU	0x2C

; At different location depending on BPB
FAT_VOLID	DS	4	; Volume ID
O_VOLID40	EQU	0x27	; For BPB 4.0
O_VOLID70	EQU	0x43	; For BPB 7.0
FAT_VOLLBL	DS	11	; Volume Label
O_VOLLBL40	EQU	0x2B	; For BPB 4.0
O_VOLLBL70	EQU	0x47	; For BPB 7.0

#code _ROM

FAT_INIT:
#local
	XOR	A		
	LD	(LBA+0), A
	LD	(LBA+1), A
	LD	(LBA+2), A
	LD	(LBA+3), A	
	LD	HL, SECTOR	
	CALL	CF_READ		; Read in the boot sector

	; For now we'll assume that the the volume has no partition table
	; and is formatted as FAT
	; We'll be using https://jdebp.eu/FGA/determining-fat-widths.html
	; as a guide to determine BPB type and FAT type
	
	; First load in the BPB 3.4 table as it's common to the others
	LD	HL, SECTOR+BPB_OFFSET	
	LD	DE, FAT_SECTSIZ
	LD	BC, BPB_SIZ
	LDIR			; Copy relevant BPB 3.4 into variables
	
	XOR	A
	LD	(FAT_TYPE), A
	LD	(BPB_VER), A
	
TEST7:
	LD	A,(SECTOR+0x42)	; Check for BPB 7.0 signature
	AND	0xFE
	CP	0x28		; 0x28 and 0x29 indicate BPB 7
	JR	NZ, TEST4
	; Now check if the type field is correct
	LD	DE, SECTOR+0x52
	LD	HL, S_FAT	; Check if starts with FAT
	LD	B, LS_FAT
	CALL	MEMCMP		
	JP	NZ, TEST4	; Not a BPB type 7
	; DE pointing to SECTOR+0x55	(Either "     " for calc, "FATxx   ")
	; Where xx is 12, 16, or 32
	LD	HL, S_FSPACE
	LD	B, LS_FSPACE
	CALL	MEMCMP
	JP	Z, FND7CALC	; We found a BPB 7.0 sig, with a calculated FAT type
	
	LD	DE, SECTOR+0x55
	LD	HL, S_F12
	LD	B, LS_FSPACE
	CALL	MEMCMP
	JP	Z, FND7FAT12	; Found a BPB 7.0 sig with FAT12
	
	LD	DE, SECTOR+0x55
	LD	HL, S_F16
	LD	B, LS_FSPACE
	CALL	MEMCMP
	JP	Z, FND7FAT16	; Found a BPB 7.0 sig with FAT16
	
	LD	DE, SECTOR+0x55
	LD	HL, S_F12
	LD	B, LS_FSPACE
	CALL	MEMCMP
	JP	Z, FND7FAT32	; Found a BPB 7.0 sig with FAT32
TEST4:	; Try and look for a BPB v4.0
	LD	A,(SECTOR+0x26)	; Check for BPB 4.0 signature
	AND	0xFE
	CP	0x28		; 0x28 and 0x29 indicate BPB 7
	JR	NZ, BPB3_4	; If signature does not match, assume BPB 3.4
	; Now check if the type field is correct
	LD	DE, SECTOR+0x36
	LD	HL, S_FAT	; Check if starts with FAT
	LD	B, LS_FAT
	CALL	MEMCMP		
	JP	NZ, TEST4	; Not a BPB type 7
	; DE pointing to SECTOR+0x39	(Either "     " for calc, "FATxx   ")
	; Where xx is 12, 16, or 32
	LD	HL, S_FSPACE
	LD	B, LS_FSPACE
	CALL	MEMCMP
	JP	Z, FND4CALC	; We found a BPB 4.0 sig, with a calculated FAT type
	
	LD	DE, SECTOR+0x39
	LD	HL, S_F12
	LD	B, LS_FSPACE
	CALL	MEMCMP
	JP	Z, FND4FAT12	; Found a BPB 4.0 sig with FAT12
	
	LD	DE, SECTOR+0x39
	LD	HL, S_F16
	LD	B, LS_FSPACE
	CALL	MEMCMP
	JP	Z, FND4FAT16	; Found a BPB 4.0 sig with FAT16
	
	LD	DE, SECTOR+0x39
	LD	HL, S_F12
	LD	B, LS_FSPACE
	CALL	MEMCMP
	JP	Z, FND4FAT32	; Found a BPB 4.0 sig with FAT32
BPB3_4:	; Assume a BPB3.4 since we couldn't find a 4.0 or 7.0
COMMON:
	LD	HL, (FAT_TSECT)
	LD	A, H
	OR	A, L
	JR	Z, NOTSECT	; If 0 then use LGTSECT instead
	; Otherwise copy TSECT into LGTEST
	LD	A, H
	LD	(FAT_LGTSECT+0), A
	LD	A, L
	LD	(FAT_LGTSECT+1), A
	XOR	A
	LD	(FAT_LGTSECT+2), A
	LD	(FAT_LGTSECT+3), A
NOTSECT:
	LD	HL, (FAT_SECTFAT)
	LD	A, H
	OR	A, L
	JR	Z, NOSECTFAT	; If 0 then use SECTFAT32 instead
	; Otherwise copy SECTFAT into SECTFAT32
	LD	A, H
	LD	(FAT_SECTFAT32+0), A
	LD	A, L
	LD	(FAT_SECTFAT32+1), A
	XOR	A
	LD	(FAT_SECTFAT32+2), A
	LD	(FAT_SECTFAT32+3), A
NOSECTFAT:
	; Now calculate our fat type if not already known
	LD	A, (FAT_TYPE)
	AND	A
	JR	NZ, KNOWNFAT		; If not 0 then use pre-specified type
	; Otherwise calculate based on sectors
	LD	IX, FAT_CLUSTCNT
	LD	A, (IX+3)
	OR	(IX+2)			; If > 0x0000FFFF must be FAT32
	JR	NZ, FAT32
	; FAT32 if > 0x0000FFF7, so we need to test more
	LD	A, (IX+1)
	XOR	0xFF
	JR	NZ, TESTFAT16		; If < 0x0000FF00 then can't be FAT32
	LD	A, (IX+0)
	CP	0xF7
	JR	NC, FAT32		; If >= 0x0000FFF7 then FAT32
TESTFAT16:
	; 0x00000FF7 <= FAT16 <= 0x0000FFF6
	LD	A, (IX+1)
	CP	0x10
	JR	NC, FAT16		; If > 0x00000FFF then FAT16
	CP	0x0F
	JR	NZ, FAT12		; If < 0x00000F00 then FAT12
	LD	A, (IX+0)
	CP	0xF7
	JR	NC, FAT16		; If >= 0x00000FF7 then FAT16
	; Otherwise FAT12
FAT12:
	LD	A, 12
	LD	(FAT_TYPE), A
	JR	KNOWNFAT
FAT16:
	LD	A, 16
	LD	(FAT_TYPE), A
	JR	KNOWNFAT
FAT32:
	LD	A, 32
	LD	(FAT_TYPE), A
	; Fall into KNOWNFAT
KNOWNFAT:
	; We've determined FAT type, copied relevant BPB values
	
	
	; Determine LBA for first FAT



FND7FAT12:
	LD	A, 12
	LD	(FAT_TYPE), A
	JR	FND7CALC
FND7FAT16:
	LD	A, 16
	LD	(FAT_TYPE), A
	JR	FND7CALC
FND7FAT32:
	LD	A, 32
	LD	(FAT_TYPE), A
	; Fall through
FND7CALC:
	LD	A, 70
	LD	(BPB_VER), A
	; Grab sectors per fat 32, and root cluster from BPB
	LD	HL, SECTOR+O_SECTFAT32
	LD	DE, FAT_SECTFAT32
	LD	BC, 4
	LDIR			; Copy
	LD	HL, SECTOR+O_ROOTCLUS
	LD	DE, FAT_ROOTCLUS
	LD	BC, 4
	LDIR			; Copy
	LD	HL, SECTOR+O_VOLID70
	LD	DE, FAT_VOLID
	LD	BC, 4
	LDIR			; Copy
	LD	HL, SECTOR+O_VOLLBL70
	LD	DE, FAT_VOLLBL
	LD	BC, 11
	LDIR			; Copy
	
	JP	COMMON
	
FND4FAT12:
	LD	A, 12
	LD	(FAT_TYPE), A
	JR	FND4CALC
FND4FAT16:
	LD	A, 16
	LD	(FAT_TYPE), A
	JR	FND4CALC
FND4FAT32:
	LD	A, 32
	LD	(FAT_TYPE), A
	; Fall through
FND4CALC:
	LD	A, 40
	LD	(BPB_VER), A
	; Populate values from 4.0 BPB here
	LD	HL, SECTOR+O_VOLID40
	LD	DE, FAT_VOLID
	LD	BC, 4
	LDIR			; Copy
	LD	HL, SECTOR+O_VOLLBL40
	LD	DE, FAT_VOLLBL
	LD	BC, 11
	LDIR			; Copy
	JP	COMMON
#endlocal


S_FAT:		DB "FAT"
LS_FAT		equ .-S_FAT
S_FSPACE:	DB "     "
LS_FSPACE:	equ .-S_FSPACE
S_F12		DB "12   "
S_F16		DB "16   "
S_F32		DB "32   "


; Calculate number of clusters in volume
;  Requires LGTSECT and FATSECT32 to be populated, if 16-bit values are used
;  then copy them into these 32-bit registers.
; Stores result in FAT_CLUSTCNT (32-bit)
CALCCLUST:
#local
	; First calculate sectors for fixed root directory:
	; SectorsInRootDirectory = (BPB.RootDirectoryEntries * 32 + BPB.BytesPerSector - 1) / BPB.BytesPerSector
	LD	A, (FAT_DIRENTS+0)
	LD	(FAT_SECTROOT+0), A
	LD	A, (FAT_DIRENTS+1)
	LD	(FAT_SECTROOT+1), A
	XOR	A
	LD	(FAT_SECTROOT+2), A
	; Multiply by 32 (10000) (<<4)
	; Carry flag is clear from XOR
	LD	IX, FAT_SECTROOT
	LD	B, 4
MUL32:
	RL	(IX+0)
	RL	(IX+1)
	RL	(IX+2)
	AnD	A			; Clear carry
	DJNZ	MUL32
	; Add Bytespersector
	LD	A, (FAT_SECTSIZ+0)
	ADD	A, (IX+0)
	LD	(IX+0), A
	LD	A, (FAT_SECTSIZ+1)
	ADC	A, (IX+1)
	LD	(IX+1), A
	XOR	A
	ADC	A, (IX+2)
	LD	(IX+2), A
	; Subtract 1
	LD	A, (IX+0)
	SUB	1
	LD	(IX+0), A
	LD	A, (IX+1)
	SBC	0
	LD	(IX+1), A
	LD	A, (IX+2)
	SBC	0
	LD	(IX+2), A
	; Now divide by bytes per sector, we'll do repeated subtraction for now
	LD	IX, FAT_SECTSIZ
	LD	BC, 0
DIVSECTSIZ:
	LD	A, (FAT_SECTROOT+0)
	SUB	(IX+0)
	LD	(FAT_SECTROOT+0), A
	LD	A, (FAT_SECTROOT+1)
	SBC	(IX+1)
	LD	(FAT_SECTROOT+1), A
	LD	A, (FAT_SECTROOT+2)
	SBC	0
	LD	(FAT_SECTROOT+2), A
	INC	BC
	JR	NC, DIVSECTSIZ		; Repeat until we go under 0
	DEC	BC			; Make up for the fact we went one beyond
	; We now have FAT_SECTROOT
	
	; Calculate data start
	;DataStart = BPB.ReservedSectors + BPB.FATs * SectorsPerFAT + SectorsInRootDirectory
	LD	IX, FAT_RESVSECT
	LD	A, (FAT_SECTROOT+0)
	ADD	(IX+0)
	LD	(FAT_DATASTART+0), A
	LD	A, (FAT_SECTROOT+1)
	ADC	(IX+1)
	LD	(FAT_DATASTART+1), A
	LD	A, (FAT_SECTROOT+2)
	ADC	0
	LD	(FAT_DATASTART+2), A
	LD	A, 0
	ADC	0
	LD	(FAT_DATASTART+3), A
	; Calculate FATs*Sectors pet Fat by repeated addition
	LD	A, (FAT_NFATS)
	LD	B, A
	LD	IX, FAT_SECTFAT32
MULFATS:
	LD	A, (FAT_DATASTART+0)
	ADD	(IX+0)
	LD	(FAT_DATASTART+0),A
	LD	A, (FAT_DATASTART+1)
	ADD	(IX+1)
	LD	(FAT_DATASTART+1),A
	LD	A, (FAT_DATASTART+2)
	ADD	(IX+2)
	LD	(FAT_DATASTART+2),A
	LD	A, (FAT_DATASTART+3)
	ADD	(IX+3)
	LD	(FAT_DATASTART+3),A
	DJNZ	MULFATS
	; We now have FAT_DATASTART
	
	; Calculate cluster count
	; ClusterCount = 2 + (SectorsInVolume - DataStart) / BPB.SectorsPerCluster
	LD	IX, FAT_DATASTART
	LD	A, (FAT_LGTSECT+0)
	SUB	(IX+0)
	LD	(FAT_CLUSTCNT+0), A
	LD	A, (FAT_LGTSECT+1)
	SBC	(IX+1)
	LD	(FAT_CLUSTCNT+1), A
	LD	A, (FAT_LGTSECT+2)
	SBC	(IX+2)
	LD	(FAT_CLUSTCNT+2), A
	LD	A, (FAT_LGTSECT+3)
	SBC	(IX+3)
	LD	(FAT_CLUSTCNT+3), A
	; Now divide by Sectors per cluster
	; Well assume Sectors per cluster is a power of two like it should be
	; However it's not strictly required to be, but is in practice
	; We're also not allowing a value of 0 (256)
	LD	IX, FAT_CLUSTCNT
	LD	A, (FAT_CLUSTSIZ)
	LD	B, 0
DIVSCLUS:
	AND	A			; Clear carry
	RR	(IX+0)
	RR	(IX+1)
	RR	(IX+2)
	RR	(IX+3)
	AND	A			; Clear carry
	RRA				
	BIT	0, A			; Check if we found our match
	JR	Z, DIVSCLUS
	; Finally add 2
	LD	A, (FAT_CLUSTCNT+0)
	ADD	2
	LD	(FAT_CLUSTCNT+0), A
	LD	A, (FAT_CLUSTCNT+1)
	ADC	0
	LD	(FAT_CLUSTCNT+1), A
	LD	A, (FAT_CLUSTCNT+2)
	ADC	0
	LD	(FAT_CLUSTCNT+2), A
	LD	A, (FAT_CLUSTCNT+3)
	ADC	0
	LD	(FAT_CLUSTCNT+3), A
	
	RET
#endlocal

; Set the current cluster to the value in FAT_CLUSTER
FAT_SETCLUSTER:
	XOR	A
	LD	(FAT_CURSECT), A	; Reset current sector
	; Convert CLUSTER into LBA
	
	; Multiply cluster # by sectors per cluster
	LD	HL, (FAT_CLUSTER+0)
	LD	(FAT_CLUSTLBA+0), HL
	LD	HL, (FAT_CLUSTER+2)
	LD	(FAT_CLUSTLBA+2), HL
	
	
	
	; Add LBA of first cluster (FAT_DATASTART)
	
	
	RET

; Read in the next sector in the current cluster
FAT_READSECT:
	
	
; Compare memory at (HL) to (DE) for B bytes
; Set's Z flag to results
; Pointers left on first byte not to match
MEMCMP:
	LD	A, (DE)
	CP	(HL)
	RET	NZ		; If bytes don't match return with Z flag clear
	INC	HL
	INC	DE
	DJNZ	MEMCMP
	RET			; Z flag still set from CP
