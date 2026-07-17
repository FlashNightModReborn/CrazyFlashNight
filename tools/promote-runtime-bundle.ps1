param(
    [string]$ProjectRoot,
    [Parameter(Mandatory=$true)][string]$CandidateRoot,
    [Parameter(Mandatory=$true)][string[]]$PeerAttestationPath
)

$ErrorActionPreference = 'Stop'
if (-not $ProjectRoot) { $ProjectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path) }
$ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path.TrimEnd('\')
$CandidateRoot = (Resolve-Path -LiteralPath $CandidateRoot).Path.TrimEnd('\')
if ($CandidateRoot -eq $ProjectRoot) { throw 'CandidateRoot cannot be the live project deployment root.' }
. (Join-Path $ProjectRoot 'tools\runtime-build-common.ps1')

$verifyScript = Join-Path $ProjectRoot 'tools\verify-runtime-bundle.ps1'
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $verifyScript -ProjectRoot $ProjectRoot -DeploymentRoot $CandidateRoot
if ($LASTEXITCODE -ne 0) { throw 'Candidate runtime bundle verification failed.' }

$localAttestationPath = Join-Path $CandidateRoot 'runtime-build-attestation.json'
if (-not (Test-Path -LiteralPath $localAttestationPath -PathType Leaf)) { throw 'Candidate lacks runtime-build-attestation.json.' }
$attestationPaths = @($localAttestationPath) + @($PeerAttestationPath)
$attestations = @()
foreach ($path in $attestationPaths) {
    $resolved = (Resolve-Path -LiteralPath $path).Path
    $attestations += Get-Content -LiteralPath $resolved -Raw -Encoding UTF8 | ConvertFrom-Json
}
$consensus = Test-Cf7RuntimeBuildAttestationConsensus -Attestations $attestations

$actualSource = Get-Cf7RuntimeSourceTreeHash -ProjectRoot $ProjectRoot -Mode Worktree
$actualToolchain = Get-Cf7ToolchainLockHash -ProjectRoot $ProjectRoot -Mode Worktree
$actualRecipe = Get-Cf7RuntimeBuildRecipeHash -ProjectRoot $ProjectRoot -Mode Worktree
$actualClosure = Get-Cf7RuntimeArtifactClosure -DeploymentRoot $CandidateRoot
if ($consensus.sourceTreeHash -ne $actualSource) { throw 'Candidate consensus sourceTreeHash does not match the current worktree.' }
if ($consensus.toolchainLockHash -ne $actualToolchain) { throw 'Candidate consensus toolchainLockHash does not match the current lock.' }
if ($consensus.buildRecipeHash -ne $actualRecipe) { throw 'Candidate consensus buildRecipeHash does not match the current recipe.' }
if ($consensus.artifactClosureHash -ne $actualClosure.artifactClosureHash) { throw 'Candidate bytes do not match the attested artifact closure.' }

$deploymentChanges = @(& git -C $ProjectRoot status --porcelain -- 'CRAZYFLASHER7MercenaryEmpire.exe' 'runtime' 'config/build/runtime-release-consensus.json')
if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect the current runtime deployment state.' }
if ($deploymentChanges.Count -gt 0) {
    throw "Live runtime deployment is dirty; promotion refused:`n$($deploymentChanges -join "`n")"
}

$transactionBase = [IO.Path]::GetFullPath((Join-Path $ProjectRoot 'tmp\runtime-promotions')).TrimEnd('\')
if (-not (Test-Path -LiteralPath $transactionBase -PathType Container)) {
    New-Item -ItemType Directory -Path $transactionBase -Force | Out-Null
}
$transactionRoot = Join-Path $transactionBase ([DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ') + '-' + [Guid]::NewGuid().ToString('N'))
$stageRoot = Join-Path $transactionRoot 'next'
$backupRoot = Join-Path $transactionRoot 'previous'
New-Item -ItemType Directory -Path $stageRoot,$backupRoot -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $CandidateRoot 'runtime') -Destination $stageRoot -Recurse
Copy-Item -LiteralPath (Join-Path $CandidateRoot 'CRAZYFLASHER7MercenaryEmpire.exe') -Destination (Join-Path $stageRoot 'CRAZYFLASHER7MercenaryEmpire.exe')

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $verifyScript -ProjectRoot $ProjectRoot -DeploymentRoot $stageRoot
if ($LASTEXITCODE -ne 0) { throw 'Staged promotion copy failed bundle verification.' }

$liveRuntime = Join-Path $ProjectRoot 'runtime'
$liveBootstrap = Join-Path $ProjectRoot 'CRAZYFLASHER7MercenaryEmpire.exe'
$backupRuntime = Join-Path $backupRoot 'runtime'
$backupBootstrap = Join-Path $backupRoot 'CRAZYFLASHER7MercenaryEmpire.exe'
$consensusRecordPath = Join-Path $ProjectRoot 'config\build\runtime-release-consensus.json'
$backupConsensusRecord = Join-Path $backupRoot 'runtime-release-consensus.json'
$nextConsensusRecord = Join-Path $stageRoot 'runtime-release-consensus.json'
$releaseRecord = [pscustomobject]@{
    schema = 'cf7-runtime-release-consensus.v1'
    sourceTreeHash = [string]$consensus.sourceTreeHash
    toolchainLockHash = [string]$consensus.toolchainLockHash
    buildRecipeHash = [string]$consensus.buildRecipeHash
    artifactClosureHash = [string]$consensus.artifactClosureHash
    builders = @($attestations | ForEach-Object { [string]$_.builderId } | Sort-Object)
    promotedAtUtc = [DateTime]::UtcNow.ToString('o')
}
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText($nextConsensusRecord, ($releaseRecord | ConvertTo-Json -Depth 5) + "`n", $utf8NoBom)
$installedRuntime = $false
$installedBootstrap = $false
$installedConsensusRecord = $false
$hadConsensusRecord = Test-Path -LiteralPath $consensusRecordPath -PathType Leaf
try {
    Move-Item -LiteralPath $liveRuntime -Destination $backupRuntime
    Move-Item -LiteralPath $liveBootstrap -Destination $backupBootstrap
    if ($hadConsensusRecord) { Move-Item -LiteralPath $consensusRecordPath -Destination $backupConsensusRecord }
    Move-Item -LiteralPath (Join-Path $stageRoot 'runtime') -Destination $liveRuntime
    $installedRuntime = $true
    Move-Item -LiteralPath (Join-Path $stageRoot 'CRAZYFLASHER7MercenaryEmpire.exe') -Destination $liveBootstrap
    $installedBootstrap = $true
    Move-Item -LiteralPath $nextConsensusRecord -Destination $consensusRecordPath
    $installedConsensusRecord = $true

    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $verifyScript -ProjectRoot $ProjectRoot
    if ($LASTEXITCODE -ne 0) { throw 'Promoted runtime bundle failed final verification.' }
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ProjectRoot 'tools\verify-runtime-consensus.ps1') -ProjectRoot $ProjectRoot
    if ($LASTEXITCODE -ne 0) { throw 'Promoted runtime consensus record failed final verification.' }
    & $liveBootstrap --verify-only
    if ($LASTEXITCODE -ne 0) { throw 'Promoted bootstrap rejected the runtime bundle.' }
} catch {
    $failure = $_
    if ($installedConsensusRecord -and (Test-Path -LiteralPath $consensusRecordPath)) { Remove-Item -LiteralPath $consensusRecordPath -Force }
    if ($installedBootstrap -and (Test-Path -LiteralPath $liveBootstrap)) { Remove-Item -LiteralPath $liveBootstrap -Force }
    if ($installedRuntime -and (Test-Path -LiteralPath $liveRuntime)) { Remove-Item -LiteralPath $liveRuntime -Recurse -Force }
    if (Test-Path -LiteralPath $backupBootstrap) { Move-Item -LiteralPath $backupBootstrap -Destination $liveBootstrap }
    if (Test-Path -LiteralPath $backupRuntime) { Move-Item -LiteralPath $backupRuntime -Destination $liveRuntime }
    if ($hadConsensusRecord -and (Test-Path -LiteralPath $backupConsensusRecord)) { Move-Item -LiteralPath $backupConsensusRecord -Destination $consensusRecordPath }
    throw "Runtime promotion rolled back: $($failure.Exception.Message)"
}

Write-Host "[RuntimePromotion] OK builders=$(@($attestations | ForEach-Object { $_.builderId }) -join ',') closure=$($consensus.artifactClosureHash)" -ForegroundColor Green
Write-Host "[RuntimePromotion] Recoverable previous bundle: $backupRoot" -ForegroundColor DarkGray
