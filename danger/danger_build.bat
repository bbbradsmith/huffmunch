@del output\*.o
@del output\*.nes
@del output\*.dbg
@del output\*.map


cc65\bin\ca65 -o output\huffmunch.o -g ..\huffmunch.s
@IF ERRORLEVEL 1 GOTO error

cc65\bin\ca65 -o output\huffmunch_canonical.o -g ..\huffmunch_canonical.s
@IF ERRORLEVEL 1 GOTO error

cc65\bin\ca65 -o output\danger.o -g danger.s
@IF ERRORLEVEL 1 GOTO error

cc65\bin\ca65 -o output\danger_canonical.o -D CANONICAL -g danger.s
@IF ERRORLEVEL 1 GOTO error

cc65\bin\ld65 -o output\danger.nes -m output\danger.map --dbgfile output\danger.dbg -C danger.cfg output\danger.o output\huffmunch.o
@IF ERRORLEVEL 1 GOTO error

cc65\bin\ld65 -o output\danger_canonical.nes -m output\danger_canonical.map --dbgfile output\danger_canonical.dbg -C danger.cfg output\danger_canonical.o output\huffmunch_canonical.o
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