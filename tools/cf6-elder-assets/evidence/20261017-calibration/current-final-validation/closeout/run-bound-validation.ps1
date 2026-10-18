param([Parameter(Mandatory=$true)][string]$PlanPath)
$ErrorActionPreference='Stop'
$repo=(Get-Location).Path
$taskDir=Join-Path $repo 'tmp/cf6-combat-calibration-20261017'
$plan=Get-Content -LiteralPath $PlanPath -Raw -Encoding UTF8 | ConvertFrom-Json
$proof=Join-Path $taskDir $plan.output
if(Test-Path -LiteralPath $proof){throw 'Refuse to overwrite validation evidence'}
New-Item -ItemType Directory -Path $proof | Out-Null
function Get-Bindings {
 $rows=@()
 foreach($relative in $plan.bindings){
  $path=Join-Path $repo $relative
  $rows+=[ordered]@{path=$relative;bytes=(Get-Item -LiteralPath $path).Length;sha256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash}
 }
 return ,$rows
}
$failed=$false
foreach($run in $plan.runs){
 $folder=Join-Path $proof $run.name
 New-Item -ItemType Directory -Path $folder | Out-Null
 $before=Get-Bindings
 $before | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $folder 'bindings-before.json') -Encoding UTF8
 $runnerArgs=@($run.args)
 $ErrorActionPreference='Continue'
 & powershell -NoProfile -ExecutionPolicy Bypass -File $run.runner @runnerArgs 2>&1 | Tee-Object -FilePath (Join-Path $folder 'run.log')
 $code=$LASTEXITCODE
 $ErrorActionPreference='Stop'
 foreach($name in @('flashlog.txt','compiler_errors.txt','compile_output.txt','TestLoader.swf')){
  $source=Join-Path $repo ('scripts/'+$name)
  if(Test-Path -LiteralPath $source){Copy-Item -LiteralPath $source -Destination (Join-Path $folder $name)}
 }
 $after=Get-Bindings
 $after | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $folder 'bindings-after.json') -Encoding UTF8
 $unchanged=($before | ConvertTo-Json -Depth 6 -Compress) -ceq ($after | ConvertTo-Json -Depth 6 -Compress)
 if(-not $unchanged){$code=1}
 [ordered]@{name=$run.name;exitCode=$code;bindingsUnchanged=$unchanged;time=(Get-Date).ToString('o')} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $folder 'result.json') -Encoding UTF8
 if($code -ne 0){$failed=$true}
 if(Test-Path -LiteralPath 'scripts/compile_state_uncertain.marker'){exit 1}
 if(Test-Path -LiteralPath 'scripts/testloader_scratch_inflight.marker'){exit 1}
 if(-not $unchanged){throw 'Source/resource binding changed during validation'}
}
if($failed){exit 1}
