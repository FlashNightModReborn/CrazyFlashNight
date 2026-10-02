[CmdletBinding()]
param([ValidateRange(1, 3600)][int]$TimeoutSeconds = 244, [switch]$SkipCompile)
$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') `
    -DomainId 'garage-purchase' `
    -TemplateRelativePath 'scripts/test-runners/garage-purchase/TestLoader.as.template' `
    -SuiteRelativePaths @('scripts/类定义/org/flashNight/arki/ui/GaragePurchasePanelServiceTest.as') `
    -SuiteFqns @('org.flashNight.arki.ui.GaragePurchasePanelServiceTest') `
    -ExpectedTracePatterns @('(?m)^GaragePurchasePanelServiceTest Tests Passed: 48\r?$', '(?m)^GaragePurchasePanelServiceTest Tests Failed: 0\r?$') `
    -SuccessSummary '48/48 assertions' -TimeoutSeconds $TimeoutSeconds -SkipCompile:$SkipCompile
