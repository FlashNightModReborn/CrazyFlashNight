# CF7 更新安装脚本
# 由 7z SFX 自解压后自动执行，或从 zip 包内的「安装更新.bat」直接调用
param(
    [switch]$DeleteSelf,
    [string]$GamePath = "",
    [switch]$NoPause,
    [ValidateRange(1, 600)][int]$VerifyTimeoutSeconds = 120
)

$ErrorActionPreference = "Stop"

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

# 以下只读函数也由 ZIP 构建入口点加载；点加载不定位 Steam、不执行安装。
function Assert-Cf7File([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf) -or (Get-Item -LiteralPath $Path).Length -eq 0) {
        throw "必需文件缺失或为空：$Path"
    }
}

function Get-Cf7Files([string]$Root) {
    if (-not (Test-Path -LiteralPath $Root -PathType Container)) { throw "目录不存在：$Root" }
    if ((Get-Item -LiteralPath $Root -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {
        throw "不接受链接目录：$Root"
    }
    foreach ($item in Get-ChildItem -LiteralPath $Root -Force) {
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "不接受链接：$($item.FullName)" }
        if ($item.PSIsContainer) { Get-Cf7Files $item.FullName } else { $item }
    }
}

function Test-Cf7PrivatePath([string]$Relative) {
    $p = $Relative.Replace('\', '/')
    return $p -match '^(?:data/rag(?:/|$)|saves(?:/|$)|launcher/webview2[^/]*userdata(?:/|$))|(?:^|/)(?:agent_tasks\.json|agent_text\.json|launcher_user_prefs\.json|\.env(?:\.[^/]*)?|credentials(?:\.[^/]*)?|secrets?(?:\.[^/]*)?|id_rsa|id_ed25519)$|\.(?:sol|db(?:-wal|-shm|-journal)?|sqlite3?(?:-wal|-shm|-journal)?|pfx|p12|pem|key)$|\.(?:local|user)\.(?:json|toml|xml|ya?ml)$'
}

function Get-Cf7RuntimeInventory([string]$Root, [switch]$AllowLegacy) {
    $manifest = Join-Path $Root 'runtime/cf7-runtime-manifest.tsv'
    Assert-Cf7File $manifest
    $lines = @([IO.File]::ReadAllLines($manifest) | Where-Object { $_ -ne '' })
    if ($lines[0] -ne 'cf7-runtime-manifest-v2' -and -not ($AllowLegacy -and $lines[0] -eq 'cf7-runtime-manifest-v1')) {
        throw "不支持的 runtime manifest：$manifest"
    }
    $seen = @{}
    $metadata = @{}
    $rows = @()
    foreach ($line in $lines | Select-Object -Skip 1) {
        $parts = @($line -split "`t")
        if ($parts.Count -eq 2 -and $parts[0] -in @('publishMode','sourceTreeHash','artifactSourceHash','producerRecipeHash','toolchainLockHash','toolchainBaseline','buildIdentityHash','payloadClosureHash')) {
            if ($metadata.ContainsKey($parts[0])) { throw "重复 manifest 元数据：$line" }
            $metadata[$parts[0]] = $parts[1]
            continue
        }
        if ($parts.Count -ne 4 -or $parts[0] -ne 'file') { throw "非法 manifest 行：$line" }
        $p = $parts[1]
        if ($p -cnotmatch '^(?:CRAZYFLASHER7MercenaryEmpire\.exe|runtime/[A-Za-z0-9_.() -]+(?:/[A-Za-z0-9_.() -]+)*)$' -or
            $p -match '(^|/)\.{1,2}(/|$)' -or $p -eq 'runtime/cf7-runtime-manifest.tsv' -or $seen.ContainsKey($p)) {
            throw "非法或重复 runtime 路径：$p"
        }
        $size = 0L
        if ($parts[2] -notmatch '^\d+$' -or -not [Int64]::TryParse($parts[2], [ref]$size) -or $parts[3] -notmatch '^[0-9A-Fa-f]{64}$') {
            throw "非法 runtime 大小或 SHA256：$line"
        }
        $seen[$p] = $true
        $rows += [pscustomobject]@{ Path=$p; Size=$size; Hash=$parts[3] }
    }
    if (-not $seen.ContainsKey('CRAZYFLASHER7MercenaryEmpire.exe')) { throw 'manifest 缺 bootstrap' }
    return [pscustomobject]@{ Rows=$rows; Metadata=$metadata }
}

function Assert-Cf7Runtime([string]$Root) {
    $inventory = Get-Cf7RuntimeInventory $Root
    $expected = @{'runtime/cf7-runtime-manifest.tsv'=$true}
    foreach ($row in $inventory.Rows) {
        $file = Join-Path $Root $row.Path
        Assert-Cf7File $file
        if ((Get-Item -LiteralPath $file).Length -ne $row.Size -or (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash -ne $row.Hash) {
            throw "runtime 大小/SHA256 不符：$($row.Path)"
        }
        $expected[$row.Path] = $true
    }
    foreach ($file in Get-Cf7Files (Join-Path $Root 'runtime')) {
        $rel = $file.FullName.Substring($Root.TrimEnd('\','/').Length + 1).Replace('\','/')
        if (-not $expected.ContainsKey($rel)) { throw "未声明 runtime 文件：$rel" }
    }
    $consensusPath = Join-Path $Root 'config/build/runtime-release-consensus.json'
    Assert-Cf7File $consensusPath
    $consensus = Get-Content -LiteralPath $consensusPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($consensus.schema -ne 'cf7-runtime-release-consensus.v2') { throw '需要 v2 consensus' }
    foreach ($key in @('artifactSourceHash','producerRecipeHash','toolchainLockHash','buildIdentityHash','payloadClosureHash')) {
        if ([string]$consensus.$key -notmatch '^[0-9A-Fa-f]{64}$' -or $consensus.$key -ne $inventory.Metadata[$key]) {
            throw "consensus 与 manifest 不符：$key"
        }
    }
    if ($consensus.manifestSha256 -ne (Get-FileHash -LiteralPath (Join-Path $Root 'runtime/cf7-runtime-manifest.tsv') -Algorithm SHA256).Hash) {
        throw 'consensus manifestSha256 不符'
    }
}

function Invoke-Cf7BootstrapVerify([string]$Root, [int]$TimeoutSeconds = 120) {
    $exe = Join-Path $Root 'CRAZYFLASHER7MercenaryEmpire.exe'
    Assert-Cf7File $exe
    # 不用 ShellExecute；保留真实进程句柄，避免 GUI exe 提前返回/ExitCode 为空。
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = $exe
    $info.Arguments = '--verify-only'
    $info.WorkingDirectory = $Root
    $info.UseShellExecute = $false
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $info
    try {
        if (-not $process.Start()) { throw 'bootstrap 校验进程未启动' }
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            $process.Kill()
            if (-not $process.WaitForExit(5000)) { throw 'bootstrap 超时且未退出；保留备份，禁止重试' }
            throw "bootstrap --verify-only 超时（$TimeoutSeconds 秒）"
        }
        if ($process.ExitCode -ne 0) { throw "bootstrap --verify-only exit code=$($process.ExitCode)；检查 resources/logs/bootstrap.log" }
    } finally { $process.Dispose() }
}

function Install-Update {
    param([string]$GamePath)
    $scriptDir = $PSScriptRoot
    $resourcesSrc = Join-Path $scriptDir 'resources'
    $GamePath = [IO.Path]::GetFullPath($GamePath).TrimEnd('\','/')
    if ($scriptDir.StartsWith($GamePath + '\', [StringComparison]::OrdinalIgnoreCase) -or
        ($GamePath + '\').StartsWith($scriptDir.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw '请先把安装包完整解压到游戏目录以外'
    }
    if (@(Get-ChildItem -LiteralPath $GamePath -Force -Filter '.cf7-update-backup-*').Count) {
        throw '发现上轮安装备份；请先核对恢复结果，不自动覆盖或清除备份'
    }
    Assert-Cf7Runtime $resourcesSrc
    if (Test-Path -LiteralPath (Join-Path $resourcesSrc 'data/rag')) { throw 'data/rag 不得进包' }
    $files = @(Get-Cf7Files $resourcesSrc)
    $copy = @{}
    foreach ($file in $files) {
        $rel = $file.FullName.Substring($resourcesSrc.Length + 1).Replace('\','/')
        if (Test-Cf7PrivatePath $rel) { throw "包内含玩家状态或凭据：$rel" }
        $copy['resources/' + $rel] = $file.FullName
    }
    $unityRel = 'CrazyFlasher7StandAloneStarter_Data/Managed/Assembly-CSharp.dll'
    Assert-Cf7File (Join-Path $scriptDir $unityRel)
    $copy[$unityRel] = Join-Path $scriptDir $unityRel
    $ragExes = @(Get-ChildItem -LiteralPath $scriptDir -Filter '*.exe' -File)
    if ($ragExes.Count -ne 1 -or $ragExes[0].Name -cnotmatch '^CFN-RAG-v\d+\.\d+\.\d+\.exe$') {
        throw '包内必须且只能有一个 CFN-RAG-v<主>.<次>.<补丁>.exe 终端程序'
    }
    Assert-Cf7File $ragExes[0].FullName
    $copy[$ragExes[0].Name] = $ragExes[0].FullName

    # 旧 manifest 仅授予局部文件移除范围，绝不清空 resources/runtime 或 resources。
    $resDst = Join-Path $GamePath 'resources'
    $owned = @{}
    foreach ($row in (Get-Cf7RuntimeInventory $resourcesSrc).Rows) { $owned[$row.Path] = $true }
    $obsolete = @()
    if (Test-Path -LiteralPath (Join-Path $resDst 'runtime/cf7-runtime-manifest.tsv')) {
        foreach ($row in (Get-Cf7RuntimeInventory $resDst -AllowLegacy).Rows) {
            $owned[$row.Path] = $true
            if (-not $copy.ContainsKey('resources/' + $row.Path)) { $obsolete += 'resources/' + $row.Path }
        }
    }
    if (Test-Path -LiteralPath (Join-Path $resDst 'runtime')) {
        foreach ($file in Get-Cf7Files (Join-Path $resDst 'runtime')) {
            $rel = $file.FullName.Substring($resDst.Length + 1).Replace('\','/')
            if ($rel -ne 'runtime/cf7-runtime-manifest.tsv' -and -not $owned.ContainsKey($rel)) {
                throw "旧 runtime 含未声明文件（保留、不猜测删除）：$rel"
            }
        }
    }
    # 避免 launch_rag.bat 的通配命中旧终端；只移动合法版本名，不动其它 exe。
    foreach ($file in Get-ChildItem -LiteralPath $GamePath -Filter 'CFN-RAG-v*.exe' -File) {
        if ($file.Name -cnotmatch '^CFN-RAG-v\d+\.\d+\.\d+\.exe$') { throw "旧终端命名异常，请人工核对：$($file.Name)" }
        if (-not $copy.ContainsKey($file.Name)) { $obsolete += $file.Name }
    }
    $changes = @(@($copy.Keys) + $obsolete | Sort-Object -Unique)
    # 逐条预检目标及其父路径，拒绝目录冲突和 junction，防止写到玩家路径外。
    foreach ($rel in $changes) {
        $dest = Join-Path $GamePath $rel
        if (Test-Path -LiteralPath $dest -PathType Container) { throw "目标文件被目录占用：$dest" }
        $p = $dest
        while ($p.Length -ge $GamePath.Length) {
            if ((Test-Path -LiteralPath $p) -and ((Get-Item -LiteralPath $p -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
                throw "目标含链接，停止安装：$p"
            }
            $p = Split-Path -Parent $p
        }
    }
    $backup = Join-Path $GamePath ('.cf7-update-backup-' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $backup | Out-Null
    $changed = New-Object 'System.Collections.Generic.List[string]'
    # 中断时留下原文件和清单供人工恢复；下次安装不自动吞掉未知状态。
    @($changes | ForEach-Object { [pscustomobject]@{ path=$_; existed=(Test-Path -LiteralPath (Join-Path $GamePath $_)) } }) |
        ConvertTo-Json -Depth 3 | Set-Content -LiteralPath (Join-Path $backup 'files.json') -Encoding UTF8
    try {
        foreach ($rel in $changes) {
            $dest = Join-Path $GamePath $rel
            if (Test-Path -LiteralPath $dest) {
                $saved = Join-Path $backup $rel
                New-Item -ItemType Directory -Path (Split-Path -Parent $saved) -Force | Out-Null
                Move-Item -LiteralPath $dest -Destination $saved
            }
            $changed.Add($rel)
            if ($copy.ContainsKey($rel)) {
                New-Item -ItemType Directory -Path (Split-Path -Parent $dest) -Force | Out-Null
                Copy-Item -LiteralPath $copy[$rel] -Destination $dest
            }
        }
        Assert-Cf7Runtime $resDst
        foreach ($rel in @($unityRel, $ragExes[0].Name)) {
            if ((Get-FileHash -LiteralPath $copy[$rel] -Algorithm SHA256).Hash -ne (Get-FileHash -LiteralPath (Join-Path $GamePath $rel) -Algorithm SHA256).Hash) {
                throw "安装后字节不一致：$rel"
            }
        }
        Invoke-Cf7BootstrapVerify $resDst $VerifyTimeoutSeconds
    } catch {
        $failure = $_.Exception.Message
        $restoreErrors = @()
        for ($i = $changed.Count - 1; $i -ge 0; $i--) {
            $rel = $changed[$i]
            try {
                $dest = Join-Path $GamePath $rel
                if (Test-Path -LiteralPath $dest -PathType Leaf) { Remove-Item -LiteralPath $dest -Force }
                $saved = Join-Path $backup $rel
                if (Test-Path -LiteralPath $saved -PathType Leaf) { Move-Item -LiteralPath $saved -Destination $dest }
            } catch { $restoreErrors += "$rel : $($_.Exception.Message)" }
        }
        throw "安装失败：$failure；已尝试逐文件恢复。备份/清单位于 $backup；恢复错误：$($restoreErrors -join '; ')"
    }
    Remove-Item -LiteralPath $backup -Recurse -Force
    Write-Host '  [OK] 安装完成，bootstrap --verify-only exit code=0（不代表实机可玩验收）' -ForegroundColor Green
}

# ── 主流程 ──
if ($MyInvocation.InvocationName -eq '.') { return }
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$Host.UI.RawUI.WindowTitle = '闪客快打7 更新安装'
if ([Environment]::OSVersion.Version.Major -lt 10) { throw '最低要求 Windows 10' }

Write-Header

# 1. 定位安装目标：显式指定优先，否则自动扫描 Steam 库
if ($GamePath) {
    $gamePath = (Resolve-Path $GamePath).Path
    Write-Host "  使用指定游戏目录: $gamePath" -ForegroundColor Gray
} else {
    $gamePath = Find-GamePath
}

# 2. 找不到则手动选择
if (-not $gamePath) {
    Write-Host "  未能自动找到游戏目录。" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  请手动选择 $GAME_DIR_NAME 文件夹..." -ForegroundColor White
    $gamePath = Select-FolderDialog
    if (-not $gamePath) {
        Write-Host "  [X] 已取消。" -ForegroundColor Red
        if (-not $NoPause) { Write-Host ""; Read-Host "  按 Enter 退出" }
        exit 1
    }
}

# 3. 验证目录
$exePath = Join-Path $gamePath "CrazyFlasher7StandAloneStarter.exe"
if (-not (Test-Path $exePath)) {
    Write-Host "  [!] 目录中未找到 CrazyFlasher7StandAloneStarter.exe" -ForegroundColor Yellow
    Write-Host "  选择的路径: $gamePath" -ForegroundColor Gray
    if ($NoPause) { throw "目标目录不是 Steam 版游戏目录：$gamePath" }
    Write-Host ""
    $confirm = Read-Host "  仍然继续？(y/N)"
    if ($confirm -ne "y" -and $confirm -ne "Y") {
        Write-Host "  已取消。" -ForegroundColor Red
        Write-Host ""; Read-Host "  按 Enter 退出"
        exit 1
    }
}

# 4. 确认安装
if (-not $NoPause) {
    Write-Host ""
    Write-Host "  即将更新: $gamePath" -ForegroundColor White
    $confirm = Read-Host "  确认开始？(Y/n)"
    if ($confirm -eq "n" -or $confirm -eq "N") {
        Write-Host "  已取消。" -ForegroundColor Red
        Write-Host ""; Read-Host "  按 Enter 退出"
        exit 1
    }
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
if (-not $NoPause) { Read-Host "  按 Enter 退出" }
