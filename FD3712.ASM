;--------------------------------------------------------------------------
;
;  This is the disassembled source code for the 1K PROM found on the
;  "S-100 Interface" board (aka "8800 Interface") for the iCOM FD3712
;  floppy drive cabinet runing Lifeboat CP/M 1.4. The PROM is located
;  at F000h and expects the 128 byte 6810 RAM chip at F400. 
;
;  Note that a different PROM is used for Lifeboat CP/M on the FD3812.
;  Other iCOM software (e.g., FDOS, DEBBI) uses yet another PROM and
;  locates the PROM at C000h.
;
;  Disassembled by Mike Douglas, November, 2020.
;
;--------------------------------------------------------------------------

; Interface board equates

ROMBASE	equ	0F000h		;base address of PROM
RAMBASE	equ	0F400h		;start of RAM on the interface board

; FD3712 controller commands

cSTATUS	equ	00h		;read status
cREAD	equ	03h		;read sector
cWRITE	equ	05h		;write sector
cRDCRC	equ	07h		;validate sector CRC
cSEEK	equ	09h		;seek to track
cCLRERR	equ	0Bh		;clear error flags
cRESTOR	equ	0Dh		;seek to track 0
cSETTRK	equ	11h		;set track to seek
cDRVSEC	equ	21h		;set unit and sector
cWRTBUF	equ	31h		;write buffer
cRDBUF	equ	40h		;read buffer
cSHIFT	equ	41h		;shift read buffer
cRESET	equ	81h		;reset the contorller
cLDCFG	equ	15h		;load configuration

; Controller status bits

sBUSY	equ	01h		;1=busy
sSKERR	equ	02h		;1=seek error
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

NUMSEC	equ	26		;sectors per track
SECLEN	equ	128		;length of sector

; Misc equates

CR	equ	0Dh
LF	equ	0Ah
BS	equ	08h
TAB	equ	09h

;--------------------------------------------------------------------------
; Interface board RAM
;--------------------------------------------------------------------------
	org	RAMBASE		;start of RAM on the interface board

RAMVECS	equ	$		;BIOS vectors in interface RAM
rCold	ds	3		;cold start
rWarm	ds	3		;warm start
rConSt	ds	3		;console status
rConIn	ds	3		;console character in 
rConOut	ds	3		;console character out
rList	ds	3		;list character out
rPunch	ds	3		;punch character out
rReader	ds	3		;reader character in
	ds	8

; The following 16 bytes, starting at F420, are copied from the CP/M boot 
;   image into this area during cold boot. The data starts 16 bytes before
;   the start of the BIOS in the CP/M boot image.

PARAMS	equ	$		;parameter table copied from CP/M image
verStr	ds	7		;version string
drvTrk	ds	1		;track num the drive is known to be on
	ds	4
bufPtr	ds	2		;pointer to a buffer for write buffering
	ds	1
wrtVfy	ds	1		;write verify is 40h bit in this byte

drvNum	ds	1		;drive number from CP/M
trkNum	ds	1		;track number from CP/M
secNum	ds	1		;sector number from CP/M
dmaAddr	ds	2		;buffer address
	ds	11
biosAdr	ds	2		;address of BIOS in RAM
	ds	5
	
lptPos	ds	1		;current position in line buffer
lptLen	ds	1		;printer line length and cold start flag
lptPrev	ds	1		;previous character printed
prevChr	ds	1		;previous character displayed
bufChr	ds	1		;buffered input character

STACK	equ	RAMBASE+80h	;location of local stack

;--------------------------------------------------------------------------
; Start of code
;--------------------------------------------------------------------------
	org	ROMBASE

	jmp	boot		;a jump to F000 boots disk
	db	' ALTAIRC '
	jmp	bootNC		;F00C: boot, no change to vector table
	db	15h		;match PROM content

; BIOS jump table

vCold	jmp	cBoot		;after cold boot processing
	jmp	wBoot		;perform warm boot
	jmp	rConSt		;console status RAM vector
	jmp	rConIn		;console character in RAM vector
	jmp	rConOut		;console character out RAM vector
	jmp	rList		;list character out RAM vector
	jmp	rPunch		;punch character out RAM vector
	jmp	rReader		;reader character in RAM vector
	jmp	home		;disk home
	jmp	selDrv		;select drive
	jmp	setTrk		;set track number
	jmp	setSec		;set sector number
	jmp	setDma		;set I/O buffer address
	jmp	read		;read sector
	jmp	write		;write sector
	ret			;close function in 3812
	db	0,0		;match PROM content
	jmp	ramByC		;RAMBASE indexed by C
	jmp	initAll		;initAll

	db	' 3712-V21 (C) LIFEBOAT ASSOCIATES 1979 '

