$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'scripts/test-runners/testplayer-control.ps1')
$fixtureRoot = Join-Path (Split-Path -Parent $PSScriptRoot) ('tmp/testplayer-control-fixtures/' + [Guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $fixtureRoot -Force)
$script:submissions = 0
$script:caseMode = ''
$script:caseScripts = ''
function Get-Process {
    param($Name,$Id,$ErrorAction)
    if ($script:fakeExited) { return @() }
    return [pscustomobject]@{Id=123;StartTime=[DateTime]'2026-10-12T10:00:00Z';Path='C:\Flash.exe';Responding=($script:caseMode -cne 'unresponsive')}
}
function Get-ScheduledTask {
    param($TaskName)
    $state = if ($TaskName -ceq 'FlashCS6Task' -and $script:caseMode -ceq 'owned-stop' -and -not $script:fakeExited) {'Running'} else {'Ready'}
    return [pscustomobject]@{State=$state;Actions=@([pscustomobject]@{Execute='C:\Flash.exe'})}
}
function Stop-ScheduledTask {
    param($TaskName,$ErrorAction)
    $script:stopSubmissions++
    $script:fakeExited = $true
}
function Start-ScheduledTask {
    param($TaskName,$ErrorAction)
    $script:submissions++
    $cfg = Join-Path $script:caseScripts 'testplayer_control.cfg'
    if ($script:caseMode -ceq 'unresponsive') { return }
    $nonce = ([IO.File]::ReadAllText($cfg)).Split("`n")[1]
    Remove-Item -LiteralPath $cfg
    $closed = if ($script:submissions -eq 1 -and $script:caseMode -cne 'already-stopped') {'true'} else {'false'}
    if ($script:caseMode -ceq 'reappeared') { $closed = 'true' }
    if ($script:caseMode -ceq 'wrong-nonce') { $nonce = '0' * 32 }
    $body = "$nonce`nclosed=$closed`ndocuments=1`nfile:///C|/TestLoader.xfl"
    if ($script:caseMode -like 'output-clear*') {
        $body = "$nonce`nclosed=false`ndocuments=1`nfile:///C|/TestLoader.xfl`nowned=true"
        if ($script:caseMode -ceq 'output-clear') { $body += "`noutput_cleared=true" }
    }
    if ($script:caseMode -ceq 'malformed') { $body = "$nonce`nclosed=maybe" }
    if ($script:caseMode -ceq 'close-error') { $body = "$nonce`nERROR`nfixture close error" }
    [IO.File]::WriteAllText((Join-Path $script:caseScripts 'testplayer_control.receipt'),$body,[Text.UTF8Encoding]::new($false))
}
foreach ($mode in @('close','already-stopped','reappeared','wrong-nonce','malformed','close-error','unresponsive','pending-compile')) {
    $script:caseMode = $mode
    $script:caseScripts = Join-Path $fixtureRoot "$mode/scripts"
    [void](New-Item -ItemType Directory -Path $script:caseScripts -Force)
    $script:submissions = 0
    $script:fakeExited = $false
    if ($mode -ceq 'pending-compile') { [IO.File]::WriteAllText((Join-Path $script:caseScripts 'compile_target.cfg'),'pending') }
    $accepted = $false
    try { $result = Invoke-Cf7StopTestPlayers -ScriptsDirectory $script:caseScripts -ControlTimeoutSeconds 1; $accepted = $result.stopped }
    catch { $reason = $_.Exception.Message }
    $expected = $mode -cin @('close','already-stopped')
    if ($accepted -ne $expected) { throw "Control fixture $mode expected=$expected accepted=$accepted reason=$reason" }
    if ($mode -ceq 'pending-compile' -and $script:submissions -ne 0) { throw 'Unsafe control was submitted' }
    if ($expected -and $script:submissions -ne 2) { throw 'Stop must use two separate nonce-bound invocations' }
}
$ownershipMarker = Join-Path $fixtureRoot 'owned.marker'
$taintMarker = Join-Path $fixtureRoot 'taint.marker'
$identity = @{pid=123;start_ticks=([DateTime]'2026-10-12T10:00:00Z').Ticks;observed_path='C:\Flash.exe';task_execute='C:\Flash.exe';ownership_marker=$ownershipMarker;ownership_body="fixture`nexclusive=true";taint_marker=$taintMarker}
foreach ($field in @('pid','start_ticks','observed_path','task_execute','task-idle','tainted','guard-changed','valid')) {
    $script:caseMode = 'owned-stop';$script:fakeExited = $false;$script:stopSubmissions = 0
    $probe = $identity.Clone()
    [IO.File]::WriteAllText($ownershipMarker,$identity.ownership_body)
    Remove-Item -LiteralPath $taintMarker -ErrorAction SilentlyContinue
    if ($field -ceq 'pid') { $probe.pid=999 }
    if ($field -ceq 'start_ticks') { $probe.start_ticks=1 }
    if ($field -ceq 'observed_path') { $probe.observed_path='C:\Unowned.exe' }
    if ($field -ceq 'task_execute') { $probe.task_execute='C:\Changed.exe' }
    if ($field -ceq 'task-idle') { $script:caseMode='stale-task' }
    if ($field -ceq 'tainted') { [IO.File]::WriteAllText($taintMarker,'foreign') }
    if ($field -ceq 'guard-changed') { [IO.File]::WriteAllText($ownershipMarker,'another owner') }
    $accepted = $false
    try { $stopped = Stop-Cf7OwnedReadOnlyTestHost -Identity $probe;$accepted=$stopped.process_exit_verified } catch {}
    if ($accepted -ne ($field -ceq 'valid')) { throw "Owned host identity fixture failed: $field" }
    if ($field -cne 'valid' -and $script:stopSubmissions -ne 0) { throw 'Unowned host stop was submitted' }
}
foreach ($mode in @('output-clear','output-clear-missing-ack')) {
    $script:caseMode=$mode;$script:submissions=0;$script:fakeExited=$false
    $script:caseScripts=Join-Path $fixtureRoot "$mode/scripts"
    [void](New-Item -ItemType Directory -Path $script:caseScripts -Force)
    $accepted=$false
    try {
        $cleared=Invoke-Cf7StopTestPlayers -ScriptsDirectory $script:caseScripts -Operation clear_owned_test_output -ControlTimeoutSeconds 1
        $accepted=$cleared.output_cleared -and -not $cleared.stopped
    } catch {}
    if ($accepted -ne ($mode -ceq 'output-clear')) { throw "Output clear fixture failed: $mode" }
    if ($script:submissions -ne 1) { throw 'Output clear must use one acknowledged call without closing the player' }
}
Write-Host 'Test player control: 18/18 fixtures passed'
