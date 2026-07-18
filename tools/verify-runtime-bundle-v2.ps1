param(
    [string]$ProjectRoot,
    [string]$DeploymentRoot,
    [switch]$Staged,
    [switch]$IntegrityOnly,
    [switch]$Json
)

$ErrorActionPreference = 'Stop'
if (-not $ProjectRoot) { $ProjectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path) }
$ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path.TrimEnd('\')
if (-not $DeploymentRoot) { $DeploymentRoot = $ProjectRoot }
$DeploymentRoot = (Resolve-Path -LiteralPath $DeploymentRoot).Path.TrimEnd('\')
if ($Staged -and $DeploymentRoot -ne $ProjectRoot) { throw '-Staged cannot use a separate DeploymentRoot.' }

. (Join-Path $ProjectRoot 'tools\runtime-build-common.ps1')
. (Join-Path $ProjectRoot 'tools\runtime-build-v2-common.ps1')

function Test-Cf7V2ManifestPath([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path) -or $Path.Contains('\') -or $Path.Contains(':')) { return $false }
    if ($Path.StartsWith('/') -or $Path.EndsWith('/') -or $Path.Contains('//')) { return $false }
    if ($Path -notmatch '^[A-Za-z0-9_.() -]+(?:/[A-Za-z0-9_.() -]+)*$') { return $false }
    foreach ($segment in $Path.Split('/')) { if ($segment -eq '.' -or $segment -eq '..') { return $false } }
    return $Path -eq 'CRAZYFLASHER7MercenaryEmpire.exe' -or $Path.StartsWith('runtime/', [StringComparison]::Ordinal)
}

function Get-Cf7V2DeploymentPaths {
    if ($Staged) {
        $paths = @(& git -C $ProjectRoot ls-files -- 'CRAZYFLASHER7MercenaryEmpire.exe' 'runtime')
        if ($LASTEXITCODE -ne 0) { throw 'Cannot enumerate staged runtime deployment.' }
        return @($paths | ForEach-Object { $_.Replace('\','/') } |
            Where-Object { $_ -ne 'runtime/cf7-runtime-manifest.tsv' } | Sort-Object -Unique)
    }
    $paths = @()
    $rootExe = Join-Path $DeploymentRoot 'CRAZYFLASHER7MercenaryEmpire.exe'
    if (Test-Path -LiteralPath $rootExe -PathType Leaf) { $paths += 'CRAZYFLASHER7MercenaryEmpire.exe' }
    $runtimeDir = Join-Path $DeploymentRoot 'runtime'
    if (Test-Path -LiteralPath $runtimeDir -PathType Container) {
        Get-ChildItem -LiteralPath $runtimeDir -Recurse -File | ForEach-Object {
            $relative = $_.FullName.Substring($DeploymentRoot.Length + 1).Replace('\','/')
            if ($relative -ne 'runtime/cf7-runtime-manifest.tsv') { $paths += $relative }
        }
    }
    return @($paths | Sort-Object -Unique)
}

function Get-Cf7V2PathBytes([string]$RelativePath) {
    if ($Staged) { return Get-Cf7GitBlobBytes -ProjectRoot $ProjectRoot -RelativePath $RelativePath }
    return [IO.File]::ReadAllBytes((Join-Path $DeploymentRoot ($RelativePath -replace '/','\')))
}

if ($Staged) {
    $manifestBytes = Get-Cf7GitBlobBytes -ProjectRoot $ProjectRoot -RelativePath 'runtime/cf7-runtime-manifest.tsv'
    $manifestText = [Text.Encoding]::UTF8.GetString($manifestBytes)
} else {
    $manifestPath = Join-Path $DeploymentRoot 'runtime\cf7-runtime-manifest.tsv'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw "Runtime manifest missing: $manifestPath" }
    $manifestText = [IO.File]::ReadAllText($manifestPath, [Text.Encoding]::UTF8)
}

$lines = @($manifestText -split "`r?`n" | Where-Object { $_ -ne '' })
if ($lines.Count -lt 9 -or $lines[0] -ne 'cf7-runtime-manifest-v2') {
    throw 'Runtime manifest is not cf7-runtime-manifest-v2.'
}

$allowedMetadata = @(
    'publishMode','artifactSourceHash','producerRecipeHash','toolchainLockHash',
    'toolchainBaseline','buildIdentityHash','payloadClosureHash'
)
$metadata = @{}
$fileRows = @()
$manifestPaths = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
foreach ($line in $lines | Select-Object -Skip 1) {
    $parts = @($line -split "`t")
    if ($parts.Count -eq 4 -and $parts[0] -eq 'file') {
        $path = $parts[1]
        if (-not (Test-Cf7V2ManifestPath $path)) { throw "Unsafe runtime manifest path: $path" }
        if (-not $manifestPaths.Add($path)) { throw "Duplicate/case-colliding runtime path: $path" }
        $size = 0L
        if (-not [Int64]::TryParse($parts[2], [Globalization.NumberStyles]::None,
                [Globalization.CultureInfo]::InvariantCulture, [ref]$size) -or $size -lt 0) {
            throw "Invalid runtime manifest size: $line"
        }
        if ($parts[3] -notmatch '^[0-9A-Fa-f]{64}$') { throw "Invalid runtime manifest SHA256: $line" }
        $fileRows += [pscustomobject]@{ path=$path; size=$size; sha256=$parts[3].ToUpperInvariant() }
        continue
    }
    if ($parts.Count -ne 2 -or $parts[0] -notin $allowedMetadata) { throw "Unknown runtime manifest row: $line" }
    if ($metadata.ContainsKey($parts[0])) { throw "Duplicate runtime manifest metadata: $($parts[0])" }
    $metadata[$parts[0]] = $parts[1]
}

foreach ($required in $allowedMetadata) {
    if (-not $metadata.ContainsKey($required) -or [string]::IsNullOrWhiteSpace($metadata[$required])) {
        throw "Runtime manifest lacks metadata: $required"
    }
}
foreach ($hashField in @('artifactSourceHash','producerRecipeHash','toolchainLockHash','buildIdentityHash','payloadClosureHash')) {
    if ([string]$metadata[$hashField] -notmatch '^[0-9A-Fa-f]{64}$') { throw "Invalid runtime manifest hash: $hashField" }
    $metadata[$hashField] = ([string]$metadata[$hashField]).ToUpperInvariant()
}
if ($metadata.publishMode -ne 'framework-dependent') { throw "Unsupported publishMode: $($metadata.publishMode)" }
if (-not $manifestPaths.Contains('CRAZYFLASHER7MercenaryEmpire.exe')) { throw 'Manifest does not own the root bootstrap.' }

$errors = @()
$actualPaths = @(Get-Cf7V2DeploymentPaths)
$actualSet = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
foreach ($path in $actualPaths) {
    if (-not $actualSet.Add($path)) { throw "Duplicate/case-colliding deployed path: $path" }
}
foreach ($path in $manifestPaths) { if (-not $actualSet.Contains($path)) { $errors += "manifest path missing: $path" } }
foreach ($path in $actualSet) { if (-not $manifestPaths.Contains($path)) { $errors += "undeclared deployment file: $path" } }

foreach ($row in $fileRows) {
    try {
        $bytes = Get-Cf7V2PathBytes $row.path
        $actualHash = Get-Cf7BytesSha256 -Bytes $bytes
        if ($bytes.LongLength -ne $row.size) { $errors += "size $($row.path) expected=$($row.size) actual=$($bytes.LongLength)" }
        if ($actualHash -ne $row.sha256) { $errors += "sha256 $($row.path) expected=$($row.sha256) actual=$actualHash" }
    } catch {
        $errors += "missing/read $($row.path): $($_.Exception.Message)"
    }
}

$actualPayloadClosureHash = Get-Cf7RuntimeV2CanonicalClosureHash -Files $fileRows
if ($actualPayloadClosureHash -ne $metadata.payloadClosureHash) {
    $errors += "payloadClosureHash expected=$($metadata.payloadClosureHash) actual=$actualPayloadClosureHash"
}

$manifestBuildIdentity = Get-Cf7RuntimeV2BuildIdentityHash `
    -ArtifactSourceHash $metadata.artifactSourceHash `
    -ProducerRecipeHash $metadata.producerRecipeHash `
    -ToolchainLockHash $metadata.toolchainLockHash
if ($manifestBuildIdentity -ne $metadata.buildIdentityHash) {
    $errors += "buildIdentityHash expected=$($metadata.buildIdentityHash) actual=$manifestBuildIdentity"
}

$mode = if ($Staged) { 'Index' } else { 'Worktree' }
$state = 'integrity-only'
if (-not $IntegrityOnly) {
    $actualArtifactSourceHash = Get-Cf7RuntimeArtifactSourceHash -ProjectRoot $ProjectRoot -Mode $mode
    $actualProducerRecipeHash = Get-Cf7RuntimeProducerRecipeHash -ProjectRoot $ProjectRoot -Mode $mode
    $actualToolchainLockHash = Get-Cf7RuntimeToolchainLockHashV2 -ProjectRoot $ProjectRoot -Mode $mode
    $actualBuildIdentity = Get-Cf7RuntimeV2BuildIdentityHash `
        -ArtifactSourceHash $actualArtifactSourceHash `
        -ProducerRecipeHash $actualProducerRecipeHash `
        -ToolchainLockHash $actualToolchainLockHash
    if ($actualArtifactSourceHash -ne $metadata.artifactSourceHash) { $errors += "artifactSourceHash expected=$($metadata.artifactSourceHash) actual=$actualArtifactSourceHash" }
    if ($actualProducerRecipeHash -ne $metadata.producerRecipeHash) { $errors += "producerRecipeHash expected=$($metadata.producerRecipeHash) actual=$actualProducerRecipeHash" }
    if ($actualToolchainLockHash -ne $metadata.toolchainLockHash) { $errors += "toolchainLockHash expected=$($metadata.toolchainLockHash) actual=$actualToolchainLockHash" }
    if ($actualBuildIdentity -ne $metadata.buildIdentityHash) { $errors += "current buildIdentityHash expected=$($metadata.buildIdentityHash) actual=$actualBuildIdentity" }
    $state = 'coherent'
}

$result = [ordered]@{
    schema = 'cf7-runtime-bundle-verification.v2'
    passed = $errors.Count -eq 0
    state = if ($errors.Count -eq 0) { $state } else { 'invalid' }
    mode = if ($Staged) { 'staged' } else { 'worktree' }
    buildIdentityHash = $metadata.buildIdentityHash
    payloadClosureHash = $actualPayloadClosureHash
    files = $fileRows.Count
    errors = @($errors)
}
if ($Json) { $result | ConvertTo-Json -Depth 5 }
if ($errors.Count -gt 0) {
    foreach ($message in $errors) { Write-Host "[RuntimeBundleV2] MISMATCH $message" -ForegroundColor Red }
    Write-Host "[RuntimeBundleV2] FAIL state=invalid mode=$($result.mode)" -ForegroundColor Red
    exit 2
}
Write-Host "[RuntimeBundleV2] OK state=$state mode=$($result.mode) files=$($fileRows.Count) payload=$actualPayloadClosureHash" -ForegroundColor Green
