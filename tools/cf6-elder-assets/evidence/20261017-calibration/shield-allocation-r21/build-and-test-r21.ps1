$ErrorActionPreference='Continue'
chcp.com 65001 | Out-Null
$taskDir='tmp/cf6-combat-calibration-20261017'
& python -X utf8 -B tools/cf6-elder-assets/build.py --import-approved *> "$taskDir/elder-r21-generate.log"
if($LASTEXITCODE -ne 0){throw 'R21 XFL generation failed'}
& python -X utf8 -B tools/cf6-elder-assets/build.py --check *> "$taskDir/elder-r21-generator-check.log"
if($LASTEXITCODE -ne 0){throw 'R21 generator check failed'}
& python -X utf8 -B tools/cf6-elder-assets/balance.py --write *> "$taskDir/elder-r21-balance-write.log"
if($LASTEXITCODE -ne 0){throw 'R21 action formula regeneration failed'}
& python -X utf8 -B tools/cf6-elder-assets/balance.py *> "$taskDir/elder-r21-balance-check.log"
if($LASTEXITCODE -ne 0){throw 'R21 action formula check failed'}
& node tools/derive-arena-unit-catalog.js *> "$taskDir/arena-catalog-r21-generation.log"
if($LASTEXITCODE -ne 0){throw 'R21 arena catalog regeneration failed'}
& node tools/derive-arena-unit-catalog.js --check *> "$taskDir/arena-catalog-r21-check.log"
if($LASTEXITCODE -ne 0){throw 'R21 arena catalog check failed'}
& python -X utf8 -B "$taskDir/check-r21-scoped-data-impact.py" *> "$taskDir/r21-scoped-data-impact.log"
if($LASTEXITCODE -ne 0){throw 'R21 changed inputs outside the scoped Elder data'}
& powershell -NoProfile -ExecutionPolicy Bypass -File "$taskDir/build-r21-elder.ps1"
if($LASTEXITCODE -ne 0){throw 'R21 resource compilation failed'}
& python -X utf8 -B tools/cf6-audio/build-test-fixture.py *> "$taskDir/audio-fixture-r21-generation.log"
if($LASTEXITCODE -ne 0){throw 'R21 audio fixture generation failed'}
& python -X utf8 -B tools/cf6-elder-assets/verify.py *> "$taskDir/elder-r21-resource-verification.log"
if($LASTEXITCODE -ne 0){throw 'R21 resource verification failed'}
& powershell -NoProfile -ExecutionPolicy Bypass -File "$taskDir/run-bound-validation.ps1" -PlanPath "$taskDir/native-r21-shield-allocation-plan.json"
exit $LASTEXITCODE
