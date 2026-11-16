param([Parameter(Mandatory=$true)][string]$BaselineRoot)
$ErrorActionPreference = 'Stop'
$baseline = (Resolve-Path -LiteralPath $BaselineRoot).Path
$candidateRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
if ($baseline -ieq $candidateRoot) { throw 'Control tests require an isolated baseline.' }
if (-not (Test-Path -LiteralPath (Join-Path $baseline '.git') -PathType Leaf)) { throw 'Use an isolated linked baseline worktree.' }
$expectedCommit = (Get-Content -LiteralPath (Join-Path $PSScriptRoot '../baseline.json') -Raw -Encoding UTF8 | ConvertFrom-Json).sourceCommit
if ((git -C $baseline rev-parse HEAD) -cne $expectedCommit) { throw 'Unexpected baseline commit.' }
foreach ($marker in @('compile_state_uncertain.marker','testloader_scratch_inflight.marker','testplayer_control.cfg')) {
    if (Test-Path -LiteralPath (Join-Path $baseline ('scripts\'+$marker))) { throw ('Unresolved state: '+$marker) }
}
$classBase = 'scripts/类定义/org/flashNight/gesh/tooltip/test/'
foreach ($name in @('TooltipCaptureControl','TooltipCaptureControlProbe')) {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot ('as2/org/flashNight/gesh/tooltip/test/'+$name+'.as')) -Destination (Join-Path $baseline ($classBase+$name+'.as')) -Force
}
$controlDir = Join-Path $baseline 'tmp/tooltip-paired-capture'
New-Item -ItemType Directory -Path $controlDir -Force | Out-Null
$controlPath = Join-Path $controlDir 'output-control.xml'
$controlUri = 'file:///' + $controlPath.Replace('\','/')
$runId = [Guid]::NewGuid().ToString('N')
$nonce = [Guid]::NewGuid().ToString('N')
[IO.File]::WriteAllText($controlPath,('<captureControl runId="'+$runId+'" state="pause" nonce="'+$nonce+'"/>'),[Text.UTF8Encoding]::new($false))
$relativeFixture = 'tmp/tooltip-paired-capture/control-TestLoader.as.template'
$template = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'control-TestLoader.as.template'))
$template = $template.Replace('__CONTROL_RUN_ID__',$runId).Replace('__CONTROL_URI__',($controlUri | ConvertTo-Json -Compress))
[IO.File]::WriteAllText((Join-Path $baseline $relativeFixture),$template,[Text.UTF8Encoding]::new($true))
$liveLog = Join-Path $env:APPDATA 'Macromedia/Flash Player/Logs/flashlog.txt'
$watcher = Start-Job -ArgumentList @($liveLog,$controlPath,$runId,$nonce) -ScriptBlock {
    param($Log,$Control,$Run,$Nonce)
    $deadline = [DateTime]::UtcNow.AddSeconds(300)
    $needle = 'TC_CAPTURE_PAUSED|'+$Run+'|'+$Nonce+'|'
    while ([DateTime]::UtcNow -lt $deadline) {
        if ((Test-Path -LiteralPath $Log) -and [IO.File]::ReadAllText($Log).Contains($needle)) {
            [IO.File]::WriteAllText($Control,('<captureControl runId="'+$Run+'" state="run" nonce="'+$Nonce+'"/>'),[Text.UTF8Encoding]::new($false))
            Write-Output 'Observed a fresh pause acknowledgement; resumed the same probe.'
            return
        }
        Start-Sleep -Milliseconds 100
    }
    throw 'Capture control probe did not acknowledge pause.'
}
try {
    $parameters = @{
        DomainId='tooltip-capture-control';TemplateRelativePath=$relativeFixture
        SuiteRelativePaths=@($classBase+'TooltipCaptureControlProbe.as')
        SuiteFqns=@('org.flashNight.gesh.tooltip.test.TooltipCaptureControlProbe')
        AdditionalAsRelativePaths=@($classBase+'TooltipCaptureControl.as')
        ExpectedTracePatterns=@('CAPTURE_CONTROL_PROBE\|passed')
        SuccessSummary='Fresh AVM1 acknowledged pause before resuming the same export pump.'
        TimeoutSeconds=240;AsyncBehaviorTimeoutSeconds=30
    }
    & (Join-Path $baseline 'scripts/test-runners/run-focused-testloader.ps1') @parameters
    $code=$LASTEXITCODE
    Receive-Job -Job $watcher -Wait -ErrorAction Stop
    exit $code
} finally {
    if ($watcher.State -eq 'Running') { Stop-Job -Job $watcher }
    Remove-Job -Job $watcher -Force
}
