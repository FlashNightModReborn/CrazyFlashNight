[CmdletBinding()]
param([ValidateRange(1, 3600)][int]$TimeoutSeconds = 300, [switch]$SkipCompile)
$ErrorActionPreference = 'Stop'
$focusedRun = @{
    DomainId = 'emergency-injection'
    TemplateRelativePath = 'scripts/test-runners/emergency-injection/TestLoader.as.template'
    SuiteRelativePaths = @('scripts/类定义/org/flashNight/arki/unit/Action/Skill/EmergencyInjectionServiceTest.as')
    SuiteFqns = @('org.flashNight.arki.unit.Action.Skill.EmergencyInjectionServiceTest')
    AdditionalAsRelativePaths = @('scripts/类定义/org/flashNight/arki/item/itemCollection/DrugInventory.as', 'scripts/类定义/org/flashNight/arki/unit/Action/Skill/EmergencyInjectionService.as', 'scripts/类定义/org/flashNight/arki/unit/Action/Skill/EmergencyInjector.as', 'scripts/类定义/org/flashNight/arki/unit/Action/Skill/DrugInputService.as', 'scripts/类定义/org/flashNight/arki/component/Damage/DamageCalculator.as', 'scripts/类定义/org/flashNight/arki/unit/UnitComponent/Initializer/TitaniumSetRuntime.as', 'scripts/类定义/org/flashNight/arki/unit/UnitComponent/Initializer/UnifiedType61Runtime.as')
    ExpectedTracePatterns = @('(?m)^EmergencyInjectionServiceTest Tests Passed: 73\r?$', '(?m)^EmergencyInjectionServiceTest Tests Failed: 0\r?$')
    SuccessSummary = 'Emergency injection native 73/73: per-chest ownership, synchronous damage, real drug container, authorization, cooldown, lifecycle and failure boundaries'
    TimeoutSeconds = $TimeoutSeconds
    SkipCompile = $SkipCompile
}
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') @focusedRun
