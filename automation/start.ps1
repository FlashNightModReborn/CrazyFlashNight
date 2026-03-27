# ============================================================
# CF7:ME 一键启动脚本
# 启动守护进程 EXE（内含 Flash Player 启动 + V8 总线）
# ============================================================

$scriptDirectory = Split-Path -Parent -Path $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptDirectory

$guardianExe = Join-Path $projectRoot "CRAZYFLASHER7MercenaryEmpire.exe"

if (-not (Test-Path $guardianExe)) {
    Write-Host "[Error] Guardian EXE not found: $guardianExe"
    Write-Host "Please run launcher\build.ps1 first."
    exit 1
}

Write-Host "Starting CF7:ME Guardian..."
try {
    Start-Process -FilePath $guardianExe -WorkingDirectory $projectRoot -NoNewWindow
    Write-Host "Guardian started successfully."
    Write-Host "(Flash Player + V8 Bus are managed by the guardian process)"
} catch {
    Write-Host "Failed to start guardian: $_"
    exit 1
}
