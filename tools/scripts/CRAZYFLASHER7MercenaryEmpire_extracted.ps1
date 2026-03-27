$scriptDirectory = (Get-Location)

# 定义默认的 Flash Player 和 SWF 文件名称

$flashPlayerDefault = "Adobe Flash Player 20.exe"

$swfDefault = "CRAZYFLASHER7MercenaryEmpire.swf"

# 检查配置文件是否存在，如果存在则读取

$configFilePath = "$scriptDirectory\config.toml"

$flashPlayerPath = ""

$swfPath = ""

if (Test-Path $configFilePath) {

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

# 如果在配置文件中未指定路径，则使用默认值

if (-not $flashPlayerPath) {

    $flashPlayerPath = "$scriptDirectory\$flashPlayerDefault"

}

if (-not $swfPath) {

    $swfPath = "$scriptDirectory\$swfDefault"

}

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

Start-Process -FilePath $flashPlayerPath -ArgumentList $swfPath -NoNewWindow