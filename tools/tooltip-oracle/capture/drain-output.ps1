param(
    [Parameter(Mandatory=$true)][string]$BaselineRoot,
    [Parameter(Mandatory=$true)][int]$ParentPid,
    [Parameter(Mandatory=$true)][int]$FlashPid,
    [Parameter(Mandatory=$true)][ValidatePattern('^[a-f0-9]{32}$')][string]$RunId,
    [Parameter(Mandatory=$true)][ValidatePattern('^[a-f0-9]{32}$')][string]$ScratchToken,
    [string]$ColdHostProofPath,
    [switch]$ResumeBeforeFirstControl,
    [ValidateRange(1,60)][int]$IntervalSeconds=10
)
$ErrorActionPreference='Stop'
$root=(Resolve-Path -LiteralPath $BaselineRoot).Path
$scriptsRoot=Join-Path $root 'scripts'
$scratchPath=Join-Path $scriptsRoot 'testloader_scratch_inflight.marker'
$setupPath=Join-Path $root 'tmp/tooltip-paired-capture/setup.json'
$controlPath=Join-Path $root 'tmp/tooltip-paired-capture/output-control.xml'
$liveLog=Join-Path $env:APPDATA 'Macromedia/Flash Player/Logs/flashlog.txt'
$evidenceRoot=Join-Path $root 'tmp/tooltip-paired-capture/output-drain'
if(-not (Test-Path -LiteralPath (Join-Path $root '.git') -PathType Leaf)){throw 'Use an isolated linked baseline.'}
$setup=Get-Content -LiteralPath $setupPath -Raw -Encoding UTF8|ConvertFrom-Json
if($setup.target -ine $root -or $setup.candidateRoot -ieq $root){throw 'Capture setup target differs.'}
if((git -C $root rev-parse HEAD) -cne $setup.sourceCommit){throw 'Capture baseline commit differs.'}
foreach($entry in $setup.files.psobject.Properties){
    if((Get-FileHash -LiteralPath (Join-Path $root $entry.Name) -Algorithm SHA256).Hash -ine $entry.Value){throw ('Prepared source drift: '+$entry.Name)}
}
if(Test-Path -LiteralPath $evidenceRoot){
    if(-not $ResumeBeforeFirstControl){throw 'Output drain evidence already exists.'}
    foreach($name in @('checkpoints.json','host-ownership.json')){if(Test-Path -LiteralPath (Join-Path $evidenceRoot $name)){throw 'Resume is limited to failure before the first output control.'}}
    if([IO.File]::ReadAllText($controlPath) -cne "<captureControl state=`"run`"/>`n"){throw 'Initial capture control changed; inspect its acknowledgement instead of replaying.'}
    $priorAdmission=Get-Content -LiteralPath (Join-Path $evidenceRoot 'compiler-idle.json') -Raw -Encoding UTF8|ConvertFrom-Json
    if($priorAdmission.parentPid -ne $ParentPid -or $priorAdmission.flashPid -ne $FlashPid -or $priorAdmission.scratchToken -cne $ScratchToken -or $priorAdmission.machineLeaseIdle -ne $true -or $priorAdmission.uncertainMarkerAbsent -ne $true){throw 'Previous compiler admission belongs to another capture.'}
    foreach($name in @('testhost_ownership.marker','testhost_foreign_document.marker')){if(Test-Path -LiteralPath (Join-Path $scriptsRoot $name)){throw 'A prior output owner requires separate recovery.'}}
}else{
    if($ResumeBeforeFirstControl){throw 'No previous admission to resume.'}
    New-Item -ItemType Directory -Path $evidenceRoot|Out-Null
}
$record=Get-Content -LiteralPath $scratchPath -Raw -Encoding UTF8|ConvertFrom-Json
if($record.token -cne $ScratchToken -or $record.owner_pid -ne $ParentPid -or $record.owner_kind -cne 'focused:tooltip-corpus'){throw 'Capture scratch owner differs.'}
. (Join-Path $scriptsRoot 'test-runners/testloader-scratch-transaction.ps1')
. (Join-Path $scriptsRoot 'test-runners/testplayer-control.ps1')
Assert-Cf7TestLoaderScratchAdmission -MarkerPath $scratchPath -RunnerPath $record.runner_path -RepoHash $record.repo_hash -CompileLease $record.compile_lease -LeaseOwnerPid $ParentPid
$hosts=@(Get-Process -Name Flash)
if($hosts.Count -ne 1 -or $hosts[0].Id -ne $FlashPid){throw 'Capture cold host identity differs.'}
if($ColdHostProofPath){
    $proof=Get-Content -LiteralPath $ColdHostProofPath -Raw -Encoding UTF8|ConvertFrom-Json
    if($proof.controllerPid -ne $PID -and (-not $ResumeBeforeFirstControl -or (Get-Process -Id $proof.controllerPid -ErrorAction SilentlyContinue))){throw 'Cold capture controller is different or still running.'}
    if($proof.schema -cne 'cf7.tooltip-capture-cold-host.v1' -or $proof.baselineRoot -ine $root -or
       $proof.noPriorFlash -ne $true -or $proof.hostPid -ne $FlashPid -or $proof.hostStartTicks -cne [string]$hosts[0].StartTime.Ticks -or
       $hosts[0].StartTime.ToUniversalTime() -lt ([DateTime]$proof.intentUtc).ToUniversalTime().AddSeconds(-1) -or
       ([DateTime]$record.created_utc).ToUniversalTime() -lt ([DateTime]$proof.readyUtc).ToUniversalTime() -or $proof.phaseReceipts.Count -ne 2){throw 'Controlled cold prewarm proof differs from this capture.'}
    $receiptRoot=[IO.Path]::GetFullPath((Join-Path $root 'tmp/flash-testplayer-control')).TrimEnd('\')+'\'
    foreach($phase in $proof.phaseReceipts){
        $phasePath=[IO.Path]::GetFullPath($phase.path)
        if(-not $phasePath.StartsWith($receiptRoot,[StringComparison]::OrdinalIgnoreCase) -or
           (Get-FileHash -LiteralPath $phasePath -Algorithm SHA256).Hash -cne $phase.sha256 -or
           [IO.File]::ReadAllText($phasePath) -notmatch '^[a-f0-9]{32}\nclosed=false\ndocuments=0$'){throw 'Cold prewarm readiness receipt differs.'}
    }
}elseif($hosts[0].StartTime.ToUniversalTime() -lt ([DateTime]$record.created_utc).ToUniversalTime()){throw 'Capture host predates its scratch transaction without a controlled cold prewarm proof.'}
$hostStartTicks=$hosts[0].StartTime.Ticks
$parentMutex=[Threading.Mutex]::new($false,('Local\CF7_FlashCompile_'+$record.repo_hash))
try{if($parentMutex.WaitOne(0)){$parentMutex.ReleaseMutex();throw 'Capture parent does not hold its transaction.'}}finally{$parentMutex.Dispose()}
$machine=[Threading.Mutex]::new($false,'Local\CF7_FlashCompile_MachineGlobal')
$held=$false
$receiptRows=@()
$runEscaped=[regex]::Escape($RunId)

function Assert-CaptureIdentity {
    if(-not (Get-Process -Id $ParentPid -ErrorAction SilentlyContinue)){throw 'Capture parent ended while paused; inspect terminal evidence.'}
    $current=Get-Content -LiteralPath $scratchPath -Raw -Encoding UTF8|ConvertFrom-Json
    if($current.token -cne $ScratchToken -or $current.owner_pid -ne $ParentPid){throw 'Capture transaction changed.'}
    $currentHosts=@(Get-Process -Name Flash)
    if($currentHosts.Count -ne 1 -or $currentHosts[0].Id -ne $FlashPid -or $currentHosts[0].StartTime.Ticks -ne $hostStartTicks){throw 'Capture host changed.'}
}
function Assert-SameCapture {
    Assert-CaptureIdentity
    if(Test-Path -LiteralPath (Join-Path $scriptsRoot 'compile_state_uncertain.marker')){throw 'Capture has uncertain state.'}
}
function Write-Control([string]$State,[string]$Nonce){
    $pending=$controlPath+'.'+[Guid]::NewGuid().ToString('N')+'.pending'
    $body='<captureControl runId="'+$RunId+'" state="'+$State+'" nonce="'+$Nonce+'"/>'
    [IO.File]::WriteAllText($pending,$body,[Text.UTF8Encoding]::new($false))
    # A real backup path also avoids Windows PowerShell 5 converting a null
    # string argument into an invalid empty backup filename.
    $previous=Join-Path $evidenceRoot ('control-'+$Nonce+'-'+$State+'.previous.xml')
    [IO.File]::Replace($pending,$controlPath,$previous)
}
function Read-LiveTrace {
    $stream=[IO.File]::Open($liveLog,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
    $reader=[IO.StreamReader]::new($stream,[Text.Encoding]::UTF8,$true)
    try{
        $body=$reader.ReadToEnd()
        $lastNewline=$body.LastIndexOf("`n")
        if($lastNewline -lt 0){return ''}
        # Hash only complete lines; the writer may still hold the final UTF-8
        # codepoint or newline. The complete raw file remains untouched.
        return $body.Substring(0,$lastNewline+1)
    }finally{$reader.Dispose()}
}
function Get-TraceDigest([string]$Body){
    $hasher=[Security.Cryptography.SHA256]::Create()
    try{return ([BitConverter]::ToString($hasher.ComputeHash([Text.Encoding]::UTF8.GetBytes($Body)))).Replace('-','').ToLowerInvariant()}finally{$hasher.Dispose()}
}
try{
    $raw=Read-LiveTrace
    $beginMatches=[regex]::Matches($raw,'(?m)^TC_INPUT_BEGIN\|([^\r\n]+)\r?$')
    if($beginMatches.Count -ne 1 -or (($beginMatches[0].Groups[1].Value|ConvertFrom-Json).runId -cne $RunId)){throw 'Expected one fresh paired capture header.'}
    if(-not ([IO.File]::ReadAllText($record.runner_path).Contains($RunId))){throw 'Installed TestLoader differs from the capture run.'}
    if($ResumeBeforeFirstControl){
        if($raw -match ('(?m)^TC_CAPTURE_(?:PAUSED|RESUMED)\|'+$runEscaped+'\|')){throw 'A previous control acknowledgement exists; do not replay.'}
        [ordered]@{observedUtc=[DateTime]::UtcNow.ToString('o');controllerPid=$PID;originalControllerPid=$proof.controllerPid;parentPid=$ParentPid;flashPid=$FlashPid;runId=$RunId;initialControlUnchanged=$true;priorPauseOrResumeAbsent=$true;priorOutputClearAbsent=$true}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $evidenceRoot 'resumed-before-first-control.json') -Encoding UTF8
    }
    # TestMovie can emit its header before compile_test has observed its terminal
    # receipt and released the machine lease. In that phase its in-flight marker
    # is expected. Observe only identities until that exact compiler becomes idle;
    # no pause/output control may be submitted while it is active or uncertain.
    $admissionDeadline=[DateTime]::UtcNow.AddSeconds(30)
    do{
        Assert-CaptureIdentity
        $held=$machine.WaitOne(0)
        if($held){break}
        Start-Sleep -Milliseconds 100
    }while([DateTime]::UtcNow -lt $admissionDeadline)
    if(-not $held){throw 'Capture compiler did not release the machine lease before control admission.'}
    Assert-SameCapture
    $admissionName=if($ResumeBeforeFirstControl){'compiler-idle-resumed.json'}else{'compiler-idle.json'}
    [ordered]@{observedUtc=[DateTime]::UtcNow.ToString('o');parentPid=$ParentPid;flashPid=$FlashPid;scratchToken=$ScratchToken;machineLeaseIdle=$true;uncertainMarkerAbsent=$true}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $evidenceRoot $admissionName) -Encoding UTF8
    $machine.ReleaseMutex();$held=$false
    $inspected=$false
    for($iteration=0;$iteration -lt 1000;$iteration++){
        if(-not (Get-Process -Id $ParentPid -ErrorAction SilentlyContinue)){break}
        Assert-SameCapture
        $nonce=[Guid]::NewGuid().ToString('N')
        Write-Control 'pause' $nonce
        $pausePattern='(?m)^TC_CAPTURE_PAUSED\|'+$runEscaped+'\|'+$nonce+'\|native=(\d+)\|inputs=(\d+)\r?$'
        $deadline=[DateTime]::UtcNow.AddSeconds(30)
        do{
            $raw=Read-LiveTrace
            if($raw -match ('(?m)^TC_INPUT_END\|[^\r\n]*"runId":"'+$runEscaped+'"')){Write-Output 'Capture reached its footer; no further output clear.';return}
            Assert-SameCapture
            $ack=[regex]::Match($raw,$pausePattern)
            if($ack.Success){break}
            Start-Sleep -Milliseconds 100
        }while([DateTime]::UtcNow -lt $deadline)
        if(-not $ack.Success){throw 'No exact pause acknowledgement. Capture remains paused/pending for inspection.'}
        $native=[int]$ack.Groups[1].Value;$inputs=[int]$ack.Groups[2].Value
        $flushDeadline=[DateTime]::UtcNow.AddSeconds(3)
        do{
            $observedNative=[regex]::Matches($raw,'(?m)^TC_ITEM\|\d+\|').Count
            $observedInputs=[regex]::Matches($raw,'(?m)^TC_INPUT\|'+$runEscaped+'\|').Count
            if($observedNative -eq $native -and $observedInputs -eq $inputs){break}
            if($observedNative -gt $native -or $observedInputs -gt $inputs){break}
            Start-Sleep -Milliseconds 100
            Assert-SameCapture
            $raw=Read-LiveTrace
        }while([DateTime]::UtcNow -lt $flushDeadline)
        if($raw -match ('(?m)^TC_INPUT_ERROR\|'+$runEscaped+'\|')){throw 'Capture error before output clear.'}
        if($observedNative -ne $native -or $observedInputs -ne $inputs){
            [IO.File]::WriteAllText((Join-Path $evidenceRoot 'count-mismatch.trace'),$raw,[Text.UTF8Encoding]::new($false))
            throw ('Pause counter mismatch: native='+$observedNative+'/'+$native+'; inputs='+$observedInputs+'/'+$inputs+'. No output was cleared or expected record fabricated.')
        }
        $prefix=$raw;$digest=Get-TraceDigest $prefix
        # The parent compiler must have released the machine lease. The capture
        # stays paused while waiting; never race JSFL compile/testMovie.
        $deadline=[DateTime]::UtcNow.AddSeconds(30)
        do{$held=$machine.WaitOne(0);if($held){break};Start-Sleep -Milliseconds 100}while([DateTime]::UtcNow -lt $deadline)
        if(-not $held){throw 'Machine compile lease did not become idle while paused.'}
        Assert-SameCapture
        if(-not $inspected){
            $inspection=Invoke-Cf7StopTestPlayers -ScriptsDirectory $scriptsRoot -Operation inspect_owned_test_host -ControlTimeoutSeconds 30
            $inspection|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $evidenceRoot 'host-ownership.json') -Encoding UTF8
            $inspected=$true
        }
        $clear=Invoke-Cf7StopTestPlayers -ScriptsDirectory $scriptsRoot -Operation clear_owned_test_output -ControlTimeoutSeconds 30
        $after=Read-LiveTrace
        if(-not $after.StartsWith($prefix,[StringComparison]::Ordinal)){throw 'Raw trace prefix changed during the acknowledged pause. Do not resume.'}
        if([regex]::Matches($after,'(?m)^TC_ITEM\|\d+\|').Count -ne $native -or [regex]::Matches($after,'(?m)^TC_INPUT\|'+$runEscaped+'\|').Count -ne $inputs){throw 'Capture advanced during pause. Do not resume.'}
        $receiptRows += [ordered]@{iteration=$iteration;utc=[DateTime]::UtcNow.ToString('o');runId=$RunId;nonce=$nonce;native=$native;inputs=$inputs;tracePrefixCharacters=$prefix.Length;tracePrefixSha256=$digest;clear=$clear}
        $receiptRows|ConvertTo-Json -Depth 10|Set-Content -LiteralPath (Join-Path $evidenceRoot 'checkpoints.json') -Encoding UTF8
        $machine.ReleaseMutex();$held=$false
        Write-Control 'run' $nonce
        Write-Output ('Resumed after verified output clear: native='+$native+'; inputs='+$inputs)
        Start-Sleep -Seconds $IntervalSeconds
    }
}finally{if($held){$machine.ReleaseMutex()};$machine.Dispose()}
