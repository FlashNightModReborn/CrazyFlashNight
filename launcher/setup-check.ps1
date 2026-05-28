# ============================================================
# CF7:ME Guardian Process - Environment Setup Check (net10.0-windows)
# 构建 / 运行前置依赖检查
#   - .NET 10 SDK（user-scope %LOCALAPPDATA%\Microsoft\dotnet 或 system PATH）
#     满足 global.json `version: 10.0.300` + `rollForward: latestFeature`
#   - WebView2 Runtime（Phase 1 全局硬依赖）
#   - MSVC C 编译器（miniaudio.dll 软依赖：缺则跳过 native build；运行时硬依赖）
#   - Rust 工具链（sol_parser.dll 硬依赖）
#   - Node.js + npm（TypeScript 编译 V8 脚本 + cf7-packer + cf7-save-repair-dict-build 硬依赖）
# 缺失硬依赖即 fail，给下载链接。CI / 新机首次构建必须先过本脚本
# ============================================================

$ErrorActionPreference = "Stop"

$launcherDir = $PSScriptRoot
$projectRoot = Split-Path -Parent $launcherDir
$failCount = 0

function Write-Ok($msg)   { Write-Host "  [OK]   $msg" -ForegroundColor Green }
function Write-Warn($msg, $hint) {
    Write-Host "  [WARN] $msg" -ForegroundColor Yellow
    if ($hint) { Write-Host "         -> $hint" -ForegroundColor DarkYellow }
}
function Write-Fail($msg, $hint) {
    Write-Host "  [FAIL] $msg" -ForegroundColor Red
    if ($hint) { Write-Host "         -> $hint" -ForegroundColor Yellow }
    $script:failCount++
}

function Get-GlobalJsonSdkVersion {
    $globalJsonPath = Join-Path $projectRoot "global.json"
    if (-not (Test-Path $globalJsonPath)) { return $null }

    try {
        $json = Get-Content -Raw -Path $globalJsonPath | ConvertFrom-Json
        if ($json.sdk -and $json.sdk.version) {
            return [version]$json.sdk.version
        }
    } catch { }

    return $null
}

function Test-SdkVersionMeetsPin {
    param(
        [Parameter(Mandatory=$true)][version]$Installed,
        [Parameter(Mandatory=$true)][version]$Pinned
    )

    if ($Installed.Major -ne $Pinned.Major) { return $false }
    if ($Installed.Minor -ne $Pinned.Minor) { return $false }

    # global.json uses rollForward=latestFeature. For 10.0.300 this accepts
    # 10.0.300+ feature bands, but not earlier previews such as 10.0.100.
    return $Installed.Build -ge $Pinned.Build
}

Write-Host "=== CF7:ME Setup Check (net10.0-windows) ===" -ForegroundColor Cyan
Write-Host ""

# 1. .NET 10 SDK
Write-Host "[1/5] .NET 10 SDK..." -ForegroundColor Yellow
$userDotnet = Join-Path $env:LOCALAPPDATA "Microsoft\dotnet\dotnet.exe"
if (Test-Path $userDotnet) {
    $dotnet = $userDotnet
    Write-Ok "user-scope dotnet: $dotnet"
} else {
    $sysDotnet = (Get-Command dotnet -ErrorAction SilentlyContinue).Source
    if ($sysDotnet) {
        $dotnet = $sysDotnet
        Write-Ok "system dotnet: $dotnet"
    } else {
        $dotnet = $null
        Write-Fail ".NET runtime/SDK 找不到" `
            "user-scope 装法（无需 admin）：powershell -c `"iwr https://dot.net/v1/dotnet-install.ps1 -OutFile `$env:TEMP\dotnet-install.ps1; & `$env:TEMP\dotnet-install.ps1 -Channel 10.0 -InstallDir `$env:LOCALAPPDATA\Microsoft\dotnet`""
    }
}

