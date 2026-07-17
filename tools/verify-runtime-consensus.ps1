param(
    [string]$ProjectRoot,
    [string]$DeploymentRoot,
    [string]$RecordPath,
    [switch]$Staged
)

$ErrorActionPreference = 'Stop'
if (-not $ProjectRoot) { $ProjectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path) }
$ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
$DeploymentRoot = if ($DeploymentRoot) { (Resolve-Path -LiteralPath $DeploymentRoot).Path } else { $ProjectRoot }
if ($Staged -and ($DeploymentRoot -ne $ProjectRoot -or $RecordPath)) { throw '-Staged uses the indexed project deployment and canonical record path.' }
. (Join-Path $ProjectRoot 'tools\runtime-build-common.ps1')

$relativeRecord = 'config/build/runtime-release-consensus.json'
if ($Staged) {
    $record = [Text.Encoding]::UTF8.GetString((Get-Cf7GitBlobBytes -ProjectRoot $ProjectRoot -RelativePath $relativeRecord)) | ConvertFrom-Json
    $mode = 'Index'
} else {
    if (-not $RecordPath) { $RecordPath = Join-Path $ProjectRoot ($relativeRecord -replace '/', '\') }
    $record = Get-Content -LiteralPath $RecordPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $mode = 'Worktree'
}

if ($record.schema -ne 'cf7-runtime-release-consensus.v1') { throw 'Unsupported runtime release consensus schema.' }
$builders = @($record.builders)
if ($builders.Count -lt 2) { throw 'Runtime release consensus requires at least two builders.' }
$builderSet = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
foreach ($builder in $builders) {
    if ([string]$builder -notmatch '^[a-z0-9][a-z0-9._-]{1,63}$') { throw "Invalid consensus builderId: $builder" }
    if (-not $builderSet.Add([string]$builder)) { throw "Duplicate consensus builderId: $builder" }
}
foreach ($field in @('sourceTreeHash','toolchainLockHash','buildRecipeHash','artifactClosureHash')) {
    if ([string]$record.$field -notmatch '^[0-9A-Fa-f]{64}$') { throw "Invalid release consensus field: $field" }
}

$actualSource = Get-Cf7RuntimeSourceTreeHash -ProjectRoot $ProjectRoot -Mode $mode
$actualToolchain = Get-Cf7ToolchainLockHash -ProjectRoot $ProjectRoot -Mode $mode
$actualRecipe = Get-Cf7RuntimeBuildRecipeHash -ProjectRoot $ProjectRoot -Mode $mode
$actualClosure = Get-Cf7RuntimeArtifactClosure -DeploymentRoot $DeploymentRoot -ProjectRoot $ProjectRoot -Mode $mode
$errors = @()
if ($record.sourceTreeHash -ne $actualSource) { $errors += "sourceTreeHash expected=$($record.sourceTreeHash) actual=$actualSource" }
if ($record.toolchainLockHash -ne $actualToolchain) { $errors += "toolchainLockHash expected=$($record.toolchainLockHash) actual=$actualToolchain" }
if ($record.buildRecipeHash -ne $actualRecipe) { $errors += "buildRecipeHash expected=$($record.buildRecipeHash) actual=$actualRecipe" }
if ($record.artifactClosureHash -ne $actualClosure.artifactClosureHash) { $errors += "artifactClosureHash expected=$($record.artifactClosureHash) actual=$($actualClosure.artifactClosureHash)" }
if ($errors.Count -gt 0) {
    foreach ($message in $errors) { Write-Host "[RuntimeConsensus] MISMATCH $message" -ForegroundColor Red }
    exit 2
}
Write-Host "[RuntimeConsensus] OK mode=$mode builders=$($builders -join ',') closure=$($actualClosure.artifactClosureHash)" -ForegroundColor Green
