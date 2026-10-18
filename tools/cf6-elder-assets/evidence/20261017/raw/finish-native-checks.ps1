chcp.com 65001 > $null
$steps=@(
 @{prefix='behavior-r8';runner='scripts/run-cf6-elder-asset-tests.ps1';args=@{}},
 @{prefix='blade-beam-render-r1';runner='scripts/run-cf6-bladebot-beam-render-tests.ps1';args=@{}},
 @{prefix='render-full-r6';runner='scripts/run-cf6-elder-render-tests.ps1';args=@{}},
 @{prefix='blade-capture-r1';runner='scripts/run-cf6-bladebot-asset-tests.ps1';args=@{Capture=$true;TimeoutSeconds=900;AsyncBehaviorTimeoutSeconds=900}},
 @{prefix='render-capture-r6';runner='scripts/run-cf6-elder-render-tests.ps1';args=@{Capture=$true}}
)
foreach($step in $steps){
 $stem=Join-Path $PSScriptRoot $step.prefix
 if(Test-Path -LiteralPath ($stem+'.log')){throw 'Preserve existing native attempt: '+$stem}
 $runner=$step.runner;$arguments=$step.args
 & $runner @arguments *>&1 | Tee-Object -FilePath ($stem+'.log')
 $nightCode=$LASTEXITCODE
 Copy-Item -LiteralPath 'scripts/flashlog.txt' -Destination ($stem+'-trace.txt')
 Copy-Item -LiteralPath 'scripts/compiler_errors.txt' -Destination ($stem+'-errors.txt')
 Copy-Item -LiteralPath 'scripts/TestLoader.swf' -Destination ($stem+'-TestLoader.swf')
 if($nightCode -ne 0){exit $nightCode}
}
