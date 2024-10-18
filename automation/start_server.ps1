# 检查是否以管理员身份运行
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "Script not running as administrator. Restarting with elevated privileges..."
    Start-Process powershell.exe -ArgumentList ("-NoProfile", "-ExecutionPolicy Bypass", "-File `"" + $PSCommandPath + "`"") -Verb RunAs
    exit
}

Write-Host "Searching for the 'Local Server' directory containing server.js..."

function Find-ServerDir {
    param ([string]$dir)
    $serverFilePath = Join-Path $dir "Local Server\server.js"
    if (Test-Path -Path $serverFilePath) {
        return (Join-Path $dir "Local Server")
    }
    $parentDir = Split-Path -Parent -Path $dir
    if ($parentDir -ne $dir) {
        return Find-ServerDir -dir $parentDir
    } else {
        return $null
    }
}

$currentDir = Split-Path -Parent -Path $MyInvocation.MyCommand.Path
$serverDir = Find-ServerDir -dir $currentDir

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
    Write-Host "Unable to find the 'Local Server' directory with 'server.js' in any parent directories."
    exit 1
}
