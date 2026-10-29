[CmdletBinding()]
param([int]$TimeoutSeconds=240,[switch]$SkipCompile)
$ErrorActionPreference='Stop'
chcp.com 65001 | Out-Null
$run=@{
 DomainId='bullet-visual'
 TemplateRelativePath='scripts/test-runners/bullet-visual/TestLoader.as.template'
 SuiteRelativePaths=@(
  'scripts/类定义/org/flashNight/arki/render/BulletVisualProbeTest.as',
  'scripts/类定义/org/flashNight/arki/render/NativeFrameTagTest.as'
 )
 SuiteFqns=@('org.flashNight.arki.render.BulletVisualProbeTest','org.flashNight.arki.render.NativeFrameTagTest')
 AdditionalAsRelativePaths=@(
  'scripts/类定义/org/flashNight/arki/render/BulletVisualProbe.as',
  'scripts/类定义/org/flashNight/arki/render/NativeFrameTag.as',
  'scripts/类定义/org/flashNight/arki/bullet/BulletComponent/Chain/ChainUnitManager.as'
 )
 ExpectedTracePatterns=@(
  '(?m)^BulletVisualProbeTest Tests Passed: 15\r?$',
  '(?m)^BulletVisualProbeTest Tests Failed: 0\r?$',
  '(?m)^NativeFrameTagTest Tests Passed: 12\r?$',
  '(?m)^NativeFrameTagTest Tests Failed: 0\r?$'
 )
 SuccessSummary='Bullet ownership plus native source-frame tag matrix'
 TimeoutSeconds=$TimeoutSeconds
 SkipCompile=$SkipCompile
}
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') @run
exit $LASTEXITCODE
