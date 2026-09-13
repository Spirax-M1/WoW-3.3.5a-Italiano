param(
    [string]$GamePath = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$PayloadRoot = Join-Path $Root "payload"
$MetadataRoot = Join-Path $Root "metadata"
$PatchManifestPath = Join-Path $MetadataRoot "patch_manifest.json"
$ChecksumPath = Join-Path $MetadataRoot "SHA256SUMS"

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
Write-Host "WoW 3.3.5a Italiano - Installer v1.0.0"
Write-Host "======================================="
Write-Host ""

# ------------------------------------------------------------
# Verifica integrita pacchetto
# ------------------------------------------------------------

Write-Step "Verifica integrita pacchetto"

if (-not (Test-Path -LiteralPath $PayloadRoot -PathType Container)) {
    throw "Cartella payload mancante."
}

if (-not (Test-Path -LiteralPath $PatchManifestPath -PathType Leaf)) {
    throw "patch_manifest.json mancante."
}

if (-not (Test-Path -LiteralPath $ChecksumPath -PathType Leaf)) {
    throw "SHA256SUMS mancante."
}

$ChecksumLines = Get-Content -LiteralPath $ChecksumPath

$VerifiedFiles = 0

foreach ($Line in $ChecksumLines) {
    if ([string]::IsNullOrWhiteSpace($Line)) {
        continue
    }

    if ($Line -notmatch '^([0-9a-fA-F]{64})\s{2}(.+)$') {
        throw "Riga SHA256SUMS non valida: $Line"
    }

    $ExpectedHash = $Matches[1].ToLowerInvariant()
    $RelativePath = $Matches[2] -replace '/', '\'
    $PackageFile = Join-Path $Root $RelativePath

    if (-not (Test-Path -LiteralPath $PackageFile -PathType Leaf)) {
        throw "File del pacchetto mancante: $RelativePath"
    }

    $ActualHash = Get-Sha256 $PackageFile

    if ($ActualHash -ne $ExpectedHash) {
        throw "Checksum errato: $RelativePath"
    }

    $VerifiedFiles++
}

Write-Host "Checksum payload: PASS ($VerifiedFiles file)"

# ------------------------------------------------------------
# Trova client
# ------------------------------------------------------------

Write-Step "Ricerca client WoW 3.3.5a"

$Candidates = New-Object System.Collections.Generic.List[string]

if (-not [string]::IsNullOrWhiteSpace($GamePath)) {
    try {
        $Candidate = Normalize-GamePath $GamePath

        if (Test-WowFolder $Candidate) {
            $Candidates.Add($Candidate)
        }
    }
    catch {
    }
}

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
    if ($Candidates.Count -gt 1) {
        Write-Host "Sono stati trovati piu client:"
        Write-Host ""

        foreach ($Candidate in $Candidates) {
            Write-Host "  $Candidate"
        }

        Write-Host ""
    }

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

$WowPath = Join-Path $GamePath "Wow.exe"

# ------------------------------------------------------------
# Verifica Wow.exe
# ------------------------------------------------------------

Write-Step "Verifica Wow.exe"

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

$CurrentHash = Get-Sha256 $WowPath

Write-Host "SHA256 Wow.exe:"
Write-Host $CurrentHash

$WowState = ""

if ($CurrentHash -eq $OriginalHash) {
    $WowState = "ORIGINAL"
    Write-Host "Stato: client originale compatibile" -ForegroundColor Green
}
elseif ($CurrentHash -eq $PatchedHash) {
    $WowState = "PATCHED"
    Write-Host "Stato: Wow.exe gia patchato" -ForegroundColor Green
}
else {
    throw @"
Wow.exe non riconosciuto.

Questo installer supporta esclusivamente:
World of Warcraft WotLK 3.3.5a build 12340 enUS.

Il file NON verra modificato.
"@
}

# ------------------------------------------------------------
# Baseline backup
# ------------------------------------------------------------

Write-Step "Backup"

$BackupRoot = Join-Path $GamePath "WoW-ITA-Backup"
$BaselineRoot = Join-Path $BackupRoot "v1.0.0-baseline"
$BaselineFiles = Join-Path $BaselineRoot "files"
$BaselineManifestPath = Join-Path $BaselineRoot "baseline.json"
$WowBackupPath = Join-Path $BaselineRoot "Wow.exe.original"

New-Item `
    -ItemType Directory `
    -Path $BaselineRoot `
    -Force |
    Out-Null

if (-not (Test-Path -LiteralPath $BaselineManifestPath -PathType Leaf)) {
    Write-Host "Creo baseline dei file che verranno sovrascritti..."

    $BaselineEntries = @()

    $PayloadFiles = Get-ChildItem `
        -LiteralPath $PayloadRoot `
        -File `
        -Recurse

    foreach ($Source in $PayloadFiles) {
        $Relative = $Source.FullName.Substring(
            $PayloadRoot.Length
        ).TrimStart('\')

        $Target = Join-Path $GamePath $Relative
        $Existed = Test-Path -LiteralPath $Target -PathType Leaf

        if ($Existed) {
            $BackupTarget = Join-Path $BaselineFiles $Relative
            $BackupParent = Split-Path -Parent $BackupTarget

            New-Item `
                -ItemType Directory `
                -Path $BackupParent `
                -Force |
                Out-Null

            Copy-Item `
                -LiteralPath $Target `
                -Destination $BackupTarget `
                -Force
        }

        $BaselineEntries += [PSCustomObject]@{
            relative_path = $Relative
            existed_before_install = [bool]$Existed
        }
    }

    [PSCustomObject]@{
        format = 1
        package_version = "1.0.0"
        created_utc = [DateTime]::UtcNow.ToString("o")
        files = $BaselineEntries
    } |
        ConvertTo-Json -Depth 6 |
        Set-Content `
            -LiteralPath $BaselineManifestPath `
            -Encoding UTF8

    Write-Host "Baseline payload: creata"
}
else {
    Write-Host "Baseline payload: gia esistente, non viene sovrascritta"
}

if (
    $WowState -eq "ORIGINAL" -and
    -not (Test-Path -LiteralPath $WowBackupPath -PathType Leaf)
) {
    Copy-Item `
        -LiteralPath $WowPath `
        -Destination $WowBackupPath

    if ((Get-Sha256 $WowBackupPath) -ne $OriginalHash) {
        Remove-Item -LiteralPath $WowBackupPath -Force
        throw "Verifica backup Wow.exe fallita."
    }

    Write-Host "Backup Wow.exe originale: creato"
}
elseif (Test-Path -LiteralPath $WowBackupPath -PathType Leaf) {
    Write-Host "Backup Wow.exe originale: gia presente"
}
else {
    Write-Host "Wow.exe era gia patchato; nessun originale disponibile da salvare."
}

# ------------------------------------------------------------
# Installa payload
# ------------------------------------------------------------

Write-Step "Installazione localizzazione"

$PayloadFiles = Get-ChildItem `
    -LiteralPath $PayloadRoot `
    -File `
    -Recurse

foreach ($Source in $PayloadFiles) {
    $Relative = $Source.FullName.Substring(
        $PayloadRoot.Length
    ).TrimStart('\')

    $Target = Join-Path $GamePath $Relative
    $TargetParent = Split-Path -Parent $Target

    New-Item `
        -ItemType Directory `
        -Path $TargetParent `
        -Force |
        Out-Null

    Copy-Item `
        -LiteralPath $Source.FullName `
        -Destination $Target `
        -Force
}

Write-Host "Payload installato: $($PayloadFiles.Count) file"

# ------------------------------------------------------------
# Patch Wow.exe
# ------------------------------------------------------------

if ($WowState -eq "ORIGINAL") {
    Write-Step "Patch Wow.exe"

    [byte[]]$WowBytes = [IO.File]::ReadAllBytes($WowPath)

    foreach ($Patch in $PatchManifest.patches) {
        $Offset = [int64]$Patch.offset

        [byte[]]$OldBytes = Convert-HexToBytes $Patch.old_hex
        [byte[]]$NewBytes = Convert-HexToBytes $Patch.new_hex

        if ($OldBytes.Length -ne $NewBytes.Length) {
            throw "Patch con lunghezza OLD/NEW differente."
        }

        if (
            ($Offset + $OldBytes.Length) -gt
            $WowBytes.Length
        ) {
            throw "Patch fuori dai limiti di Wow.exe."
        }

        for ($i = 0; $i -lt $OldBytes.Length; $i++) {
            if ($WowBytes[$Offset + $i] -ne $OldBytes[$i]) {
                throw (
                    "Byte originali inattesi all'offset 0x{0:X}." -f $Offset
                )
            }
        }

        for ($i = 0; $i -lt $NewBytes.Length; $i++) {
            $WowBytes[$Offset + $i] = $NewBytes[$i]
        }
    }

    $TempWow = Join-Path $GamePath "Wow.exe.wowita.tmp"

    [IO.File]::WriteAllBytes(
        $TempWow,
        $WowBytes
    )

    $TempHash = Get-Sha256 $TempWow

    if ($TempHash -ne $PatchedHash) {
        Remove-Item -LiteralPath $TempWow -Force

        throw @"
La patch prodotta non corrisponde all'hash finale atteso.
Wow.exe originale NON e stato sostituito.
"@
    }

    Move-Item `
        -LiteralPath $TempWow `
        -Destination $WowPath `
        -Force

    Write-Host "Patch Wow.exe: PASS"
}
else {
    Write-Host ""
    Write-Host "Wow.exe gia patchato: nessuna modifica necessaria."
}

