@echo off
setlocal

cd /d "%~dp0"
if errorlevel 1 exit /b 1
copy /Y "..\out\build\release\extension\midisf2.hdll" "testMain\midisf2.hdll" >nul
cd testMain

echo [1/2] Compiling Miniaudio tests...
haxe test-miniaudio.hxml
if errorlevel 1 goto :fail

echo [2/2] Running Miniaudio tests...
hl test-miniaudio.hl
if errorlevel 1 goto :fail

exit /b 0

:fail
echo Tests failed with exit code %ERRORLEVEL%.
pause
