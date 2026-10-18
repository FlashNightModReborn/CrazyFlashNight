$ErrorActionPreference='Stop'
chcp.com 65001 | Out-Null
$taskDir='tmp/cf6-combat-calibration-20261017'
$taskPurpose=Get-Content -LiteralPath "$taskDir/arena-r22-full/preregistered-purpose.json" -Raw -Encoding utf8 | ConvertFrom-Json
if(-not $taskPurpose.firstArenaExecutionOfVariant -or $taskPurpose.expectedRows -ne 36){throw 'Wrong full-matrix purpose'}
if(-not(Test-Path -LiteralPath "tmp/arena-worker-experiments/$($taskPurpose.precedingPilotExperiment)/experiment-report.json")){throw 'Historical exploratory run is not complete'}
$taskDisplay=@(Get-Content -LiteralPath $taskPurpose.displayLog -Encoding utf8 | ForEach-Object {$_ | ConvertFrom-Json})
$taskLastOn=@($taskDisplay | Where-Object {$_.event -eq 'state_observed'})[-1];$taskLast=$taskDisplay[-1]
$taskAge=((Get-Date).ToUniversalTime()-([datetime]$taskLast.utc).ToUniversalTime()).TotalSeconds
if($taskLastOn.state -ne 1 -or $taskAge -lt 0 -or $taskAge -gt 30){throw 'Display observation is off, unknown or stale'}
if($taskDisplay | Where-Object {$_.event -in @('subscription_ended','scope_failed','display_request_released')}){throw 'Display scope has ended'}
if(Test-Path -LiteralPath 'tmp/arena-worker-experiments/cf6-cal-r22-full-20261018/execution-started.json'){throw 'R22 already started; do not replay'}
& node tools/arena-calibration/run-worker-experiment.js --plan "$taskDir/arena-r22-full/experiment-plan.json" *> "$taskDir/r22-full-runner.log"
exit $LASTEXITCODE
