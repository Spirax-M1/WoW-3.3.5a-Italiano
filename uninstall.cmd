@echo off
setlocal
chcp 65001 >nul
title WoW 3.3.5a Italiano - Uninstall v1.0.0

echo.
echo WoW 3.3.5a Italiano - Uninstall v1.0.0
echo ======================================
echo.

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0uninstall.ps1" %*

set "UNINSTALL_RESULT=%ERRORLEVEL%"

echo.
if "%UNINSTALL_RESULT%"=="0" (
    echo Disinstallazione terminata.
) else (
    echo ERRORE: disinstallazione non completata.
    echo Codice PowerShell: %UNINSTALL_RESULT%
)

echo.
pause
endlocal & exit /b %UNINSTALL_RESULT%

