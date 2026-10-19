$ErrorActionPreference='Stop'
chcp.com 65001 | Out-Null
$repo=(Get-Location).Path
$taskDir=Join-Path $repo 'tmp/cf6-combat-calibration-20261017'
$consumer=Join-Path $repo 'scripts/asLoader.swf'
$attempt=Join-Path $taskDir 'build-integrated-melee-loader'
New-Item -ItemType Directory -Path $attempt -ErrorAction Stop | Out-Null
$before=(Get-FileHash -LiteralPath $consumer -Algorithm SHA256).Hash
$started=(Get-Date).ToUniversalTime()
$ErrorActionPreference='Continue'
& powershell -NoProfile -ExecutionPolicy Bypass -File scripts/compile_test.ps1 -Target publish -VerifySwf $consumer -TimeoutSeconds 600 2>&1 | Tee-Object -FilePath (Join-Path $attempt 'compile.log')
$code=$LASTEXITCODE
$ErrorActionPreference='Stop'
foreach($name in @('compiler_errors.txt','compile_output.txt','publish_done.marker','compile_state_uncertain.marker')){
 $source=Join-Path $repo ('scripts/'+$name)
 if(Test-Path -LiteralPath $source){Copy-Item -LiteralPath $source -Destination (Join-Path $attempt $name)}
}
[ordered]@{exitCode=$code;startedUtc=$started.ToString('o');target='publish';consumer=$consumer;beforeSha256=$before;head=(git rev-parse HEAD).Trim()} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $attempt 'attempt.json') -Encoding UTF8
if($code -ne 0){exit $code}
Copy-Item -LiteralPath $consumer -Destination (Join-Path $attempt 'asLoader.swf')
[ordered]@{consumer=$consumer;sha256=(Get-FileHash -LiteralPath $consumer -Algorithm SHA256).Hash;bytes=(Get-Item -LiteralPath $consumer).Length;modifiedUtc=(Get-Item -LiteralPath $consumer).LastWriteTimeUtc.ToString('o');head=(git rev-parse HEAD).Trim()} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $attempt 'identity.json') -Encoding UTF8
node tools/audit-as2-class-embedding.js --swf scripts/asLoader.swf *> (Join-Path $attempt 'class-ownership.log')
if($LASTEXITCODE -ne 0){throw 'Published class ownership failed'}
Write-Host 'Merged melee-input loader published; no TestLoader behavior suite started.'
