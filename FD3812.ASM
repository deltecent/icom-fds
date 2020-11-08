;--------------------------------------------------------------------------
;
;  This is the disassembled source code for the 1K PROM found on the
;  "S-100 Interface" board (aka "8800 Interface") for the iCOM FD3812
;  floppy drive cabinet runing Lifeboat CP/M 1.4. The PROM is located
;  at F000h and expects the 128 byte 6810 RAM chip at F400. 
;
;  Note that a different PROM is used for Lifeboat CP/M on the FD3712.
;  Other iCOM software (e.g., FDOS, DEBBI) uses yet another PROM and
;  locates the PROM at C000h.
;
;  Disassembled by Mike Douglas, November, 2020.
;
;--------------------------------------------------------------------------

; FD3812 controller commands

cSTATUS	equ	00h		;read status
cREAD	equ	03h		;read sector
cWRITE	equ	05h		;write sector
cRDCRC	equ	07h		;validate sector CRC
cSEEK	equ	09h		;seek to track
cCLRERR	equ	0Bh		;clear error flags
cRESTOR	equ	0Dh		;seek to track 0
cSETTRK	equ	11h		;set track to seek
cDRVSEC	equ	21h		;set unit and sector
cWRTBUF	equ	30h		;write buffer
cRDBUF	equ	40h		;read buffer
cRESET	equ	81h		;reset the contorller
cLDCFG	equ	15h		;load configuration

; Controller status bits

sBUSY	equ	01h		;1=busy
sCRCERR	equ	08h		;1=CRC error
sWRTPRT	equ	10h		;1=write protected
sNOTRDY	equ	20h		;1=drive not ready

; Interface board registers

CMDOUT	equ	0C0h		;command output register
DATAIN	equ	0C0h		;data input from controller
DATAOUT	equ	0C1h		;data out to controller

; CP/M equates

CCPLEN	equ	0800h		;CP/M 1.4 fixed
BDOSLEN	equ	0D00h		;CP/M 1.4 fixed

WARMJMP	equ	0		;warm boot jump address
BDOSJMP	equ	5		;BDOS jump address
DEFDRV	equ	4		;CP/M default drive address

; Drive equates

NUMSEC	equ	52		;CP/M sectors per DD track

;--------------------------------------------------------------------------
; Interface board RAM
;--------------------------------------------------------------------------
	org	0F400h		;start of RAM on the interface board
	
RAMORG	equ	$		;start of RAM address
	ds	20h		;not used by PROM

; The following 16 bytes, starting at F420, are copied from the CP/M boot 
;   image into this area during cold boot. The data starts 16 bytes before
;   the start of the BIOS in the CP/M boot image.

PARAMS	equ	$		;parameter table copied from CP/M image
verStr	ds	7		;version string
densTrk	ds	1		;density has been set on the controller
				;  for this track number, else FFh
densTbl	ds	4		;density table per drive (four drives)
				;  value of 2 means double density
bufPtr	ds	2		;pointer to a buffer for write buffering
	ds	1
wrtVfy	ds	1		;write verify is 40h bit in this byte
	
; Remaining RAM usage
			
drvTrk	equ	$		;drive, track from CP/M as word
drvNum	ds	1		;drive number from CP/M
trkNum	ds	1		;track number from CP/M
secNum	ds	1		;sector number from CP/M
dmaAddr	ds	2		;buffer address

fDrvTrk	equ	$		;drive, track in read fifo as word
fifoDrv	ds	1		;drive number in read fifo
fifoTrk	ds	1		;track number in read fifo
	ds	1
fifoPos	ds	1		;current position in read fifo

bDrvTrk	equ	$		;drive, track in write buffer as word
bufDrv	ds	1		;drive number in write buffer
bufTrk	ds	1		;track number in write buffer
bufSec	ds	1		;sector number in write buffer
	ds	1

