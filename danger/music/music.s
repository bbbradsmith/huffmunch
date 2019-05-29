; Lizard Music Engine
; Copyright Brad Smith 2019
; http://lizardnes.com

;
; music and sound
;

.feature force_range
.macpack longbranch

.export music_tick
.export music_init

.export player_pal
.exportzp player_next_sound
.exportzp player_next_music
.exportzp player_pause
.export player_current_music

.include "../output/data_music.inc"

.segment "ZEROPAGE"

temp_ptrn:             .res 2 ; not required to persist outside of music_init/music_tick

; zero-page for convenience
player_next_sound:     .res 2
player_next_music:     .res 1
player_pause:          .res 1
; zero-page for indirection
pointer_pattern_table: .res 2
pointer_order:         .res 2
pointer_pattern:       .res 8
pointer_sfx_pattern:   .res 4

.segment "RAM"

player_pal:            .res 1
;player_next_sound:     .res 2
;player_next_music:     .res 1
;player_pause:          .res 1
player_current_music:  .res 1

player_speed:          .res 1
player_pattern_length: .res 1
player_row:            .res 1
player_row_sub:        .res 1
player_order_frame:    .res 1

player_row_skip:       .res 4
player_macro_pos:      .res 16
player_note:           .res 4
player_vol:            .res 4
player_halt:           .res 4
player_pitch_low:      .res 4
player_pitch_high:     .res 4

player_sfx_on:         .res 2
player_sfx_pos:        .res 2
player_sfx_skip:       .res 2

player_vol_out:        .res 4
player_freq_out_low:   .res 4
player_freq_out_high:  .res 4
player_duty_out:       .res 4
player_apu_high:       .res 4

;pointer_pattern_table: .res 2
;pointer_order:         .res 2
;pointer_pattern:       .res 8
pointer_macro:         .res 32
;pointer_sfx_pattern:   .res 4

.segment "CODE"

music_init:
	;
	; initialize the APU
	;
	; disable length counters, set volume to 0
	lda #%00110000
	sta $4000
	sta $4004
	sta $400C
	; init triangle halted
	lda #%10000000
	sta $4008
	; enable channels
	lda #%00001111
	sta $4015
	; disable and minimize sweep
	lda #%01111111
	sta $4001
	sta $4005
	; zero low freq
	lda #0
	sta $4002
	sta $4006
	sta $400A
	sta $400E
	sta $4011 ; reset ZXX
	; zero high freq and reload length counters
	lda #%00001000
	sta $4003
	sta $4007
	sta $400B
	sta $400F
	; flag to reset high freq registers
	lda #$FF
	sta player_apu_high+0
	sta player_apu_high+1
	sta player_apu_high+2
	sta player_apu_high+3
	;
	; initialize to song 0
	;
	lda #0
	jsr load_music
	rts

music_tick:
	; if new music assigned, load it now
	lda player_next_music
	cmp player_current_music
	beq :+
		jsr load_music
	:
	; if new sfx assigned, load it now
	lda player_next_sound+0
	beq :+
		ldx #0
		jsr load_sfx
	:
	lda player_next_sound+1
	beq :+
		ldx #1
		jsr load_sfx
	:
	; if paused, mute the APU and skip the update
	lda player_pause
	beq :+
		lda #0
		sta $4015
		; high freq registers need to reset when 4015 is renabled
		lda #$FF
		sta player_apu_high+0
		sta player_apu_high+1
		sta player_apu_high+2
		sta player_apu_high+3
		rts
	:
	;
	; tick pattern
	;
