@echo off
setlocal
chcp 65001 >nul
title WoW 3.3.5a Italiano - Refresh v1.0.0

echo.
echo WoW 3.3.5a Italiano - Refresh v1.0.0
echo ====================================
echo.

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0refresh.ps1" %*

set "REFRESH_RESULT=%ERRORLEVEL%"

echo.
if "%REFRESH_RESULT%"=="0" (
    echo Refresh terminato.
) else (
    echo ERRORE: refresh non completato.
    echo Codice PowerShell: %REFRESH_RESULT%
)

echo.
pause
endlocal
