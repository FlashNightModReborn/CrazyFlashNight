[CmdletBinding()]
param([ValidateRange(1,3600)][int]$TimeoutSeconds=300,[switch]$SkipCompile)
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
# Issue #262: content is owned by TS. Flash input/anchor tests have a separate focused runner.
& node (Join-Path $repoRoot 'launcher/tooltip-engine/build.cjs') --check
if ($LASTEXITCODE -ne 0) { throw 'Tooltip bundle check failed.' }
& node --test (Join-Path $repoRoot 'launcher/tooltip-engine/tests/engine.test.cjs') (Join-Path $repoRoot 'launcher/tooltip-engine/tests/source-regressions.test.cjs')
if ($LASTEXITCODE -ne 0) { throw 'Tooltip content tests failed.' }
Write-Host '[OK] Launcher tooltip content tests passed; no Flash/AVM1 claim.'
