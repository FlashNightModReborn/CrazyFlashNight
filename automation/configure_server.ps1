# ============================================================
# CF7:ME 环境配置脚本
# 配置 Flash Player 信任目录（仅需运行一次）
# Node.js 不再需要 — V8 总线已内嵌于守护进程
# ============================================================

# 检查是否以管理员身份运行
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "Script not running as administrator. Restarting with elevated privileges..."
    Start-Process powershell.exe -ArgumentList ("-NoProfile", "-ExecutionPolicy Bypass", "-File `"" + $PSCommandPath + "`"") -Verb RunAs
    exit
}

# 设置 Flash Player 信任目录
Write-Host "Setting up Flash Player trust directory..."

$currentDir = Split-Path -Parent -Path $MyInvocation.MyCommand.Path
$resourcesDir = Split-Path -Parent $currentDir

Write-Host "Project directory: $resourcesDir"

if ($resourcesDir) {
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
    Write-Host "Failed to find the project directory. Exiting..."
    exit 1
}

Write-Host ""
Write-Host "Configuration complete."
Write-Host "You can now run start.ps1 to launch the game."
Write-Host "Press Enter to exit."
Read-Host
