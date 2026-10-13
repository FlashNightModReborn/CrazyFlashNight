function Invoke-Cf7StopTestPlayers {
    param(
        [Parameter(Mandatory = $true)][string]$ScriptsDirectory,
        [ValidateRange(1, 30)][int]$ControlTimeoutSeconds = 10,
        [ValidateSet('stop_test_players','inspect_owned_test_host','quit_owned_test_host','clear_owned_test_output')]
        [string]$Operation = 'stop_test_players'
    )
    # Caller holds the same repository compile mutex, including scratch admission.
    $controlCfg = Join-Path $ScriptsDirectory 'testplayer_control.cfg'
    $controlReceipt = Join-Path $ScriptsDirectory 'testplayer_control.receipt'
    foreach ($pending in @('compile_target.cfg','compile_mode.cfg','compile_reopen.marker','compile_quit_after_publish.cfg','testplayer_control.cfg')) {
        if (Test-Path -LiteralPath (Join-Path $ScriptsDirectory $pending)) {
            throw "Pending instruction blocks test player control: $pending"
        }
    }
    if ((Get-ScheduledTask -TaskName 'CompileTriggerTask').State -eq 'Running') {
        throw 'Compile trigger is still running; player control was not submitted.'
    }
    $hosts = @(Get-Process -Name Flash -ErrorAction SilentlyContinue)
    if ($hosts.Count -ne 1) {
        throw 'Player control requires one responsive CS6 host; no host is killed or cold-started.'
    }
    $hostIdentity = '{0}|{1}|{2}' -f $hosts[0].Id, $hosts[0].StartTime.Ticks, $hosts[0].Path
    $receiptDirectory = Join-Path (Split-Path -Parent $ScriptsDirectory) ('tmp/flash-testplayer-control/' + [Guid]::NewGuid().ToString('N'))
    [void](New-Item -ItemType Directory -Path $receiptDirectory -Force)
    $phases = @()
    $phaseCount = if ($Operation -in @('inspect_owned_test_host','clear_owned_test_output')) {1} else {2}
    for ($phase = 0; $phase -lt $phaseCount; $phase++) {
        $current = @(Get-Process -Name Flash -ErrorAction SilentlyContinue)
        if ($current.Count -ne 1 -or
            ('{0}|{1}|{2}' -f $current[0].Id,$current[0].StartTime.Ticks,$current[0].Path) -cne $hostIdentity) { throw 'CS6 host identity changed during player control.' }
        # Responding is only a sampled window heuristic (and can be false during
        # cold initialization). The nonce-bound JSFL acknowledgement is the gate.
        $nonce = [Guid]::NewGuid().ToString('N')
        # Preserve prior receipt; nonce rejects stale and cross-run acknowledgements.
        [IO.File]::WriteAllText($controlCfg, "$Operation`n$nonce", [Text.UTF8Encoding]::new($false))
        Start-ScheduledTask -TaskName 'CompileTriggerTask' -ErrorAction Stop
        $deadline = [DateTime]::UtcNow.AddSeconds($ControlTimeoutSeconds)
        $body = $null
        do {
            if (Test-Path -LiteralPath $controlReceipt) {
                $candidate = [IO.File]::ReadAllText($controlReceipt, [Text.Encoding]::UTF8)
                if ($candidate.StartsWith($nonce + "`n", [StringComparison]::Ordinal)) { $body = $candidate }
            }
            $taskReady = (Get-ScheduledTask -TaskName 'CompileTriggerTask').State -ne 'Running'
            if ($null -ne $body -and $taskReady) { break }
            Start-Sleep -Milliseconds 125
        } while ([DateTime]::UtcNow -lt $deadline)
        if ($null -eq $body -or -not $taskReady) {
            # Keep a possibly unconsumed instruction so another compile cannot inherit it.
            throw 'Test player control has no fresh idle acknowledgement; recovery stays blocked.'
        }
        [IO.File]::WriteAllText((Join-Path $receiptDirectory ("phase-$phase.receipt")), $body, [Text.UTF8Encoding]::new($false))
        $match = [regex]::Match($body, '^' + $nonce + '\nclosed=(true|false)\ndocuments=(\d+)(?:\n[^\r\n]+)*$')
        if (-not $match.Success) { throw 'Malformed or failed CS6 test player control acknowledgement.' }
        if ($Operation -cne 'stop_test_players' -and $body -notmatch '(?m)^owned=true$') {
            throw 'CS6 did not prove exclusive TestLoader document ownership.'
        }
        if ($Operation -ceq 'clear_owned_test_output' -and $body -notmatch '(?m)^output_cleared=true$') {
            throw 'CS6 did not acknowledge the owned Output Panel clear.'
        }
        if (Test-Path -LiteralPath $controlCfg) { throw 'CS6 did not consume the exact player control instruction.' }
        $phases += @{closed=($match.Groups[1].Value -ceq 'true');documents=[int]$match.Groups[2].Value}
        # A separate host invocation must see zero old players, after close has returned.
        if ($phase -eq 1 -and $phases[1].closed) { throw 'A player reappeared between stop and verification; recovery stays blocked.' }
        if ($Operation -ceq 'quit_owned_test_host') {
            $exitMatch = [regex]::Match($body, '(?m)^exit_requested=(true|false)$')
            if (-not $exitMatch.Success) { throw 'Owned host exit phase has no exact acknowledgement.' }
            if ($exitMatch.Groups[1].Value -ceq 'true') { break }
        }
    }
    if ($Operation -ceq 'quit_owned_test_host') {
        $deadline = [DateTime]::UtcNow.AddSeconds($ControlTimeoutSeconds)
        do {
            $remaining = @(Get-Process -Name Flash -ErrorAction SilentlyContinue)
            if ($remaining.Count -eq 0) { break }
            Start-Sleep -Milliseconds 125
        } while ([DateTime]::UtcNow -lt $deadline)
        if ($remaining.Count -ne 0) { throw 'Owned test host exit receipt did not produce actual process exit.' }
        return @{host=$hostIdentity;phases=$phases;receipts=$receiptDirectory;stopped=$true;owned=$true;exited=$true}
    }
    $current = @(Get-Process -Name Flash -ErrorAction SilentlyContinue)
    if ($current.Count -ne 1 -or
        ('{0}|{1}|{2}' -f $current[0].Id,$current[0].StartTime.Ticks,$current[0].Path) -cne $hostIdentity) {
        throw 'CS6 host changed after stop verification.'
    }
    return @{host=$hostIdentity;nonce=$nonce;phases=$phases;receipts=$receiptDirectory;stopped=($Operation -ceq 'stop_test_players');owned=($Operation -in @('inspect_owned_test_host','clear_owned_test_output'));output_cleared=($Operation -ceq 'clear_owned_test_output')}
}