cDrvTrk	equ	$		;drive, track of current drive as word
curDrv	ds	1		;drive number of current drive
curTrk	ds	1		;track number of current drive
curSec	ds	1		;sector number of current drive

biosAdr	ds	2		;address of BIOS in RAM

STACK	equ	RAMORG+80h	;location of local stack

;--------------------------------------------------------------------------
; Start of PROM at F000h
;--------------------------------------------------------------------------
	org	0F000h
	
	jmp	boot		;a jump to F000h boots the disk

;--------------------------------------------------------------------------
; H2D128 - move 128 bytes from (HL) to (DE)
; moveH2D - move B bytes from (HL) to (DE)
;--------------------------------------------------------------------------
H2D128	mvi	b,128		;move 128 bytes

moveH2D	mov	a,m		;copy byte from (HL) to (DE)	
	stax	d
	inx	h
	inx	d
	dcr	b		;decrement byte count
	jnz	moveH2D

	ret

	db	0FFh,3Ah	;match the PROM

;--------------------------------------------------------------------------
; vCold, vWarm - cold start and warm start jump vectors
;--------------------------------------------------------------------------
vCold	jmp	cBoot		;cold boot jump vector
vWarm	jmp	wBoot		;warm boot jump vector

;--------------------------------------------------------------------------
; setTrk, setSec, setDma - standard BIOS entry points
;--------------------------------------------------------------------------
setTrk	mov	a,c		;save track specified in C
	sta	trkNum
	ret

setSec	mov	a,c		;save CP/M sector specified in C
	sta	secNum
	ret

setDma	mov	h,b		;save buffer address specified in BC
	mov	l,c
	shld	dmaAddr
	ret
	
	db	0FFh,0FFh	;match the PROM

;--------------------------------------------------------------------------
; BIOS disk functions jump table
;--------------------------------------------------------------------------
	jmp	home		;BIOS home function
	jmp	selDrv		;BIOS select drive function
	jmp	setTrk		;BIOS set track function
	jmp	setSec		;BIOS set sector function
	jmp	setDma		;BIOS set DMA function
	jmp	read		;BIOS read sector function
	jmp	write		;BIOS write sector function
	jmp	close		;ensure write buffer flushed
	jmp	densC		;get density for drive specified in C as
				;  drive + (densTbl-RAMORG)
	jmp	initAll		;initialize controller, drives, variables

;--------------------------------------------------------------------------
; boot - load 1st sector from track 0 into RAM at 80h and jump to it
;--------------------------------------------------------------------------
boot	lxi	sp,80h		;initialize stack pointer
	call	initAll		;initialize controller, drives, variables

	lxi	h,0		;drive 0, track 0
	shld	drvTrk

	mvi	c,1		;request sector 1
	call	setSec

	lxi	h,80h		;load sector into RAM at 80h
	shld	dmaAddr
	
	call	read		;read the sector
	jnz	boot		;error, try again

	lxi	h,RAMORG	;pass loader the RAM location in DE
	xchg			;DE->RAM
	lxi	h,vCold		;and a jump to CP/M cold boot in HL
	jmp	80h		;jump to the loaded sector

;--------------------------------------------------------------------------
; cBoot - CP/M cold boot processing
;--------------------------------------------------------------------------
cBoot	shld	biosAdr		;save address provided for the BIOS

	lxi	d,-16		;parameter table starts 16 bytes before 
	dad	d		;  the start of the BIOS

	lxi	d,PARAMS	;copy to parameter table in RAM
	mvi	b,16		;copying 16 bytes
	call	moveH2D		;copy (HL) to (DE)

	lxi	d,-128		;startup msg is 128 bytes before BIOS
	dad	d
	call	banner		;display it

	xra	a		;drive 0 is default drive
	sta	DEFDRV
	jmp	jmpCpm		;init and enter CP/M

