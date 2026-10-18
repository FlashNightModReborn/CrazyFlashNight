$ErrorActionPreference='Stop'
chcp.com 65001 | Out-Null
$taskDir='tmp/cf6-combat-audio-20261017'
foreach($family in @('headbot','bladebot','elder')){
 $planner=if($family -eq 'bladebot'){'arena-wave-plan.js'}else{'arena-plan.js'}
 & node "tools/cf6-$family-assets/$planner" "$taskDir/arena-$family-config.json" *> "$taskDir/arena-$family-plan.log"
 if($LASTEXITCODE -ne 0){throw "Plan failed: $family"}
 & node tools/arena-calibration/run-worker-experiment.js --plan "$taskDir/arena-$family/experiment-plan.json" *> "$taskDir/arena-$family-run.log"
 $code=$LASTEXITCODE
 if($code -ne 0){throw "Experiment failed: $family"}
 $reportPath="tmp/arena-worker-experiments/cf6-$family-combat-audio-20261017/experiment-report.json"
 $report=Get-Content -LiteralPath $reportPath -Raw -Encoding UTF8 | ConvertFrom-Json
 if(-not $report.qualified -or $report.status -ne 'completed' -or $report.errors.Count -ne 0){throw "Incomplete experiment: $family"}
 Write-Output "Completed $family with verified cleanup and save protection."
}
