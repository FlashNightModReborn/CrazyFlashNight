[CmdletBinding()]
param([switch]$CollectOnly)

chcp.com 65001 | Out-Null
$ErrorActionPreference = 'Stop'
$focusRoot = Split-Path -Parent $PSScriptRoot
$focusRunDir = Join-Path $focusRoot ('logs/focus-diagnostic/' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
New-Item -ItemType Directory -Path $focusRunDir -Force | Out-Null
$focusPreviousFlag = [Environment]::GetEnvironmentVariable('CF7_FOCUS_TRACE', 'Process')
$focusExit = 0
$focusContext = [ordered]@{
    collectedAtUtc = $null
    requestedAtUtc = [DateTime]::UtcNow.ToString('O')
    collectOnly = [bool]$CollectOnly
    runtimeMode = $null
    process = $null
    files = @()
    error = $null
}

try {
    if (-not $CollectOnly) {
        [Environment]::SetEnvironmentVariable('CF7_FOCUS_TRACE', '1', 'Process')
        Write-Host '正在启动正式版本的焦点诊断。请保留此窗口，正常退出游戏后会自动生成日志包。'
        # 复用正式入口的完整性、旧进程拒绝和实际进程身份核验，不选择开发候选。
        & (Join-Path $focusRoot 'automation/start.ps1') *> (Join-Path $focusRunDir 'startup.txt')
        if ($LASTEXITCODE -ne 0) { throw '启动失败，详细原因已保存到 startup.txt。请先正常关闭已运行的游戏。' }
        $focusPorts = Get-Content -LiteralPath (Join-Path $focusRoot 'launcher_ports.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        $focusProcess = Get-Process -Id ([int]$focusPorts.pid) -ErrorAction Stop
        $focusExpectedExe = Join-Path $focusRoot 'runtime/CRAZYFLASHER7MercenaryEmpire.Core.exe'
        if (-not [string]::Equals($focusProcess.Path, $focusExpectedExe, [StringComparison]::OrdinalIgnoreCase)) {
            throw '实际运行路径不是本目录的正式 runtime，不能作为本次诊断会话。'
        }
        $focusContext.runtimeMode = 'formal_runtime'
        $focusContext.process = [ordered]@{
            pid = $focusProcess.Id
            path = $focusProcess.Path
            startedAtUtc = $focusProcess.StartTime.ToUniversalTime().ToString('O')
        }
        Write-Host '观察上限为启动后 30 分钟。按日常习惯游玩；失灵时保留一次点击，再按原来的办法恢复。'
        Write-Host '退出后发送日志 ZIP，并说明大约发生时间与恢复办法。也可随时双击“收集焦点诊断日志.cmd”。'
        try { $focusProcess.WaitForExit() } finally { $focusProcess.Dispose() }
    }
} catch {
    $focusExit = 1
    $focusContext.error = $_.Exception.Message
    Write-Host $focusContext.error -ForegroundColor Red
} finally {
    [Environment]::SetEnvironmentVariable('CF7_FOCUS_TRACE', $focusPreviousFlag, 'Process')
    foreach ($focusRelative in @('logs/launcher.log.1', 'logs/launcher.log', 'logs/bootstrap.log',
            'runtime/cf7-runtime-manifest.tsv', 'config/build/runtime-release-consensus.json')) {
        $focusSource = Join-Path $focusRoot $focusRelative
        if (Test-Path -LiteralPath $focusSource -PathType Leaf) {
            Copy-Item -LiteralPath $focusSource -Destination (Join-Path $focusRunDir (Split-Path -Leaf $focusSource))
        }
    }
    foreach ($focusRelative in @('runtime/CRAZYFLASHER7MercenaryEmpire.Core.dll', 'scripts/asLoader.swf')) {
        $focusSource = Join-Path $focusRoot $focusRelative
        if (Test-Path -LiteralPath $focusSource -PathType Leaf) {
            $focusContext.files += [ordered]@{ path = $focusRelative; sha256 = (Get-FileHash -LiteralPath $focusSource -Algorithm SHA256).Hash }
        }
    }
    $focusLines = @(foreach ($focusLog in @('launcher.log.1', 'launcher.log')) {
        $focusCopiedLog = Join-Path $focusRunDir $focusLog
        if (Test-Path -LiteralPath $focusCopiedLog) {
            Get-Content -LiteralPath $focusCopiedLog -Encoding UTF8 | Where-Object { $_ -match '\[FocusTrace(AS2)?\]' }
        }
    })
    $focusLines | Set-Content -LiteralPath (Join-Path $focusRunDir 'focus-events.txt') -Encoding UTF8
    $focusContext.collectedAtUtc = [DateTime]::UtcNow.ToString('O')
    $focusContext | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $focusRunDir 'diagnostic-context.json') -Encoding UTF8
    Get-ChildItem -LiteralPath $focusRunDir -File | Get-FileHash -Algorithm SHA256 |
        Select-Object @{Name='file'; Expression={ Split-Path -Leaf $_.Path }}, Hash |
        ConvertTo-Json | Set-Content -LiteralPath (Join-Path $focusRunDir 'file-hashes.json') -Encoding UTF8
    Compress-Archive -LiteralPath $focusRunDir -DestinationPath ($focusRunDir + '.zip')
    Write-Host ('日志包：' + $focusRunDir + '.zip') -ForegroundColor Cyan
    if ($focusLines.Count -eq 0) { Write-Host '尚无焦点事件；请确认本轮通过焦点诊断入口启动。' -ForegroundColor Yellow }
}
exit $focusExit
