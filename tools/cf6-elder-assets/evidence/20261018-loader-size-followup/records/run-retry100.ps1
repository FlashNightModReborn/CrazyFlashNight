$ErrorActionPreference='Stop'
chcp.com 65001 | Out-Null
$taskDir='tmp/cf6-combat-calibration-20261017/loader-size-followup'
$taskScope='tmp/cf6-combat-calibration-20261017/display-qualified-20261018-r11'
try {
 if(Test-Path -LiteralPath 'tmp/arena-worker-experiments/cf6-loader-c6-b100-retry1-20261018/execution-started.json'){throw 'Preserve existing retry execution'}
 $taskEvents=@(Get-Content -LiteralPath "$taskScope/display-state.jsonl" -Encoding UTF8 | ForEach-Object {$_ | ConvertFrom-Json})
 $taskOn=@($taskEvents | Where-Object {$_.event -eq 'state_observed'})[-1]
 $taskAge=((Get-Date).ToUniversalTime()-([datetime]$taskEvents[-1].utc).ToUniversalTime()).TotalSeconds
 if($taskOn.state -ne 1 -or $taskAge -lt 0 -or $taskAge -gt 30){throw 'Display off, unknown or stale'}
 if($taskEvents | Where-Object {$_.event -in @('subscription_ended','scope_failed','display_request_released')}){throw 'Display scope ended'}
 & node tools/arena-calibration/run-worker-experiment.js --plan "$taskDir/arena-elder-retry/experiment-plan.json" *> "$taskDir/elder-retry-runner.log"
 if($LASTEXITCODE -ne 0){throw 'Fresh Beast100 integration did not qualify'}
} finally {
 $taskStop=Join-Path $taskScope 'STOP'
 if(-not(Test-Path -LiteralPath $taskStop)){[IO.File]::WriteAllText((Join-Path (Get-Location) $taskStop),'Fresh retry live tests ended; release temporary display hold immediately.')}
}
Write-Host 'Fresh isolated Beast100 pair completed; display release requested.'
