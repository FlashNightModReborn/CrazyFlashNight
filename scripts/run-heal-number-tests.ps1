[CmdletBinding()]
param([ValidateRange(1,3600)][int]$TimeoutSeconds = 240, [switch]$SkipCompile)
$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'test-runners\run-focused-testloader.ps1') `
    -DomainId 'heal-number' `
    -TemplateRelativePath 'scripts\test-runners\heal-number\TestLoader.as.template' `
    -SuiteRelativePaths @('scripts\类定义\org\flashNight\arki\unit\Action\Regeneration\HealApplierTest.as',
        'scripts\类定义\org\flashNight\arki\unit\Action\Regeneration\HealNumberContractTest.as') `
    -SuiteFqns @('org.flashNight.arki.unit.Action.Regeneration.HealApplierTest',
        'org.flashNight.arki.unit.Action.Regeneration.HealNumberContractTest') `
    -ExpectedTracePatterns @('(?m)^===== HealApplier 汇总: run=\d+ pass=\d+ fail=0 =====\r?$',
        '(?m)^HealNumberContract Tests Passed: 24\r?$', '(?m)^HealNumberContract Tests Failed: 0\r?$') `
    -SuccessSummary 'HealApplier + HealNumberContract 24 assertions' `
    -TimeoutSeconds $TimeoutSeconds -SkipCompile:$SkipCompile
