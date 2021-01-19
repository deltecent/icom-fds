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
;  Disassembled by Patrick Linstruth, January, 2021.
;  Based on FD3812 disassembly by Mike Douglas, November, 2020.
;
;--------------------------------------------------------------------------

PROM	equ	0f000h		;address of prom
PRAM	equ	PROM+0400h	;address of ram

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
cWRTBUF	equ	31h		;write buffer
cRDBUF	equ	40h		;read buffer
cSRDBUF	equ	41h		;shift read buffer
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

RAW	equ	40H		;read after wrt

; Drive equates

NUMSEC	equ	26		;CP/M sectors per SD track

; Other equates

CR	equ	0Dh		;carrige return
LF	equ	0Ah		;line feed
BS	equ	8		;back sp
TAB	equ	9		;tab char

;--------------------------------------------------------------------------
;I/O VECTORS IN INTERFACE "ON BOARD" RAM
;--------------------------------------------------------------------------

CINIT	EQU	PRAM
WINIT	EQU	PRAM+3
CONST	EQU	PRAM+6
CONIN	EQU	PRAM+9
CONOUT	EQU	PRAM+0CH
LIST	EQU	PRAM+0FH
PUNCH	EQU	PRAM+12H
READER	EQU	PRAM+15H

;--------------------------------------------------------------------------
; Interface board RAM
;--------------------------------------------------------------------------
	org	PRAM		;start of RAM on the interface board

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

biosAdr	ds	2		;address of BIOS in RAM (PRAM+40h)

;--------------------------------------------------------------------------
; Start of PROM
;--------------------------------------------------------------------------

	org	PROM

	jmp	entry

	db	020h,041h,04ch	;match the PROM
	db	054h,041h,049h	;match the PROM
	db	052h,043h,020h	;match the PROM
	db	0c3h,085h,0f0h	;match the PROM
	db	015h		;match the PROM

vCold	jmp	cBoot
	jmp	wBoot
	jmp	CONST
	jmp	CONIN
	jmp	CONOUT
	jmp	LIST
	jmp	PUNCH
	jmp	READER
	jmp	home
	jmp	selDrv
	jmp	setTrk
	jmp	setSec
	jmp	setDma
	jmp	read
	jmp	write

	ret			;CLOSE not implemented
	nop
	nop

	jmp	densC
	jmp	initAll

cpyrght db	' 3712-V21 '
	db	'(C) LIFEBOAT ASSOCIATES 1979 !'

	db	0e0h,0f3h	;match the PROM

	jmp	init

entry	lxi	h,PRAM-010h	;HL->PROM vector table
	jmp	init
	lxi	h,PRAM-098h
	jmp	init

init	lxi	sp,80h		;initialize stack pointer
	call	ramVec		;make vector table in RAM
	lxi	sp,80h		;again??

boot	call	initAll		;initialize controller, drives, variables
	mvi	c,0		;track 0
	call	setTrk
	lxi	b,80h		;load sector into RAM at 80h
	call	setDma
	call	read		;read the sector
	jnz	boot		;error, try again
	lxi	h,PRAM		;pass loader the RAM location in DE
	xchg			;DE->RAM
	lxi	h,vCold		;and a jump to CP/M cold boot in HL
	jmp	80h		;jump to boot loader

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
	xra	a		;initialize LPTLEN
	sta	LPTLEN

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

	mvi	c,0		;track 0
	call	setTrk

	lhld	biosAdr		;HL->start of the BIOS
	lxi	d,-(CCPLEN+BDOSLEN)	;compute start address of the CCP
	dad	d		;HL->start of the CCP in RAM

	inr	h		;HL->CCP + 2 sectors
	mvi	a,4		;A=sector 4

	call	wbLoop		;read sectors 2-26 off track 0

	mvi	c,1		;track 1
	call	setTrk

	lhld	biosAdr
	lxi	d,-(CCPLEN+BDOSLEN)
	dad	d		;hl->start address of the CCP
	lxi	d,25*128
	dad	d		;hl->CCP + 25 sectors

	mvi	a,1		;A=sector 1
	call	wbLoop

	jmp	jmpCpm

wbLoop	sta	secNum
	shld	dmaAddr
	lda	biosAdr+1	;see if we've reached the BIOS address
	dcr	a
	cmp	h		;compare address now to BIOS address
	jc	wbSkip		;reached the BIOS, don't read

	call	read		;read the next sector
	jnz	wBoot		;error, start over