;--------------------------------------------------------------------------
; boot - load 1st sector from track 0 into RAM at 80h and jump to it
;--------------------------------------------------------------------------

; (F06D) Jump here to boot using SIO vector table for console I/O

	lxi	h,sioVec	;use SIO vector table
	jmp	copyTbl

; (F073, default) Jump here to boot using 2SIO vector table for
;    console I/O

boot	lxi	h,sio2Vec	;use 2SIO vector table
	jmp	copyTbl

; (F079) Jump here to boot using monitor C000h PROM for console I/O

	lxi	h,monVec	;use monitor ROM for console I/O
	jmp	copyTbl

copyTbl	lxi	sp,80h		;init stack pointer
	call	initVec		;init vector table in RAM

; (F085) Jump here to boot without changing the vector table in RAM

bootNC	lxi	sp,80h		;init stack pointer

ldBoot	call	initAll		;init controller, drives, variables
	mvi	c,0		;load boot sector from track zero
	call	setTrk
	lxi	b,80h		;loading into RAM at 80h
	call	setDma
	call	read		;read the boot sector
	jnz	ldBoot		;error, try again

	lxi	h,RAMBASE	;give interface RAM pointer in DE
	xchg
	lxi	h,vCold		;cold start jump vector in HL
	jmp	80h		;jump to boot sector just loaded

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

	xra	a		;line length of zero means init printer
	sta	lptLen

	call	banner		;display startup message

	xra	a		;drive 0 is default drive
	sta	DEFDRV
	jmp	jmpCpm		;init and enter CP/M

;--------------------------------------------------------------------------
; wBoot - CP/M warm boot processing. The CP/M image is stored on tracks
;   zero and one with a physical sector skew of 3. 
;--------------------------------------------------------------------------
wBoot	lxi	sp,100h		;init stack poiner
	call	initAll		;init controller, drives, variables

	mvi	c,0		;load starts on track 0	
	call	setTrk

	lhld	biosAdr		;HL->start of the BIOS
	lxi	d,-(CCPLEN+BDOSLEN)  ;compute start address of the CCP
	dad	d		;HL->start of the CCP in RAM

	inr	h		;HL->2nd page of CCP
	mvi	a,4		;start loading at sector 4
	call	readTrk		;load track 0

	mvi	c,1		;load rest of CP/M from track 1
	call	setTrk

	lhld	biosAdr		;compute address for track 1
	lxi	d,-(CCPLEN+BDOSLEN)  ;compute start address of the CCP
	dad	d
	lxi	d,(NUMSEC-1)*SECLEN  ;bytes loaded from track 0
	dad	d		;HL->where to load track 1

	mvi	a,1		;start on sector 1
	call	readTrk		;read a track
	jmp	jmpCpm		;enter CPM

readTrk	sta	secNum		;set sector number
	shld	dmaAddr		;set load address

	lda	biosAdr+1	;MSB of BIOS address
	dcr	a		;have we reached the BIOS
	cmp	h
	jc	wbSkip		;reached BIOS, don't read

	call	read		;read the next sector
	jnz	wBoot		;error, start over

wbSkip	lhld	dmaAddr		;HL=start of last sector read
	lxi	d,3*SECLEN	;3 sector interleave
	dad	d

	lda	secNum		;increment sector by 3
	adi	3
	cpi	NUMSEC+1	;past last sector?
	jc	readTrk		;no

	sui	NUMSEC		;wrap back to start
	lxi	d,-(NUMSEC*SECLEN)
	dad	d
	cpi	1		;if back to sector 1, we're done
	jnz	readTrk

	ret

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
; banner - Display startup banner message found in the CP/M image
;   128 bytes prior to the start of the BIOS
;--------------------------------------------------------------------------
banner	mov	a,m		;A=next byte of message
	ora	a		;exit on zero byte
	rz

	mov	c,m		;pass character in C
	inx	h		;point to next character
	push	h
	call	outChar		;call BIOS output character
	pop	h
	jmp	banner

outChar	lhld	biosAdr		;point to BIOS conOut entry
	lxi	d,0Ch		
	dad	d
	pchl			;jump to it

;--------------------------------------------------------------------------
; ramByC - return pointer in HL to RAMBASE + value passed in C
;--------------------------------------------------------------------------
ramByC	lxi	h,RAMBASE
	mvi	b,0
	dad	b
	ret

;--------------------------------------------------------------------------
; home, setTrk, selDrv, setSec, setDma - standard BIOS entry points
;--------------------------------------------------------------------------
home	jmp	doHome

