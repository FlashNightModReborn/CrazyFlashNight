$ErrorActionPreference='Stop'
chcp.com 65001 | Out-Null
$taskDir='tmp/cf6-combat-calibration-20261017'
& python -X utf8 -B tools/cf6-elder-assets/build.py --import-approved *> "$taskDir/regeneration-r19-elder.log"
if($LASTEXITCODE -ne 0){throw 'R19 library generation failed'}
& python -X utf8 -B tools/cf6-elder-assets/build.py --check *> "$taskDir/regeneration-r19-check.log"
if($LASTEXITCODE -ne 0){throw 'R19 library regeneration check failed'}
& python -X utf8 -B tools/cf6-elder-assets/balance.py --write *> "$taskDir/balance-r19-elder-write.log"
if($LASTEXITCODE -ne 0){throw 'R19 formula regeneration failed'}
& python -X utf8 -B tools/cf6-elder-assets/balance.py *> "$taskDir/balance-r19-elder-check.log"
if($LASTEXITCODE -ne 0){throw 'R19 formula check failed'}
& node tools/derive-arena-unit-catalog.js *> "$taskDir/arena-catalog-r19-generation.log"
if($LASTEXITCODE -ne 0){throw 'R19 arena catalog regeneration failed'}
& node tools/derive-arena-unit-catalog.js --check *> "$taskDir/arena-catalog-r19-check.log"
if($LASTEXITCODE -ne 0){throw 'R19 arena catalog check failed'}
& python -X utf8 -B "$taskDir/check-r19-scoped-data-impact.py" *> "$taskDir/r19-scoped-data-impact.log"
if($LASTEXITCODE -ne 0){throw 'R19 changed inputs outside the scoped Elder data'}
& powershell -NoProfile -ExecutionPolicy Bypass -File "$taskDir/build-r19-elder.ps1"
if($LASTEXITCODE -ne 0){throw 'R19 publication failed'}
& python -X utf8 -B tools/cf6-audio/build-test-fixture.py *> "$taskDir/audio-fixture-r19-generation.log"
if($LASTEXITCODE -ne 0){throw 'Audio fixture generation failed'}
& powershell -NoProfile -ExecutionPolicy Bypass -File "$taskDir/run-bound-validation.ps1" -PlanPath "$taskDir/native-r19-output-distribution-plan.json"
exit $LASTEXITCODE