wbSkip	lhld	dmaAddr
	lxi	d,3*128	
	dad	d
	lda	secNum
	adi	3

	cpi	NUMSEC+1	;past last sector?
	jc	wbLoop

	sui	NUMSEC		;wrap back to start
	lxi	d,-(CCPLEN+BDOSLEN-800h)
	dad	d

	cpi	1		;if back to 1, we're done
	jnz	wbLoop

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

	mov	c,m		;pass character in A
	inx	h		;point to next character
	push	h
	call	outChar		;call BIOS output character
	pop	h
	jmp	banner

outChar	lhld	biosAdr		;point to BIOS entry
	lxi	d,0ch		;CONOUT entry
	dad	d
	pchl			;jump to it

;--------------------------------------------------------------------------
; densC - Return density table entry in HL for drive indicated by C
;--------------------------------------------------------------------------
densC	lxi	h,PRAM		;compute address in drive table
	mvi	b,0		;BC=offset to drive
	dad	b		;HL->drive in drive table
	ret

;--------------------------------------------------------------------------
; home - BIOS entry point. Do a restore to track 0 on the current drive.
;--------------------------------------------------------------------------
home	jmp	doHome

;--------------------------------------------------------------------------
; setTrk, selDrv, setSec, setDma - standard BIOS entry points
;--------------------------------------------------------------------------
setTrk	mov	a,c		;save track specified in C
	sta	trkNum
	ret

selDrv	mov	a,c		;save passed drive number in drvNum
	sta	drvNum

	mvi	a,0ffh		;indicate that track density is not set
	sta	densTrk		;  in the controller
	ret

setSec	mov	a,c		;save CP/M sector specified in C
	sta	secNum
	ret

setDma	mov	h,b		;save buffer address specified in BC
	mov	l,c
	shld	dmaAddr
	ret
	
read	call	selSeek		;select drive, seek to track
	jnz	errExit		;failed

	mvi	c,10		;retry count

readReq mvi	a,cREAD		;issue read command to the controller
	call	doCmd
	ani	sNOTRDY+sCRCERR	;check for read errors
	jz	startRd		;no errors

	call	clrErrs		;clear errors on the controller
	dcr	c		;decrement retry count
	jnz	readReq

	jmp	errExit		;give up

startRd lhld	dmaAddr		;hl->user buffer to store sector
	mvi	c,128		;read 128 bytes from controller
	mvi	a,cRDBUF	;first byte of read buffer
	out	CMDOUT
	in	DATAIN		;get byte from controller
	mov	m,a		;save byte in user buffer
	inx	h
	xra	a		;status
	out	CMDOUT
	dcr	c		;decrement byte count

rdLoop	mvi	a,cSRDBUF	;shift read buffer to next byte
	out	CMDOUT
	in	DATAIN		;get byte from controller
	mov	m,a		;save byte in user buffer
	inx	h
	xra	a		;status
	out	CMDOUT
	dcr	c		;decrement byte count
	jnz	rdLoop

	ret

;--------------------------------------------------------------------------
; write - BIOS entry point. Write 128 byte CP/M sector to the drive,
;   track and sector specified in drvNum, trkNum, and secNum. Sector
;   data to be written is specified in dmaAddr. Double density writes
;   are buffered in RAM at (bufPtr).
;--------------------------------------------------------------------------
write	call	selSeek		;select drive, seek to track
	jnz	errExit		;failed

	lhld	dmaAddr		;HL->user data to write
	mvi	c,128		;write 128 bytes

wrtLoop	mov	a,m		;copy byte from HL
	out	DATAOUT		;store on controller
	mvi	a,cWRTBUF	;write buffer
	out	CMDOUT
	xra	a		;status
	out	CMDOUT
	inx	h		;next byte
	dcr	c		;decrement count
	jnz	wrtLoop	

	mvi	c,10		;c=retry count

wrtSec	mvi	a,cWRITE	;issue write command to the controller
	call	doCmd
	ani	sNOTRDY		;drive not ready?
	jz	wrtVrfy		;no, verify sector

	call	clrErrs		;clear errors in the controller
	jmp	errExit		;give up

wrtVrfy	lda	wrtVfy		;verify the write?
	ani	RAW
	rz			;no

	mvi	a,cRDCRC	;issue read CRC to validate
	call	doCmd
	ani	sNOTRDY+sCRCERR	;CRC error?
	rz			;no

	call	clrErrs		;clear errors in the controller
	dcr	c		;decrement retry count
	jnz	wrtSec

errExit	mvi	a,1		;return with A and status <> 0
	ora	a
	ret

;--------------------------------------------------------------------------
; selSeek - Select current drive, seek to current track, give
;   controller current sector to look for
;--------------------------------------------------------------------------
selSeek	xra	a		;set single density
	out	DATAOUT
	mvi	a,cLDCFG

	call	outCmd
	call	drvSec		;set drive and sector
	call	seek		;seek to curTrk

	ret			;zero if no error

