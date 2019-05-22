; Huffmunch
; Brad Smith, 2019
; https://github.com/bbbradsmith/huffmunch

.importzp huffmunch_zpblock

; in: Y:X = stream index, hm_node = pointer to data block
; out: Y:X = output byte length of current stream, hm_node = total stream count in data
.export huffmunch_load

; out: reads 1 byte from stream, result in A (X,Y,flags clobbered)
.export huffmunch_read

hm_node    = <(huffmunch_zpblock + 0); pointer to current node of tree
hm_stream  = <(huffmunch_zpblock + 2) ; pointer to bitstream
hm_tree    = <(huffmunch_zpblock + 4) ; pointer to tree base + 1
hm_byte    = <(huffmunch_zpblock + 6) ; current byte of bitstream
hm_status  = <(huffmunch_zpblock + 7) ; bits 0-2 = bits left in hm_byte, bit 7 = string with suffix
hm_length  = <(huffmunch_zpblock + 8) ; bytes left in current string
hm_strings = <(huffmunch_zpblock + 10) ; pointer to string table
hm_fc      = <(huffmunch_zpblock + 12) ; first code at current depth (24-bit)
hm_c       = <(huffmunch_zpblock + 15) ; current code (24-bit)
hm_dc      = <(huffmunch_zpblock + 18) ; depth-relative code (16-bit)
hm_ds      = <(huffmunch_zpblock + 20) ; string count at current depth (16-bit)
hm_s       = <(huffmunch_zpblock + 22) ; current string reached (16-bit)

.assert (huffmunch_zpblock + 24) <= 256, error, "huffmunch_zpblock requires 24 bytes on zero page"

; NOTE: only hm_node and hm_stream need to be on ZP
;       the rest could go elsewhere, but still recommended for ZP

.segment "CODE"

.proc huffmunch_load
	; hm_node = header
	; Y:X = index
	hm_temp = hm_byte ; temporary 16-bit value in hm_status:hm_byte
	; 1. hm_stream = (index * 2)
	sty hm_stream+1
	txa
	asl
	sta hm_stream+0
	rol hm_stream+1
	; 2. hm_temp = stream count * 2
	ldy #1
	lda (hm_node), Y
	pha
	sta hm_temp+1
	dey
	lda (hm_node), Y
	pha ; stack = stream count 0,1
	asl
	sta hm_temp+0
	rol hm_temp+1
	; 3. hm_node = header + 2
	lda hm_node+1
	pha
	lda hm_node+0
	pha ; stack = header 0, 1, stream count 0, 1
	clc
	adc #2
	sta hm_node+0
	bcc :+
		inc hm_node+1
	:
	; 4. hm_tree = header + 2 + (4 * stream count)
	lda hm_node+0
	clc
	adc hm_temp+0
	sta hm_tree+0
	lda hm_node+1
	adc hm_temp+1
	sta hm_tree+1
	lda hm_tree+0
	clc
	adc hm_temp+0
	sta hm_tree+0
	lda hm_tree+1
	adc hm_temp+1
	sta hm_tree+1
	; 5. hm_node = header + 2 + (index * 2)
	lda hm_node+0
	clc
	adc hm_stream+0
	sta hm_node+0
	lda hm_node+1
	adc hm_stream+1
	sta hm_node+1
	; 6. hm_stream = header + stream address [ready]
	; Y = 0
	pla
	clc
	adc (hm_node), Y
	sta hm_stream+0
	iny
	pla ; stack = stream count 0, 1
	adc (hm_node), Y
	sta hm_stream+1
	; 7. hm_node = header + 2 + (index * 2) + (2 * stream count)
	lda hm_node+0
	clc
	adc hm_temp+0
	sta hm_node+0
	lda hm_node+1
	adc hm_temp+1
	sta hm_node+1
	; 8. Y:X = stream length
	; Y = 1
	lda (hm_node), Y
	pha ; stack = stream length 1, stream count 0, 1
	dey
	lda (hm_node), Y
	tax
	pla ; stack = stream count 0, 1
	tay
	; 9. hm_node = total stream count [ready]
	pla
	sta hm_node+0
	pla
	sta hm_node+1
	tya
	pha
	txa
	pha ; stack = stream length 1, 0
	; 10. find string table: hm_strings [ready], ++hm_tree [ready]
	ldy #0
	lda (hm_tree), Y
	tax ; X = tree depth (number of depth entries)
	inc hm_tree+0 ; ++hm_tree
	bne :+
		inc hm_tree+1
	:
	lda hm_tree+0
	sta hm_strings+0
	lda hm_tree+1
	sta hm_strings+1
	; adance hm_strings past tree depth table
	; X = tree depth
	; Y=0
	cpx #0
	beq :+++
	:
		lda (hm_tree), Y
		iny
		cmp #255
		bne :+ ; 1 byte entry vs. 3 byte entry
			iny
			iny
		:
		dex
		bne :--
	:
	tya
	clc
	adc hm_strings+0
	sta hm_strings+0
	bne :+
		inc hm_strings+1
	:
	; 11. initialize other data [ready]
	pla
	tay
	pla
	tax ; Y:X = stream length [ready]
	lda #0
	sta hm_byte ; hm_byte doesn't need initialization, just for consistency
	sta hm_status
	sta hm_length
	sta hm_fc+0 ; the rest of these don't need initialization either
	sta hm_fc+1
	sta hm_fc+2
	sta hm_dc+0
	sta hm_dc+1
	sta hm_dc+2
	sta hm_c+0
	sta hm_c+1
	sta hm_c+2
	sta hm_ds+0
	sta hm_ds+1
	sta hm_s+0
	sta hm_s+1
	rts
.endproc

.proc huffmunch_read
	ldy #0
	lda hm_length ; string bytes pending
	beq string_empty
