# 生成可直接装进 Steam resources 的每日包 zip（覆盖式安装，不需要 7-Zip）
# 用法：powershell -ExecutionPolicy Bypass -File sfx/build-windows-zip.ps1 [-PackOutput DIR] [-Version NAME] [-RagExe PATH] [-OutDir DIR] [-KeepStaging]
param(
    [string]$PackOutput = "",
    [string]$Version    = "",
    [string]$RagExe     = "",
    [string]$OutDir     = "",
    [switch]$KeepStaging
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.IO.Compression.FileSystem

$ToolRoot = Split-Path -Parent $PSScriptRoot
$SfxDir   = $PSScriptRoot

function Resolve-PackOutput {
    if ($PackOutput) {
        $resolved = (Resolve-Path $PackOutput).Path
        if (-not (Test-Path (Join-Path $resolved "CRAZYFLASHER7MercenaryEmpire.exe"))) {
            throw "指定目录不像打包产物（缺 CRAZYFLASHER7MercenaryEmpire.exe）：$resolved"
        }
        return $resolved
    }
    $candidates = @(Get-ChildItem (Join-Path $ToolRoot "output") -Directory -ErrorAction SilentlyContinue |
        Where-Object { Test-Path (Join-Path $_.FullName "CRAZYFLASHER7MercenaryEmpire.exe") } |
        Sort-Object LastWriteTime -Descending)
    if ($candidates.Count -eq 0) {
        throw "未找到打包产物，请先执行 npm run pack，或用 -PackOutput 指定目录"
    }
    return $candidates[0].FullName
}

$source = Resolve-PackOutput
if (-not $Version) { $Version = Split-Path $source -Leaf }
if (-not $OutDir)  { $OutDir  = Join-Path $ToolRoot "output" }
if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir | Out-Null }
$OutDir = (Resolve-Path $OutDir).Path

Write-Host "=== 构建 Steam 可安装每日包 ===" -ForegroundColor Cyan
Write-Host "  打包产物: $source"
Write-Host "  版本标记: $Version"

$staging = Join-Path $ToolRoot "sfx-staging-zip"
if (Test-Path $staging) { Remove-Item $staging -Recurse -Force }
$resStage = Join-Path $staging "resources"
New-Item -ItemType Directory -Path $resStage -Force | Out-Null

Write-Host "  复制运行树 -> resources/ ..."
Copy-Item -Path (Join-Path $source "*") -Destination $resStage -Recurse -Force

# 打包器与校验留下的副产物不进包
foreach ($junk in @(".cf7-packer-output", "logs")) {
    $p = Join-Path $resStage $junk
    if (Test-Path $p) { Remove-Item $p -Recurse -Force }
}
Get-ChildItem $resStage -Filter "*.zip" -File -ErrorAction SilentlyContinue | Remove-Item -Force

# Unity 外壳补丁（正版检测加固版 Assembly-CSharp.dll），只带 Managed 下这一个文件
$unityDll = Join-Path $ToolRoot "assets\CrazyFlasher7StandAloneStarter_Data\Managed\Assembly-CSharp.dll"
if (Test-Path $unityDll) {
    $managed = Join-Path $staging "CrazyFlasher7StandAloneStarter_Data\Managed"
    New-Item -ItemType Directory -Path $managed -Force | Out-Null
    Copy-Item $unityDll $managed -Force
    Write-Host "  已加入 Unity 外壳补丁"
}

Copy-Item (Join-Path $SfxDir "install.ps1") $staging -Force

if ($RagExe) {
    $rag = Get-Item $RagExe
    Copy-Item $rag.FullName $staging -Force
    Write-Host "  已加入终端程序: $($rag.Name)"
}

$bat = @'
@echo off
chcp 65001 >nul 2>&1
title 闪客快打7 每日包安装
setlocal
where powershell.exe >nul 2>&1
if errorlevel 1 (
    echo [X] 未检测到 PowerShell，无法继续。
    pause
    exit /b 1
)
powershell.exe -ExecutionPolicy Bypass -File "%~dp0install.ps1"
if errorlevel 1 pause
'@
Set-Content -Path (Join-Path $staging "安装更新.bat") -Value $bat -Encoding UTF8

$readme = @"
闪客快打7重置计划 每日包（$Version）

怎么装
1. 关掉正在运行的游戏。
2. 把本压缩包解压到任意位置（不要直接解压进 resources 里）。
3. 双击「安装更新.bat」，程序会自动找到 Steam 里的游戏目录，确认后开始覆盖更新。
   找不到时按提示手动选择 CRAZYFLASHER7StandAloneStarter 文件夹。
4. 装完从 Steam 启动游戏。

安装做了什么
- 把 resources\ 里的新版本文件覆盖到游戏目录的 resources\ 下，不删除里面原有的其它文件。
- 用补丁版 Assembly-CSharp.dll 覆盖 CrazyFlasher7StandAloneStarter_Data\Managed\ 下的同名文件。
- 如果包里有 CFN-RAG-v*.exe，会放到 resources 的上一级（游戏根目录），供游戏内终端使用。

注意
- 覆盖式安装，不要先清空 resources，否则会丢掉原版底座里的其它文件。
- 玩家存档不会被改动。
"@
Set-Content -Path (Join-Path $staging "使用说明.txt") -Value $readme -Encoding UTF8

$zipPath = Join-Path $OutDir ("CF7-每日包-{0}.zip" -f $Version)
if (Test-Path $zipPath) { Remove-Item $zipPath -Force }

Write-Host "  压缩中（约 2 GB，需要一点时间）..."
[System.IO.Compression.ZipFile]::CreateFromDirectory(
    $staging,
    $zipPath,
    [System.IO.Compression.CompressionLevel]::Optimal,
    $false)

# 产物自检：结构、关键入口、中文名 UTF-8 标志
$zip = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
try {
    $entries = $zip.Entries
    # .NET 读取时会把条目分隔符归一成反斜杠，比较前统一
    $norm = @($entries | ForEach-Object { $_.FullName.Replace('\', '/') })
    $hasBootstrap = $norm -contains "resources/CRAZYFLASHER7MercenaryEmpire.exe"
    $hasInstaller = $norm -contains "install.ps1"
    $hasBat = $norm -contains "安装更新.bat"
    Write-Host ("  条目: {0}，未压缩合计: {1:N2} GB" -f $entries.Count, (($entries | Measure-Object Length -Sum).Sum / 1GB))
    if (-not $hasBootstrap) { throw "zip 内缺 resources/CRAZYFLASHER7MercenaryEmpire.exe" }
    if (-not $hasInstaller) { throw "zip 内缺 install.ps1" }
    if (-not $hasBat) { throw "zip 内缺 安装更新.bat" }
    $nonAscii = @($norm | Where-Object { ($_.ToCharArray() | Where-Object { [int]$_ -gt 127 }).Count -gt 0 })
    Write-Host ("  中文名条目: {0}（UTF-8 文件名，Explorer/7-Zip 解压不乱码）" -f $nonAscii.Count)
} finally {
    $zip.Dispose()
}

if (-not $KeepStaging) { Remove-Item $staging -Recurse -Force }

$sizeGB = (Get-Item $zipPath).Length / 1GB
Write-Host ("完成: {0} （{1:N2} GB）" -f $zipPath, $sizeGB) -ForegroundColor Green
