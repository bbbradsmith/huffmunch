@del output\*.o
@del output\*.nes
@del output\*.dbg
@del output\*.map


cc65\bin\ca65 -o output\huffmunch.o -g ..\huffmunch.s
@IF ERRORLEVEL 1 GOTO error

cc65\bin\ca65 -o output\danger.o -g danger.s
@IF ERRORLEVEL 1 GOTO error

cc65\bin\ca65 -o output\music.o -D SFX_NO_HALT -g music\music.s
@IF ERRORLEVEL 1 GOTO error

cc65\bin\ld65 -o output\danger.nes -m output\danger.map --dbgfile output\danger.dbg -C danger.cfg output\danger.o output\huffmunch.o output\music.o
@IF ERRORLEVEL 1 GOTO error

@echo.
@echo.
@echo Build successful!
@if NOT "%1" == "nopause" pause
@GOTO end
:error
@echo.
@echo.
@echo Build error!
@if NOT "%1" == "nopause" pause
:end
