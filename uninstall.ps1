param(
    [string]$GamePath = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$PatchManifestPath = Join-Path $Root "metadata\patch_manifest.json"

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
Write-Host "WoW 3.3.5a Italiano - Uninstall v1.0.0"
Write-Host "======================================"
Write-Host ""

if (-not (Test-Path -LiteralPath $PatchManifestPath -PathType Leaf)) {
    throw "patch_manifest.json non trovato."
}

$PatchManifest = Get-Content `
    -LiteralPath $PatchManifestPath `
    -Raw |
    ConvertFrom-Json

$OriginalHash = (
    $PatchManifest.wow_exe.original_sha256
).ToLowerInvariant()

$PatchedHash = (
    $PatchManifest.wow_exe.patched_sha256
).ToLowerInvariant()

# ------------------------------------------------------------
# Trova client
# ------------------------------------------------------------

Write-Step "Ricerca client WoW"

if (-not [string]::IsNullOrWhiteSpace($GamePath)) {
    try {
        $GamePath = Normalize-GamePath $GamePath
    }
    catch {
        $GamePath = ""
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

Write-Step "Ripristino file precedenti"

$Restored = 0
$Removed = 0

foreach ($Entry in $Baseline.files) {
    $Relative = [string]$Entry.relative_path
    $Target = Join-Path $GamePath $Relative

    if ([bool]$Entry.existed_before_install) {
        $BackupFile = Join-Path $BaselineFiles $Relative

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

$CurrentHash = Get-Sha256 $WowPath

Write-Host "Hash corrente:"
Write-Host $CurrentHash

if ($CurrentHash -eq $OriginalHash) {
    Write-Host "Wow.exe e gia originale."
}
elseif ($CurrentHash -eq $PatchedHash) {

    if (Test-Path -LiteralPath $WowBackupPath -PathType Leaf) {
        $BackupHash = Get-Sha256 $WowBackupPath

        if ($BackupHash -ne $OriginalHash) {
            throw "Il backup Wow.exe originale ha un hash inatteso."
        }

        $TempWow = Join-Path $GamePath "Wow.exe.wowita.restore.tmp"

        Copy-Item `
            -LiteralPath $WowBackupPath `
            -Destination $TempWow `
            -Force

        if ((Get-Sha256 $TempWow) -ne $OriginalHash) {
            Remove-Item -LiteralPath $TempWow -Force
            throw "Verifica del Wow.exe da ripristinare fallita."
        }

        Move-Item `
            -LiteralPath $TempWow `
            -Destination $WowPath `
            -Force

        Write-Host "Wow.exe ripristinato dal backup originale."
    }
    else {
        Write-Host "Backup originale non presente."
        Write-Host "Applico la patch inversa verificata..."

        [byte[]]$WowBytes = [IO.File]::ReadAllBytes($WowPath)

        foreach ($Patch in $PatchManifest.patches) {
            $Offset = [int64]$Patch.offset

            [byte[]]$OldBytes = Convert-HexToBytes $Patch.old_hex
            [byte[]]$NewBytes = Convert-HexToBytes $Patch.new_hex

            if ($OldBytes.Length -ne $NewBytes.Length) {
                throw "Patch inversa con lunghezze differenti."
            }

            if (
                ($Offset + $NewBytes.Length) -gt
                $WowBytes.Length
            ) {
                throw "Patch inversa fuori dai limiti di Wow.exe."
            }

            for ($i = 0; $i -lt $NewBytes.Length; $i++) {
                if ($WowBytes[$Offset + $i] -ne $NewBytes[$i]) {
                    throw (
                        "Byte patched inattesi all'offset 0x{0:X}." -f $Offset
                    )
                }
            }

            for ($i = 0; $i -lt $OldBytes.Length; $i++) {
                $WowBytes[$Offset + $i] = $OldBytes[$i]
            }
        }

        $TempWow = Join-Path $GamePath "Wow.exe.wowita.restore.tmp"

        [IO.File]::WriteAllBytes(
            $TempWow,
            $WowBytes
        )

        if ((Get-Sha256 $TempWow) -ne $OriginalHash) {
            Remove-Item -LiteralPath $TempWow -Force
            throw "La patch inversa non produce il Wow.exe originale atteso."
        }

        Move-Item `
            -LiteralPath $TempWow `
            -Destination $WowPath `
            -Force

        Write-Host "Patch inversa Wow.exe: PASS"
    }
}
else {
    Write-Host ""
    Write-Host "ATTENZIONE:" -ForegroundColor Yellow
    Write-Host "Wow.exe ha un hash sconosciuto."
    Write-Host "Per sicurezza NON viene modificato." -ForegroundColor Yellow
}

# ------------------------------------------------------------
# Verifica finale Wow.exe
# ------------------------------------------------------------

$FinalHash = Get-Sha256 $WowPath

if ($FinalHash -eq $OriginalHash) {
    Write-Host "Wow.exe finale: ORIGINAL_EXPECTED" -ForegroundColor Green
}
elseif ($FinalHash -eq $PatchedHash) {
    Write-Host "Wow.exe finale: ancora PATCHED" -ForegroundColor Yellow
}
else {
    Write-Host "Wow.exe finale: HASH SCONOSCIUTO" -ForegroundColor Yellow
}

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
