# 检查是否以管理员身份运行
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "Script not running as administrator. Restarting with elevated privileges..."
    Start-Process powershell.exe -ArgumentList ("-NoProfile", "-ExecutionPolicy Bypass", "-File `"" + $PSCommandPath + "`"") -Verb RunAs
    exit
}


# 开始设置过程
Write-Host "Starting the setup process..."

# 检查Node.js是否已安装
Write-Host "Checking for Node.js installation..."
try {
    # 获取Node.js版本，如果未安装将抛出异常
    $nodeVersion = & node -v 2>$null
} catch {
    $nodeVersion = $null
}

if ($LASTEXITCODE -eq 0 -and $nodeVersion) {
    Write-Host "Node.js is already installed."
    Write-Host "Current installed version: $nodeVersion"
    
    if ($nodeVersion -eq "v20.12.2") {
        Write-Host "Correct version of Node.js v20.12.2 is already installed."
    } else {
        Write-Host "Incorrect version found. Updating to v20.12.2..."
        $installerPath = Join-Path $env:TEMP "nodejs-installer.msi"
        
        # 下载Node.js安装包
        Write-Host "Downloading Node.js v20.12.2 from official website..."
        try {
            Invoke-WebRequest -Uri "https://nodejs.org/dist/v20.12.2/node-v20.12.2-x64.msi" -OutFile $installerPath -UseBasicParsing
            Write-Host "Download completed. Starting installation..."
            
            # 静默安装Node.js
            Start-Process msiexec.exe -ArgumentList "/i `"$installerPath`" /quiet /norestart" -Wait
            Write-Host "Node.js has been updated to v20.12.2."
        } catch {
            Write-Host "Failed to download or install Node.js. Please check your internet connection and permissions."
            exit 1
        }
    }
} else {
    Write-Host "Node.js is not installed. Installing now..."
    $installerPath = Join-Path $env:TEMP "nodejs-installer.msi"
    
    # 下载Node.js安装包
    Write-Host "Downloading Node.js v20.12.2 from official website..."
    try {
        Invoke-WebRequest -Uri "https://nodejs.org/dist/v20.12.2/node-v20.12.2-x64.msi" -OutFile $installerPath -UseBasicParsing
        Write-Host "Download completed. Starting installation..."
        
        # 静默安装Node.js
        Start-Process msiexec.exe -ArgumentList "/i `"$installerPath`" /quiet /norestart" -Wait
        Write-Host "Node.js has been installed."
    } catch {
        Write-Host "Failed to download or install Node.js. Please check your internet connection and permissions."
        exit 1
    }
}

# 设置Flash Player信任目录
Write-Host "Setting up Flash Player trust directory..."

# 获取当前脚本的目录
$currentDir = Split-Path -Parent -Path $MyInvocation.MyCommand.Path
Write-Host "Current directory: $currentDir"

# 递归查找 'resources' 目录的函数
function Find-ResourcesDir {
    param (
        [string]$dir
    )
    # 检查当前目录下是否存在 'resources' 目录
    $resourcesPath = Join-Path $dir "resources"
    if (Test-Path -Path $resourcesPath) {
        return $resourcesPath
    }
    # 获取父目录
    $parentDir = Split-Path -Parent -Path $dir
    # 如果父目录与当前目录不同，则继续递归查找
    if ($parentDir -ne $dir) {
        return Find-ResourcesDir -dir $parentDir
    } else {
        return $null
    }
}

# 调用函数查找 'resources' 目录
$resourcesDir = Find-ResourcesDir -dir $currentDir

if ($resourcesDir) {
    Write-Host "Trust directory found: $resourcesDir"

    # 设置Flash Player信任目录路径
    $flashTrustDir = "C:\Windows\SysWOW64\Macromed\Flash\FlashPlayerTrust"
    if (-not (Test-Path $flashTrustDir)) {
        try {
            New-Item -Path $flashTrustDir -ItemType Directory -Force | Out-Null
            Write-Host "Created Flash Player Trust directory: $flashTrustDir"
        } catch {
            Write-Host "Failed to create Flash Player Trust directory. Please check your permissions."
            exit 1
        }
    }

    # 创建或覆盖信任配置文件
    $trustFilePath = Join-Path $flashTrustDir "project.cfg"
    Write-Host "Writing trust directory to: $trustFilePath"
    try {
        Set-Content -Path $trustFilePath -Value $resourcesDir -Force
        Write-Host "Trust settings updated."
    } catch {
        Write-Host "Failed to write trust settings. Please check your permissions."
        exit 1
    }
} else {
    Write-Host "Failed to find the resources directory. Exiting..."
    exit 1
}

# 尝试定位 'Local Server' 目录并启动服务器
Write-Host "Searching for the 'Local Server' directory containing server.js..."

# 递归查找 'Local Server' 目录的函数
function Find-ServerDir {
    param (
        [string]$dir
    )
    # 检查当前目录下是否存在 'Local Server\server.js'
    $serverFilePath = Join-Path $dir "Local Server\server.js"
    if (Test-Path -Path $serverFilePath) {
        return (Join-Path $dir "Local Server")
    }
    # 获取父目录
    $parentDir = Split-Path -Parent -Path $dir
    # 如果父目录与当前目录不同，则继续递归查找
    if ($parentDir -ne $dir) {
        return Find-ServerDir -dir $parentDir
    } else {
        return $null
    }
}

# 调用函数查找 'Local Server' 目录
$serverDir = Find-ServerDir -dir $currentDir

if ($serverDir) {
    Write-Host "Found 'server.js' in: $serverDir"
    Set-Location $serverDir

    if (Test-Path "server.js") {
        Write-Host "Starting the server..."
        try {
            # 启动服务器进程
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
    Write-Host "Unable to find the 'Local Server' directory with 'server.js' in any parent directories."
    exit 1
}

Write-Host "Setup process completed."