emit_byte:
	dec hm_length
	lda (hm_node), Y
	inc hm_node+0
	bne :+
		inc hm_node+1
	:
	rts
string_empty:
	; hm_length = 0
	; Y = 0
	bit hm_status
	bpl walk_tree
	; follow suffix
	lda (hm_node), Y
	clc
	adc hm_tree+0
	tax
	iny
	lda (hm_node), Y
	adc hm_tree+1
	sta hm_node+1
	stx hm_node+0
	dey ; ldy #0
	lda (hm_node), Y
	beq leaf0
leaf1:
	sta hm_length
	lda hm_status
	and #$7F ; clear high bit, no more suffix
	sta hm_status
	inc hm_node+0
	bne :+
		inc hm_node+1
	:
	jmp emit_byte
leaf0:
	; hm_status high bit is already set (suffix)
	iny
	lda (hm_node), Y
	sta hm_length
	lda hm_node+0
	clc
	adc #2
	sta hm_node+0
	bcc :+
		inc hm_node+1
	:
	dey
	jmp emit_byte
walk_tree:
	lda hm_tree+0
	sta hm_node+0
	lda hm_tree+1
	sta hm_node+1
	ldy #0
	sty hm_fc+0
	sty hm_fc+1
	sty hm_fc+2
	sty hm_dc+0
	sty hm_dc+1
	sty hm_dc+2
	sty hm_c+0
	sty hm_c+1
	sty hm_c+2
	sty hm_ds+0
	sty hm_ds+1
	sty hm_s+0
	sty hm_s+1
walk_node:
	; Y = 0
	; hm_fc = first code at current depth (24-bit)
	; hm_s = first symbol at current depth (16-bit)
	; hm_c = current code
	; read leaf count into hm_ds, advance hm_node to next depth
	lda (hm_node), Y
	cmp #255
	beq :+
		sta hm_ds+0
		sty hm_ds+1
		jmp :++
	:
		iny
		lda (hm_node), Y
		sta hm_ds+0
		iny
		lda (hm_node), Y
		sta hm_ds+1
	:
	iny
	tya
	clc
	adc hm_node+0
	sta hm_node+0
	bcc :+
		inc hm_node+1
	:
	ldy #0
	; compute relative code (hm_dc)
	lda hm_c+0
	sec
	sbc hm_fc+0
	sta hm_dc+0
	lda hm_c+1
	sbc hm_fc+1
	sta hm_dc+1
	; high byte ignored: relative code must be < total strings (65536)
	; compare relative code to count of leaves at this depth
	lda hm_dc+0
	cmp hm_ds+0
	lda hm_dc+1
	sbc hm_ds+1
	bcs :+
		; string is at this depth, at the relative code + first string at this depth
		lda hm_dc+0
		clc
		adc hm_s+0
		sta hm_s+0
		lda hm_dc+1
		adc hm_s+1
		sta hm_s+1
		jmp walk_strings
	:
	; hm_s += hm_ds ; advance string to start of next layer
	; hm_fc += hm_ds ; advance code to first non-leaf on current
	; hm_fc *= 2 ; make room for a new bit on next layer
	lda hm_s+0
	clc
	adc hm_ds+0
	sta hm_s+0
	lda hm_s+1
	adc hm_ds+1
	sta hm_s+1
	lda hm_fc+0
	clc
	adc hm_ds+0
	sta hm_fc+0
	lda hm_fc+1
	adc hm_ds+1
	sta hm_fc+1
	lda hm_fc+2
	adc #0 ; hm_ds is only 16-bit
	sta hm_fc+2
	asl hm_fc+0
	rol hm_fc+1
	rol hm_fc+2
	; read a new bit and append to current code
	lda hm_status
	bne :+
		lda #8
		sta hm_status
		lda (hm_stream), Y
		sta hm_byte
		inc hm_stream+0
		bne :+
		inc hm_stream+1
	:
	dec hm_status
	asl hm_byte ; big-endian bit order
	rol hm_c+0
	rol hm_c+1
	rol hm_c+2
	; carry should be clear here, or we've made a big mistake!
	jmp walk_node
walk_strings:
	; move to start of string table
	lda hm_strings+0
	sta hm_node+0
	lda hm_strings+1
	sta hm_node+1
	; skip strings until the desired one is reached
	ldy #0
next_string:
	; Y = 0
	lda hm_s+0
	ora hm_s+1
	beq found_string
	lda (hm_node), Y
	beq skip_suffixed
skip_normal: ; skip A bytes + 1
	clc
	adc hm_node+0
	sta hm_node+0
	bcc :+
		inc hm_node+1
	:
	inc hm_node+0
	bne :+
		inc hm_node+1
	:
	jmp skip_finish
skip_suffixed: ; after 0, skip number of bytes + 4
	iny
	lda (hm_node), Y
	clc
	adc hm_node+0
	sta hm_node+0
	bcc :+
		inc hm_node+1
	:
	lda hm_node+0
	clc
	adc #4
	sta hm_node+0
	bcc :+
		inc hm_node+1
	:
	dey
	;jmp skip_finish
skip_finish:
	lda hm_s+0
	bne :+
		dec hm_s+1
	:
	dec hm_s+0
	jmp next_string
found_string:
	lda (hm_node), Y
	beq string1
string0:
	sta hm_length
	inc hm_node+0
	bne :+
		inc hm_node+1
	:
	jmp emit_byte
string1:
	iny
	lda (hm_node), Y
	sta hm_length
	lda hm_status
	ora #$80
	sta hm_status ; high bit = suffix follows
	dey
	lda hm_node+0
	clc
	adc #2
	sta hm_node+0
	bcc :+
		inc hm_node+1
	:
	jmp emit_byte
.endproc
