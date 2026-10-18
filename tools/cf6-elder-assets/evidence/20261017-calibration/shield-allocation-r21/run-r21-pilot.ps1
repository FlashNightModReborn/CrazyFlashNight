$ErrorActionPreference='Stop'
chcp.com 65001 | Out-Null
$taskDir='tmp/cf6-combat-calibration-20261017'
& powershell -NoProfile -ExecutionPolicy Bypass -File "$taskDir/finish-native-cleanup-after-r21.ps1"
if($LASTEXITCODE -ne 0){throw 'R21 native cleanup failed'}
& python -X utf8 -B "$taskDir/check-r21-source-scope.py" *> "$taskDir/r21-source-scope-check.log"
if($LASTEXITCODE -ne 0){throw 'R21 source scope check failed'}
& node tools/audit-as2-class-embedding.js --json | Out-File -LiteralPath "$taskDir/class-closure-r21.json" -Encoding utf8
if($LASTEXITCODE -ne 0){throw 'R21 production class closure failed'}
& python -X utf8 -B tools/cf6-elder-assets/verify.py *> "$taskDir/verify-elder-r21.log"
if($LASTEXITCODE -ne 0){throw 'R21 resource verification failed'}
$taskRender=Get-Content -LiteralPath "$taskDir/r21-native-render-verification.json" -Raw -Encoding utf8 | ConvertFrom-Json
if(-not $taskRender.ok -or $taskRender.images -ne 12){throw 'R21 current native images are not verified'}
& python -X utf8 -B "$taskDir/sync-workers.py" r23
if($LASTEXITCODE -ne 0){throw 'R21 Worker synchronization failed'}
& python -X utf8 -B "$taskDir/prepare-r21-pilot.py"
if($LASTEXITCODE -ne 0){throw 'R21 plan preparation failed'}
$taskDisplay=@(Get-Content -LiteralPath "$taskDir/display-qualified-20261018-r7/display-state.jsonl" | ForEach-Object {$_ | ConvertFrom-Json})
$taskLastOn=@($taskDisplay | Where-Object {$_.event -eq 'state_observed'})[-1]
$taskLast=$taskDisplay[-1]
$taskAge=((Get-Date).ToUniversalTime()-([datetime]$taskLast.utc).ToUniversalTime()).TotalSeconds
if($taskLastOn.state -ne 1 -or $taskAge -lt 0 -or $taskAge -gt 30){throw 'Display observation is off, unknown or stale'}
if($taskDisplay | Where-Object {$_.event -in @('subscription_ended','scope_failed','display_request_released')}){throw 'Display scope has ended'}
if(Test-Path -LiteralPath 'tmp/arena-worker-experiments/cf6-cal-r21-pilot-20261018/execution-started.json'){throw 'R21 already started; do not replay'}
& node tools/arena-calibration/run-worker-experiment.js --plan "$taskDir/arena-r21-pilot/experiment-plan.json" *> "$taskDir/r21-pilot-runner.log"
exit $LASTEXITCODE
