[CmdletBinding()]
param([int]$TimeoutSeconds = 240, [switch]$SkipCompile)
$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') `
    -DomainId 'scheduler-boundary' `
    -TemplateRelativePath 'scripts/test-runners/scheduler-boundary/TestLoader.as.template' `
    -SuiteRelativePaths @('scripts/类定义/org/flashNight/dev/SchedulerBoundaryTest.as') `
    -SuiteFqns @('org.flashNight.dev.SchedulerBoundaryTest') `
    -ExpectedTracePatterns @('(?m)^SchedulerBoundaryTests passed=4 failed=0\r?$') `
    -SuccessSummary 'Invalid interval rejection preserves task identity and queue membership' `
    -TimeoutSeconds $TimeoutSeconds -SkipCompile:$SkipCompile -AutoStopReadOnlyPlayer
