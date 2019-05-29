Lizard Music Engine
===================

This folder contains an NES music implementation derived from the game Lizard.
http://lizardnes.com

This code is released under the Creative Commons Attribution License (CC BY 4.0)
For more details, and for more Lizard source code, see:
https://github.com/bbbradsmith/lizard_src_demo


Prerequisites:
- Famitracker 0.4.6: http://famitracker.com/
- Python 3: https://www.python.org/
- CC65: https://cc65.github.io/

To build the music data:

1. Place FamiTracker.exe (0.4.6) in this folder
2. Create music FTM files (numbered starting from 00)
   music_00.ftm should be silent, will run from startup
3. Create sound effect FTM files (numbered starting from 01)
   sfx_01.ftm, etc.
4. Run export_music.py to build the exported music data.

Music can use only the following effects:
   Bxx (looping)
   D00 (variable pattern length)
   F0x (speed change)
Volume column is supported.
Music must use tempo 150. Only the speed setting may change.
Hi-Pitch macros are not supported.
Note release macros are not supported.
DPCM is not supported.
Using pitch and arpeggio macros simultaneously may have a different result than Famitracker.

The maximum number of empty rows between events in a pattern is 127.
Empty patterns longer than 127 rows may need to be broken up with extra events
to avoid a "too many skipped rows" error.

Sound effects must be created with speed 1.
Can only use one channel, either the first square, or the noise channel.
Will end when a note cut is reached.
Volume column is allowed.
Vxx is allowed, but no other effects are.

A playing sound effect will cancel any current music note on the same channel,
and play instead of music for its duration of effect.
The music will resume on that channel at the next note.


To use the music engine:

1. Build music.s with ca65 and include its object in your link.
2. Titles from the FTM files will become MUSIC_[TITLE] and SOUND_[TITLE] enums in data_music_enums.inc
3. Include music.inc in your project's assembly files that need to interface with the music engine.
4. Set player_pal to 1 if this is a 50Hz system.
5. Call music_init at startup.
6. Call music_tick at end of NMI.

To play music:
	lda #MUSIC_[TITLE]
	sta player_music_next

To play a sound:
	; this macro will clobber A
	PLAY_SOUND SOUND_[TITLE]

Write 1 to player_pause to temporarily pause music. 0 to resume.


Notes:

2152 bytes of code and note/volume tables
22 bytes of zeropage
105 bytes of other RAM
~1830 cycles per most frames
~2500 cycles peak
~4000 cycles if a new music is loaded

(Optionally could place all variables on ZP, saves about 300 bytes of code and ~100 cycles per frame.)
