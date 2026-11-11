param([int]$TimeoutSeconds = 300)
& python -X utf8 (Join-Path $PSScriptRoot '../tools/movement-direction/build-test-host.py') --check
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') -DomainId movement-timeline -CompileTargetRelativePath MovementDirectionHost/MovementDirectionHost.xfl -CompileSwfRelativePath MovementDirectionHost.swf -TemplateRelativePath 'scripts/test-runners/movement-timeline/TestLoader.as.template' -SuiteRelativePaths 'scripts/类定义/org/flashNight/arki/unit/UnitComponent/Routing/MovementDirectionTimelineTest.as' -SuiteFqns 'org.flashNight.arki.unit.UnitComponent.Routing.MovementDirectionTimelineTest' -ExpectedTracePatterns @('MovementDirectionTimelineTest: 34 passed, 0 failed; actual published timelines') -SuccessSummary '真实小跳、闪现、滑步时间轴与起手后反转输入专项通过' -TimeoutSeconds $TimeoutSeconds -AsyncBehaviorTimeoutSeconds 120
exit $LASTEXITCODE
