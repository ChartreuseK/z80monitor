; Implementation of the FAT16 filesystem
;

#local

#data _RAM
; All values are little endian
FAT_SECTSIZ	DS	2	; Bytes per sector
FAT_CLUSTSIZ	DS	1	; Sectors per cluster
FAT_RESVSECT	DS	2	; Reserved sectors
FAT_NFATS	DS	1	; Number of fats
FAT_DIRENTS	DS	2	; Root directory entries
FAT_TSECT	DS	2	; Total sectors 
FAT_MEDIA	DS	1	; Media byte
FAT_SECTFAT	DS	2	; Sectors per FAT (FAT12/16), if 0 then probably FAT32
FAT_SECTTRCK	DS	2	; Sectors per Track
FAT_NHEADS	DS	2	; Number of heads
FAT_FATSECT:	; First copy of the FAT starts after hidden sectors
FAT_HIDSECT	DS	4	; Number of hidden sectors
FAT_LGTSECT	DS	4	; Large total sectors (If TSECT=0)
BPB_SIZ		EQU	. - FAT_SECTSIZ

FAT_VOLID::	DS	4
FAT_VOLLBL::	DS	11	; One extra byte for null termination
FAT_VOLLNL_NULL	DS	1
VOL_SIZ		EQU	4+11	

FAT_ROOTLBA	DS	4	; LBA of the first sector of the root dir
FAT_FATLBA	DS	4	; LBA of the first FAT

ATTR_STR	DS	7	; 6 + null


FAT_TYPE	DS	1	; Detected Fat type - 12, 16, 32 (or 64 for ExFAT)
#code _ROM


SECTSIZ_O	EQU	11	; Offset from start of sector
VOLID_O		EQU	39	; 39 for FAT12/16, 67 for FAT32

FAT_INIT::
#local
	XOR	A
	LD	(LBA+0), A
	LD	(LBA+1), A
	LD	(LBA+2), A
	LD	(LBA+3), A	; Read in the boot sector
	LD	HL, SECTOR
	CALL	CF_READ
	
	LD	HL, SECTOR+SECTSIZ_O	
	LD	DE, FAT_SECTSIZ
	LD	BC, BPB_SIZ
	LDIR			; Copy relevant BPB into variables
	
	XOR	A
	; Calculate first FAT LBA
	LD	(FAT_FATLBA+3), A	; FAT is within the first 64k sectors
	LD	(FAT_ROOTLBA+3), A	; (Start of ROOT DIR LBA calc)
	LD	(FAT_FATLBA+2), A	; 
	LD	(FAT_ROOTLBA+2), A	; (Start of ROOT DIR LBA calc)
	LD	A, (FAT_RESVSECT+1)	; First FAT is right after the reserved
	LD	(FAT_FATLBA+1), A	; sectors
	LD	(FAT_ROOTLBA+1), A	; (Start of ROOT DIR LBA calc)
	LD	A, (FAT_RESVSECT+0)
	LD	(FAT_FATLBA+0), A
	LD	(FAT_ROOTLBA+0), A	; (Start of ROOT DIR LBA calc)
	
	; Calculate root directory LBA
	; Root directory starts after all copies of the FAT
	; FAT_ROOTLBA = ( FAT_FATLBA + (FAT_SECTFAT) * FAT_NFATS) )
	; We need calculate and add SECTORS_PER_FAT * NUM_FATS to ROOTLBA
	LD	HL, (FAT_SECTFAT)	
	
	LD	DE, HL			; Save a copy of SECTFAT
	LD	A, (FAT_NFATS)
	DEC	A
	LD	B, A
	JR	Z, SFNF_ADD 
	; We're assuming no 16-bit overflow of SECTFAT*NFATS)
SFNF_MUL:
	ADD	HL, DE
	DJNZ	SFNF_MUL
