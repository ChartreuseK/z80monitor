

#data _RAM
; Parameters
FAT_FILENAME	DS	11	; Current open file with extension
FAT_FILELEN	DS	4	; Open file length
FAT_FILECLUS	DS	4	; Starting cluster of file

FAT_CURADDR	DS	2
FAT_BANK	DS	1	; Bank to load into for READ_BANK

FAT_CLUSTER	DS	4	; Custer to index (Little endian, 12, 16 or 32-bit)
FAT_CURSECT	DS	1	; Current sector within cluster
FAT_CLUSTLBA 	DS	4	; LBA of current cluster sector


;; Open file datastructure for program
;Structure:
;FILE_FN		equ	0		; Offset for filename (11)
;FILE_SIZE	equ	FILE_FN+11	; Current size of file (2)
;FILE_CUROFF	equ	FILE_SIZE+2	; Current offset in file (4)

FILES:



; Calculated values
FAT_TYPE	DS	1	; Fat type. 12, 16, or 32
BPB_VER		DS	1	; BPB type. 34 (for 3.4) 40 (for 4.0) or 70 (for 7.0)	
FAT_CLUSTCNT	DS	4	; Number of clusters in volume	
FAT_SECTROOT	DS	4	; Number of sectors for fixed root directory
				; Max would be 4097 (for 65535 dirents)
				; But for calc, we might overflow 16-bit
FAT_DATASTART	DS	4	; Starting sector for data (first cluster)
FAT_ROOTLBA	DS	4	; LBA of Root directory if fixed
FAT_LBA		DS	4	; LBA of first FAT

; Boot Parameter Block, read from disk
BPB_OFFSET	EQU	0x0B	; Offset from start of boot sector
; BPB 2.0 table
FAT_BPBSTART:
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

DIRENTSIZ	EQU	32

#code _ROM

 
; Something is fishy around here after we added the FAT_READFILE_BANK
; FAT_INIT sometimes fails at runtime depending on alignment


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
	LD	DE, FAT_BPBSTART
	LD	BC, BPB_SIZ
	LDIR			; Copy relevant BPB 3.4 into variables
	
	
	; Clear fat type and bpb
	XOR	A
	LD	(FAT_TYPE), A
	LD	(BPB_VER), A
	
	
	; Begin testing for BPB signatures
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
	
	LD	A, L
	LD	(FAT_LGTSECT+0), A
	LD	A, H
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
	EX	DE, HL
	LD	HL, FAT_SECTFAT32
	CALL	COPY32_16

NOSECTFAT:
	CALL	CALCCLUST		; Calculate # of clusters

	; Now calculate our fat type if not already known
	LD	A, (FAT_TYPE)
	AND	A
	JP	NZ, KNOWNFAT		; If not 0 then use pre-specified type
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
	JP	KNOWNFAT
FAT16:
	LD	A, 16
	LD	(FAT_TYPE), A
	JR	KNOWNFAT
FAT32:
	LD	A, 32
	LD	(FAT_TYPE), A
	JR	KNOWNFAT
;-------
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
;--------
KNOWNFAT:
	
	; We've determined FAT type, copied relevant BPB values
	; Print out a debugging message
	LD	HL, STR_FATTEMP1
	CALL	PRINT
	
	LD	A, (FAT_TYPE)
	CALL	PRINTBYTE_DEC		; Print FAT version
	LD	HL, STR_FATTEMP2
	CALL	PRINT
	LD	A, (BPB_VER)	
	CALL	PRINTBYTE_DEC		; Print BPB version 
	LD	HL, STR_FATTEMP3
	CALL	PRINT
	LD	HL, FAT_VOLLBL
	LD	B, 11
	CALL	PRINT_FIX		; Print out the volume label
	CALL	PRINTNL
		
	; Determine LBA for first FAT
	LD	DE, (FAT_RESVSECT)
	LD	(FAT_LBA), DE		; First FAT LBA = Reserved sectors
	LD	DE, 0
	LD	(FAT_LBA+2), DE		; 
	
	RET
	
	
STR_FATTEMP1:
	.ascii "Found FAT ",0
STR_FATTEMP2:
	.ascii " with BPB version ",0
STR_FATTEMP3:
	.ascii 10,13,"Volume label: ",0
#endlocal



; Calculate number of clusters in volume
;  Requires LGTSECT and SECTFAT32 to be populated
;  if 16-bit values are used then copy them into these 32-bit registers.
; Stores result in FAT_CLUSTCNT (32-bit)
CALCCLUST:
#local
	; First calculate sectors for fixed root directory:
	; SectorsInRootDirectory = (BPB.RootDirectoryEntries * 32 + BPB.BytesPerSector - 1) / BPB.BytesPerSector
	LD	A, (FAT_DIRENTS+0)		; Initialize to RootDirEnts
	LD	(FAT_SECTROOT+0), A
	LD	A, (FAT_DIRENTS+1)
	LD	(FAT_SECTROOT+1), A
	XOR	A
	LD	(FAT_SECTROOT+2), A
	LD	(FAT_SECTROOT+3), A
		
	; Multiply by 32 (10000) (<<4)
	; Carry flag is clear from XOR
	LD	IX, FAT_SECTROOT
	LD	B, 5
MUL32:
	RL	(IX+0)
	RL	(IX+1)
	RL	(IX+2)
	AnD	A			; Clear carry
	DJNZ	MUL32
	
	LD	HL, FAT_SECTROOT
	LD	DE, (FAT_SECTSIZ)
	CALL	ADD32_16		; Add Bytespersector
	
	LD	HL, FAT_SECTROOT
	LD	DE, 1
	CALL	SUB32_16		; Subtract 1
	
	
	
	; Now divide by bytes per sector, we'll do repeated subtraction for now
	LD	IX, FAT_SECTSIZ
	LD	DE, 0
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
	INC	DE
	JR	NC, DIVSECTSIZ		; Repeat until we go under 0
	DEC	DE			; Make up for the fact we went one beyond
	; We now have FAT_SECTROOT in DE
	LD	HL, FAT_SECTROOT
	CALL	COPY32_16		; Copy back into FAT_SECTROOT
	
	; Display FAT_SECTROOT
	LD	HL, STR_SECTROOT
	CALL	PRINT
	LD	BC, (FAT_SECTROOT+2)	; High word
	CALL	PRINTWORD
	LD	BC, (FAT_SECTROOT)	; Low word
	CALL	PRINTWORD
	CALL	PRINTNL

	; Above gives correct calculation  v/
	
	; Calculate data start
	;DataStart = BPB.ReservedSectors + BPB.FATs * SectorsPerFAT + SectorsInRootDirectory
	LD	HL, FAT_DATASTART
	LD	DE, (FAT_RESVSECT)
	CALL	COPY32_16		; Initialize to Resv sect
	
	
	
	
	; Calculate FATs*Sectors pet Fat by repeated addition
	; And add to DATASTART
	; NFATS is usually 2 so this is fairly fast
	
	LD	A, (FAT_NFATS)
	LD	B, A
	LD	IX, FAT_SECTFAT32