@pal_repeat: ; for PAL support, repeat every 5th frame
	lda player_row_sub
	jne @tick_pattern_end
		inc player_row
		ldx #0
		@channel_loop:
			lda player_row_skip, X
			beq :+
				dec player_row_skip, X
				jmp @next_channel
			:
			txa
			pha ; push X
			asl
			tax ; X *= 2
			@read_loop:
				; X = channel * 2
				; top of stack = channel
				lda (pointer_pattern+0, X) ; A = command
				inc pointer_pattern+0, X
				bne :+
					inc pointer_pattern+1, X
				:
				; if A < 0x80 skip and end row
				cmp #$80
				bcs :+
					tay
					pla
					tax
					tya
					sta player_row_skip, X
					jmp @next_channel
				:
				; if A == 0x80 halt and end row
				bne :+
					pla
					tax
					lda #1
					sta player_halt, X
					jmp @next_channel
				:
				; A >= 0x81
				; if A < 0xE0 play note and end row
				cmp #$E0
				bcs :+
					sec
					sbc #$81
					tay ; Y = note (A - 0x81)
					pla
					tax
					tya
					sta player_note, X
					lda #0
					sta player_halt, X
					sta player_pitch_low, X
					sta player_pitch_high, X
					sta player_macro_pos+ 0, X
					sta player_macro_pos+ 4, X
					sta player_macro_pos+ 8, X
					sta player_macro_pos+12, X
					jmp @next_channel
				:
				; A >= 0xE0
				; if A < 0xF0 volume
				cmp #$F0
				bcs :+
					and #$0F ; volume = A & 0x0F
					tay
					pla
					tax
					tya
					sta player_vol, X
					txa
					pha ; put X back on stack for next loop
					asl
					tax ; put X*2 back
					jmp @read_loop
				:
				; if A == 0xF0 set instrument
				bne :++
					lda #0
					sta temp_ptrn+1
					; let A = instrument
					lda (pointer_pattern+0, X)
					inc pointer_pattern+0, X
					bne :+
						inc pointer_pattern+1, X
					:
					; A *= 4 (store 2 high bits in temp_ptrn+1)
					asl
					rol temp_ptrn+1
					asl
					rol temp_ptrn+1
					clc
					adc #<data_music_instrument
					sta temp_ptrn+0
					lda #>data_music_instrument
					adc temp_ptrn+1
					sta temp_ptrn+1
					; temp_ptrn = data_music_instrument + (4 * instrument)
					; load 4 macros
					ldy #0
					lda (temp_ptrn), Y
					tay
					lda data_music_macro_low, Y
					sta pointer_macro+0+ 0, X
					lda data_music_macro_high, Y
					sta pointer_macro+1+ 0, X
					ldy #1
					lda (temp_ptrn), Y
					tay
					lda data_music_macro_low, Y
					sta pointer_macro+0+ 8, X
					lda data_music_macro_high, Y
					sta pointer_macro+1+ 8, X
					ldy #2
					lda (temp_ptrn), Y
					tay
					lda data_music_macro_low, Y
					sta pointer_macro+0+16, X
					lda data_music_macro_high, Y
					sta pointer_macro+1+16, X
					ldy #3
					lda (temp_ptrn), Y
					tay
					lda data_music_macro_low, Y
					sta pointer_macro+0+24, X
					lda data_music_macro_high, Y
					sta pointer_macro+1+24, X
					; reset the macro positions
					pla
					pha ; put X back on stack for next loop
					tax
					lda #0
					sta player_macro_pos+ 0, X
					sta player_macro_pos+ 4, X
					sta player_macro_pos+ 8, X
					sta player_macro_pos+12, X
					txa
					asl
					tax ; put back X*2 for next loop
					jmp @read_loop
				:
				; if A == F1 BXX
				cmp #$F1
				bne :++
					lda (pointer_pattern+0, X)
					inc pointer_pattern+0, X
					bne :+
						inc pointer_pattern+1, X
					:
					; A = (A*4)-4
					sec
					sbc #1
					asl
					asl
					.ifdef REMIX
						lda #1
						sta i ; mark loop has begun
						jmp @read_loop
					.endif
					sta player_order_frame
					; advance to end of pattern
					lda player_pattern_length
					sta player_row
					jmp @read_loop
				:
				; if A == F2 D00
				cmp #$F2
				bne :+
					; advance to end of pattern
					lda player_pattern_length
					sta player_row
					jmp @read_loop
				:
				; if A == F3 FXX
				cmp #$F3
				bne :++
					lda (pointer_pattern+0, X)
					inc pointer_pattern+0, X
					bne :+
						inc pointer_pattern+1, X
					:
					sta player_speed
					jmp @read_loop
				:
				; else this is an unimplemented command
				inc pointer_pattern+0, X
				bne :+
					inc pointer_pattern+1, X
				:
				jmp @read_loop
			; next channel
			@next_channel:
			; X = channel
			inx
			cpx #4
		jne @channel_loop
		; if player_row >= player_pattern_length
		;    advance order
		lda player_row
		cmp player_pattern_length
		bcc @advance_order_end
			lda #0
			sta player_row
			lda player_order_frame
			clc
			adc #4
			sta player_order_frame
			tay ; y = order+0
			ldx #0
			: ; for i=0;i<4;++i (X = i*2)
				tya
				pha ; push order+i
				lda (pointer_order), Y
				asl
				tay ; Y = order frame * 2
				lda (pointer_pattern_table), Y
				sta pointer_pattern+0, X
				iny
				lda (pointer_pattern_table), Y
				sta pointer_pattern+1, X
				; pull order+i
				pla
				tay
				iny ; ++i
				; next channel
				inx
				inx
				cpx #8
			bne :-
			lda #0
			ldx #0
			:
				sta player_row_skip, X
				inx
				cpx #4
			bne :-
		@advance_order_end:
		lda player_speed
		sta player_row_sub
	@tick_pattern_end:
	dec player_row_sub
	; adjust for pal (tick twice every 5th frame)
	lda player_pal ; 0 = NTSC, else PAL
	beq :++
		cmp #1 ; 1 = repeat this frame
		bne :+
			lda #6
			sta player_pal
			jmp @pal_repeat
		:
		dec player_pal
	:
	;
	; tick sfx
	;
	ldy #0
	lda player_sfx_on+0
	beq @sfx0_done
		lda player_sfx_skip+0
		beq :+
			dec player_sfx_skip+0
			jmp @sfx0_done
		:
		@sfx0_read_loop:
			lda (pointer_sfx_pattern+0), Y
			inc pointer_sfx_pattern+0
			bne :+
				inc pointer_sfx_pattern+1
			:
			; if A < 0x80 skip
			cmp #$80
			bcs :+
				sta player_sfx_skip+0
				jmp @sfx0_done
			:
			; if A == 0x80 halt
			bne :+
				lda #0
				sta player_sfx_on+0
				.ifndef SFX_NO_HALT
				lda #1
				sta player_halt+0
				.endif
				jmp @sfx0_done
			:
			; A >= 0x81
			; if A < 0xE0 note
			cmp #$E0
			bcs :+
				sec
				sbc #$81
				tax
				lda data_music_tuning_low, X
				sta player_freq_out_low+0
				lda data_music_tuning_high, X
				sta player_freq_out_high+0
				jmp @sfx0_done
			:
			; A >= 0xE0
			; if A < 0xF0 volume
			cmp #$F0
			bcs :+
				and #$0F
				sta player_vol_out+0
				jmp @sfx0_read_loop
			:
			; A >= 0xF0 duty
			and #$03
			sta player_duty_out+0
			jmp @sfx0_read_loop
		; end of sfx0_read_loop
	@sfx0_done:
	lda player_sfx_on+1
	beq @sfx1_done
		lda player_sfx_skip+1
		beq :+
			dec player_sfx_skip+1
			jmp @sfx1_done
		:
		@sfx1_read_loop:
			lda (pointer_sfx_pattern+2), Y
			inc pointer_sfx_pattern+2
			bne :+
				inc pointer_sfx_pattern+3
			:
			; if A < 0x80 skip
			cmp #$80
			bcs :+
				sta player_sfx_skip+1
				jmp @sfx1_done
			:
			; if A == 0x80 halt
			bne :+
				lda #0
				sta player_sfx_on+1
				.ifndef SFX_NO_HALT
				lda #1
				sta player_halt+3
				.endif
				jmp @sfx1_done
			:
			; A >= 0x81
			; if A < 0xE0 note
			cmp #$E0
			bcs :+
				eor #$FF ; A = $0F - (A - $81)
				sec
				adc #($0F+$81)
				sta player_freq_out_low+3
				jmp @sfx1_done
			:
			; A >= 0xE0
			; if A < 0xF0 volume
			cmp #$F0
			bcs :+
				and #$0F
				sta player_vol_out+3
				jmp @sfx1_read_loop
			:
			; A >= 0xF0 duty
			and #$01
			sta player_duty_out+3
			jmp @sfx1_read_loop
		; end of sfx1_read_loop
	@sfx1_done:
	;
	; tick macros
	;
	; channel 0 square 1
	lda player_sfx_on+0
	jne @channel_0_sfx_override
		; volume
		lda player_halt+0
		bne :+
			lda #0
			jsr tick_macro
			asl
			asl
			asl
			asl
			ora player_vol+0
			tax
			lda data_music_multiply, X
			jmp :++
		:
			lda #0
			jsr tick_macro
			lda #0
		:
		sta player_vol_out+0
		; arp
		lda #4
		jsr tick_macro
		clc
		adc player_note+0
		cmp #96
		bcc :+
			lda #95
		:
		tax
		lda data_music_tuning_low, X
		sta player_freq_out_low+0
		lda data_music_tuning_high, X
		sta player_freq_out_high+0
		; pitch
		lda #8
		jsr tick_macro
		cmp #0
		bmi :+
			clc
			adc player_pitch_low+0
			sta player_pitch_low+0
			lda player_pitch_high+0
			adc #0
			sta player_pitch_high+0
			jmp :++
		:
			clc
			adc player_pitch_low+0
			sta player_pitch_low+0
			lda player_pitch_high+0
			adc #$FF
			sta player_pitch_high+0
		:
		lda player_freq_out_low+0
		clc
		adc player_pitch_low+0
		sta player_freq_out_low+0
		lda player_freq_out_high+0
		adc player_pitch_high+0
		and #$07
		sta player_freq_out_high+0
		; duty
		lda #12
		jsr tick_macro
		and #$03
		sta player_duty_out+0
		jmp @tick_channel_1
	@channel_0_sfx_override:
		lda #0
		jsr tick_macro
		lda #4
		jsr tick_macro
		lda #8
		jsr tick_macro
		; pitch needs update even when SFX playing
		cmp #0
		bmi :+
			clc
			adc player_pitch_low+0
			sta player_pitch_low+0
			lda player_pitch_high+0
			adc #0
			sta player_pitch_high+0
			jmp :++
		:
			clc
			adc player_pitch_low+0
			sta player_pitch_low+0
			lda player_pitch_high+0
			adc #$FF
			sta player_pitch_high+0
		:
		lda #12
		jsr tick_macro
	; channel 1 square 2
	@tick_channel_1:
		; volume
		lda player_halt+1
		bne :+
			lda #1
			jsr tick_macro
			asl
			asl
			asl
			asl
			ora player_vol+1
			tax
			lda data_music_multiply, X
			jmp :++
		:
			lda #1
			jsr tick_macro
			lda #0
		:
		sta player_vol_out+1
		; arp
		lda #5
		jsr tick_macro
		clc
		adc player_note+1
		cmp #96
		bcc :+
			lda #95
		:
		tax
		lda data_music_tuning_low, X
		sta player_freq_out_low+1
		lda data_music_tuning_high, X
		sta player_freq_out_high+1
		; pitch
		lda #9
		jsr tick_macro
		cmp #0
		bmi :+
			clc
			adc player_pitch_low+1
			sta player_pitch_low+1
			lda player_pitch_high+1
			adc #0
			sta player_pitch_high+1
			jmp :++
		:
			clc
			adc player_pitch_low+1
			sta player_pitch_low+1
			lda player_pitch_high+1
			adc #$FF
			sta player_pitch_high+1
		:
		lda player_freq_out_low+1
		clc
		adc player_pitch_low+1
		sta player_freq_out_low+1
		lda player_freq_out_high+1
		adc player_pitch_high+1
		and #$07
		sta player_freq_out_high+1
		; duty
		lda #13
		jsr tick_macro
		and #$03
		sta player_duty_out+1
	; channel 2 triangle
	@tick_channel_2:
	; volume
		lda player_halt+2
		bne :+
			lda #2
			jsr tick_macro
			asl
			asl
			asl
			asl
			ora player_vol+2
			tax
			lda data_music_multiply, X
			jmp :++
		:
			lda #2
			jsr tick_macro
			lda #0
		:
		sta player_vol_out+2
		; arp
		lda #6
		jsr tick_macro
		clc
		adc player_note+2
		cmp #96
		bcc :+
			lda #95
		:
		tax
		lda data_music_tuning_low, X
		sta player_freq_out_low+2
		lda data_music_tuning_high, X
		sta player_freq_out_high+2
		; pitch
		lda #10
		jsr tick_macro
		cmp #0
		bmi :+
			clc
			adc player_pitch_low+2
			sta player_pitch_low+2
			lda player_pitch_high+2
			adc #0
			sta player_pitch_high+2
			jmp :++
		:
			clc
			adc player_pitch_low+2
			sta player_pitch_low+2
			lda player_pitch_high+2
			adc #$FF
			sta player_pitch_high+2
		:
		lda player_freq_out_low+2
		clc
		adc player_pitch_low+2
		sta player_freq_out_low+2
		lda player_freq_out_high+2
		adc player_pitch_high+2
		and #$07
		sta player_freq_out_high+2
		; duty
		;lda #14
		;jsr tick_macro
	; channel 3 noise
	@tick_channel_3:
	lda player_sfx_on+1
	bne @channel_3_sfx_override
		; volume
		lda player_halt+3
		bne :+
			lda #3
			jsr tick_macro
			asl
			asl
			asl
			asl
			ora player_vol+3
			tax
			lda data_music_multiply, X
			jmp :++
		:
			lda #3
			jsr tick_macro
			lda #0
		:
		sta player_vol_out+3
		; arp
		lda #7
		jsr tick_macro
		clc
		adc player_note+3
		cmp #96
		bcc :+
			lda #95
		:
		eor #$FF ; A = $0F - A
		sec
		adc #$0F
		and #$0F ; A &= $0F
		sta player_freq_out_low+3
		; pitch
		;lda #11
		;jsr tick_macro
		; duty
		lda #15
		jsr tick_macro
		and #$01
		sta player_duty_out+3
		jmp @tick_channel_end
	@channel_3_sfx_override:
		lda #3
		jsr tick_macro
		lda #7
		jsr tick_macro
		;lda #11
		;jsr tick_macro
		lda #15
		jsr tick_macro
	@tick_channel_end:
	;
	; write to APU
	;
	lda #%00001111
	sta $4015 ; unmute if muted
	lda #%11000000
	sta $4017 ; tick the frame counter
	; channel 0
	lda player_duty_out+0
	asl
	asl
	asl
	asl
	asl
	asl
	ora #%00110000
	ora player_vol_out+0
	sta $4000
	lda player_freq_out_low+0
	sta $4002
	lda player_freq_out_high+0
	ora #%00001000
	cmp player_apu_high+0
	beq :+
		sta $4003
		sta player_apu_high+0
	:
	; channel 1
	lda player_duty_out+1
	asl
	asl
	asl
	asl
	asl
	asl
	ora #%00110000
	ora player_vol_out+1
	sta $4004
	lda player_freq_out_low+1
	sta $4006
	lda player_freq_out_high+1
	ora #%00001000
	cmp player_apu_high+1
	beq :+
		sta $4007
		sta player_apu_high+1
	:
	; channel 2
	lda player_vol_out+2
	beq :+
		lda #%11111111
		jmp :++
	:
		lda #%10000000
	:
	sta $4008
	lda player_freq_out_low+2
	sta $400A
	lda player_freq_out_high+2
	ora #%00001000
	cmp player_apu_high+2
	beq :+
		sta $400B
		sta player_apu_high+2
	:
	; channel 3
	lda player_vol_out+3
	ora #%00110000
	sta $400C
	lda player_duty_out+3
	ror
	ror
	ora player_freq_out_low+3
	sta $400E
	lda #%00001000
	cmp player_apu_high+3
	beq :+
		sta $400F
		sta player_apu_high+3
	:
	rts