if ($dotnet) {
    $sdks = & $dotnet --list-sdks 2>&1
    $pinnedSdk = Get-GlobalJsonSdkVersion
    if (-not $pinnedSdk) {
        $pinnedSdk = [version]"10.0.300"
    }
    $matchingSdk = @()
    foreach ($line in $sdks) {
        if ($line -match "^(\d+\.\d+\.\d+)") {
            $sdkVersion = [version]$matches[1]
            if (Test-SdkVersionMeetsPin -Installed $sdkVersion -Pinned $pinnedSdk) {
                $matchingSdk += $line
            }
        }
    }
    if ($matchingSdk.Count -gt 0) {
        Write-Ok ".NET SDK satisfies global.json $pinnedSdk latestFeature: $($matchingSdk -join '; ')"
    } else {
        Write-Fail ".NET SDK 不满足 global.json pin $pinnedSdk + latestFeature" `
            "Installed: $($sdks -join '; '). 装法同上 -Channel 10.0；需 10.0.$($pinnedSdk.Build) 或更高 feature band"
    }

    $rt = & $dotnet --list-runtimes 2>&1
    $desktop10 = $rt | Where-Object { $_ -match "^Microsoft\.WindowsDesktop\.App 10\." }
    if ($desktop10) {
        Write-Ok "WindowsDesktop runtime 10.x present: $($desktop10 -join '; ')"
    } else {
        Write-Fail "WindowsDesktop.App 10.x runtime 缺失（UseWindowsForms 硬依赖）" `
            "通常装 SDK 时已带，单装 runtime: -Runtime windowsdesktop -Channel 10.0"
    }
}

# 2. WebView2 Runtime
Write-Host "[2/5] WebView2 Runtime..." -ForegroundColor Yellow
$wv2ClientId = "{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}"
$wv2Keys = @(
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\$wv2ClientId",
    "HKLM:\SOFTWARE\Microsoft\EdgeUpdate\Clients\$wv2ClientId",
    "HKCU:\SOFTWARE\Microsoft\EdgeUpdate\Clients\$wv2ClientId"
)
$wv2Found = $false
foreach ($k in $wv2Keys) {
    if (Test-Path $k) {
        $pv = (Get-ItemProperty -Path $k -ErrorAction SilentlyContinue).pv
        if ($pv -and $pv -ne "0.0.0.0") {
            Write-Ok "WebView2 Runtime v$pv at $k"
            $wv2Found = $true
            break
        }
    }
}
if (-not $wv2Found) {
    Write-Fail "WebView2 Runtime not installed (Phase 1 hard dependency)" `
        "Download: https://developer.microsoft.com/microsoft-edge/webview2/ (Evergreen Bootstrapper)"
}

# 3. MSVC C 编译器（miniaudio.dll 构建期软依赖，运行期硬依赖）
Write-Host "[3/5] MSVC C compiler (for miniaudio.dll)..." -ForegroundColor Yellow
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
if (Test-Path $vswhere) {
    $vsPath = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath 2>$null
    if ($vsPath) {
        Write-Ok "VC Build Tools at: $vsPath"
    } else {
        Write-Warn "VC Build Tools 未通过 vswhere 检出（native\build.bat 会失败）" `
            "winget install Microsoft.VisualStudio.2022.BuildTools --override `"--add Microsoft.VisualStudio.Component.VC.Tools.x86.x64`""
    }
} else {
    Write-Warn "vswhere.exe missing — 无法验证 VC Build Tools" `
        "通常装 VS2022 Build Tools 即可"
}

# 4. Rust toolchain（sol_parser.dll 硬依赖）
Write-Host "[4/5] Rust toolchain (for sol_parser.dll)..." -ForegroundColor Yellow
$cargo = (Get-Command cargo -ErrorAction SilentlyContinue).Source
if ($cargo) {
    $cargoVer = & cargo --version 2>&1
    Write-Ok "cargo present: $cargoVer"
} else {
    Write-Fail "cargo not in PATH（sol_parser.dll build 必需）" `
        "Install: https://rustup.rs/ → rustup-init.exe → stable-x86_64-pc-windows-msvc"
}

# 5. Node.js + npm（TypeScript / packer / dict-build 硬依赖）
Write-Host "[5/5] Node.js + npm..." -ForegroundColor Yellow
$node = (Get-Command node -ErrorAction SilentlyContinue).Source
$npm  = (Get-Command npm  -ErrorAction SilentlyContinue).Source
if ($node -and $npm) {
    $nodeVer = & node --version 2>&1
    $npmVer  = & npm --version 2>&1
    Write-Ok "node $nodeVer / npm $npmVer"
} else {
    Write-Fail "node / npm 未在 PATH（TypeScript 编译 + cf7-packer + cf7-save-repair-dict-build 必需）" `
        "winget install OpenJS.NodeJS.LTS"
}

# 结论
Write-Host ""
if ($failCount -eq 0) {
    Write-Host "=== All checks passed ===" -ForegroundColor Green
    exit 0
} else {
    Write-Host "=== $failCount check(s) failed ===" -ForegroundColor Red
    exit 1
}
