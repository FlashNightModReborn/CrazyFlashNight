param([int]$TimeoutSeconds=180)
$ErrorActionPreference='Stop'
& python -X utf8 -B (Join-Path $PSScriptRoot '../tools/cf6-bladebot-assets/build-knockback-fixture.py') --check
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') -DomainId cf6-knockback-scope -TemplateRelativePath 'scripts/test-runners/cf6-knockback-scope/TestLoader.as.template' -SuiteRelativePaths 'scripts/类定义/org/flashNight/arki/unit/Action/Melee/Cf6KnockbackScopeTest.as' -SuiteFqns 'org.flashNight.arki.unit.Action.Melee.Cf6KnockbackScopeTest' -ExpectedTracePatterns @('Cf6KnockbackScopeTest: 7 passed, 0 failed') -SuccessSummary '敌人击退使用自身摩擦力且独立衰减' -TimeoutSeconds $TimeoutSeconds -AsyncBehaviorTimeoutSeconds $TimeoutSeconds
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
