# Shared, read-only preflight. String.Length is the Windows UTF-16 path budget.
function Assert-Cf7WebViewPath([string]$Path, [ValidateSet('Any','File','Directory')][string]$Kind = 'Any') {
    if ($Path -notmatch '^[A-Za-z]:[\\/]' -or $Path -match '[<>"|?*\x00-\x1f]' -or $Path.Substring(2).Contains(':')) {
        throw "Fixed WebView2 requires a plain local absolute path: $Path"
    }
    foreach ($segment in $Path.Substring(3).Split([char[]]'\/')) {
        if (-not $segment -or $segment -in @('.', '..') -or $segment -match '[. ]$' -or
            $segment -match '^(?i:CON|PRN|AUX|NUL|COM[1-9\u00b9\u00b2\u00b3]|LPT[1-9\u00b9\u00b2\u00b3])(?:\.|$)') {
            throw "Invalid Windows WebView2 path segment: $Path"
        }
    }
    $full = [IO.Path]::GetFullPath($Path)
    if ($full.Length -gt 240) {
        throw "Fixed WebView2 path exceeds 240 UTF-16 units (projected=$($full.Length)). Use -WebView2CacheDirectory (producer: -CacheDirectory) with a short local directory: $full"
    }
    $probe = $full
    while ($probe.Length -gt 3) {
        if (Test-Path -LiteralPath $probe) {
            $item = Get-Item -LiteralPath $probe -Force
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Fixed WebView2 cannot traverse a reparse point: $probe" }
            if ($probe -eq $full -and (($Kind -eq 'Directory' -and -not $item.PSIsContainer) -or
                ($Kind -eq 'File' -and $item.PSIsContainer))) { throw "WebView2 path must be a $Kind`: $full" }
            if ($probe -ne $full -and -not $item.PSIsContainer) { throw "WebView2 ancestor is a file: $probe" }
        }
        $probe = [IO.Path]::GetDirectoryName($probe)
    }
    if ((New-Object IO.DriveInfo ([IO.Path]::GetPathRoot($full))).DriveType -eq [IO.DriveType]::Network) { throw "WebView2 cache must be machine-local: $full" }
    return $full
}
function Resolve-Cf7WebViewLockedPath([string]$Root, [string]$Relative, [ValidateSet('File','Directory')][string]$Kind = 'File') {
    if (-not $Relative -or $Relative.Contains('\') -or [IO.Path]::IsPathRooted($Relative)) { throw "Invalid locked WebView2 relative path: $Relative" }
    return Assert-Cf7WebViewPath ($Root + '\' + $Relative.Replace('/', '\')) $Kind
}
function Add-Cf7WebViewPathNode($Nodes, [string]$Path, [string]$Kind) {
    $probe = $Path
    while ($probe.Length -gt 3) {
        if ($Nodes.ContainsKey($probe)) {
            $node = $Nodes[$probe]
            if ($node.kind -cne $Kind -or $node.path -cne $probe) {
                throw "Conflicting WebView2 file/directory or directory spelling: $probe"
            }
        } else { $Nodes.Add($probe, [pscustomobject]@{path=$probe; kind=$Kind}) }
        $probe = [IO.Path]::GetDirectoryName($probe)
        $Kind = 'Directory'
    }
}
function Get-Cf7WebViewLayout {
    param([string]$ProjectRoot, $Spec, [string]$CacheDirectory, [string]$DestinationDirectory, [string]$DeploymentRoot)
    if ([string]::IsNullOrWhiteSpace($CacheDirectory)) { $CacheDirectory = Join-Path $ProjectRoot 'tmp\w2' }
    if ($Spec.cabSha256 -cnotmatch '^[A-F0-9]{64}$') { throw 'Invalid WebView2 CAB hash.' }
    $cache = Assert-Cf7WebViewPath $CacheDirectory 'Directory'
    $cab = Assert-Cf7WebViewPath ($cache + '\' + $Spec.cabSha256 + '.cab') 'File'
    $download = Assert-Cf7WebViewPath ($cab + '.download-' + [guid]::NewGuid().ToString('N')) 'File'
    $extraction = Assert-Cf7WebViewPath ($cache + '\' + $Spec.cabSha256 + '-extracted') 'Directory'
    $engine = Resolve-Cf7WebViewLockedPath $extraction $Spec.extractedDirectory 'Directory'
    $nodes = New-Object 'Collections.Generic.Dictionary[string,object]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($directory in @($cache,$extraction,$engine)) { Add-Cf7WebViewPathNode $nodes $directory 'Directory' }
    foreach ($filePath in @($cab,$download)) { Add-Cf7WebViewPathNode $nodes $filePath 'File' }
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($file in @($Spec.files)) {
        $path = Resolve-Cf7WebViewLockedPath $engine $file.path
        Add-Cf7WebViewPathNode $nodes $path 'File'
        if (-not $seen.Add($path)) { throw "Duplicate locked WebView2 file: $($file.path)" }
    }
    $destination = $null
    if ($DestinationDirectory) {
        $destination = Assert-Cf7WebViewPath $DestinationDirectory 'Directory'
        Add-Cf7WebViewPathNode $nodes $destination 'Directory'
        if ($destination.StartsWith($cache + '\', [StringComparison]::OrdinalIgnoreCase) -or
            $cache.StartsWith($destination + '\', [StringComparison]::OrdinalIgnoreCase) -or $cache -ieq $destination) { throw 'WebView2 cache and destination must not overlap.' }
        $seen.Clear()
        foreach ($part in @($Spec.parts)) {
            $path = Resolve-Cf7WebViewLockedPath $destination $part.path
            Add-Cf7WebViewPathNode $nodes $path 'File'
            if (-not $seen.Add($path)) { throw "Duplicate WebView2 chunk: $($part.path)" }
        }
    }
    if ($DeploymentRoot) {
        $deployment = Assert-Cf7WebViewPath $DeploymentRoot 'Directory'
        if ($cache -ieq $deployment -or $cache.StartsWith($deployment + '\', [StringComparison]::OrdinalIgnoreCase) -or
            $deployment.StartsWith($cache + '\', [StringComparison]::OrdinalIgnoreCase)) {
            throw 'WebView2 cache and entire candidate deployment must not overlap before replacement.'
        }
    }
    return [pscustomobject]@{ cache=$cache; cab=$cab; download=$download; extraction=$extraction; engine=$engine; destination=$destination }
}
# Inspect CFFILE names before expand writes anything. The CAB digest is checked first.
function Assert-Cf7WebViewCabInventory([string]$Cab, $Spec) {
    $reader = New-Object IO.BinaryReader ([IO.File]::OpenRead($Cab))
    try {
        if ($reader.ReadUInt32() -ne 0x4643534d) { throw 'Invalid WebView2 CAB signature.' }
        $reader.BaseStream.Position = 16
        $filesOffset = $reader.ReadUInt32()
        $reader.BaseStream.Position = 28
        $count = $reader.ReadUInt16()
        if ($count -ne @($Spec.files).Count) { throw 'WebView2 CAB file count differs from lock.' }
        $expected = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
        foreach ($file in $Spec.files) { [void]$expected.Add($Spec.extractedDirectory + '/' + $file.path) }
        $reader.BaseStream.Position = $filesOffset
        for ($i=0; $i -lt $count; $i++) {
            $reader.BaseStream.Position += 14
            $attributes = $reader.ReadUInt16()
            $bytes = New-Object 'System.Collections.Generic.List[byte]'
            do {
                $b = $reader.ReadByte()
                if ($bytes.Count -gt 4096) { throw 'WebView2 CAB file name is too long.' }
                if ($b -ne 0) { $bytes.Add($b) }
            } while ($b -ne 0)
            $encoding = if (($attributes -band 0x80) -ne 0) { New-Object Text.UTF8Encoding($false, $true) } else { [Text.Encoding]::ASCII }
            $name = $encoding.GetString($bytes.ToArray()).Replace('\','/')
            if (-not $expected.Remove($name)) { throw "WebView2 CAB inventory differs from lock: $name" }
        }
        if ($expected.Count -ne 0) { throw 'WebView2 CAB inventory is incomplete.' }
    } finally { $reader.Dispose() }
}
