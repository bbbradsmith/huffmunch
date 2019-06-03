; The Most Dangerous Game
; Brad Smith, 2019
; https://github.com/bbbradsmith/huffmunch
;
; A demonstration of the Huffmmunch compression library,
; using The Most Dangerous Game by Richard Connell.

.macpack longbranch

PAGE_W = 28
PAGE_H = 25
PAGE_MAX = 100

GREY_PROFILE = 0 ; simple performance profiling: greyscale while idle

.segment "ZEROPAGE"

; rendering
nmi_on:    .res 1 ; if 0 NMI does nothing but increment nmi_count
nmi_count: .res 1 ; increments every NMI
nmi_mode:  .res 1 ; controls PPU updates during NMI (0 for none, returned to 0 after NMI)
nmi_addr:  .res 2 ; address of PPU update (see nmi_buffer)
scroll_x:  .res 1
scroll_y:  .res 1
ppu_2000:  .res 1
ppu_2001:  .res 1

; gamepad
gamepads_old: .res 2
gamepads:     .res 2
gamepad_new:  .res 1 ; buttons pressed since last poll
gamepad:      .res 1 ; OR of both gamepads
gamepad_old:  .res 1 ; previous value of gamepad

; selection
page:       .res 1
page_count: .res 1
page_bytes: .res 2 ; just for debugging
page_index: .res 1 ; page selection on index screen
i:          .res 1 ; temporary counter
j:          .res 1 ; temporary counter
k:          .res 1 ; temporary counter
draw_nmt:   .res 1 ; next nametable to draw ($20 or $24)
knife_x:    .res 1 ; position of index knife
knife_y:    .res 1 ; (y=0 for offscreen)
index_hold: .res 1 ; frames of held button on index screen
music_on:   .res 1

; huffmunch data
.exportzp huffmunch_zpblock
huffmunch_zpblock: .res 9
.ifdef CANONICAL
	.res 24-9 ; canonical requires more RAM
.endif

.segment "RAM"
; rendering
palette:    .res 32
nmi_buffer: .res (PAGE_W*2)

.segment "OAM"
.align 256
oam: .res 256

.segment "CODE"

.import huffmunch_load
.import huffmunch_read

.include "music/music.inc"

;
; utilities
;

.macro PPU_LATCH addr_
	bit $2002
	lda #>addr_
	sta $2006
	lda #<addr_
	sta $2006
.endmacro

.macro NMI_LATCH addr_
	lda #>addr_
	sta nmi_addr+1
	lda #<addr
	sta nmi_addr+0
.endmacro

.proc prepare_story_huffmunch
	lda #<story
	sta huffmunch_zpblock+0
	lda #>story
	sta huffmunch_zpblock+1
	rts
.endproc

; begin decompressing page
.proc prepare_story_page
	jsr prepare_story_huffmunch
	ldx page
	cpx #255
	beq :+ ; skip for index page
	ldy #0
	jsr huffmunch_load
	sty page_bytes+1
	stx page_bytes+0
:
	rts
.endproc

; in: A
; out: Y:X:A decimal representation
.proc decimal
	ldy #0
	ldx #0
	:
		cmp #100
		bcc :+
		iny
		;sec
		sbc #100
		jmp :-
	:
		cmp #10
		bcc :+
		inx
		;sec
		sbc #10
		jmp :-
	:
	; Y:X:A = raw decimal values
	clc
	adc #'0'
	pha
	tya
	beq hide_100s
	clc
	adc #'0'
	tay
	txa
show_10s:
	clc
	adc #'0'
	jmp finish
hide_100s:
	lda #' '
	tay
	txa
	bne show_10s
	lda #' '
finish:
	tax
	pla
	; Y:X:A = ascii number with leading zeroes replaced by spaces
	rts
.endproc

; places a line number for the current page on the second row of nmi_update
.proc prepare_page_number
	lda #' '
	ldx #0
	:
		sta nmi_buffer+PAGE_W, X
		inx
		cpx #PAGE_W
		bcc :-
	lda page
	beq skip ; title page (no number)
	cmp #255
	beq skip ; index page (no number)
	jsr decimal
	sty nmi_buffer+(2*PAGE_W)-3
	stx nmi_buffer+(2*PAGE_W)-2
	sta nmi_buffer+(2*PAGE_W)-1
skip:
	rts
.endproc

