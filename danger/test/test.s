; simple test wrapper for test.c to use

.export _story

.segment "ZEROPAGE"

.ifdef EXTERNAL_ZPBLOCK
	.exportzp huffmunch_zpblock
	huffmunch_zpblock: .res 9
.endif

.segment "RODATA"

_story:
	.incbin "../output/danger0000.hfb"
