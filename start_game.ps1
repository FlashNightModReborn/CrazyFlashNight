# 获取当前脚本所在的目录 (start_game.ps1 所在目录)
$scriptDirectory = Split-Path -Parent -Path $MyInvocation.MyCommand.Path

# 定义 start.ps1 的路径
$startScriptPath = Join-Path $scriptDirectory "automation\start.ps1"

# 检查 start.ps1 是否存在
if (-not (Test-Path $startScriptPath)) {
    Write-Host "Error: Start script not found at $startScriptPath"
    exit 1
}

# 启动 start.ps1 脚本
Write-Host "Starting the game and server using $startScriptPath..."

try {
    Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$startScriptPath`"" -NoNewWindow
    Write-Host "Game and server started successfully."
} catch {
    Write-Host "Failed to start the game and server using $startScriptPath. Error: $_"
    exit 1
}
