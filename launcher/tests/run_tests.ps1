# ============================================================
# CF7:ME Launcher Test Runner (net10.0-windows)
# 独立于 build.ps1：不走 native / TypeScript / 拷贝步骤，仅跑 C# 单测
# ============================================================
#
# Phase 4 重写：从 nuget restore + msbuild + xunit.console.exe 路径切到
# `dotnet test`（Microsoft.NET.Test.Sdk + xunit.runner.visualstudio）。

$ErrorActionPreference = "Stop"

$testsDir    = $PSScriptRoot
$launcherDir = Split-Path -Parent $testsDir
$projectRoot = Split-Path -Parent $launcherDir
$testsCsproj = Join-Path $testsDir "Launcher.Tests.csproj"
$xunitRunnerPolicy = Join-Path $testsDir "xunit.runner.json"

function Assert-XunitRunnerPolicy {
    param(
        [Parameter(Mandatory = $true)]
        [string]$PolicyPath
    )

    if (-not (Test-Path -LiteralPath $PolicyPath -PathType Leaf)) {
        throw "xUnit runner policy missing: $PolicyPath"
    }

    try {
        $policyText = [System.IO.File]::ReadAllText(
            $PolicyPath,
            [System.Text.Encoding]::UTF8)
        $policy = $policyText | ConvertFrom-Json -ErrorAction Stop
    } catch {
        throw "xUnit runner policy is not valid JSON: $($_.Exception.Message)"
    }

    if ($null -eq $policy -or $policy -is [System.Array]) {
        throw "xUnit runner policy root must be one JSON object"
    }

    $schema = $policy.PSObject.Properties['$schema']
    if ($null -eq $schema -or
        $schema.Value -isnot [string] -or
        $schema.Value -ne
        'https://xunit.net/schema/v2.8/xunit.runner.schema.json') {
        throw "xUnit runner policy must use the frozen v2.8 schema"
    }

    $diagnostics =
        $policy.PSObject.Properties['diagnosticMessages']
    if ($null -eq $diagnostics -or
        $diagnostics.Value -isnot [bool] -or
        -not $diagnostics.Value) {
        throw "xUnit runner policy diagnosticMessages must be boolean true"
    }

    $parallelize =
        $policy.PSObject.Properties['parallelizeTestCollections']
    if ($null -eq $parallelize -or
        $parallelize.Value -isnot [bool] -or
        $parallelize.Value) {
        throw "xUnit runner policy parallelizeTestCollections must be boolean false"
    }
}

# dotnet host 探测：只接受 global.json 的 exact SDK contract，不改机器 PATH。
. (Join-Path $launcherDir 'resolve-dotnet.ps1')

Write-Host "=== CF7:ME Launcher Tests (net10.0-windows) ===" -ForegroundColor Cyan
Write-Host "  Launcher Dir: $launcherDir"
Write-Host "  Tests Dir   : $testsDir"

Write-Host ""
Write-Host "[Step 0] exact SDK resolver contract tests..." -ForegroundColor Yellow
& (Join-Path $testsDir 'resolve-dotnet.tests.ps1')

$dotnet = Resolve-Cf7Dotnet -ProjectRoot $projectRoot
Write-Host "  dotnet      : $dotnet"
$dotnetSdk = & $dotnet --version 2>&1
Write-Host "  dotnet SDK  : $dotnetSdk"
Write-Host ""

if (-not (Test-Path $testsCsproj)) {
    Write-Host "[FAIL] Tests csproj missing: $testsCsproj" -ForegroundColor Red
    exit 1
}

Write-Host "[Step 1] xUnit runner policy preflight..." -ForegroundColor Yellow
try {
    Assert-XunitRunnerPolicy -PolicyPath $xunitRunnerPolicy
} catch {
    Write-Host "[FAIL] $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
Write-Host "  schema                    : v2.8"
Write-Host "  diagnostic messages       : on"
Write-Host "  parallel test collections : off"
Write-Host ""

Write-Host "[Step 2] dotnet test (Release)..." -ForegroundColor Yellow
# Push-Location $projectRoot 保证 global.json (repo root) 被 dotnet host 找到，SDK exact pin 生效
Push-Location $projectRoot
$previousErrorActionPreference = $ErrorActionPreference
$testOutput = @()
try {
    # Windows PowerShell turns redirected native stderr into ErrorRecord.
    # Keep it non-terminating while the complete testhost diagnostic stream
    # is captured, then restore the runner's fail-fast preference.
    $ErrorActionPreference = "Continue"
    $testOutput = @(
        & $dotnet test $testsCsproj -c Release `
            --logger "console;verbosity=normal" 2>&1
    )
    $exitCode = $LASTEXITCODE
} finally {
    $ErrorActionPreference = $previousErrorActionPreference
    Pop-Location
}

foreach ($line in $testOutput) {
    Write-Output $line
}

$runnerPolicyMarker =
    'Starting:    Launcher.Tests (parallel test collections = off, stop on fail = off)'
$runnerPolicyMarkerCount = @(
    $testOutput | Where-Object {
        ([string]$_).Contains($runnerPolicyMarker)
    }
).Count
if ($runnerPolicyMarkerCount -ne 1) {
    Write-Host (
        "[FAIL] xUnit testhost did not emit the exact serial-policy " +
        "diagnostic marker (count=$runnerPolicyMarkerCount)"
    ) -ForegroundColor Red
    exit 1
}
Write-Host "[xunit-policy] testhost confirmed parallel test collections = off"

Write-Host ""
if ($exitCode -eq 0) {
    Write-Host "=== Tests Passed ===" -ForegroundColor Green
} else {
    Write-Host "=== Tests FAILED (exit=$exitCode) ===" -ForegroundColor Red
}
exit $exitCode
