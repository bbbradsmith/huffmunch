The Most Dangerous Game
=======================

A test of the huffmunch compression library for NES.
https://github.com/bbbradsmith/huffmunch

This compresses the text of the short story
"The Most Dangerous Game" and displays it as an NES ROM.

The original story was written by Richard Connell in 1924,
and is public domain.
https://en.wikipedia.org/wiki/The_Most_Dangerous_Game


danger.txt
	the original story text (public domain)
	https://archive.org/details/TheMostDangerousGame_129
danger_prepare.py
	python script to prepare the original text from danger.txt
	1. arranges the text to fit the NES screen: output\danger.bin
	2. generates compression list for each page: output\danger.lst
danger_compress.bat
	executes the huffmunch compressor: output\danger0000.hfb
readme.txt
	you are reading this


This demonstration is not yet finished. Please check back later.
