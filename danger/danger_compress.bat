..\release\huffmunch.exe -v -l output\danger.lst output\danger.hfb
REM ..\release\huffmunch.exe -dt -v -l output\danger.lst output\danger.hfb.d > output\danger.hfb.debug.txt
@if NOT "%1" == "nopause" pause