; places a line number for the current page on the first row of nmi_update (clobbers second row)
.proc prepare_page_number_single
	jsr prepare_page_number
	ldx #0
	:
		lda nmi_buffer+PAGE_W, X
		sta nmi_buffer, X
		inx
		cpx #PAGE_W
		bcc :-
	rts
.endproc

; fills nmi_buffer with index page
; X = 0-12
.proc prepare_index_line_pair
	lda #' '
	ldy #0
	:
		sta nmi_buffer, Y
		iny
		cpy #(2*PAGE_W)
		bcc :-
	cpx #0 ; first 2 rows empty
	bne :+
		rts
	:
	cpx #1 ; second 2 rows say "INDEX" on their lower row
	bne :++
		ldy #0
		:
			lda index_text, Y
			sta nmi_buffer+PAGE_W, Y
			iny
			cpy #INDEX_TEXT_LEN
			bcc :-
		rts
	:
	cpx #2 ; third 2 rows empty
	bne :+
		rts
	:
	; subsequent rows show page numbers
	txa
	sec
	sbc #3
	; * 10
	sta i
	asl
	asl
	clc
	adc i
	asl
	sta i
	ldy #0
	:
		sty j
		lda i
		cmp page_count
		bcs :+
		jsr decimal
		pha
		txa
		pha
		tya
		pha
		ldy j
		ldx number_position, Y
		pla
		sta nmi_buffer+0, X
		pla
		sta nmi_buffer+1, X
		pla
		sta nmi_buffer+2, X
		inc i
		iny
		cpy #10
		bcc :-
	:
	rts
index_text:
	.byte " INDEX"
	INDEX_TEXT_LEN = *-index_text
number_position:
	.repeat 5, I
		.byte 3 + (I*5)
	.endrepeat
	.repeat 5, I
		.byte PAGE_W + 3 + (I*5)
	.endrepeat
.endproc

; fills nmi_buffer with two lines
; X = 0-12
.proc prepare_page_line_pair
	; setup write address
	lda #0
	sta i
	txa
	asl
	clc
	adc #2
	asl
	;rol i
	asl
	;rol i
	asl
	;rol i
	asl
	rol i
	asl
	rol i ; (x + 2) * 32
	clc
	adc #<2
	sta nmi_addr+0
	lda draw_nmt
	adc i
	sta nmi_addr+1
	; index has a separate routine
	lda page
	cmp #255
	bne :+
		jmp prepare_index_line_pair
	:
	txa
	pha
	; load first line
	ldx #0
	stx i
	:
		jsr huffmunch_read
		cmp #0
		beq :+
		ldx i
		sta nmi_buffer, X
		inc i
		jmp :-
	:
	lda #' '
	ldx i
	cpx #PAGE_W
	beq :++
	:
		sta nmi_buffer, X
		inx
		cpx #PAGE_W
		bcc :-
	:
	; the last pair ends with a page number instead
	pla
	cmp #12
	bcc :+
		jmp prepare_page_number
	:
	; load second line
	ldx #0
	stx i
	:
		jsr huffmunch_read
		cmp #0
		beq :+
		ldx i
		sta nmi_buffer+PAGE_W, X
		inc i
		jmp :-
	:
	lda #' '
	ldx i
	cpx #PAGE_W
	beq :++
	:
		sta nmi_buffer+PAGE_W, X
		inx
		cpx #PAGE_W
		bcc :-
	:
	rts
.endproc

.proc flip_draw_nmt
	lda draw_nmt
	eor #$08
	sta draw_nmt
	rts
.endproc

;
; main
;

.proc main
	; draw page frames
	PPU_LATCH $2000
	jsr draw_page
	jsr draw_page
	jsr draw_page
	jsr draw_page
	; load palettes
	ldx #0
	:
		lda palette_data, X
		sta palette, X
		inx
		cpx #32
		bcc :-
	; setup sprites
	ldx #0
	:
		lda #$FF
		sta oam, X
		inx
		bne :-
	; get page count
	jsr prepare_story_huffmunch
	ldx #0
	ldy #0
	jsr huffmunch_load
	lda huffmunch_zpblock+0
	sta page_count
	cmp #PAGE_MAX
	bcs :+
	lda huffmunch_zpblock+1
	beq :++
	:
		brk ; error: too many pages
	:
	; prepare title page
	lda #$20
	sta draw_nmt
	lda #0
	sta k
	sta page
	jsr prepare_story_page
	:
		ldx k
		jsr prepare_page_line_pair
		jsr immediate_row2
		inc k
		lda k
		cmp #13
		bcc :-
	jsr flip_draw_nmt
	; pre-generate index knife sprite
	jsr setup_knife
	; clear button presses
	jsr poll_gamepads
	; begin rendering
	lda #%00011110
	sta ppu_2001
	lda #%10000000
	sta ppu_2000
	sta $2000 ; commence NMI
	; detect region
	jsr cpu_speed_detect
	sta player_pal
	jsr music_init
	; allow NMI
	lda #1
	sta nmi_on
	jsr srender_on
	jmp reading_loop