# ------------------------------------------------------------
# Verifica finale
# ------------------------------------------------------------

Write-Step "Verifica finale"

$FinalWowHash = Get-Sha256 $WowPath

if ($FinalWowHash -ne $PatchedHash) {
    throw "Hash finale Wow.exe non valido."
}

$InstalledOk = 0

foreach ($Line in $ChecksumLines) {
    if ([string]::IsNullOrWhiteSpace($Line)) {
        continue
    }

    if ($Line -notmatch '^([0-9a-fA-F]{64})\s{2}payload/(.+)$') {
        continue
    }

    $ExpectedHash = $Matches[1].ToLowerInvariant()
    $Relative = $Matches[2] -replace '/', '\'
    $Target = Join-Path $GamePath $Relative

    if (-not (Test-Path -LiteralPath $Target -PathType Leaf)) {
        throw "File installato mancante: $Relative"
    }

    if ((Get-Sha256 $Target) -ne $ExpectedHash) {
        throw "File installato non valido: $Relative"
    }

    $InstalledOk++
}

Write-Host "Wow.exe: PASS"
Write-Host "Payload : PASS ($InstalledOk file)"

Write-Host ""
Write-Host "======================================="
Write-Host "INSTALLAZIONE COMPLETATA CON SUCCESSO"
Write-Host "======================================="
Write-Host ""
Write-Host "Client:"
Write-Host $GamePath
Write-Host ""
Write-Host "Puoi avviare Wow.exe normalmente."
