; simple test wrapper for test.c to use

.export _story

.segment "ZEROPAGE"

.ifdef EXTERNAL_ZPBLOCK
	.exportzp huffmunch_zpblock
	huffmunch_zpblock: .res 9
	.ifdef CANONICAL
		.res 23-9 ; canonical requires more RAM
	.endif
.else
	.ifdef CANONICAL
		.error "CANONICAL requires EXTERNAL_ZPBLOCK"
	.endif
.endif

.segment "RODATA"

_story:
	.ifndef CANONICAL
		.incbin "../output/danger0000.hfb"
	.else
		.incbin "../output/danger0000.hfc"
	.endif
