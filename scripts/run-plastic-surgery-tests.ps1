[CmdletBinding()]
param([ValidateRange(1, 3600)][int]$TimeoutSeconds = 244, [switch]$SkipCompile)
$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') `
    -DomainId 'plastic-surgery' `
    -TemplateRelativePath 'scripts/test-runners/plastic-surgery/TestLoader.as.template' `
    -SuiteRelativePaths @('scripts/类定义/org/flashNight/arki/ui/PlasticSurgeryPanelServiceTest.as') `
    -SuiteFqns @('org.flashNight.arki.ui.PlasticSurgeryPanelServiceTest') `
    -ExpectedTracePatterns @('(?m)^PlasticSurgeryPanelServiceTest Tests Passed: 44\r?$', '(?m)^PlasticSurgeryPanelServiceTest Tests Failed: 0\r?$') `
    -SuccessSummary '44/44 assertions' -TimeoutSeconds $TimeoutSeconds -SkipCompile:$SkipCompile
