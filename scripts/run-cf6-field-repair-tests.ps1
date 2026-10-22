[CmdletBinding()]
param([ValidateRange(1,3600)][int]$TimeoutSeconds=600,[switch]$SkipCompile)
$ErrorActionPreference='Stop'
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') `
    -DomainId 'cf6-field-repair' `
    -TemplateRelativePath 'scripts/test-runners/cf6-field-repair/TestLoader.as.template' `
    -SuiteRelativePaths @('scripts/类定义/org/flashNight/arki/scene/WaveSpawnWheelTest.as','scripts/类定义/org/flashNight/arki/scene/Cf6TutorialTurretServiceTest.as','scripts/类定义/org/flashNight/arki/unit/Action/Shoot/WeaponAmmoRuntimeTest.as','scripts/类定义/org/flashNight/gesh/tooltip/test/WeaponAmmoTooltipTest.as','scripts/类定义/org/flashNight/gesh/tooltip/test/TooltipFormatterTest.as','scripts/类定义/org/flashNight/arki/unit/Action/Shoot/WeaponAmmoDataTest.as') `
    -SuiteFqns @('org.flashNight.arki.scene.WaveSpawnWheelTest','org.flashNight.arki.scene.Cf6TutorialTurretServiceTest','org.flashNight.arki.unit.Action.Shoot.WeaponAmmoRuntimeTest','org.flashNight.gesh.tooltip.test.WeaponAmmoTooltipTest','org.flashNight.gesh.tooltip.test.TooltipFormatterTest','org.flashNight.arki.unit.Action.Shoot.WeaponAmmoDataTest') `
    -AdditionalAsRelativePaths @('scripts/类定义/org/flashNight/arki/scene/WaveSpawnWheel.as','scripts/类定义/org/flashNight/arki/scene/Cf6TutorialTurretService.as','scripts/类定义/org/flashNight/arki/unit/Action/Shoot/WeaponAmmoRuntime.as','scripts/类定义/org/flashNight/arki/bullet/BulletComponent/Movement/LinearBulletMovement.as') `
    -ExpectedTracePatterns @('(?m)^WaveSpawnWheelTest Tests Passed: 18\r?$','(?m)^WaveSpawnWheelTest Tests Failed: 0\r?$','(?m)^Cf6TutorialTurretServiceTest Tests Passed: 120\r?$','(?m)^Cf6TutorialTurretServiceTest Tests Failed: 0\r?$','(?m)^--- WeaponAmmoRuntimeTest: 305/305 passed, 0 failed ---\r?$','(?m)^--- WeaponAmmoTooltipTest: 26/26 passed, 0 failed ---\r?$','(?m)^--- TooltipFormatterTest: 71/71 passed, 0 failed ---\r?$','(?m)^--- WeaponAmmoDataTest: 139/139 passed, 0 failed ---\r?$') `
    -SuccessSummary '679/679 assertions: deferred wave spawning, CF6 turret ownership and cross-row movement, upstream issue163 ammo with real XML; not full-game acceptance' `
    -TimeoutSeconds $TimeoutSeconds -SkipCompile:$SkipCompile
