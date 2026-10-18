$ErrorActionPreference='Stop'
$root=(Get-Location).Path
$proof=Join-Path $root 'tmp/cf6-playtest-feedback-20261017/native-tests-pass5'
if(Test-Path -LiteralPath $proof){throw 'Refuse to overwrite evidence'}
New-Item -ItemType Directory -Path $proof | Out-Null
$anyFailure=$false
foreach($domain in @('elder-asset','headbot-asset','bladebot-asset','player-aim')){
 $dir=Join-Path $proof $domain
 New-Item -ItemType Directory -Path $dir | Out-Null
 $ErrorActionPreference='Continue'
 & powershell -NoProfile -ExecutionPolicy Bypass -File ('scripts/run-cf6-'+$domain+'-tests.ps1') -TimeoutSeconds 600 2>&1 | Tee-Object -FilePath (Join-Path $dir 'run.log')
 $result=$LASTEXITCODE
 $ErrorActionPreference='Stop'
 foreach($name in @('flashlog.txt','compiler_errors.txt','compile_output.txt','TestLoader.swf')){
  $source=Join-Path $root ('scripts/'+$name)
  if(Test-Path -LiteralPath $source){Copy-Item -LiteralPath $source -Destination (Join-Path $dir $name)}
 }
 @{domain=$domain;exitCode=$result;time=(Get-Date).ToString('o')} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $dir 'result.json') -Encoding UTF8
 if($result -ne 0){$anyFailure=$true}
 if(Test-Path -LiteralPath 'scripts/compile_state_uncertain.marker'){exit 1}
 if(Test-Path -LiteralPath 'scripts/testloader_scratch_inflight.marker'){exit 1}
}

if($anyFailure){exit 1}
