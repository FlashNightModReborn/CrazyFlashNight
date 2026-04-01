# ============================================================
# CF7:ME Guardian Process - Build Script
# 构建守护进程并复制产物到项目根目录
# ============================================================

$ErrorActionPreference = "Stop"

$launcherDir = $PSScriptRoot
$projectRoot = Split-Path -Parent $launcherDir
$msbuild = "C:\Windows\Microsoft.NET\Framework64\v4.0.30319\msbuild.exe"
$nuget = Join-Path $launcherDir "tools\nuget.exe"
$binDir = Join-Path $launcherDir "bin\Release"

Write-Host "=== CF7:ME Guardian Build ===" -ForegroundColor Cyan
Write-Host "  Project Root: $projectRoot"
Write-Host "  Launcher Dir: $launcherDir"
Write-Host ""

# Step 1: NuGet restore
Write-Host "[Step 1/4] NuGet restore..." -ForegroundColor Yellow
$packagesConfig = Join-Path $launcherDir "packages.config"
$packagesDir = Join-Path $launcherDir "packages"
& $nuget restore $packagesConfig -PackagesDirectory $packagesDir -Verbosity quiet
if ($LASTEXITCODE -ne 0) {
    Write-Host "[FAIL] NuGet restore failed." -ForegroundColor Red
    exit 1
}
Write-Host "  NuGet restore OK." -ForegroundColor Green

# Step 1.5: TypeScript compile (V8 scripts)
Write-Host "[Step 1.5] TypeScript compile..." -ForegroundColor Yellow
$tsDir = Join-Path $launcherDir "scripts"
if (Test-Path (Join-Path $tsDir "tsconfig.json")) {
    Push-Location $tsDir
    try {
        if (-not (Test-Path "node_modules")) {
            npm install --ignore-scripts 2>&1 | Out-Null
        }
        npx tsc --project tsconfig.json
        if ($LASTEXITCODE -ne 0) {
            Write-Host "  [FAIL] TypeScript compilation failed." -ForegroundColor Red
            exit 1
        }
        Write-Host "  TypeScript compiled -> dist/hit-number-bundle.js" -ForegroundColor Green
    } finally {
        Pop-Location
    }
} else {
    Write-Host "  [SKIP] No tsconfig.json found in $tsDir" -ForegroundColor Yellow
}

# Step 1.8: Build native miniaudio DLL
Write-Host "[Step 1.8] Build native miniaudio DLL..." -ForegroundColor Yellow
$nativeBat = Join-Path $launcherDir "native\build.bat"
if (Test-Path $nativeBat) {
    & cmd /c $nativeBat
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[FAIL] Native build failed." -ForegroundColor Red
        exit 1
    }
    Write-Host "  Native build OK." -ForegroundColor Green
} else {
    Write-Host "  [SKIP] No native\build.bat found" -ForegroundColor Yellow
}

# Step 2: MSBuild
Write-Host "[Step 2/4] MSBuild compile..." -ForegroundColor Yellow
$csproj = Join-Path $launcherDir "CRAZYFLASHER7MercenaryEmpire.csproj"
& $msbuild $csproj "-p:Configuration=Release" -verbosity:minimal
if ($LASTEXITCODE -ne 0) {
    Write-Host "[FAIL] MSBuild failed." -ForegroundColor Red
    exit 1
}
Write-Host "  MSBuild OK." -ForegroundColor Green

# Step 3: Copy managed artifacts to project root
Write-Host "[Step 3/4] Copy managed DLLs..." -ForegroundColor Yellow
$managedFiles = @(
    "CRAZYFLASHER7MercenaryEmpire.exe",
    "ClearScript.Core.dll",
    "ClearScript.V8.dll",
    "ClearScript.V8.ICUData.dll",
    "Newtonsoft.Json.dll",
    "miniaudio.dll",
    "SharpDX.dll",
    "SharpDX.DXGI.dll",
    "SharpDX.Direct3D11.dll",
    "SharpDX.D3DCompiler.dll",
    "Microsoft.Web.WebView2.Core.dll",
    "Microsoft.Web.WebView2.WinForms.dll"
)
foreach ($f in $managedFiles) {
    $src = Join-Path $binDir $f
    if (Test-Path $src) {
        Copy-Item $src $projectRoot -Force
        Write-Host "  Copied: $f"
    } else {
        Write-Host "  [WARN] Not found: $src" -ForegroundColor Yellow
    }
}

# Step 4: Copy native V8 DLL
Write-Host "[Step 4/6] Copy native V8 DLL..." -ForegroundColor Yellow
$nativeSrc = Join-Path $launcherDir `
    "packages\Microsoft.ClearScript.V8.Native.win-x64.7.4.5\runtimes\win-x64\native\ClearScriptV8.win-x64.dll"
if (Test-Path $nativeSrc) {
    Copy-Item $nativeSrc $projectRoot -Force
    Write-Host "  Copied: ClearScriptV8.win-x64.dll"
} else {
    Write-Host "  [FAIL] Native DLL not found: $nativeSrc" -ForegroundColor Red
    exit 1
}

# Step 5: Copy WebView2 native loader
Write-Host "[Step 5/6] Copy WebView2 native loader..." -ForegroundColor Yellow
$wv2Loader = Join-Path $launcherDir `
    "packages\Microsoft.Web.WebView2.1.0.3856.49\runtimes\win-x64\native\WebView2Loader.dll"
if (Test-Path $wv2Loader) {
    Copy-Item $wv2Loader $projectRoot -Force
    Write-Host "  Copied: WebView2Loader.dll"
} else {
    Write-Host "  [WARN] WebView2Loader.dll not found: $wv2Loader" -ForegroundColor Yellow
}

# Step 6: Verify web overlay assets
Write-Host "[Step 6/6] Verify web overlay assets..." -ForegroundColor Yellow
$webDir = Join-Path $launcherDir "web"
if (Test-Path (Join-Path $webDir "overlay.html")) {
    Write-Host "  OK: launcher\web\overlay.html present"
} else {
    Write-Host "  [WARN] launcher\web\overlay.html not found (WebView2 overlay will be unavailable)" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "=== Build Complete ===" -ForegroundColor Green
Write-Host "  Output: $projectRoot\CRAZYFLASHER7MercenaryEmpire.exe"
