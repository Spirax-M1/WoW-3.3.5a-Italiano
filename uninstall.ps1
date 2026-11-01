param(
    [string]$GamePath = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $Root "client-compatibility.ps1")
$PatchManifestPath = Join-Path $Root "metadata\patch_manifest.json"


function Get-SafePath {
    param([string]$Base, [string]$Relative)
    if ([string]::IsNullOrWhiteSpace($Relative) -or [IO.Path]::IsPathRooted($Relative) -or $Relative.Contains(':')) {
        throw "Percorso non valido: $Relative"
    }
    $Current = $Base
    foreach ($Part in ($Relative -split '[\\/]')) {
        if ($Part -eq '' -or $Part -eq '.' -or $Part -eq '..') { throw "Percorso non valido: $Relative" }
        $Current = Join-Path $Current $Part
        if (Test-Path -LiteralPath $Current) {
            $Item = Get-Item -LiteralPath $Current -Force
            if (($Item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "Link o junction non supportato: $Current"
            }
        }
    }
    return $Current
}

function Write-Step {
    param([string]$Text)

    Write-Host ""
    Write-Host "== $Text ==" -ForegroundColor Cyan
}

function Get-Sha256 {
    param([string]$Path)

    return (
        Get-FileHash -LiteralPath $Path -Algorithm SHA256
    ).Hash.ToLowerInvariant()
}

function Convert-HexToBytes {
    param([string]$Hex)

    if (($Hex.Length % 2) -ne 0) {
        throw "Stringa HEX non valida."
    }

    [byte[]]$Result = New-Object byte[] ($Hex.Length / 2)

    for ($i = 0; $i -lt $Result.Length; $i++) {
        $Result[$i] = [Convert]::ToByte(
            $Hex.Substring($i * 2, 2),
            16
        )
    }

    return ,$Result
}

function Test-WowFolder {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $false
    }

    return Test-Path -LiteralPath (
        Join-Path $Path "Wow.exe"
    ) -PathType Leaf
}

function Normalize-GamePath {
    param([string]$Path)

    $Path = $Path.Trim()

    if (
        $Path.Length -ge 2 -and
        $Path.StartsWith('"') -and
        $Path.EndsWith('"')
    ) {
        $Path = $Path.Substring(1, $Path.Length - 2)
    }

    return [IO.Path]::GetFullPath($Path)
}

Write-Host ""
Write-Host "WoW 3.3.5a Italiano - Uninstall v1.0.1"
Write-Host "======================================"
Write-Host ""

if (-not (Test-Path -LiteralPath $PatchManifestPath -PathType Leaf)) {
    throw "patch_manifest.json non trovato."
}

$PatchManifest = Get-Content `
    -LiteralPath $PatchManifestPath `
    -Raw |
    ConvertFrom-Json

# ------------------------------------------------------------
# Trova client
# ------------------------------------------------------------

Write-Step "Ricerca client WoW"

if (-not [string]::IsNullOrWhiteSpace($GamePath)) {
    $GamePath = Normalize-GamePath $GamePath
    if (-not (Test-WowFolder $GamePath)) {
        throw "Wow.exe non trovato nel percorso indicato: $GamePath"
    }
}

if (-not (Test-WowFolder $GamePath)) {
    $Candidates = New-Object System.Collections.Generic.List[string]

    $LocalCandidates = @(
        $Root,
        (Split-Path -Parent $Root),
        (Join-Path $env:USERPROFILE "Games\World of Warcraft 3.3.5a")
    )

    foreach ($Candidate in $LocalCandidates) {
        if (Test-WowFolder $Candidate) {
            $Candidates.Add(
                (Normalize-GamePath $Candidate)
            )
        }
    }

    foreach ($Drive in (Get-PSDrive -PSProvider FileSystem)) {
        if ([string]::IsNullOrWhiteSpace($Drive.Root)) {
            continue
        }

        $DriveCandidates = @(
            (Join-Path $Drive.Root "World of Warcraft 3.3.5a"),
            (Join-Path $Drive.Root "Games\World of Warcraft 3.3.5a"),
            (Join-Path $Drive.Root "WoW 3.3.5a")
        )

        foreach ($Candidate in $DriveCandidates) {
            if (Test-WowFolder $Candidate) {
                $Candidates.Add(
                    (Normalize-GamePath $Candidate)
                )
            }
        }
    }

    $Candidates = @(
        $Candidates |
        Select-Object -Unique
    )

    if ($Candidates.Count -eq 1) {
        $GamePath = $Candidates[0]
        Write-Host "Client rilevato:"
        Write-Host $GamePath
    }
    else {
        while ($true) {
            $Entered = Read-Host "Inserisci la cartella del client WoW 3.3.5a"

            try {
                $Entered = Normalize-GamePath $Entered
            }
            catch {
                Write-Host "Percorso non valido." -ForegroundColor Yellow
                continue
            }

            if (Test-WowFolder $Entered) {
                $GamePath = $Entered
                break
            }

            Write-Host "Wow.exe non trovato in quella cartella." -ForegroundColor Yellow
        }
    }
}

$WowPath = Join-Path $GamePath "Wow.exe"

# ------------------------------------------------------------
# Baseline
# ------------------------------------------------------------

$BackupRoot = Join-Path $GamePath "WoW-ITA-Backup"
$BaselineRoot = Join-Path $BackupRoot "v1.0.0-baseline"
$BaselineFiles = Join-Path $BaselineRoot "files"
$BaselineManifestPath = Join-Path $BaselineRoot "baseline.json"
$WowBackupPath = Join-Path $BaselineRoot "Wow.exe.original"

Write-Step "Verifica baseline"

