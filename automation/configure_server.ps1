# 检查是否以管理员身份运行
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "Script not running as administrator. Restarting with elevated privileges..."
    Start-Process powershell.exe -ArgumentList ("-NoProfile", "-ExecutionPolicy Bypass", "-File `"" + $PSCommandPath + "`"") -Verb RunAs
    exit
}

# 检查Node.js是否已安装
Write-Host "Checking for Node.js installation..."
try {
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
        
        Write-Host "Downloading Node.js v20.12.2 from official website..."
        try {
            Invoke-WebRequest -Uri "https://nodejs.org/dist/v20.12.2/node-v20.12.2-x64.msi" -OutFile $installerPath -UseBasicParsing
            Write-Host "Download completed. Starting installation..."
            
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
    
    Write-Host "Downloading Node.js v20.12.2 from official website..."
    try {
        Invoke-WebRequest -Uri "https://nodejs.org/dist/v20.12.2/node-v20.12.2-x64.msi" -OutFile $installerPath -UseBasicParsing
        Write-Host "Download completed. Starting installation..."
        
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

# 因为脚本在 'automation' 文件夹中，'resources' 文件夹是其父目录
$resourcesDir = Split-Path -Parent $currentDir

Write-Host "Current directory: $currentDir"
Write-Host "Resources directory: $resourcesDir"

if ($resourcesDir) {
    Write-Host "Trust directory found: $resourcesDir"

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

Write-Host "Configuration process completed. Press Enter to exit."
Read-Host
