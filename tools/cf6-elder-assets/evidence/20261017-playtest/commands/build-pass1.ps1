param()
$ErrorActionPreference='Stop'
$repo=(Get-Location).Path
$proof=Join-Path $repo 'tmp/cf6-playtest-feedback-20261017/build-pass1'
if(Test-Path -LiteralPath $proof){throw 'Refuse to overwrite prior build evidence'}
New-Item -ItemType Directory -Path $proof | Out-Null
$targets=@(
 @{Name='headbot';Target='flashswf/arts/new/Codex大头机器人素材/Codex大头机器人素材.xfl';Swf='flashswf/arts/new/Codex大头机器人素材.swf'},
 @{Name='elder';Target='flashswf/arts/new/Codex老头素材/Codex老头素材.xfl';Swf='flashswf/arts/new/Codex老头素材.swf'},
 @{Name='bladebot';Target='flashswf/arts/new/Codex大刀机器人素材/Codex大刀机器人素材.xfl';Swf='flashswf/arts/new/Codex大刀机器人素材.swf'},
 @{Name='asLoader';Target='publish';Swf='scripts/asLoader.swf'}
)
foreach($item in $targets){
 $folder=Join-Path $proof $item.Name
 New-Item -ItemType Directory -Path $folder | Out-Null
 & powershell -NoProfile -ExecutionPolicy Bypass -File scripts/compile_test.ps1 -Target $item.Target -PublishOnly -VerifySwf $item.Swf -TimeoutSeconds 600 2>&1 | Tee-Object -FilePath (Join-Path $folder 'compile.log')
 $result=$LASTEXITCODE
 foreach($name in @('compiler_errors.txt','compile_output.txt','publish_done.marker')){
  $source=Join-Path $repo ('scripts/'+$name)
  if(Test-Path -LiteralPath $source){Copy-Item -LiteralPath $source -Destination (Join-Path $folder $name)}
 }
 if(Test-Path -LiteralPath $item.Swf){
  Copy-Item -LiteralPath $item.Swf -Destination (Join-Path $folder 'candidate.swf')
  $identity=@{name=$item.Name;target=$item.Target;swf=$item.Swf;exitCode=$result;sha256=(Get-FileHash -LiteralPath $item.Swf -Algorithm SHA256).Hash;bytes=(Get-Item -LiteralPath $item.Swf).Length;time=(Get-Date).ToString('o')}
  $identity | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $folder 'identity.json') -Encoding UTF8
 }
 if($result -ne 0){exit $result}
}
