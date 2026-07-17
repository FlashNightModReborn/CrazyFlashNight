param([string]$ProjectRoot)

$ErrorActionPreference = 'Stop'
if (-not $ProjectRoot) { $ProjectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path) }
$ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path.TrimEnd('\')
. (Join-Path $ProjectRoot 'tools\runtime-build-common.ps1')

function Expect-Failure([string]$Label, [scriptblock]$Action) {
    try { & $Action; throw "Expected failure did not occur: $Label" }
    catch {
        if ($_.Exception.Message -eq "Expected failure did not occur: $Label") { throw }
    }
}

$testBase = [IO.Path]::GetFullPath((Join-Path $ProjectRoot 'tmp\runtime-build-consensus-test')).TrimEnd('\')
$allowedPrefix = [IO.Path]::GetFullPath((Join-Path $ProjectRoot 'tmp')).TrimEnd('\') + '\'
if (-not $testBase.StartsWith($allowedPrefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe consensus test path.' }
if (Test-Path -LiteralPath $testBase) { Remove-Item -LiteralPath $testBase -Recurse -Force }
New-Item -ItemType Directory -Path (Join-Path $testBase 'runtime') -Force | Out-Null

try {
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [IO.File]::WriteAllText((Join-Path $testBase 'CRAZYFLASHER7MercenaryEmpire.exe'), 'bootstrap-fixture', $utf8NoBom)
    [IO.File]::WriteAllText((Join-Path $testBase 'runtime\fixture.dll'), 'runtime-fixture', $utf8NoBom)
    $sourceHash = Get-Cf7RuntimeSourceTreeHash -ProjectRoot $ProjectRoot -Mode Worktree
    $toolchainHash = Get-Cf7ToolchainLockHash -ProjectRoot $ProjectRoot -Mode Worktree
    $rootExe = Get-Item -LiteralPath (Join-Path $testBase 'CRAZYFLASHER7MercenaryEmpire.exe')
    $fixture = Get-Item -LiteralPath (Join-Path $testBase 'runtime\fixture.dll')
    $manifest = @(
        'cf7-runtime-manifest-v1',
        ('publishMode' + "`t" + 'framework-dependent'),
        ('sourceTreeHash' + "`t" + $sourceHash),
        ('toolchainLockHash' + "`t" + $toolchainHash),
        ('toolchainBaseline' + "`t" + 'cf7-win-x64-2026-07-17'),
        ('file' + "`t" + 'CRAZYFLASHER7MercenaryEmpire.exe' + "`t" + $rootExe.Length + "`t" + (Get-FileHash -Algorithm SHA256 -LiteralPath $rootExe.FullName).Hash),
        ('file' + "`t" + 'runtime/fixture.dll' + "`t" + $fixture.Length + "`t" + (Get-FileHash -Algorithm SHA256 -LiteralPath $fixture.FullName).Hash)
    ) -join "`n"
    [IO.File]::WriteAllText((Join-Path $testBase 'runtime\cf7-runtime-manifest.tsv'), $manifest + "`n", $utf8NoBom)

    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ProjectRoot 'tools\verify-runtime-bundle.ps1') -ProjectRoot $ProjectRoot -DeploymentRoot $testBase
    if ($LASTEXITCODE -ne 0) { throw 'Separate DeploymentRoot verification failed.' }

    $builderA = New-Cf7RuntimeBuildAttestation -ProjectRoot $ProjectRoot -DeploymentRoot $testBase -BuilderId 'builder-a'
    $builderB = New-Cf7RuntimeBuildAttestation -ProjectRoot $ProjectRoot -DeploymentRoot $testBase -BuilderId 'builder-b'
    $consensus = Test-Cf7RuntimeBuildAttestationConsensus -Attestations @($builderA, $builderB)
    if ($consensus.artifactClosureHash -ne $builderA.artifactClosureHash) { throw 'Consensus returned the wrong closure.' }

    $recordPath = Join-Path $testBase 'runtime-release-consensus.json'
    $record = [pscustomobject]@{
        schema = 'cf7-runtime-release-consensus.v1'
        sourceTreeHash = $consensus.sourceTreeHash
        toolchainLockHash = $consensus.toolchainLockHash
        buildRecipeHash = $consensus.buildRecipeHash
        artifactClosureHash = $consensus.artifactClosureHash
        builders = @('builder-a','builder-b')
        promotedAtUtc = [DateTime]::UtcNow.ToString('o')
    }
    [IO.File]::WriteAllText($recordPath, ($record | ConvertTo-Json -Depth 5) + "`n", $utf8NoBom)
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ProjectRoot 'tools\verify-runtime-consensus.ps1') -ProjectRoot $ProjectRoot -DeploymentRoot $testBase -RecordPath $recordPath
    if ($LASTEXITCODE -ne 0) { throw 'Runtime release consensus verification failed.' }

    Expect-Failure 'duplicate builder' { Test-Cf7RuntimeBuildAttestationConsensus -Attestations @($builderA, $builderA) | Out-Null }
    $mismatch = $builderB | ConvertTo-Json -Depth 8 | ConvertFrom-Json
    $mismatch.artifactClosureHash = ('0' * 64)
    Expect-Failure 'closure mismatch' { Test-Cf7RuntimeBuildAttestationConsensus -Attestations @($builderA, $mismatch) | Out-Null }
    Expect-Failure 'single attestation' { Test-Cf7RuntimeBuildAttestationConsensus -Attestations @($builderA) | Out-Null }

    Write-Host '[RuntimeConsensusTest] OK checks=6' -ForegroundColor Green
} finally {
    if (Test-Path -LiteralPath $testBase) { Remove-Item -LiteralPath $testBase -Recurse -Force }
}
