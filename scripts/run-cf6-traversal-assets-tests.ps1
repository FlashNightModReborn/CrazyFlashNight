[CmdletBinding()]
param([ValidateRange(1, 3600)][int]$TimeoutSeconds = 360, [switch]$SkipCompile)
$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') `
    -DomainId 'cf6-traversal-assets' `
    -TemplateRelativePath 'scripts/test-runners/cf6-traversal-assets/TestLoader.as.template' `
    -SuiteRelativePaths @('scripts/类定义/org/flashNight/arki/scene/Cf6TraversalAssetsTest.as') `
    -SuiteFqns @('org.flashNight.arki.scene.Cf6TraversalAssetsTest') `
    -ExpectedTracePatterns @('(?m)^Cf6TraversalAssetsTest Tests Passed: 30\r?$', '(?m)^Cf6TraversalAssetsTest Tests Failed: 0\r?$') `
    -SuccessSummary '30/30 assertions over 1124 actual door asset frames and native clipDepth pixels; no full-game acceptance' `
    -AsyncBehaviorTimeoutSeconds 180 -TimeoutSeconds $TimeoutSeconds -SkipCompile:$SkipCompile
