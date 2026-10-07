@echo off
echo Thor Forever - read-only setup check
echo No game settings or components will be changed.
rem The Unix path of this folder: Z:\x\y\ becomes /x/y.
if /i not "%~d0"=="Z:" (
    echo Open this file through drive Z:, or use Thor-Forever.exe instead.
    pause
    exit /b 2
)
set "TF=%~dp0"
set "TF=%TF:~2,-1%"
set "TF=%TF:\=/%"
start.exe /unix /system/bin/sh %TF%/check-setup.sh
echo Wait five seconds, then open setup-check.txt in the installer folder.
pause
