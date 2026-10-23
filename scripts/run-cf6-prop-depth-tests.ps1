[CmdletBinding()]
param([ValidateRange(1, 3600)][int]$TimeoutSeconds = 360, [switch]$SkipCompile)
$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') `
    -DomainId 'cf6-prop-depth' `
    -TemplateRelativePath 'scripts/test-runners/cf6-prop-depth/TestLoader.as.template' `
    -SuiteRelativePaths @('scripts/类定义/org/flashNight/arki/scene/Cf6PropDepthServiceTest.as') `
    -SuiteFqns @('org.flashNight.arki.scene.Cf6PropDepthServiceTest') `
    -AdditionalAsRelativePaths @('scripts/类定义/org/flashNight/arki/scene/Cf6PropDepthService.as') `
    -ExpectedTracePatterns @('(?m)^Cf6PropDepthServiceTest Tests Passed: 30\r?$', '(?m)^Cf6PropDepthServiceTest Tests Failed: 0\r?$') `
    -SuccessSummary '30/30 real AVM1 assertions, including BitmapData occlusion and same-path replacement; not full chapter acceptance' `
    -TimeoutSeconds $TimeoutSeconds -SkipCompile:$SkipCompile