[CmdletBinding()]
param([ValidateRange(1, 3600)][int]$TimeoutSeconds = 240, [switch]$SkipCompile)

$focusedRun = @{
    DomainId = 'equipment-light'
    TemplateRelativePath = 'scripts\test-runners\equipment-light\TestLoader.as.template'
    SuiteRelativePaths = @('scripts\类定义\org\flashNight\arki\render\EquipmentLightTest.as')
    SuiteFqns = @('org.flashNight.arki.render.EquipmentLightTest')
    AdditionalAsRelativePaths = @(
        'scripts\类定义\org\flashNight\arki\render\EquipmentLightBridge.as',
        'scripts\类定义\org\flashNight\arki\unit\UnitComponent\Dressup\EquipmentUtil\EquipmentLightController.as'
    )
    ExpectedTracePatterns = @(
        '(?m)^EquipmentLightTest Tests Passed: 34\r?$',
        '(?m)^EquipmentLightTest Tests Failed: 0\r?$'
    )
    SuccessSummary = '装备光源：真实MovieClip锚点、姿态、常驻身份、内置去重与卸载'
    TimeoutSeconds = $TimeoutSeconds
    SkipCompile = $SkipCompile
}
& (Join-Path $PSScriptRoot 'test-runners\run-focused-testloader.ps1') @focusedRun
