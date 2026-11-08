[CmdletBinding()]
param([ValidateRange(1,3600)][int]$TimeoutSeconds=600,[switch]$SkipCompile)
$focusedRun=@{
    DomainId='gray-goo-assets'
    TemplateRelativePath='scripts/test-runners/gray-goo-assets/TestLoader.as.template'
    SuiteRelativePaths=@('scripts/类定义/org/flashNight/arki/render/GrayGooAssetTest.as')
    SuiteFqns=@('org.flashNight.arki.render.GrayGooAssetTest')
    AdditionalAsRelativePaths=@('scripts/类定义/org/flashNight/arki/component/Buff/Effect/ToughnessVulnerabilityController.as')
    ExpectedTracePatterns=@(
        '(?m)^GrayGooAssetTest phases: XML,I,II,III,max,pooled,reuse\r?$',
        '(?m)^GrayGooAssetTest result: passed=17 failed=0\r?$')
    SuccessSummary='GrayGooAssetTest 17/17 real asset stages and pooling'
    TimeoutSeconds=$TimeoutSeconds
    SkipCompile=$SkipCompile
}
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') @focusedRun
