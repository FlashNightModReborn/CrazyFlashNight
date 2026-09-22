[CmdletBinding()]
param([int]$TimeoutSeconds=240)
$ErrorActionPreference='Stop'
chcp.com 65001 | Out-Null
$run=@{
 DomainId='render-schedule'
 TemplateRelativePath='scripts/test-runners/render-schedule/TestLoader.as.template'
 SuiteRelativePaths=@('scripts/类定义/org/flashNight/neur/PerformanceOptimizer/test/RenderScheduleBridgeTest.as')
 SuiteFqns=@('org.flashNight.neur.PerformanceOptimizer.test.RenderScheduleBridgeTest')
 AdditionalAsRelativePaths=@('scripts/类定义/org/flashNight/neur/PerformanceOptimizer/IntervalSampler.as','scripts/类定义/org/flashNight/neur/PerformanceOptimizer/PerformanceScheduler.as','scripts/类定义/org/flashNight/neur/PerformanceOptimizer/PerformanceActuator.as')
 ExpectedTracePatterns=@('(?m)^RenderScheduleBridgeTest Tests Passed: 17\r?$','(?m)^RenderScheduleBridgeTest Tests Failed: 0\r?$')
 SuccessSummary='Render schedule bridge tests passed'
 TimeoutSeconds=$TimeoutSeconds
}
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') @run
exit $LASTEXITCODE
