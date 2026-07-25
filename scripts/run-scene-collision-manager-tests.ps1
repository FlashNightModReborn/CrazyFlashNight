[CmdletBinding()]
param(
    [ValidateRange(1, 3600)]
    [int]$TimeoutSeconds = 240,
    [switch]$SkipCompile
)

$ErrorActionPreference = 'Stop'
$commonRunner = Join-Path $PSScriptRoot 'test-runners\run-focused-testloader.ps1'
$focusedRun = @{
    DomainId = 'scene-collision-manager'
    TemplateRelativePath = 'scripts\test-runners\scene-collision-manager\TestLoader.as.template'
    SuiteRelativePaths = @(
        'scripts\类定义\org\flashNight\arki\scene\SceneCollisionManagerTest.as'
    )
    SuiteFqns = @(
        'org.flashNight.arki.scene.SceneCollisionManagerTest'
    )
    ExpectedTracePatterns = @(
        '(?m)^SceneCollisionManagerTest Tests Passed: 21\r?$'
        '(?m)^SceneCollisionManagerTest Tests Failed: 0\r?$'
        '(?m)^SceneCollisionManagerTest Cases Passed: 4/4\r?$'
    )
    SuccessSummary = '21/21 assertions, 4/4 cases'
    TimeoutSeconds = $TimeoutSeconds
    SkipCompile = $SkipCompile
}
& $commonRunner @focusedRun
