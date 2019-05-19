.segment "ZEROPAGE"
nmi_update: .res 1
nmi_addr: .res 2
scroll_x: .res 1
scroll_y: .res 1
ppu_2000: .res 1
ppu_2001: .res 1
palette: .res 32

.exportzp huffmunch_zpblock
huffmunch_zpblock: .res 9

.segment "RAM"

.segment "OAM"
.align 256
oam: .res 256

.segment "CODE"

.macro PPU_LATCH addr_
	bit $2002
	lda #>addr_
	sta $2006
	lda #<addr_
	sta $2006
.endmacro

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
	; TODO setup title page etc.
	; begin rendering
	lda #%00011110
	sta ppu_2001
	lda #%10001000
	sta ppu_2000
	sta $2000 ; commence NMI
	jsr render_on
loop:
	; TODO
	jmp loop
.endproc

;
; read controller
;

; TODO

;
; drawing and NMI
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
	sta nmi_update
	:
		lda nmi_update
		bne :-
	rts
.endproc

.proc nmi
	pha
	txa
	pha
	tya
	pha
	lda nmi_update
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
	lda nmi_update
	cmp #NMI_ROW
	bcc finish
		lda nmi_addr+1
		sta $2006
		lda nmi_addr+0
		sta $2006
		; TODO ROW
	lda nmi_update
	cmp #NMI_ROW2
	bcc finish
		lda nmi_addr+0
		clc
		adc #32
		tax
		lda nmi_addr+1
		adc #0
		sta $2006
		stx $2006
		; TODO ROW2
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
	sta nmi_update
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
	rti
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
	.byte $0F, $16, $06, $30
	.byte $0F, $16, $06, $30
	.byte $0F, $16, $06, $30
	.byte $0F, $16, $06, $30
	.byte $0F, $16, $06, $30
	.byte $0F, $16, $06, $30
	.byte $0F, $16, $06, $30
	.byte $0F, $16, $06, $30

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
