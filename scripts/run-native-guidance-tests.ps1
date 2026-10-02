[CmdletBinding()]
param([int]$TimeoutSeconds=240,[switch]$SkipCompile)
$ErrorActionPreference='Stop'
$focusedRun=@{
    DomainId='native-guidance'
    TemplateRelativePath='scripts/test-runners/native-guidance/TestLoader.as.template'
    SuiteRelativePaths=@('scripts/类定义/org/flashNight/arki/ui/NativeGuidanceServiceTest.as')
    SuiteFqns=@('org.flashNight.arki.ui.NativeGuidanceServiceTest')
    AdditionalAsRelativePaths=@('scripts/类定义/org/flashNight/arki/ui/NativeGuidanceService.as')
    ExpectedTracePatterns=@('(?m)^NativeGuidanceServiceTest Tests Passed: 54\r?$','(?m)^NativeGuidanceServiceTest Tests Failed: 0\r?$')
    SuccessSummary='U8 原生引导映射、显示时序与清理测试通过'
    TimeoutSeconds=$TimeoutSeconds
    SkipCompile=$SkipCompile
}
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') @focusedRun
