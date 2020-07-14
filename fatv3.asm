; FAT16B file system, third attempt.
; Let's keep it somewhat simple and not have a hack of trying to be 
; generic 12/16/32 but in reality only supporting FAT16
; No partition support, filesystem must be directly on drive
; No long file name support
; Root directory only to start
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


#data _RAM
BPBVER	DS	1	; BPB version, 70, 40, or 34 


#code _ROM
; Initialize a drive's data structure
FAT_MOUNT:
#local
	LD	HL, LBA
	CALL	CLEAR32
	LD	HL, SECTOR
	CALL	CF_READ		; Read in sector 0
	
	; Ideally should do some kind of signature check here first
	; to determine that this is a FAT filesystem
	; If it's BPB3.4 we can't tell for sure
	
	; Figure out BPB version
	LD	A, (SECTOR+0x42)	; Check if we're BPB 7.0
	AND	0FEh		
	CMP	40			; 40 and 41 indicate 7.0 when here
	JZ	BPB70
	LD	A, (SECTOR+0x26)	; Check if we're BPB 4.0
	AND	0FEh
	CMP	40			; 40 and 41 indicate 4.0 when here
	; Otherwise we must be 3.4, fall in
; BPB version 3.4
BPB34:
; BPB version 4.0
BPB40:
; BBP version 7.0
BPB70:
	
#endlocal


; Get FAT entry for cluster DE
FAT_GET:
	RET
FAT_SET:
; Set FAT entry to BC for cluster DE
	RET
