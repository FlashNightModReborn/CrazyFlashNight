# CF7 更新安装脚本
# 由 7z SFX 自解压后自动执行
param(
    [switch]$DeleteSelf
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$Host.UI.RawUI.WindowTitle = "闪客快打7 更新安装"

$STEAM_APP_ID = "2402310"
$GAME_DIR_NAME = "CRAZYFLASHER7StandAloneStarter"

function Write-Header {
    Write-Host ""
    Write-Host "  ===========================================" -ForegroundColor Cyan
    Write-Host "    闪客快打7重置计划 - 更新安装程序" -ForegroundColor Cyan
    Write-Host "  ===========================================" -ForegroundColor Cyan
    Write-Host ""
}

function Find-SteamLibraries {
    # 方法1: 注册表
    $steamPath = $null
    foreach ($key in @(
        "HKLM:\SOFTWARE\WOW6432Node\Valve\Steam",
        "HKLM:\SOFTWARE\Valve\Steam",
        "HKCU:\SOFTWARE\Valve\Steam"
    )) {
        try {
            $steamPath = (Get-ItemProperty -Path $key -Name InstallPath -ErrorAction SilentlyContinue).InstallPath
            if ($steamPath) { break }
        } catch {}
    }

    $libraries = @()

    if ($steamPath -and (Test-Path $steamPath)) {
        $libraries += $steamPath
        # 解析 libraryfolders.vdf 找额外库
        $vdf = Join-Path $steamPath "steamapps\libraryfolders.vdf"
        if (Test-Path $vdf) {
            $content = Get-Content $vdf -Raw
            $matches = [regex]::Matches($content, '"path"\s+"([^"]+)"')
            foreach ($m in $matches) {
                $lib = $m.Groups[1].Value -replace '\\\\', '\'
                if ($lib -ne $steamPath) { $libraries += $lib }
            }
        }
    }

    # 方法2: 常见路径
    foreach ($drive in (Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Free -ne $null })) {
        $common = @(
            "$($drive.Root)Steam",
            "$($drive.Root)Program Files\Steam",
            "$($drive.Root)Program Files (x86)\Steam",
            "$($drive.Root)SteamLibrary",
            "$($drive.Root)steam"
        )
        foreach ($p in $common) {
            if ((Test-Path $p) -and ($libraries -notcontains $p)) {
                $libraries += $p
            }
        }
    }

    return $libraries
}

function Find-GamePath {
    $libraries = Find-SteamLibraries
    Write-Host "  扫描 Steam 库..." -ForegroundColor Gray

    foreach ($lib in $libraries) {
        # 检查 appmanifest
        $manifest = Join-Path $lib "steamapps\appmanifest_$STEAM_APP_ID.acf"
        if (Test-Path $manifest) {
            $gamePath = Join-Path $lib "steamapps\common\$GAME_DIR_NAME"
            $exeCheck = Join-Path $gamePath "CrazyFlasher7StandAloneStarter.exe"
            if ((Test-Path $gamePath) -and (Test-Path $exeCheck)) {
                Write-Host "  找到游戏目录: $gamePath" -ForegroundColor Green
                return $gamePath
            }
        }
        # 直接检查目录
        $direct = Join-Path $lib "steamapps\common\$GAME_DIR_NAME"
        $exeCheck = Join-Path $direct "CrazyFlasher7StandAloneStarter.exe"
        if ((Test-Path $direct) -and (Test-Path $exeCheck)) {
            Write-Host "  找到游戏目录: $direct" -ForegroundColor Green
            return $direct
        }
    }

    return $null
}

function Select-FolderDialog {
    Add-Type -AssemblyName System.Windows.Forms
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = "请选择 $GAME_DIR_NAME 所在的文件夹"
    $dialog.ShowNewFolderButton = $false
    if ($dialog.ShowDialog() -eq "OK") {
        return $dialog.SelectedPath
    }
    return $null
}

