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
if ([string]::IsNullOrWhiteSpace($BuilderId)) { $BuilderId = 'local-unregistered' }
if ($BuilderId -notmatch '^[a-z0-9][a-z0-9._-]{1,127}$') {
    throw 'BuilderId must be 2-128 lowercase ASCII letters, digits, dot, underscore, or hyphen.'
}

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

Write-Host '=== CF7 Runtime Release Candidate Ready ===' -ForegroundColor Green
Write-Host "  Candidate : $CandidateRoot"
Write-Host "  Tree      : $resolvedTree"
[pscustomobject][ordered]@{
    schema = 'cf7-runtime-release-candidate.v2'
    candidateRoot = $CandidateRoot
    releaseTreeOid = $resolvedTree
    policyValidated = -not $SkipPolicy.IsPresent
}