;--------------------------------------------------------------------------
; wBoot - CP/M warm boot processing. The CP/M image is stored on track
;   one in double density with a physical sector skew of 3. This means
;   CP/M sectors are read as follows: 1,2 then 7,8, then 13,14, etc. A
;   total of three revolutions is required to read every sector.
;--------------------------------------------------------------------------
wBoot	lxi	sp,100h		;init stack pointer
	call	initAll		;init controller, drives, variables

	lxi	h,0100h		;drive 0, track 1
	shld	drvTrk

	lhld	biosAdr		;HL->start of the BIOS
	lxi	d,-(CCPLEN+BDOSLEN)  ;compute start address of the CCP
	dad	d		;HL->start of the CCP in RAM

	mvi	a,1		;A=starting sector

wbLoop	mov	c,a		;C=sector number
	push	b		;preserve it

	sta	secNum		;set sector number
	shld	dmaAddr		;set load address

	mov	a,h		;see if we've reached the BIOS address
	lhld	biosAdr
	cmp	h		;compare address now to BIOS address
	jnc	wbSkip		;reached the BIOS, don't read

	call	read		;read the next sector
	jnz	wBoot		;error, start over

wbSkip	pop	b		;get back sector in C
	mov	a,c		;see if odd or even sector
	rrc			;ls bit now in carry
	mov	a,c		;A is sector number again
	lhld	dmaAddr		;HL=start of last sector read
	jc	wbOdd		;odd sector (1st half of physical)

	adi	4		;CP/M sector skew of 6 (3 physical)
	inr	h		;location of next sector in RAM
	inr	h

wbOdd	inr	a		;incremented 1 or 5 sectors
	lxi	d,128		;128 bytes per CP/M sector
	dad	d		;HL->address for next sector

	cpi	NUMSEC+1	;past last sector?
	jc	wbNext		;no

	sui	NUMSEC		;wrap back to start
	cpi	3		;did we land on sector 3 (2nd rev)?

	lhld	biosAdr		;compute address for 2nd revolution
	lxi	d,-(CCPLEN+BDOSLEN-100h)
	dad	d
	jz	wbNext		;yes, on 2nd revolution

	inr	h		;else, one page later for 3rd revolution

wbNext	cpi	1		;if back to 1, we're done
	jnz	wbLoop		;read next sector
				;fall into jmpCpm
				
;--------------------------------------------------------------------------
; jmpCpm - perform the CP/M initialization required of the BIOS and
;   then enter the CCP.
;--------------------------------------------------------------------------
jmpCpm	lxi	b,80h		;default DMA address for CP/M
	call	setDma

	mvi	a,JMP		;init warm boot and BDOS jump vectors
	sta	WARMJMP		;address zero on page 0
	sta	BDOSJMP

	lhld	biosAdr		;warm boot jumps to BIOS+3
	inx	h
	inx	h
	inx	h
	shld	WARMJMP+1	;BIOS warm start

	lxi	d,-(BDOSLEN-3)	;compute BDOS entry address
	dad	d
	shld	BDOSJMP+1

	lda	DEFDRV		;pass default drive in C
	mov	c,a

	lxi	d,-(CCPLEN+6)	;compute CCP address
	dad	d
	pchl			;jump to the CCP

;--------------------------------------------------------------------------
; home - BIOS entry point. Flush dirty write buffer if present, then
;   do a restore to track 0 on the current drive.
;--------------------------------------------------------------------------
home	call	close		;close/flush any current activity
	lda	drvNum		;set CP/M drvNum as the current drive
	sta	curDrv
	jmp	doHome		;restore drive to track 0 and exit

;--------------------------------------------------------------------------
; selDrv - BIOS entry point. Select the drive passed in C
;--------------------------------------------------------------------------
selDrv	mov	a,c		;save passed drive number in drvNum
	sta	drvNum

	call	close		;close/flush any current activity
	mvi	a,0FFh		;indicate that track density is not set
	sta	densTrk		;  in the controller
	ret

