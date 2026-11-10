# 生成当前 worktree 的 Steam 每日 ZIP；不复用历史 PackOutput，不执行发布。
[CmdletBinding()]
param(
    [string]$Version = '',
    [string]$RagExe = '',
    [string]$OutDir = '',
    [switch]$KeepStaging
)

$ErrorActionPreference = 'Stop'
# ZipArchiveMode/ZipFileExtensions 分属两个程序集，缺一个就会在写条目时 TypeNotFound。
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$ToolRoot = Split-Path -Parent $PSScriptRoot
$RepoRoot = [IO.Path]::GetFullPath((Join-Path $ToolRoot '../..'))
$audit = Join-Path $ToolRoot 'scripts/audit-runtime-closure.mjs'
$installer = Join-Path $PSScriptRoot 'install.ps1'
$unityRel = 'CrazyFlasher7StandAloneStarter_Data/Managed/Assembly-CSharp.dll'
$unityDll = Join-Path (Join-Path $ToolRoot 'assets') $unityRel

# 缺依赖立即失败，不能在门禁不存在时继续出包。
foreach ($required in @($audit, $installer, $unityDll, (Join-Path $RepoRoot 'tools/verify-runtime-bundle-v2.ps1'))) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf) -or (Get-Item -LiteralPath $required).Length -eq 0) {
        throw "必需资产/审计缺失或为空：$required"
    }
}
. $installer
if (-not $RagExe) { throw '必须显式指定 -RagExe，例如当前配套的 CFN-RAG-v<主>.<次>.<补丁>.exe' }
Assert-Cf7File $RagExe
$rag = Get-Item -LiteralPath $RagExe
if ($rag.Name -cnotmatch '^CFN-RAG-v\d+\.\d+\.\d+\.exe$') {
    throw '终端文件名必须为 CFN-RAG-v<主>.<次>.<补丁>.exe，收到：' + $rag.Name
}
$ragHash = (Get-FileHash -LiteralPath $rag.FullName -Algorithm SHA256).Hash
$unityHash = (Get-FileHash -LiteralPath $unityDll -Algorithm SHA256).Hash
foreach ($command in @('node', 'npm.cmd', 'powershell.exe')) {
    if (-not (Get-Command $command -ErrorAction SilentlyContinue)) { throw "缺少构建依赖：$command" }
}
if (-not $Version) { $Version = Get-Date -Format 'yyyy-MM-dd' }
if ($Version -notmatch '^[\p{L}\p{N}][\p{L}\p{N}._-]*$' -or $Version.EndsWith('.')) { throw 'Version 必须是安全的单段文件名' }
if (-not $OutDir) { $OutDir = Join-Path $ToolRoot 'output' }
$OutDir = [IO.Path]::GetFullPath($OutDir)
$zipPath = Join-Path $OutDir ("CF7-每日包-{0}.zip" -f $Version)
# 不提前删除已有交付包，避免失败时把旧包也弄丢。
if (Test-Path -LiteralPath $zipPath) { throw "目标 ZIP 已存在，请使用不同 Version/OutDir：$zipPath" }
New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
$work = Join-Path (Join-Path $ToolRoot 'output') ('.zip-build-' + [Guid]::NewGuid().ToString('N'))
$staging = Join-Path $work 'staging'
$resStage = Join-Path $staging 'resources'
$extracted = Join-Path $work '解压自检'
$pendingZip = Join-Path $OutDir ('.cf7-pending-' + [Guid]::NewGuid().ToString('N') + '.zip')
New-Item -ItemType Directory -Path $staging -Force | Out-Null

function Invoke-ClosureAudit([string]$Payload) {
    & node $audit --payload $Payload --repo $RepoRoot
    if ($LASTEXITCODE -ne 0) { throw '运行时闭包审计未通过，停止出包' }
}

