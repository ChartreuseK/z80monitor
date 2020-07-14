; FAT16B file system, third attempt.
; Let's keep it somewhat simple and not have a hack of trying to be 
; generic 12/16/32 but in reality only supporting FAT16
; No partition support, filesystem must be directly on drive
; No long file name support
; Root directory only to start
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

#local	; Avoid poluting the monitor's namespace with all our variables
;-----------------------------------------------------------------------
#data _RAM

BPBVER		DS 1	; BPB version, 70, 40, or 34 
; Bios Parameter Block - Info about the filesystem
BPB:
; 2.0 BPB
BPB_SECTSIZE	DS 2	; # bytes in a sector (better be 512 for us)
BPB_CLUSTSIZE	DS 1	; # of sectors per cluster
BPB_RESVSECT	DS 2	; Reserved sectors
BPB_NFATS	DS 1	; Number of fats
BPB_DIRENTS	DS 2	; Root directory entries
BPB_TSECT	DS 2	; Total sectors 
BPB_MEDIA	DS 1	; Media byte (Don't care)
BPB_SECTFAT	DS 2	; Sectors per FAT if 0 then use BPB_SECTFAT32
; BPB 3.4 additions
BPB_SECTTRCK	DS 2	; Sectors per Track (Don't care)
BPB_NHEADS	DS 2	; Number of heads (Don't care)
BPB_HIDSECT	DS 4	; Number of hidden sectors (Don't care)
BPB_LGTSECT	DS 4	; Large total sectors (If TSECT=0)
BPB_SIZ		EQU	. - BPB
BPB_OFFSET	EQU	0Bh	; Offset within boot sector
BPB40_VOLLBL	EQU 	0x2B
BPB40_VOLID	EQU 	0x27

FAT_DATASTART	DS 4	; First sector of data (after fats, root dir, and reserved)
FAT_ROOTLBA	DS 4	; LBA of root directory
FAT_FATLBA	DS 4 	; LBA of first fat
FAT_ROOTSECT	DS 2	; # of sectors for root directory
FAT_CLUSTCNT	DS 2	; # of clusters in volume
DW_TEMP1	DS 4	; dword temp
;-----------------------------------------------------------------------
#code _ROM

;-----------------------------------------------------------------------
; Cluster ranges for various fat sizes 
FAT12_CLUSTER_MAX equ 0FF6h
FAT16_CLUSTER_MAX equ 0FFF6h
FAT32_CLUSTER_MAX equ 0FFFFFF6h

BPB70_FSTYPE equ 0x52	; Offset to FSTYPE in boot sector
BPB40_FSTYPE equ 0x36

FATDIR_START_CLUSTER equ 1Ah
FATDIR_SIZE 	     equ 1Ch

DIRENTSIZ	EQU	32
ENT_ATTR	equ	11		; Attribute byte
ENT_FS		equ	0x1C		; Size of file (DWORD)
ENT_CLUST	equ	0x1A		; Starting cluster


; File structure
  ; Name
FS_FNAME::	EQU	0		; 11 Filename (8+3 padded)
  ; Current Index within file
FS_SECT::	EQU	FS_FNAME+11	; 1  Sector within cluster
FS_CLUST::	EQU	FS_SECT+1	; 2  Current cluster
  ; Index for directory entry
FS_DIRENT::	EQU	FS_CLUST+2	; 2  Index within root directory
  ; Status flags 
FS_FLAGS::	EQU	FS_DIRENT+2	; 1  Flags:
  ; 80 - End of file. Current cluster is end of file
  ; 40 - Read only.   Ignored for now (blocks writes)
  ; 20  
  ; 10
  ; 08
  ; 04
  ; 02 - Modified. File has been written to (size may have changed)
  ; 01 - Open. File is opened and safe to use
FS_SIZE::	EQU	FS_FLAGS+1	; 4 - Size of file (in bytes)
FS_OFFSET::	EQU	FS_SIZE+4	; 4 - Current offset in bytes (For keeping track of length)
FS_RESERVED	EQU	FS_OFFSET+4	; Padding for future expansion 
FSLEN::		EQU	FS_RESERVED+7 ; currently 25 bytes, pad to 32 for future use

;-----------------------------------------------------------------------



;-----------------------------------------------------------------------
; Initialize a drive's data structure
;-----------------------------------------------------------------------
FAT_INIT::
#local
	LD	HL, LBA
	CALL	CLEAR32
	LD	HL, SECTOR
	CALL	CF_READ		; Read in sector 0
	
	; Ideally should do some kind of signature check here first
	; to determine that this is a FAT filesystem
	; If it's BPB3.4 we can't tell for sure
	; We also can't tell between BPB3.4 and older really, hopefully not an issue

	; Copy in BPB 3.4 values to variables, these are common to all
	; BPB types
	LD	HL, SECTOR+BPB_OFFSET	
	LD	DE, BPB
	LD	BC, BPB_SIZ
	LDIR			; Copy relevant BPB 3.4 into variables

	
	; Figure out BPB version
	LD	A, (SECTOR+0x42)	; Check if we're BPB 7.0
	AND	0FEh		
	CP	40			; 40 and 41 indicate 7.0 when here
	JR	Z, BPB70
	LD	A, (SECTOR+0x26)	; Check if we're BPB 4.0
	AND	0FEh
	CP	40			; 40 and 41 indicate 4.0 when here
	JR	Z, BPB40
	; Otherwise we must be 3.4, fall in
; BPB version 3.4
BPB34:
	LD	A, 034h
	LD	(BPBVER),A
	; Calculate FAT type by cluster count
	JR	CALCFAT
; BPB version 4.0
BPB40:
	LD	A, 040h
	LD	(BPBVER),A
	LD	HL, SECTOR+BPB40_FSTYPE
	JR	FSTYPE
; BBP version 7.0
BPB70:
	LD	A, 070h
	LD	(BPBVER),A
	LD	HL, SECTOR+BPB70_FSTYPE
	JP	FAIL_BPB70		; Unsupported for now, only normally
					; used for FAT32 anyways
FSTYPE:
	; Examine the FSTYPE field
	LD	DE, STR_FAT
	LD	B, 3
	CALL	MEMCMP
	JP	NZ, FAIL_UNKNOWN
	; We have a FAT filesystem, what size is it?
	; (Properly we need to check the full width, but we're lazy)
	LD	A, (HL)
	CP	' '		; If we find a space, then we go by 
	JR	Z, CALCFAT	; the cluster count
	CP	'3'		; If a 3 then it must be FAT32
	JP	Z, FAIL_FAT32	; 
	CP	'1'		; Only other options are 12 and 16
	JP	NZ, FAIL_UNKNOWN 
	INC	HL
	LD	A,(HL)
	CP	'2'		; FAT12
	JP	Z, FAIL_FAT12	
	CP	'6'		; Anything but 6 means we're not FAT16
	JP	NZ, FAIL_UNKNOWN
	LD	HL, 16		; We must be fat 16, save for later
	PUSH	HL
	JR	CONT1		
CALCFAT:
	LD	HL, 0		; Need to calculate FAT
	PUSH	HL		; Save for later
CONT1:
	; We need to do some more setup before we can calculate the 
	; cluster count
	; Convert 16-bit TSECT to LGTSECT if not already
	LD	HL, (BPB_TSECT)		; Total sectors (16-bit)
	LD	A, H
	OR	L
	JR	Z, CONT2
	; Copy 16-bit into 32-bit
	LD	(BPB_LGTSECT), HL	; Store low bytes
	XOR	A			; 0
	LD	(BPB_LGTSECT+2), A
	LD	(BPB_LGTSECT+3), A 	; Clear high bytes
	; Sector count has been enlarged
CONT2:
	CALL	PRINTI
	.ascii "FAT: Sectors per cluster:           $",0
	LD	A, (BPB_CLUSTSIZE) \ CALL PRINTBYTE
	CALL	PRINTNL
	

	LD	HL, (BPB_SECTSIZE)	; Check sector size
	LD	DE, 512			; Only 512 byte sectors supported
	CMP16	DE
	JP	NZ, FAIL_SECTSIZ	 
	; Calculate cluster count in volume
	
	
	; SectorsInRootDirectory = (BPB.RootDirectoryEntries * 32 + BPB.BytesPerSector - 1) / BPB.BytesPerSector
	LD	HL, (BPB_DIRENTS)	; # of root directory entries
	LD	(DW_TEMP1), HL		
	LD	HL, 0
	LD	(DW_TEMP1+2), HL	; Expand to 32-bits
	; Each directory entry is 32 bytes (left shift by 5)
	; Carry flag is clear from XOR
	LD	IX, DW_TEMP1
	LD	B, 5
MULDIRSIZ:
	AND	A			; Clear carry
	RL	(IX+0)
	RL	(IX+1)
	RL	(IX+2)			; Top byte unneeded as DIRENTS
	DJNZ	MULDIRSIZ		; is only 16-bits
	
	LD	HL, DW_TEMP1
	LD	DE, 511			; BPB.BytesPerSector - 1 
	CALL	ADD32_16		; (force round up when we divide)
	; We need to divide by 512 (bytes per sector). 
	; We'll shift right by 8, then one more (>>9)
	; Max size of result for FAT16 is 4096 (65535 root directory entries)
	LD	HL, (DW_TEMP1+1)	; >> 8, no need to worry about high byte
	SRL	H			; as (65535 * 32 + 511) = 0x2001DF
	RR	L			; >> 9 now
	LD	(FAT_ROOTSECT), HL	; Size of root directory in sectors
	
	; Display size of root directory
	CALL	PRINTI
	.ascii "FAT: Sectors for root directory:  $", 0
	LD	BC, (FAT_ROOTSECT)
	CALL	PRINTWORD
	CALL	PRINTNL
	
	; Calculate data start
	; DataStart = BPB.ReservedSectors + BPB.FATs * SectorsPerFAT + SectorsInRootDirectory
	LD	HL, FAT_DATASTART
	LD	DE, (BPB_RESVSECT)
	CALL	COPY32_16	
	CALL 	PRINTI
	.ascii "FAT: Reserved sectors:            $", 0
	LD	BC, (FAT_DATASTART+0) \ CALL PRINTWORD
	CALL	PRINTNL
		
	CALL 	PRINTI
	.ascii "FAT: Sectors per fat:             $", 0
	LD	BC, (BPB_SECTFAT) \ CALL PRINTWORD
	CALL	PRINTNL
	
	CALL 	PRINTI
	.ascii "FAT: Number of fats:                $", 0
	LD	A, (BPB_NFATS)
	CALL	PRINTBYTE
	CALL	PRINTNL
	
	LD	HL, FAT_DATASTART
	LD	DE, FAT_FATLBA
	CALL	COPY32			; Save block of the first fat
	
	
	LD	A, (BPB_NFATS)		; Number of fats
	LD	B, A
MULFATS:
	LD	DE, (BPB_SECTFAT)	; Number of sectors in a fat
	LD	HL, FAT_DATASTART
	CALL	ADD32_16
	DJNZ	MULFATS
	
	; Datastart currently points to the first block of the root
	; directory, save it for easy access later
	LD	HL, FAT_DATASTART
	LD	DE, FAT_ROOTLBA
	CALL	COPY32
	
	CALL	PRINTI
	.ascii "FAT: Root directory LBA:      $", 0
	LD	BC, (FAT_ROOTLBA+2) \ CALL PRINTWORD
	LD	BC, (FAT_ROOTLBA+0) \ CALL PRINTWORD
	CALL	PRINTNL
	
	; Finally add our sectors in the root directory
	LD	HL, FAT_DATASTART
	LD	DE, (FAT_ROOTSECT)
	CALL	ADD32_16
	
	CALL 	PRINTI
	.ascii "FAT: Data start sector:       $", 0
	LD	BC, (FAT_DATASTART+2) \ CALL PRINTWORD
	LD	BC, (FAT_DATASTART+0) \ CALL PRINTWORD
	CALL	PRINTNL
	
	
	; Now we can calculate the cluster count
	; ClusterCount = 2 + (SectorsInVolume - DataStart) / BPB.SectorsPerCluster
	LD	HL, BPB_LGTSECT		; Sectors in volume
	LD	DE, DW_TEMP1		; Keep in 32-bit for now to determine if this is FAT32
	CALL	COPY32		
	LD	DE, DW_TEMP1
	LD	HL, FAT_DATASTART	; Data start sector
	CALL	SUB32
	; Divide by sectors per cluster
	; Well assume Sectors per cluster is a power of two like it should be
	; However it's not strictly required to be, but is in practice
	; We're also not allowing a value of 0 (256)
	LD	HL, DW_TEMP1
	LD	A, (BPB_CLUSTSIZE)
	BIT	0, A			; Check that clustsiz isn't 1
	JR	NZ, NODIVCLUS		; If it is then don't divide
DIVSCLUS:
	CALL	SRL32			; Shift clustcnt right 1
	RRA				; Shift clustsiz right by 1 (who cares about carry in bits)
	BIT	0, A			; Check if we found our match
	JR	Z, DIVSCLUS
NODIVCLUS:
	LD	HL, DW_TEMP1
	LD	DE, 2
	CALL	ADD32_16		; + 2
	
	; Display calculated cluster count
	CALL	PRINTI
	.ascii "FAT: Cluster count:           $", 0
	LD	BC, (DW_TEMP1+2) \ CALL	PRINTWORD
	LD	BC, (DW_TEMP1+0) \ CALL	PRINTWORD
	CALL	PRINTNL
	
	; DW_TEMP1 now contains the cluster count determine FAT type
	POP	BC			; Restore fat value from earlier
	
	LD	HL, (DW_TEMP1+2)
	LD	A, H
	OR	L			; If > 0x0000FFFF then must be FAT32
	JP	NZ, FAIL_FAT32	
	LD	HL, (DW_TEMP1)
	LD	(FAT_CLUSTCNT), HL	; Save the 16-bit cluster count
	LD	A, H
	CP	0FFh
	JR	NZ, CONT3		; If < 0xFF00 no way of being FAT32
	LD	A, L
	CP	0F7h			; If >= 0xFFF7 then FAT32
	JP	NC, FAIL_FAT32
CONT3:	; Now we're either FAT16 or FAT12. Check if we have an override
	LD	C, A			; Check fat value from before
	AND	A
	JR	NZ, FAT16		; Override to FAT 16
	; Otherwise check if < 0xFF7 (FAT12)
	LD	A, H
	CP	010h
	JR	NC, FAT16		; If > 0x0FFF then FAT16
	CP	0Fh
	JR	NZ, FAIL_FAT12		; If < 0x0F00 then FAT12
	LD	A, L
	CP	0F7h
	JR	C, FAIL_FAT12		; If < 0x0FF7 then FAT12
FAT16:	; Now we know we're 100% FAT16, everything is good
	CALL	PRINTI
	.ascii "FAT: FAT16 filesystem detected  ",0
	CALL	PRINTI
	.ascii "BPB: ",0
	LD	A, (BPBVER) \ CALL	PRINTBYTE
	CALL	PRINTNL
	
	LD	A, (BPBVER)
	CP	034h
	JR	Z, NOLBL		; BPB 3.4 volumes have no label
	CALL	PRINTI
	.ascii "FAT: Volume Label: ",0
	LD	HL, SECTOR+BPB40_VOLLBL
	LD	B, 11
	CALL	PRINT_FIX
	CALL	PRINTI
	.ascii " ID: ",0
	LD	BC, (SECTOR+BPB40_VOLID)
	CALL	PRINTWORD
NOLBL:
	CALL	PRINTNL
	
	AND	A			; Clear carry for success
	RET				; And we're mounted!
	
; MOUNT FAILURES, carry set
FAIL_FAT12:
	CALL	PRINTI
	.ascii "FAT: FAT12 filesystem detected, only FAT16 supported", 0
	SCF \ RET
FAIL_FAT32:
	CALL	PRINTI
	.ascii "FAT: FAT32 filesystem detected, only FAT16 supported", 0
	SCF \ RET
FAIL_UNKNOWN:
	CALL	PRINTI
	.ascii "FAT: Unknown filesystem type", 0
	SCF \ RET
FAIL_BPB70:
	CALL	PRINTI
	.ascii "FAT: BPB7.0 detected, only 3.4 and 4.0 supported", 0
	SCF \ RET
FAIL_SECTSIZ:
	POP	HL	; Saved fat type
	CALL	PRINTI
	.ascii "FAT: Invalid sector size, only 512B supported", 0
	SCF \ RET
STR_FAT:	.ascii "FAT"	
#endlocal
;-----------------------------------------------------------------------






;-----------------------------------------------------------------------
; List the root directory
;-----------------------------------------------------------------------
FAT_DIR_ROOT::
#local
	LD	HL, FAT_ROOTLBA		; Root directory start
	LD	DE, LBA
	CALL	COPY32
	LD	HL, SECTOR
	CALL	CF_READ			; Read in first sector of directory
	
	CALL	PRINTI
	.ascii "Filename       RO   Size (HEX) start",13,10
STR_LISTBREAK:
	.ascii "------------------------------------",0
	      ; 0         1         2         3         4
	      ; 01234567890123456789012345678901234567890
	      ; FILENAME EXT   R    FILESIZE   CLUS
	CALL	PRINTNL
	LD	BC, (BPB_DIRENTS)	; Entries in root directory
	LD	HL, SECTOR		; Start of our sector buffer
	
	
	PUSH	BC
DIRLOOP:
	PUSH	HL
	CALL	PRINTENT		; Print directory entry HL
	POP	HL
	
	POP	BC			; Restore counter
	 LD	A, (HL)
	 AND	A			; If a directory entry starts with
	 JR	Z, DONE			; NULL then there are no more entries
	
	 DEC	BC			; Dec
	 LD	A, B
	 OR	C
	 JR	Z, DONE			; If no entries left then we're done
	PUSH	BC			; Save counter
	
	LD	DE, DIRENTSIZ
	ADD	HL, DE			; Advance to the next directory entry
	LD	DE, SECTOR+512		; End of sector
	CMP16	DE			; Compare HL with DE
	JR	C, NOLOAD		; If < SECTOR+512 then we don't need to load next
	; Otherwise Load next sector
	LD	HL, LBA
	LD	DE, 1
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
	
; Print out a directory entry
; HL - points to first byte of entry
PRINTENT:
#local
	
	LD	A, (HL)			; First byte of filename
	AND	A
	RET	Z			; Skip blank entries
	CP	$E5
	RET	Z			; Skip deleted entries

	PUSH	HL
	POP	IX			; Copy pointer into IX for indexing
	LD	A, (IX+ENT_ATTR)	; Read attribute byte
	; Attb byte is:
	; 1 - Read Only, 2 - Hidden , 4 - System, 8 - Volume ID
	; 16 - Directory, 32 - Archive
	AND	$0F			; Mask off low bits
	CP	$0F			; If Read only, hidden, system, and volume_id then is a LFN entry
	RET	Z			; Skip LFN entries
	AND	$0E			; If HIDDEN, SYSTEM, or VOLUME_ID 
	RET	NZ			; Then don't show files
	; We want our printed format to be:
	; 0         1         2         3         4
	; 01234567890123456789012345678901234567890
	; FILENAME EXT   R    FILESIZE   CLUS
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
	;CALL	PRINTNL
	;RET
	JR	CLUST
ISDIR:
	CALL	PRINTI
	.ascii	"<DIR>   ",0
	;RET
CLUST:
	CALL	PRINTI
	.ascii "   ",0
	LD	BC, (IX+ENT_CLUST)
	CALL	PRINTWORD
	CALL	PRINTNL
	RET
SPACE:
	LD	A, ' '
	CALL	PRINTCH
	DJNZ	SPACE
	RET
	
#endlocal	
#endlocal	
;-----------------------------------------------------------------------






;-----------------------------------------------------------------------
; Get FAT entry for cluster DE, result in DE
;-----------------------------------------------------------------------
FAT_GET:
#local
	PUSH	DE
	LD	HL, FAT_FATLBA		; Pointer to start of first fat
	LD	DE, LBA
	CALL	COPY32
	
	POP	DE
	PUSH	DE
	
	; # of clusters per sector of fat is 512/2 = 256
	; So D contains the sector offset to add, and E*2 the entry
	LD	HL, LBA
	LD	E, D			; Index to correct sector
	LD	D, 0
	CALL	ADD32_16
	LD	HL, SECTOR
	CALL	CF_READ			; Read in sector of first FAT
	POP	HL			; Cluster #
	LD	H, 0			; Only the part within this sector
	ADD	HL, HL			; Offset of entry (each is a word)
	LD	DE, SECTOR		
	ADD	HL, DE 			; Pointer to entry
	LD	DE, (HL)
	
	RET
#endlocal
;-----------------------------------------------------------------------


;-----------------------------------------------------------------------
; Set FAT entry to BC for cluster DE
;-----------------------------------------------------------------------
FAT_SET:
#local
	PUSH	BC
	
	PUSH	DE
	LD	HL, FAT_FATLBA		; Pointer to start of first fat
	LD	DE, LBA
	CALL	COPY32
	
	POP	DE
	PUSH	DE
	; # of clusters per sector of fat is 512/2 = 256
	; So D contains the sector offset to add, and E*2 the entry
	LD	HL, LBA
	LD	E, D			; Index to correct sector
	LD	D, 0
	CALL	ADD32_16
	LD	HL, SECTOR
	CALL	CF_READ			; Read in sector of first FAT
	
	POP	HL			; Cluster #
	LD	H, 0			; Only the part within this sector
	ADD	HL, HL			; Offset of entry (each is a word)
	LD	DE, SECTOR		
	ADD	HL, DE 			; Pointer to entry
	
	POP	BC
	LD	(HL), BC		; Set entry in sector
	
	LD	HL, SECTOR
	CALL	CF_WRITE		; Write back sector in first fat
	
	; Copy into all the other fats
	LD	A, (BPB_NFATS)
	LD	B, A
	JR	PRE_DEC			; Pre-decrement since we may 
FATLOOP:				; only have 1 fat
	PUSH	BC
	LD	HL, LBA
	LD	DE, (BPB_SECTFAT)	; Advance to the next FAT
	CALL	ADD32_16
	LD	HL, SECTOR		; Write the same sector to the
	CALL	CF_WRITE		; fat copies
	POP	BC
PRE_DEC:
	DJNZ	FATLOOP
	RET
#endlocal
;-----------------------------------------------------------------------



;-----------------------------------------------------------------------
; Get the next cluster in the chain 
; Input: DE - current cluster #
; Result: DE - next cluster # (0 if invalid)
; (Call FAT_GET instead if exact value desired)
;-----------------------------------------------------------------------
NEXTCLUST:
	CALL	FAT_GET
; Check if a cluster is valid, 
CLUSTVALID:
#local
	LD	A, D
	CP	00h
	JR	NZ, TEST1
	LD	A, E
	CP	02h		; Clusters > 2 are invalid
	JR	C, INVALID	; 
	LD	A, D
TEST1:
	CP	0FFh		; Test FFF6-FFFF - EOF, invalid, or bad
	RET	NZ		; 
	LD	A, E
	CP	0F6h
	RET	C		; If < 0FFF6h then it's valid
INVALID:		
	LD	DE, 0		; Invalid sector, return 0
	RET
#endlocal
;-----------------------------------------------------------------------


;-----------------------------------------------------------------------
; Convert cluster DE into LBA address (in LBA)
;-----------------------------------------------------------------------
CLUST2LBA:
	CALL	CLUSTVALID	; Check if a cluster is valid
	LD	HL, 0
	CMP16	DE		; If DE=0 then cluster is invalid
	SCF			; Set carry for failure
	RET	Z		

	DEC DE \ DEC DE		; Clusters start at 2 from the data area
	; LBA = FAT_DATASTART + (CLUSTER-2) * BPB_CLUSTSIZE
	; Need to do 32-bit math here
	; DE (16) * BPB_CLUSTSIZE (8)
	LD	HL, LBA
	CALL	COPY32_16	; Promote cluster # to 32-bits in LBA
	
	LD	A, (BPB_CLUSTSIZE)
	LD	E, A
	LD	D, 0
	LD	HL, DW_TEMP1
	CALL	COPY32_16	; Promote cluster size to 32-bits in TEMP1
	LD	HL, LBA
	LD	BC, DW_TEMP1	
	CALL	MUL32		; Multiply
	LD	HL, FAT_DATASTART
	LD	DE, LBA
	CALL	ADD32		; Add starting sector
	AND	A		; Success (clear carry)
	RET			; And we're done
;-----------------------------------------------------------------------




;-----------------------------------------------------------------------
; Find a file in the root directory
; HL - 8+3 space padded file name
; Returns: HL - pointer to directory entry (within SECTOR)
;  Carry set if file not found
;-----------------------------------------------------------------------
FAT_FINDFILE:
#local
	PUSH	HL
	POP	IX			; Save filename in IX
	
	LD	HL, FAT_ROOTLBA		; Start of root directory
	LD	DE, LBA
	CALL	COPY32
	LD	HL, SECTOR
	CALL	CF_READ			; First sector of root directory
	LD	BC, (BPB_DIRENTS)	; Entries in root directory
	LD	HL, SECTOR		; Start of our sector buffer
	
	
	PUSH	BC			; (1) Save entries 
DIRLOOP:
	PUSH	HL			; (2) Save sector
	POP	IY			; (2) Copy into IY for indexing
	PUSH	IY			; (2) Resave sector
	LD	A, (IY+ENT_ATTR)	; Read attribute byte
	; Attb byte is:
	; 1 - Read Only, 2 - Hidden , 4 - System, 8 - Volume ID
	; 16 - Directory, 32 - Archive
	AND	$0F			; Mask off low bits
	CP	$0F			; If Read only, hidden, system, and volume_id then is a LFN entry
	JP	Z, NOTFILE2
	; We're at a directory entry, see if filename matches
	LD	B, 11
	
	PUSH	IX			; (3) Save pointer to start of filename
NAMECHECK:
	LD	A, (IX)
	CP	(HL)			; Compare with current file
	JR	NZ, NOTFILE
	INC	HL
	INC	IX
	DJNZ	NAMECHECK
	
	
	; Filename matches, we have our file entry
	POP	IX 			; (3) Pointer to start of file name
	POP	HL			; (2) HL points to the directory entry
	POP	BC			; (1) Counter
	; Need to invert counter
	; Store index into BC
	PUSH	HL			; (1) Dir pointer
	LD	HL, (BPB_DIRENTS)
	AND	A			; Clear carry
	SBC	HL, BC			; Get index
	EX	DE, HL			; Save in DE
	POP	HL			; (1) Dir pointer
	AND	A			; Clear carry
	RET				; File found!
NOTFILE:	
	POP	IX			;(3) Pointer to start of filename
NOTFILE2:
	POP	HL			;(2) Pointer to dir ent start
	POP	BC			;(1) Restore counter
	LD	A, (HL)
	AND	A			; If a directory entry starts with
	JR	Z, DONE			; NULL then there are no more entries
	
	DEC	BC			; Dec counter
	LD	A, B
	OR	C
	JR	Z, DONE			; If no entries left then we're done
	PUSH	BC			; (1) Save counter
	PUSH	IX			; (2) Save filename
	LD	DE, DIRENTSIZ
	ADD	HL, DE			; Advance to the next directory entry
	LD	DE, SECTOR+512		; End of sector
	CMP16	DE			; Compare HL with DE
	JR	C, NOLOAD		; If < SECTOR+512 then we don't need to load next
	; Otherwise Load next sector
	LD	HL, LBA
	LD	DE, 1
	CALL	ADD32_16		; Increment LBA
	LD	HL, SECTOR
	CALL	CF_READ
	LD	HL, SECTOR		; Reset HL
NOLOAD:
	POP	IX			; (2) restore filename
	JP	DIRLOOP			;
DONE:
	; File not found
	SCF				; Set carry for error
	RET
#endlocal
;-----------------------------------------------------------------------


;-----------------------------------------------------------------------
; Check if a cluster DE is the end of a file (corrupts SECTOR)
;-----------------------------------------------------------------------
ISEOF:
#local
	LD	A, D
	OR	E
	JR	Z, YES			; File is empty, so yes
	CALL	FAT_GET
	LD	A, D
	CP	0FFh
	JR	NZ, NO			; <0xFF00
	LD	A, E
	CP	0F6h
	JR	NC, YES			; >=0xFFF6
NO:	; !=0, and FAT indicates it's not EOF
	AND	A			; Clear carry
	RET
YES:
	SCF				; Set carry
	RET
#endlocal
;-----------------------------------------------------------------------



;-----------------------------------------------------------------------
; Get the next free cluster from the FAT. 
; Returns:
;   DE - free cluster #
;   Carry flag set if no clusters free
;-----------------------------------------------------------------------
FAT_GETCLUSTER:
#local
	LD	HL, FAT_FATLBA
	LD	DE, LBA
	CALL	COPY32
	; Search fat for a 0000 entry. No need to skip first two as they're
	; gauranteed not to be 0000
	LD	HL, SECTOR
	CALL	CF_READ
	LD	DE, 0
	
NEXT:
	LD	BC, (HL)		; Read in entry
	LD	A, B
	OR	C
	JR	Z, FOUND		; Found free entry
	INC HL \ INC HL			; Next entry
	INC DE				; Keep track of cluster #
	LD	BC, SECTOR+512
	CMP16	BC			; Compare HL with DE
	JR	C, NEXT		; If < SECTOR+512 then we don't need to load next
	; Load next sector of FAT
	PUSH	DE			; Save cluster #
	 LD	HL, LBA
	 LD	DE, 1
	 CALL	ADD32_16		; Next block
	 LD	HL, SECTOR
	 CALL	CF_READ
	POP	DE			; cluster #
	; Check if we're at the end of the disk
	LD	HL, (FAT_CLUSTCNT)	; # of clusters on disk
	INC	HL
	INC	HL			; Index starts at 2
	CMP16	DE			; total-cur
	JR	Z, NOTFOUND		; cur = total
	JR	NC, NEXT		; cur < total
NOTFOUND:	; cur >= total
	LD	DE, 0
	SCF			; No space left on disk
	RET
FOUND:	; Cluster # in DE
	AND	A			; Clear carry
	RET
#endlocal
;-----------------------------------------------------------------------





;-----------------------------------------------------------------------
; Set the file name in the FS struct
; HL - Filename (8.3 null terminated)
; DE - Pointer to FS struct
;-----------------------------------------------------------------------
FS_SETFILENAME::
#local
	; Clear filename to make our life easier
	LD	A, ' '
	LD	B, 11
	PUSH	DE
CLR:
	LD	(DE), A		; Filename is first entry in FS struct
	INC	DE
	DJNZ	CLR
	POP	DE
	
	; Copy up to 8 chars till we see either a NULL or a .
	LD	B, 8
NAMEL:
	LD	A, (HL)
	AND	A
	JR	Z, DONE		; Once we hit a null we're done
	CP	'.'	
	JR	Z, DOEXT	; Or if we hit a dot
	AND	0DFH		; Force to uppercase
	LD	(DE), A		; Otherwise copy
	INC	HL
	INC	DE
	DJNZ	NAMEL
	; We copied 8 characters, make sure there's a dot here...
	LD	A, (HL)
	CP	'.'	
	JR	Z, DOEXT
	; Otherwise this was a bad filename
	SCF
	RET			; Carry indicates failure
DOEXT:
	LD	A, E
	ADD	B		; Add remaining to get to extension
	LD	E, A
	LD	A, D
	ADC	0
	LD	D, A
	
	LD	B, 3
EXTLOOP:
	INC	HL
	LD	A, (HL)
	AND	A
	JR	Z, DONE
	AND	0DFH		; Force to uppercase
	LD	(DE), A
	INC	DE
	DJNZ	EXTLOOP
DONE:
	AND	A		; Clear carry
	RET
#endlocal
;-----------------------------------------------------------------------



;-----------------------------------------------------------------------
; Open a file (filename must already be set)
; HL - Pointer to FS struct (preserved)
;-----------------------------------------------------------------------
FS_OPEN::
#local

	PUSH	HL			; Save our pointer
	 ; Search for the file in the directory
	 CALL	FAT_FINDFILE		; Search for file
	 JR	C, FAIL			; Fail if file not found
	 ; HL points to directory entry, DE is index
	POP	IX			; Restore FS struct into IX
	
	LD	(IX+FS_DIRENT), DE	; Save directory index
	LD	A, 0
	LD	(IX+FS_SECT), A		; Clear sector 
	LD	(IX+FS_OFFSET+0),A
	LD	(IX+FS_OFFSET+1),A
	LD	(IX+FS_OFFSET+2),A
	LD	(IX+FS_OFFSET+3),A	; Clear offset within file
	LD	DE, FATDIR_START_CLUSTER
	ADD	HL, DE
	LD	E, (HL) \ INC	HL
	LD	D, (HL) \ INC	HL
	LD	(IX+FS_CLUST), DE	; Start cluster
	; Size is right after the cluster	
	PUSH	DE ; Save start cluster
	 LD	E, (HL)	\ INC HL	; Low word of file size
	 LD	D, (HL) \ INC HL
	 LD	(IX+FS_SIZE), DE
	 LD	E, (HL)	\ INC HL	; high word of file size
	 LD	D, (HL) \ INC HL
	 LD	(IX+FS_SIZE+2), DE
	POP	DE ; Start cluster back into DE
	PUSH	IX			; Save pointer
	 ; Check if end of file for flags
	 LD	A, D
	 OR	E			; Check if file is empty	
	 JR	Z, ISEND
	 LD	A, 01h			; Not EOF and open
	 JR	FLAG1
ISEND:	
	 LD	A, 81h			; Is EOF and open
FLAG1:
	 LD	(IX+FS_FLAGS), A
	POP	HL			; Restore pointer for caller
	AND	A			; Clear carry, success
	RET
FAIL:
	POP	HL
	SCF
	RET
#endlocal
;-----------------------------------------------------------------------


;-----------------------------------------------------------------------
; Close open file
; HL - Pointer to FS struct
;-----------------------------------------------------------------------
FS_CLOSE::
#local
	PUSH	HL
	POP	IX
	BIT	0, (IX+FS_FLAGS)
	RET	Z			; File is already closed ignore
	
	; DEBUG: Print out fields
	; Flags Sector(in cluster) Cluster Dir.ent Size Offset
	PUSHALL
	CALL	PRINTI
	.ascii 10,13,"FS: DEBUG: Struct on close:",10,13,0
	LD	A, (IX+FS_FLAGS) \ CALL	PRINTBYTE
	LD	A, ' ' \ CALL PRINTCH
	LD	A, (IX+FS_SECT) \ CALL PRINTBYTE
	LD	A, ' ' \ CALL PRINTCH
	LD	BC, (IX+FS_CLUST) \ CALL PRINTWORD
	LD	A, ' ' \ CALL PRINTCH
	LD	BC, (IX+FS_DIRENT) \ CALL PRINTWORD
	LD	A, ' ' \ CALL PRINTCH
	LD	BC, (IX+FS_SIZE+2) \ CALL PRINTWORD
	LD	BC, (IX+FS_SIZE+0) \ CALL PRINTWORD
	LD	A, ' ' \ CALL PRINTCH
	LD	BC, (IX+FS_OFFSET+2) \ CALL PRINTWORD
	LD	BC, (IX+FS_OFFSET+0) \ CALL PRINTWORD
	CALL	PRINTNL
	POPALL

	
	LD	A, (IX+FS_FLAGS)
	AND	0FEh			; Mark file as closed
	LD	(IX+FS_FLAGS), A	
	AND	02h			; Check if modified
	RET	Z			; File is clean, don't update dir
	; File has been modified!
	; We need to return to the directory entry and update the size
	CALL	FILE_GET_DIRENT
	LD	DE, FATDIR_SIZE
	ADD	HL, DE
	LD	BC, (IX+FS_SIZE+0)
	LD	(HL), C \ INC HL
	LD	(HL), B \ INC HL
	LD	BC, (IX+FS_SIZE+2)
	LD	(HL), C \ INC HL
	LD	(HL), B \ INC HL
	; We could also update the modified time here if desired
	LD	HL, SECTOR
	CALL	CF_WRITE		; Write updated directory to disk
	AND	A			; Clear carry, success
	RET
#endlocal
;-----------------------------------------------------------------------



;-----------------------------------------------------------------------
; Add amount DE to FS_OFFSET field in FS struct (HL)
;-----------------------------------------------------------------------
ADD_OFFSET:
	LD	BC, FS_OFFSET
	ADD	HL, BC
	CALL	ADD32_16
	RET	
;-----------------------------------------------------------------------


;-----------------------------------------------------------------------
; Compare FS_OFFSET field with FS_SIZE in FS struct (IX)
;-----------------------------------------------------------------------
CMP_OFFSET_SIZE:
	LD	HL, (IX+FS_SIZE+2)	; High word first
	LD	DE, (IX+FS_OFFSET+2)
	CMP16	DE
	RET	C			; SIZE < OFFSET
	RET	NZ 			; SIZE > OFFSET
	; High bytes match, need to check low
	LD	HL, (IX+FS_SIZE+0)	; High word first
	LD	DE, (IX+FS_OFFSET+0)
	CMP16	DE
	RET				
	; C set if SIZE < OFFSET
	; Z set if SIZE == OFFSET
	; NC & !Z if SIZE > OFFSET
;-----------------------------------------------------------------------

;-----------------------------------------------------------------------
; Copy FS_OFFSET field into FS_SIZE, file has been expanded
;-----------------------------------------------------------------------
OFFSET_TO_SIZE:
	LD	HL, (IX+FS_OFFSET+2)
	LD	(IX+FS_SIZE+2), HL
	LD	HL, (IX+FS_OFFSET+0)
	LD	(IX+FS_SIZE+0), HL
	RET
;-----------------------------------------------------------------------


;-----------------------------------------------------------------------	
; Reaquire the directory entry for a open file
; IX points to file structure
; Returns:
;  HL - pointer to directory entry within SECTOR
;  LBA/SECTOR - pointing to sector of directory entry so we can
;   simply write back
;-----------------------------------------------------------------------
FILE_GET_DIRENT:
#local
	LD	HL, FAT_ROOTLBA
	LD	DE, LBA
	CALL	COPY32
	
	LD	E, (IX+FS_DIRENT)
	LD	D, (IX+FS_DIRENT+1)
	; Directory entries are 32 bytes, 16 (4 bits) fit per 512B sector
	; Get sector 
	LD	BC, 0			; Offset in sector
	SRL	D \ RR	E \ RR C
	SRL	D \ RR	E \ RR C
	SRL	D \ RR	E \ RR C
	SRL	D \ RR	E \ RR C	; >> 4, DE now contains the sector
	; And BC contains the entry within the sector * 16
	PUSH	BC	
	
	; DE is the sector offset
	LD	HL, LBA
	CALL	ADD32_16		; Add to root directory lba
	
	LD	HL, SECTOR
	CALL	CF_READ			; Read in sector in directory
	
	LD	HL, SECTOR
	POP	BC			; 
	ADD	HL, BC			; Offset in sector / 2
	ADD	HL, BC			; Offset in sector
	; HL now points at the directory entry, LBA at the sector it's in
	RET
#endlocal
;-----------------------------------------------------------------------

; BIOS is free to handle the far pointers more gracefully and normallize
; then before calling these functions that use them
;-----------------------------------------------------------------------
; Read next sector from open file
; IX - Pointer to FS struct (kernel space)
; C:HL - Far Pointer to buffer to read (Must be in low bank!)
; C - (low nybble only) bank pointer
;-----------------------------------------------------------------------
FS_READ::
#local
	PUSH	HL
	PUSH	BC		; Save far pointer
	 LD	A, H
	 AND 	080H		; Sanity check our address
	 JP	NZ, FAIL	; If in high bank then error out
	 LD	A, C
	 AND	0F0H		; Sanity check bank pointer
	 JP	NZ, FAIL	; If any high nybble data then error out
	 ; Okay far pointer is sane, we can begin
	 LD	A, (IX+FS_FLAGS)	; Check the file is open
	 AND	1
	 JP	Z, FAIL		; File is not open
	 LD	A, (IX+FS_FLAGS)
	 AND 	080h		; Are we at the end already?
	 JP	NZ, EOF
	 ; Okay try and read in the next sector
	 LD	A, (BPB_CLUSTSIZE)
	 CP	(IX+FS_SECT)	; 
	 JP	Z, NEWCLUST	; We need a new cluster
	 JP	C, FAIL		; FS_SECT was >= CLUSTSIZE already, something is wrong
	 JP	SEQCLUST	; Still space left
NEWCLUST:
	 ; Load next cluster in chain
	 LD	DE, (IX+FS_CLUST)
	 CALL	NEXTCLUST
	 LD	A, D
	 OR	E
	 JP	Z, EOFMARK		; No more data (or bad block in file/fat error)
	 LD	(IX+FS_CLUST), DE	; Next cluster in chain
	 LD	(IX+FS_SECT), 0		; Start of sector within cluster
SEQCLUST:
	 ; Read specified Cluster+sector
	 LD	DE, (IX+FS_CLUST)
	 CALL	CLUST2LBA
	 LD	HL, LBA
	 LD	D, 0
	 LD	E, (IX+FS_SECT)
	 CALL	ADD32_16
	 LD	HL, SECTOR
	 CALL	CF_READ
	
	 ; Copy data into banked address
	POP 	BC
	POP	DE			; Restore far pointer (dest)
	; Copy SECTOR to C:DE
	
	
	
	LD	A, C			; Destination bank
	LD	HL, SECTOR		; Source	
	LD	BC, 512			; Count
	PUSH	IX
	CALL	RAM_BANKCOPY		; Do a bank copy
	POP	IX
	
	; Add to offset the amount we read
	PUSH	IX \ POP HL
	LD	DE, 512			; Amount of bytes read
	CALL	ADD_OFFSET
	
	; Check if we're past the file size
	CALL	CMP_OFFSET_SIZE
	JR	C, EOFMARK2		; We're at the end of the file
	
	 ; Increment current sector
	INC	(IX+FS_SECT)
	LD	A, (BPB_CLUSTSIZE)
	CP	(IX+FS_SECT)	; 
	JP	NZ, NOINCFIX	; We didn't force a wrap thankfully
	; Need to advance to next sector or mark EOF
	; Load next cluster in chain
	LD	DE, (IX+FS_CLUST)
	CALL	NEXTCLUST
	LD	A, D
	OR	E
	JR	Z, EOFMARK2		; No more data (or bad block in file/fat error)
	LD	(IX+FS_CLUST), DE	; Next cluster in chain
	LD	(IX+FS_SECT), 0		; Start of sector within cluster
NOINCFIX:
	; And we're done
	LD	A, 1
	AND	A			; Clear carry
	RET
EOFMARK2:
	LD	A, (IX+FS_FLAGS)
	OR	080h
	LD	(IX+FS_FLAGS), A
	; Don't advance clust or sect
	JR	NOINCFIX
EOFMARK:
	LD	A, (IX+FS_FLAGS)
	OR	080h
	LD	(IX+FS_FLAGS), A
EOF:	
	XOR	A		; Indicate EOF
	JR	FAIL2
FAIL:	LD	A, 0FFh		; Indicate argument error
FAIL2:	POP	BC
	POP	HL
	
	SCF			; Carry for error
	RET
#endlocal
;-----------------------------------------------------------------------



;-----------------------------------------------------------------------
; Write current sector to open file, advance to next
; IX - Pointer to FS struct (kernel space)
; C:HL - Far Pointer to buffer to write from
; C - (low nybble only) bank pointer
;-----------------------------------------------------------------------
FS_WRITE::
#local
	PUSH	HL
	PUSH	BC		; Save far pointer
	 LD	A, H
	 AND 	080H		; Sanity check our address
	 JP	NZ, FAIL	; If in high bank then error out
	 LD	A, C
	 AND	0F0H		; Sanity check bank pointer
	 JP	NZ, FAIL	; If any high nybble data then error out
	 ; Okay far pointer is sane, we can begin
	 LD	A, (IX+FS_FLAGS)	; Check the file is open
	 AND	1
	 JP	Z, FAIL		; File is not open
	 LD	A, (IX+FS_FLAGS)
	 
	 PUSHALL
	 CALL	PRINTI
	 .ascii "1",0
	 POPALL
	 
	 ; Set modified flag while we're here.
	 OR	2h
	 LD	(IX+FS_FLAGS), A	; Modified set since we're writing
	 AND 	080h		; Are we at the end already?
	 CALL	NZ, EOF_ALLOC	; Okay we'll need to allocate a new cluster

	 ; Address specified Cluster+sector
	 LD	DE, (IX+FS_CLUST)
	 LD	A, D
	 OR	E
	 CALL	Z, EOF_ALLOC	; At start of empty file, allocate
	 PUSHALL
	 CALL	PRINTI
	 .ascii "2",0
	 POPALL
	 CALL	CLUST2LBA
	 LD	HL, LBA
	 LD	D, 0
	 LD	E, (IX+FS_SECT)
	 CALL	ADD32_16
	 
	 
	 ; Copy data from banked address to sector buffer
	POP 	BC
	POP	HL			; Restore far pointer (src)
	; Copy C:DE to SECTOR
	LD	A, C			; Destination bank
	LD	DE, SECTOR		; Destination	
	LD	BC, 512			; Count
	CALL	RAM_BANKCOPY		; Do a bank copy 
	LD	HL, SECTOR
	CALL	CF_WRITE		; Write data to disk
	
	; Add to offset the amount we wrote
	PUSH	IX \ POP HL
	LD	DE, 512			; Amount of bytes written
	CALL	ADD_OFFSET
	
	; Check if we're past the file size (and need to update it)
	CALL	CMP_OFFSET_SIZE
	CALL	C, OFFSET_TO_SIZE	; If so offset is our new size
	
	; Okay try and point to next sector 
	INC	(IX+FS_SECT)	; Next sector within cluster
	LD	A, (BPB_CLUSTSIZE)
	CP	(IX+FS_SECT)	; 
	JP	C, FAIL		; FS_SECT was >= CLUSTSIZE already, something is wrong
	JP	NZ, DONE	; More sectors still in cluster
	; No more sectors in current cluster, check if there's a cluster
	; already allocated after this one
	LD	DE, (IX+FS_CLUST)
	CALL	NEXTCLUST	; Try and get next cluster
	LD	A, D
	OR	E
	JR	Z, EOF		; We're at the end of the file, set flag
				; Leave FS_SECT invalid for now, should be fine
	; Not at end of file
	LD	(IX+FS_CLUST), DE	; Store next cluster
	LD	(IX+FS_SECT), 0		; First sector of
	JR	DONE			; And we're done
EOF:
	LD	A, (IX+FS_FLAGS)
	OR	80h			; Set EOF flag
	LD	(IX+FS_FLAGS), A
	; And we're done
DONE:
	LD	A, 1
	AND	A			; Clear carry
	RET
	
		
EOF_ALLOC:	; We're at the EOF and we need to write data
	; We need to allocate a new cluster to this file
	PUSH	IX
	 CALL	FAT_GETCLUSTER	; Get a new cluster in DE
	 JP	C, NOSPACE
	 ; Append to chain
	 POP	IX \ PUSH IX	; Restore FS pointer
	 PUSH	DE		; Save new cluster
	  LD	BC, 0FFFFh	; End of file marker
   	  CALL	FAT_SET
	  LD	DE, (IX+FS_CLUST)
	  LD	A, D
	  OR	E		; Test if empty file with null cluster
	  JR	Z, EMPTYFILE
	 POP	BC		; Restore new cluster into BC
	 PUSH	BC		; Keep saved
	  ; Skip if we're empty
	  CALL	FAT_SET	; Set current cluster's next to be the new one
	 POP	DE		; Next cluser #
FINISH:
	POP 	IX
	LD	(IX+FS_CLUST), DE	; Current is our new cluster
	LD	(IX+FS_SECT), 0		; First sector of new cluster
	LD	A, (IX+FS_FLAGS)
	AND	07Fh		; Remove EOF flag
	LD	(IX+FS_FLAGS), A
	RET
EMPTYFILE:
	; We need to save this new cluster into the directory entry
	CALL	FILE_GET_DIRENT	; Get our directory entry in HL
	POP	BC		; New cluster #
	LD	(IX+FS_CLUST), BC	; Save into file handle
	LD	DE, ENT_CLUST	; Cluster of this entry
	ADD	HL, DE
	LD	(HL),BC		; Save into directory entry
	LD	HL, SECTOR
	CALL	CF_WRITE	; Update directory info
	LD	DE, (IX+FS_CLUST)
	JP	FINISH	
NOSPACE:
	POP	IX
	LD	A, 1		; 1 indicates out of space
	JR	FAIL2
FAIL:	LD	A, 0FFh		; Indicate argument error
FAIL2:	POP	BC
	POP	HL
	
	SCF			; Carry for error
	RET
#endlocal
	RET
;-----------------------------------------------------------------------

;-----------------------------------------------------------------------
; Read entire open file to memory (max size 32kB)
; IX - Pointer to FS struct (kernel space)
; C:HL - Far Pointer to buffer to read (Must be in low bank!)
; C - (low nybble only) bank pointer
;-----------------------------------------------------------------------
FS_READFILE::
#local
	; Assume file is open an re-wound to the start
LOOP:
	PUSH	IX
	PUSH	BC
	PUSH	HL
	
	CALL	FS_READ
	JR	C, RDFAIL
	LD	A, '.'
	CALL	PRINTCH
	POP	HL
	POP	BC
	POP	IX
	; Advance to next address
	LD	DE, 512
	ADD	HL, DE		; Ready for next sector
	LD	A, H
	AND	080H
	JR	Z, LOOP
	; Out of memory to copy to, we're done early
	LD	A, 0FFh		; Set A to indicate truncation
	AND	A		; Clear carry
	RET
RDFAIL:
	POP	HL
	POP	BC
	POP	IX
	AND	A
	JR	NZ, ERROR
	; Otherwise end of file, we're done
	RET	; Carry already clear
ERROR:	
	SCF
	RET
#endlocal
;-----------------------------------------------------------------------


;-----------------------------------------------------------------------
; Rewind file 
; HL - Pointer to file struct
;-----------------------------------------------------------------------
FS_REWIND::
#local
	PUSH	HL
	POP	IX
	LD	A, (IX+FS_FLAGS)	; Check the file is open
	AND	1
	RET	Z			; File is not open
	
	XOR	A
	LD	(IX+FS_SECT), A		; Sector within cluster
	LD	(IX+FS_OFFSET+0), A
	LD	(IX+FS_OFFSET+1), A
	LD	(IX+FS_OFFSET+2), A
	LD	(IX+FS_OFFSET+3), A	; Clear offset within file
	
	CALL	FILE_GET_DIRENT		; Re open directory entry (for start cluster)
	LD	DE, FATDIR_START_CLUSTER
	ADD	HL, DE
	LD	BC, (HL)		; Read in start cluster
	LD	(IX+FS_CLUST), BC	; Save start cluster
	LD	A, B
	OR	C			; Check if start cluster is 0 (empty file)
	JR	Z, SETEOF		
	
	LD	A, (IX+FS_FLAGS)	; Read in flags
	AND	07Fh			; Clear EOF flag
	LD	(IX+FS_FLAGS), A
	RET
SETEOF:	LD	A, (IX+FS_FLAGS)	; Read in flags
	OR	080h			; Set EOF flag
	LD	(IX+FS_FLAGS), A
	RET
#endlocal
;-----------------------------------------------------------------------	
	
	
	
	
;-----------------------------------------------------------------------	
; Create a new file with the specified name
; HL - Pointer to FS struct with name filled in
;-----------------------------------------------------------------------	
FS_CREATE::
#local
	PUSHALL 
	CALL	PRINTI
	.ascii "FS: DEBUG FS_CREATE: ",10,13,0
	POPALL
	PUSH	HL			; Save filename/struct
	 ; First check if the file already exists
	 CALL	FAT_FINDFILE		; Search for file
	 JP	NC, EXISTS		; Fail if file already exists
	 ; Find first free or deleted entry
	
	 LD	HL, FAT_ROOTLBA		; Start of root directory
	 LD	DE, LBA
	 CALL	COPY32
	 LD	HL, SECTOR
	 CALL	CF_READ			; First sector of root directory
	 LD	BC, (BPB_DIRENTS)	; Entries in root directory
	 LD	HL, SECTOR		; Start of our sector buffer
	POP	IX			; Save filename back into IX
	
	
	PUSH	BC			; (1) Save entries 
DIRLOOP:
	PUSH HL
	LD	A,'.' \ CALL PRINTCH
	POP HL
	 LD	A, (HL)			; Check first byte of name
	 CP	0E5h			; Deleted entry
	 JR	Z, FOUND
	 AND	A			; Empty entry
	 JR	Z, FOUND
	
	POP	BC			; (1) Restore counter
	DEC	BC			; Dec counter
	LD	A, B
	OR	C
	JP	Z, NOSPACE		; If no entries left then unable to create
	PUSH	BC			; (1) Save counter
	
	 LD	DE, DIRENTSIZ
	 ADD	HL, DE			; Advance to the next directory entry
	 LD	DE, SECTOR+512		; End of sector
	 CMP16	DE			; Compare HL with DE
	 JR	C, NOLOAD		; If < SECTOR+512 then we don't need to load next
	 ; Otherwise Load next sector
	 LD	HL, LBA
	 LD	DE, 1
	 CALL	ADD32_16		; Increment LBA
	 LD	HL, SECTOR
	 CALL	CF_READ
	 LD	HL, SECTOR		; Reset HL
NOLOAD:
	 JP	DIRLOOP			;
FOUND:
	POP BC				; (1) Pop counter 
	; Found a free entry point (in HL)
	; Initialize this entry
	PUSH	HL			; Save pointer to entry
	 PUSH	IX
	 POP	DE
	 LD	B, 11
COPYNAME:				; Copy filename to entry
	 LD	A, (DE)
	 LD	(HL), A
	 INC	HL
	 INC	DE
	 DJNZ	COPYNAME
	 XOR	A
	 LD	(HL), A	\ INC HL	; 0B Attributes
	 LD	(HL), A	\ INC HL	; 0C Unused/extra attributes
	 LD	(HL), A	\ INC HL	; 0D Unused/Fine create time
	 LD	(HL), A	\ INC HL	; 0E Unused
	 LD	(HL), A	\ INC HL	; 0F Unused
	 LD	(HL), A	\ INC HL	; 10 Unused
	 LD	(HL), A	\ INC HL	; 11 Unused
	 LD	(HL), A	\ INC HL	; 12 Unused
	 LD	(HL), A	\ INC HL	; 13 Unused
	 LD	(HL), A	\ INC HL	; 14 Unused
	 LD	(HL), A	\ INC HL	; 15 Unused
	 LD	(HL), A	\ INC HL	; 16 (2) Last modified time
	 LD	(HL), A	\ INC HL	; 17
	 LD	(HL), A	\ INC HL	; 18 (2) Last modified date
	 LD	(HL), A	\ INC HL	; 19
	 LD	(HL), A	\ INC HL	; 1a (2) Start cluster
	 LD	(HL), A	\ INC HL	; 1b 
	 LD	(HL), A	\ INC HL	; 1c (4) File length
	 LD	(HL), A	\ INC HL	; 1d
	 LD	(HL), A	\ INC HL	; 1e
	 LD	(HL), A	\ INC HL	; 1f
	 LD	HL, SECTOR
	 CALL	CF_WRITE
	 CALL	PRINTNL
	POP	HL			; Return pointer to entry
	AND	A			; Clear carry
	RET
NOSPACE:				; No free entries left
EXISTS:
	CALL	PRINTNL
	SCF				; File already exists 
	RET
#endlocal
;-----------------------------------------------------------------------	

;-----------------------------------------------------------------------
; Delete the file with the specified name
; HL - Pointer to FS struct with name filled in
;-----------------------------------------------------------------------	
FS_DELETE::
	PUSHALL 
	CALL	PRINTI
	.ascii "FS: DEBUG FS_DELETE:",10,13,0
	POPALL
	CALL	FAT_FINDFILE		; Search for file
	JP	C, FAIL			; Fail if file not found
	; HL points to directory entry of file
	LD	(HL), 0E5h		; Mark file as deleted
	LD	DE, ENT_CLUST		; Offset to cluster
	ADD	HL, DE
	LD	BC, (HL)		; Read in starting cluster
	
	PUSH HL \ PUSH BC 
	CALL PRINTWORD
	LD	A, "-" \ CALL PRINTCH
	POP BC \ POP HL
	
	PUSH	BC			; Save cluster
	LD	(HL), 0	\ INC HL	; Clear starting cluster
	LD	(HL), 0	
	LD	HL, SECTOR
	CALL	CF_WRITE		; Write updated dir to disk

	POP	DE			; Restore current cluster
CLEARLOOP:
	LD	A, D
	OR	E
	JR	Z, DONE			; Check is already empty	
	PUSH	DE			; Save current cluster
	CALL	FAT_GET			; Value of next cluster in chain
	POP	HL			; Previous cluster
	EX	DE, HL			; Previous cluster into DE
	LD	BC, 0000h		; Mark cluster as free
	PUSH	HL			; Save next cluster
	CALL	FAT_SET			; previous cluster now marked as free
	POP	DE			; Next cluster

	PUSH	DE
	 PUSH	DE \ POP BC
	 CALL	PRINTWORD
	 LD	A, '-' \ CALL PRINTCH
	POP	DE
	; Now check if we're at the end of the chain
	LD	A, 0FFh
	CP	D			; FF - D
	JR	NZ, CLEARLOOP		; < FF00 
	; Cluster >FF00
	LD	A, 0F5h
	CP	E
	JR	NC, CLEARLOOP		; Cluster < FFF5
DONE: ; File is empty, no need to do any more.
	CALL	PRINTNL
	AND	A			
	RET
FAIL:
	SCF				; No such file
	RET
;-----------------------------------------------------------------------	
	


#endlocal
