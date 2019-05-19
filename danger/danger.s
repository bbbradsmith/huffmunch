.segment "ZEROPAGE"

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

main:
	; load palettes
	PPU_LATCH $3F00
	ldx #0
	:
		lda palettes, X
		sta $2007
		inx
		cpx #32
		bcc :-
	; more to do
loop:
	jmp loop

nmi:
	rti

irq:
	rti

reset:
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

.segment "VECTORS"
.word nmi
.word reset
.word irq

;
;
;

.segment "DATA"

palettes:
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
