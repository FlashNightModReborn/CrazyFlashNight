[CmdletBinding()]
param([int]$TimeoutSeconds=240)
$ErrorActionPreference='Stop'
chcp.com 65001 | Out-Null
$run=@{
 DomainId='visual-wire-q1'
 TemplateRelativePath='scripts/test-runners/visual-wire-q1/TestLoader.as.template'
 SuiteRelativePaths=@('scripts/类定义/org/flashNight/arki/render/VisualWireQ1Test.as')
 SuiteFqns=@('org.flashNight.arki.render.VisualWireQ1Test')
 AdditionalAsRelativePaths=@('scripts/类定义/org/flashNight/arki/render/BulletVisualProbe.as','scripts/类定义/org/flashNight/arki/render/VisualWireService.as')
 ExpectedTracePatterns=@('(?m)^VisualWireQ1Test Tests Passed: 16\r?$','(?m)^VisualWireQ1Test Tests Failed: 0\r?$')
 SuccessSummary='Q1-R actual MovieClip, broadcaster, negotiation and lifetime boundary matrix'
 TimeoutSeconds=$TimeoutSeconds
}
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') @run
exit $LASTEXITCODE