function Start-Cf7OwnedReadOnlyTestHost {
    param([Parameter(Mandatory = $true)][string]$ScriptsDirectory)
    if (@(Get-Process -Name Flash -ErrorAction SilentlyContinue).Count -ne 0) {
        throw 'An owned read-only test host requires no pre-existing Flash process.'
    }
    $ownershipMarker = Join-Path $ScriptsDirectory 'testhost_ownership.marker'
    $taintMarker = Join-Path $ScriptsDirectory 'testhost_foreign_document.marker'
    if ((Test-Path -LiteralPath $ownershipMarker) -or (Test-Path -LiteralPath $taintMarker)) {
        throw 'An earlier owned host lease requires recovery; no new host was started.'
    }
    $editorTask = Get-ScheduledTask -TaskName 'FlashCS6Task' -ErrorAction Stop
    $triggerTask = Get-ScheduledTask -TaskName 'CompileTriggerTask' -ErrorAction Stop
    if ($editorTask.Actions.Count -ne 1 -or $triggerTask.Actions.Count -ne 1 -or
        $editorTask.Actions[0].Execute -ine $triggerTask.Actions[0].Execute -or
        -not [string]::IsNullOrWhiteSpace($editorTask.Actions[0].Arguments) -or
        $editorTask.Principal.RunLevel -ne 'Highest' -or
        $editorTask.Settings.ExecutionTimeLimit -ne 'PT0S' -or $editorTask.State -eq 'Running') {
        throw 'Owned test host requires the existing idle, native, unlimited CS6 lifecycle task.'
    }
    $started = [DateTime]::Now
    Start-ScheduledTask -TaskName 'FlashCS6Task' -ErrorAction Stop
    $deadline = [DateTime]::UtcNow.AddSeconds(15)
    do {
        $hosts = @(Get-Process -Name Flash -ErrorAction SilentlyContinue)
        if ($hosts.Count -eq 1 -and $hosts[0].Responding) { break }
        Start-Sleep -Milliseconds 125
    } while ([DateTime]::UtcNow -lt $deadline)
    if ($hosts.Count -ne 1 -or $hosts[0].StartTime -lt $started.AddSeconds(-1) -or
        (Get-ScheduledTask -TaskName 'FlashCS6Task').State -ne 'Running') {
        throw 'Fresh task-owned CS6 identity could not be established.'
    }
    # Initial splash creation can momentarily report Responding=true before
    # configuration loading occupies the UI thread. Let the host finish it.
    Start-Sleep -Milliseconds 500
    $ownership = Invoke-Cf7StopTestPlayers -ScriptsDirectory $ScriptsDirectory -Operation inspect_owned_test_host -ControlTimeoutSeconds 30
    if (-not $ownership.owned) { throw 'Fresh CS6 contains documents outside the disposable TestLoader scope.' }
    $ownershipBody = $ownership.nonce + "`nexclusive=true"
    if (-not (Test-Path -LiteralPath $ownershipMarker) -or [IO.File]::ReadAllText($ownershipMarker) -cne $ownershipBody) {
        throw 'The exact host ownership marker does not match its fresh JSFL receipt.'
    }
    return @{pid=$hosts[0].Id;start_ticks=$hosts[0].StartTime.Ticks;observed_path=$hosts[0].Path;task_execute=$editorTask.Actions[0].Execute;preflight=$ownership.receipts;ownership_marker=$ownershipMarker;ownership_body=$ownershipBody;taint_marker=$taintMarker}
}

