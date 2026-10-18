param([int]$TimeoutSeconds=600,[switch]$Capture)
$ErrorActionPreference='Stop'
$template=if($Capture){'scripts/test-runners/cf6-bladebot-beam-render/TestLoader-capture.as.template'}else{'scripts/test-runners/cf6-bladebot-beam-render/TestLoader.as.template'}
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') -DomainId cf6-bladebot-beam-render -TemplateRelativePath $template -SuiteRelativePaths 'scripts/类定义/org/flashNight/arki/unit/Action/Melee/Cf6BladebotBeamRenderTest.as' -SuiteFqns 'org.flashNight.arki.unit.Action.Melee.Cf6BladebotBeamRenderTest' -ExpectedTracePatterns @('Cf6BladebotBeamRenderTest: \d+ passed, 0 failed; 32 draw points') -SuccessSummary '大刀原 906 光束的 31 帧和镜像关键帧实际绘制通过' -TimeoutSeconds $TimeoutSeconds -AsyncBehaviorTimeoutSeconds $TimeoutSeconds
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
