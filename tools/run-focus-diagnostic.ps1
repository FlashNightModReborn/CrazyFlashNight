[CmdletBinding()]
param([switch]$CollectOnly, [string]$ProjectRoot, [string]$PreparedRunDir)

chcp.com 65001 | Out-Null
$ErrorActionPreference = 'Stop'
if ($ProjectRoot -and -not $CollectOnly) { throw '-ProjectRoot is only supported for collection.' }
if ($PreparedRunDir -and -not $CollectOnly) { throw '-PreparedRunDir requires -CollectOnly.' }
$focusRoot = if ($ProjectRoot) { (Resolve-Path -LiteralPath $ProjectRoot).Path } else { Split-Path -Parent $PSScriptRoot }
$focusArchiveRoot = [IO.Path]::GetFullPath((Join-Path $focusRoot 'logs/focus-diagnostic'))
$focusPrepared = $null
$focusPreparedValidated = $false
if ($PreparedRunDir) {
    $focusRunDir = [IO.Path]::GetFullPath($PreparedRunDir)
    if (-not [string]::Equals((Split-Path -Parent $focusRunDir), $focusArchiveRoot, [StringComparison]::OrdinalIgnoreCase) -or
        (Split-Path -Leaf $focusRunDir) -notmatch '^auto-\d{8}-\d{6}-\d{3}-[0-9a-f]{32}$') {
        throw 'Prepared collection must be an automatic snapshot directly under this project logs/focus-diagnostic.'
    }
    $focusPreparedValidated = $true
    if (Test-Path -LiteralPath ($focusRunDir + '.zip')) { Write-Host ('日志包：' + $focusRunDir + '.zip'); exit 0 }
    $focusPrepared = Get-Content -LiteralPath (Join-Path $focusRunDir 'auto-collection.json') -Raw -Encoding UTF8 | ConvertFrom-Json
} else { $focusRunDir = Join-Path $focusArchiveRoot (Get-Date -Format 'yyyyMMdd-HHmmss-fff') }
trap {
    if ($focusPreparedValidated -and (Test-Path -LiteralPath $focusRunDir -PathType Container)) {
        try { $_.Exception.ToString() | Set-Content -LiteralPath (Join-Path $focusRunDir 'collection-error.txt') -Encoding UTF8 } catch { }
    }
    Write-Error $_ -ErrorAction Continue
    exit 1
}
New-Item -ItemType Directory -Path $focusRunDir -Force | Out-Null
$focusPreviousFlag = [Environment]::GetEnvironmentVariable('CF7_FOCUS_TRACE', 'Process')
$focusPreviousCollector = [Environment]::GetEnvironmentVariable('CF7_FOCUS_EXIT_COLLECTOR', 'Process')
$focusExit = 0
$focusContext = [ordered]@{
    collectedAtUtc = $null
    requestedAtUtc = [DateTime]::UtcNow.ToString('O')
    collectOnly = [bool]$CollectOnly
    collectionTrigger = if ($focusPrepared) { 'game_exit' } elseif ($CollectOnly) { 'manual' } else { 'diagnostic_launcher_exit' }
    runtimeMode = $null
    process = $null
    files = @()
    error = $null
    recording = $null
    captureStatus = 'not_recorded'
    focusEventsSource = $null
    focusEventCount = 0
    as2ObserveReadySeen = $false
    collectionWarnings = @()
    webviewFailures = $null
}
if ($focusPrepared) {
    $focusContext.requestedAtUtc = $focusPrepared.requestedAtUtc
    $focusContext.collectionWarnings = @($focusPrepared.collectionWarnings)
}

