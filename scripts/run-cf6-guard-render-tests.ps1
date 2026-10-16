param([ValidateSet('before','after')][string]$Variant='after',[switch]$Capture,[int]$TimeoutSeconds=180)
$ErrorActionPreference='Stop'
$suffix=if($Capture){'-capture'}else{''}
$template="scripts/test-runners/cf6-guard-render/TestLoader-$Variant$suffix.as.template"
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') -DomainId cf6-guard-render -TemplateRelativePath $template -SuiteRelativePaths 'scripts/类定义/org/flashNight/arki/unit/Action/Melee/Cf6GuardRenderTest.as' -SuiteFqns 'org.flashNight.arki.unit.Action.Melee.Cf6GuardRenderTest' -ExpectedTracePatterns @('Cf6GuardRenderTest: 21 passed, 0 failed; 10 draw points') -SuccessSummary '保安变身原生绘制耗时与像素采样完成' -TimeoutSeconds $TimeoutSeconds -AsyncBehaviorTimeoutSeconds $TimeoutSeconds
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
