$ErrorActionPreference='Stop'
chcp.com 65001 | Out-Null
$taskDir='tmp/cf6-combat-calibration-20261017'
$taskPurpose=Get-Content -LiteralPath "$taskDir/arena-head-c5/preregistered-purpose.json" -Raw -Encoding utf8 | ConvertFrom-Json
$taskDisplay=@(Get-Content -LiteralPath $taskPurpose.displayLog -Encoding utf8 | ForEach-Object {$_ | ConvertFrom-Json})
$taskLastOn=@($taskDisplay | Where-Object {$_.event -eq 'state_observed'})[-1]
$taskLast=$taskDisplay[-1]
$taskAge=((Get-Date).ToUniversalTime()-([datetime]$taskLast.utc).ToUniversalTime()).TotalSeconds
if($taskLastOn.state -ne 1 -or $taskAge -lt 0 -or $taskAge -gt 30){throw 'Display observation is off, unknown or stale'}
if($taskDisplay | Where-Object {$_.event -in @('subscription_ended','scope_failed','display_request_released')}){throw 'Display scope has ended'}
if(Test-Path -LiteralPath 'tmp/arena-worker-experiments/cf6-cal-head-c5-20261018/execution-started.json'){throw 'C5 full matrix already started; do not replay'}
& node tools/arena-calibration/run-worker-experiment.js --plan "$taskDir/arena-head-c5/experiment-plan.json" *> "$taskDir/head-c5-runner.log"
$taskExitCode=$LASTEXITCODE
if($taskExitCode -ne 0){exit $taskExitCode}
$taskDisplayScope=Split-Path -Leaf (Split-Path -Parent $taskPurpose.displayLog)
& python -X utf8 -B "$taskDir/close-final-display-scope.py" --scope $taskDisplayScope --last-experiment cf6-cal-head-c5-20261018 *> "$taskDir/head-c5-immediate-display-release.log"
exit $LASTEXITCODE
