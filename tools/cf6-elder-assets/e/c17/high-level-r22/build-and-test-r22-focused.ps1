$ErrorActionPreference='Continue'
chcp.com 65001 | Out-Null
$taskDir='tmp/cf6-combat-calibration-20261017'
& python -X utf8 -B tools/cf6-elder-assets/build.py --import-approved *> "$taskDir/elder-r22-generate.log"
if($LASTEXITCODE -ne 0){throw 'R22 XFL generation failed'}
& python -X utf8 -B tools/cf6-elder-assets/build.py --check *> "$taskDir/elder-r22-generator-check.log"
if($LASTEXITCODE -ne 0){throw 'R22 generator check failed'}
& python -X utf8 -B tools/cf6-elder-assets/balance.py *> "$taskDir/elder-r22-balance-check.log"
if($LASTEXITCODE -ne 0){throw 'R22 unchanged action formula check failed'}
& powershell -NoProfile -ExecutionPolicy Bypass -File "$taskDir/build-r22-elder.ps1"
if($LASTEXITCODE -ne 0){throw 'R22 resource compilation failed'}
& python -X utf8 -B tools/cf6-audio/build-test-fixture.py *> "$taskDir/audio-fixture-r22-generation.log"
if($LASTEXITCODE -ne 0){throw 'R22 audio fixture generation failed'}
& python -X utf8 -B tools/cf6-elder-assets/verify.py *> "$taskDir/elder-r22-resource-verification.log"
if($LASTEXITCODE -ne 0){throw 'R22 resource verification failed'}
& powershell -NoProfile -ExecutionPolicy Bypass -File "$taskDir/run-bound-validation.ps1" -PlanPath "$taskDir/native-r22-focused-plan.json"
exit $LASTEXITCODE
