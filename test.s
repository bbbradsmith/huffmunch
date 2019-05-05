


;
; iNES header
;

.segment "HEADER"

INES_MAPPER = 0 ; 0 = NROM
INES_MIRROR = 0 ; 0 = vertical arrangement
INES_SRAM   = 1 ; 1 = battery backed SRAM at $6000-7FFF

.byte 'N', 'E', 'S', $1A ; ID
.byte $02 ; 16k PRG bank count
.byte $00 ; 8k CHR bank count
.byte INES_MIRROR | (INES_SRAM << 1) | ((INES_MAPPER & $f) << 4)
.byte (INES_MAPPER & %11110000)
.byte $0, $0, $0, $0, $0, $0, $0, $0 ; padding

.segment "ZEROPAGE"
i: .res 1
zpblock: .res 32


.segment "BSS"
bssblock: .res 32

.segment "OAM"
oam: .res 256


.segment "CODE"

; jump to make debugging entry easy
test_huffq:
	jmp huffq
test_huffc:
	jmp huffc

q_head = zpblock + 0
q_node = zpblock + 2
q_stream = zpblock + 4
q_buffer = zpblock + 6
q_length = zpblock + 7
q_temp = zpblock + 9

huffq:
	jsr latch_chr
	lda #<mario_chr_hmq
	sta q_head+0
	lda #>mario_chr_hmq
	sta q_head+1
	lda #<(8*1024)
	sta q_length+0
	lda #>(8*1024)
	sta q_length+1
	lda #<(mario_chr_hmq+957+1)
	sta q_stream+0
	lda #>(mario_chr_hmq+957+1)
	sta q_stream+1
	ldx #8
	ldy #0
	lda mario_chr_hmq+957
	sta q_buffer
	; find data (omit this in the final version, always require pointer)
;find_data:
;	jsr read_skip
;	cmp #3
;	bcc found_string
;	lda q_temp+0
;	clc
;	adc q_node+0
;	sta q_node+0
;	lda q_temp+1
;	adc q_node+1
;	sta q_node+1
;	jmp find_data
;found_string:
;	cmp #2
;	; TODO
	; ready!
decode_symbol:
	lda q_length+0
	ora q_length+1
	bne :+
		rts
	:
	; go to top of tree
	lda q_head+0
	sta q_node+0
	lda q_head+1
	sta q_node+1
tree_branch:
	jsr read_skip
	cmp #3
	bcc emit_symbol
	jsr read_bitstream
	bcc tree_branch ; left branch (already there)
		; right branch (add skip result to node position)
		lda q_temp+0
		clc
		adc q_node+0
		sta q_node+0
		lda q_temp+1
		adc q_node+1
		sta q_node+1
	jmp tree_branch
emit_symbol:
	cmp #2
	bcs emit_string2
	cmp #1
	bcs emit_string1
emit_string0:
	jsr read_node
	jsr emit_byte
	jmp decode_symbol
emit_string1:
	jsr emit_string1_
	jmp decode_symbol
emit_string1_:
	txa
	pha
	jsr read_node
	tax
	:
		jsr read_node
		jsr emit_byte
		dex
		bne :-
	pla
	tax
	rts
emit_string2:
	jsr emit_string1_
	jsr read_node
	clc
	adc q_head+0
	sta q_temp+0
	jsr read_node
	adc q_head+1
	sta q_node+1
	lda q_temp+0
	sta q_node+0
	jsr read_node
	jmp emit_symbol
emit_byte:
	sta $2007
	lda q_length+0
	bne :+
		dec q_length+1
	:
	dec q_length+0
	rts
read_skip: ; Y=0
	jsr read_node
	cmp #255
	beq :+
		; 1-byte skip has a +1 we have to undo
		tay
		dey
		sty q_temp+0
		ldy #0
		sty q_temp+1
		; Y=0
		rts
	:
	jsr read_node
	sta q_temp+0
	jsr read_node
	sta q_temp+1
	lda #255
	rts
read_node: ; Y=0, does not clobber carry
	lda (q_node), Y
	inc q_node+0
	bne :+
		inc q_node+1
	:
	rts
read_bitstream: ; Y=0, return bit in carry
	ror q_buffer
	dex
	beq :+
		rts
	:
	php
	ldx #8
	lda (q_stream), Y
	sta q_buffer
	inc q_stream+0
	bne :+
		inc q_stream+1
	:
	plp
	rts

