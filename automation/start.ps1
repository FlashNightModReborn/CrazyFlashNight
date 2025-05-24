# 获取当前脚本所在的目录 (automation directory)
$scriptDirectory = Split-Path -Parent -Path $MyInvocation.MyCommand.Path

# 启动游戏的脚本路径 (ensure it's relative to the automation folder)
$startGameScript = "$scriptDirectory\start_game.ps1"

# 启动服务器的脚本路径 (ensure it's relative to the automation folder)
$startServerScript = "$scriptDirectory\start_server.ps1"

# 检查启动游戏的脚本是否存在
if (-not (Test-Path $startGameScript)) {
    Write-Host "Error: Game startup script not found at $startGameScript"
    exit 1
}

# 检查启动服务器的脚本是否存在
if (-not (Test-Path $startServerScript)) {
    Write-Host "Error: Server startup script not found at $startServerScript"
    exit 1
}

# 启动游戏
Write-Host "Starting the game..."
try {
    Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$startGameScript`"" -NoNewWindow
    Write-Host "Game started successfully."
} catch {
    Write-Host "Failed to start the game. Please check the game startup script."
    exit 1
}

# 启动服务器
Write-Host "Starting the server..."
try {
    Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$startServerScript`"" -NoNewWindow
    Write-Host "Server started successfully."
} catch {
    Write-Host "Failed to start the server. Please check the server startup script."
    exit 1
}

Write-Host "Both the game and server have been started successfully."
