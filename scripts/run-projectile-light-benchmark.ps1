[CmdletBinding()]
param([ValidateRange(1, 3600)][int]$TimeoutSeconds = 240, [switch]$SkipCompile)

$focusedRun = @{
    DomainId = 'projectile-light-benchmark'
    TemplateRelativePath = 'scripts\test-runners\projectile-light-benchmark\TestLoader.as.template'
    SuiteRelativePaths = @('scripts\类定义\org\flashNight\arki\render\ProjectileLightBenchmark.as')
    SuiteFqns = @('org.flashNight.arki.render.ProjectileLightBenchmark')
    ExpectedTracePatterns = @(0..4 | ForEach-Object { "(?m)^ProjectileLightBenchmark case=$_ calls=\d+ samples=30 allocations=\d+ registered=\d+ sources=\d+ admitted=\d+ registerMsP50=\d+ registerMsP95=\d+ payloadMsP50=\d+ payloadMsP95=\d+\r?$" })
    SuccessSummary = '动态光效五类固定负载、登记和出灯耗时'
    TimeoutSeconds = $TimeoutSeconds
    SkipCompile = $SkipCompile
}
& (Join-Path $PSScriptRoot 'test-runners\run-focused-testloader.ps1') @focusedRun
