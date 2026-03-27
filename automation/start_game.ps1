# ============================================================
# CF7:ME 游戏启动脚本（兼容旧入口）
# 现在统一由守护进程管理，此脚本等价于 start.ps1
# ============================================================

$scriptDirectory = Split-Path -Parent -Path $MyInvocation.MyCommand.Path
$startScript = Join-Path $scriptDirectory "start.ps1"

if (Test-Path $startScript) {
    & $startScript
} else {
    Write-Host "[Error] start.ps1 not found"
    exit 1
}
