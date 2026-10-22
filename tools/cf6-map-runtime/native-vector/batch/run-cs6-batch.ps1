# CF6 K3 native-vector serial CS6 queue. ROOT executes this by hand; the K3 line never runs it.
# Fail-closed: consumes the locked batch/plan.json cross-checked against the Astra-owned
# converter-ready.json (schema/status/files path+sha256+bytes), re-verifies the pinned
# dependencies, the signal, map-input and each source SVG before every target, stops at
# the first failure and keeps all evidence under batch/logs/cs6-<timestamp>/.
# Targets with a plan builder field (the reviewed floor_lattice vector-pattern wrapper)
# assemble through that builder script with --assemble instead of plain build-layer.py.
[CmdletBinding()]
param([string[]]$Only=@())
$ErrorActionPreference='Stop'
chcp.com 65001 | Out-Null
$repoCf6=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../..')).TrimEnd('\')
Set-Location -LiteralPath $repoCf6
$batchDirCf6=Join-Path $repoCf6 'tools/cf6-map-runtime/native-vector/batch'
$planCf6=Get-Content -LiteralPath (Join-Path $batchDirCf6 'plan.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$readyPathCf6=Join-Path $batchDirCf6 'converter-ready.json'
if(!(Test-Path -LiteralPath $readyPathCf6)){throw 'converter-ready.json absent; Astra-owned signal required'}
$readyShaCf6=(Get-FileHash -LiteralPath $readyPathCf6 -Algorithm SHA256).Hash.ToLowerInvariant()
$readyCf6=Get-Content -LiteralPath $readyPathCf6 -Raw -Encoding UTF8 | ConvertFrom-Json
if($readyCf6.schema -ne 'cf6-native-converter-ready.v1'){throw ('ready schema rejected: '+$readyCf6.schema)}
if($readyCf6.status -ne 'ready_for_K3_source_preparation'){throw ('ready status rejected: '+$readyCf6.status)}
if(!$readyCf6.files -or $readyCf6.files.Count -eq 0){throw 'ready files array empty'}
function Test-ReadyDepsCf6 {
 foreach($fCf6 in $readyCf6.files){
  if([string]::IsNullOrEmpty($fCf6.path) -or [string]::IsNullOrEmpty($fCf6.sha256) -or $fCf6.bytes -le 0){return ('malformed files entry: '+$fCf6.path)}
  $pCf6=Join-Path $repoCf6 $fCf6.path
  if(!(Test-Path -LiteralPath $pCf6)){return ('dependency missing: '+$fCf6.path)}
  if((Get-Item -LiteralPath $pCf6).Length -ne $fCf6.bytes){return ('dependency bytes mismatch: '+$fCf6.path)}
  if((Get-FileHash -LiteralPath $pCf6 -Algorithm SHA256).Hash.ToLowerInvariant() -ne $fCf6.sha256.ToLowerInvariant()){return ('dependency sha mismatch: '+$fCf6.path)}
 }
 if((Get-FileHash -LiteralPath $readyPathCf6 -Algorithm SHA256).Hash.ToLowerInvariant() -ne $readyShaCf6){return 'converter-ready.json changed during the queue'}
 return $null
}
$badCf6=Test-ReadyDepsCf6; if($badCf6){throw ('ready contract violated: '+$badCf6)}
$mapInputPathCf6=Join-Path $repoCf6 $planCf6.mapInput.path
if((Get-FileHash -LiteralPath $mapInputPathCf6 -Algorithm SHA256).Hash.ToLowerInvariant() -ne $planCf6.mapInput.sha256){throw 'map-input changed since the plan lock; rerun batch-plan.py --check'}
if($readyCf6.inputIndexSha256 -ne $planCf6.mapInput.sha256){throw 'ready inputIndex differs from the locked plan'}
$stampCf6=Get-Date -Format 'yyyyMMdd-HHmmss'
$evidenceCf6=Join-Path $batchDirCf6 ('logs/cs6-'+$stampCf6)
New-Item -ItemType Directory -Force -Path $evidenceCf6 | Out-Null
$pythonCf6=Join-Path $repoCf6 'tmp/cf6-py312/Scripts/python.exe'
foreach($targetCf6 in $planCf6.targets){
 $nameCf6=$targetCf6.name
 if($Only.Count -and $Only -notcontains $nameCf6){continue}
 if($targetCf6.status -in @('blocked','failed')){Write-Host ('SKIP '+$nameCf6+' ('+$targetCf6.status+')');continue}
 $badCf6=Test-ReadyDepsCf6; if($badCf6){throw ('ready contract violated before '+$nameCf6+': '+$badCf6)}
 $sourcePathCf6=Join-Path $repoCf6 $targetCf6.source
 if(!(Test-Path -LiteralPath $sourcePathCf6) -or (Get-FileHash -LiteralPath $sourcePathCf6 -Algorithm SHA256).Hash.ToLowerInvariant() -ne $targetCf6.sourceSha256){throw ('locked source changed for '+$nameCf6+'; stop to avoid mixed identity')}
 $outCf6=Join-Path $evidenceCf6 $nameCf6
 New-Item -ItemType Directory -Force -Path $outCf6 | Out-Null
 if($targetCf6.textureCount -gt 0){
  if($nameCf6 -notmatch '^CF6_A(0[1-689]|1[0-9]|20|22)_[A-Za-z0-9_-]+$'){throw ('Name rejected by the import-native.ps1 mirror check: '+$nameCf6)}
  if(!(Test-Path -LiteralPath (Join-Path $repoCf6 $targetCf6.xfl))){
   & (Join-Path $repoCf6 'tmp/cf6-roguelike-20261021/orchestration/import-native.ps1') -Recipe $nameCf6 -RecipeRelativePath $targetCf6.importRecipe *> (Join-Path $outCf6 'import.log')
   if($LASTEXITCODE -ne 0){Get-Content -LiteralPath (Join-Path $outCf6 'import.log') -Tail 12;throw ('Native import failed '+$nameCf6)}
  }
 }
 $assembleScriptCf6='tools/cf6-map-runtime/native-vector/build-layer.py'
 $assembleArgsCf6=@('--map',$targetCf6.map,'--layer',$targetCf6.layer,'--asset-dir',$targetCf6.assetDir,'--assemble')
 if($targetCf6.builder){
  $assembleScriptCf6=$targetCf6.builder.script
  $assembleArgsCf6=@($targetCf6.builder.args)+@('--assemble')
 }
 & $pythonCf6 -X utf8 -B $assembleScriptCf6 @assembleArgsCf6 *> (Join-Path $outCf6 'assemble.log')
 if($LASTEXITCODE -ne 0){Get-Content -LiteralPath (Join-Path $outCf6 'assemble.log') -Tail 12;throw ('Assemble failed '+$nameCf6)}
 $swfRelCf6='flashswf/backgrounds/cf6/'+$targetCf6.swf
 & scripts/compile_test.ps1 -Target $targetCf6.xfl -PublishOnly -VerifySwf $swfRelCf6 -TimeoutSeconds 300 *> (Join-Path $outCf6 'publish.log')
 $codeCf6=$LASTEXITCODE
 foreach($fCf6 in @('compiler_errors.txt','compile_output.txt')){if(Test-Path -LiteralPath (Join-Path 'scripts' $fCf6)){Copy-Item -LiteralPath (Join-Path 'scripts' $fCf6) -Destination (Join-Path $outCf6 $fCf6)}}
 if($codeCf6 -ne 0){Get-Content -LiteralPath (Join-Path $outCf6 'publish.log') -Tail 12;throw ('Publish failed '+$nameCf6)}
 $receiptCf6=@{status='compiled';target=$targetCf6.xfl;swf=$swfRelCf6;sha256=(Get-FileHash -LiteralPath $swfRelCf6).Hash.ToLowerInvariant();checkedAt=(Get-Date).ToString('o');note='Candidate compile only; not a runtime release.'}
 [IO.File]::WriteAllText((Join-Path $outCf6 'receipt.json'),($receiptCf6|ConvertTo-Json),[Text.UTF8Encoding]::new($false))
 Write-Host ('OK '+$nameCf6+' Compiler 0/0; evidence '+$outCf6)
}
Write-Host ('Queue done; evidence under '+$evidenceCf6)
