param()
$ErrorActionPreference='Stop'
chcp.com 65001 | Out-Null
$repoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
Set-Location -LiteralPath $repoRoot
$attempt=Join-Path $PSScriptRoot 'build-pass3'
New-Item -ItemType Directory -Path $attempt -ErrorAction Stop | Out-Null
$keys=@('wings','soldier','guard')
foreach($key in $keys){
    $folder=Join-Path $attempt $key
    New-Item -ItemType Directory -Path $folder | Out-Null
    $manifestPath=Join-Path $repoRoot ('tools/cf6-'+$key+'-assets/native-manifest.json')
    $manifest=Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $owner=Join-Path $repoRoot $manifest.owner
    $name=Split-Path $owner -Leaf
    $target=Join-Path $owner ($name+'.xfl')
    $swf=$owner+'.swf'
    $before=Get-FileHash -LiteralPath $swf -Algorithm SHA256
    Write-Host ('Publishing '+$key)
    $ErrorActionPreference='Continue'
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/compile_test.ps1 -Target $target -PublishOnly -VerifySwf $swf -TimeoutSeconds 240 2>&1 | Tee-Object -FilePath (Join-Path $folder 'compile.log')
    $code=$LASTEXITCODE
    $ErrorActionPreference='Stop'
    foreach($file in @('compiler_errors.txt','compile_output.txt','publish_done.marker')){
        if(Test-Path -LiteralPath (Join-Path $repoRoot ('scripts/'+$file))){Copy-Item -LiteralPath (Join-Path $repoRoot ('scripts/'+$file)) -Destination (Join-Path $folder $file)}
    }
    Copy-Item -LiteralPath $swf -Destination (Join-Path $folder 'candidate.swf')
    Copy-Item -LiteralPath $manifestPath -Destination (Join-Path $folder 'native-manifest.json')
    $after=Get-Item -LiteralPath $swf
    [ordered]@{unit=$key;exitCode=$code;target=$target;swf=$swf;beforeSha256=$before.Hash;sha256=(Get-FileHash -LiteralPath $swf -Algorithm SHA256).Hash;bytes=$after.Length;modifiedUtc=$after.LastWriteTimeUtc.ToString('o');manifestSha256=(Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash} | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $folder 'identity.json') -Encoding UTF8
    if($code -ne 0){exit $code}
}
