; The Most Dangerous Game
; Brad Smith, 2019
; https://github.com/bbbradsmith/huffmunch
;
; A demonstration of the Huffmmunch compression library,
; using The Most Dangerous Game by Richard Connell.

; select/start go to index/options page (scroll up to it)
; left/up go back one page
; right/down go back one page
; B stop/start music
; A cycle colours
; on title: when leaving title page start music if not already started
; -- (first time only, otherwise if B has stopped it, it should not restart again)

; back a page (or index) should scroll up
; - update page row at bottom
; - update 25 rows top to bottom
; - (scroll as far as you can as early as you can)

; forward (or leaving index) should scroll down
; - update 25 rows top to bottom
; - might be able to get a double with the page row
; - (scroll as far as you can as early as you can)

; finally:
; fill unused remaining space with music
; lizard music library?

; CHR needs a little hunting knife (16x8, black outline, 2 palettes maybe?)
; for a single sprite on the index page
; set up aseprite and get lizard palette into it (and gimp)... make a png?

PAGE_W = 28
PAGE_H = 25
PAGE_MAX = 100

.segment "ZEROPAGE"

; rendering
nmi_mode: .res 1
nmi_addr: .res 2
scroll_x: .res 1
scroll_y: .res 1
ppu_2000: .res 1
ppu_2001: .res 1

; gamepad
gamepads_old: .res 2
gamepads:     .res 2
gamepad_new:  .res 1 ; buttons pressed since last poll
gamepad:      .res 1 ; OR of both gamepads

; selection
page:       .res 1
page_count: .res 1
page_bytes: .res 2 ; just for debugging
page_index: .res 1 ; page selection on index screen
i:          .res 1 ; temporary counter
j:          .res 1 ; temporary counter
k:          .res 1 ; temporary counter
draw_nmt:   .res 1 ; next nametable to draw ($20 or $24)

; huffmunch data
.exportzp huffmunch_zpblock
huffmunch_zpblock: .res 9

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
	ldx #255
	ldy #240
	jsr draw_knife
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
	; clear button presses
	jsr poll_gamepads
	; begin rendering
	lda #%00011110
	sta ppu_2001
	lda #%10000000
	sta ppu_2000
	sta $2000 ; commence NMI
	jsr render_on
	jmp reading_loop
.endproc

.proc reading_loop
	jsr poll_gamepads
	; button A cycles colour
	lda gamepad_new
	and #PAD_A
	beq a_end
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
	a_end:
	; button B toggles music
	lda gamepad_new
	and #PAD_B
	beq b_end
		; TODO
	b_end:
	; button SELECT/START goes to index
	lda gamepad_new
	and #(PAD_SELECT | PAD_START)
	beq index_end
		lda page
		sta page_index
		lda #255
		sta page
		jsr page_retreat
		jsr index_loop
		jmp reading_loop
	index_end:
	; holding RIGHT/DOWN advances page
	lda gamepad
	and #(PAD_R | PAD_D)
	beq advance_end
		ldx page
		inx
		cpx page_count
		bcs advance_end
		inc page
		jsr page_advance
		jmp reading_loop
	advance_end:
	; holding LEFT/UP retreats page
	lda gamepad
	and #(PAD_L | PAD_U)
	beq retreat_end
		ldx page
		beq retreat_end
		dec page
		jsr page_retreat
		jmp reading_loop
	retreat_end:
	jsr render_on
	jmp reading_loop
.endproc

.proc page_advance
	jsr prepare_story_page
	ldx #0
	@pair:
		stx k
		jsr prepare_page_line_pair
		ldx k
		lda scroll_advance, X
		sta scroll_y
		jsr render_row2
		ldx k
		inx
		cpx #13
		bcc @pair
	@remain:
		lda scroll_advance, X
		sta scroll_y
		jsr render_on
		inx
		cpx #14
		bcc @remain
	lda #0
	sta scroll_y
	lda ppu_2000
	eor #%00000010 ; flip nametable vertically
	sta ppu_2000
	jsr flip_draw_nmt
	jmp render_on
scroll_advance:
	; TODO maybe add some smoothness to this? make sure it doesn't run past visible change
	.repeat 14, I
		.byte (I+1) * 16
	.endrepeat
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
	jsr render_row
	ldx #1
	@pair:
		stx k
		dex
		jsr prepare_page_line_pair
		ldx k
		lda scroll_retreat, X
		sta scroll_y
		jsr render_row2
		ldx k
		inx
		cpx #14
		bcc @pair
	@remain:
		lda scroll_retreat, X
		sta scroll_y
		jsr render_on
		inx
		cpx #24
		bcc @remain
	jmp flip_draw_nmt
scroll_retreat:
	; first 14 frames careful not to go past visible change (24 pixels)
	.repeat 14, I
		.byte 240 - (I+1)
	.endrepeat
	; remaining frames can be as fast as desired
	.repeat 10, I
		.byte 216-(((I+1)*216)/10)
	.endrepeat
.endproc

.proc index_loop
	; TODO
	rts
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
	lda gamepads+0
	eor gamepads_old+0
	and gamepads+0
	sta gamepad_new
	lda gamepads+1
	eor gamepads_old+1
	and gamepads+1
	ora gamepad_new
	sta gamepad_new
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

.proc draw_knife
	; TODO
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
	lda nmi_mode
	beq skip
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
skip:
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
	.byte $0F, $08, $18, $30
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
