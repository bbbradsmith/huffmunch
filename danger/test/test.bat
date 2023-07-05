@del ..\output\test.c.s
@del ..\output\test.o
@del ..\output\test.c.o
@del ..\output\huffmunch.o
@del ..\output\huffmunch_c.o
@del ..\output\huffmunch_c_internal.o
@del ..\output\test.bin

..\cc65\bin\ca65 -o ..\output\huffmunch.o -g ..\..\huffmunch.s
@IF ERRORLEVEL 1 GOTO error

..\cc65\bin\ca65 -o ..\output\huffmunch_c.o -D EXTERNAL_ZPBLOCK -g ..\..\huffmunch_c.s
@IF ERRORLEVEL 1 GOTO error

..\cc65\bin\ca65 -o ..\output\huffmunch_c_internal.o -g ..\..\huffmunch_c.s
@IF ERRORLEVEL 1 GOTO error

..\cc65\bin\cc65 -o ..\output\test.c.s -T -O -g test.c
@IF ERRORLEVEL 1 GOTO error

..\cc65\bin\ca65 -o ..\output\test.c.o -g ..\output\test.c.s
@IF ERRORLEVEL 1 GOTO error

..\cc65\bin\ca65 -o ..\output\test.o -D EXTERNAL_ZPBLOCK -g test.s
@IF ERRORLEVEL 1 GOTO error

..\cc65\bin\ca65 -o ..\output\test_internal.o -g test.s
@IF ERRORLEVEL 1 GOTO error

..\cc65\bin\ld65 -o ..\output\test.bin           -t sim6502 -m ..\output\test.bin.map           ..\output\test.o           ..\output\huffmunch.o           ..\output\huffmunch_c.o          ..\output\test.c.o sim6502.lib
@IF ERRORLEVEL 1 GOTO error

..\cc65\bin\ld65 -o ..\output\test_internal.bin  -t sim6502 -m ..\output\test_internal.bin.map  ..\output\test_internal.o  ..\output\huffmunch.o           ..\output\huffmunch_c_internal.o ..\output\test.c.o sim6502.lib
@IF ERRORLEVEL 1 GOTO error

..\cc65\bin\sim65 -c ..\output\test.bin
@IF ERRORLEVEL 1 GOTO error

..\cc65\bin\sim65 -c ..\output\test_internal.bin
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