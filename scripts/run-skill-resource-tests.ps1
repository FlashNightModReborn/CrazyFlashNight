[CmdletBinding()]
param([ValidateRange(1,3600)][int]$TimeoutSeconds=600,[switch]$SkipCompile)
$ErrorActionPreference='Stop'
$run=@{
    DomainId='skill-resource'
    TemplateRelativePath='scripts/test-runners/skill-resource/TestLoader.as.template'
    SuiteRelativePaths=@('scripts/类定义/org/flashNight/arki/skill/SkillResourceServiceTest.as')
    SuiteFqns=@('org.flashNight.arki.skill.SkillResourceServiceTest')
    AdditionalAsRelativePaths=@(
        'scripts/类定义/org/flashNight/arki/skill/SkillResourceService.as'
        'scripts/类定义/org/flashNight/arki/item/ItemUtil.as'
        'scripts/类定义/org/flashNight/arki/item/itemCollection/ArrayInventory.as'
        'scripts/类定义/org/flashNight/arki/item/itemCollection/DrugInventory.as'
    )
    ExpectedTracePatterns=@(
        '(?m)^SkillResourceServiceTest Tests Passed: [1-9][0-9]*\r?$'
        '(?m)^SkillResourceServiceTest Tests Failed: 0\r?$'
    )
    SuccessSummary='Actual inventory read parity, saturated resource hints, no writes and local A/B'
    TimeoutSeconds=$TimeoutSeconds
    SkipCompile=$SkipCompile
}
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') @run
