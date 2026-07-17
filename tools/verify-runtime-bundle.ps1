param(
    [string]$ProjectRoot,
    [switch]$Staged
)

$ErrorActionPreference = 'Stop'
if (-not $ProjectRoot) { $ProjectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path) }
$ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
. (Join-Path $ProjectRoot 'tools\runtime-build-common.ps1')

function Test-Cf7ManifestPath([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path) -or $Path.Contains('\') -or $Path.Contains(':')) { return $false }
    if ($Path.StartsWith('/') -or $Path.EndsWith('/') -or $Path.Contains('//')) { return $false }
    if ($Path -notmatch '^[A-Za-z0-9_.() -]+(?:/[A-Za-z0-9_.() -]+)*$') { return $false }
    foreach ($segment in $Path.Split('/')) { if ($segment -eq '.' -or $segment -eq '..') { return $false } }
    return $Path -eq 'CRAZYFLASHER7MercenaryEmpire.exe' -or $Path.StartsWith('runtime/', [StringComparison]::Ordinal)
}

function Get-Cf7DeploymentFiles([bool]$FromIndex) {
    if ($FromIndex) {
        $paths = @(& git -C $ProjectRoot ls-files -- 'CRAZYFLASHER7MercenaryEmpire.exe' 'runtime')
        if ($LASTEXITCODE -ne 0) { throw 'Cannot enumerate deployment files from Git index.' }
        return @($paths | ForEach-Object { $_.Replace('\', '/') } | Where-Object { $_ -ne 'runtime/cf7-runtime-manifest.tsv' })
    }

    $paths = @()
    $rootExe = Join-Path $ProjectRoot 'CRAZYFLASHER7MercenaryEmpire.exe'
    if (Test-Path -LiteralPath $rootExe -PathType Leaf) { $paths += 'CRAZYFLASHER7MercenaryEmpire.exe' }
    $runtimeDir = Join-Path $ProjectRoot 'runtime'
    if (Test-Path -LiteralPath $runtimeDir -PathType Container) {
        Get-ChildItem -LiteralPath $runtimeDir -Recurse -File | ForEach-Object {
            $relative = $_.FullName.Substring($ProjectRoot.Length + 1).Replace('\', '/')
            if ($relative -ne 'runtime/cf7-runtime-manifest.tsv') { $paths += $relative }
        }
    }
    return @($paths)
}

if ($Staged) {
    $manifestBytes = Get-Cf7GitBlobBytes -ProjectRoot $ProjectRoot -RelativePath 'runtime/cf7-runtime-manifest.tsv'
    $manifestText = [Text.Encoding]::UTF8.GetString($manifestBytes)
} else {
    $manifestPath = Join-Path $ProjectRoot 'runtime\cf7-runtime-manifest.tsv'
    $manifestText = [IO.File]::ReadAllText($manifestPath, [Text.Encoding]::UTF8)
}

$lines = @($manifestText -split "`r?`n" | Where-Object { $_ -ne '' })
if ($lines.Count -lt 5 -or $lines[0] -ne 'cf7-runtime-manifest-v1') { throw 'Runtime manifest schema/header is invalid.' }

$metadata = @{}
$fileRows = @()
$manifestPaths = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
foreach ($line in $lines | Select-Object -Skip 1) {
    $parts = @($line -split "`t")
    if ($parts.Count -eq 4 -and $parts[0] -eq 'file') {
        $path = $parts[1]
        if (-not (Test-Cf7ManifestPath $path)) { throw "Unsafe/unknown manifest path: $path" }
        if (-not $manifestPaths.Add($path)) { throw "Duplicate or case-colliding manifest path: $path" }
        $size = 0L
        if (-not [Int64]::TryParse($parts[2], [Globalization.NumberStyles]::None, [Globalization.CultureInfo]::InvariantCulture, [ref]$size) -or $size -lt 0) {
            throw "Invalid manifest size: $line"
        }
        if ($parts[3] -notmatch '^[0-9A-Fa-f]{64}$') { throw "Invalid manifest SHA256: $line" }
        $fileRows += [pscustomobject]@{ Path=$path; Size=$size; Hash=$parts[3].ToUpperInvariant() }
        continue
    }
    if ($parts.Count -ne 2 -or $parts[0] -notin @('publishMode','sourceTreeHash','toolchainLockHash','toolchainBaseline')) {
        throw "Unknown/malformed manifest row: $line"
    }
    if ($metadata.ContainsKey($parts[0])) { throw "Duplicate manifest metadata: $($parts[0])" }
    $metadata[$parts[0]] = $parts[1]
}

foreach ($required in @('publishMode','sourceTreeHash','toolchainLockHash','toolchainBaseline')) {
    if (-not $metadata.ContainsKey($required) -or [string]::IsNullOrWhiteSpace($metadata[$required])) { throw "Runtime manifest lacks metadata: $required" }
}
if ($metadata.publishMode -ne 'framework-dependent') { throw "Unsupported publishMode: $($metadata.publishMode)" }
if (-not $manifestPaths.Contains('CRAZYFLASHER7MercenaryEmpire.exe')) { throw 'Manifest does not own the root bootstrap executable.' }

$actualPaths = @(Get-Cf7DeploymentFiles -FromIndex $Staged.IsPresent)
$actualSet = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
foreach ($path in $actualPaths) {
    if (-not $actualSet.Add($path)) { throw "Duplicate/case-colliding deployment path: $path" }
}

$errors = @()
foreach ($path in $manifestPaths) { if (-not $actualSet.Contains($path)) { $errors += "manifest path missing from deployment closure: $path" } }
foreach ($path in $actualSet) { if (-not $manifestPaths.Contains($path)) { $errors += "undeclared deployment file: $path" } }

if ($errors.Count -gt 0) {
    foreach ($message in $errors) { Write-Host "[RuntimeBundle] MISMATCH $message" -ForegroundColor Red }
    Write-Host "[RuntimeBundle] FAIL mode=$(if ($Staged) {'staged'} else {'worktree'})" -ForegroundColor Red
    exit 2
}

foreach ($row in $fileRows) {
    try {
        if ($Staged) { $bytes = Get-Cf7GitBlobBytes -ProjectRoot $ProjectRoot -RelativePath $row.Path }
        else { $bytes = [IO.File]::ReadAllBytes((Join-Path $ProjectRoot ($row.Path -replace '/', '\'))) }
        $actualHash = Get-Cf7BytesSha256 -Bytes $bytes
        if ($bytes.LongLength -ne $row.Size) { $errors += "size $($row.Path) expected=$($row.Size) actual=$($bytes.LongLength)" }
        if ($actualHash -ne $row.Hash) { $errors += "sha256 $($row.Path) expected=$($row.Hash) actual=$actualHash" }
    } catch { $errors += "missing/read $($row.Path): $($_.Exception.Message)" }
}

$actualSource = Get-Cf7RuntimeSourceTreeHash -ProjectRoot $ProjectRoot -Mode $(if ($Staged) { 'Index' } else { 'Worktree' })
$actualToolchain = Get-Cf7ToolchainLockHash -ProjectRoot $ProjectRoot -Mode $(if ($Staged) { 'Index' } else { 'Worktree' })
if ($actualSource -ne $metadata.sourceTreeHash) { $errors += "sourceTreeHash expected=$($metadata.sourceTreeHash) actual=$actualSource" }
if ($actualToolchain -ne $metadata.toolchainLockHash) { $errors += "toolchainLockHash expected=$($metadata.toolchainLockHash) actual=$actualToolchain" }

if ($errors.Count -gt 0) {
    foreach ($message in $errors) { Write-Host "[RuntimeBundle] MISMATCH $message" -ForegroundColor Red }
    Write-Host "[RuntimeBundle] FAIL mode=$(if ($Staged) {'staged'} else {'worktree'})" -ForegroundColor Red
    exit 2
}
Write-Host "[RuntimeBundle] OK mode=$(if ($Staged) {'staged'} else {'worktree'}) files=$($fileRows.Count) sourceTreeHash=$actualSource toolchainLockHash=$actualToolchain" -ForegroundColor Green
