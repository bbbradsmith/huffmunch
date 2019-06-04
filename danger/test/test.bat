@del ..\output\test.c.s
@del ..\output\test.o
@del ..\output\test_canonical.o
@del ..\output\test.c.o
@del ..\output\huffmunch.o
@del ..\output\huffmunch_canonical.o
@del ..\output\test.bin
@del ..\output\test_canonical.bin


..\cc65\bin\ca65 -o ..\output\huffmunch.o -g ..\..\huffmunch.s
@IF ERRORLEVEL 1 GOTO error

..\cc65\bin\ca65 -o ..\output\huffmunch_canonical.o -g ..\..\huffmunch_canonical.s
@IF ERRORLEVEL 1 GOTO error

..\cc65\bin\ca65 -o ..\output\huffmunch_rle.o -g ..\..\huffmunch_rle.s
@IF ERRORLEVEL 1 GOTO error

..\cc65\bin\cc65 -o ..\output\test.c.s -T -O -g test.c
@IF ERRORLEVEL 1 GOTO error

..\cc65\bin\ca65 -o ..\output\test.c.o -g ..\output\test.c.s
@IF ERRORLEVEL 1 GOTO error

..\cc65\bin\ca65 -o ..\output\test.o -D STANDARD -g test.s
@IF ERRORLEVEL 1 GOTO error

..\cc65\bin\ca65 -o ..\output\test_canonical.o -D CANONICAL -g test.s
@IF ERRORLEVEL 1 GOTO error

..\cc65\bin\ca65 -o ..\output\test_rle.o -D RLE -g test.s
@IF ERRORLEVEL 1 GOTO error

..\cc65\bin\ld65 -o ..\output\test.bin -C test.cfg -m ..\output\test.bin.map ..\output\test.o ..\output\huffmunch.o ..\output\test.c.o sim6502.lib 
@IF ERRORLEVEL 1 GOTO error

..\cc65\bin\ld65 -o ..\output\test_canonical.bin -C test.cfg -m ..\output\test_canonical.bin.map ..\output\test_canonical.o ..\output\huffmunch_canonical.o ..\output\test.c.o sim6502.lib
@IF ERRORLEVEL 1 GOTO error

..\cc65\bin\ld65 -o ..\output\test_rle.bin -C test.cfg -m ..\output\test_rle.bin.map ..\output\test_rle.o ..\output\huffmunch_rle.o ..\output\test.c.o sim6502.lib
@IF ERRORLEVEL 1 GOTO error

..\cc65\bin\sim65 ..\output\test.bin
@IF ERRORLEVEL 1 GOTO error

..\cc65\bin\sim65 ..\output\test_canonical.bin
@IF ERRORLEVEL 1 GOTO error

..\cc65\bin\sim65 ..\output\test_rle.bin
@IF ERRORLEVEL 1 GOTO error

@echo.
@echo.
@echo Build and test successful!
@pause
@GOTO end
:error
@echo.
@echo.
@echo Build or test error!
@pause
:end