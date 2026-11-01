# Shared by install/uninstall; Windows PowerShell 5.1 compatible.
function Get-CompatibleBytes {
    param([byte[]]$Data, $Manifest, [bool]$Reverse = $false)
    $ErrorText = 'Wow.exe incompatibile: richiesti PE x86 3.3.5a (12340) e istruzioni della mod intatte.'
    if ($Data.Length -lt 64 -or $Data[0] -ne 77 -or $Data[1] -ne 90) { throw $ErrorText }
    $Pe = [BitConverter]::ToUInt32($Data, 60)
    if ($Pe + 26 -gt $Data.Length) { throw $ErrorText }
    if ([BitConverter]::ToUInt32($Data, $Pe) -ne 0x4550 -or
        [BitConverter]::ToUInt16($Data, $Pe+4) -ne 0x14c -or
        [BitConverter]::ToUInt16($Data, $Pe+24) -ne 0x10b) { throw $ErrorText }
    $Count = [BitConverter]::ToUInt16($Data, $Pe+6)
    $Opt = [BitConverter]::ToUInt16($Data, $Pe+20)
    $Sections = @()
    $VersionOk = $false
    for ($i = 0; $i -lt $Count; $i++) {
        $H = $Pe+24+$Opt+$i*40
        if ($H+40 -gt $Data.Length) { throw $ErrorText }
        [int64]$Size = [BitConverter]::ToUInt32($Data, $H+16)
        [int64]$Start = [BitConverter]::ToUInt32($Data, $H+20)
        $Flags = [BitConverter]::ToUInt32($Data, $H+36)
        if ($Start+$Size -gt $Data.Length) { throw $ErrorText }
        $Sections += @{ Start=$Start; End=$Start+$Size; Flags=$Flags }
        $Name = [Text.Encoding]::ASCII.GetString($Data, $H, 8).TrimEnd([char]0)
        if ($Name -eq '.rsrc') {
            for ($j = $Start; $j+16 -le $Start+$Size; $j++) {
                if ($Data[$j] -eq 0xbd -and
                    [BitConverter]::ToUInt32($Data, $j) -eq 4277077181 -and
                    [BitConverter]::ToUInt32($Data, $j+4) -eq 65536 -and
                    [BitConverter]::ToUInt32($Data, $j+8) -eq 196611 -and
                    [BitConverter]::ToUInt32($Data, $j+12) -eq 340020) { $VersionOk = $true; break }
            }
        }
    }
    if (-not $VersionOk) { throw $ErrorText }
    [byte[]]$Out = $Data.Clone()
    $Used = @{}
    foreach ($Patch in $Manifest.patches) {
        [int64]$Offset = $Patch.offset
        [byte[]]$Old = Convert-HexToBytes $Patch.old_hex
        [byte[]]$New = Convert-HexToBytes $Patch.new_hex
        [byte[]]$Before = Convert-HexToBytes $Patch.context_before_hex
        [byte[]]$After = Convert-HexToBytes $Patch.context_after_hex
        $N = $Old.Length
        if ($N -eq 0 -or $New.Length -ne $N -or $Before.Length -eq 0 -or $After.Length -eq 0 -or
            $Offset -lt $Before.Length -or $Offset+$N+$After.Length -gt $Data.Length) { throw $ErrorText }
        $InCode = $false
        foreach ($Section in $Sections) {
            if ($Section.Start -le $Offset-$Before.Length -and $Offset+$N+$After.Length -le $Section.End -and
                ($Section.Flags -band 0x20000000)) { $InCode = $true }
        }
        if (-not $InCode) { throw $ErrorText }
        for ($i=0; $i -lt $Before.Length; $i++) {
            if ($Data[$Offset-$Before.Length+$i] -ne $Before[$i]) { throw $ErrorText }
        }
        for ($i=0; $i -lt $After.Length; $i++) {
            if ($Data[$Offset+$N+$i] -ne $After[$i]) { throw $ErrorText }
        }
        $IsOld = $true; $IsNew = $true
        for ($i=0; $i -lt $N; $i++) {
            if ($Used.ContainsKey($Offset+$i)) { throw $ErrorText }
            $Used[$Offset+$i] = $true
            if ($Data[$Offset+$i] -ne $Old[$i]) { $IsOld = $false }
            if ($Data[$Offset+$i] -ne $New[$i]) { $IsNew = $false }
        }
        if (-not ($IsOld -or $IsNew)) { throw $ErrorText }
        $Replacement = if ($Reverse) { $Old } else { $New }
        [Array]::Copy($Replacement, 0, $Out, $Offset, $N)
    }
    if ($Used.Count -eq 0) { throw $ErrorText }
    return ,$Out
}

function Get-BytesHash {
    param([byte[]]$Data)
    $Hasher = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($Hasher.ComputeHash($Data))).Replace('-', '').ToLowerInvariant() }
    finally { $Hasher.Dispose() }
}

function Assert-PayloadBaseline {
    param($Baseline, [string]$Game, [string]$Payload, [string]$Files)
    if ($Baseline.format -ne 1 -or $Baseline.package_version -ne '1.0.0') { throw 'Baseline incompatibile.' }
    $Expected = @{}
    foreach ($File in @(Get-ChildItem -LiteralPath $Payload -File -Recurse)) {
        $Rel = $File.FullName.Substring($Payload.Length).TrimStart('\').Replace('/', '\')
        $Expected[$Rel] = $true
    }
    $Seen = @{}
    foreach ($Entry in $Baseline.files) {
        $Rel = ([string]$Entry.relative_path).Replace('/', '\')
        $null = Get-SafePath $Game $Rel
        if ($Seen.ContainsKey($Rel) -or -not $Expected.ContainsKey($Rel) -or
            $Entry.existed_before_install -isnot [bool]) { throw 'Baseline non corrispondente al payload.' }
        $Seen[$Rel] = $true
        if ($Entry.existed_before_install) {
            $Backup = Get-SafePath $Files $Rel
            if (-not (Test-Path -LiteralPath $Backup -PathType Leaf)) { throw "Backup mancante: $Rel" }
            if ($Entry.PSObject.Properties.Name -contains 'sha256') {
                if ($Entry.sha256 -and (Get-Sha256 $Backup) -ne $Entry.sha256) { throw "Backup corrotto: $Rel" }
            }
        }
    }
    if ($Seen.Count -ne $Expected.Count) { throw 'Baseline incompleta.' }
}
