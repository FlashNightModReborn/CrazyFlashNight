chcp.com 65001 > $null
$ErrorActionPreference='Stop'
$stem=Join-Path $PSScriptRoot 'publish-r15'
if(Test-Path -LiteralPath ($stem+'.log')){throw 'Preserve prior R15 publish attempt'}
& scripts/compile_test.ps1 -StopTestPlayers -TimeoutSeconds 60 -ControlTimeoutSeconds 30 *>&1 | Tee-Object -FilePath ($stem+'-pre-stop.log')
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
& scripts/compile_test.ps1 -Target 'flashswf/arts/new/Codex老头素材/Codex老头素材.xfl' -PublishOnly -VerifySwf 'flashswf/arts/new/Codex老头素材.swf' -TimeoutSeconds 300 *>&1 | Tee-Object -FilePath ($stem+'.log')
$nativeExit=$LASTEXITCODE
foreach($item in @(@{source='scripts/compiler_errors.txt';suffix='-errors.txt'},@{source='scripts/compile_output.txt';suffix='-output.txt'},@{source='flashswf/arts/new/Codex老头素材.swf';suffix='.swf'})){
 if(Test-Path -LiteralPath $item.source){Copy-Item -LiteralPath $item.source -Destination ($stem+$item.suffix)}
}
if($nativeExit -ne 0){exit $nativeExit}
$steps=@(
 @{prefix='behavior-r15';runner='scripts/run-cf6-elder-asset-tests.ps1';args=@{}},
 @{prefix='render-probe-r15';runner='scripts/run-cf6-elder-render-tests.ps1';args=@{Probe=$true}}
)
foreach($step in $steps){
 $stem=Join-Path $PSScriptRoot $step.prefix
 if(Test-Path -LiteralPath ($stem+'.log')){throw 'Preserve prior test attempt: '+$stem}
 & scripts/compile_test.ps1 -StopTestPlayers -TimeoutSeconds 60 -ControlTimeoutSeconds 30 *>&1 | Tee-Object -FilePath ($stem+'-pre-stop.log')
 if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
 $runner=$step.runner;$arguments=$step.args;$nativeExit=0
 try { & $runner @arguments *>&1 | Tee-Object -FilePath ($stem+'.log');$nativeExit=$LASTEXITCODE }
 catch { $_ | Out-String | Tee-Object -FilePath ($stem+'.log') -Append;$nativeExit=1 }
 foreach($item in @(@{source='scripts/flashlog.txt';suffix='-trace.txt'},@{source='scripts/compiler_errors.txt';suffix='-errors.txt'},@{source='scripts/TestLoader.swf';suffix='-TestLoader.swf'})){
  if(Test-Path -LiteralPath $item.source){Copy-Item -LiteralPath $item.source -Destination ($stem+$item.suffix)}
 }
 if($nativeExit -ne 0){exit $nativeExit}
}
& scripts/compile_test.ps1 -StopTestPlayers -TimeoutSeconds 60 -ControlTimeoutSeconds 30 *>&1 | Tee-Object -FilePath (Join-Path $PSScriptRoot 'native-r15-final-stop.log')
exit $LASTEXITCODE
