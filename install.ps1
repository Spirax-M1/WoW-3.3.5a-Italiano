param(
    [string]$GamePath = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $Root "client-compatibility.ps1")
$PayloadRoot = Join-Path $Root "payload"
$MetadataRoot = Join-Path $Root "metadata"
$PatchManifestPath = Join-Path $MetadataRoot "patch_manifest.json"
$ChecksumPath = Join-Path $MetadataRoot "SHA256SUMS"


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
Write-Host "WoW 3.3.5a Italiano - Installer v1.0.1"
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
$VerifiedPaths = @{}

foreach ($Line in $ChecksumLines) {
    if ([string]::IsNullOrWhiteSpace($Line)) {
        continue
    }

    if ($Line -notmatch '^([0-9a-fA-F]{64})\s{2}(.+)$') {
        throw "Riga SHA256SUMS non valida: $Line"
    }

    $ExpectedHash = $Matches[1].ToLowerInvariant()
    $RelativePath = $Matches[2] -replace '/', '\'
    if ($RelativePath -notmatch '^payload[\\/]') { throw "Checksum fuori dal payload." }
    if ($VerifiedPaths.ContainsKey($RelativePath)) { throw "Checksum duplicato: $RelativePath" }
    $VerifiedPaths[$RelativePath] = $true
    $PackageFile = Get-SafePath $Root $RelativePath

    if (-not (Test-Path -LiteralPath $PackageFile -PathType Leaf)) {
        throw "File del pacchetto mancante: $RelativePath"
    }

    $ActualHash = Get-Sha256 $PackageFile

    if ($ActualHash -ne $ExpectedHash) {
        throw "Checksum errato: $RelativePath"
    }

    $VerifiedFiles++
}

$ActualPayload = @(Get-ChildItem -LiteralPath $PayloadRoot -File -Recurse)
if ($VerifiedFiles -eq 0 -or $ActualPayload.Count -ne $VerifiedFiles) { throw "Elenco payload diverso dai checksum." }
foreach ($File in $ActualPayload) {
    $Relative = "payload\" + $File.FullName.Substring($PayloadRoot.Length).TrimStart('\')
    if (-not $VerifiedPaths.ContainsKey($Relative)) { throw "File non verificato: $Relative" }
}
Write-Host "Checksum payload: PASS ($VerifiedFiles file)"

# ------------------------------------------------------------
# Trova client
# ------------------------------------------------------------

Write-Step "Ricerca client WoW 3.3.5a"

$Candidates = New-Object System.Collections.Generic.List[string]

if (-not [string]::IsNullOrWhiteSpace($GamePath)) {
    $Candidate = Normalize-GamePath $GamePath
    if (-not (Test-WowFolder $Candidate)) {
        throw "Wow.exe non trovato nel percorso indicato: $Candidate"
    }
    $Candidates.Add($Candidate)
}
else {

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

$null = Get-SafePath $GamePath "Wow.exe"
foreach ($Relative in $PatchManifest.required_files) {
    $Required = Get-SafePath $GamePath $Relative
    if (-not (Test-Path -LiteralPath $Required -PathType Leaf) -or (Get-Item -LiteralPath $Required).Length -eq 0) {
        throw "File richiesto dalla localizzazione mancante o vuoto: $Relative"
    }
}
[byte[]]$OriginalData = [IO.File]::ReadAllBytes($WowPath)
[byte[]]$Candidate = Get-CompatibleBytes $OriginalData $PatchManifest
$OriginalHash = Get-BytesHash $OriginalData
$PatchedHash = Get-BytesHash $Candidate
$WowState = if ($OriginalHash -eq $PatchedHash) { "PATCHED" } else { "ORIGINAL" }
Write-Host "Client 3.3.5a compatibile: $WowState"

# ------------------------------------------------------------
# Baseline backup
# ------------------------------------------------------------

Write-Step "Backup"

$BackupRoot = Join-Path $GamePath "WoW-ITA-Backup"
$BaselineRoot = Join-Path $BackupRoot "v1.0.0-baseline"
$BaselineFiles = Join-Path $BaselineRoot "files"
$BaselineManifestPath = Join-Path $BaselineRoot "baseline.json"
$WowBackupPath = Join-Path $BaselineRoot "Wow.exe.original"

foreach ($Relative in @("Wow.exe", "Wow.exe.wowita.tmp", "WoW-ITA-Backup/v1.0.0-baseline/baseline.json", "WoW-ITA-Backup/v1.0.0-baseline/Wow.exe.original")) {
    $null = Get-SafePath $GamePath $Relative
}
foreach ($Source in $ActualPayload) {
    $Relative = $Source.FullName.Substring($PayloadRoot.Length).TrimStart('\')
    $null = Get-SafePath $GamePath $Relative
    $null = Get-SafePath $GamePath ("WoW-ITA-Backup/v1.0.0-baseline/files/" + $Relative)
}
if (Test-Path -LiteralPath $BaselineManifestPath -PathType Leaf) {
    $ExistingBaseline = Get-Content -LiteralPath $BaselineManifestPath -Raw | ConvertFrom-Json
    Assert-PayloadBaseline $ExistingBaseline $GamePath $PayloadRoot $BaselineFiles
}

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

        $Target = Get-SafePath $GamePath $Relative
        $Existed = Test-Path -LiteralPath $Target -PathType Leaf

        if ($Existed) {
            $BackupTarget = Get-SafePath $BaselineFiles $Relative
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
            sha256 = $(if ($Existed) { Get-Sha256 $BackupTarget } else { $null })
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

    $Target = Get-SafePath $GamePath $Relative
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

    if ((Get-Sha256 $WowPath) -ne $OriginalHash) { throw "Wow.exe modificato durante l'installazione." }
    [byte[]]$WowBytes = $Candidate

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
    $Target = Get-SafePath $GamePath $Relative

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

