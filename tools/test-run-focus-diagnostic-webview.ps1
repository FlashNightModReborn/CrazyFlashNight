$ErrorActionPreference = 'Stop'
# 直测 tools/run-focus-diagnostic.ps1 的 standalone（非 prepared）WebView 证据采集：
# 临时 fixture 项目根 + 真实 powershell.exe 5.1 子进程，不启动游戏。
# 断言：JSONL 尾部有界收编、轮转份、manifest 明示 recorder_log_only、
# file-hashes.json 覆盖全部新增顶层文件、原始 dump 不进 standalone 包。
try { Add-Type -AssemblyName System.IO.Compression.FileSystem } catch { }

$repoRoot = Split-Path -Parent $PSScriptRoot
$scriptPath = Join-Path $repoRoot 'tools/run-focus-diagnostic.ps1'
$ps51 = Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe'
$fixtureBase = Join-Path $repoRoot 'tmp/focus-diagnostic-webview'
$tailCap = 256 * 1024
if (Test-Path -LiteralPath $fixtureBase) { Remove-Item -LiteralPath $fixtureBase -Recurse -Force }
New-Item -ItemType Directory -Path $fixtureBase -Force | Out-Null

function New-FixtureRoot([string]$Name) {
    $root = Join-Path $fixtureBase $Name
    New-Item -ItemType Directory -Path (Join-Path $root 'logs') -Force | Out-Null
    return $root
}

function Invoke-StandaloneCollect([string]$Root) {
    # 真实生产入口形态：5.1 powershell + -CollectOnly -ProjectRoot；无焦点事件时 exit 1 属预期。
    $out = & $ps51 -NoProfile -ExecutionPolicy Bypass -File $scriptPath `
        -CollectOnly -ProjectRoot $Root 2>&1 | Out-String
    $zip = Get-ChildItem -LiteralPath (Join-Path $Root 'logs/focus-diagnostic') -Filter '*.zip' |
        Sort-Object LastWriteTimeUtc | Select-Object -Last 1
    if (-not $zip) { throw "standalone collect produced no zip under $Root`n$out" }
    return $zip.FullName
}

function Read-ZipEntries([string]$ZipPath) {
    $entries = @{}
    $zip = [IO.Compression.ZipFile]::OpenRead($ZipPath)
    try {
        foreach ($e in $zip.Entries) {
            $ms = New-Object IO.MemoryStream
            $s = $e.Open(); $s.CopyTo($ms); $s.Dispose()
            $entries[$e.Name] = $ms.ToArray()
        }
    } finally { $zip.Dispose() }
    return $entries
}

function ConvertFrom-JsonEntry([hashtable]$Entries, [string]$Name) {
    # 生产脚本以 PS5.1 Set-Content -Encoding UTF8 落盘（带 BOM）；5.1 的 ConvertFrom-Json 不接受 U+FEFF。
    [Text.Encoding]::UTF8.GetString($Entries[$Name]).TrimStart([char]0xFEFF) | ConvertFrom-Json | ForEach-Object { $_ }
}

function Assert-HashesCoverEntries([hashtable]$Entries) {
    $hashes = @(ConvertFrom-JsonEntry $Entries 'file-hashes.json')
    foreach ($h in $hashes) {
        if (-not $Entries.ContainsKey([string]$h.file)) { throw ('hash listed for missing entry ' + $h.file) }
        $sha = [Security.Cryptography.SHA256]::Create()
        try { $actual = ([BitConverter]::ToString($sha.ComputeHash($Entries[[string]$h.file]))).Replace('-', '') }
        finally { $sha.Dispose() }
        if ($actual -ne [string]$h.Hash) { throw ('hash mismatch on ' + $h.file) }
    }
    foreach ($name in @('webview-failures.jsonl', 'webview-failures.jsonl.1', 'webview-failures-manifest.json')) {
        if ($Entries.ContainsKey($name) -and -not @($hashes | Where-Object { $_.file -eq $name })) {
            throw "file-hashes.json does not cover $name"
        }
    }
}

$results = @()
function Record([string]$Name, [scriptblock]$Body) {
    try { & $Body; $script:results += @{ name = $Name; passed = $true } }
    catch { $script:results += @{ name = $Name; passed = $false; error = $_.Exception.Message } }
}