.endproc

.pushseg
.segment "ALIGN"
.align 32
; counts CPU cycles in between 2 NMIs to determin regional timing
; returns in A:
;   0 NTSC  (60Hz, 1.79MHz)
;   1 PAL   (50Hz, 1.66MHz)
;   2 Dendy (50Hz, 1.77MHz)
.proc cpu_speed_detect
	; count CPU cycles in between 2 NMIs
	ldx #0
	ldy #0
	lda nmi_count
	:
		cmp nmi_count
		beq :-
	lda nmi_count
	:
		inx
		bne :+
		.assert >:+=>*, error, "branch crosses page boundary"
			iny
		:
		cmp nmi_count
		beq :--
		.assert >:--=>*, error, "branch crosses page boundary"
	; Y:X result
	; NTSC  0A:8D
	; PAL   0B:C8
	; Dendy 0C:92
	tya
	sec
	sbc #$0A
	rts
.endproc
.popseg

.proc reading_loop
	jsr poll_gamepads
	jsr common_input ; A/B for colour/music
	; button SELECT/START goes to index
	lda gamepad_new
	and #(PAD_SELECT | PAD_START)
	beq :+
		lda page
		sta page_index
		jsr index_knife
		lda #255
		sta page
		jsr page_retreat
		jsr index_loop
		jmp reading_loop
	:
	; tapping RIGHT or holding DOWN advances page
	lda gamepad_new
	and #PAD_R
	bne :+
	lda gamepad
	and #PAD_D
	beq advance_end
	:
		ldx page
		inx
		cpx page_count
		bcs advance_end
		inc page
		lda music_on ; when advancing to page 1 for the first time, turn on music (if not already toggled)
		bne :+
			jsr toggle_music
		:
		jsr page_advance
		jmp reading_loop
	advance_end:
	; tapping left LEFT or holding UP retreats page
	lda gamepad_new
	and #PAD_L
	bne :+
	lda gamepad
	and #PAD_U
	beq :++
	:
		ldx page
		beq :+
		dec page
		jsr page_retreat
		jmp reading_loop
	:
	jsr srender_on
	jmp reading_loop
.endproc

.proc page_advance
	PLAY_SOUND ::SOUND_PAGE
	jsr prepare_story_page
	ldx #0
	@pair:
		stx k
		jsr prepare_page_line_pair
		ldx k
		lda scroll_advance, X
		sta scroll_y
		jsr srender_row2
		ldx k
		inx
		cpx #13
		bcc @pair
	@remain:
		lda scroll_advance, X
		sta scroll_y
		jsr srender_on
		inx
		cpx #17
		bcc @remain
	lda #0
	sta knife_y ; hide knife if coming back from index
	sta scroll_y
	lda ppu_2000
	eor #%00000010 ; flip nametable vertically
	sta ppu_2000
	jsr flip_draw_nmt
	jmp srender_on
scroll_advance:
	.byte 1, 3, 6, 13, 26, 44, 71 ; smooth in
	.byte 100, 129, 158, 187 ; 29 pixels/frame
	.byte 208, 222, 229, 234, 237, 239 ; smooth out
	; It takes 13 frames to update the nametables.
	; Spreading the scroll over 17 frames with a few extra frames of acceleration/deceleration,
	; always moving by odd numbers to avoid the strobe-grid experience of scrolling by tile increments.
	; At frame 12 it catches up with 208. On frame 13 the update is finished,
	; but we take a few more frames to slow down smoothly.
.endproc

