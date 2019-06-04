; simple test wrapper for test.c to use

.export _test_init
.export _test_begin_block
.export _test_read_byte

.import huffmunch_load
.import huffmunch_read

.ifdef RLE
.import huffmunch_read_rle
.endif

.segment "ZEROPAGE"

.exportzp huffmunch_zpblock
huffmunch_zpblock: .res 9
.ifdef RLE
	.res 11-9 ; RLE requires more RAM
.endif
.ifdef CANONICAL
	.res 24-9 ; canonical requires more RAM
.endif

.segment "RODATA"

story:
	.ifdef STANDARD
		.incbin "../output/danger0000.hfb"
	.endif
	.ifdef RLE
		.incbin "../output/danger0000.hfr"
	.endif
	.ifdef CANONICAL
		.incbin "../output/danger0000.hfc"
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
	rts ; X:A = block count

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
	.ifndef RLE
		jsr huffmunch_read ; A = byte read
	.else
		jsr huffmunch_read_rle
	.endif
	ldx #0
	rts ; X:A = byte read
