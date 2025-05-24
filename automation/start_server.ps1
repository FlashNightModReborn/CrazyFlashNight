# 获取当前脚本所在的目录
$scriptDirectory = Split-Path -Parent -Path $MyInvocation.MyCommand.Path

# 定义配置服务器脚本的路径
$configureScriptPath = Join-Path $scriptDirectory "configure_server.ps1"

# 检查Node.js是否已安装
Write-Host "Checking for Node.js installation..."
try {
    $nodeVersion = & node -v 2>$null
} catch {
    $nodeVersion = $null
}

if (-not $nodeVersion) {
    Write-Host "Node.js is not installed or not functioning. Running the configuration script..."
    if (Test-Path $configureScriptPath) {
        Write-Host "Calling configure_server.ps1 to install Node.js and set up the environment..."
        # 调用配置脚本并等待执行完成
        try {
            & "$configureScriptPath"
            Write-Host "Configuration script executed successfully. Continuing with server startup..."
        } catch {
            Write-Host "Failed to run the configuration script. Please check the configuration script for issues."
            exit 1
        }
    } else {
        Write-Host "Configuration script not found at $configureScriptPath. Please check the file path."
        exit 1
    }
} else {
    Write-Host "Node.js is already installed. Current installed version: $nodeVersion"
}

# 搜索 'Local Server' 目录并启动服务器
Write-Host "Searching for the 'Local Server' directory containing server.js..."

function Find-ServerDir {
    param ([string]$dir)
    
    # 查找 Local Server 文件夹中的 server.js 文件
    $serverFilePath = Join-Path $dir "tools\Local Server\server.js"
    if (Test-Path -Path $serverFilePath) {
        return (Join-Path $dir "tools\Local Server")
    }

    return $null
}

# 获取当前脚本目录
$currentDir = Split-Path -Parent -Path $MyInvocation.MyCommand.Path

# Move one level up to the 'resources' directory
$resourcesDir = Split-Path -Parent $currentDir

# 从 'resources' 目录查找 'Local Server' 目录
$serverDir = Find-ServerDir -dir $resourcesDir

if ($serverDir) {
    Write-Host "Found 'server.js' in: $serverDir"
    Set-Location $serverDir

    if (Test-Path "server.js") {
        Write-Host "Starting the server..."
        try {
            Start-Process -FilePath "node.exe" -ArgumentList "server.js" -NoNewWindow -PassThru
            Write-Host "Server has been started successfully."
        } catch {
            Write-Host "Failed to start the server. Please check Node.js installation and server.js script."
            exit 1
        }
    } else {
        Write-Host "Server file 'server.js' not found in the expected directory."
        exit 1
    }
} else {
    Write-Host "Unable to find the 'Local Server' directory with 'server.js'."
    exit 1
}
