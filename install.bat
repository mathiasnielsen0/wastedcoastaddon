@echo off
setlocal
title Wasted Coast (WC4L) installer

set "SRC=%~dp0WastedCoast"
if not exist "%SRC%\WastedCoast.toc" (
    echo Kunne ikke finde mappen WastedCoast ved siden af install.bat.
    echo Pak hele zip-filen ud foer du koerer installeren.
    echo.
    pause
    exit /b 1
)

echo ==============================================
echo   Wasted Coast (WC4L) - installer
echo ==============================================
echo.

rem --- Find World of Warcraft ---
set "WOW="
if exist "C:\Program Files (x86)\World of Warcraft\" set "WOW=C:\Program Files (x86)\World of Warcraft"
if not defined WOW if exist "C:\Program Files\World of Warcraft\" set "WOW=C:\Program Files\World of Warcraft"
if not defined WOW if exist "D:\World of Warcraft\" set "WOW=D:\World of Warcraft"
if not defined WOW if exist "C:\Games\World of Warcraft\" set "WOW=C:\Games\World of Warcraft"
if defined WOW goto found

echo Kunne ikke finde World of Warcraft automatisk.
echo Skriv stien til WoW-mappen, eller traek mappen hertil.
echo (Eksempel: D:\Games\World of Warcraft)
echo.
set /p "WOW=Sti: "
set "WOW=%WOW:"=%"
if "%WOW%"=="" goto fail

:found
echo Fandt WoW her: %WOW%
echo.
echo Hvilken version spiller I?
echo   1 = Classic Era   (_classic_era_)
echo   2 = Classic       (_classic_, fx Cataclysm/MoP Classic)
echo   3 = Anniversary   (_anniversary_, TBC Classic Anniversary)
echo.
choice /c 123 /n /m "Vaelg 1, 2 eller 3: "
set "FLAVOR=_classic_era_"
if errorlevel 2 set "FLAVOR=_classic_"
if errorlevel 3 set "FLAVOR=_anniversary_"

set "DEST=%WOW%\%FLAVOR%\Interface\AddOns"
if not exist "%WOW%\%FLAVOR%\" goto noflavor
if not exist "%DEST%" mkdir "%DEST%"

if exist "%DEST%\VennerneForever" (
    echo.
    echo BEMAERK: Den gamle demo-version "VennerneForever" ligger stadig i AddOns.
    echo Slet mappen manuelt, saa de to ikke koerer ved siden af hinanden.
)

echo.
echo Kopierer til: %DEST%\WastedCoast
xcopy "%SRC%" "%DEST%\WastedCoast\" /E /I /Y /Q >nul
if errorlevel 1 goto fail

echo.
echo Faerdig! Wasted Coast er installeret.
echo.
echo Naeste skridt:
echo   1. Start WoW (eller skriv /reload hvis spillet allerede koerer)
echo   2. Tjek at Wasted Coast er sat til paa addon-listen ved karaktervalg
echo   3. Skriv /wc4l i spillet
echo.
pause
exit /b 0

:noflavor
echo.
echo Mappen "%WOW%\%FLAVOR%" findes ikke.
echo Er den valgte version installeret? Proev den anden, eller tjek stien.
echo.
pause
exit /b 1

:fail
echo.
echo Installationen mislykkedes. Proev at kopiere mappen WastedCoast
echo manuelt til Interface\AddOns - se README.md.
echo.
pause
exit /b 1