;--------------------------------------------------------------------------
; close - Flush write buffer if it is dirty
;--------------------------------------------------------------------------
close	lda	bufDrv		;is a pending write buffered?
	inr	a		;  (testing for FFh)
	rz			;no, exit

	call	swapStk		;switch to local stack
	push	b		;preserve BC
	call	ckFlush		;flush if needed
	pop	b
	ret

	db	11h		;match PROM content

;--------------------------------------------------------------------------
; read - BIOS entry point. Read 128 byte CP/M sector from the drive,
;   track and sector specified in drvNum, trkNum, and secNum. Sector
;   is moved to the address specified in dmaAddr.
;--------------------------------------------------------------------------
read	call	swapStk		;switch to local stack
	call	getDens		;single or double density drive/track?
	jz	readReq		;single, a read is required

	lxi	h,drvTrk	;is a write pending for the same sector?
	lxi	d,bufDrv
	call	cmpDrvs		;compare drive, track, physical sector numbers
	jnz	chkFifo		;not same, so no flush needed

	ldax	d		;same logical sector too?
	cmp	m
	jnz	chkFifo		;no, so no flush needed

	call	ckFlush		;flush if dirty
	rnz			;exit if flush failed

chkFifo	lxi	h,drvTrk	;requested sector already in read fifo?
	lxi	d,fDrvTrk	;compare to drive, track, sector in fifo
	call	cmpDrvs
	jz	inFifo		;data already in read fifo

readReq	lxi	h,drvTrk	;a disk read is required, set CP/M drive and
	call	setCur		;  track as current drive and track
	call	filFifo		;read physical sector into the read fifo
	rnz			;exit if the read failed

inFifo	call	getDens		;is this sector single or double density?
	jz	rdFifo		;single, go read it from the fifo (A=0)

	lda	secNum		;A=CP/M sector num	
	inr	a		;compute 0 or 128 byte offset into fifo to 
	rrc			;  start the read
	ani	80h		;A=0 or 128 byte offset into physical sector

rdFifo 	lhld	dmaAddr		;get user buffer address into DE
	xchg
	call	movFifo		;move sector from fifo to (dmaAddr)
	rz			;always true

	db	0C3h,11h	;match PROM content

;--------------------------------------------------------------------------
; write - BIOS entry point. Write 128 byte CP/M sector to the drive,
;   track and sector specified in drvNum, trkNum, and secNum. Sector
;   data to be written is specified in dmaAddr. Double density writes
;   are buffered in RAM at (bufPtr).
;--------------------------------------------------------------------------
write	call	swapStk		;switch to local stack
	call	getDens		;single or double density?
	lhld	dmaAddr		;HL->user data to write
	jz	wrtReq		;write to disk required if single density

	lxi	h,drvTrk	;is a write pending for the same sector?
	lxi	d,bufDrv	;compare drive, track, physical sector numbers
	call	cmpDrvs
	jnz	bufdWrt		;no, so this will be a buffered write

	ldax	d		;is it the same logical sector too?
	cmp	m
	jz	mov2Buf		;yes, OK to just over-write the write buffer

; The pending write buffer is the other half of the physical sector for which
;   we are doing this write request. Go ahead and write the entire physical
;   sector now. Half from the write buffer, half from the new request.

	mvi	a,0FFh		;writing same physical sector, different logical
	sta	bufDrv		;write buffer will be clear after this flush

	lhld	dmaAddr		;put current write-from address on stack
	push	h

	lhld	bufPtr		;HL->pending write buffer
	lda	bufSec		;pending sector odd or even?
	rrc
	jc	mov2Ffo		;odd (1st half), so move it to fifo first

	xthl			;HL=dma for current write instead
		
mov2Ffo	call	wrtHL		;move sector (HL) to the write fifo
	pop	h		;gets opposite buffer just moved to fifo

wrtReq	call	wrtHL		;move sector (HL) to the write fifo

	lxi	h,drvTrk	;set caller drive, track
	call	setCur		;  as current
	call	doWrite		;do the write
	ret

	db	2Fh,0FEh	;match PROM content