MULFATS:
	LD	DE, FAT_DATASTART
	LD	HL, FAT_SECTFAT32
	CALL	ADD32

	DJNZ	MULFATS
	
	LD	HL, FAT_DATASTART
	LD	DE, FAT_ROOTLBA		; Save root directory pointer before we add its length
	CALL	COPY32		
	
	LD	HL, FAT_DATASTART
	LD	DE, (FAT_SECTROOT)
	CALL	ADD32_16		; Add sectors in root directory
	;
	
	
	; We now have FAT_DATASTART
	; Dispaly it
	LD	HL, STR_DATASTART
	CALL	PRINT
	LD	BC, (FAT_DATASTART+2)	; High word
	CALL	PRINTWORD
	LD	BC, (FAT_DATASTART)	; Low word
	CALL	PRINTWORD
	CALL	PRINTNL
	
	LD	HL, STR_ROOTSTART
	CALL	PRINT
	LD	BC, (FAT_ROOTLBA+2)	; High word
	CALL	PRINTWORD
	LD	BC, (FAT_ROOTLBA)	; Low word
	CALL	PRINTWORD
	CALL	PRINTNL
	
	
	; Above gives correct calculation  v/
	
	; Calculate cluster count
	; ClusterCount = 2 + (SectorsInVolume - DataStart) / BPB.SectorsPerCluster
	LD	DE, FAT_CLUSTCNT
	LD	HL, FAT_LGTSECT
	CALL	COPY32			; Initialize to SectorsInVolume
	
	LD	DE, FAT_CLUSTCNT
	LD	HL, FAT_DATASTART
	CALL	SUB32			; Subtract DataStart
	
	; Now divide by Sectors per cluster
	; Well assume Sectors per cluster is a power of two like it should be
	; However it's not strictly required to be, but is in practice
	; We're also not allowing a value of 0 (256)
	LD	HL, FAT_CLUSTCNT
	LD	A, (FAT_CLUSTSIZ)
	BIT	0, A			; Check that clustsiz isn't 1
	JR	NZ, NODIVCLUS		; If it is then don't divide
DIVSCLUS:
	CALL	SRL32			; Shift clustcnt right 1
	RRA				; Shift clustsiz right by 1 (who cares about carry in bits)
	BIT	0, A			; Check if we found our match
	JR	Z, DIVSCLUS
NODIVCLUS:
	
	; Finally add 2
	LD	DE, 2
	LD	HL, FAT_CLUSTCNT
	CALL	ADD32_16
	
	; Display cluster count
	LD	HL, STR_CLUSTCNT
	CALL	PRINT
	LD	BC, (FAT_CLUSTCNT+2)
	CALL	PRINTWORD
	LD	BC, (FAT_CLUSTCNT)
	CALL	PRINTWORD
	CALL	PRINTNL
	
	RET
#endlocal




; List the root directory
FAT_DIR_ROOT:
#local
	LD	A, (FAT_TYPE)		; Check which fat version 
	CP	16+1			; We're only supporting FAT12/16 fixed root directories for now
	JR	C, ISFIXED
	; Otherwise display a message and return
	LD	HL, STR_NOROOT
	CALL	PRINTN
	RET
ISFIXED:
	

	LD	HL, FAT_ROOTLBA		; Root directory is right before the start of data
	LD	DE, LBA
	CALL	COPY32
	
	LD	HL, SECTOR
	CALL	CF_READ			; Read in first sector of directory
	
	LD	HL, STR_ROOTLIST
	CALL	PRINTN
	
	LD	A, (FAT_DIRENTS)	; Number of entries in root directory
	LD	B, A			; Copy to B
	
	LD	HL, SECTOR		; HL points to our current directory entry

	
	PUSH	BC
DIRLOOP:
	PUSH	HL
	CALL	PRINTENT		; Print directory entry HL
	POP	HL
	
	POP	BC			; Restore counter
	
	
	DEC	B			; Dec
	JR	Z, DONE			; If no entries left then we're done
	PUSH	BC			; Save counter
	
	LD	DE, DIRENTSIZ
	ADD	HL, DE			; Advance to the next directory entry
	LD	DE, SECTOR+512		; End of sector
	CMP16	DE			; Compare HL with DE
	JR	C, NOLOAD		; If < SECTOR+512 then we don't need to load next
	; Otherwise Load next sector
	LD	DE, 1
	LD	HL, LBA
	CALL	ADD32_16		; Increment LBA
	LD	HL, SECTOR
	CALL	CF_READ
	LD	HL, SECTOR		; Reset HL
NOLOAD:
	JR	DIRLOOP			;
DONE:
	LD	HL, STR_LISTBREAK
	CALL	PRINTN
	RET
#endlocal	

; Print out a directory entry
; HL - points to first byte of entry
PRINTENT:
#local
ENT_ATTR	equ	11		; Attribute byte
ENT_FS		equ	28
	PUSH	HL
	POP	IX			; Copy pointer into IX for indexing
	LD	A, (IX+0)		; First byte of filename
	AND	A
	JR	Z, SKIPENT		; Skip blank entries
	CP	$E5
	JR	Z, SKIPENT		; Skip deleted entries


	LD	A, (IX+ENT_ATTR)	; Read attribute byte
	; Attb byte is:
	; 1 - Read Only, 2 - Hidden , 4 - System, 8 - Volume ID
	; 16 - Directory, 32 - Archive
	AND	$0F			; Mask off low bits
	CP	$0F			; If Read only, hidden, system, and volume_id then is a LFN entry
	JR	Z, SKIPENT		; Skip LFN entries
	AND	$0E			; If HIDDEN, SYSTEM, or VOLUME_ID 
	JR	NZ, SKIPENT		; Then don't show files
	; We want our printed format to be:
	; 0         1         2         3         4
	; 01234567890123456789012345678901234567890
	; FILENAME EXT   R    FILESIZE
	; or
	; DIRNAME  EXT        <DIR>   
	
	; Print the name
	PUSH	IX
	POP	HL			; Move to HL
	LD	B, 8			; Filename is 8 ch long
	CALL	PRINT_FIX		; EVIL: We're going to be evil and rely on PRINTFIX not preserving HL
	LD	A, ' '			
	CALL	PRINTCH	
	LD	B, 3			; Extension is 3 ch long
	CALL	PRINT_FIX		; Print extension
	LD	B, 3			; 3ch space
	CALL	SPACE
	; Print if Read-only or not
	LD	A, (IX+ENT_ATTR)	; Read attribute byte
	AND	1			; Check if read-only
	JR	Z, NORDONLY
	LD	A, 'R'
	CALL	PRINTCH
	JR	AFTER1
