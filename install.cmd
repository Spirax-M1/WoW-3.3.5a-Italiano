@echo off
setlocal
chcp 65001 >nul
title WoW 3.3.5a Italiano - Installer v1.0.0

echo.
echo WoW 3.3.5a Italiano - Installer v1.0.0
echo ========================================
echo.

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" %*

set "INSTALL_RESULT=%ERRORLEVEL%"

echo.
if "%INSTALL_RESULT%"=="0" (
    echo Installazione terminata.
) else (
    echo ERRORE: installazione non completata.
    echo Codice PowerShell: %INSTALL_RESULT%
)

echo.
pause
endlocal
