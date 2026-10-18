$ErrorActionPreference='Stop'
chcp.com 65001 | Out-Null
$taskDir='tmp/cf6-combat-calibration-20261017'
if(-not(Test-Path -LiteralPath 'tmp/arena-worker-experiments/cf6-cal-r17-pilot-20261018/experiment-report.json')){throw 'R17 pilot is not complete'}
if(-not(Test-Path -LiteralPath 'tools/cf6-elder-assets/evidence/20261017-calibration/history/r17-pilot-awake/phase-aware-summary.json')){throw 'R17 collection is incomplete'}
$taskDisplay=@(Get-Content -LiteralPath "$taskDir/display-qualified-20261018-r5/display-state.jsonl" | ForEach-Object {$_ | ConvertFrom-Json})
$taskLastOn=@($taskDisplay | Where-Object {$_.event -eq 'state_observed'})[-1]
$taskLast=$taskDisplay[-1]
$taskAge=((Get-Date).ToUniversalTime()-([datetime]$taskLast.utc).ToUniversalTime()).TotalSeconds
if($taskLastOn.state -ne 1 -or $taskAge -lt 0 -or $taskAge -gt 30){throw 'Display observation is off, unknown or stale'}
if($taskDisplay | Where-Object {$_.event -in @('subscription_ended','scope_failed','display_request_released')}){throw 'Display scope has ended'}
if(Test-Path -LiteralPath 'tmp/arena-worker-experiments/cf6-cal-head-c4-20261018/execution-started.json'){throw 'C4 integration already started; do not replay'}
& node tools/arena-calibration/run-worker-experiment.js --plan "$taskDir/arena-head-c4/experiment-plan.json" *> "$taskDir/head-c4-runner.log"
exit $LASTEXITCODE
