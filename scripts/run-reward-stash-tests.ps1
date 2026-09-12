[CmdletBinding()]
param([switch]$RunScale,
    [ValidateRange(1,3600)][int]$TimeoutSeconds = 240)
$ErrorActionPreference = 'Stop'
chcp.com 65001 | Out-Null
$projectDir = Split-Path -Parent $PSScriptRoot
$runnerPath = Join-Path $PSScriptRoot 'TestLoader.as'
$markerPath = Join-Path $PSScriptRoot 'testloader_scratch_inflight.marker'
$uncertainPath = Join-Path $PSScriptRoot 'compile_state_uncertain.marker'
. (Join-Path $PSScriptRoot 'test-runners/testloader-scratch-transaction.ps1')
$normalized = [IO.Path]::GetFullPath($projectDir).TrimEnd('\').ToUpperInvariant()
$sha = [Security.Cryptography.SHA256]::Create()
try { $repoHash = ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($normalized)))).Replace('-','').Substring(0,24) }
finally { $sha.Dispose() }
$mutex = [Threading.Mutex]::new($false, 'Local\CF7_FlashCompile_' + $repoHash)
$held = $false
$transaction = $null
$installedHash = $null
$oldLease = $env:CF7_FLASH_COMPILE_LEASE
$runId = [Guid]::NewGuid().ToString('N')
try {
    $held = $mutex.WaitOne(0)
    if (!$held) { throw 'Another Flash compile is active.' }
    if (Test-Path -LiteralPath $uncertainPath) { throw 'Inspect the previous uncertain Flash compile before retrying.' }
    $lease = 'v1:{0}:{1}:{2}' -f $repoHash, $PID, [Guid]::NewGuid().ToString('N')
    $transaction = New-Cf7TestLoaderScratchTransaction -MarkerPath $markerPath -RunnerPath $runnerPath -RepoHash $repoHash -CompileLease $lease -OwnerKind 'reward-stash'
    Assert-Cf7TestLoaderScratchReadyToInstall -Transaction $transaction
    $template = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'test-runners/reward-stash/TestLoader.as.template'))
    if ([regex]::Matches($template, '__REWARD_STASH_RUN_ID__').Count -ne 2) { throw 'Runner must bind both markers to one run ID.' }
    [IO.File]::WriteAllText($runnerPath, $template.Replace('__REWARD_STASH_RUN_ID__', $runId).Replace('__RUN_STASH_SCALE__', $RunScale.IsPresent.ToString().ToLowerInvariant()), [Text.UTF8Encoding]::new($true))
    $installedHash = (Get-FileHash -LiteralPath $runnerPath -Algorithm SHA256).Hash
    $env:CF7_FLASH_COMPILE_LEASE = $lease
    $started = [DateTime]::UtcNow
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'compile_test.ps1') -Target test -TimeoutSeconds $TimeoutSeconds
    if ($LASTEXITCODE -ne 0) { throw "Flash reward-stash compile/test failed ($LASTEXITCODE)." }
    $tracePath = Join-Path $PSScriptRoot 'flashlog.txt'
    $trace = [IO.File]::ReadAllText($tracePath)
    $start = "[CF7_REWARD_STASH_TEST_RUN] start runId=$runId"
    $end = "[CF7_REWARD_STASH_TEST_RUN] complete runId=$runId"
    if ($RunScale) {
        $scaleDeadline = [DateTime]::UtcNow.AddMinutes(10)
        $liveLog = Join-Path $env:APPDATA 'Macromedia\Flash Player\Logs\flashlog.txt'
        do {
            $liveTrace = [IO.File]::ReadAllText($liveLog)
            $begin = $liveTrace.IndexOf($start)
            if ($begin -ge 0) { $trace = $liveTrace.Substring($begin) }
            if ($trace.Contains($end)) { break }
            Start-Sleep -Milliseconds 500
        } while ([DateTime]::UtcNow -lt $scaleDeadline)
        [IO.File]::WriteAllText($tracePath, $trace, [Text.UTF8Encoding]::new($false))
        if ($trace -notmatch '\[STASH_SCALE_COMPLETE\] success=true' -or
            [regex]::Matches($trace, '\[STASH_SCALE\]').Count -ne 5) { throw 'Real scale closure is incomplete.' }
        $trace -split "`r?`n" | Where-Object { $_ -match 'STASH_SCALE' } | Write-Host
    }
    if ((Get-Item -LiteralPath $tracePath).LastWriteTimeUtc -lt $started -or
        [regex]::Matches($trace,[regex]::Escape($start)).Count -ne 1 -or
        [regex]::Matches($trace,[regex]::Escape($end)).Count -ne 1 -or
        $trace.IndexOf($end) -le $trace.IndexOf($start) -or
        $trace -notmatch 'RewardStashServiceTest Tests Failed: 0' -or
        $trace -notmatch 'RewardStashServiceTest Tests Passed: 114' -or
        $trace -match '\[FAIL\]') {
        [IO.File]::WriteAllText($uncertainPath, "Reward stash behavior closure missing: $runId")
        throw 'Fresh reward-stash behavior closure is missing.'
    }
    Write-Host "[OK] Reward stash AS2 behavior passed; runId=$runId"
} finally {
    if ($null -eq $oldLease) { Remove-Item Env:CF7_FLASH_COMPILE_LEASE -ErrorAction SilentlyContinue }
    else { $env:CF7_FLASH_COMPILE_LEASE = $oldLease }
    try {
        if ($transaction -and $installedHash) { Restore-Cf7TestLoaderScratchTransaction -Transaction $transaction -InstalledHash $installedHash }
    } finally {
        if ($held) { $mutex.ReleaseMutex() }
        $mutex.Dispose()
    }
}
