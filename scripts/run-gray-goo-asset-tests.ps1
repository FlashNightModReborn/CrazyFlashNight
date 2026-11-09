[CmdletBinding()]
param([ValidateRange(1,3600)][int]$TimeoutSeconds=900,[switch]$SkipCompile)
$focusedRun=@{
    DomainId='gray-goo-assets'
    TemplateRelativePath='scripts/test-runners/gray-goo-assets/TestLoader.as.template'
    SuiteRelativePaths=@('scripts/类定义/org/flashNight/arki/render/GrayGooAssetTest.as')
    SuiteFqns=@('org.flashNight.arki.render.GrayGooAssetTest')
    AdditionalAsRelativePaths=@('scripts/类定义/org/flashNight/arki/component/Buff/Effect/ToughnessVulnerabilityController.as')
    ExpectedTracePatterns=@(
        '(?m)^GrayGooAssetTest phases: XML,I,II,III,max,pooled,reuse,zero-loss\r?$',
        '(?m)^GrayGooAssetTest result: passed=37 failed=0\r?$')
    SuccessSummary='GrayGooAssetTest 37/37: visible anchors, real crumble bursts, latest marks, ownership and pooled reset'
    TimeoutSeconds=$TimeoutSeconds
    SkipCompile=$SkipCompile
}
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') @focusedRun
