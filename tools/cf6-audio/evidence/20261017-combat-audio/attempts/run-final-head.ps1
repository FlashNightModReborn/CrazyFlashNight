$ErrorActionPreference='Stop'
chcp.com 65001 | Out-Null
$taskDir='tmp/cf6-combat-audio-20261017'
& python -X utf8 -B "$taskDir/sync-legacy-workers.py"
if($LASTEXITCODE -ne 0){throw 'Worker sync failed'}
& node tools/cf6-headbot-assets/arena-plan.js "$taskDir/arena-headbot-final-config.json" *> "$taskDir/arena-headbot-final-after-legacy-plan.log"
if($LASTEXITCODE -ne 0){throw 'Final Head plan failed'}
& node tools/arena-calibration/run-worker-experiment.js --plan "$taskDir/arena-headbot-final/experiment-plan.json" *> "$taskDir/arena-headbot-final-after-legacy-run.log"
if($LASTEXITCODE -ne 0){throw 'Final Head experiment failed'}
