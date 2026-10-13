[CmdletBinding()]
param([int]$TimeoutSeconds = 240, [switch]$SkipCompile)
$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') `
    -DomainId 'scheduler-debt' `
    -TemplateRelativePath 'scripts/test-runners/scheduler-debt/TestLoader.as.template' `
    -SuiteRelativePaths @('scripts/类定义/org/flashNight/dev/SchedulerDebtTest.as') `
    -SuiteFqns @('org.flashNight.dev.SchedulerDebtTest') `
    -ExpectedTracePatterns @('(?m)^SchedulerDebtTest passed=[1-9][0-9]* failed=0\r?$', '(?m)^SchedulerMovieClipTests passed=[1-9][0-9]* failed=0\r?$') `
    -SuccessSummary 'Stable Task identity, coarse deadlines, lifecycle and load comparisons' `
    -TimeoutSeconds $TimeoutSeconds -SkipCompile:$SkipCompile -AutoStopReadOnlyPlayer
