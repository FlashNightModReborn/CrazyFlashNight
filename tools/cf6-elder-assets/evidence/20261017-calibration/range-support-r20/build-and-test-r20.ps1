$ErrorActionPreference='Continue'
chcp.com 65001 | Out-Null
$taskDir='tmp/cf6-combat-calibration-20261017'
& python -X utf8 -B tools/cf6-elder-assets/build.py --import-approved *> "$taskDir/elder-r20-generate.log"
if($LASTEXITCODE -ne 0){throw 'R20 XFL generation failed'}
& python -X utf8 -B tools/cf6-elder-assets/build.py --check *> "$taskDir/elder-r20-generator-check.log"
if($LASTEXITCODE -ne 0){throw 'R20 generator check failed'}
& python -X utf8 -B tools/cf6-elder-assets/balance.py *> "$taskDir/elder-r20-balance-check.log"
if($LASTEXITCODE -ne 0){throw 'R20 unchanged action formula check failed'}
& powershell -NoProfile -ExecutionPolicy Bypass -File "$taskDir/build-r20-elder.ps1"
if($LASTEXITCODE -ne 0){throw 'R20 resource compilation failed'}
& python -X utf8 -B tools/cf6-audio/build-test-fixture.py *> "$taskDir/audio-fixture-r20-generation.log"
if($LASTEXITCODE -ne 0){throw 'R20 audio fixture generation failed'}
& python -X utf8 -B tools/cf6-elder-assets/verify.py *> "$taskDir/elder-r20-resource-verification.log"
if($LASTEXITCODE -ne 0){throw 'R20 resource verification failed'}
& powershell -NoProfile -ExecutionPolicy Bypass -File "$taskDir/run-bound-validation.ps1" -PlanPath "$taskDir/native-r20-range-support-plan.json"
exit $LASTEXITCODE
