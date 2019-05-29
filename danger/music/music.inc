; Lizard Music Engine
; Copyright Brad Smith 2019
; http://lizardnes.com

;
; music.inc
;
; common definitions for playing sound

.import music_init
.import music_tick

.import player_pal
.importzp player_pause
.importzp player_next_music
.importzp player_next_sound
.import player_current_music

.include "../output/data_music_enums.inc"

; xxx must be a constant, clobbers A
.macro PLAY_SOUND xxx
	lda #xxx
	sta player_next_sound + .ident(.sprintf("SOUND_MODE__%d",xxx))
.endmacro

; end of file
