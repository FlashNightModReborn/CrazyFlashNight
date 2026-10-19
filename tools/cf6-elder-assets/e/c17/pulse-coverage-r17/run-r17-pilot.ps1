$ErrorActionPreference='Stop'
chcp.com 65001 | Out-Null
$taskDir='tmp/cf6-combat-calibration-20261017'
& powershell -NoProfile -ExecutionPolicy Bypass -File "$taskDir/finish-native-cleanup-after-r17.ps1"
if($LASTEXITCODE -ne 0){throw 'R17 native cleanup failed'}
& python -X utf8 -B tools/cf6-elder-assets/verify.py *> "$taskDir/verify-elder-r17.log"
if($LASTEXITCODE -ne 0){throw 'R17 resource verification failed'}
& python -X utf8 -B "$taskDir/check-elder-r17-image-equivalence.py"
if($LASTEXITCODE -ne 0){throw 'R17 graphic equivalence failed'}
& python -X utf8 -B "$taskDir/sync-workers.py" r19
if($LASTEXITCODE -ne 0){throw 'R17 Worker synchronization failed'}
& python -X utf8 -B "$taskDir/prepare-r17-pilot.py"
if($LASTEXITCODE -ne 0){throw 'R17 plan preparation failed'}
$taskDisplay=@(Get-Content -LiteralPath "$taskDir/display-qualified-20261018-r5/display-state.jsonl" | ForEach-Object {$_ | ConvertFrom-Json})
$taskLastOn=@($taskDisplay | Where-Object {$_.event -eq 'state_observed'})[-1]
$taskLast=$taskDisplay[-1]
$taskAge=((Get-Date).ToUniversalTime()-([datetime]$taskLast.utc).ToUniversalTime()).TotalSeconds
if($taskLastOn.state -ne 1 -or $taskAge -lt 0 -or $taskAge -gt 30){throw 'Display observation is off, unknown or stale'}
if($taskDisplay | Where-Object {$_.event -in @('subscription_ended','scope_failed','display_request_released')}){throw 'Display scope has ended'}
if(Test-Path -LiteralPath 'tmp/arena-worker-experiments/cf6-cal-r17-pilot-20261018/execution-started.json'){throw 'R17 already started; do not replay'}
& node tools/arena-calibration/run-worker-experiment.js --plan "$taskDir/arena-r17-pilot/experiment-plan.json" *> "$taskDir/r17-pilot-runner.log"
exit $LASTEXITCODE
