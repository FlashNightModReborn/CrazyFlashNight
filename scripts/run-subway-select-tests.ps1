[CmdletBinding()]
param([ValidateRange(1, 3600)][int]$TimeoutSeconds = 244, [switch]$SkipCompile)
$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') `
    -DomainId 'subway-select' `
    -TemplateRelativePath 'scripts/test-runners/subway-select/TestLoader.as.template' `
    -SuiteRelativePaths @('scripts/类定义/org/flashNight/arki/ui/SubwaySelectPanelServiceTest.as') `
    -SuiteFqns @('org.flashNight.arki.ui.SubwaySelectPanelServiceTest') `
    -ExpectedTracePatterns @('(?m)^SubwaySelectPanelServiceTest Tests Passed: 30\r?$', '(?m)^SubwaySelectPanelServiceTest Tests Failed: 0\r?$') `
    -SuccessSummary '30/30 assertions' -TimeoutSeconds $TimeoutSeconds -SkipCompile:$SkipCompile
