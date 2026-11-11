param([int]$TimeoutSeconds = 300)
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') -DomainId movement-direction -TemplateRelativePath 'scripts/test-runners/movement-direction/TestLoader.as.template' -SuiteRelativePaths 'scripts/类定义/org/flashNight/arki/unit/UnitComponent/Routing/MovementSkillDirectionTest.as' -SuiteFqns 'org.flashNight.arki.unit.UnitComponent.Routing.MovementSkillDirectionTest' -ExpectedTracePatterns @('MovementSkillDirectionTest: 40 passed, 0 failed') -SuccessSummary '位移起手方向、斜移与迟到输入专项通过' -TimeoutSeconds $TimeoutSeconds
exit $LASTEXITCODE
