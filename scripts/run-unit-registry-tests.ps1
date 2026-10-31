[CmdletBinding()]
param(
    [ValidateRange(1, 3600)]
    [int]$TimeoutSeconds = 240
)

$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'test-runners\run-focused-testloader.ps1') `
    -DomainId 'unit-registry' `
    -TemplateRelativePath 'scripts\test-runners\unit-registry\TestLoader.as.template' `
    -SuiteRelativePaths @('scripts\类定义\org\flashNight\arki\unit\UnitRegistryTest.as') `
    -SuiteFqns @('org.flashNight.arki.unit.UnitRegistryTest') `
    -ExpectedTracePatterns @(
        '(?m)^UnitRegistryTest Production Summary: units=475, keys=475, stageEnemies=134, books=3/3\r?$',
        '(?m)^UnitRegistryTest Tests Passed: 62\r?$',
        '(?m)^UnitRegistryTest Tests Failed: 0\r?$',
        '(?m)^UnitRegistryTest Cases Passed: 9/9\r?$'
    ) `
    -SuccessSummary '62/62 assertions, 9/9 cases (475 production units + stages + 3 books)' `
    -TimeoutSeconds $TimeoutSeconds
