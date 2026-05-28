# ============================================================
# .NET 10 Desktop Runtime 探测助手（与 launcher/native/bootstrap/bootstrap.cpp 等价）
#
# 为什么需要：
#   - Headless 调用方（automation/start.ps1, scripts/gobang_trainer_cycle.ps1, tools/cfn-cli.sh）
#     直跑 runtime\Core.exe 绕过 bootstrap 的 MessageBox prompt
#   - Core.exe (FDD apphost) 默认只搜 %ProgramFiles%\dotnet；若 runtime 装在 user-scope 必须
#     export DOTNET_ROOT_X64 / DOTNET_ROOT 让 apphost 找到
#   - 半安装的 user-scope（空 10.x 目录、preview 残留）会让 apphost 信 env 后找不到 deps.json
#     就报英文错并退出。校验必须包含 Microsoft.WindowsDesktop.App.deps.json 真实存在
#
# 行为：
#   1. 优先看系统位置 %ProgramFiles%\dotnet — 命中即返回，不设 env（apphost 默认能搜到）
#   2. 否则依次 %LOCALAPPDATA%\Microsoft\dotnet → %USERPROFILE%\.dotnet
#   3. 每个候选必须含 shared\Microsoft.WindowsDesktop.App\10.*\Microsoft.WindowsDesktop.App.deps.json
#   4. 找到非默认位置时 set $env:DOTNET_ROOT_X64 / $env:DOTNET_ROOT
#   5. 完全找不到时返回 $false（调用方自行决定 fatal / warn）
#
# 用法（在调用脚本顶部）：
#   . (Join-Path $PSScriptRoot '..\tools\dotnet-runtime-detect.ps1')   # 路径相对调用方
#   if (-not (Set-DotnetRootForCore)) { exit 1 }
# ============================================================

function Test-DotnetRoot10Valid {
    param([string]$Root)
    if ([string]::IsNullOrEmpty($Root)) { return $false }
    $desktop = Join-Path $Root 'shared\Microsoft.WindowsDesktop.App'
    if (-not (Test-Path -LiteralPath $desktop)) { return $false }
    $candidates = Get-ChildItem -LiteralPath $desktop -Directory -Filter '10.*' -ErrorAction SilentlyContinue
    foreach ($v in $candidates) {
        $deps = Join-Path $v.FullName 'Microsoft.WindowsDesktop.App.deps.json'
        if (Test-Path -LiteralPath $deps) { return $true }
    }
    return $false
}

function Set-DotnetRootForCore {
    [CmdletBinding()]
    param([switch]$Quiet)

    $systemDotnet = $null
    if ($env:ProgramFiles) { $systemDotnet = Join-Path $env:ProgramFiles 'dotnet' }

    if (Test-DotnetRoot10Valid $systemDotnet) {
        if (-not $Quiet) {
            Write-Host "Using system .NET 10 desktop runtime at $systemDotnet (no DOTNET_ROOT override)"
        }
        return $true
    }

    $candidates = @()
    if ($env:LOCALAPPDATA) { $candidates += (Join-Path $env:LOCALAPPDATA 'Microsoft\dotnet') }
    if ($env:USERPROFILE)  { $candidates += (Join-Path $env:USERPROFILE  '.dotnet') }

    foreach ($cand in $candidates) {
        if (Test-DotnetRoot10Valid $cand) {
            $env:DOTNET_ROOT_X64 = $cand
            $env:DOTNET_ROOT     = $cand
            if (-not $Quiet) {
                Write-Host "Using user-scope .NET 10 desktop runtime at $cand (DOTNET_ROOT set)"
            }
            return $true
        }
    }

    if (-not $Quiet) {
        Write-Host "[Error] 未找到带 Microsoft.WindowsDesktop.App.deps.json 的 .NET 10 桌面运行时；" -ForegroundColor Red
        Write-Host "        请双击 CRAZYFLASHER7MercenaryEmpire.exe 让 bootstrap 自动安装，" -ForegroundColor Red
        Write-Host "        或手动安装 tools\dotnet-runtime\windowsdesktop-runtime-10.*-win-x64.exe" -ForegroundColor Red
    }
    return $false
}
