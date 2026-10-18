param([switch]$Capture,[switch]$Fragment,[switch]$Charge,[int]$TimeoutSeconds=600)
$ErrorActionPreference='Stop'
if($Capture -and -not $PSBoundParameters.ContainsKey('TimeoutSeconds')){$TimeoutSeconds=1800}
$domain=if($Fragment){'cf6-headbot-fragment'}else{'cf6-headbot-render'}
$pattern=if($Fragment){'Cf6HeadbotRenderTest: \d+ passed, 0 failed; 1 draw points'}elseif($Charge){'Cf6HeadbotRenderTest: \d+ passed, 0 failed; 7 draw points'}else{'Cf6HeadbotRenderTest: \d+ passed, 0 failed; 198 draw points'}
$suffix=if($Fragment){'-fragment'}elseif($Charge){'-charge'}elseif($Capture){'-capture'}else{''}
$template="scripts/test-runners/cf6-headbot-render/TestLoader$suffix.as.template"
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') -DomainId $domain -TemplateRelativePath $template -SuiteRelativePaths 'scripts/类定义/org/flashNight/arki/unit/Action/Melee/Cf6HeadbotRenderTest.as' -SuiteFqns 'org.flashNight.arki.unit.Action.Melee.Cf6HeadbotRenderTest' -ExpectedTracePatterns @($pattern) -SuccessSummary '大头机器人声明的原生帧集合绘制完成' -TimeoutSeconds $TimeoutSeconds -AsyncBehaviorTimeoutSeconds $TimeoutSeconds
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
