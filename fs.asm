; These file routines assume operation in banked mode
; and will make use of bank copy and CURBANK for FILE
; struct.  Filename for create and delete assumed to be
; in kernel space
;
; FILE structs *MUST NOT CROSS BANK BOUNDARY*
;

FSERR_EXISTS equ 1	; File already exists
FSERR_NOENTS equ 2	; No free directory entries
FSERR_NOEXIST equ 3 ; File does not exist

; File struct contents:
; 8 bytes - filename (Must be uppercase)
; 3 bytes - extension (Must be uppercase)
; 1 byte - sector within cluster
; 4 bytes - current cluster (first 2 used for FAT16)
; 4 bytes - sector within file
; 512 bytes - current sector
;
; TOTAL 532 bytes per file

; Create a new file with a given name
; Allocate a directory entry for a 0 size file
;  HL - Pointer to filename null terminated (8.3 all caps)
FS_CREATE:
#local
	CALL FAT_SETFILENAME	; Convert file name and set active
	CALL FAT_OPENFILE	; See if file exists by trying to open it
	JR	C, NOEXISTS
	LD	A, FSERR_EXISTS
	SCF			; Set carry to indicate failure
	RET
	; Okay file doesn't exist, let's try and create it	
NOEXISTS:		
	LD	HL, STR_FSCREATE
	CALL	PRINTN
	CALL	FAT_NEWFILE	; Create file entry
	JR	NC, NOFAIL
	LD	A, FSERR_NOENTS	
	SCF
NOFAIL:
	RET
STR_FSCREATE:
	.ascii "Made it to newfile",10,13,0
#endlocal

; Delete a file with a given name
; Free all clusters, mark directory entry as free
;  HL - Pointer to filename (8.3 all caps)
FS_DELETE:
#local
	CALL FAT_SETFILENAME	; Convert file name and set active
	CALL FAT_OPENFILE	; See if file exists by trying to open it
	JR	NC, EXISTS
	LD	A, FSERR_NOEXIST
	SCF			; Set carry to indicate failure
	RET
	; Okay file exists, try and delete
EXISTS:		
	CALL	PRINTI
	.ascii "Deleting file...",10,13,0

	CALL	FAT_DELETEFILE	; Create file entry
	JR	NC, NOFAIL
	LD	A, FSERR_NOENTS	
	SCF
NOFAIL:
	RET
#endlocal

; Open a file with a given name
;  Requires a FILE struct in a loaded bank of the program
; Args:
;  HL - Pointer to FILE struct (in CURBANK space)
FS_OPEN:
#local
	RET
#endlocal


; Reads a sector into file struct, advances sector/cluster pointer
; If end of file then ?? returned
FS_READSEC:
    RET
; Write a sector from file struct to file, advances sector/cluster pointer
FS_WRITESEC:
    RET
; Rewind to beginning of file
; Args:
;  HL - Pointer to FILE struct (in CURBANK space)
FS_REWIND:
    RET