try {
    if (-not $CollectOnly) {
        [Environment]::SetEnvironmentVariable('CF7_FOCUS_TRACE', '1', 'Process')
        # 专用启动器已在等待退出，由它收尾；Core 核对 PID 与启动时刻，已关闭的启动器不抑制自动打包。
        $focusCollectorProcess = [Diagnostics.Process]::GetCurrentProcess()
        try {
            [Environment]::SetEnvironmentVariable('CF7_FOCUS_EXIT_COLLECTOR',
                ($PID.ToString() + ':' + $focusCollectorProcess.StartTime.ToUniversalTime().Ticks.ToString()), 'Process')
        } finally { $focusCollectorProcess.Dispose() }
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
        $focusRollingStarted = $false
        $focusStartupRecording = Join-Path $focusRoot 'logs/focus-trace/recording-context.json'
        if (Test-Path -LiteralPath $focusStartupRecording) {
            try {
                $focusStartupContext = Get-Content -LiteralPath $focusStartupRecording -Raw -Encoding UTF8 | ConvertFrom-Json
                $focusRollingStarted = [int]$focusStartupContext.process.pid -eq $focusProcess.Id -and
                    [DateTime]::Parse([string]$focusStartupContext.process.startedAtUtc).ToUniversalTime() -eq $focusProcess.StartTime.ToUniversalTime()
            } catch { }
        }
        if ($focusRollingStarted) { Write-Host '本轮持续记录，按容量循环保留最近日志。失灵时保留一次点击，再按原来的办法恢复。' }
        else { Write-Host '当前 Core 使用旧版观察上限（30 分钟）；持续录制需要配套新版 Core 和 asLoader。' -ForegroundColor Yellow }
        Write-Host '退出后发送日志 ZIP，并说明大约发生时间与恢复办法。也可随时双击“收集焦点诊断日志.cmd”。'
        try { $focusProcess.WaitForExit() } finally { $focusProcess.Dispose() }
    }
} catch {
    $focusExit = 1
    $focusContext.error = $_.Exception.Message
    Write-Host $focusContext.error -ForegroundColor Red
} finally {
    [Environment]::SetEnvironmentVariable('CF7_FOCUS_TRACE', $focusPreviousFlag, 'Process')
    [Environment]::SetEnvironmentVariable('CF7_FOCUS_EXIT_COLLECTOR', $focusPreviousCollector, 'Process')
    foreach ($focusRelative in @('logs/launcher.log.1', 'logs/launcher.log', 'logs/bootstrap.log',
            'runtime/cf7-runtime-manifest.tsv', 'config/build/runtime-release-consensus.json', 'config.toml')) {
        $focusSource = Join-Path $focusRoot $focusRelative
        if (-not $focusPrepared -and (Test-Path -LiteralPath $focusSource -PathType Leaf)) {
            Copy-Item -LiteralPath $focusSource -Destination (Join-Path $focusRunDir (Split-Path -Leaf $focusSource))
        }
    }
    # WebView 故障记录器有界尾部（standalone 路径）：与 Core WebViewFailureReportCollector
    # 同口径 logTailBytes 上限与共享读容忍；本路径只收 JSONL 元数据，不采集原始 dump —
    # 那需要 launcher 侧采集（手动诊断包 / 游戏退出自动快照），此处 manifest 明示该限制。
    $focusWvfTailCap = 256 * 1024
    $focusWvfLogStates = [ordered]@{}
    foreach ($focusWvfName in @('webview-failures.jsonl', 'webview-failures.jsonl.1')) {
        $focusWvfState = [ordered]@{ included = $false; bytes = [long]0; truncated = $false; omittedReason = $null }
        $focusWvfSource = Join-Path $focusRoot ('logs/' + $focusWvfName)
        if (-not $focusPrepared) {
            if (-not (Test-Path -LiteralPath $focusWvfSource -PathType Leaf)) {
                $focusWvfState.omittedReason = 'log_missing'
            } else {
                $focusWvfStream = $null
                try {
                    $focusWvfStream = New-Object IO.FileStream($focusWvfSource,
                        [IO.FileMode]::Open, [IO.FileAccess]::Read,
                        ([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
                    $focusWvfStart = [Math]::Max(0L, $focusWvfStream.Length - $focusWvfTailCap)
                    [void]$focusWvfStream.Seek($focusWvfStart, [IO.SeekOrigin]::Begin)
                    if ($focusWvfStart -gt 0) {
                        $focusWvfState.truncated = $true
                        while (($focusWvfB = $focusWvfStream.ReadByte()) -ge 0 -and $focusWvfB -ne 10) { }
                    }
                    $focusWvfMs = New-Object IO.MemoryStream
                    $focusWvfBuf = New-Object byte[] 65536
                    while ($focusWvfMs.Length -lt $focusWvfTailCap -and
                        ($focusWvfN = $focusWvfStream.Read($focusWvfBuf, 0,
                            [int][Math]::Min($focusWvfBuf.Length, $focusWvfTailCap - $focusWvfMs.Length))) -gt 0) {
                        $focusWvfMs.Write($focusWvfBuf, 0, $focusWvfN)
                    }
                    # 共享读期间文件仍可能被追加：累计截停且尚有未读字节才算截断。
                    if ($focusWvfMs.Length -ge $focusWvfTailCap -and
                        $focusWvfStream.Position -lt $focusWvfStream.Length) { $focusWvfState.truncated = $true }
                    $focusWvfBytes = $focusWvfMs.ToArray()
                    [IO.File]::WriteAllBytes((Join-Path $focusRunDir $focusWvfName), $focusWvfBytes)
                    $focusWvfState.included = $true
                    $focusWvfState.bytes = [long]$focusWvfBytes.LongLength
                } catch {
                    $focusWvfState.omittedReason = 'log_unreadable'
                    $focusContext.collectionWarnings += ('webview-failures: ' + $focusWvfName + ' unreadable; tail omitted')
                } finally {
                    if ($null -ne $focusWvfStream) { $focusWvfStream.Dispose() }
                }
            }
        }
        $focusWvfLogStates[$focusWvfName] = $focusWvfState
    }
    if (-not $focusPrepared) {
        $focusWvfLog = $focusWvfLogStates['webview-failures.jsonl']
        $focusWvfRotated = $focusWvfLogStates['webview-failures.jsonl.1']
        $focusWvfManifest = [ordered]@{
            version = 1
            generatedAtUtc = [DateTime]::UtcNow.ToString('O')
            collector = 'powershell-standalone'
            coverage = 'recorder_log_only'
            note = 'standalone collection ships only the bounded recorder log; raw Crashpad report files are bundled by launcher-side collection (manual diagnostic package / automatic game-exit snapshot).'
            sourceLog = 'logs/webview-failures.jsonl'
            bounds = [ordered]@{ logTailBytes = [long]$focusWvfTailCap }
            failuresLog = [ordered]@{
                included = [bool]$focusWvfLog.included
                bytes = [long]$focusWvfLog.bytes
                truncated = [bool]$focusWvfLog.truncated
                omittedReason = $focusWvfLog.omittedReason
                rotated = [ordered]@{
                    file = 'webview-failures.jsonl.1'
                    included = [bool]$focusWvfRotated.included
                    bytes = [long]$focusWvfRotated.bytes
                    omittedReason = $focusWvfRotated.omittedReason
                }
            }
            included = @()
            omitted = @([ordered]@{
                reason = 'standalone_reports_not_collected'
                detail = 'raw crash report files require launcher-side collection; see webview-failures in the manual diagnostic package or automatic exit snapshot'
            })
        }
        try {
            [IO.File]::WriteAllText((Join-Path $focusRunDir 'webview-failures-manifest.json'),
                ($focusWvfManifest | ConvertTo-Json -Depth 6), (New-Object Text.UTF8Encoding($false)))
        } catch { $focusContext.collectionWarnings += ('webview-failures: manifest write failed: ' + $_.Exception.Message) }
        $focusContext.webviewFailures = [ordered]@{
            logIncluded = [bool]$focusWvfLog.included
            logBytes = [long]$focusWvfLog.bytes
            logTruncated = [bool]$focusWvfLog.truncated
            rotatedIncluded = [bool]$focusWvfRotated.included
            coverage = 'recorder_log_only'
        }
    }
    $focusRollingLogs = @()
    $focusRecordingDir = if ($focusPrepared) { $focusRunDir } else { Join-Path $focusRoot 'logs/focus-trace' }
    foreach ($focusName in @('focus-trace.log.2', 'focus-trace.log.1', 'focus-trace.log', 'recording-context.json')) {
        $focusSource = Join-Path $focusRecordingDir $focusName
        if (Test-Path -LiteralPath $focusSource -PathType Leaf) {
            try {
                $focusCopy = Join-Path $focusRunDir $focusName
                if (-not $focusPrepared) { Copy-Item -LiteralPath $focusSource -Destination $focusCopy }
                if ($focusName -eq 'recording-context.json') {
                    $focusContext.recording = Get-Content -LiteralPath $focusCopy -Raw -Encoding UTF8 | ConvertFrom-Json
                } else { $focusRollingLogs += $focusCopy }
            } catch { $focusContext.collectionWarnings += ('滚动文件采集失败 ' + $focusName + ': ' + $_.Exception.Message) }
        }
    }
    foreach ($focusRelative in @('runtime/CRAZYFLASHER7MercenaryEmpire.Core.dll', 'scripts/asLoader.swf')) {
        $focusSource = Join-Path $focusRoot $focusRelative
        if (-not $focusPrepared -and (Test-Path -LiteralPath $focusSource -PathType Leaf)) {
            $focusContext.files += [ordered]@{ path = $focusRelative; sha256 = (Get-FileHash -LiteralPath $focusSource -Algorithm SHA256).Hash }
        }
    }
    if ($focusPrepared -and $focusContext.recording) { $focusContext.files = @($focusContext.recording.files) }
    $focusContext.focusEventsSource = if ($focusRollingLogs.Count -gt 0) { 'rolling' } else { 'legacy_launcher' }
    $focusInputLogs = if ($focusRollingLogs.Count -gt 0) { $focusRollingLogs } else {
        @('launcher.log.1', 'launcher.log') | ForEach-Object { Join-Path $focusRunDir $_ }
    }
    $focusLines = @(foreach ($focusCopiedLog in $focusInputLogs) {
        if (Test-Path -LiteralPath $focusCopiedLog) {
            Get-Content -LiteralPath $focusCopiedLog -Encoding UTF8 | Where-Object { $_ -match '\[Focus(?:Trace(?:AS2)?|Recording)\]' }
        }
    })
    $focusLines | Set-Content -LiteralPath (Join-Path $focusRunDir 'focus-events.txt') -Encoding UTF8
    $focusActualEvents = @($focusLines | Where-Object { $_ -match '\[FocusTrace(?:AS2)?\]' })
    if ($focusContext.recording) {
        $focusSessionPattern = '"session"\s*:\s*"' + [regex]::Escape([string]$focusContext.recording.session) + '"'
        $focusActualEvents = @($focusActualEvents | Where-Object { $_ -match $focusSessionPattern })
        $focusContext.as2ObserveReadySeen = [bool]$focusContext.recording.as2ObserveReadySeen
    } else {
        $focusContext.as2ObserveReadySeen = @($focusActualEvents | Where-Object { $_ -match 'event=observe_ready' }).Count -gt 0
        if ($focusRollingLogs.Count -gt 0) { $focusContext.collectionWarnings += '滚动录制身份缺失，不能归属本轮会话。' }
    }
    $focusContext.focusEventCount = $focusActualEvents.Count
    if ($focusContext.error) { $focusContext.captureStatus = 'start_failed' }
    elseif ($focusRollingLogs.Count -gt 0 -and $focusContext.recording) {
        if ($CollectOnly) {
            $focusContext.process = $focusContext.recording.process
            $focusContext.runtimeMode = $focusContext.recording.runtimeMode
        }
        $focusContext.captureStatus = if ($focusContext.recording.status -eq 'write_error') { 'recording_error' }
            elseif ($focusContext.recording.status -eq 'stopped') { 'recorded' } else { 'live_or_interrupted_snapshot' }
        $focusPortsPath = Join-Path $focusRoot 'launcher_ports.json'
        if (-not $focusPrepared -and (Test-Path -LiteralPath $focusPortsPath)) {
            try {
                $focusCurrentPorts = Get-Content -LiteralPath $focusPortsPath -Raw -Encoding UTF8 | ConvertFrom-Json
                $focusCurrentProcess = Get-Process -Id ([int]$focusCurrentPorts.pid) -ErrorAction SilentlyContinue
                if ($focusCurrentProcess) {
                    $focusSameProcess = [int]$focusCurrentPorts.pid -eq [int]$focusContext.recording.process.pid
                    if ($focusSameProcess -and $focusContext.recording.process.startedAtUtc) {
                        $focusRecordedStart = [DateTime]::Parse([string]$focusContext.recording.process.startedAtUtc).ToUniversalTime()
                        $focusSameProcess = $focusCurrentProcess.StartTime.ToUniversalTime() -eq $focusRecordedStart
                    }
                    if (-not $focusSameProcess) { $focusContext.captureStatus = 'stale_recording' }
                }
            } catch { $focusContext.collectionWarnings += ('当前进程状态未确认: ' + $_.Exception.Message) }
        }
    } elseif ($focusActualEvents.Count -gt 0) { $focusContext.captureStatus = 'legacy_snapshot' }
    else { $focusContext.captureStatus = 'no_focus_events'; $focusExit = 1 }
    if (-not $focusContext.error -and $focusActualEvents.Count -eq 0 -and $focusContext.captureStatus -ne 'recording_error') {
        $focusContext.captureStatus = 'no_focus_events'
        $focusExit = 1
    }
    if ($focusContext.collectionWarnings.Count -gt 0 -and -not $focusContext.error -and
        $focusContext.captureStatus -notin @('recording_error', 'stale_recording', 'no_focus_events')) {
        $focusContext.captureStatus = 'partial_snapshot'
    }
    if ($focusPrepared -and $focusPrepared.session -ne $focusContext.recording.session) {
        $focusContext.captureStatus = 'stale_recording'
        $focusContext.collectionWarnings += '退出快照与录制会话不一致，不能认领为本轮记录。'
        $focusExit = 1
    }
    $focusSummary = @(
        '焦点诊断采集状态: ' + $focusContext.captureStatus
        '焦点事件来源: ' + $focusContext.focusEventsSource
        '事件文本行数: ' + $focusLines.Count
        '本轮焦点事件行数: ' + $focusContext.focusEventCount
        'AS2 观察就绪已记录: ' + $focusContext.as2ObserveReadySeen
        '文件可生成不代表录制成功。start_failed / no_focus_events / stale_recording 必须先核对启动或配置。'
        '普通启动前在 config.toml 设置 diagFocusTrace = true；正常退出自动打包，运行中可手动立即采集。'
        '运行中采集是快照，尾部可能尚未刷出；各段头部携带该段会话与录制时文件身份。'
    )
    $focusSummary | Set-Content -LiteralPath (Join-Path $focusRunDir '采集说明.txt') -Encoding UTF8
    $focusContext.collectedAtUtc = [DateTime]::UtcNow.ToString('O')
    $focusContext | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $focusRunDir 'diagnostic-context.json') -Encoding UTF8
    Get-ChildItem -LiteralPath $focusRunDir -File | Get-FileHash -Algorithm SHA256 |
        Select-Object @{Name='file'; Expression={ Split-Path -Leaf $_.Path }}, Hash |
        ConvertTo-Json | Set-Content -LiteralPath (Join-Path $focusRunDir 'file-hashes.json') -Encoding UTF8
    # 完整压缩后才出现最终 ZIP 名；失败保留退出快照与错误，不能把半包当完成。
    Compress-Archive -LiteralPath $focusRunDir -DestinationPath ($focusRunDir + '.partial.zip') -Force
    Move-Item -LiteralPath ($focusRunDir + '.partial.zip') -Destination ($focusRunDir + '.zip')
    Write-Host ('采集状态：' + $focusContext.captureStatus)
    if ($focusContext.error) { Write-Host '诊断启动未成功：ZIP 仅包含已有日志快照，不代表本轮已开启录制。' -ForegroundColor Red }
    if ($focusContext.captureStatus -eq 'stale_recording') {
        Write-Host '记录不属于当前游戏进程。请确认 diagFocusTrace 已开启并重启游戏；本包保留旧记录供分析。' -ForegroundColor Yellow
    }
    if ($focusContext.captureStatus -eq 'recording_error') {
        Write-Host '本轮日志写入曾失败，请保留 ZIP 内的 recording-context.json 和已有记录供分析。' -ForegroundColor Red
    }
    Write-Host ('日志包：' + $focusRunDir + '.zip') -ForegroundColor Cyan
    if ($focusLines.Count -eq 0) { Write-Host '尚无焦点事件；请设置 diagFocusTrace = true 后重新启动，或使用焦点诊断启动入口。' -ForegroundColor Yellow }
    # 只回收已验证位于本项目归档目录的自动快照；人工采集目录继续保留。
    if ($focusPrepared -and $focusExit -eq 0) {
        Get-ChildItem -LiteralPath $focusRunDir -File | Remove-Item -Force
        Remove-Item -LiteralPath $focusRunDir -Force
    }
}
exit $focusExit