c_head = q_head ; zpblock + 0
c_layer = q_node ; zpblock + 2
c_stream = q_stream ; = zpblock + 4
c_buffer = q_buffer ; = zpblock + 6
c_length = q_length ; = zpblock + 7
c_temp = q_temp ; = zpblock + 9

c_fc = zpblock + 11
c_fs = zpblock + 13
c_b  = zpblock + 15
c_ds = zpblock + 17
c_dc = zpblock + 19
c_string = zpblock + 21
c_stringlen = zpblock + 23


huffc:
	jsr latch_chr
	lda #<mario_chr_hmc
	sta c_head+0
	lda #>mario_chr_hmc
	sta c_head+1
	lda #<(8*1024)
	sta c_length+0
	lda #>(8*1024)
	sta c_length+1
	lda #<(mario_chr_hmc+834+1)
	sta c_stream+0
	lda #>(mario_chr_hmc+834+1)
	sta c_stream+1
	lda #<(mario_chr_hmc+14)
	sta c_string+0
	lda #>(mario_chr_hmc+14)
	sta c_string+1
	ldx #8
	ldy #0
	lda mario_chr_hmc+834
	sta c_buffer
decode_symbolc:
	lda c_length+0
	ora c_length+1
	bne :+
		rts
	:
	lda #0
	sta c_fc+0
	sta c_fc+1 ; fc = 0
	sta c_fs+0
	sta c_fs+1 ; fs = 0
	sta c_b+0
	sta c_b+1 ; b = 0
	lda c_head+0
	clc
	adc #1
	sta c_layer+0
	lda c_head+1
	adc #0
	sta c_layer+1 ; layer = head+1 (skip depth byte)
decode_layer:
	jsr read_layer ; ds = leaf count for this depth
	lda c_b+0
	sec
	sbc c_fc+0
	sta c_dc+0
	lda c_b+1
	sbc c_fc+1
	sta c_dc+1 ; dc = b - fc
	lda c_dc+0
	cmp c_ds+0
	lda c_dc+1
	sbc c_ds+1
	bcc matched
	lda c_fs+0
	clc
	adc c_ds+0
	sta c_fs+0
	lda c_fs+1
	adc c_ds+1
	sta c_fs+1 ; fs += ds
	lda c_fc+0
	clc
	adc c_ds+0
	sta c_fc+0
	lda c_fc+1
	adc c_ds+1
	sta c_fc+1 ; fc += ds
	asl c_fc+0
	rol c_fc+1 ; fc *= 2
	jsr read_bitstream
	rol c_b+0
	rol c_b+1 ; b = (b << 1) | bistream
	jmp decode_layer
matched:
	lda c_fs+0
	clc
	adc c_dc+0
	sta c_temp+0
	lda c_fs+1
	adc c_dc+1
	sta c_temp+1 ; s (temp) = fs + dc
	lda c_string+0
	sta c_layer+0
	lda c_string+1
	sta c_layer+1 ; layer/node = string table
skip_strings:
	lda c_temp+0
	ora c_temp+1
	beq emit_string
	jsr read_node
	cmp #0
	bne :+
		jsr read_node
		pha
		lda #2
		clc
		adc c_layer+0
		sta c_layer+0
		lda #0
		adc c_layer+1
		sta c_layer+1 ; skip 2 extra bytes for string reference
		pla
	:
	; A = string length to skip
	clc
	adc c_layer+0
	sta c_layer+0
	lda #0
	adc c_layer+1
	sta c_layer+1 ; skip string
	lda c_temp+0
	bne :+
		dec c_temp+1
	:
	dec c_temp+0 ; --s (temp)
	jmp skip_strings
emit_string:
	jsr read_node
	cmp #0
	beq :+
		sta c_stringlen
		jsr emit_string_
		jmp decode_symbolc
	:
	jsr read_node
	sta c_stringlen
	jsr emit_string_
	jsr read_node
	clc
	adc c_head+0
	pha
	jsr read_node
	adc c_head+1
	sta c_layer+1
	pla
	sta c_layer+0
	jmp emit_string
emit_string_:
	jsr read_node
	;eor #$FF ; negative for test
	eor #$00
	sta $2007
	lda c_length+0
	bne :+
		dec c_length+1
	:
	dec c_length+0
	dec c_stringlen
	bne emit_string_
	rts
