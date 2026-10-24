[CmdletBinding()]
param([ValidateRange(1, 3600)][int]$TimeoutSeconds = 360, [switch]$SkipCompile)
$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') `
    -DomainId 'cf6-economy' `
    -TemplateRelativePath 'scripts/test-runners/cf6-economy/TestLoader.as.template' `
    -SuiteRelativePaths @('scripts/类定义/org/flashNight/arki/scene/Cf6EconomyRulesTest.as') `
    -SuiteFqns @('org.flashNight.arki.scene.Cf6EconomyRulesTest') `
    -AdditionalAsRelativePaths @('scripts/类定义/org/flashNight/arki/scene/Cf6EconomyRules.as','scripts/类定义/org/flashNight/arki/scene/BookRunRules.as','scripts/类定义/org/flashNight/arki/scene/BookRunService.as') `
    -ExpectedTracePatterns @('(?m)^Cf6EconomyRulesTest Tests Passed: 53\r?$', '(?m)^Cf6EconomyRulesTest Tests Failed: 0\r?$') `
    -SuccessSummary '53/53 finite seeded supply, exact elite ownership and cloned run identity assertions; no inventory/save writes' `
    -TimeoutSeconds $TimeoutSeconds -SkipCompile:$SkipCompile