;--------------------------------------------------------------------------
; drvSec - Select current drive, give controller current sector
;   to look for
;--------------------------------------------------------------------------
drvSec	lda	drvNum		;A=drive number
	ani	03h		;only allow 0-3
	rrc			;move to bits 6-7
	rrc
	mov	c,a		;save in C
	lda	secNum		;A=sector number
	ora	c		;add drive number
	out	DATAOUT
	mvi	a,cDRVSEC	;set drive and sector
	call	outCmd

	ret

;--------------------------------------------------------------------------
; seek - Seek to curTrk. 
;--------------------------------------------------------------------------
seek	mvi	c,2		;c=retry count
	lda	trkNum		;A=current track
	lxi	h,densTrk	;HL->controller density
	cmp	m		;density set for this track?
	rz			;yes, so we're already on right track

	mov	m,a		;this track will now have density set

	lda	trkNum		;set track number in controller
	out	DATAOUT
	mvi	a,cSETTRK	;set track to seek
	call	outCmd	

	mvi	a,cSEEK		;use seek command
	call	doCmd
	ani	sNOTRDY+sCRCERR	;check for read errors
	rz			;exit if no errors

	call	clrErrs		;clear errors on controller
	mvi	m,0ffh		;density not set
	dcr	c		;decrement retry count
	jnz	seek

	call	reset0		;reset controller, restore to track 0

	mvi	a,2		;clear zero flag
	ora	a
	ret

;--------------------------------------------------------------------------
; initAll - Initialize variables, reset controller, restore drive 0
;   to track 0
; reset0 - reset controller, restore current drive to track 0
; doHome - restore current drive to track 0
;--------------------------------------------------------------------------
initAll xra	a
	sta	drvNum		;set current drive=0
	inr	a
	sta	secNum		;set current sector=1

reset0	mvi	a,cRESET	;reset controller	
	call	outCmd

doHome	call	drvSec		;set drive and sector on the controller

	mvi	a,0ffh		;no track density set
	sta	densTrk

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
; moveH2D - move B bytes from (HL) to (DE)
;--------------------------------------------------------------------------

moveH2D	mov	a,m		;copy byte from (HL) to (DE)	
	stax	d
	inx	h
	inx	d
	dcr	b		;decrement byte count
	jnz	moveH2D

	ret

;--------------------------------------------------------------------------
; Create vector in PRAM from table in HL
;--------------------------------------------------------------------------
ramVec	lxi	d,PRAM		;DE->TOP of iCOM RAM
	mvi	b,((VREADER-VCINIT)/2)+1

vecLp	mvi	a,JMP		;JMP opcode
	stax	d		;store in PRAM
	inx	d		;de=de+1
	mov	a,m		;get lsb vector
	stax	d		;store in PRAM
	inx	h		;hl=hl+1
	inx	d		;de=de+1
	mov	a,m		;get msb vector
	stax	d		;store in PRAM
	inx	h		;hl=hl+1
	inx	d		;de=de+1
	dcr	b		;decrement count
	jnz	vecLp		;next vector

	ret			;done

;--------------------------------------------------------------------------
; PROM I/O Routines
;--------------------------------------------------------------------------

;*** ALTAIR 88-2SIO ROUTINES ***

SSS	EQU	10h		;2SIO status port
SSI	EQU	11h		;2SIO input port
SSO	EQU	11h		;2SIO output port
SSDA	EQU	01h		;data available mask
SSBE	EQU	02h		;buffer empty mask

SIOINIT	mvi	a,03h		;reset
	out	SSS
	mvi	a,11h		;8 data bits, 2 stop bits
	out	SSS
	ret

SIOST	in	SSS
	ani	01h
	mvi	a,0
	rz			;return A=0 if no key

	cma			;return A=0FFh if key
	ret

SIOIN	in	SSS
	ani	01h
	jz	SIOIN		;no data yet

	in	SSI
	ani	07fh
	jz	SIOIN

	ret
 
SIOUT	in	SSS
	ani	02h
	jz	SIOUT		;not ready for output
	mov	a,c
	out	SSO		;output byte
	ret

	ret			;here from PROM image

SIORET	ret			;no warm init done

;*** IMSAI (MITS REV NON-ZERO) I/O ROUTINE ***

TTS	EQU	0		;STATUS PORT
TTI	EQU	1		;DATA INPUT PORT
TTO	EQU	1		;DATA OUTPUT PORT
TTDA	EQU	1		;DATA AVAILABLE PORT
TTBE	EQU	80H		;BUFFER EMPTY PORT

TTYST	in	TTS
	ani	TTDA
	mvi	a,0
	rnz			;return A=0 if no key
	cma			;return A=FFh if key

	ret