; bufdWrt - Doing a buffered write. Flush existing write buffer if needed.
;   If the sector is in a directory block, force a write to disk.

bufdWrt	call	ckFlush		;flush write buffer if needed
	rnz			;write failed, exit

mov2Buf	lxi	h,drvTrk	;set the buffered track, drive, sector the 	
	lxi	d,bufDrv	;   same as the CP/M track, drive, sector
	call	H2D3		;move the three bytes (HL) to (DE)

	lhld	bufPtr		;HL->write buffer in BIOS data area
	xchg			;DE->write buffer in BIOS
	lhld	dmaAddr		;HL->user write sector
	call	H2D128		;move user sector to write buffer

	lhld	biosAdr		;compute address of block number in the BDOS
	lxi	d,-0AF7h	
	dad	d		;HL->current block number

	lxi	d,ckFlush	;jump to flush routine with returns
	push	d

	mov	a,m		;if in a directory block force a write to disk
	cpi	010H
	rz			;jumps to ckFlush
	cpi	013H
	rz
	cpi	016H
	rz
	cpi	017H
	rz
	pop	d		;restore stack
	xra	a		;no error and exit
	ret

	db	0Eh		;match PROM content

;--------------------------------------------------------------------------
; ckFlush - If the write buffer is dirty, write it to disk.
;--------------------------------------------------------------------------
ckFlush	lxi	h,bufDrv	;is a write buffered?
	mov	a,m		;(test for FF)
	inr	a
	rz			;no

	call	setCur		;curDrv=bufDrv
	mvi	a,0FFH		;nothing buffered any more
	sta	bufDrv
	call	filFifo		;read physical sector we're about to write
	rnz			;read failed

	lda	bufSec		;is even or odd CP/M sector buffered?
	rrc
	jnc	flEven		;even (2nd 128 bytes of physical sector)

	call	wrtBuf		;move buffered sector to write fifo
	call	skip128		;skip 1st 128 bytes read
	call	rd2Wrt		;copy 2nd 128 to write fifo
	jz	flWrite		;always true

	db	11h		;match PROM content

flEven	call	rd2Wrt		;copy 1st 128 bytes read to write fifo
	call	wrtBuf		;move buffered data to write fifo

flWrite	call	doWrite		;now write the sector
	ret

;--------------------------------------------------------------------------
; setCur - Set drive number, track, sector pointed to by HL as the
;   current drive, track, and sector.
;--------------------------------------------------------------------------
setCur	lxi	d,cDrvTrk	;(HL) to current drive, track, sector

H2D3	mvi	b,3		;move three bytes from (HL) to (DE)
	jmp	moveH2D

	db	06h		;match PROM content

;--------------------------------------------------------------------------
; cmpDrvs - Compare drive number, track, and physical sector of the
;   two drives pointed to by HL and DE. Returns zero true if all
;   three match.
;--------------------------------------------------------------------------
cmpDrvs	ldax	d		;A=DE->drive
	ora	a
	rm			;drive number not set

	cmp	m		;same as HL->drive?
	rnz			;no

	inx	h		;point to HL->track
	inx	d		;point to DE->track
	ldax	d		;on same track?
	cmp	m
	rnz			;no

	inx	h		;move to sector on each
	inx	d

	mov	a,m		;A=HL->sector
	inr	a		;convert to physical sector
	rrc
	ani	07FH
	mov	c,a		;C=HL->physical sector

	ldax	d		;form DE->physical sector
	inr	a
	rrc
	ani	07FH
	cmp	c		;same physical sector?
	ret			;return status

	db	0FEh,21h	;match PROM content