function Stop-Cf7OwnedReadOnlyTestHost {
    param([Parameter(Mandatory = $true)]$Identity)
    $hosts = @(Get-Process -Name Flash -ErrorAction SilentlyContinue)
    if (-not (Test-Path -LiteralPath $Identity.ownership_marker) -or
        [IO.File]::ReadAllText($Identity.ownership_marker) -cne $Identity.ownership_body -or
        (Test-Path -LiteralPath $Identity.taint_marker)) {
        throw 'Owned editor document lease changed or was tainted; foreign documents are preserved.'
    }
    if ($hosts.Count -ne 1 -or $hosts[0].Id -ne $Identity.pid -or
        $hosts[0].StartTime.Ticks -ne $Identity.start_ticks -or $hosts[0].Path -ine $Identity.observed_path -or
        (Get-ScheduledTask -TaskName 'FlashCS6Task').State -ne 'Running' -or
        (Get-ScheduledTask -TaskName 'FlashCS6Task').Actions[0].Execute -ine $Identity.task_execute) {
        throw 'CS6 lifecycle identity drift; refusing to stop an unowned editor.'
    }
    # Task Scheduler ends only the host created by this runner. No arbitrary PID
    # killing, window input, task modification, or blind replay is performed.
    Stop-ScheduledTask -TaskName 'FlashCS6Task' -ErrorAction Stop
    $deadline = [DateTime]::UtcNow.AddSeconds(10)
    do {
        $remaining = @(Get-Process -Id $Identity.pid -ErrorAction SilentlyContinue)
        $triggerIdle = (Get-ScheduledTask -TaskName 'CompileTriggerTask').State -ne 'Running'
        $editorIdle = (Get-ScheduledTask -TaskName 'FlashCS6Task').State -ne 'Running'
        if ($remaining.Count -eq 0 -and $triggerIdle -and $editorIdle) { break }
        Start-Sleep -Milliseconds 125
    } while ([DateTime]::UtcNow -lt $deadline)
    if ($remaining.Count -ne 0 -or -not $triggerIdle -or -not $editorIdle) {
        throw 'Owned host or JSFL trigger is still alive; recovery stays blocked.'
    }
    return @{host=$Identity;stopped=$true;process_exit_verified=$true;trigger_idle=$true;editor_idle=$true}
}