function Install-Update {
    param([string]$GamePath)

    $scriptDir = Split-Path -Parent $MyInvocation.ScriptName
    $resourcesSrc = Join-Path $scriptDir "resources"
    $dataSrc = Join-Path $scriptDir "CrazyFlasher7StandAloneStarter_Data"

    # 统计文件数
    $fileCount = 0
    if (Test-Path $resourcesSrc) {
        $fileCount += (Get-ChildItem $resourcesSrc -Recurse -File).Count
    }
    if (Test-Path $dataSrc) {
        $fileCount += (Get-ChildItem $dataSrc -Recurse -File).Count
    }

    Write-Host ""
    Write-Host "  目标路径: $GamePath" -ForegroundColor White
    Write-Host "  文件数量: $fileCount" -ForegroundColor White
    Write-Host ""

    # 复制 resources/
    if (Test-Path $resourcesSrc) {
        $resDst = Join-Path $GamePath "resources"
        Write-Host "  正在更新 resources/ ..." -ForegroundColor Yellow
        Copy-Item -Path "$resourcesSrc\*" -Destination $resDst -Recurse -Force
        Write-Host "  resources/ 更新完成" -ForegroundColor Green
    }

    # 复制 _Data/
    if (Test-Path $dataSrc) {
        $dataDst = Join-Path $GamePath "CrazyFlasher7StandAloneStarter_Data"
        Write-Host "  正在更新 CrazyFlasher7StandAloneStarter_Data/ ..." -ForegroundColor Yellow
        Copy-Item -Path "$dataSrc\*" -Destination $dataDst -Recurse -Force
        Write-Host "  _Data/ 更新完成" -ForegroundColor Green
    }

    Write-Host ""
    Write-Host "  [OK] 安装完成！" -ForegroundColor Green
    Write-Host ""
}

# ── 主流程 ──

Write-Header

# 1. 自动定位
$gamePath = Find-GamePath

# 2. 找不到则手动选择
if (-not $gamePath) {
    Write-Host "  未能自动找到游戏目录。" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  请手动选择 $GAME_DIR_NAME 文件夹..." -ForegroundColor White
    $gamePath = Select-FolderDialog
    if (-not $gamePath) {
        Write-Host "  [X] 已取消。" -ForegroundColor Red
        Write-Host ""; Read-Host "  按 Enter 退出"
        exit 1
    }
}

# 3. 验证目录
$exePath = Join-Path $gamePath "CrazyFlasher7StandAloneStarter.exe"
if (-not (Test-Path $exePath)) {
    Write-Host "  [!] 目录中未找到 CrazyFlasher7StandAloneStarter.exe" -ForegroundColor Yellow
    Write-Host "  选择的路径: $gamePath" -ForegroundColor Gray
    Write-Host ""
    $confirm = Read-Host "  仍然继续？(y/N)"
    if ($confirm -ne "y" -and $confirm -ne "Y") {
        Write-Host "  已取消。" -ForegroundColor Red
        Write-Host ""; Read-Host "  按 Enter 退出"
        exit 1
    }
}

# 4. 确认安装
Write-Host ""
Write-Host "  即将更新: $gamePath" -ForegroundColor White
$confirm = Read-Host "  确认开始？(Y/n)"
if ($confirm -eq "n" -or $confirm -eq "N") {
    Write-Host "  已取消。" -ForegroundColor Red
    Write-Host ""; Read-Host "  按 Enter 退出"
    exit 1
}

# 5. 执行安装
Install-Update -GamePath $gamePath

# 6. 可选删除自身
$sfxExe = [System.Environment]::GetCommandLineArgs() | Where-Object { $_ -match '\.exe$' } | Select-Object -First 1
if ($DeleteSelf -and $sfxExe -and (Test-Path $sfxExe)) {
    Write-Host "  正在删除安装包..." -ForegroundColor Gray
    Start-Process cmd.exe -ArgumentList "/c ping 127.0.0.1 -n 2 >nul & del /f `"$sfxExe`"" -WindowStyle Hidden
} else {
    Write-Host "  提示: 安装包可以安全删除。" -ForegroundColor Gray
}

Write-Host ""
Read-Host "  按 Enter 退出"