SFNF_ADD:
	; Add HL to our 32-bit FAT_ROOTLBA
	LD	A, (FAT_ROOTLBA+0)
	ADD	L
	LD	(FAT_ROOTLBA+0), A
	
	LD	A, (FAT_ROOTLBA+1)
	ADC	H
	LD	(FAT_ROOTLBA+1), A
	
	LD	A, (FAT_ROOTLBA+2)	; Probably not nessisary, FAT should be
	ADC	0			; in first 64k sectors anyways...
	LD	(FAT_ROOTLBA+2), A
	
	LD	A, (FAT_ROOTLBA+3)
	ADC	0
	LD	(FAT_ROOTLBA+3), A
	; FAT_ROOTLBA = ( FAT_FATLBA + (FAT_SECTFAT) * FAT_NFATS) )
	
	
	; Copy volume ID and name
	LD	HL, SECTOR+VOLID_O
	LD	DE, FAT_VOLID
	LD	BC, VOL_SIZ
	LDIR			; Copy volume ID and name
	XOR	A
	LD	(DE), A	; Null terminate volume ID string
	
	
	; Determine if we're FAT12,16,32,or ExFAT
	CALL	CALCVER
	
	
	RET
#endlocal


;--------
; Increment 28-bit LBA value
INC_LBA:
	LD	A, (LBA+0)
	ADD	1
	LD	(LBA+0), A
	LD	A, (LBA+1)
	ADC	0
	LD	(LBA+1), A
	LD	A, (LBA+2)
	ADC	0
	LD	(LBA+2), A
	LD	A, (LBA+3)
	ADC	0
	LD	(LBA+3), A
	RET
	


;--------
; Do a root directory listing
FAT_DIR_ROOT::
#local
	PUSH	BC
	PUSH	DE
	PUSH	HL
	PUSH	IX
	; Start at the first block of the ROOT dir
	LD	A, (FAT_ROOTLBA+0)
	LD	(LBA+0), A
	LD	A, (FAT_ROOTLBA+1)
	LD	(LBA+1), A
	LD	A, (FAT_ROOTLBA+2)
	LD	(LBA+2), A
	LD	A, (FAT_ROOTLBA+3)
	LD	(LBA+3), A
	
	LD	HL, STR_ROOTLIST
	CALL	PRINTN
	
	
	LD	HL, SECTOR
	CALL	CF_READ
	
	LD	IX, SECTOR		; Point to first entry
	
	LD	A, (FAT_DIRENTS)	; Root directory entries
	LD	E, A			; Save
	
	
DOENT:
	CALL	PRINTENT
	
	; Advance to the next entry
	DEC	E			; Check how many dirents are left
	JR	Z, DONE			; If none then we're done
	; Otherwise move to next entry
	LD	BC, 32			; 32 bytes per entry
	ADD	IX, BC
	; Check if we need to load the next block
	; We need to compare IX to SECTOR+512
	LD	BC, IX			; Transfer IX to HL so we can do
	LD	HL, BC			; a 16-bit compare
	LD	BC, SECTOR+512		; End address
	SBC	HL, BC
	ADD	HL, BC
	JR	C, NOLOAD		; If IX < SECTOR+512 then no need to load
	; Load a new block
	CALL	INC_LBA			; Next sequential block
	LD	HL, SECTOR
	CALL	CF_READ			; Read in block
	LD	IX, SECTOR		; Reset index
NOLOAD:
	JR	DOENT
DONE:
	POP	IX
	POP	HL
	POP	DE
	POP	BC
	RET
	
#endlocal


;--------
; Print a directory entry
;  IX - Points to entry
;
; Corrupts A, BC, HL
PRINTENT:
#local
	LD	A, (IX+11)		; First read attributes byte
	LD	B, A			; Save attribute byte
	AND	A
	JP	Z, SKIPENT		; Blank entries are unused?
	AND	$0F
	CP	$0F
	JP	Z, SKIPENT		; Skip LFN entries
	
	CALL	CLR_ATTRSTR
	BIT	0, B			; Read only
	JR	Z, THIDDEN
	LD	A, 'R'
	LD	(ATTR_STR+0), A
