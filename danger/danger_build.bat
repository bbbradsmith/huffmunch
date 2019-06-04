@del output\*.o
@del output\*.nes
@del output\*.dbg
@del output\*.map


cc65\bin\ca65 -o output\huffmunch.o -g ..\huffmunch.s
@IF ERRORLEVEL 1 GOTO error

cc65\bin\ca65 -o output\huffmunch_canonical.o -g ..\huffmunch_canonical.s
@IF ERRORLEVEL 1 GOTO error

cc65\bin\ca65 -o output\huffmunch_rle.o -g ..\huffmunch_rle.s
@IF ERRORLEVEL 1 GOTO error

cc65\bin\ca65 -o output\danger.o -D STANDARD -g danger.s
@IF ERRORLEVEL 1 GOTO error

cc65\bin\ca65 -o output\danger_canonical.o -D CANONICAL -g danger.s
@IF ERRORLEVEL 1 GOTO error

cc65\bin\ca65 -o output\danger_rle.o -D RLE -g danger.s
@IF ERRORLEVEL 1 GOTO error

cc65\bin\ca65 -o output\music.o -D SFX_NO_HALT -g music\music.s
@IF ERRORLEVEL 1 GOTO error

cc65\bin\ld65 -o output\danger.nes -m output\danger.map --dbgfile output\danger.dbg -C danger.cfg output\danger.o output\huffmunch.o output\music.o
@IF ERRORLEVEL 1 GOTO error

cc65\bin\ld65 -o output\danger_canonical.nes -m output\danger_canonical.map --dbgfile output\danger_canonical.dbg -C danger.cfg output\danger_canonical.o output\huffmunch_canonical.o output\music.o
@IF ERRORLEVEL 1 GOTO error

cc65\bin\ld65 -o output\danger_rle.nes -m output\danger_rle.map --dbgfile output\danger_rle.dbg -C danger.cfg output\danger_rle.o output\huffmunch_rle.o output\music.o
@IF ERRORLEVEL 1 GOTO error

@echo.
@echo.
@echo Build successful!
@pause
@GOTO end
:error
@echo.
@echo.
@echo Build error!
@pause
:end