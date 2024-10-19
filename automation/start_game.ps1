# 定义允许的执行策略级别（可以运行脚本的策略）
$acceptablePolicies = @('RemoteSigned', 'Unrestricted', 'Bypass')

# 获取当前执行策略
$currentPolicy = Get-ExecutionPolicy

# 检查当前执行策略是否足够宽松
if ($acceptablePolicies -contains $currentPolicy) {
    Write-Host "Execution Policy is acceptable: $currentPolicy"
} else {
    Write-Host "Current Execution Policy ($currentPolicy) is not acceptable. Attempting to change it to Bypass."

    # 检查是否以管理员身份运行
    if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
        Write-Host "Script not running as administrator. Restarting with elevated privileges..."

        # 使用管理员权限重新启动 PowerShell，并设置执行策略为 Bypass
        Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"" + $PSCommandPath + "`"" -Verb RunAs
        exit
    } else {
        # 如果已经是管理员身份，则直接更改执行策略
        Set-ExecutionPolicy Bypass -Scope Process -Force
        Write-Host "Execution Policy has been temporarily set to Bypass for this session."
    }
}

# 获取当前脚本所在的目录 (automation directory)
$scriptDirectory = Split-Path -Parent -Path $MyInvocation.MyCommand.Path

# 定义默认的 Flash Player 和 SWF 文件名称
$flashPlayerDefault = "Adobe Flash Player 20.exe"
$swfDefault = "CRAZYFLASHER7MercenaryEmpire.swf"

# 计算相对于 automation 的路径 (resources)
$resourcesDir = Split-Path -Parent $scriptDirectory  # 获取上一级目录，也就是 resources 目录

# 配置文件位于 automation 目录中
$configFilePath = "$scriptDirectory\config.toml"
$flashPlayerPath = ""
$swfPath = ""

if (Test-Path $configFilePath) {
    Write-Host "Reading configuration from: $configFilePath"
    # 读取 TOML 文件的内容
    $config = Get-Content $configFilePath

    # 提取 flashPlayerPath 和 swfPath 的值
    foreach ($line in $config) {
        if ($line -like "flashPlayerPath =*") {
            $flashPlayerPath = $line -replace 'flashPlayerPath = ', '' -replace '"', ''
        } elseif ($line -like "swfPath =*") {
            $swfPath = $line -replace 'swfPath = ', '' -replace '"', ''
        }
    }
}

# 如果在配置文件中未指定路径，则使用默认值 (附加到 resources 目录)
if (-not $flashPlayerPath) {
    $flashPlayerPath = Join-Path $resourcesDir $flashPlayerDefault
} else {
    if (-not [System.IO.Path]::IsPathRooted($flashPlayerPath)) {
        $flashPlayerPath = Join-Path $resourcesDir $flashPlayerPath
    }
}

if (-not $swfPath) {
    $swfPath = Join-Path $resourcesDir $swfDefault
} else {
    if (-not [System.IO.Path]::IsPathRooted($swfPath)) {
        $swfPath = Join-Path $resourcesDir $swfPath
    }
}

# 输出路径进行调试
Write-Host "Flash Player Path: $flashPlayerPath"
Write-Host "SWF Path: $swfPath"

# 检查 Flash Player 和 SWF 文件是否存在
if (-not (Test-Path $flashPlayerPath)) {
    Write-Host "Error: Flash Player executable not found at $flashPlayerPath"
    exit 1
}

if (-not (Test-Path $swfPath)) {
    Write-Host "Error: SWF file not found at $swfPath"
    exit 1
}

# 启动 Flash Player 并加载 SWF 文件，但不隐藏 Flash Player 窗口
Write-Host "Starting Flash Player with SWF..."
try {
    Start-Process -FilePath $flashPlayerPath -ArgumentList $swfPath -NoNewWindow
    Write-Host "Game has been started successfully."
} catch {
    Write-Host "Error: Failed to start Flash Player. $_"
    exit 1
}

# 等待用户输入，防止窗口关闭
Write-Host "Press Enter to exit..."
Read-Host
