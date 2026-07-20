[CmdletBinding()]
param(
    [string]$ProjectRoot,
    [string]$BuilderId = $env:CF7_RUNTIME_BUILDER_ID,
    [string]$CandidateRoot,
    [string]$ReleaseTreeOid = 'HEAD',
    [string]$PolicyReceiptPath,
    [switch]$SkipPrepare,
    [switch]$SkipPolicy,
    [switch]$ForceReplace
)

$ErrorActionPreference = 'Stop'
$launcherDir = $PSScriptRoot
if (-not $ProjectRoot) { $ProjectRoot = Split-Path -Parent $launcherDir }
$ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path.TrimEnd('\')
$expectedLauncher = [IO.Path]::GetFullPath((Join-Path $ProjectRoot 'launcher')).TrimEnd('\')
if (-not $launcherDir.Equals($expectedLauncher, [StringComparison]::OrdinalIgnoreCase)) {
    throw "build.ps1 must run from the Launcher directory belonging to ProjectRoot: $ProjectRoot"
}

function Get-Cf7FileDigestState {
    param([Parameter(Mandatory=$true)][string]$Path)
    $fullPath = [IO.Path]::GetFullPath($Path)
    $exists = Test-Path -LiteralPath $fullPath -PathType Leaf
    [pscustomobject][ordered]@{
        path = $fullPath
        exists = $exists
        sha256 = if ($exists) { (Get-FileHash -LiteralPath $fullPath -Algorithm SHA256).Hash.ToUpperInvariant() } else { $null }
    }
}

function Get-Cf7FormalDeploymentSnapshot {
    param([Parameter(Mandatory=$true)][string]$Root)
    $paths = @()
    $bootstrapPath = Join-Path $Root 'CRAZYFLASHER7MercenaryEmpire.exe'
    if (Test-Path -LiteralPath $bootstrapPath -PathType Leaf) { $paths += Get-Item -LiteralPath $bootstrapPath -Force }
    $runtimePath = Join-Path $Root 'runtime'
    if (Test-Path -LiteralPath $runtimePath -PathType Container) {
        $runtimeItem = Get-Item -LiteralPath $runtimePath -Force
        if (($runtimeItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Formal runtime directory must not be a reparse point: $runtimePath"
        }
        $runtimeEntries = @(Get-ChildItem -LiteralPath $runtimePath -Recurse -Force)
        $runtimeReparse = @($runtimeEntries | Where-Object { ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 })
        if ($runtimeReparse.Count -gt 0) {
            throw "Formal runtime closure contains a reparse point: $($runtimeReparse[0].FullName)"
        }
        $paths += @($runtimeEntries | Where-Object { -not $_.PSIsContainer })
    }
    $consensusPath = Join-Path $Root 'config\build\runtime-release-consensus.json'
    if (Test-Path -LiteralPath $consensusPath -PathType Leaf) { $paths += Get-Item -LiteralPath $consensusPath -Force }

    $records = @($paths | ForEach-Object {
        if (($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Formal deployment file must not be a reparse point: $($_.FullName)"
        }
        [pscustomobject][ordered]@{
            path = $_.FullName.Substring($Root.Length + 1).Replace('\','/')
            sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToUpperInvariant()
        }
    } | Sort-Object path)
    $canonical = (($records | ForEach-Object { "$($_.path)`t$($_.sha256)" }) -join "`n") + "`n"
    $hasher = [Security.Cryptography.SHA256]::Create()
    try {
        $fingerprint = ([BitConverter]::ToString($hasher.ComputeHash([Text.Encoding]::UTF8.GetBytes($canonical)))).Replace('-','')
    } finally {
        $hasher.Dispose()
    }
    return [pscustomobject][ordered]@{
        fingerprintSha256 = $fingerprint
        files = $records
        fileCount = $records.Count
    }
}

function Test-Cf7SameFormalDeploymentSnapshot {
    param(
        [Parameter(Mandatory=$true)]$Before,
        [Parameter(Mandatory=$true)]$After
    )
    return $Before.fileCount -eq $After.fileCount -and
        [string]$Before.fingerprintSha256 -ceq [string]$After.fingerprintSha256
}

if ([string]::IsNullOrWhiteSpace($BuilderId)) { $BuilderId = 'local-unregistered' }
if ($BuilderId -notmatch '^[a-z0-9][a-z0-9._-]{1,127}$') {
    throw 'BuilderId must be 2-128 lowercase ASCII letters, digits, dot, underscore, or hyphen.'
}

$candidateBase = [IO.Path]::GetFullPath((Join-Path $ProjectRoot 'tmp\runtime-candidates\v2')).TrimEnd('\')
foreach ($candidatePathSegment in @(
    (Join-Path $ProjectRoot 'tmp'),
    (Join-Path $ProjectRoot 'tmp\runtime-candidates'),
    $candidateBase
)) {
    if (Test-Path -LiteralPath $candidatePathSegment) {
        $candidatePathItem = Get-Item -LiteralPath $candidatePathSegment -Force
        if (($candidatePathItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Candidate path must not traverse a reparse point: $candidatePathSegment"
        }
    }
}
if ($CandidateRoot) {
    if (-not [IO.Path]::IsPathRooted($CandidateRoot)) {
        throw 'CandidateRoot must be an absolute path.'
    }
    $CandidateRoot = [IO.Path]::GetFullPath($CandidateRoot).TrimEnd('\')
    if ($CandidateRoot.Equals($candidateBase, [StringComparison]::OrdinalIgnoreCase) -or
            -not $CandidateRoot.StartsWith($candidateBase + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw "CandidateRoot must remain below $candidateBase"
    }
}

$liveCorePath = Join-Path $ProjectRoot 'runtime\CRAZYFLASHER7MercenaryEmpire.Core.dll'
$formalDeploymentBefore = Get-Cf7FormalDeploymentSnapshot -Root $ProjectRoot

Write-Host '!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!' -ForegroundColor Yellow
Write-Host '  CANDIDATE BUILD ONLY - NOT DEPLOYED' -ForegroundColor Yellow
Write-Host '  FORMAL RUNTIME WILL NOT BE UPDATED; acceptance must explicitly start the candidate.' -ForegroundColor Yellow
Write-Host '!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!' -ForegroundColor Yellow

$resolvedTree = @(& git -C $ProjectRoot rev-parse --verify "$ReleaseTreeOid`^{tree}" 2>&1)
if ($LASTEXITCODE -ne 0 -or $resolvedTree.Count -ne 1 -or [string]$resolvedTree[0] -notmatch '^[0-9a-fA-F]{40,64}$') {
    throw "Cannot resolve release tree: $ReleaseTreeOid"
}
$resolvedTree = ([string]$resolvedTree[0]).Trim().ToLowerInvariant()

if (-not $SkipPrepare) {
    Write-Host '=== CF7 Runtime Release Prepare ===' -ForegroundColor Cyan
    & (Join-Path $ProjectRoot 'tools\prepare-launcher-release-assets.ps1') `
        -ProjectRoot $ProjectRoot `
        -ReleaseTreeOid $resolvedTree
    if ($LASTEXITCODE -ne 0) { throw 'Launcher release asset preparation failed.' }
}

if (-not $CandidateRoot) {
    . (Join-Path $ProjectRoot 'tools\runtime-build-v2-common.ps1')
    $identity = Get-Cf7RuntimeBuildIdentityV2 -ProjectRoot $ProjectRoot -Mode Worktree
    $candidateLeaf = New-Cf7RuntimeV2CandidateLeafName `
        -BuildIdentityHash ([string]$identity.buildIdentityHash) -BuilderId $BuilderId
    $CandidateRoot = Join-Path $ProjectRoot ("tmp\runtime-candidates\v2\{0}" -f $candidateLeaf)
}
$CandidateRoot = [IO.Path]::GetFullPath($CandidateRoot).TrimEnd('\')

Write-Host '=== CF7 Runtime Payload Producer ===' -ForegroundColor Cyan
$producerArguments = @{
    BuilderId = $BuilderId
    CandidateRoot = $CandidateRoot
}
if ($ForceReplace) { $producerArguments.ForceReplace = $true }
& (Join-Path $launcherDir 'build-runtime-candidate.ps1') @producerArguments
if ($LASTEXITCODE -ne 0) { throw 'Runtime candidate producer failed.' }

if (-not $SkipPolicy) {
    Write-Host '=== CF7 Runtime Release Policy ===' -ForegroundColor Cyan
    $policyArguments = @{
        ProjectRoot = $ProjectRoot
        ReleaseTreeOid = $resolvedTree
        IdentityMode = 'Worktree'
        CandidateRoot = $CandidateRoot
    }
    if ($PolicyReceiptPath) { $policyArguments.ReceiptPath = $PolicyReceiptPath }
    & (Join-Path $ProjectRoot 'tools\validate-launcher-release-policy.ps1') @policyArguments
    if ($LASTEXITCODE -ne 0) { throw 'Launcher release policy validation failed.' }
}

$metadataPath = Join-Path $CandidateRoot 'runtime-build-metadata.v2.json'
if (-not (Test-Path -LiteralPath $metadataPath -PathType Leaf)) {
    throw "Runtime candidate metadata missing: $metadataPath"
}
try {
    $candidateMetadata = Get-Content -LiteralPath $metadataPath -Raw -Encoding UTF8 | ConvertFrom-Json
} catch {
    throw "Runtime candidate metadata is invalid JSON: $metadataPath ($($_.Exception.Message))"
}
if ([string]$candidateMetadata.schema -cne 'cf7-runtime-candidate-metadata.v2' -or
        [string]$candidateMetadata.buildIdentityHash -notmatch '^[0-9A-Fa-f]{64}$' -or
        [string]$candidateMetadata.payloadClosureHash -notmatch '^[0-9A-Fa-f]{64}$') {
    throw "Runtime candidate metadata is incomplete or invalid: $metadataPath"
}

$candidateCorePath = Join-Path $CandidateRoot 'runtime\CRAZYFLASHER7MercenaryEmpire.Core.dll'
$candidateCore = Get-Cf7FileDigestState -Path $candidateCorePath
if (-not $candidateCore.exists) { throw "Runtime candidate Core DLL missing: $candidateCorePath" }
$liveCoreAfter = Get-Cf7FileDigestState -Path $liveCorePath
$formalDeploymentAfter = Get-Cf7FormalDeploymentSnapshot -Root $ProjectRoot
if (-not (Test-Cf7SameFormalDeploymentSnapshot -Before $formalDeploymentBefore -After $formalDeploymentAfter)) {
    throw "Candidate build changed the formal deployment closure. This command is producer-only and must never deploy. before=$($formalDeploymentBefore.fingerprintSha256) after=$($formalDeploymentAfter.fingerprintSha256)"
}
$candidateMatchesLive = if ($liveCoreAfter.exists) {
    [string]$candidateCore.sha256 -ceq [string]$liveCoreAfter.sha256
} else {
    $null
}

Write-Host '=== CF7 Runtime Candidate Ready - NOT DEPLOYED ===' -ForegroundColor Yellow
Write-Host "  Deployment status : NOT_DEPLOYED"
Write-Host "  Candidate root    : $CandidateRoot"
Write-Host "  Candidate Core    : $($candidateCore.path)"
Write-Host "  Candidate SHA256  : $($candidateCore.sha256)"
Write-Host "  Live Core         : $($liveCoreAfter.path)"
Write-Host "  Live SHA256       : $(if ($liveCoreAfter.exists) { $liveCoreAfter.sha256 } else { '<missing>' })"
Write-Host "  Formal closure    : $($formalDeploymentAfter.fingerprintSha256) ($($formalDeploymentAfter.fileCount) files)"
Write-Host "  Build identity    : $($candidateMetadata.buildIdentityHash)"
Write-Host "  Payload closure   : $($candidateMetadata.payloadClosureHash)"
Write-Host "  Tree              : $resolvedTree"
Write-Host '  FORMAL RUNTIME UNCHANGED; candidate ready must never be reported as deployed.' -ForegroundColor Yellow
[pscustomobject][ordered]@{
    schema = 'cf7-runtime-release-candidate.v2'
    deploymentStatus = 'NOT_DEPLOYED'
    runtimeMode = 'isolated_candidate'
    formalRuntimeModified = $false
    formalDeploymentModified = $false
    formalDeploymentFingerprintSha256 = [string]$formalDeploymentAfter.fingerprintSha256
    formalDeploymentFileCount = [int]$formalDeploymentAfter.fileCount
    candidateRoot = $CandidateRoot
    candidateCorePath = [string]$candidateCore.path
    candidateCoreSha256 = [string]$candidateCore.sha256
    liveCorePath = [string]$liveCoreAfter.path
    liveCoreExists = [bool]$liveCoreAfter.exists
    liveCoreSha256 = if ($liveCoreAfter.exists) { [string]$liveCoreAfter.sha256 } else { $null }
    candidateMatchesLive = $candidateMatchesLive
    buildIdentityHash = ([string]$candidateMetadata.buildIdentityHash).ToUpperInvariant()
    payloadClosureHash = ([string]$candidateMetadata.payloadClosureHash).ToUpperInvariant()
    releaseTreeOid = $resolvedTree
    policyValidated = -not $SkipPolicy.IsPresent
}