NORDONLY:
	LD	A, ' '
	CALL	PRINTCH
AFTER1:
	LD	B, 4
	CALL	SPACE
	; Print filesize or <DIR> if directory
	LD	A, (IX+ENT_ATTR)
	AND	$10
	JR	NZ, ISDIR
	
	LD	B, (IX+ENT_FS+3)		; High word of filesize
	LD	C, (IX+ENT_FS+2)		
	CALL	PRINTWORD
	LD	B, (IX+ENT_FS+1)		; Low word of filesize
	LD	C, (IX+ENT_FS+0)		
	CALL	PRINTWORD
	CALL	PRINTNL
	RET
ISDIR:
	LD	HL, STR_DIR
	CALL	PRINTN
SKIPENT:
	RET
	
	
SPACE:
	LD	A, ' '
	CALL	PRINTCH
	DJNZ	SPACE
	RET
#endlocal	

; Add a new file to the directory
; Name should be in FAT_FILENAME already
FAT_NEWFILE:
#local
	LD	A, (FAT_TYPE)
	CP	16+1		; Only support FAT12/16 fixed root dir for now
	JR	C, ISFIXED
	LD	HL, STR_NOROOT
	CALL	PRINTN
	SCF
	RET
ISFIXED:
	LD	HL, FAT_ROOTLBA		; Root directory is right before the start of data
	LD	DE, LBA
	CALL	COPY32

	LD	HL, SECTOR
	CALL	CF_READ			; Read in first sector of directory

	LD	HL, (FAT_DIRENTS)	; Number of entries in root directory
	PUSH	HL
	POP	BC
	
	LD	HL, SECTOR		; HL points to our current directory entry
DIRLOOP:
	LD	A, (HL)			; Check first byte of filename
	AND	A	
	JR	Z, FOUNDENT		; Found a free entry
	CP	0xE5	
	JR	Z, FOUNDENT		; Found a deleted/free entry

	DEC	BC
	LD	A, B
	OR	C
	JR	NZ, ENTS
NOENTS:
	; No directory entires available
	SCF
	RET
ENTS:
	PUSH	BC
	LD	DE, DIRENTSIZ
	ADD	HL, DE			; Advance to the next directory entry
	LD	DE, SECTOR+512		; End of sector
	CMP16	DE			; Compare HL with DE
	JR	C, NOLOAD		; If < SECTOR+512 then we don't need to load next
	; Otherwise Load next sector
	LD	DE, 1
	LD	HL, LBA
	CALL	ADD32_16		; Increment LBA
	LD	HL, SECTOR
	CALL	CF_READ
	LD	HL, SECTOR		; Reset HL
NOLOAD:
	POP	BC
	JR	DIRLOOP			;
	; We found a free entry, make it ours
FOUNDENT:
	PUSH 	HL
	CALL	PRINTI
	.ascii "Found free entry",10,13,0
	POP	HL

	; HL points to the first byte of the entry
	PUSH	HL
	LD	B, 11
	LD	DE, FAT_FILENAME
COPYNAME:
	LD	A, (DE)
	LD	(HL), A
	INC	DE
	INC	HL
	DJNZ	COPYNAME 
	
	LD	A, 0			; 
	LD	B, 32-11
BLANKL:
	LD	(HL), A			; Blank out reset of entry
	INC	HL
	DJNZ	BLANKL

	LD	HL, SECTOR
	CALL	CF_WRITE		; Write updated sector

	POP	HL			; Leave pointer to entry in HL
	AND	A			; Clear carry
	RET

#endlocal

; Delte a file
; Filename in FAT_FILENAME
FAT_DELETEFILE:
#local
	; Find file in root directory
	LD	A, (FAT_TYPE)		; Check which fat version 
	CP	16+1			; We're only supporting FAT12/16 fixed root directories for now
	JR	C, ISFIXED
	; Otherwise display a message and return
	LD	HL, STR_NOROOT
	CALL	PRINTN
	RET
ISFIXED:
	LD	HL, FAT_ROOTLBA		; Root directory is right before the start of data
	LD	DE, LBA
	CALL	COPY32
	
	LD	HL, SECTOR
	CALL	CF_READ			; Read in first sector of directory
	
	LD	HL, (FAT_DIRENTS)	; Number of entries in root directory
	PUSH 	HL \ POP BC		; Copy to BC
	
	LD	HL, SECTOR		; HL points to our current directory entry
	PUSH	BC			; Save counter
DIRLOOP:
	PUSH	HL
	; First 11 bytes are the filename+ext
	LD	DE, FAT_FILENAME
	LD	B, 11
	CALL	MEMCMP
	JR	Z, FOUND
	POP	HL	
	
	POP	BC
	DEC	BC			; Remaining entries
	LD	A, B
	OR	C
	JR	Z, NOTFOUND		; If no entries left then we're done
	PUSH	BC			; Save counter
	
	LD	DE, DIRENTSIZ
	ADD	HL, DE			; Advance to the next directory entry
	LD	DE, SECTOR+512		; End of sector
	CMP16	DE			; Compare HL with DE
	JR	C, DIRLOOP		; If < SECTOR+512 then we don't need to load next
	; Otherwise Load next sector
	LD	DE, 1
	LD	HL, LBA
	CALL	ADD32_16		; Increment LBA
	LD	HL, SECTOR
	CALL	CF_READ
	LD	HL, SECTOR		; Reset HL
	JR	DIRLOOP			;
