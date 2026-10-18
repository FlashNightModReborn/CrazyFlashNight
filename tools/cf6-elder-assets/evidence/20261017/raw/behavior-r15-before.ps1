chcp.com 65001 > $null
$ErrorActionPreference='Stop'
$stem=Join-Path $PSScriptRoot 'behavior-r15-before'
if(Test-Path -LiteralPath ($stem+'.log')){throw 'Preserve prior baseline fixture attempt'}
& scripts/compile_test.ps1 -StopTestPlayers -TimeoutSeconds 60 -ControlTimeoutSeconds 30 *>&1 | Tee-Object -FilePath ($stem+'-pre-stop.log')
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
$nativeExit=0
try { & scripts/run-cf6-elder-asset-tests.ps1 *>&1 | Tee-Object -FilePath ($stem+'.log');$nativeExit=$LASTEXITCODE }
catch { $_ | Out-String | Tee-Object -FilePath ($stem+'.log') -Append;$nativeExit=1 }
foreach($item in @(@{source='scripts/flashlog.txt';suffix='-trace.txt'},@{source='scripts/compiler_errors.txt';suffix='-errors.txt'},@{source='scripts/TestLoader.swf';suffix='-TestLoader.swf'})){
 if(Test-Path -LiteralPath $item.source){Copy-Item -LiteralPath $item.source -Destination ($stem+$item.suffix)}
}
exit $nativeExit
