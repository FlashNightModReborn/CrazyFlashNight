# ============================================================
# CF7:ME Launcher Test Runner
# 独立于 build.ps1：不走 native / TypeScript / 拷贝步骤，仅跑 C# 单测
# ============================================================

$ErrorActionPreference = "Stop"

$testsDir    = $PSScriptRoot
$launcherDir = Split-Path -Parent $testsDir
$msbuild     = "C:\Windows\Microsoft.NET\Framework64\v4.0.30319\msbuild.exe"
$nuget       = Join-Path $launcherDir "tools\nuget.exe"
$packagesDir = Join-Path $launcherDir "packages"

Write-Host "=== CF7:ME Launcher Tests ===" -ForegroundColor Cyan
Write-Host "  Launcher Dir: $launcherDir"
Write-Host "  Tests Dir   : $testsDir"
Write-Host ""

if (-not (Test-Path $nuget)) {
    Write-Host "[FAIL] nuget.exe missing: $nuget" -ForegroundColor Red
    exit 1
}
if (-not (Test-Path $msbuild)) {
    Write-Host "[FAIL] msbuild missing: $msbuild" -ForegroundColor Red
    exit 1
}

# Step 1a: restore 主工程 packages.config（ProjectReference 需要主工程 HintPath 解析）
Write-Host "[Step 1a] NuGet restore (main)..." -ForegroundColor Yellow
$mainPackagesConfig = Join-Path $launcherDir "packages.config"
& $nuget restore $mainPackagesConfig -PackagesDirectory $packagesDir -Verbosity quiet
if ($LASTEXITCODE -ne 0) {
    Write-Host "[FAIL] NuGet restore (main) failed." -ForegroundColor Red
    exit 1
}
Write-Host "  main restore OK." -ForegroundColor Green

# Step 1b: restore 测试专属 packages.config（xunit 系列）
Write-Host "[Step 1b] NuGet restore (tests)..." -ForegroundColor Yellow
$testPackagesConfig = Join-Path $testsDir "packages.config"
& $nuget restore $testPackagesConfig -PackagesDirectory $packagesDir -Verbosity quiet
if ($LASTEXITCODE -ne 0) {
    Write-Host "[FAIL] NuGet restore (tests) failed." -ForegroundColor Red
    exit 1
}
Write-Host "  tests restore OK." -ForegroundColor Green

# Step 2: MSBuild 编译测试项目（ProjectReference 会顺带编译主工程）
Write-Host "[Step 2] MSBuild compile tests..." -ForegroundColor Yellow
$testsCsproj = Join-Path $testsDir "Launcher.Tests.csproj"
& $msbuild $testsCsproj "-p:Configuration=Debug" -verbosity:minimal
if ($LASTEXITCODE -ne 0) {
    Write-Host "[FAIL] MSBuild failed." -ForegroundColor Red
    exit 1
}
Write-Host "  MSBuild OK." -ForegroundColor Green

# Step 3: 探测 xunit.console.exe（restore 后实际布局以 nuget 为准，不 hardcode）
Write-Host "[Step 3] Locate xunit runner..." -ForegroundColor Yellow
$runner = Get-ChildItem -Path $packagesDir -Recurse -Filter "xunit.console.exe" -ErrorAction SilentlyContinue |
          Select-Object -First 1
if (-not $runner) {
    Write-Host "[FAIL] xunit.console.exe not found under $packagesDir" -ForegroundColor Red
    exit 1
}
Write-Host "  runner: $($runner.FullName)" -ForegroundColor Green

# Step 4: 找到测试产出 dll
$testDll = Join-Path $testsDir "bin\Debug\Launcher.Tests.dll"
if (-not (Test-Path $testDll)) {
    Write-Host "[FAIL] test dll missing: $testDll" -ForegroundColor Red
    exit 1
}

# Step 5: 跑测试
Write-Host "[Step 4] Run tests..." -ForegroundColor Yellow
& $runner.FullName $testDll -nologo
$exitCode = $LASTEXITCODE
Write-Host ""
if ($exitCode -eq 0) {
    Write-Host "=== Tests Passed ===" -ForegroundColor Green
} else {
    Write-Host "=== Tests FAILED (exit=$exitCode) ===" -ForegroundColor Red
}
exit $exitCode