try {
    Write-Host '=== 从当前 worktree 构建每日 ZIP ===' -ForegroundColor Cyan
    Write-Host "  暂存目录: $work"
    # npm 的现有 pack 流水线负责过滤、致密化与 AS2 所有权审计；新目录不含历史残留。
    & npm.cmd --prefix $ToolRoot run pack -- --output $resStage --require-worktree
    if ($LASTEXITCODE -ne 0) { throw 'npm run pack 失败，停止出包' }
    Assert-Cf7File (Join-Path $resStage 'CRAZYFLASHER7MercenaryEmpire.exe')
    $marker = Join-Path $resStage '.cf7-packer-output'
    if (Test-Path -LiteralPath $marker) { Remove-Item -LiteralPath $marker -Force }
    Invoke-ClosureAudit $resStage

    New-Item -ItemType Directory -Path (Split-Path -Parent (Join-Path $staging $unityRel)) -Force | Out-Null
    Copy-Item -LiteralPath $unityDll -Destination (Join-Path $staging $unityRel)
    Copy-Item -LiteralPath $installer -Destination $staging
    Copy-Item -LiteralPath $rag.FullName -Destination $staging

    # cmd.exe：纯 ASCII、CRLF、无 BOM。保留安装脚本真实退出码，不被 pause 覆盖。
    $bat = @'
@echo off
title CF7 Daily Update Installer
setlocal
cd /d "%~dp0."
if not exist "%~dp0install.ps1" (
    echo [X] install.ps1 not found. Extract the whole zip again.
    pause
    exit /b 1
)
where powershell.exe >nul 2>&1
if errorlevel 1 (
    echo [X] PowerShell not found. Windows 10/11 is required.
    pause
    exit /b 1
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1"
set "result=%errorlevel%"
pause
exit /b %result%
'@
    [IO.File]::WriteAllText((Join-Path $staging '安装更新.bat'), (($bat -replace "`r?`n", "`r`n") + "`r`n"), [Text.Encoding]::ASCII)
    $readme = @"
闪客快打7重置计划 每日包（$Version）

1. 退出游戏，将整个 ZIP 解压到游戏目录以外，不要直接解压到 resources。
2. 双击「安装更新.bat」，确认 Steam 游戏目录后安装。
3. 安装器逐文件备份覆盖项，只移除旧清单声明而新包不再使用的 runtime 文件。
   不清空 resources，不覆盖存档、Agent 状态或个人凭据；未声明的旧 runtime 文件会阻止安装。
4. 必带终端 $($rag.Name)，放在游戏根目录；旧版本终端也会备份后替换。
5. 复制失败或 bootstrap --verify-only 失败时恢复覆盖项，不报告成功。
   如果出现 .cf7-update-backup-* 目录，请保留并核对，不要盲目重装。
6. 校验只验证文件闭包，不启动 Core，不代表实机可玩；仍需主助手沙箱运行游戏验收。
"@
    Set-Content -LiteralPath (Join-Path $staging '使用说明.txt') -Value $readme -Encoding UTF8

    # 在压缩前固定所有文件的相对路径、大小和字节摘要；解压后逐条验证中文路径在内的完整集合。
    $inventory = @{}
    foreach ($file in Get-Cf7Files $staging) {
        $rel = $file.FullName.Substring($staging.Length + 1)
        $inventory[$rel] = @{ Size=$file.Length; Hash=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash }
    }
    # .NET Framework 的 CreateFromDirectory 会把条目名写成反斜杠，违反 ZIP 规范的正斜杠约定，
    # 部分解压工具会把整棵子树当成单个文件名；这里逐条以正斜杠写条目并当场断言。
    $archive = [IO.Compression.ZipFile]::Open($pendingZip, [IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($rel in ($inventory.Keys | Sort-Object)) {
            [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, (Join-Path $staging $rel),
                $rel.Replace('\', '/'), [IO.Compression.CompressionLevel]::Optimal)
        }
    } finally { $archive.Dispose() }
    $written = [IO.Compression.ZipFile]::OpenRead($pendingZip)
    try {
        if ($written.Entries.Count -ne $inventory.Count) { throw 'ZIP 条目数与暂存文件数不符' }
        foreach ($entry in $written.Entries) {
            if ($entry.FullName.Contains('\')) { throw "ZIP 条目名含反斜杠：$($entry.FullName)" }
        }
    } finally { $written.Dispose() }
    [IO.Compression.ZipFile]::ExtractToDirectory($pendingZip, $extracted)
    $actual = @(Get-Cf7Files $extracted)
    if ($actual.Count -ne $inventory.Count) { throw 'ZIP 解压后文件数量不符' }
    foreach ($file in $actual) {
        $rel = $file.FullName.Substring($extracted.Length + 1)
        if (-not $inventory.ContainsKey($rel) -or $file.Length -ne $inventory[$rel].Size -or
            (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash -ne $inventory[$rel].Hash) {
            throw "ZIP 解压后路径/大小/SHA256 不符：$rel"
        }
    }
    foreach ($rel in @('安装更新.bat', '使用说明.txt', 'install.ps1', $unityRel, $rag.Name, 'resources/CRAZYFLASHER7MercenaryEmpire.exe')) {
        Assert-Cf7File (Join-Path $extracted $rel)
    }
    if ((Get-FileHash -LiteralPath (Join-Path $extracted $rag.Name) -Algorithm SHA256).Hash -ne $ragHash -or
        (Get-FileHash -LiteralPath (Join-Path $extracted $unityRel) -Algorithm SHA256).Hash -ne $unityHash) {
        throw '解压后的终端或 Unity 补丁与构建输入字节不一致'
    }
    $extractedResources = Join-Path $extracted 'resources'
    Invoke-ClosureAudit $extractedResources
    Invoke-Cf7BootstrapVerify $extractedResources
    # 最终命名只发生在所有门禁通过之后；不触发 runtime promotion。
    Move-Item -LiteralPath $pendingZip -Destination $zipPath
    Write-Host ("完成: {0}（{1:N2} GB；解压/闭包/verify-only 通过，尚未实机验收）" -f $zipPath, ((Get-Item -LiteralPath $zipPath).Length / 1GB)) -ForegroundColor Green
} finally {
    if (Test-Path -LiteralPath $pendingZip) { Remove-Item -LiteralPath $pendingZip -Force }
    if ($KeepStaging) { Write-Host "保留构建与解压现场：$work" }
    elseif (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force }
}