;--------------------------------------------------------------------------
; filFifo - Do a physical disk read of curDrv into the fifo on the
;   controller card.
;--------------------------------------------------------------------------
filFifo	mvi	a,0FFh		;set fifo content as undefined
	sta	fDrvTrk		
	xra	a		;no bytes in fifo
	sta	fifoPos

	call	rdPhys		;read physical sector into fifo
	mvi	a,1
	rnz			;return with A<>0 if error

	lxi	h,cDrvTrk	;show fifo contains current drive data
	lxi	d,fDrvTrk
	call	H2D3		;move the three bytes drive, track, sector

	mov	a,b		;A=B=0
	rz			;always true

	db	0C3h, 7Ah, 0F1h	;match PROM content

;--------------------------------------------------------------------------
; doWrite - Physically write the write fifo to disk
;--------------------------------------------------------------------------
doWrite	mvi	a,0FFh		;invalidate the read fifo
	sta	fDrvTrk
	call	wrtSec		;write the output fifo to disk
	rz			;return if no error

	mvi	a,1		;else return with A<>0 for error
	ret

;--------------------------------------------------------------------------
; swapStk - Switch to local stack. When caller later does a return,
;    it jumps to restStk to restore the stack and finally exit.
;--------------------------------------------------------------------------
swapStk	pop	d		;DE=return address
	lxi	h,0		;save SP in HL
	dad	sp

	lxi	sp,STACK	;set SP to local stack

	push	h		;push saved SP on stack
	lxi	h,restStk	;put restStk on stack so a return
	push	h		;   jumps to restStk

	xchg			;HL=return address
	pchl			;return from call to swapStk

; restStk - restore original SP and exit

restStk	pop	h		;restore original SP
	sphl
	ret			;return BIOS caller

	db	21h		;match PROM content

;--------------------------------------------------------------------------
; rdPhys - Read physical sector into the controller's fifo
;--------------------------------------------------------------------------
rdPhys	call	selSeek		;select drive, seek to track
	jnz	errExit		;failed

	mvi	c,5		;C=rety count

rdLoop	mvi	a,cREAD		;issue read command to controller
	call	doCmd
	ani	sCRCERR		;CRC error?
	rz			;no, exit

	call	clrErrs		;clear controller errors
	dcr	c		;decrment retry count
	jnz	rdLoop		;and try again

errExit	mvi	a,1		;return with A and status <> 0
	ora	a
	ret

;--------------------------------------------------------------------------
; movFifo - move 128 byte sector from FIFO to (DE)
;--------------------------------------------------------------------------
movFifo	lxi	h,fifoPos	;at right spot in controller fifo?
	cmp	m
	cnz	skip128		;no, skip 1st 128 bytes of fifo

	mvi	b,128		;moving 128 bytes
	mvi	a,cRDBUF	;issue read fifo command to the controller
	out	CMDOUT

fifoLp	in	DATAIN		;get next byte from fifo	
	stax	d		;store in RAM destination
	inx	d		
	inr	m		;increment our fifo position
	dcr	b		;decrement byte counter
	jnz	fifoLp

	xra	a		;leave controller in examine status mode
	out	CMDOUT
	rz			;always true

	db	11h		;match PROM content

;--------------------------------------------------------------------------
; skip128 - Skip through 128 bytes of the read fifo
;--------------------------------------------------------------------------
skip128	mvi	b,128		;skipping 128 bytes

	lxi	h,fifoPos	;HL->our fifo position
	mvi	a,cRDBUF	;issue read fifo command to the controller
	out	CMDOUT

skipLp	in	DATAIN		;get next byte from fifo
	inr	m		;increment our fifo position
	dcr	b		;decrement byte counter
	jnz	skipLp

	mov	a,b		;A=B=0 (examine status command)
	out	CMDOUT		;leave controller in examine status mode
	rz			;always true

	db	0CDh,17h,0F2h	;match PROM content

;--------------------------------------------------------------------------
; wrtSec - Physically write the write FIFO to disk
;--------------------------------------------------------------------------
wrtSec	call	selSeek		;select drive, seek to track
	jnz	errExit		;failed

	mvi	c,5		;C=retry counter