THIDDEN:
	BIT	1, B			; Hidden
	JR	Z, TSYSTEM
	LD	A, 'H'
	LD	(ATTR_STR+1), A
TSYSTEM:
	BIT	2, B			; System
	JR	Z, TVOLID
	LD	A, 'S'
	LD	(ATTR_STR+2), A
TVOLID:
	BIT	3, B			; Volume ID ?
	JR	Z, TDIR
	LD	A, 'V'
	LD	(ATTR_STR+3), A
TDIR:
	BIT	4, B			; Directory
	JR	Z, TARCHIVE
	LD	A, 'D'
	LD	(ATTR_STR+4), A
TARCHIVE:
	BIT	5, B			; Archive
	JR	Z, TDONE
	LD	A, 'A'
	LD	(ATTR_STR+5), A
TDONE:
	LD	HL, ATTR_STR
	CALL	PRINT
	LD	A, ' '
	CALL	PRINTCH
	
	LD	BC, IX			; Filename is right at the start
	LD	HL, BC
	LD	B, 8			; Name length
PRNAME:
	LD	A, (HL)
	INC	HL
	CALL	PRINTCH
	DJNZ	PRNAME
	
	LD	A, ' '			; Filename/Ext sepeator 
	CALL	PRINTCH			; (space for fixed-width listing)
	LD	B, 3			; Extension length
PREXT:
	LD	A, (HL)
	INC	HL
	CALL	PRINTCH
	DJNZ	PREXT
	
	LD	A, $09			; TAB
	CALL	PRINTCH
	
	; Now print filesize
	LD	B, (IX+31)		; High word of filesize
	LD	C, (IX+30)		
	CALL	PRINTWORD
	LD	B, (IX+29)		; Low word of filesize
	LD	C, (IX+28)		
	CALL	PRINTWORD
	
	LD	A, $09
	CALL	PRINTCH
	; Then print starting cluster
	LD	B, (IX+21)		; High word of start cluster
	LD	C, (IX+20)		
	CALL	PRINTWORD
	LD	B, (IX+27)		; Low word of start cluster
	LD	C, (IX+26)		
	CALL	PRINTWORD
	
	CALL	PRINTNL			; Tail call
SKIPENT:
	RET
#endlocal



;--------
; Reset the attribute string for entries
CLR_ATTRSTR:
	LD	A, ' '
	LD	(ATTR_STR), A
	LD	(ATTR_STR+1), A
	LD	(ATTR_STR+2), A
	LD	(ATTR_STR+3), A
	LD	(ATTR_STR+4), A
	LD	(ATTR_STR+5), A
	XOR	A
	LD	(ATTR_STR+6), A
	RET
	

;--------
; Determine the FAT version
; Calculate the total number of clusters for the partition
;  TCLUS = NDATASEC / SECPERCLUS
;  NDATASEC = TSECT - (RESVSECT + NFATS*SECTFAT + ROOTDIRSECT)
;  NDATASEC = TSECT - (FAT_ROOTLBA + ROOTDIRSECT)
;
; If NDATASEC < 4085      -- FAT12
;    NDATASEC < 65525     -- FAT16
;    NDATASEC < 268435445 -- FAT32
; Otherwise               -- ExFAT/FAT64
;
CALCVER:
#local
	; If Rootdir ents is 0 then FAT32+
	LD	A, (FAT_DIRENTS)
	;LD	B, (FAT_DIRENTS+1)
	OR	A, B
	JR	NZ, NOT32
	; Assume FAT32, we'll ignore exFAT as a possibility
	LD	A, 32
	LD	(FAT_TYPE), A
	RET
NOT32:
	; Determine if FAT12 or FAT16
	
	RET
#endlocal
;===============================================================================
; Static Data
STR_ROOTLIST:
	.ascii "Root dir listing:",10,13
	.ascii "-------------------",0


#endlocal
