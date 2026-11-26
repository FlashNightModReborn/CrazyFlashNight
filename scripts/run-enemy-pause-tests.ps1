[CmdletBinding()]
param(
    [ValidateRange(1, 3600)]
    [int]$TimeoutSeconds = 240,
    [switch]$SkipCompile
)

$ErrorActionPreference = 'Stop'
$commonRunner = Join-Path $PSScriptRoot 'test-runners\run-focused-testloader.ps1'
$focusedRun = @{
    DomainId = 'enemy-pause'
    TemplateRelativePath = 'scripts\test-runners\enemy-pause\TestLoader.as.template'
    SuiteRelativePaths = @(
        'scripts\类定义\org\flashNight\arki\unit\UnitAI\EnemyPauseMovementTest.as'
    )
    SuiteFqns = @(
        'org.flashNight.arki.unit.UnitAI.EnemyPauseMovementTest'
    )
    AdditionalAsRelativePaths = @(
        'scripts\逻辑\单位函数\单位函数_lsy_敌人模板迁移.as',
        'scripts\类定义\org\flashNight\arki\unit\UnitAI\core\AIEnvironment.as'
    )
    ExpectedTracePatterns = @(
        '(?m)^=== EnemyPauseMovementTest result: passed=11 failed=0 ===\r?$'
    )
    SuccessSummary = 'EnemyPauseMovementTest 11/11 assertions'
    TimeoutSeconds = $TimeoutSeconds
    SkipCompile = $SkipCompile
}
& $commonRunner @focusedRun
