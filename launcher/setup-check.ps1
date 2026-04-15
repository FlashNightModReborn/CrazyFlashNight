# ============================================================
# CF7:ME Guardian Process - Environment Setup Check
# P3b Phase 1j: 构建 / 运行前置依赖检查
#   - .NET Framework 4.6.2 Targeting Pack (MSB3644 防呆)
#   - MSBuild (build.ps1 使用 Framework64 v4.0.30319)
#   - tools/nuget.exe
#   - WebView2 Runtime (Phase 1 全局硬依赖)
# 缺失即 fail，给下载链接。CI/新机首次构建必须先过本脚本
# ============================================================

$ErrorActionPreference = "Stop"

$launcherDir = $PSScriptRoot
$failCount = 0

function Write-Ok($msg)   { Write-Host "  [OK]   $msg" -ForegroundColor Green }
function Write-Fail($msg, $hint) {
    Write-Host "  [FAIL] $msg" -ForegroundColor Red
    if ($hint) { Write-Host "         -> $hint" -ForegroundColor Yellow }
    $script:failCount++
}

Write-Host "=== CF7:ME Setup Check ===" -ForegroundColor Cyan
Write-Host ""

# 1. .NET Framework 4.6.2 Targeting Pack
Write-Host "[1/4] .NET Framework 4.6.2 Targeting Pack..." -ForegroundColor Yellow
$refAsmDir = "${env:ProgramFiles(x86)}\Reference Assemblies\Microsoft\Framework\.NETFramework\v4.6.2"
if (Test-Path (Join-Path $refAsmDir "mscorlib.dll")) {
    Write-Ok ".NETFramework v4.6.2 reference assemblies found"
} else {
    Write-Fail "Targeting Pack 4.6.2 missing (MSB3644 will hit)" `
        "Download: https://dotnet.microsoft.com/download/dotnet-framework/net462 (Developer Pack)"
}

# 2. MSBuild (build.ps1 hard-codes Framework64 v4.0.30319)
Write-Host "[2/4] MSBuild (Framework64 v4.0.30319)..." -ForegroundColor Yellow
$msbuild = "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\msbuild.exe"
if (Test-Path $msbuild) {
    Write-Ok "msbuild.exe present at $msbuild"
} else {
    Write-Fail "msbuild.exe not found at $msbuild" `
        "Install .NET Framework 4.x runtime (usually preinstalled on Win10/11)"
}

# 3. tools/nuget.exe
Write-Host "[3/4] tools/nuget.exe..." -ForegroundColor Yellow
$nuget = Join-Path $launcherDir "tools\nuget.exe"
if (Test-Path $nuget) {
    Write-Ok "nuget.exe present"
} else {
    Write-Fail "launcher\tools\nuget.exe missing" `
        "Download: https://dist.nuget.org/win-x86-commandline/latest/nuget.exe -> launcher\tools\"
}

# 4. WebView2 Runtime (Phase 1 全局硬依赖)
Write-Host "[4/4] WebView2 Runtime..." -ForegroundColor Yellow
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

# 结论
Write-Host ""
if ($failCount -eq 0) {
    Write-Host "=== All checks passed ===" -ForegroundColor Green
    exit 0
} else {
    Write-Host "=== $failCount check(s) failed ===" -ForegroundColor Red
    exit 1
}
