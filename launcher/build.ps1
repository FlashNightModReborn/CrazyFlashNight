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

# Step 1.9: Build sol_parser DLL (Rust cdylib)
Write-Host "[Step 1.9] Build sol_parser.dll (Rust)..." -ForegroundColor Yellow
$solBat = Join-Path $launcherDir "native\sol_parser\build.bat"
if (-not (Test-Path $solBat)) {
    Write-Host "[FAIL] sol_parser build.bat missing: $solBat" -ForegroundColor Red
    exit 1
}
& cmd /c $solBat
if ($LASTEXITCODE -ne 0) {
    Write-Host "[FAIL] sol_parser build failed." -ForegroundColor Red
    exit 1
}
$solParserDll = Join-Path $binDir "sol_parser.dll"
if (-not (Test-Path $solParserDll)) {
    Write-Host "[FAIL] sol_parser.dll not found at $solParserDll after build." -ForegroundColor Red
    exit 1
}
Write-Host "  sol_parser.dll OK." -ForegroundColor Green

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
    "sol_parser.dll",
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

# Step 3.5: Hard assert sol_parser.dll landed at projectRoot (Step 3 只 WARN 不 fail,
# 此处补独立硬断言防止 "build 成功但运行时 DllNotFoundException".)
$solParserProjDll = Join-Path $projectRoot "sol_parser.dll"
if (-not (Test-Path $solParserProjDll)) {
    Write-Host "[FAIL] sol_parser.dll missing at projectRoot after copy step." -ForegroundColor Red
    exit 1
}
Write-Host "[Step 3.5] sol_parser.dll present at projectRoot." -ForegroundColor Green

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

# Step 6: Verify required WebView2 runtime assets
Write-Host "[Step 6/6] Verify required WebView2 runtime assets..." -ForegroundColor Yellow
$webDir = Join-Path $launcherDir "web"
$requiredWebPaths = @(
    "bootstrap.html",
    "bootstrap-main.js",
    "overlay.html",
    "config\version.js",
    "css\bootstrap.css",
    "css\welcome.css",
    "css\overlay.css",
    "css\panels.css",
    "lib\marked.min.js",
    "help\controls.md",
    "help\worldview.md",
    "help\easter-eggs.md",
    "icons\manifest.json",
    "data\lockbox-variants.json",
    "assets\bg\manifest.json",
    "assets\logos\cf7me-title.png",
    "assets\logos\steam.svg",
    "assets\intro.mp4",
    "assets\map\page-base.png",
    "assets\map\page-faction.png",
    "modules\audio.js",
    "modules\factions.js",
    "modules\archive-schema.js",
    "modules\archive-editor.js",
    "modules\diagnostic-log.js",
    "modules\display.js",
    "modules\about.js",
    "modules\bridge.js",
    "modules\uidata.js",
    "modules\toast.js",
    "modules\sparkline.js",
    "modules\notch.js",
    "modules\currency.js",
    "modules\jukebox.js",
    "modules\combo.js",
    "modules\panels.js",
    "modules\tooltip.js",
    "modules\icons.js",
    "modules\kshop.js",
    "modules\help-panel.js",
    "modules\map-avatar-source-data.js",
    "modules\map-panel-data.js",
    "modules\map-fit-presets.js",
    "modules\map-panel.js",
    "modules\map-hud.js",
    "modules\overlay-audio-bindings.js",
    "modules\minigames\shared\host-bridge.js",
    "modules\minigames\shared\minigame-shell.css",
    "modules\minigames\lockbox\lockbox.css",
    "modules\minigames\lockbox\lockbox-panel.js",
    "modules\minigames\pinalign\pinalign.css",
    "modules\minigames\pinalign\pinalign-panel.js",
    "modules\minigames\gobang\gobang.css",
    "modules\minigames\gobang\gobang-panel.js",
    "modules\minigames\gobang\gobang-audio.js",
    "modules\minigames\gobang\core\index.js"
)
$missingWebPaths = @()
foreach ($relativePath in $requiredWebPaths) {
    $fullPath = Join-Path $webDir $relativePath
    if (-not (Test-Path $fullPath)) {
        $missingWebPaths += $relativePath
    }
}
if ($missingWebPaths.Count -gt 0) {
    Write-Host "[FAIL] Required launcher\\web runtime assets missing:" -ForegroundColor Red
    foreach ($missingPath in $missingWebPaths) {
        Write-Host "  - $missingPath" -ForegroundColor Red
    }
    exit 1
}
Write-Host "  OK: launcher\\web runtime assets present ($($requiredWebPaths.Count) checks)" -ForegroundColor Green

Write-Host ""
Write-Host "=== Build Complete ===" -ForegroundColor Green
Write-Host "  Output: $projectRoot\CRAZYFLASHER7MercenaryEmpire.exe"
