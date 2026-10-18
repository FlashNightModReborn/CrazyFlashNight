$ErrorActionPreference='Stop'
chcp.com 65001 | Out-Null
$folder=Join-Path $PSScriptRoot 'build-pass6/legacy-agent'
New-Item -ItemType Directory -Path $folder -ErrorAction Stop | Out-Null
$target='flashswf/arts/new/素材库-诺亚新敌人/素材库-诺亚新敌人.xfl'
$swf='flashswf/arts/new/素材库-诺亚新敌人.swf'
$before=Get-FileHash -LiteralPath $swf -Algorithm SHA256
$ErrorActionPreference='Continue'
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/compile_test.ps1 -Target $target -PublishOnly -VerifySwf $swf -TimeoutSeconds 240 2>&1 | Tee-Object -FilePath (Join-Path $folder 'compile.log')
$code=$LASTEXITCODE
$ErrorActionPreference='Stop'
foreach($file in @('compiler_errors.txt','compile_output.txt','publish_done.marker')){
 if(Test-Path -LiteralPath ('scripts/'+$file)){Copy-Item -LiteralPath ('scripts/'+$file) -Destination (Join-Path $folder $file)}
}
Copy-Item -LiteralPath $swf -Destination (Join-Path $folder 'candidate.swf')
$item=Get-Item -LiteralPath $swf
[ordered]@{unit='legacy-agent';exitCode=$code;target=$target;swf=$swf;beforeSha256=$before.Hash;sha256=(Get-FileHash -LiteralPath $swf -Algorithm SHA256).Hash;bytes=$item.Length;modifiedUtc=$item.LastWriteTimeUtc.ToString('o')} | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $folder 'identity.json') -Encoding UTF8
exit $code
