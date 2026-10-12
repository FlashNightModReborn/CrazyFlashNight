[CmdletBinding()]
param([int]$TimeoutSeconds = 180, [switch]$SkipCompile)
$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') `
    -DomainId 'student-load-probe' `
    -TemplateRelativePath 'scripts/test-runners/student-load-probe/TestLoader.as.template' `
    -SuiteRelativePaths @('scripts/类定义/org/flashNight/dev/StudentLoadProbeTest.as') `
    -SuiteFqns @('org.flashNight.dev.StudentLoadProbeTest') `
    -ExpectedTracePatterns @('(?m)^StudentLoadProbeTest passed=8 failed=0\r?$') `
    -SuccessSummary 'Resource load, cleanup, two native initializations and starting states only' `
    -TimeoutSeconds $TimeoutSeconds -AsyncBehaviorTimeoutSeconds 10 `
    -OwnedReadOnlyHost -SkipCompile:$SkipCompile
