; simple test wrapper for test.c to use

.export _test_init
.export _test_begin_block
.export _test_read_byte

.import huffmunch_load
.import huffmunch_read

.segment "ZEROASM" : zeropage

.exportzp huffmunch_zpblock
huffmunch_zpblock: .res 9
.ifdef CANONICAL
	.res 24-9 ; canonical requires more RAM
.endif

.segment "RODATA"

story:
	.ifndef CANONICAL
		.incbin "output/danger0000.hfb"
	.else
		.incbin "output/danger0000.hfc"
	.endif

.segment "CODE"

_test_init:
	lda #<story
	sta huffmunch_zpblock+0
	lda #>story
	sta huffmunch_zpblock+1
	ldx #0
	ldy #0
	jsr huffmunch_load
	ldx huffmunch_zpblock+1
	lda huffmunch_zpblock+0
	rts

_test_begin_block: ; X:A = block
	ldy #<story
	sty huffmunch_zpblock+0
	ldy #>story
	sty huffmunch_zpblock+1
	pha
	txa
	tay
	pla
	tax ; Y:X = block
	jsr huffmunch_load ; Y:X = block length
	txa
	pha
	tya
	tax
	pla
	rts ; X:A = block length

_test_read_byte:
	jsr huffmunch_read ; A = byte read
	ldx #0
	rts ; X:A = byte read