NOTFOUND:
	LD	HL, STR_FNF
	CALL	PRINTN	
	SCF				; Set carry to indicate failure
	RET
FOUND:
	; Found the file, now delete it
	POP	IX			; Restore pointer to the directory entry
	POP	BC			; BC was left on the stack, remove it
	; Okay this is a really inefficient copy code, but look how clean it looks
	; Copy the length
	LD	A, $E5
	LD	(IX+0), A		; Set file to erased

	; Copy the starting cluster
	LD	A, (IX+26)		; Low word
	LD	(FAT_CLUSTER+0), A
	LD	B, A
	
	LD	A, (IX+27)
	LD	(FAT_CLUSTER+1), A
	OR	B
	LD	B, A
	
	LD	A, (IX+20)		; High word (Always 0 on FAT12/16)
	LD	(FAT_CLUSTER+2), A
	OR	B
	LD	B, A

	LD	A, (IX+21)
	LD	(FAT_CLUSTER+3), A
	OR	B
	LD	B, A			; Save if cluster was 0 (empty file)

	LD	A, 0			; Zero out start cluster
	LD	(IX+26), A
	LD	(IX+27), A
	LD	(IX+20), A
	LD	(IX+21), A
	
	PUSH	BC
	LD	HL, SECTOR
	CALL	CF_WRITE		; Write changes to directory entry

	CALL	PRINTI
	.ascii "Directory entry cleared",10,13,0

	POP	BC
	LD	A, B
	AND	A			; Check if file was empty
	RET	Z			; If it was then we're done

	CALL	PRINTI
	.ascii "Cluster not empty, clearing chain",10,13,0

	; Debug print next cluster
	PUSH	HL
	PUSH	BC
	CALL	PRINTI
	.ascii "Cluster chain: ",0
	LD	BC, (FAT_CLUSTER)
	CALL	PRINTWORD
	CALL	PRINTI
	.ascii ".",0
	POP	BC
	POP	HL

	; Now we have to free the cluster chain, the hard part
	; Abuse FAT_NEXTCLUST to get next cluster in chain, and point us
	; just after the entry needed to be wiped
NEXTCLUST:
	CALL	FAT_NEXTCLUST		; Get next cluster address into FAT_CLUSTER
					; Leaves HL pointed at entry with LBA pointing to sector
	LD	A, 0
	LD	(HL), A			; Mark cluster as free 0000
	INC	HL
	LD	(HL), A			
	LD	HL, SECTOR
	CALL	CF_WRITE		; Write change to FAT 
	
	LD	DE, FAT_SECTFAT32	; Advance to second FAT
	LD	HL, LBA
	CALL	ADD32
	 
	LD	HL, SECTOR		; Write to second fat
	CALL	CF_WRITE
	
	; Debug print next cluster
	PUSH	HL
	PUSH	BC
	LD	BC, (FAT_CLUSTER)
	CALL	PRINTWORD
	CALL	PRINTI
	.ascii ".",0



	POP	BC
	POP	HL

	CALL	FAT_ISCLUSTEND		; Was this the last cluster in the file?
	JR	C, NEXTCLUST

	CALL	PRINTI
	.ascii 10,13,"1st fat updated. Copying 1st to 2nd",10,13,0
DONE:
	AND A	; Clear carry
	RET
#endlocal


; Copy 1st fat onto second
FAT_COPY:
	; Copy first to second fat
	LD	BC, 0			; Count
COPYFAT:
	LD	HL, FAT_LBA
	LD	DE, LBA
	CALL	COPY32			; Source first fat

	LD	HL, LBA
	PUSH	BC \ POP DE
	CALL	ADD32_16		; Add current offset

	PUSH	BC
	 LD	HL, SECTOR
	 CALL	CF_READ			; Read source

	 LD	DE, FAT_SECTFAT32	; Advance to second FAT
	 LD	HL, LBA
	 CALL	ADD32
	 
	 LD	HL, SECTOR		; Write to second fat
	 CALL	CF_WRITE
	POP	BC			; Restore counter
	INC	BC
	LD	HL, (FAT_SECTFAT32)
	CMP16	BC
	JR	NZ, COPYFAT		; Loop till we copy entire FAT
	RET

;-----------
; Advance to the next cluster
FAT_NEXTCLUST:
#local
	; Look up current cluster in FAT
	; We need to read in the FAT from the disk
	; To do so we need to figure out which sector in the FAT
	; contains the current cluster
	LD	HL, FAT_CLUSTER		; Pointer
	LD	DE, 2
	CALL	SUB32_16		; Remove cluster offset
	; BAD: Assuming FAT16 only for now. Handle FAT12 later
	; For FAT16
	; FAT Sector  = FAT_LBA + (cluster * 2)/512 (sect size)
	; Offset inside sector = (cluster * 2) % 512
	; BAD: We're dealing with only hard-drives, assume sector size of 512
	;      This makes the calcuation instead: FAT_LBA + (cluster/256)
	;      Dividing by 256 is just a shift by one byte
	LD	HL, FAT_CLUSTER+1 	; +1 to shift off the lowest byte (/256) (pointer)
	LD	DE, LBA
	CALL	COPY32

	XOR	A			; Clear A
	LD	(LBA+3), A		; Clear highest byte of LBA since it contains garbage
	; We now have (cluster * 2) / 512 in LBA
	LD	HL, FAT_LBA
	LD	DE, LBA
	CALL	ADD32			; Add FAT_LBA to get the sector to read
	
	LD	HL, SECTOR
	CALL	CF_READ			; Read sector into buffer
	
	; Our offset in the sector is (cluster * 2) % 512
	; BAD: Still assuming a sector size of 512 we can simply take the low byte of CLUSTER
	;      and multiply it by 2 to get the offset
	LD	A, (FAT_CLUSTER)
	LD	L, A
	LD	H, 0
	ADD	HL, HL			; (cluster * 2) % 512
	LD	DE, SECTOR
	ADD	HL, DE			; Add starting address of the sector to get our pointer
	
	PUSH	HL
	CALL	PRINTI
	.ascii "FNC(",0
	POP	BC
	PUSH	BC
	CALL	PRINTWORD
	CALL	PRINTI
	.ascii ")",0
	POP	HL

	LD	A, (HL)			; Low byte of next cluster
	LD	(FAT_CLUSTER), A
	INC	HL
	LD	A, (HL)			; High byte of next cluster
	LD	(FAT_CLUSTER+1), A
	; Since we're assuming FAT_16 here, zero out upper bytes just incase
	XOR	A
	LD	(FAT_CLUSTER+2), A
	LD	(FAT_CLUSTER+3), A
	DEC	HL
	DEC	HL			; Point HL back to the entry
	RET
