$ErrorActionPreference='Stop'
chcp.com 65001 | Out-Null
$taskDir='tmp/cf6-combat-calibration-20261017'
$taskAnalysis=Get-Content -LiteralPath 'tools/cf6-elder-assets/evidence/20261017-calibration/history/r22-full-awake/acceptance-summary.json' -Raw -Encoding utf8 | ConvertFrom-Json
if(-not $taskAnalysis.fullMatrix -or -not $taskAnalysis.strengthPassed){throw 'The current full strength matrix is not accepted'}
$taskReport=Get-Content -LiteralPath 'tmp/arena-worker-experiments/cf6-cal-r22-full-20261018/experiment-report.json' -Raw -Encoding utf8 | ConvertFrom-Json
if(-not $taskReport.qualified -or $taskReport.status -ne 'completed'){throw 'Arena execution and cleanup are not qualified'}
$taskIdentity=Get-Content -LiteralPath "$taskDir/arena-r22-full/input-identity.json" -Raw -Encoding utf8 | ConvertFrom-Json
foreach($taskBinding in $taskIdentity.sourceBindings){
 if((Get-FileHash -LiteralPath $taskBinding.path -Algorithm SHA256).Hash.ToLowerInvariant() -ne $taskBinding.sha256){throw "Current input changed: $($taskBinding.path)"}
}
& powershell -NoProfile -ExecutionPolicy Bypass -File "$taskDir/run-bound-validation.ps1" -PlanPath "$taskDir/native-r22-final-plan.json"
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
& powershell -NoProfile -ExecutionPolicy Bypass -File "$taskDir/finish-native-cleanup-after-r22-final.ps1"
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
& python -X utf8 -B "$taskDir/verify-r22-native-images.py" *> "$taskDir/r22-native-image-verification.log"
exit $LASTEXITCODE