read_layer:
	jsr read_node ; c_layer = q_node
	cmp #255
	beq :+
		sta c_ds+0
		lda #0
		sta c_ds+1
		rts
	:
	jsr read_node
	sta c_ds+0
	jsr read_node
	sta c_ds+1
	rts

;
;
;

latch_chr:
	bit $2002
	lda #$00
	sta $2006
	sta $2006
	rts

wipe_chr:
	jsr latch_chr
	ldx #0
	ldy #0
	sty i
	:
		stx i
		tya
		clc
		adc i
		sta $2007
		inx
		bne :-
		iny
		cpy #32
		bcc :-
	rts

mario_chr_hmq:
	.incbin "smb.chr.hmq"
mario_chr_hmc:
	.incbin "smb.chr.hmc"

main:
	jsr load_bg
:
	jsr wipe_chr
	jsr test_huffq
	jsr wait_press
	jsr wipe_chr
	jsr test_huffc
	jsr wait_press
	jmp :-

load_bg:
	; 4 nametables
	bit $2002
	lda #$20
	sta $2006
	lda #$00
	sta $2006
	jsr load_nmt
	jsr load_nmt
	jsr load_nmt
	jsr load_nmt
	; palette
	lda #$3F
	sta $2006
	lda #$00
	sta $2006
	ldx #8
	:
		lda #$0F
		sta $2007
		lda #$00
		sta $2007
		lda #$10
		sta $2007
		lda #$20
		sta $2007
		dex
		bne :-
	rts
load_nmt:
	ldx #0
	ldy #0
	sty i
	:
		txa
		and #15
		ora i
		sta $2007
		inx
		cpx #32
		bcc :-
		ldx #0
		iny
		tya
		asl
		asl
		asl
		asl
		sta i
		cpy #30
		bcc :-
	; attributes
	lda #0
	ldx #64
	:
		sta $2007
		dex
		bne :-
	rts

wait_press:
	lda #0
	sta $2005
	sta $2005
	lda #%00001010 ; no sprites
	sta $2001
:
	jsr gamepad_poll
	beq :-
:
	jsr gamepad_poll
	bne :-
	lda #%00000000
	sta $2001
	rts



;
; gamepad
;

PAD_A      = $01
PAD_B      = $02
PAD_SELECT = $04
PAD_START  = $08
PAD_U      = $10
PAD_D      = $20
PAD_L      = $40
PAD_R      = $80

.segment "ZEROPAGE"
gamepad: .res 1

.segment "CODE"
; gamepad_poll: this reads the gamepad state into the variable labelled "gamepad"
;   This only reads the first gamepad, and also if DPCM samples are played they can
;   conflict with gamepad reading, which may give incorrect results.
gamepad_poll:
	; strobe the gamepad to latch current button state
	lda #1
	sta $4016
	lda #0
	sta $4016
	; read 8 bytes from the interface at $4016
	ldx #8
	:
		pha
		lda $4016
		; combine low two bits and store in carry bit
		and #%00000011
		cmp #%00000001
		pla
		; rotate carry into gamepad variable
		ror
		dex
		bne :-
	sta gamepad
	lda gamepad
	rts

irq:
nmi:
	rti

reset:
	sei       ; mask interrupts
	lda #0
	sta $2000 ; disable NMI
	sta $2001 ; disable rendering
	sta $4015 ; disable APU sound
	sta $4010 ; disable DMC IRQ
	lda #$40
	sta $4017 ; disable APU IRQ
	cld       ; disable decimal mode
	ldx #$FF
	txs       ; initialize stack
	; wait for first vblank
	bit $2002
	:
		bit $2002
		bpl :-
	; clear all RAM to 0
	lda #0
	ldx #0
	:
		sta $0000, X
		sta $0100, X
		sta $0200, X
		sta $0300, X
		sta $0400, X
		sta $0500, X
		sta $0600, X
		sta $0700, X
		inx
		bne :-
	; place all sprites offscreen at Y=255
	lda #255
	ldx #0
	:
		sta oam, X
		inx
		inx
		inx
		inx
		bne :-
	; wait for second vblank
	:
		bit $2002
		bpl :-
	; NES is initialized, ready to begin!
	; enable the NMI for graphical updates, and jump to our main program
	lda #%10001000
	sta $2000
	jmp main

.segment "VECTORS"
.word nmi
.word reset
.word irq