Record 'with-log-and-rotated' {
    $root = New-FixtureRoot 'with-log'
    $line = '{"kind":"browser_process_exited","session":"s-fixture"}'
    [IO.File]::WriteAllText((Join-Path $root 'logs/webview-failures.jsonl'), "$line`n", [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $root 'logs/webview-failures.jsonl.1'), "$line`n", [Text.UTF8Encoding]::new($false))
    # 一个真实 dump 形状的文件必须不被 standalone 路径收编（仅 launcher 侧采集 dump）。
    $reports = Join-Path $root 'launcher/webview2_overlay_userdata/EBWebView/Crashpad/reports'
    New-Item -ItemType Directory -Path $reports -Force | Out-Null
    [IO.File]::WriteAllBytes((Join-Path $reports 'crash.dmp'), (New-Object byte[] 64))

    $entries = Read-ZipEntries (Invoke-StandaloneCollect $root)
    foreach ($name in @('webview-failures.jsonl', 'webview-failures.jsonl.1', 'webview-failures-manifest.json')) {
        if (-not $entries.ContainsKey($name)) { throw "missing zip entry $name" }
    }
    if ($entries.Keys | Where-Object { $_ -like '*.dmp' -or $_ -like 'wvf-*' }) { throw 'standalone zip must not contain raw reports' }
    $manifest = ConvertFrom-JsonEntry $entries 'webview-failures-manifest.json'
    if ($manifest.collector -ne 'powershell-standalone' -or $manifest.coverage -ne 'recorder_log_only') { throw 'manifest coverage markers wrong' }
    if (-not $manifest.failuresLog.included -or -not $manifest.failuresLog.rotated.included) { throw 'log tail not recorded included' }
    if (-not @($manifest.omitted | Where-Object { $_.reason -eq 'standalone_reports_not_collected' })) { throw 'dump limitation omission missing' }
    $ctx = ConvertFrom-JsonEntry $entries 'diagnostic-context.json'
    if (-not $ctx.webviewFailures.logIncluded) { throw 'context webviewFailures.logIncluded false' }
    Assert-HashesCoverEntries $entries
}

Record 'tail-truncated' {
    $root = New-FixtureRoot 'truncated'
    $line = '{"kind":"fixture","pad":"' + ('x' * 400) + '"}'
    $sb = New-Object Text.StringBuilder
    while ($sb.Length -lt (320 * 1024)) { [void]$sb.AppendLine($line) }
    [IO.File]::WriteAllText((Join-Path $root 'logs/webview-failures.jsonl'), $sb.ToString(), [Text.UTF8Encoding]::new($false))

    $entries = Read-ZipEntries (Invoke-StandaloneCollect $root)
    $tail = $entries['webview-failures.jsonl']
    if ($tail.LongLength -gt $tailCap) { throw "tail exceeded cap: $($tail.LongLength)" }
    foreach ($l in [Text.Encoding]::UTF8.GetString($tail) -split "`r?`n" | Where-Object { $_ }) {
        $null = $l | ConvertFrom-Json   # 截断后首行必须是完整 JSON 行
    }
    $manifest = ConvertFrom-JsonEntry $entries 'webview-failures-manifest.json'
    if (-not $manifest.failuresLog.truncated) { throw 'truncated flag not set' }
    Assert-HashesCoverEntries $entries
}

Record 'missing-log' {
    $root = New-FixtureRoot 'missing'
    $entries = Read-ZipEntries (Invoke-StandaloneCollect $root)
    if ($entries.ContainsKey('webview-failures.jsonl')) { throw 'missing log must not create entry' }
    $manifest = ConvertFrom-JsonEntry $entries 'webview-failures-manifest.json'
    if ($manifest.failuresLog.omittedReason -ne 'log_missing') { throw 'log_missing omission not recorded' }
    Assert-HashesCoverEntries $entries
}

Record 'locked-log-tolerated' {
    $root = New-FixtureRoot 'locked'
    $logPath = Join-Path $root 'logs/webview-failures.jsonl'
    [IO.File]::WriteAllText($logPath, '{"kind":"fixture"}' + "`n", [Text.UTF8Encoding]::new($false))
    $held = New-Object IO.FileStream($logPath, 'Open', 'ReadWrite', 'None')
    try {
        $entries = Read-ZipEntries (Invoke-StandaloneCollect $root)
    } finally { $held.Dispose() }
    if ($entries.ContainsKey('webview-failures.jsonl')) { throw 'exclusively locked log must not be copied' }
    $manifest = ConvertFrom-JsonEntry $entries 'webview-failures-manifest.json'
    if ($manifest.failuresLog.omittedReason -ne 'log_unreadable') { throw 'log_unreadable omission not recorded' }
    Assert-HashesCoverEntries $entries
}

$failed = @($results | Where-Object { -not $_.passed })
@{ passed = ($failed.Count -eq 0); cases = $results; count = $results.Count } |
    ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $fixtureBase 'webview-collect-check.json') -Encoding UTF8
foreach ($r in $results) {
    if ($r.passed) { Write-Host ('PASS ' + $r.name) } else { Write-Host ('FAIL ' + $r.name + ' -- ' + $r.error) }
}
Write-Host ("Standalone WebView collect: {0}/{1} fixtures passed" -f ($results.Count - $failed.Count), $results.Count)
if ($failed.Count -gt 0) { exit 1 }
