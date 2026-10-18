param([switch]$Capture,[switch]$Probe,[switch]$Charge,[int]$TimeoutSeconds=600)
$ErrorActionPreference='Stop'
if($Capture -and -not $PSBoundParameters.ContainsKey('TimeoutSeconds')){$TimeoutSeconds=1800}
$domain='cf6-elder-render'
$pattern=if($Probe){'Cf6ElderRenderTest: \d+ passed, 0 failed; 6 draw points'}elseif($Charge){'Cf6ElderRenderTest: \d+ passed, 0 failed; 12 draw points'}elseif($Capture){'Cf6ElderRenderTest: \d+ passed, 0 failed; 25 draw points'}else{'Cf6ElderRenderTest: \d+ passed, 0 failed; 805 draw points'}
$suffix=if($Probe){'-probe'}elseif($Charge){'-charge'}elseif($Capture){'-capture'}else{''}
$template="scripts/test-runners/cf6-elder-render/TestLoader$suffix.as.template"
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') -DomainId $domain -TemplateRelativePath $template -SuiteRelativePaths 'scripts/类定义/org/flashNight/arki/unit/Action/Melee/Cf6ElderRenderTest.as' -SuiteFqns 'org.flashNight.arki.unit.Action.Melee.Cf6ElderRenderTest' -ExpectedTracePatterns @($pattern) -SuccessSummary '老头双形态声明的原生帧集合绘制完成' -TimeoutSeconds $TimeoutSeconds -AsyncBehaviorTimeoutSeconds $TimeoutSeconds
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
