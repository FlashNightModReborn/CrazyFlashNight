# ============================================================
# CF7:ME 一键启动脚本（headless 自动化）
# 启动守护进程 EXE（内含 Flash Player 启动 + V8 总线）
#
# 2026-05-28 net10 迁移后：
#   - 用户面 CRAZYFLASHER7MercenaryEmpire.exe 是 native bootstrap，runtime 缺失时弹 MessageBox
#   - headless 路径直接走 runtime\CRAZYFLASHER7MercenaryEmpire.Core.exe 跳过 prompt
#   - Core apphost 默认只搜 %ProgramFiles%\dotnet，所以要复刻 bootstrap 的 user-scope 探测
# ============================================================

$scriptDirectory = Split-Path -Parent -Path $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptDirectory

$coreExe = Join-Path $projectRoot "runtime\CRAZYFLASHER7MercenaryEmpire.Core.exe"

if (-not (Test-Path $coreExe)) {
    Write-Host "[Error] Core EXE not found: $coreExe"
    Write-Host "Please run launcher\build.ps1 first."
    exit 1
}

# user-scope runtime 探测（与 bootstrap.cpp / cfn-cli.sh 行为一致）
foreach ($cand in @(
    (Join-Path $env:LOCALAPPDATA 'Microsoft\dotnet'),
    (Join-Path $env:USERPROFILE 'AppData\Local\Microsoft\dotnet'),
    (Join-Path $env:USERPROFILE '.dotnet')
)) {
    if (-not $cand) { continue }
    $desktopDir = Join-Path $cand 'shared\Microsoft.WindowsDesktop.App'
    if (-not (Test-Path $desktopDir)) { continue }
    if ((Get-ChildItem -LiteralPath $desktopDir -Directory -Filter '10.*' -ErrorAction SilentlyContinue).Count -gt 0) {
        $env:DOTNET_ROOT_X64 = $cand
        $env:DOTNET_ROOT = $cand
        Write-Host "Using user-scope dotnet runtime at $cand"
        break
    }
}

Write-Host "Starting CF7:ME Guardian Core..."
try {
    # 显式传 --project-root（Core 在 runtime\ 子目录，AppContext.BaseDirectory ≠ projectRoot）
    Start-Process -FilePath $coreExe `
        -ArgumentList @('--project-root', $projectRoot) `
        -WorkingDirectory $projectRoot -NoNewWindow
    Write-Host "Guardian started successfully."
    Write-Host "(Flash Player + V8 Bus are managed by the guardian process)"
} catch {
    Write-Host "Failed to start guardian: $_"
    exit 1
}
