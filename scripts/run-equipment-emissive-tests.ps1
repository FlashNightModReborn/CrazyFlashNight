[CmdletBinding()]
param([ValidateRange(1, 3600)][int]$TimeoutSeconds = 240, [switch]$SkipCompile)

$focusedRun = @{
    DomainId = 'equipment-emissive'
    TemplateRelativePath = 'scripts\test-runners\equipment-emissive\TestLoader.as.template'
    SuiteRelativePaths = @('scripts\类定义\org\flashNight\arki\render\EquipmentEmissiveTest.as')
    SuiteFqns = @('org.flashNight.arki.render.EquipmentEmissiveTest')
    AdditionalAsRelativePaths = @(
        'scripts\类定义\org\flashNight\arki\render\EquipmentLightBridge.as',
        'scripts\类定义\org\flashNight\arki\unit\UnitComponent\Dressup\EquipmentUtil\EquipmentLightController.as',
        'scripts\类定义\org\flashNight\arki\unit\UnitComponent\Dressup\EquipmentUtil\EquipmentEmissiveController.as',
        'scripts\类定义\org\flashNight\arki\unit\UnitComponent\Dressup\EquipmentUtil\EquipmentEmissionState.as'
    )
    ExpectedTracePatterns = @(
        '(?m)^EquipmentEmissiveTest Tests Passed: 99\r?$',
        '(?m)^EquipmentEmissiveTest Tests Failed: 0\r?$'
    )
    SuccessSummary = '装备自发光：单位归并、状态观察、刀光包络、优先预算与清理'
    TimeoutSeconds = $TimeoutSeconds
    SkipCompile = $SkipCompile
}
& (Join-Path $PSScriptRoot 'test-runners\run-focused-testloader.ps1') @focusedRun
