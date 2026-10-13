[CmdletBinding()]
param([int]$TimeoutSeconds = 240, [switch]$SkipCompile)
$ErrorActionPreference='Stop'
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') `
    -DomainId 'swf-authority-debt' `
    -TemplateRelativePath 'scripts/test-runners/swf-authority-debt/TestLoader.as.template' `
    -SuiteRelativePaths @('scripts/类定义/org/flashNight/dev/SWFAuthorityDebtTest.as') `
    -SuiteFqns @('org.flashNight.dev.SWFAuthorityDebtTest') `
    -ExpectedTracePatterns @('(?m)^SWFAuthorityDebtTest passed=11 failed=0\r?$') `
    -SuccessSummary 'Actual resource-first/loader-first ownership and canonical skill calls' `
    -TimeoutSeconds $TimeoutSeconds -SkipCompile:$SkipCompile -AutoStopReadOnlyPlayer
