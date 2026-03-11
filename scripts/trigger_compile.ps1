$ErrorActionPreference = 'Stop'
[Console]::InputEncoding = [System.Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$OutputEncoding = [System.Text.UTF8Encoding]::new($false)

$ScriptDir = Split-Path -Parent $PSCommandPath
$ProjectDir = Split-Path -Parent $ScriptDir
$ErrorMarker = Join-Path $ScriptDir 'publish_error.marker'
$LoaderNames = @('cf7_compile_loader.jsfl', 'compile.jsfl')

function Convert-ToJsflUri {
    param([Parameter(Mandatory = $true)][string]$Path)

    $resolved = (Resolve-Path $Path).Path.Replace('\', '/')
    return 'file:///' + $resolved.Replace(':', '|')
}

function Fail {
    param([Parameter(Mandatory = $true)][string]$Message)

    Set-Content -Path $ErrorMarker -Value $Message -Encoding UTF8
    Write-Host ('[ERROR] {0}' -f $Message)
    exit 1
}

$cfgBase = Join-Path $env:LOCALAPPDATA 'Adobe\Flash CS6'
if (-not (Test-Path $cfgBase)) {
    Fail '找不到 Flash CS6 配置目录'
}

$expectedProjectUri = Convert-ToJsflUri $ProjectDir
$selectedLoader = $null
$fallbackLoader = $null

Get-ChildItem $cfgBase -Directory -ErrorAction SilentlyContinue | ForEach-Object {
    $commandsDir = Join-Path $_.FullName 'Configuration\Commands'
    if (-not (Test-Path $commandsDir)) {
        return
    }

    $projectCfg = Join-Path $commandsDir 'flash_project_path.cfg'
    $projectUri = if (Test-Path $projectCfg) {
        (Get-Content -Raw -Encoding UTF8 $projectCfg).Trim()
    } else {
        $null
    }

    foreach ($loaderName in $LoaderNames) {
        $candidate = Join-Path $commandsDir $loaderName
        if (-not (Test-Path $candidate)) {
            continue
        }

        if (-not $fallbackLoader) {
            $fallbackLoader = $candidate
        }

        if ($projectUri -eq $expectedProjectUri) {
            $selectedLoader = $candidate
            return
        }
    }
}

$loaderPath = if ($selectedLoader) { $selectedLoader } else { $fallbackLoader }
if (-not $loaderPath) {
    Fail '找不到可用的编译 JSFL Loader，请先运行 scripts/setup_compile_env.bat'
}

Write-Host ('[INFO] Opening: {0}' -f $loaderPath)
& cmd.exe /c start "" "$loaderPath"
if ($LASTEXITCODE -ne 0) {
    Fail ('cmd.exe 启动 JSFL 失败，退出码: {0}' -f $LASTEXITCODE)
}

Write-Host '[OK] JSFL opened'
exit 0
