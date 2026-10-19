$ErrorActionPreference='Stop'
chcp.com 65001 | Out-Null
$taskDir='tmp/cf6-combat-calibration-20261017'
if(-not(Test-Path -LiteralPath 'tmp/arena-worker-experiments/cf6-cal-head-c4-20261018/experiment-report.json')){throw 'Head C4 integration is still active'}
$taskBuild=Get-Content -LiteralPath "$taskDir/build-r18-elder/elder/identity.json" -Raw -Encoding UTF8 | ConvertFrom-Json
if($taskBuild.exitCode -ne 0){throw 'R18 publication is not qualified'}
if((Get-FileHash -LiteralPath $taskBuild.swf -Algorithm SHA256).Hash -ne $taskBuild.sha256){throw 'R18 published resource changed'}
& python -X utf8 -B tools/cf6-audio/build-test-fixture.py *> "$taskDir/audio-fixture-r18-generation.log"
if($LASTEXITCODE -ne 0){throw 'R18 audio fixture generation failed'}
& powershell -NoProfile -ExecutionPolicy Bypass -File "$taskDir/run-bound-validation.ps1" -PlanPath "$taskDir/native-r18-near-shield-budget-plan.json"
exit $LASTEXITCODE
