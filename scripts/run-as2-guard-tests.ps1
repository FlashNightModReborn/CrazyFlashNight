[CmdletBinding()]
param([ValidateRange(1,3600)][int]$TimeoutSeconds=600,[switch]$SkipCompile)
$ErrorActionPreference='Stop'
$run=@{
    DomainId='as2-guard'
    TemplateRelativePath='scripts/test-runners/as2-guard/TestLoader.as.template'
    SuiteRelativePaths=@('scripts/类定义/org/flashNight/gesh/object/Avm1GuardContractTest.as')
    SuiteFqns=@('org.flashNight.gesh.object.Avm1GuardContractTest')
    AdditionalAsRelativePaths=@(
        'scripts/类定义/org/flashNight/arki/hud/PlayerHudService.as'
        'scripts/类定义/org/flashNight/arki/hud/PlayerHudBuffProjection.as'
        'scripts/类定义/org/flashNight/arki/unit/Action/Skill/QuickSkillInputService.as'
        'scripts/类定义/org/flashNight/arki/unit/Action/Skill/DrugInputService.as'
        'scripts/类定义/org/flashNight/arki/unit/Action/Skill/WeaponSkillInputService.as'
        'scripts/类定义/org/flashNight/arki/unit/Action/Shoot/LongGunSubWeaponCore.as'
        'scripts/类定义/org/flashNight/arki/bullet/BulletComponent/Loader/ShellLoader.as'
    )
    ExpectedTracePatterns=@(
        '(?m)^Avm1GuardContractTest Tests Passed: [1-9][0-9]*\r?$'
        '(?m)^Avm1GuardContractTest Tests Failed: 0\r?$'
    )
    SuccessSummary='AS2 guard truth tables, real read consumers, optional views and present/missing A/B'
    TimeoutSeconds=$TimeoutSeconds
    SkipCompile=$SkipCompile
}
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') @run