setTrk	mov	a,c		;save track specified in C
	sta	trkNum
	ret        

selDrv	mov	a,c		;save drive number in drvNum
	sta	drvNum
	mvi	a,0FFh		;track num drive is on is not known
	sta	drvTrk
	ret

setSec	mov	a,c		;save sector specified in C
	sta	secNum
	ret

setDma	mov	h,b		;save buffer address specified in BC
	mov	l,c
	shld	dmaAddr
	ret

;--------------------------------------------------------------------------
; read - BIOS entry point. Read 128 byte CP/M sector from the drive,
;   track and sector specified in drvNum, trkNum, and secNum. Sector
;   is moved to the address specified in dmaAddr.
;--------------------------------------------------------------------------
read	call	selSeek		;select drive, seek track
	jnz	errExit		;error

	mvi	c,10		;C=retry counter

rdRtry	mvi	a,cREAD		;issue read command
	call	doCmd
	ani	(sNOTRDY+sCRCERR)  ;check read status
	jz	readXfr		;good read, fo transfer data

	call	clrErrs		;clear controller errors 
	dcr	c		;decrement retry counter
	jnz	rdRtry		;and try again

	jmp	errExit		;give up, read failed

readXfr	lhld	dmaAddr		;HL->read destination
	mvi	c,SECLEN	;C=count of bytes to move
	mvi	a,cRDBUF	;enable fifo buffer output
	out	CMDOUT

	in	DATAIN		;get 1st byte and store
	mov	m,a
	inx	h

	xra	a		;not really needed, bit 0
	out	CMDOUT		;  already clear
	dcr	c		;one byte moved

rdLoop	mvi	a,cSHIFT	;shift fifo to next byte
	out	CMDOUT

	in	DATAIN		;get the next byte 
	mov	m,a		;and save in user buffer
	inx	h

	xra	a		;set bit zero back to zero
	out	CMDOUT
	dcr	c		;repeat for all bytes
	jnz	rdLoop

	ret

;--------------------------------------------------------------------------
; write - BIOS entry point. Write 128 byte CP/M sector to the drive,
;   track and sector specified in cpmDrv, cpmTrk, and cpmSec. Sector
;   data to be written is specified in dmaAddr. 
;--------------------------------------------------------------------------
write	call	selSeek		;select drive, seek to track
	jnz	errExit

	lhld	dmaAddr		;HL->user buffer
	mvi	c,SECLEN	;C=count of bytes to move

wrtLoop	mov	a,m		;A=next byte to write
	out	DATAOUT		;give to controller
	
	mvi	a,cWRTBUF	;command to move byte to write buffer
	out	CMDOUT	
	xra	a		;return bit zero to zero
	out	CMDOUT
	
	inx	h		;move to next byte
	dcr	c
	jnz	wrtLoop

	mvi	c,10		;C=retry counter

wrtRtry	mvi	a,cWRITE	;do the write to disk
	call	doCmd
	ani	sNOTRDY		;error?
	jz	chkCrc		;no, go check CRC

	call	clrErrs		;reset errors
	jmp	errExit		;and give up

chkCrc	lda	wrtVfy		;verifying writes?
	ani	40h		;this bit set if we are
	rz			;not verifying

	mvi	a,cRDCRC	;read sector to check CRC
	call	doCmd
	ani	(sNOTRDY+sCRCERR)  ;any errors?
	rz			;no, good write

	call	clrErrs		;clear controller errore
	dcr	c		;decrement retry count
	jnz	wrtRtry		;and try again

errExit	mvi	a,1		;return with A and status <> 0	
	ora	a
	ret

;--------------------------------------------------------------------------
; selSeek - Select current drive, seek to current track, give
;    controller current sector to look for
;--------------------------------------------------------------------------
selSeek	xra	a		;clear configuration bits
	out	DATAOUT
	mvi	a,cLDCFG	;issue the command
	call	outCmd

	call	selSec		;select drive, set sector
	call	seek		;seek to requested track
	ret

selSec	lda	drvNum		;get drive number 0-3
	ani	03h
	rrc			;put drive number in upper two bits
	rrc
	mov	c,a		;C=drive in upper two bits

	lda	secNum		;combine drive with sector number
	ora	c
	out	DATAOUT		;give to controller

	mvi	a,cDRVSEC	;issue set sector command
	call	outCmd
	ret

