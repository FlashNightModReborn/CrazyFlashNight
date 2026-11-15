[CmdletBinding()]
param([ValidateRange(1, 3600)][int]$TimeoutSeconds = 900, [switch]$SkipCompile)
$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') `
    -DomainId 'asloader-retirement' `
    -TemplateRelativePath 'scripts/test-runners/asloader-retirement/TestLoader.as.template' `
    -SuiteRelativePaths @('scripts/类定义/org/flashNight/gesh/tooltip/test/TooltipTestSuite.as') `
    -SuiteFqns @('org.flashNight.gesh.tooltip.test.TooltipTestSuite') `
    -AdditionalAsRelativePaths @('scripts/类定义/org/flashNight/gesh/tooltip/TooltipComposer.as','scripts/类定义/org/flashNight/gesh/tooltip/SkillTooltipComposer.as','scripts/类定义/org/flashNight/gesh/tooltip/NativeTooltipDocument.as','scripts/类定义/org/flashNight/gesh/tooltip/NativeTooltipBridge.as') `
    -ExpectedTracePatterns @('(?m)^ ALL PASSED: ([1-9][0-9]*)/\1 \(15 suites\)\r?$') `
    -SuccessSummary '15 existing tooltip suites including native document/owner lifecycle and content builders; no save writes' `
    -TimeoutSeconds $TimeoutSeconds -SkipCompile:$SkipCompile