wrtLoop	mvi	a,cWRITE	;issue write command to the controller
	call	doCmd
	lda	wrtVfy		;verify the write?
	ani	40h
	rz			;no

	mvi	a,cRDCRC	;issue read CRC to validate
	call	doCmd
	ani	sCRCERR		;CRC error?
	rz			;no

	call	clrErrs		;clear errors in the controller
	dcr	c		;decrement retry count
	jnz	wrtLoop

	jmp	errExit		;give up

;--------------------------------------------------------------------------
; wrtBuf - Move write buffer to the controller's write fifo.
; wrtHL - Move (HL) to the controller's write fifo.
;--------------------------------------------------------------------------
wrtBuf	lhld	bufPtr		;HL->buffered write buffer

wrtHL	mvi	b,128		;moving 128 bytes
	mvi	a,cWRTBUF	;issue write buffer to the controller
	out	CMDOUT

wrtBfLp	mov	a,m		;move a byte to the controller
	out	DATAOUT
	inx	h
	dcr	b		;loop for all 128 bytes
	jnz	wrtBfLp

	mov	a,b		;A=B=0 (examine status command)
	out	CMDOUT		;leave controller in examine status mode
	rz			;always true

	db	0Eh		;match PROM content

;--------------------------------------------------------------------------
; rd2Wrt - Move 128 bytes from read fifo to write fifo on the controller
;--------------------------------------------------------------------------
rd2Wrt	mvi	b,128		;read 128 bytes

rwLoop	mvi	a,cRDBUF	;read buffer command to controller
	out	CMDOUT
	in	DATAIN		;get a read fifo byte
	mov	c,a		;C=byte from read fifo

	xra	a		;turn off RAM output
	out	CMDOUT

	mvi	a,cWRTBUF	;write a byte to write fifo
	out	CMDOUT
	mov	a,c		;output the byte just read
	out	DATAOUT

	xra	a		;leave controller is status state
	out	CMDOUT
	dcr	b		;repeat for 128 bytes
	jnz	rwLoop

	ret 			;exit

	db	0CDh,0B7h,0F2h	;match PROM content

;--------------------------------------------------------------------------
; selSeek - Select current drive, seek to current track, give
;   controller current sector to look for
;--------------------------------------------------------------------------
selSeek	mvi	d,005H		;D=retry counter

seekLp	call	getPSec		;A=drive and physical sector
	out	DATAOUT		;give them to the controller
	mvi	a,cDRVSEC	;set drive and sector
	call	outCmd

	call	seek		;seek to track
	rz			;success

	dcr	d		;decrement retry counter
	jnz	seekLp

	jmp	errExit		;give up with error

;--------------------------------------------------------------------------
; getPSec - For current drive, track, and CP/M sector, return byte
;   with drive in upper two bits and physical sector in lower six.
;--------------------------------------------------------------------------
getPSec	lhld	cDrvTrk		;H=track, L=drive
	mov	a,l		;A=drive
	rrc			;drive in upper two bits
	rrc
	mov	e,a		;E=drive in upper two bits

	call	densHL		;test density for current drive/track
	lda	curSec		;A=current CP/M sector
	jz	combine		;track is single density

	inr	a		;convert CP/M sector to physical sector
	rrc
	ani	03Fh		;mask to six bits

combine	ora	e		;combine unit with sector
	ret

	db	06h,0Bh		;match PROM content

;--------------------------------------------------------------------------
; getDens - Return density of drive and track from drvNum, trkNum
; densHL - Return density of drive, track contained in HL
; densC - Return density of drive indicated by C where C contains
;    offset in 6810 RAM for the drive in the drive table.
;
; Returns zero for single density, non-zero for double density
;--------------------------------------------------------------------------
getDens	lhld	drvTrk		;H=track, L=drive

