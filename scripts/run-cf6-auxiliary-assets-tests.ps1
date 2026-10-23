[CmdletBinding()]
param([ValidateRange(1, 3600)][int]$TimeoutSeconds = 360, [switch]$SkipCompile)
$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') `
    -DomainId 'cf6-auxiliary-assets' `
    -TemplateRelativePath 'scripts/test-runners/cf6-auxiliary-assets/TestLoader.as.template' `
    -SuiteRelativePaths @('scripts/类定义/org/flashNight/arki/scene/Cf6AuxiliaryAssetsTest.as') `
    -SuiteFqns @('org.flashNight.arki.scene.Cf6AuxiliaryAssetsTest') `
    -ExpectedTracePatterns @('(?m)^Cf6AuxiliaryAssetsTest Tests Passed: 12\r?$', '(?m)^Cf6AuxiliaryAssetsTest Tests Failed: 0\r?$') `
    -SuccessSummary '12/12 assertions over 224 actual auxiliary asset frames and native pixel animation; no full-game acceptance' `
    -AsyncBehaviorTimeoutSeconds 180 -TimeoutSeconds $TimeoutSeconds -SkipCompile:$SkipCompile
