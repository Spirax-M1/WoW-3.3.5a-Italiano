param(
    [string]$GamePath = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Installer = Join-Path $Root "install.ps1"

Write-Host ""
Write-Host "WoW 3.3.5a Italiano - Refresh v1.0.0"
Write-Host "===================================="
Write-Host ""

if (-not (Test-Path -LiteralPath $Installer -PathType Leaf)) {
    throw "install.ps1 non trovato."
}

if ([string]::IsNullOrWhiteSpace($GamePath)) {
    & $Installer
}
else {
    & $Installer -GamePath $GamePath
}

Write-Host ""
Write-Host "Refresh completato."