if (-not (Test-Path -LiteralPath $BaselineManifestPath -PathType Leaf)) {
    throw @"
Baseline di installazione non trovata.

Per sicurezza l'uninstaller non rimuove file senza sapere
quali esistevano prima dell'installazione.
"@
}

$Baseline = Get-Content `
    -LiteralPath $BaselineManifestPath `
    -Raw |
    ConvertFrom-Json

Write-Host "Baseline trovata:"
Write-Host $BaselineRoot

# ------------------------------------------------------------
# Ripristino payload precedente
# ------------------------------------------------------------

$null = Get-SafePath $GamePath "WoW-ITA-Backup/v1.0.0-baseline/baseline.json"
Assert-PayloadBaseline $Baseline $GamePath (Join-Path $Root "payload") $BaselineFiles

# Verify all required backups before removing or replacing any payload file.
if ($Baseline.format -ne 1 -or $Baseline.package_version -ne "1.0.0") {
    throw "Baseline incompatibile."
}
$Seen = @{}
foreach ($Relative in @("Wow.exe", "Wow.exe.wowita.restore.tmp", "WoW-ITA-Backup/v1.0.0-baseline/Wow.exe.original")) { $null = Get-SafePath $GamePath $Relative }
foreach ($Entry in $Baseline.files) {
    $Relative = [string]$Entry.relative_path
    $null = Get-SafePath $GamePath $Relative
    if ($Seen.ContainsKey($Relative)) { throw "Baseline duplicata." }
    $Seen[$Relative] = $true
    if ([IO.Path]::IsPathRooted($Relative) -or $Relative -match '(^|[\\/])\.\.([\\/]|$)' -or $Relative.Contains(':')) {
        throw "Percorso baseline non valido: $Relative"
    }
    if ([bool]$Entry.existed_before_install) {
        $BackupFile = Get-SafePath $BaselineFiles $Relative
        if (-not (Test-Path -LiteralPath $BackupFile -PathType Leaf)) {
            throw "Backup mancante per: $Relative"
        }
        if ($Entry.PSObject.Properties.Name -contains 'sha256') {
            if ($Entry.sha256 -and (Get-Sha256 $BackupFile) -ne $Entry.sha256) { throw "Backup corrotto: $Relative" }
        }
    }
}
[byte[]]$OriginalData = [IO.File]::ReadAllBytes($WowPath)
$PreflightHash = Get-BytesHash $OriginalData
[byte[]]$Candidate = Get-CompatibleBytes $OriginalData $PatchManifest $true
$RestoredHash = Get-BytesHash $Candidate

Write-Step "Ripristino file precedenti"

$Restored = 0
$Removed = 0

foreach ($Entry in $Baseline.files) {
    $Relative = [string]$Entry.relative_path
    $Target = Get-SafePath $GamePath $Relative

    if ([bool]$Entry.existed_before_install) {
        $BackupFile = Get-SafePath $BaselineFiles $Relative

        if (-not (Test-Path -LiteralPath $BackupFile -PathType Leaf)) {
            throw "Backup mancante per: $Relative"
        }

        $TargetParent = Split-Path -Parent $Target

        New-Item `
            -ItemType Directory `
            -Path $TargetParent `
            -Force |
            Out-Null

        Copy-Item `
            -LiteralPath $BackupFile `
            -Destination $Target `
            -Force

        $Restored++
    }
    else {
        if (Test-Path -LiteralPath $Target -PathType Leaf) {
            Remove-Item `
                -LiteralPath $Target `
                -Force

            $Removed++
        }
    }
}

Write-Host "File ripristinati : $Restored"
Write-Host "File rimossi      : $Removed"

# ------------------------------------------------------------
# Ripristino Wow.exe
# ------------------------------------------------------------

Write-Step "Ripristino Wow.exe"

if ((Get-Sha256 $WowPath) -ne $PreflightHash) { throw "Wow.exe modificato durante la disinstallazione." }
if ($PreflightHash -ne $RestoredHash) {
    $TempWow = Join-Path $GamePath "Wow.exe.wowita.restore.tmp"
    [IO.File]::WriteAllBytes($TempWow, $Candidate)
    if ((Get-Sha256 $TempWow) -ne $RestoredHash) { throw "Verifica ripristino Wow.exe fallita." }
    Move-Item -LiteralPath $TempWow -Destination $WowPath -Force
}
Write-Host "Regioni della mod ripristinate; altre modifiche conservate."

# ------------------------------------------------------------
# Pulizia cartelle vuote create dagli addon
# ------------------------------------------------------------

$PossibleEmptyDirs = @(
    (Join-Path $GamePath "Interface\AddOns\QuestTradutor\Init"),
    (Join-Path $GamePath "Interface\AddOns\QuestTradutor\Fonts"),
    (Join-Path $GamePath "Interface\AddOns\QuestTradutor"),
    (Join-Path $GamePath "Interface\AddOns\WoWItaliano")
)

foreach ($Dir in $PossibleEmptyDirs) {
    if (Test-Path -LiteralPath $Dir -PathType Container) {
        $Children = @(
            Get-ChildItem `
                -LiteralPath $Dir `
                -Force
        )

        if ($Children.Count -eq 0) {
            Remove-Item `
                -LiteralPath $Dir `
                -Force
        }
    }
}

Write-Host ""
Write-Host "======================================="
Write-Host "DISINSTALLAZIONE COMPLETATA"
Write-Host "======================================="
Write-Host ""
Write-Host "La baseline e stata conservata in:"
Write-Host $BaselineRoot
Write-Host ""
Write-Host "Puoi eliminarla manualmente solo dopo aver verificato"
Write-Host "che il client e stato ripristinato correttamente."

