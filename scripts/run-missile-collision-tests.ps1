[CmdletBinding()]
param([ValidateRange(1, 3600)][int]$TimeoutSeconds=600, [switch]$SkipCompile)
$ErrorActionPreference='Stop'
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') `
    -DomainId 'missile-collision' `
    -TemplateRelativePath 'scripts/test-runners/missile-collision/TestLoader.as.template' `
    -SuiteRelativePaths @('scripts/类定义/org/flashNight/arki/bullet/BulletComponent/Collider/MissileCollisionTest.as', 'scripts/类定义/org/flashNight/arki/unit/UnitComponent/Dressup/DressupReferenceManagerTest.as') `
    -SuiteFqns @('org.flashNight.arki.bullet.BulletComponent.Collider.MissileCollisionTest', 'org.flashNight.arki.unit.UnitComponent.Dressup.DressupReferenceManagerTest') `
    -AdditionalAsRelativePaths @('scripts/类定义/org/flashNight/arki/bullet/BulletComponent/Collider/AABBCollider.as', 'scripts/类定义/org/flashNight/arki/unit/UnitComponent/Dressup/DressupReferenceManager.as', 'scripts/类定义/org/flashNight/arki/bullet/BulletComponent/Movement/MissileStates/SearchTargetState.as', 'scripts/类定义/org/flashNight/arki/bullet/BulletComponent/Movement/MissileStates/FreeFlyState.as') `
    -ExpectedTracePatterns @('(?m)^MissileCollisionTest Tests Passed: 32\r?$', '(?m)^MissileCollisionTest Tests Failed: 0\r?$', '(?m)^Result: (?<dressup>[1-9][0-9]*)/\k<dressup> passed, 0 failed  \([0-9]+ ms\)\r?$') `
    -SuccessSummary 'MovieClip missile collision and live unequip regression' -TimeoutSeconds $TimeoutSeconds -SkipCompile:$SkipCompile
