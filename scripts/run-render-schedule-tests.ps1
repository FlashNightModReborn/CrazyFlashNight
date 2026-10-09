[CmdletBinding()]
param([int]$TimeoutSeconds=240)
$ErrorActionPreference='Stop'
chcp.com 65001 | Out-Null
$run=@{
 DomainId='render-schedule'
 TemplateRelativePath='scripts/test-runners/render-schedule/TestLoader.as.template'
 SuiteRelativePaths=@('scripts/类定义/org/flashNight/neur/PerformanceOptimizer/test/RenderScheduleBridgeTest.as')
 SuiteFqns=@('org.flashNight.neur.PerformanceOptimizer.test.RenderScheduleBridgeTest')
 AdditionalAsRelativePaths=@('scripts/类定义/org/flashNight/neur/PerformanceOptimizer/IntervalSampler.as','scripts/类定义/org/flashNight/neur/PerformanceOptimizer/PerformanceScheduler.as','scripts/类定义/org/flashNight/neur/PerformanceOptimizer/PerformanceActuator.as','scripts/类定义/org/flashNight/neur/PerformanceOptimizer/test/PerformanceSchedulerTest.as','scripts/类定义/org/flashNight/neur/PerformanceOptimizer/test/PerformanceActuatorTest.as','scripts/类定义/org/flashNight/arki/scene/StageEvent.as','scripts/类定义/org/flashNight/neur/Server/ServerManager.as','scripts/通信/通信_fs_帧计时器.as')
 ExpectedTracePatterns=@('(?m)^RenderScheduleBridgeTest Tests Passed: 58\r?$','(?m)^RenderScheduleBridgeTest Tests Failed: 0\r?$')
 SuccessSummary='Render schedule bridge tests passed'
 TimeoutSeconds=$TimeoutSeconds
}
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') @run
exit $LASTEXITCODE
