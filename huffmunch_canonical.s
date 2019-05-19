
.importzp huffmunch_zpblock

.export huffmunch_load ; in: Y:X = index, hm_node = pointer to data block
.export huffmunch_read ; reads 1 byte from stream, result in A (flags unreliable)

.proc huffmunch_load
	; not yet written
	rts
.endproc

.proc huffmunch_read
	; not yet written
	rts
.endproc
