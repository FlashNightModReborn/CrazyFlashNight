[CmdletBinding()]
param([ValidateRange(1, 3600)][int]$TimeoutSeconds = 360, [switch]$SkipCompile)
$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') `
    -DomainId 'cf6-tutorial-turret' `
    -TemplateRelativePath 'scripts/test-runners/cf6-tutorial-turret/TestLoader.as.template' `
    -SuiteRelativePaths @('scripts/类定义/org/flashNight/arki/scene/Cf6TutorialTurretServiceTest.as') `
    -SuiteFqns @('org.flashNight.arki.scene.Cf6TutorialTurretServiceTest') `
    -AdditionalAsRelativePaths @('scripts/类定义/org/flashNight/arki/scene/Cf6TutorialTurretService.as') `
    -ExpectedTracePatterns @('(?m)^Cf6TutorialTurretServiceTest Tests Passed: 120\r?$', '(?m)^Cf6TutorialTurretServiceTest Tests Failed: 0\r?$') `
    -SuccessSummary '120/120 assertions (static count field-r2, confirm on fresh run); visual muzzle + marked cross-row LinearBulletMovement + ownership/pause/late-callback gates, no full chapter claim' `
    -TimeoutSeconds $TimeoutSeconds -SkipCompile:$SkipCompile