#endlocal




; Open a file
; Filename in FAT_FILENAME
FAT_OPENFILE:
#local
	; Find file in root directory
	LD	A, (FAT_TYPE)		; Check which fat version 
	CP	16+1			; We're only supporting FAT12/16 fixed root directories for now
	JR	C, ISFIXED
	; Otherwise display a message and return
	LD	HL, STR_NOROOT
	CALL	PRINTN
	RET
ISFIXED:
	LD	HL, FAT_ROOTLBA		; Root directory is right before the start of data
	LD	DE, LBA
	CALL	COPY32
	
	LD	HL, SECTOR
	CALL	CF_READ			; Read in first sector of directory
	
	LD	HL, (FAT_DIRENTS)	; Number of entries in root directory
	PUSH 	HL \ POP BC		; Copy to BC
	
	LD	HL, SECTOR		; HL points to our current directory entry

	
	PUSH	BC
DIRLOOP:
	PUSH	HL
	; First 11 bytes are the filename+ext
	LD	DE, FAT_FILENAME
	LD	B, 11
	CALL	MEMCMP
	JR	Z, FOUND	
	POP	HL
	
	POP	BC			; Restore counter
	DEC	BC			; Dec
	LD	A, B
	OR	C
	JR	Z, NOTFOUND		; If no entries left then we're done
	PUSH	BC			; Save counter
	
	LD	DE, DIRENTSIZ
	ADD	HL, DE			; Advance to the next directory entry
	LD	DE, SECTOR+512		; End of sector
	CMP16	DE			; Compare HL with DE
	JR	C, NOLOAD		; If < SECTOR+512 then we don't need to load next
	; Otherwise Load next sector
	LD	DE, 1
	LD	HL, LBA
	CALL	ADD32_16		; Increment LBA
	LD	HL, SECTOR
	CALL	CF_READ
	LD	HL, SECTOR		; Reset HL
NOLOAD:
	JR	DIRLOOP			;
NOTFOUND:
	LD	HL, STR_FNF
	CALL	PRINTN	
	SCF				; Set carry to indicate failure
	RET
FOUND:
	; Found the file, now open it
	POP	IX			; Restore pointer to the directory entry
	POP	BC			; BC was left on the stack, remove it
	; Okay this is a really inefficient copy code, but look how clean it looks
	; Copy the length
	LD	A, (IX+28)		; File size low byte
	LD	(FAT_FILELEN+0), A
	LD	A, (IX+29)		; File size 
	LD	(FAT_FILELEN+1), A
	LD	A, (IX+30)		; File size 
	LD	(FAT_FILELEN+2), A
	LD	A, (IX+31)		; File size high byte
	LD	(FAT_FILELEN+3), A
	; Copy the starting cluster
	LD	A, (IX+26)		; Low word
	LD	(FAT_FILECLUS+0), A
	LD	A, (IX+27)
	LD	(FAT_FILECLUS+1), A
	LD	A, (IX+20)		; High word (Always 0 on FAT12/16)
	LD	(FAT_FILECLUS+2), A
	LD	A, (IX+21)
	LD	(FAT_FILECLUS+3), A
	; File is now 'opened'
	AND	A			; Clear carry for success
	RET
#endlocal

;--------
; Copies the name.ext (8.3) filename into the FILENAME buffer
; in space padded fixed width format 8+3 'NAME    EXT'
FAT_SETFILENAME:
#local
	CALL	CLEARFN
	; Convert filename to 8+3 space padded
	; First read up to 8 characters, stopping early if we see a dot or NULL
	LD 	DE, FAT_FILENAME
	
	LD	B, 8
NAMELOOP:
	LD	A, (HL)
	CP	'.'
	JR 	Z, DOEXT
	AND	A
	JR	Z, DONE
	LD	(DE), A
	INC	DE
	INC	HL
	DJNZ	NAMELOOP
DOEXT:
	LD	DE, FAT_FILENAME+8
	LD	B, 3
EXTLOOP:
	INC	HL
	LD	A, (HL)
	AND	A
	JR	Z, DONE
	LD	(DE), A
	INC 	DE
	DJNZ	EXTLOOP
DONE:
	RET
#endlocal

;------
; Clear the filename to blank (all spaces)
CLEARFN:
#local
	PUSH	HL
	PUSH	BC
	LD	HL, FAT_FILENAME
	LD	B, 11
	LD	A, ' '
LOOP:
	LD	(HL), A
	INC	HL
	DJNZ	LOOP
	POP	BC
	POP	HL
	RET
#endlocal
	
