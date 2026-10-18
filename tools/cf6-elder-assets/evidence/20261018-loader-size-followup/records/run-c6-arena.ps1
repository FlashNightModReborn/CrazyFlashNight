$ErrorActionPreference='Stop'
chcp.com 65001 | Out-Null
$taskDir='tmp/cf6-combat-calibration-20261017/loader-size-followup'
$taskScope='tmp/cf6-combat-calibration-20261017/display-qualified-20261018-r10'
try {
 foreach($taskKind in @('head','elder')) {
  $taskId="cf6-loader-c6-$taskKind-20261018"
  if(Test-Path -LiteralPath "tmp/arena-worker-experiments/$taskId/execution-started.json"){throw 'Preserve existing arena execution'}
  $taskEvents=@(Get-Content -LiteralPath "$taskScope/display-state.jsonl" -Encoding UTF8 | ForEach-Object {$_ | ConvertFrom-Json})
  $taskObserved=@($taskEvents | Where-Object {$_.event -eq 'state_observed'})[-1]
  $taskAge=((Get-Date).ToUniversalTime()-([datetime]$taskEvents[-1].utc).ToUniversalTime()).TotalSeconds
  if($taskObserved.state -ne 1 -or $taskAge -lt 0 -or $taskAge -gt 30){throw 'Display is off, unknown or stale'}
  if($taskEvents | Where-Object {$_.event -in @('subscription_ended','scope_failed','display_request_released')}){throw 'Display scope already ended'}
  & node tools/arena-calibration/run-worker-experiment.js --plan "$taskDir/arena-$taskKind/experiment-plan.json" *> "$taskDir/$taskKind-runner.log"
  if($LASTEXITCODE -ne 0){throw "C6 $taskKind integration failed"}
 }
} finally {
 $taskStop=Join-Path $taskScope 'STOP'
 if(-not(Test-Path -LiteralPath $taskStop)){
  [IO.File]::WriteAllText((Join-Path (Get-Location) $taskStop),'C6 live integration ended; release the temporary display hold before evidence and Git closeout.')
 }
}
Write-Host 'C6 bounded integration completed; immediate display release requested.'