.proc page_retreat
	jsr prepare_story_page
	; first frame replaces page number (gives 8 more pixels of headroom at start)
	jsr prepare_page_number_single
	lda #<$0362
	sta nmi_addr+0
	lda #>$0362
	clc
	adc draw_nmt
	sta nmi_addr+1
	lda scroll_retreat+0
	sta scroll_y
	lda ppu_2000
	eor #%00000010
	sta ppu_2000
	jsr srender_row
	ldx #1
	@pair:
		stx k
		dex
		jsr prepare_page_line_pair
		ldx k
		lda scroll_retreat, X
		sta scroll_y
		jsr srender_row2
		ldx k
		inx
		cpx #14
		bcc @pair
	PLAY_SOUND ::SOUND_PAGE
	@remain:
		lda scroll_retreat, X
		sta scroll_y
		jsr srender_on
		inx
		cpx #25
		bcc @remain
	jmp flip_draw_nmt
scroll_retreat:
	.byte 239, 239, 238, 238, 237, 236, 235, 234 ,232, 230, 227, 224, 220, 216 ; slow smooth in
	.byte 187, 158, 129, 100, 71, 42, 13 ; 29 pixels/frame
	.byte 6, 3, 1, 0 ; short smooth out
	; On the first frame it updates just the line number to give extra headroom for scrolling up.
	; Then it takes 13 frames to update the nametables top to bottom before we can scroll into it.
	; The first 14 frames accelerate very slowly, taking up that headroom (up to 216),
	; then the rest moves quickly.
.endproc

.proc common_input
	; button A cycles colour
	lda gamepad_new
	and #PAD_A
	beq :++
		ldx palette+1
		inx
		cpx #$0D
		bcc :+
			ldx #$01
		:
		stx palette+1
		txa
		ora #$10
		sta palette+2
		PLAY_SOUND ::SOUND_SWITCH
	:
	; button B toggles music
	lda gamepad_new
	and #PAD_B
	beq :+
		jsr toggle_music
	:
	rts
.endproc

.proc toggle_music
	lda music_on
	cmp #1
	beq :+
		lda #1
		sta music_on
		lda #::MUSIC_BUTTERFLY
		sta player_next_music
		rts
	:
		lda #2
		sta music_on
		lda #::MUSIC_SILENT
		sta player_next_music
		rts
	;
.endproc

.proc index_loop
	INDEX_HOLD = 35 ; this many frames before auto-repeat triggers
	INDEX_REPEAT = 5 ; frames between auto-repeat
	jsr poll_gamepads ; clear any held buttons
loop:
	jsr poll_gamepads
	; typematic repeat counter
	lda gamepad
	cmp gamepad_old
	bne :+
		inc index_hold
		lda index_hold
		cmp #INDEX_HOLD
		bcc :++
		sec
		sbc #INDEX_REPEAT
		sta index_hold
		lda gamepad
		and #(PAD_L | PAD_R | PAD_U | PAD_D)
		ora gamepad_new
		sta gamepad_new ; re-press direction buttons
		jmp :++
	:
		lda #0
		sta index_hold
	:
	jsr common_input ; A/B for colour/music
	; LEFT decreases page
	lda gamepad_new
	and #(PAD_L)
	beq :+
		lda page_index
		beq :+
		dec page_index
		PLAY_SOUND ::SOUND_SWITCH
	:
	; RIGHT to increase page
	lda gamepad_new
	and #(PAD_R)
	beq :+
		ldx page_index
		inx
		cpx page_count
		bcs :+
		stx page_index
		PLAY_SOUND ::SOUND_SWITCH
	:
	; UP to decrease page by 5
	lda gamepad_new
	and #(PAD_U)
	beq :+
		lda page_index
		sec
		sbc #5
		bcc :+ ; alternatively could clamp to 0?
		sta page_index
		PLAY_SOUND ::SOUND_SWITCH
	:
	; DOWN to increase page by 5
	lda gamepad_new
	and #(PAD_D)
	beq :+
		lda page_index
		clc
		adc #5
		cmp page_count
		bcs :+ ; alternatively could clamp to page_count-1?
		sta page_index
		PLAY_SOUND ::SOUND_SWITCH
	:
	; SELECT/START to leave the index
	lda gamepad_new
	and #(PAD_SELECT | PAD_START)
	beq :+
		jmp exit
	:
	jsr index_knife
	jsr srender_on
	jmp loop
exit:
	lda page_index
	sta page
	jmp page_advance
.endproc

;
; read controller
;

.enum
	PAD_R = 1
	PAD_L = 2
	PAD_D = 4
	PAD_U = 8
	PAD_START = 16
	PAD_SELECT = 32
	PAD_B = 64
	PAD_A = 128
.endenum