;--------------------------------------------------------------------------
; seek - Seek to curTrk. Set density in the controller for the track
;    using the load configuration command.
;--------------------------------------------------------------------------
seek	mvi	c,2		;C=retry counter

	lda	trkNum		;A=requested track	
	lxi	h,drvTrk	;HL->track drive is on
	cmp	m		;on right track already?
	rz			;yes

	mov	m,a		;save track drive is on
	lda	trkNum		;give new track # to controller
	out	DATAOUT
	
	mvi	a,cSETTRK	;and issue set track command
	call	outCmd

	mvi	a,cSEEK		;seek to the track specified
	call	doCmd
	ani	(sNOTRDY+sCRCERR)   ;seek error?
	rz			;no, exit

	call	clrErrs		;else, clear controller errors
	mvi	m,0FFh		;track not valid yet	
	dcr	c		;decrement retry counter
	jnz	seek		;** will loop forever **

	call	reset0		;reset controller, seek track 0
	mvi	a,sSKERR	;return seeke error
	ora	a		;force non-zero status
	ret

;--------------------------------------------------------------------------
; initAll - Initialize variables, reset controller, restore drive 0
;    to track 0
; reset0 - reset controller, restore current drive to track 0
; doHome - restore current drive to track 0
;--------------------------------------------------------------------------
initAll	xra	a		;default to drive 0
	sta	drvNum
	inr	a		;default to sector 1
	sta	secNum

reset0	mvi	a,cRESET	;reset controller
	call	outCmd

doHome	call	selSec		;select drive and sector
	mvi	a,0FFh		;current drive track not known
	sta	drvTrk
	mvi	a,cRESTOR	;issue restore to track 0
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
; outCmd - Issue the command in A to the controller
;--------------------------------------------------------------------------
clrErrs	mvi	a,cCLRERR	;clear controller errors

outCmd	out	CMDOUT		;give command to the controller
	xra	a		;exit in examine status mode
	out	CMDOUT
	ret

;--------------------------------------------------------------------------
; moveH2D - move B bytes from (HL) to (DE)
;--------------------------------------------------------------------------
moveH2D	mov	a,m
	stax	d
	inx	h
	inx	d
	dcr	b
	jnz	moveH2D
	ret

initVec	lxi	d,RAMVECS	;DE->BIOS jumpers in interface RAM
	mvi	b,8		;copy 8 vectors

;--------------------------------------------------------------------------
; copyVec - copy eight entry vector table from (HL) to (DE). Inserts
;    a JMP instruction for each vector address
;--------------------------------------------------------------------------
copyVec	mvi	a,JMP		;store JMP instruction
	stax	d
	inx	d

	mov	a,m		;move vector LSB
	stax	d
	inx	h
	inx	d

	mov	a,m		;move vector MSB
	stax	d
	inx	h
	inx	d

	dcr	b		;do next vector
	jnz	copyVec

	ret
	
;--------------------------------------------------------------------------
; 88-2SIO drivers
;--------------------------------------------------------------------------
; Initialize 2SIO port

sio2Ini	mvi	a,03h		;reset ACIA
	out	10h
	mvi	a,11h		;set 8N2
	out	10h
	ret

; sio2St - BIOS conSt function

sio2St	in	10h		;test status port for 
	ani	01h		;  byte available
	mvi	a,0		;return zero if not
	rz
	cma			;else FF if present
	ret

; sio2In - BIOS conIn function

sio2In	in	10h		;wait for byte to be available
	ani	01h
	jz	sio2In

	in	11h		;A=new character
	ani	7Fh		;get rid of parity bit
	jz	sio2In		;if null, ignore it

	ret

; sio2Out - BIOS conOut function

sio2Out	in	10h		;wait for transmitter empty
	ani	02h
	jz	sio2Out

	mov	a,c		;transmit character from C
	out	11h
	ret

return1	ret
	
return2	ret

;--------------------------------------------------------------------------
; 88-SIO drivers
;--------------------------------------------------------------------------
; sioSt - BIOS conSt function

sioSt	in	00h		;test status port for
	ani	01h		;  byte available
	mvi	a,0		;return zero if not
	rnz
	cma			;else FF if present
	ret

; sioIn - BIOS conIn function

sioIn	in	00h		;wait for byte to be available
	ani	01h
	jnz	sioIn
	
	in	01h		;get the byte
	ani	7Fh		;get rid of parity
	jz	sioIn		;if null, ignore it
	
	ret

; sioOut - BIOS conOut function

sioOut	in	00h		;wait for transmitter empty
	ani	80h
	jnz	sioOut
	
	mov	a,c		;transmit byte from C
	out	01h
	ret

