param([int]$TimeoutSeconds = 180, [int]$AsyncBehaviorTimeoutSeconds = 60)
$ErrorActionPreference = 'Stop'
$cf6Patterns = @('Cf6ZombieAssetTest: \d+ passed, 0 failed; 28 actual timeline cases')
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') -DomainId cf6-zombie -TemplateRelativePath 'scripts/test-runners/cf6-zombie/TestLoader.as.template' -SuiteRelativePaths 'scripts/类定义/org/flashNight/arki/unit/Action/Melee/Cf6ZombieAssetTest.as' -SuiteFqns 'org.flashNight.arki.unit.Action.Melee.Cf6ZombieAssetTest' -ExpectedTracePatterns $cf6Patterns -SuccessSummary 'CF6 男女僵尸原生时间轴、攻击判定与血腥死分支专项通过' -TimeoutSeconds $TimeoutSeconds -AsyncBehaviorTimeoutSeconds $AsyncBehaviorTimeoutSeconds
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