.proc poll_gamepads
	lda gamepads+0
	sta gamepads_old+0
	lda gamepads+1
	sta gamepads_old+1
	lda gamepad
	sta gamepad_old
	ldx #1
	stx $4016
	ldx #0
	stx $4016
	:
		lda $4016
		and #3
		cmp #1
		rol gamepads+0
		lda $4017
		and #3
		cmp #1
		rol gamepads+1
		inx
		cpx #8
		bcc :-
	; onset from either controller goes into gamepad_new
	lda gamepads+0
	eor gamepads_old+0
	and gamepads+0
	sta gamepad_new
	lda gamepads+1
	eor gamepads_old+1
	and gamepads+1
	ora gamepad_new
	sta gamepad_new
	; both controllers combine into gamepad
	lda gamepads+0
	ora gamepads+1
	sta gamepad
	rts
.endproc

;
; danger drawing
;

.macro DRAW_ONE value_
	lda #value_
	sta $2007
.endmacro

.macro DRAW_REP value_, count_
	lda #value_
	ldx #count_
	jsr draw_rep
.endmacro

.proc draw_rep
	:
		sta $2007
		dex
		bne :-
	rts
.endproc

.proc draw_page
	DRAW_REP $00, 33
	DRAW_ONE $08
	DRAW_REP $04, 28
	DRAW_ONE $09
	ldy #0
	:
		DRAW_REP $00, 2
		DRAW_ONE $06
		DRAW_REP $20, 28
		DRAW_ONE $07
		iny
		cpy #26
		bcc :-
	DRAW_REP $00, 2
	DRAW_ONE $0A
	DRAW_REP $05, 28
	DRAW_ONE $0B
	DRAW_REP $00, (33+64)
	rts
.endproc

.proc immediate_row
	bit $2002
	lda nmi_addr+1
	sta $2006
	lda nmi_addr+0
	sta $2006
	ldx #0
	:
		lda nmi_buffer, X
		sta $2007
		inx
		cpx #PAGE_W
		bcc :-
	rts
.endproc

.proc immediate_row2
	jsr immediate_row
	;bit $2002
	lda nmi_addr+0
	clc
	adc #<32
	tax
	lda nmi_addr+1
	adc #>32
	sta $2006
	stx $2006
	ldx #0
	:
		lda nmi_buffer+PAGE_W, X
		sta $2007
		inx
		cpx #PAGE_W
		bcc :-
	rts
.endproc

; render calls + sprites

.proc srender_on
	jsr sprite_knife
	jmp render_on
.endproc

.proc srender_row
	jsr sprite_knife
	jmp render_row
.endproc

.proc srender_row2
	jsr sprite_knife
	jmp render_row2
.endproc

.proc sprite_knife
	lda knife_y
	bne onscreen
offscreen:
	lda #255
	sta oam+0
	sta oam+4
	rts
onscreen:
	sec
	sbc scroll_y
	bcc offscreen
	sta oam+0
	sta oam+4
	lda knife_x
	sta oam+3
	clc
	adc #8
	sta oam+7
	rts
.endproc

.proc setup_knife
	; pre-setup sprites and attributes
	lda #$0E
	sta oam+1
	lda #$0F
	sta oam+5
	lda #$00
	sta oam+2
	sta oam+6
	rts
.endproc

.proc index_knife
	ldx #0
	lda page_index
	sec
	:
		sbc #5
		bcc :+
		inx
		jmp :-
	:
	adc #5
	; A = page_index % 5
	; X = page_index / 5
	sta i
	asl
	asl
	clc
	adc i
	asl
	asl
	asl
	clc
	adc #32
	sta knife_x
	txa
	asl
	asl
	asl
	clc
	adc #62
	sta knife_y
	rts
.endproc

;
; rendering and NMI
;

.enum
	NMI_NONE=0
	NMI_ON
	NMI_ROW
	NMI_ROW2
.endenum

.proc render_on
	lda #NMI_ON
	jmp render_wait
.endproc

.proc render_row
	lda #NMI_ROW
	jmp render_wait
.endproc

.proc render_row2
	lda #NMI_ROW2
	jmp render_wait
.endproc

.proc render_wait
	.if ::GREY_PROFILE
		pha
		lda ppu_2001
		ora #%00000001
		sta $2001
		pla
	.endif
	sta nmi_mode
	:
		lda nmi_mode
		bne :-
	rts
.endproc

