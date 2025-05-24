# 脚本目录
$scriptDirectory = "C:\Program Files (x86)\Steam\steamapps\common\CRAZYFLASHER7StandAloneStarter\resources\automation"

# 配置文件路径
$configFilePath = Join-Path -Path $scriptDirectory -ChildPath "config.toml"

# 默认的 Flash Player 和文件名称
$flashPlayerDefault = "Adobe Flash Player 20.exe"
$swfDefault = "CRAZYFLASHER7MercenaryEmpire.swf"
$exeDefault = "CRAZYFLASHER7MercenaryEmpire.exe"
$saveFolderName = "saves"

# Flash 存档路径
try {
    $defaultFlashSavePath = Join-Path -Path ([Environment]::GetFolderPath("ApplicationData")) -ChildPath "Macromedia\Flash Player\#SharedObjects"
} catch {
    Write-Host "Error: Unable to determine default Flash save path. Please specify manually."
    $defaultFlashSavePath = Read-Host "Enter Flash save path manually"
}

# 初始化变量
$flashPlayerPath = ""
$swfPath = ""
$exePath = ""
$userChoice = ""

# 读取配置文件
if (Test-Path $configFilePath) {
    $config = Get-Content $configFilePath
    foreach ($line in $config) {
        if ($line -like "flashPlayerPath =*") {
            $flashPlayerPath = $line -replace 'flashPlayerPath = ', '' -replace '"', ''
        } elseif ($line -like "swfPath =*") {
            $swfPath = $line -replace 'swfPath = ', '' -replace '"', ''
        } elseif ($line -like "exePath =*") {
            $exePath = $line -replace 'exePath = ', '' -replace '"', ''
        } elseif ($line -like "userChoice =*") {
            $userChoice = $line -replace 'userChoice = ', '' -replace '"', ''
        }
    }
}

# 如果配置文件中没有提供路径，则使用默认值
if (-not $flashPlayerPath) {
    $flashPlayerPath = Join-Path -Path $scriptDirectory -ChildPath $flashPlayerDefault
}
if (-not $swfPath) {
    $swfPath = Join-Path -Path $scriptDirectory -ChildPath $swfDefault
}
if (-not $exePath) {
    $exePath = Join-Path -Path $scriptDirectory -ChildPath $exeDefault
}

# 验证路径是否存在
if (-not (Test-Path $flashPlayerPath)) {
    Write-Host "Error: Flash Player executable not found at $flashPlayerPath"
    exit 1
}

if (-not (Test-Path $swfPath)) {
    Write-Host "Error: SWF file not found at $swfPath"
    exit 1
}

if (-not (Test-Path $exePath)) {
    Write-Host "Warning: EXE file not found at $exePath. Continuing without EXE path."
}

# 存档路径映射
try {
    $domainPath = Join-Path -Path $defaultFlashSavePath -ChildPath "localhost"
    $swfSavePath = Join-Path -Path $domainPath -ChildPath (Split-Path -Leaf $swfPath)
} catch {
    Write-Host "Error: Failed to construct SWF save path. Please verify the configuration."
    exit 1
}

$exeSavePath = if ($exePath) { Join-Path -Path (Split-Path -Path $exePath) -ChildPath $saveFolderName } else { "" }

# 检查存档映射
if ((Test-Path $exeSavePath) -and (-not (Test-Path $swfSavePath))) {
    Write-Host "Detected saves in EXE path but not in SWF path. Copying saves..."
    New-Item -ItemType Directory -Path $swfSavePath -Force
    Copy-Item -Path $exeSavePath\* -Destination $swfSavePath -Recurse -Force
} elseif ((Test-Path $exeSavePath) -and (Test-Path $swfSavePath)) {
    if (-not $userChoice) {
        # 提示用户选择
        Write-Host "Both EXE and SWF paths have saves. Please choose an option:"
        Write-Host "1. Use EXE saves and overwrite SWF saves."
        Write-Host "2. Keep SWF saves and ignore EXE saves."
        $userChoice = Read-Host "Enter your choice (1 or 2)"
        
        # 验证用户输入
        if ($userChoice -notin "1", "2") {
            Write-Host "Invalid choice. Exiting."
            exit 1
        }

        # 记录用户选择到配置文件
        Add-Content -Path $configFilePath -Value "userChoice = `"$userChoice`""        
    }

    # 根据用户选择处理
    if ($userChoice -eq "1") {
        Write-Host "Overwriting SWF saves with EXE saves..."
        Copy-Item -Path $exeSavePath\* -Destination $swfSavePath -Recurse -Force
    } elseif ($userChoice -eq "2") {
        Write-Host "Keeping SWF saves and ignoring EXE saves..."
    }
} else {
    Write-Host "No saves conflict detected. Proceeding with default paths."
}

# 启动 Flash Player 并加载 SWF 文件
Write-Host "Starting Flash Player with SWF file..."
Start-Process -FilePath $flashPlayerPath -ArgumentList $swfPath -NoNewWindow

# 暂停脚本以查看日志
Write-Host "Press Enter to exit."
Read-Host
