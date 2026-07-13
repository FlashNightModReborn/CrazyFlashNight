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

# dotnet host 探测：按 global.json feature band 在用户级与系统级安装中选择，不改机器 PATH。
. (Join-Path $launcherDir 'resolve-dotnet.ps1')
$dotnet = Resolve-Cf7Dotnet -ProjectRoot $projectRoot

Write-Host "=== CF7:ME Launcher Tests (net10.0-windows) ===" -ForegroundColor Cyan
Write-Host "  Launcher Dir: $launcherDir"
Write-Host "  Tests Dir   : $testsDir"
Write-Host "  dotnet      : $dotnet"
$dotnetSdk = & $dotnet --version 2>&1
Write-Host "  dotnet SDK  : $dotnetSdk"
Write-Host ""

if (-not (Test-Path $testsCsproj)) {
    Write-Host "[FAIL] Tests csproj missing: $testsCsproj" -ForegroundColor Red
    exit 1
}

Write-Host "[Step 1] dotnet test (Release)..." -ForegroundColor Yellow
# Push-Location $projectRoot 保证 global.json (repo root) 被 dotnet host 找到，SDK pin 10.0.x 生效
Push-Location $projectRoot
try {
    & $dotnet test $testsCsproj -c Release
    $exitCode = $LASTEXITCODE
} finally {
    Pop-Location
}

Write-Host ""
if ($exitCode -eq 0) {
    Write-Host "=== Tests Passed ===" -ForegroundColor Green
} else {
    Write-Host "=== Tests FAILED (exit=$exitCode) ===" -ForegroundColor Red
}
exit $exitCode