;--------------------------------------------------------------------------
; Line printer driver - BIOS list device output routine
;--------------------------------------------------------------------------
lptOut	lda	lptLen		;length of zero means init printer
	ora	a
	jnz	lptOutC		;init already done
	
	mvi	a,11h		;init the printer
	out	03h
	xra	a
	out	02h
	
	sta	lptPos		;at position zero in line buffer
	mvi	a,132		;set max line length
	sta	lptLen
	
lptOutC	mov	a,c		;line feed?
	cpi	LF
	jnz	notLf		;no
	
	sta	lptPrev		;save LF as last character
	lda	lptPos		;anything buffered to print?
	ora	a
	rz			;no, probably LF after CR
	
notLf	mov	a,c		;back space? (reverse line feed?)
	cpi	BS
	jz	waitLpt		;yes, send direct to printer
	
	cpi	TAB		;tab?
	jz	doTab		;yes
	
	cpi	CR		;carriage return?
	jz	doCr		;yes
	rc			;exit for characters < CR
	
	lda	lptPos		;increment the buffer position
	inr	a
	
	push	h		;preserve H
	lxi	h,lptLen	;compare position to line length
	cmp	m		;have room for another character?
	pop	h
	jnz	havRoom		;yes
				;else, fall into doCr to force print

doCr	lda	lptPos		;at start of buffer?
	ora	a
	jnz	notBlnk		;no
	
	lda	lptPrev		;previous byte a CR?
	cpi	CR
	rz			;yes, ignore two CRís in a row
	mvi	c,LF		;force line feed (print) for CR
	
notBlnk	xra	a		;zero the line buffer position
	
havRoom	sta	lptPos		;update line buffer position
	mov	a,c		;save character just printed
	sta	lptPrev
	
waitLpt	in	02H		;wait for printer ready
	ani	11H
	jz	waitLpt
	
	mov	a,c		;output character to printer
	out	03H
	ret

doTab	mvi	c,' '		;space fill the tab
	call	lptOutC		;output the space
	
	lda	lptPos		;fill until next tab stop reached
	ani	07h		;tabs are every 8 bytes
	jnz	doTab
	
	ret
	
;--------------------------------------------------------------------------
; Monitor PROM I/O drivers
;--------------------------------------------------------------------------
; BIOS vectors for I/O through monitor PROM at C000h

monVec	dw	monIni		;init during cold start
	dw	return2		;no action during watm start
	dw	monSt		;console status
	dw	monIn		;console input
	dw	monOut		;console output
	dw	lptOut		;list output
	dw	monOut		;punch out
	dw	monIn		;reader in

; monIn - BIOS conIn routine

monIn	call	monChk		;wait for new byte available
	jz	monIn
	
	mov	a,m		;get the new byte
	ani	7Fh		;strip parity
	mvi	m,0		;nothing in input buffer anymore
	ret

; monChk - check if new input character available. Return zero if
;    not, non-zero if so.

monChk	lxi	h,bufChr	;HL->received byte, else zero
	mov	a,m		;is a byte already there?
	ora	a
	cz	0C01Fh		;no, go see if new byte available
	mov	m,a		;save it (zero means no data)
	ret

; monOut - BIOS conOut routine

monOut	lda	prevChr		;check for two CR in a row
	cpi	CR		;this and previous both CR?
	jnz	notCr		;no
	cmp	c
	rz			;yes, skip 2nd CR
	
notCr	mov	a,c		;save last character displayed
	sta	prevChr
	mov	b,c
	call	0C019h		;go display it
	ret

; monSt - BIOS conSt routine

monSt	call	monChk
	rz
	mvi	a,0FFh
	ret

; monIni - cold start initialzation

monIni	lxi	h,0		;set prev char and buffered char to zero
	shld	prevChr
	ret

; Match PROM

	db	0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh
	db	0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh
	db	0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh
	db	0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh
	db	0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh

;--------------------------------------------------------------------------
; BIOS vectors for 88-SIO console
;--------------------------------------------------------------------------
sioVec	dw	return1		;nothing during cold start
	dw	return2		;nothing during warm start
	dw	sioSt		;console status
	dw	sioIn		;console input
	dw	sioOut		;console output
	dw	lptOut		;list output
	dw	sioout		;punch output
	dw	sioin		;reader input

;--------------------------------------------------------------------------
; BIOS vectors for 88-2SIO console
;--------------------------------------------------------------------------
sio2Vec	dw	sio2Ini		;init port during cold start
	dw	return2		;nothing during warm start
	dw	sio2St		;console status
	dw	sio2In		;console input
	dw	sio2Out		;console output
	dw	lptOut		;list output
	dw	sio2out		;punch output
	dw	sio2in		;reader input

	end

