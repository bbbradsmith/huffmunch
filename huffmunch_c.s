; C wrapper for huffmunch.s

; Note for better performance:
;   allocate 9 bytes on zeropage (or 23 if using canonical version),
;   exportzp as huffmunch_zpblock,
;   and define EXTERNAL_ZPBLOCK when building this file.
;
; This is not the default because most platform default CFG has a restricted ZP segment size.
; This is required for using the canonical version of huffmunch, because there is not enough
; space in the internal ZP to accomodate the additional required state.

.export _huffmunch_init
.export _huffmunch_load
.export _huffmunch_read

.import huffmunch_load
.import huffmunch_read

.segment "BSS"
huffmunch_c_data: .res 2

.ifdef EXTERNAL_ZPBLOCK
	.importzp huffmunch_zpblock
.else

; use cc65 internal zeropage variables as temporary space
.importzp ptr1
huffmunch_zpblock = ptr1
.exportzp huffmunch_zpblock

; permanent storage goes to a RAM block
.segment "BSS"
huffmunch_c_ramblock: .res 9

.segment "CODE"
huffmunch_c_zp_to_ram:
	.repeat 9, I
		ldy huffmunch_zpblock + I
		sty huffmunch_c_ramblock + I
	.endrepeat
	rts
huffmunch_c_ram_to_zp:
	.repeat 9, I
		ldy huffmunch_c_ramblock + I
		sty huffmunch_zpblock + I
	.endrepeat
	rts

.endif

.segment "CODE"

_huffmunch_init: ; X:A = address of data
	sta huffmunch_c_data+0
	stx huffmunch_c_data+1
	sta huffmunch_zpblock+0
	stx huffmunch_zpblock+1
	ldx #0
	ldy #0
	jsr huffmunch_load
	ldx huffmunch_zpblock+1
	lda huffmunch_zpblock+0
	rts ; X:A = block count

_huffmunch_load: ; X:A = block
	ldy huffmunch_c_data+0
	sty huffmunch_zpblock+0
	ldy huffmunch_c_data+1
	sty huffmunch_zpblock+1
	pha
	txa
	tay
	pla
	tax ; Y:X = block
	jsr huffmunch_load ; Y:X = block length
	.ifndef EXTERNAL_ZPBLOCK
		tya
		jsr huffmunch_c_zp_to_ram
		tay
	.endif
	txa
	pha
	tya
	tax
	pla
	rts ; X:A = block length

_huffmunch_read:
	.ifndef EXTERNAL_ZPBLOCK
		jsr huffmunch_c_ram_to_zp
	.endif
	jsr huffmunch_read ; A = byte read
	.ifndef EXTERNAL_ZPBLOCK
		jsr huffmunch_c_zp_to_ram
	.endif
	ldx #0
	rts ; X:A = byte read
