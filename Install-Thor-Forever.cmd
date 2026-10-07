@echo off
echo Thor Forever - separate installation
echo Close WoW and Battle.net before proceeding. Your game must already be installed.
echo This creates a separate runtime, prefix and settings. Shared game Data is not read-only.
echo Leave this container open. Preparation can take several minutes.
pause
rem The Unix path of this folder: Z:\x\y\ becomes /x/y.
if /i not "%~d0"=="Z:" (
    echo Open this file through drive Z:, or use Thor-Forever.exe instead.
    pause
    exit /b 2
)
set "TF=%~dp0"
set "TF=%TF:~2,-1%"
set "TF=%TF:\=/%"
start.exe /unix /system/bin/sh %TF%/installer/setup.sh
echo Open the setup-report folder to see the result. Do not run installation repeatedly.
pause