;-----
; Read entire current file into memory
FAT_READFILE:
#local
	LD	(FAT_CURADDR), HL	; Save address
	LD	BC, (FAT_FILELEN)	; Read only low word of length (we're not doing backswitching in this load)
	PUSH	BC
	LD	A, (FAT_CLUSTSIZ)
	LD	(FAT_CURSECT), A	; Current sector within cluster (backwards)
	
	
	; Assume file is open for now, add some open flag later
	LD	HL, FAT_FILECLUS
	LD	DE, FAT_CLUSTER	
	CALL	COPY32			; Copy starting cluster
	CALL	CLUST2LBA		; Convert cluster to LBA 
	

	; Debug print, display current cluster and LBA
	PUSH	BC
	PUSH	HL
	LD	HL, STR_READF1
	CALL	PRINT
	LD	BC, (FAT_CLUSTER)
	CALL	PRINTWORD
	LD	HL, STR_READF2
	CALL	PRINT
	
	LD	BC, (FAT_CLUSTLBA+2)
	CALL	PRINTWORD
	LD	BC, (FAT_CLUSTLBA)
	CALL	PRINTWORD
	CALL	PRINTNL
	POP	HL
	POP	BC
	
	
	LD	HL, FAT_CLUSTLBA
	LD	DE, LBA
	CALL	COPY32			; Copy to CF card's LBA
LOOP:
	
	LD	HL, STR_READF4
	CALL	PRINT
	LD	BC, (FAT_CURADDR)
	CALL	PRINTWORD
	LD	HL, STR_READF2
	CALL	PRINT
	LD	BC, (LBA+2)
	CALL	PRINTWORD
	LD	BC, (LBA+0)
	CALL	PRINTWORD
	CALL	PRINTNL


	LD	HL, (FAT_CURADDR)	; Restore address
	CALL	CF_READ			; Read sector to memory
	
	LD	HL, (FAT_CURADDR)
	LD	DE, 512
	ADD	HL, DE			; Advance address
	LD	(FAT_CURADDR), HL	; Save address
	
	POP	HL			; Restore length
	AND	A			; Clear carry
	SBC	HL, DE			; Decrement length left
	JP	PE, DONE2		; If < 0 then we're done
	PUSH	HL
	
	LD	HL, FAT_CURSECT
	DEC	(HL)
	JR	Z, NEWCLUST
	; Increment LBA to next sector
	LD	DE, 1
	LD	HL, LBA
	CALL	ADD32_16
	JR	LOOP
NEWCLUST:
	; We're done our cluster, need to fetch the next one
	CALL	FAT_NEXTCLUST		; Fetch next cluster from FAT
	
	; Debug print next cluster
	PUSH	HL
	PUSH	BC
	LD	HL, STR_READF3
	CALL	PRINT
	LD	BC, (FAT_CLUSTER)
	CALL	PRINTWORD
	CALL	PRINTNL
	POP	BC
	POP	HL
	
	; Check if end of file
	CALL	FAT_ISCLUSTEND	
	JR	NC, DONE		; If end of file chain then we're done
	; If not follow the chain, and keep going
	CALL	CLUST2LBA		; Convert cluster to LBA
	
	LD	HL, FAT_CLUSTLBA
	LD	DE, LBA
	CALL	COPY32			; Copy to CF card's LBA

DONE:
	POP	HL			; Remove length from stack
DONE2:
	RET
#endlocal




;--------
; Convert cluster to sector number
CLUST2LBA:
#local
	

	; We need to multiply the cluster # by the cluster size
	; Then add DATASTART to it.
	
	LD	HL, FAT_CLUSTER
	LD	DE, 2
	CALL	SUB32_16		; Remove the starting cluster offset (0 and 1 reserved
	
	LD	HL, FAT_CLUSTER
	LD	DE, FAT_CLUSTLBA
	CALL	COPY32			; Copy starting value
	
	
	; Now multiply by the cluster size
	LD	A, (FAT_CLUSTSIZ)	; 
	LD	B, A
MULLOOP:
	DEC	B
	JR	Z, DONEMUL
	LD	HL, FAT_CLUSTER
	LD	DE, FAT_CLUSTLBA
	CALL	ADD32			; Add cluster # repeatedly to multiply
	JR	MULLOOP
DONEMUL:
	; Now we add to need the starting offset
	LD	HL, FAT_DATASTART
	LD	DE, FAT_CLUSTLBA
	CALL	ADD32
	; And we're done, restore original cluster #
	LD	HL, FAT_CLUSTER
	LD	DE, 2
	CALL	ADD32_16		; Restore the starting cluster offset (0 and 1 reserved
	
	
	RET
#endlocal

;-------
; Is the current cluster the end of the chain
; Resets C flag if it is, sets C if not
; BAD: Assuming FAT16 for now
FAT_ISCLUSTEND:
#local
	LD	HL, (FAT_CLUSTER)
	LD	DE, 0xFFF0
	CMP16	DE			; 16-bit compare, if < 0xFFF0 then set C flag
	; If < 0xFFF0 then the cluster is not the end of the chain
	RET
#endlocal

;--------
; Compare memory at (HL) to (DE) for B bytes
; Set's Z flag to results
; Pointers left on first byte not to match
;MEMCMP:
;	LD	A, (DE)
;	CP	(HL)
;	RET	NZ		; If bytes don't match return with Z flag clear
;	INC	HL
;	INC	DE
;	DJNZ	MEMCMP
;	RET			; Z flag still set from CP



S_FAT:		DB "FAT"
LS_FAT		equ .-S_FAT
S_FSPACE:	DB "     "
LS_FSPACE:	equ .-S_FSPACE
S_F12		DB "12   "
S_F16		DB "16   "
S_F32		DB "32   "

STR_SECTROOT:
	.ascii "Sectors for fixed root: $",0
STR_DATASTART:
	.ascii "Data start sector:      $",0
STR_CLUSTCNT:
	.ascii "Total clusters:         $",0
STR_ROOTSTART:
	.ascii "Root dir sector:        $",0
STR_NOROOT:
	.ascii "Only fixed root directory supported",0
	
STR_ROOTLIST:
	.ascii "Root directory:",13,10
	.ascii "Filename       RO   Size (HEX)",13,10
	; Fall through
STR_LISTBREAK:
	.ascii "------------------------------",0
	      ; 0         1         2         3         4
	      ; 01234567890123456789012345678901234567890
	      ; FILENAME EXT   R    FILESIZE
STR_DIR:
	.ascii "<DIR>",0
STR_FNF:
	.ascii "File not found!",0
STR_READF1:
	.ascii "Reading cluster: $",0
STR_READF2:
	.ascii " LBA: $",0
STR_READF3:
	.ascii "Next cluster: $",0
STR_READF4:
	.ascii "Current address: $",0




;-----
; Read entire current file into memory in specified bank
FAT_READFILE_BANK:
#local
	LD	(FAT_BANK), A		; Save bank
	LD	(FAT_CURADDR), HL	; Save address
	LD	BC, (FAT_FILELEN)	; Read only low word of length (we're not doing backswitching in this load)
	PUSH	BC
	LD	A, (FAT_CLUSTSIZ)
	LD	(FAT_CURSECT), A	; Current sector within cluster (backwards)
	
	
	; Assume file is open for now, add some open flag later
	LD	HL, FAT_FILECLUS
	LD	DE, FAT_CLUSTER	
	CALL	COPY32			; Copy starting cluster
	CALL	CLUST2LBA		; Convert cluster to LBA 
	

	; Debug print, display current cluster and LBA
	PUSH	BC
	PUSH	HL
	LD	HL, STR_READF1
	CALL	PRINT
	LD	BC, (FAT_CLUSTER)
	CALL	PRINTWORD
	LD	HL, STR_READF2
	CALL	PRINT
	
	LD	BC, (FAT_CLUSTLBA+2)
	CALL	PRINTWORD
	LD	BC, (FAT_CLUSTLBA)
	CALL	PRINTWORD
	CALL	PRINTNL
	POP	HL
	POP	BC
	
	
	LD	HL, FAT_CLUSTLBA
	LD	DE, LBA
	CALL	COPY32			; Copy to CF card's LBA
LOOP:
	
	LD	HL, STR_READF4
	CALL	PRINT
	LD	BC, (FAT_CURADDR)
	CALL	PRINTWORD
	LD	HL, STR_READF2
	CALL	PRINT
	LD	BC, (LBA+2)
	CALL	PRINTWORD
	LD	BC, (LBA+0)
	CALL	PRINTWORD
	CALL	PRINTNL


	LD	HL, SECTOR		; Read into SECTOR buffer, we'll copy to bank later
	CALL	CF_READ			; Read sector to memory
	
	
	; Copy to bank
	LD	HL, SECTOR
	LD	DE, (FAT_CURADDR)
	LD	BC, 512
	LD	A, (FAT_BANK)

	CALL	RAM_BANKCOPY		; Do a bank copy
	
	
	
	LD	HL, (FAT_CURADDR)
	
	LD	DE, 512
	ADD	HL, DE			; Advance address
	LD	(FAT_CURADDR), HL	; Save address
	
	POP	HL			; Restore length
	
	AND	A			; Clear carry
	SBC	HL, DE			; Decrement length left
	JP	M, DONE2		; If < 0 then we're done
	PUSH	HL
	
	LD	HL, FAT_CURSECT
	DEC	(HL)
	JR	Z, NEWCLUST
	; Increment LBA to next sector
	LD	DE, 1
	LD	HL, LBA
	CALL	ADD32_16
	JR	LOOP
NEWCLUST:
	; We're done our cluster, need to fetch the next one
	CALL	FAT_NEXTCLUST		; Fetch next cluster from FAT
	
	; Debug print next cluster
	PUSH	HL
	PUSH	BC
	LD	HL, STR_READF3
	CALL	PRINT
	LD	BC, (FAT_CLUSTER)
	CALL	PRINTWORD
	CALL	PRINTNL
	POP	BC
	POP	HL
	
	; Check if end of file
	CALL	FAT_ISCLUSTEND	
	JR	NC, DONE		; If end of file chain then we're done
	; If not follow the chain, and keep going
	CALL	CLUST2LBA		; Convert cluster to LBA
	
	LD	HL, FAT_CLUSTLBA
	LD	DE, LBA
	CALL	COPY32			; Copy to CF card's LBA

DONE:
	POP	HL			; Remove length from stack
DONE2:
	RET
#endlocal




; Offset in file:
;  Cluster in chain:   offset / (FAT_CLUSTSIZ * 512)
;  Offset in cluster:  offset % (FAT_CLUSTSIZ * 512)
;  Sector in cluster   (offset / 512) % (FAT_CLUSTSIZ)



F1_FNAME	DS	11	; Filename as space padded 8+3
F1_LEN		DS	4	; Length of file
F1_OFFSET	DS	4	; Current offset in file
F1_CLUSTER	DS	2	; Current cluster 
F1_SECT		DS	1	; Sector within cluster
F1_PAD		DS	10	; Pad out to 32 bytes

; FREAD
;   readcount = 0
; readloop:
;   Load current sector for offset
;   Read up to len bytes from sector (at sector offset), max 512-off bytes.
;   len -= bytes read; readcount += bytes read
;   If len > 0 then we need to read the next sector
;      If current sector in cluster < CLUSTSIZ then increment to next sequential sector, set offset in to 0
;      If not then we need to advance to the next cluster
;          Read the sector in the FAT for the current cluster
;          If not end-of chain then set cluster number to next cluster
;              Calculate first sector in cluster, set as current sector. offset = 0
;          If end-of-chain then return readcount, we hit end of file.
;   Goto readloop


; FWRITE
;   writecount = 0
; writeloop:
;    Load current sector for offset
;    Write up to len bytes to sector (at sector offset), max 512-off bytes
;    len -= bytes written; writecount += bytes written
;    Write sector back to disk
;    If len > 0 then we need to read the next sector
;        If current sector in cluster < CLUSTSIZ then increment to next sequential sector, set offset in to 0
;        If not then we need to advance to the next cluster
;            Read the sector in the FAT for the current cluster
;            If not end-of-chain then set cluster number to next cluster
;                Calculate first sector in cluster, set as current sector. offset = 0
;            Else (hit end of file, need to expand)
;                Start at first sector of the FAT
;                Read sector of the FAT, search each entry for a free (0000) entry.
;                If none, then advance to the next sector (sequential)
;                    If last sector of the fat, then disk is full. Return early writecount.
;                If found then calculate its cluster number, change to end of file marker.
;                Re-read in sector of FAT containing current cluster
;                Change entry to be the cluster we just found. 
;                Change current cluster to the new cluster.
;                Calculate sector of the cluster. offset = 0
;    Goto writeloop

; FCREATE
;    Load in root directory
;    Scan for unused entry location
;    If not found then return failure, directory full
;    Set filename and attributes to directory entry
;    Read RTC to get creation date and time
;    Write directory sector back to disk
;    Start at first sector of the FAT
;    Read sector of the FAT, search each entry for a free (0000) entry.
;    If none, then advance to the next sector (sequential)
;    If last sector of the fat, then disk is full.
;       Re-read in sector with directory entry
;       Mark entry as unused
;       Return early, disk full
;    If found then calculate its cluster number, change to end of file marker.
;    Re-read in sector with directory entry
;    Set starting cluster to our found cluster. Length set to 0
;    Write directory back to disk.
;    Return success.
  
  


; FOPEN
;    Load in root directory
;    Scan for matching filename
;    If not found then return failure, no such file
;    Copy relevant information into file structure
;    Return success


; FDELETE
;    Load in root directory
;    Scan for matching filename
;    If not found then return failure, no such file
;    Copy starting cluster of file
;    Wipe entry (we're not supporting any kind of 'undelete' since it doesn't work with fragmented files)
;    Set current cluster entry to starting cluster of file
;  delloop:
;    Load in sector of FAT containing current cluster entry
;    Read in next cluster value and save
;    Set next cluster value to free (0000)
;    Write sector back to disk
;    If next cluste value wasn't end of file, then goto delloop


; FTRUNCALE
;    Load in root directory
;    Scan for matching filename
;    If not found then return failure, no such file
;    Copy starting cluster of file.
;    Set length to new length
;    clen = Calculate number of clusters required for new length. (length / (512 * CLUSTSIZ))
;    If clen = 0, then clen = 1
;    Set current cluster entry to starting cluster of file
;  loop:
;    Load in sector of FAT contiaining current cluster entry
;    Decrement clen
;    If 0 then no more clusters needed
;        Set current cluster entry to value of next cluster
;        If end of file then no need to truncate, return success
;        Set next cluster entry to EOF. 
;        Write fat sector to disk
;      truncloop:
;        Load in sector of FAT containing current cluster entry
;        Set current cluster entry to value of next cluster
;        Set next cluster entry to free (0000)
;        Write fat sector to disk
;        If next cluster entry was EOF, then we're done, return success
;        goto truncloop
;    Set current cluster entry to value of next cluster
;    If next cluster is EOF, then we need to expand the file
;      expandloop:
;        Search FAT for free cluster.
;        If none found, 
;          ... (Do we truncate to original size, or indicate new size???)
;          then return failure, disk full
;        Re-read in sector of FAT containing current cluster entry
;        Set next entry to found cluster.
;        Write FAT sector to disk
;        Set current cluster entry to value of next cluster
;        Load in sector of FAT containing current cluster entry
;        Decrement clen
;        If 0 then no more clusters needed
;            Set next pointer to EOF.
;            Write FAT sector to disk.
;            Return success
;        goto expandloop
;    goto loop
;    
;    


; FINDFREECLUS
;  Find first free cluster in FAT


#data _RAM
SECTLEFT	DS	2
FREEBYTES	DS	4
#code _ROM
; Find first free cluster
; Cluster found in DE, 0 if disk full
FINDFREECLUS:
#local
	LD	HL, FAT_LBA		; First sector of first FAT
	LD	DE, LBA
	CALL	COPY32
	
	CALL	CF_READ			; Read in sector
	
	LD	HL, SECTOR		; Point to start
	LD	BC, SECTOR+512		; End of current sector pointer
	
	LD	DE, (FAT_SECTFAT32)	; Read # of sectors in FAT (FAT16 only)
	LD	(SECTLEFT), DE		; 
	
	LD	DE, 2			; Current cluster # (table starts at 2)
	
	; Loop through sector looking for a free cluster
LOOPSECT:
	LD	A, (HL)			; First byte
	INC	HL
	LD	B, (HL)			; Second byte
	INC	HL
	OR	B			; Check if was 0
	JR	Z, FOUND
	INC	DE			; Next cluster #
	CMP16	BC			; Check if beyond end of sector
	JR	C, LOOPSECT		; If not loop till end of sector
	; Check if there's sectors left
	PUSH	DE			; Save cluster #
	
	LD	DE, (SECTLEFT)
	DEC	DE
	LD	(SECTLEFT), DE		; # of sectors left
	
	LD	A, D
	OR	E	
	JR	Z, NOFREE		; If no more sectors left, then disk is full
	
	; We need to read the next sector
	LD	HL, LBA
	LD	DE, 1
	CALL	ADD32_16		; Next sequential sector
	CALL	CF_READ			; Read next sector
	POP	DE			; Restore cluster #
	LD	BC, SECTOR+512		; End of current sector pointer
	JR	LOOPSECT		; Loop till free sector found
NOFREE:
	POP	DE			; Restore cluster #	
	LD	DE, 0			; Set # to 0 to indicate disk is full
FOUND:	
	; Cluster # in DE, non-zero for success
	RET
#endlocal


; Calculate free disk space
; 
FAT_DISKFREE:
#local
	LD	DE, 0
	LD	HL, FREEBYTES
	CALL	COPY32_16		; Clear free count
	
	LD	HL, FAT_LBA		; First sector of first FAT
	LD	DE, LBA
	CALL	COPY32
	
	CALL	CF_READ			; Read in sector
	
	LD	HL, SECTOR		; Point to start
	LD	BC, SECTOR+512		; End of current sector pointer
	
	LD	DE, (FAT_SECTFAT32)	; Read # of sectors in FAT (FAT16 only)
	LD	(SECTLEFT), DE		; 
	
	LD	DE, 0			; # of free clusters
	
	; Loop through sector looking for a free cluster
LOOPSECT:
	LD	A, (HL)			; First byte
	INC	HL
	LD	B, (HL)			; Second byte
	INC	HL
	OR	B			; Check if was 0
	JR	Z, NEXT
	INC	DE			; Increment free cluster count
NEXT:
	CMP16	BC			; Check if beyond end of sector
	JR	C, LOOPSECT		; If not loop till end of sector
	; Check if there's sectors left
	PUSH	DE			; Save cluster #
	
	LD	DE, (SECTLEFT)
	DEC	DE
	LD	(SECTLEFT), DE		; # of sectors left
	
	LD	A, D
	OR	E	
	JR	Z, DONE			; If no more sectors left, then we've got the count
	
	; We need to read the next sector
	LD	HL, LBA
	LD	DE, 1
	CALL	ADD32_16		; Next sequential sector
	CALL	CF_READ			; Read next sector
	POP	DE			; Restore cluster #
	LD	BC, SECTOR+512		; End of current sector pointer
	
	JR	LOOPSECT		; Loop till free sector found
DONE:
	POP	DE			; Restore free cluster count
	; Multiple # of clusters by the size of a cluster
	
	;LD	B, (FAT_CLUSTSIZ)	; # of sectors in a cluster
	; Multiply cluster count by # of sectors in a cluster
MULLOOP:
	LD	HL, FREEBYTES
	CALL	ADD32_16		; Add cluster count
	DJNZ	MULLOOP
	; We now have number of sectors free, multipy by 512 (bytes in a sector
	LD	HL, FREEBYTES
	LD	DE, FREEBYTES
	CALL	ADD32			; Multiply by 2
	; Multiply by 256 by shifting a whole byte
	LD	A, (FREEBYTES+2)
	LD	(FREEBYTES+3), A	; Shift high byte
	LD	A, (FREEBYTES+2)
	LD	(FREEBYTES+3), A	; Shift mid byte
	LD	A, (FREEBYTES+2)
	LD	(FREEBYTES+3), A	; Shift low byte
	XOR	A
	LD	(FREEBYTES+3), A	; Clear low byte
	; Free bytes is now the number of free bytes
	RET
#endlocal