TTYIN	in	TTS
	ani	TTDA
	jnz	TTYIN		;loop for char

	in	TTI		;get char
	ani	07fh		;strip parity
	jz	TTYIN

	ret

TTYOUT	in	TTS
	ani	TTBE
	jnz	TTYOUT		;loop until ready

	mov	a,c
	out	TTO		;output char

	ret

;*** CENTRONIX PRINTER ***

CENTC	equ	2		;CENTRONICS CONTROL PORT
CENTD	equ	3		;CENTRONICS DATA PORT

LPTPOS	equ	PRAM+047h	;POSITION
LPTLEN	equ	PRAM+048h	;DOUBLES AS INIT FLAG
LPTLST	equ	PRAM+049h	;LAST CHAR

;CENTRONICS PRINTER OUTPUT ROUTINE

CENTOUT	lda	LPTLEN
	ora	a		;init?
	jnz	LPTOT1		;already init

INITCP	mvi	a,011h
	out	CENTD
	xra	a
	out	CENTC
	sta	LPTPOS
	mvi	a,132
	sta	LPTLEN		;set max line length

LPTOT1	mov	a,c		;get character
	cpi	LF		;ignore LF
	jnz	LPTOT2		;if first character on line

	sta	LPTLST
	lda	LPTPOS
	ora	a
	rz

LPTOT2	mov	a,c
	cpi	BS
	jz	LPTWAT
	cpi	TAB
	jz	MORSPC
	cpi	CR
	jz	CRTRIK
	rc			;ignore other control chars
				;make sure form feeds ignored

	lda	LPTPOS
	inr	a
	push	h
	lxi	h,LPTLEN
	cmp	m
	pop	h
	jnz	NOTENL

; Special handling for CR

CRTRIK	lda	LPTPOS		;position 0?
	ora	a
	jnz	ATENL		;print CR if not end of line

	lda	LPTLST		;ignore 2 CR in a row
	cpi	CR
	rz

	mvi	c,LF		;change pos 0 CR to LF

ATENL	xra	a

NOTENL	sta	LPTPOS		;save position of char
	mov	a,c
	sta	LPTLST		;store last char

LPTWAT	in	CENTC
	ani	011h
	jz	LPTWAT		;not ready to output

	mov	a,c
	out	CENTD		;send char to printer

	ret

MORSPC	mvi	c,' '		;handle TAB
	call	LPTOT1

	lda	LPTPOS
	ani	07h
	jnz	MORSPC

	ret			;done

	;
	; match the PROM
	;

	db	0a8h,0f3h,0d2h,0f2h,0a1h,0f3h,078h,0f3h
	db	08eh,0f3h,0f6h,0f2h,08eh,0f3h,078h,0f3h
	db	0cdh,084h,0f3h,0cah,078h,0f3h,07eh,0e6h
	db	07fh,036h,000h,0c9h,021h,04bh,0f4h,07eh
	db	0b7h,0cch,01fh,0c0h,077h,0c9h,03ah,04ah
	db	0f4h,0feh,00dh,0c2h,098h,0f3h,0b9h,0c8h
	db	079h,032h,04ah,0f4h,041h,0cdh,019h,0c0h
	db	0c9h,0cdh,084h,0f3h,0c8h,03eh,0ffh,0c9h
	db	021h,000h,000h,022h,04ah,0f4h,0c9h,0ffh

	db	0ffh,0ffh,0ffh,0ffh,0ffh,0ffh,0ffh,0ffh
	db	0ffh,0ffh,0ffh,0ffh,0ffh,0ffh,0ffh,0ffh
	db	0ffh,0ffh,0ffh,0ffh,0ffh,0ffh,0ffh,0ffh
	db	0ffh,0ffh,0ffh,0ffh,0ffh,0ffh,0ffh,0ffh
	db	0ffh,0ffh,0ffh,0ffh,0ffh,0ffh,0ffh,0ffh
	db	0ffh,0ffh,0ffh,0ffh,0ffh,0ffh,0ffh,0ffh

	db	0d1h,0f2h,0d2h,0f2h,0d3h,0f2h,0dch,0f2h
	db	0ebh,0f2h,0f6h,0f2h,0ebh,0f2h,0dch,0f2h

;--------------------------------------------------------------------------
; PROM I/O vector table
;--------------------------------------------------------------------------

VCINIT	dw	SIOINIT		;cold start init
VWINIT	dw	SIORET		;warm start init
VCONST	dw	SIOST		;console status
VCONIN	dw	SIOIN		;console in
VCONOUT	dw	SIOUT		;console out
VLIST	dw	CENTOUT		;list
VPUNCH	dw	SIOUT		;punch
VREADER	dw	SIOIN		;reader f3fe b7 f2

	end