tick_macro:
	pha
	asl
	tax
	lda pointer_macro+0, X
	sta temp_ptrn+0
	lda pointer_macro+1, X
	sta temp_ptrn+1
	pla
	tax
	lda player_macro_pos, X
	tay
	@macro_loop:
		lda (temp_ptrn), Y
		iny
		cmp #<LOOP
		bne :+
			lda (temp_ptrn), Y
			tay
			jmp @macro_loop
		:
		pha
		tya
		sta player_macro_pos, X
		pla
	rts

load_music:
	; store current music, put in x as index
	sta player_current_music
	tax
	; setup speed, pattern length, order pointer
	lda data_music_speed, x
	sta player_speed
	lda data_music_pattern_length, x
	sta player_pattern_length
	lda data_music_order_low, x
	sta pointer_order+0
	lda data_music_order_high, x
	sta pointer_order+1
	; x *= 2
	txa
	asl
	tax
	; load pattern table pointer
	lda data_music_pattern+0, x
	sta pointer_pattern_table+0
	lda data_music_pattern+1, x
	sta pointer_pattern_table+1
	; initialize the pattern reader
	lda #0
	sta player_row
	sta player_row_sub
	sta player_order_frame
	; load first pattern and initialize channels
	ldx #0
	:
		lda #0
		sta player_row_skip, x
		lda #15
		sta player_vol, x
		lda #1
		sta player_halt, x
		; fetch order 0
		txa
		pha ; store X temporarily
		tay ; copy X to Y
		asl
		tax ; X *= 2
		lda (pointer_order), y
		asl
		tay
		lda (pointer_pattern_table), y
		sta pointer_pattern, x
		iny
		lda (pointer_pattern_table), y
		sta pointer_pattern+1, x
		; restore and increment x
		pla
		tax
		inx
		cpx #4
	bne :-
	; clear all macros (point to macro 0)
	lda data_music_macro_low
	ldy data_music_macro_high
	ldx #0
	:
		sta pointer_macro+0, x
		tya
		sta pointer_macro+1, x
		lda data_music_macro_low
		inx
		inx
		cpx #32
	bne :-
	lda #0
	ldx #0
	:
		sta player_macro_pos, x
		inx
		cpx #16
	bne :-
	rts

load_sfx:
	tay
	lda #0
	sta player_next_sound, x
	sta player_sfx_pos, x
	sta player_sfx_skip, x
	lda #1
	sta player_sfx_on, x
	cpx #1
	bne :+ ; clear periodic noise flag if using noise channel
		lda #0
		sta player_duty_out+3
		ldx #2 ; X *= 2
	:
	; X = 0 or 2 (index to pointer_sfx_pattern array of 16 bit pointers)
	; Y = sfx index
	lda data_sfx_low, Y
	sta pointer_sfx_pattern+0, X
	lda data_sfx_high, Y
	sta pointer_sfx_pattern+1, X
	rts

; end of file
