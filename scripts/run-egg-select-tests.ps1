[CmdletBinding()]
param([ValidateRange(1, 3600)][int]$TimeoutSeconds = 244, [switch]$SkipCompile)
$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') `
    -DomainId 'egg-select' `
    -TemplateRelativePath 'scripts/test-runners/egg-select/TestLoader.as.template' `
    -SuiteRelativePaths @('scripts/类定义/org/flashNight/arki/ui/EggSelectPanelServiceTest.as') `
    -SuiteFqns @('org.flashNight.arki.ui.EggSelectPanelServiceTest') `
    -ExpectedTracePatterns @('(?m)^EggSelectPanelServiceTest Tests Passed: 25\r?$', '(?m)^EggSelectPanelServiceTest Tests Failed: 0\r?$') `
    -SuccessSummary '25/25 assertions' -TimeoutSeconds $TimeoutSeconds -SkipCompile:$SkipCompile