densHL	mov	a,h		;on track 0?
	ora	a
	rz			;yes, exit as single density

	mvi	a,(densTbl-RAMORG)  ;index into drive density table
	add	l		    ;   by drive number
	mov	c,a

densC	lxi	h,RAMORG	;compute address in drive table
	mvi	b,0		;BC=offset to drive
	dad	b		;HL->drive in drive table
	mov	a,m		;A=density flag (2=double)
	ani	02h		;non-zero if double density
	ret

;--------------------------------------------------------------------------
; seek - Seek to curTrk. Set density in the controller for the track
;    using the load configuration command.
;--------------------------------------------------------------------------
seek	lda	curTrk		;A=current track
	lxi	h,densTrk	;HL->controller density
	cmp	m		;density set for this track?
	rz			;yes, so we're already on right track

	mov	m,a		;this track will now have density set
	mov	e,a		;preserve track in E

	lhld	cDrvTrk		;get density for current drive, track
	call	densHL
	jz	setDens		;A=0 if single density

	mvi	a,010H		;A=10h if double density

setDens	out	DATAOUT		;set density in controller
	mvi	a,cLDCFG	;load configuration
	call	outCmd

	mov	a,e		;A=track number
	ora	a		;test for track zero
	mvi	a,cRESTOR	;use restore command for track 0
	jz	doSeek

	mov	a,e		;else, set track number in controller
	out	DATAOUT
	mvi	a,cSETTRK	;set track to seek
	call	outCmd

	mvi	a,cSEEK		;use seek command

doSeek	call	doCmd		;issue seek or restor
	ani	(sNOTRDY+sCRCERR)   ;check for seek errors
	rz			;exit if no errors

	call	reset0		;reset controller, restore to track 0
	jmp	errExit

;--------------------------------------------------------------------------
; initAll - Initialize variables, reset controller, restore drive 0
;    to track 0
; reset0 - reset controller, restore current drive to track 0
; doHome - restore current drive to track 0
;--------------------------------------------------------------------------
initAll	mvi	a,0FFh		;nothing in write buffer
	sta	bufDrv
	xra	a
	sta	curDrv		;current drive=0
	inr	a		;set current sector=1
	sta	curSec

reset0	mvi	a,cRESET	;reset controller	
	call	outCmd

doHome	call	getPSec		;get drive:physical sector
	out	DATAOUT
	mvi	a,cDRVSEC	;set drive and sector num
	call	outCmd

	mvi	a,0FFh		;no track density set
	sta	densTrk	
	sta	fDrvTrk		;nothing in read fifo

	mvi	a,cRESTOR	;restore to track 0
				;fall into doCmd

;--------------------------------------------------------------------------
; doCmd - Issue command in A to the controller, wait for completion,
;   and return status.
;--------------------------------------------------------------------------
doCmd	call	outCmd		;give command to the controller

waitCmd	in	DATAIN		;wait for not busy
	ani	sBUSY
	jnz	waitCmd

	in	DATAIN		;return status of the operation
	ret

;--------------------------------------------------------------------------
; clrErrs - Issue the clear errors command to the controller
; outCmd - Issue the command in A to the controoler
;--------------------------------------------------------------------------
clrErrs	mvi	a,cCLRERR	;clear controller errors

outCmd	out	CMDOUT		;give command to the controller
	xra	a		;exit in examine status mode
	out	CMDOUT
	ret

;--------------------------------------------------------------------------
; banner - Display startup banner message found in the CP/M image
;   128 bytes prior to the start of the BIOS
;--------------------------------------------------------------------------
banner	mov	a,m		;A=next byte of message
	ora	a		;exit on zero byte
	rz

	mov	c,m		;pass character in C
	push	h
	call	outChar		;call BIOS output character
	pop	h
	inx	h		;point to next character
	jmp	banner

outChar	lhld	biosAdr		;point to BIOS outch entry
	mvi	l,0Ch
	pchl			;jump to it

	end


