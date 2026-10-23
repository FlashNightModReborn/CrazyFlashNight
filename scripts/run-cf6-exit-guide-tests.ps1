[CmdletBinding()]
param([ValidateRange(1,3600)][int]$TimeoutSeconds=360)
$ErrorActionPreference='Stop'
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') `
    -DomainId 'cf6-exit-guide' `
    -TemplateRelativePath 'scripts/test-runners/cf6-exit-guide/TestLoader.as.template' `
    -SuiteRelativePaths @('scripts/类定义/org/flashNight/arki/scene/Cf6ExitGuideTest.as') `
    -SuiteFqns @('org.flashNight.arki.scene.Cf6ExitGuideTest') `
    -AdditionalAsRelativePaths @('scripts/类定义/org/flashNight/arki/scene/Cf6ExitGuideService.as') `
    -ExpectedTracePatterns @('(?m)^Cf6ExitGuideTest Tests Passed: 15\r?$', '(?m)^Cf6ExitGuideTest Tests Failed: 0\r?$') `
    -SuccessSummary '15 exit-guide geometry/visibility/identity assertions; no clear or navigation authority changes' `
    -TimeoutSeconds $TimeoutSeconds
