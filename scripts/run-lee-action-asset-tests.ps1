param([int]$TimeoutSeconds = 240, [int]$AsyncBehaviorTimeoutSeconds = 40, [switch]$SkipCompile)
$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') `
    -DomainId lee-action-asset `
    -TemplateRelativePath 'scripts/test-runners/lee-action-asset/TestLoader.as.template' `
    -SuiteRelativePaths 'scripts/类定义/org/flashNight/arki/unit/Action/Input/EnemyActionAssetTest.as' `
    -SuiteFqns 'org.flashNight.arki.unit.Action.Input.EnemyActionAssetTest' `
    -ExpectedTracePatterns @('EnemyActionAssetTest: [1-9][0-9]* passed, 0 failed; 33 actual timeline cases; elapsed-ms=') `
    -SuccessSummary 'Lee 实际时间轴专项通过（隔离初始化与出伤接收器，无真实存档）' `
    -TimeoutSeconds $TimeoutSeconds -AsyncBehaviorTimeoutSeconds $AsyncBehaviorTimeoutSeconds `
    -AutoStopReadOnlyPlayer -SkipCompile:$SkipCompile
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
