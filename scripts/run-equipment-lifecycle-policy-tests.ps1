[CmdletBinding()]
param([ValidateRange(1, 3600)][int]$TimeoutSeconds = 240, [switch]$SkipCompile)

$focusedRun = @{
    DomainId = 'equipment-lifecycle-policy'
    TemplateRelativePath = 'scripts\test-runners\equipment-lifecycle-policy\TestLoader.as.template'
    SuiteRelativePaths = @('scripts\类定义\org\flashNight\arki\item\equipment\EquipmentLifecyclePolicyTest.as')
    SuiteFqns = @('org.flashNight.arki.item.equipment.EquipmentLifecyclePolicyTest')
    AdditionalAsRelativePaths = @(
        'scripts\类定义\org\flashNight\arki\item\equipment\EquipmentLifecyclePolicy.as',
        'scripts\类定义\org\flashNight\arki\item\equipment\EquipmentCalculator.as',
        'scripts\类定义\org\flashNight\arki\item\equipment\TagManager.as'
    )
    ExpectedTracePatterns = @(
        '(?m)^EquipmentLifecyclePolicyTest Tests Passed: 28\r?$',
        '(?m)^EquipmentLifecyclePolicyTest Tests Failed: 0\r?$'
    )
    SuccessSummary = '独立插件生命周期：准入、进阶合成、模板保护、移除与重排'
    TimeoutSeconds = $TimeoutSeconds
    SkipCompile = $SkipCompile
}
& (Join-Path $PSScriptRoot 'test-runners\run-focused-testloader.ps1') @focusedRun
