The Most Dangerous Game
=======================

A test of the huffmunch compression library for NES.
https://github.com/bbbradsmith/huffmunch

This compresses the text of the short story
"The Most Dangerous Game" and displays it as an NES ROM.

The original story was written by Richard Connell in 1924,
and is public domain.
https://en.wikipedia.org/wiki/The_Most_Dangerous_Game


Prerequisites:

cc65: https://cc65.github.io/
python: https://www.python.org/ (optional)
FamiTracker: http://famitracker.com/ (optional)


Build from the release package:

1. Unpack cc65 into a folder called cc65/
2. Run danger_build.bat
3. See output/danger.nes


Build from source:

1. Create an output/ folder.
2. Place FamiTracker.exe in the music/ folder.
3. Run music/music_export.py to build the music data.
4. Run danger_prepare.py to prepare the story text for compression.
5. Run danger_compress.py to compress the story text.
6. Run danger_build to build the NES ROM.
7. See output/danger.nes


Files:

danger.s
	assembly source code
danger.cfg
	ld65 linker configuration
danger.txt
	the original story text (public domain)
	https://archive.org/details/TheMostDangerousGame_129
danger_build.bat
	builds the NES ROM
danger_prepare.py
	python script to prepare the original text from danger.txt
	1. arranges the text to fit the NES screen: output\danger.bin
	2. generates compression list for each page: output\danger.lst
danger_compress.bat
	executes the huffmunch compressor
	input: output\danger.bin
	output: output\danger0000.hfb
music\
	music files and music engine
output\
	pre-built files from release package
..\huffmunch.s
..\huffmunch_canonical.s
	huffmunch decompressor for 6502
..\release\huffmunch.exe
	huffmunch compressor
test\
	verifies the huffmunch 6502 implementation against the compressed data
readme.txt
	you are reading this


This demonstration is not yet finished. Please check back later.