.proc nmi
	pha
	txa
	pha
	tya
	pha
	inc nmi_count
	lda nmi_on
	jeq skip_all
	lda nmi_mode
	beq skip_ppu
	; OAM DMA
	lda #0
	sta $2003
	lda #>oam
	sta $4014
	; palettes
	bit $2002
	ldx #0
	stx $2000 ; horizontal increment
	lda #$3F
	sta $2006
	stx $2006
	:
		lda palette, X
		sta $2007
		inx
		cpx #32
		bcc :-
	lda nmi_mode
	cmp #NMI_ROW
	bcc finish
		lda nmi_addr+1
		sta $2006
		lda nmi_addr+0
		sta $2006
		ldy #0
		:
			lda nmi_buffer, Y
			sta $2007
			iny
			cpy #(PAGE_W*1)
			bcc :-
	lda nmi_mode
	cmp #NMI_ROW2
	bcc finish
		lda nmi_addr+0
		clc
		adc #<32
		tax
		lda nmi_addr+1
		adc #>32
		sta $2006
		stx $2006
		:
			lda nmi_buffer, Y
			sta $2007
			iny
			cpy #(PAGE_W*2)
			bcc :-
finish:
	lda ppu_2000
	sta $2000
	lda ppu_2001
	sta $2001
	lda scroll_x
	sta $2005
	lda scroll_y
	sta $2005
	lda #0
	sta nmi_mode
skip_ppu:
	jsr music_tick
skip_all:
	pla
	tay
	pla
	tax
	pla
	rti
.endproc

;
; IRQ and reset
;

.proc irq
	; turn screen dim grey and enter infinite loop
	; (to use BRK as a error condition for debugging)
	lda #%11111111
	sta $2001
	:
	jmp :-
.endproc

.proc reset
	sei       ; disable maskable interrupts
	lda #0
	sta $2000 ; disable non-maskable interrupt
	lda #0
	sta $2001 ; rendering off
	sta $4010 ; disable DMC IRQ
	sta $4015 ; disable APU sound
	lda #$40
	sta $4017 ; disable APU IRQ
	cld       ; disable decimal mode
	ldx #$FF
	txs       ; setup stack
	; wait for vblank #1
	bit $2002
	:
		bit $2002
		bpl :-
	; clear RAM
	lda #0
	tax
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
	; wait for vblank #2
	:
		bit $2002
		bpl :-
	; ready
	jmp main
.endproc

;
; vectors
;

.segment "VECTORS"
.word nmi
.word reset
.word irq

;
; data
;

.segment "DATA"

palette_data:
	.byte $0F, $06, $16, $30
	.byte $0F, $09, $19, $30
	.byte $0F, $0C, $1C, $30
	.byte $0F, $03, $13, $30
	.byte $0F, $0F, $00, $10
	.byte $0F, $0B, $1B, $30
	.byte $0F, $02, $12, $30
	.byte $0F, $05, $15, $30

story:
	.ifndef CANONICAL
		.incbin "output/danger0000.hfb"
	.else
		.incbin "output/danger0000.hfc"
	.endif

;
; CHR graphics tiles
;

.segment "CHR"
.incbin "danger.chr"

;
; header
;

.segment "HEADER"

INES_MAPPER     = 0 ; NROM
INES_MIRROR     = 0 ; vertical nametables
INES_PRG_16K    = 2 ; 32K
INES_CHR_8K     = 1 ; 8K
INES_BATTERY    = 0
INES2           = %00001000 ; NES 2.0 flag for bit 7
INES2_SUBMAPPER = 0
INES2_PRGRAM    = 0
INES2_PRGBAT    = 0
INES2_CHRRAM    = 0
INES2_CHRBAT    = 0
INES2_REGION    = 2 ; 0=NTSC, 1=PAL, 2=Dual

; iNES 1 header
.byte 'N', 'E', 'S', $1A ; ID
.byte <INES_PRG_16K
.byte INES_CHR_8K
.byte INES_MIRROR | (INES_BATTERY << 1) | ((INES_MAPPER & $f) << 4)
.byte (<INES_MAPPER & %11110000) | INES2
; iNES 2 section
.byte (INES2_SUBMAPPER << 4) | (INES_MAPPER>>8)
.byte ((INES_CHR_8K >> 8) << 4) | (INES_PRG_16K >> 8)
.byte (INES2_PRGBAT << 4) | INES2_PRGRAM
.byte (INES2_CHRBAT << 4) | INES2_CHRRAM
.byte INES2_REGION
.byte $00 ; VS system
.byte $00, $00 ; padding/reserved
.assert * = 16, error, "NES header must be 16 bytes."
