chcp.com 65001 > $null
$steps=@(
 @{prefix='behavior-r10';runner='scripts/run-cf6-elder-asset-tests.ps1';args=@{}},
 @{prefix='render-probe-r7';runner='scripts/run-cf6-elder-render-tests.ps1';args=@{Probe=$true}},
 @{prefix='blade-beam-capture-r2';runner='scripts/run-cf6-bladebot-beam-render-tests.ps1';args=@{Capture=$true}},
 @{prefix='wings-post-knockback-r2';runner='scripts/run-cf6-wings-asset-tests.ps1';args=@{TimeoutSeconds=600;AsyncBehaviorTimeoutSeconds=360}}
)
foreach($step in $steps){
 $stem=Join-Path $PSScriptRoot $step.prefix
 if(Test-Path -LiteralPath ($stem+'.log')){throw 'Preserve existing attempt: '+$stem}
 & scripts/compile_test.ps1 -StopTestPlayers -TimeoutSeconds 60 -ControlTimeoutSeconds 30 *>&1 | Tee-Object -FilePath ($stem+'-pre-stop.log')
 if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
 $runner=$step.runner;$arguments=$step.args;$nightCode=0
 try { & $runner @arguments *>&1 | Tee-Object -FilePath ($stem+'.log');$nightCode=$LASTEXITCODE }
 catch { $_ | Out-String | Tee-Object -FilePath ($stem+'.log') -Append;$nightCode=1 }
 foreach($item in @(@{source='scripts/flashlog.txt';suffix='-trace.txt'},@{source='scripts/compiler_errors.txt';suffix='-errors.txt'},@{source='scripts/TestLoader.swf';suffix='-TestLoader.swf'})){
  if(Test-Path -LiteralPath $item.source){Copy-Item -LiteralPath $item.source -Destination ($stem+$item.suffix)}
 }
 if($nightCode -ne 0){exit $nightCode}
}
