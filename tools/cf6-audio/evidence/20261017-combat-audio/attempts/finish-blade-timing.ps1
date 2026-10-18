$ErrorActionPreference='Stop'
chcp.com 65001 | Out-Null
$taskDir='tmp/cf6-combat-audio-20261017'
$deadline=(Get-Date).AddMinutes(10)
do{
 $rows=Get-Content -LiteralPath "$taskDir/regeneration-pass4/results.json" -Raw -Encoding UTF8 | ConvertFrom-Json
 if(@($rows | Where-Object exitCode -ne 0).Count){throw 'Regeneration failed; no compile attempted'}
 if($rows.Count -eq 8){break}
 if((Get-Date) -gt $deadline){throw 'Regeneration not complete; no compile attempted'}
 Start-Sleep -Seconds 5
}while($true)
& "$taskDir/build-pass5.ps1" *> "$taskDir/build-pass5-wrapper.log"
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
& python -X utf8 -B tools/cf6-audio/build-test-fixture.py
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
& python -X utf8 -B tools/cf6-headbot-assets/build-death-render-fixture.py
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
& "$taskDir/run-bound-validation.ps1" -PlanPath "$taskDir/blade-final-plan1.json" *> "$taskDir/blade-final-pass1-wrapper.log"
exit $LASTEXITCODE
