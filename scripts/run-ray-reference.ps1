[CmdletBinding()]
param([int]$TimeoutSeconds=240,[switch]$SkipCompile)
$ErrorActionPreference='Stop'
chcp.com 65001 | Out-Null
$sourceXml = Join-Path (Split-Path -Parent $PSScriptRoot) 'data/items/bullets_cases.xml'
Write-Host ('[RAY_REFERENCE_XML_SHA256] ' + (Get-FileHash -LiteralPath $sourceXml -Algorithm SHA256).Hash)
$run=@{
 DomainId='ray-reference'
 TemplateRelativePath='scripts/test-runners/ray-visual/RayReference.TestLoader.as.template'
 SuiteRelativePaths=@('scripts/类定义/org/flashNight/arki/render/RayVfxManagerTest.as')
 SuiteFqns=@('org.flashNight.arki.render.RayVfxManagerTest')
 AdditionalAsRelativePaths=@(
  'scripts/test-runners/ray-visual/RayReferenceBoard.as',
  'scripts/类定义/org/flashNight/arki/bullet/BulletComponent/Config/TeslaRayConfig.as',
  'scripts/类定义/org/flashNight/arki/render/RayVisualBridge.as',
  'scripts/类定义/org/flashNight/arki/render/RayVfxManager.as',
  'scripts/类定义/org/flashNight/arki/render/RayStyleRegistry.as',
  'scripts/类定义/org/flashNight/arki/render/VfxPresets.as',
  'scripts/类定义/org/flashNight/arki/render/VisualRandom.as',
  'scripts/类定义/org/flashNight/naki/RandomNumberEngine/SeededLinearCongruentialEngine.as',
  'scripts/类定义/org/flashNight/arki/render/renderer/TeslaRenderer.as',
  'scripts/类定义/org/flashNight/arki/render/renderer/PhaseResonanceRenderer.as',
  'scripts/类定义/org/flashNight/arki/render/renderer/BaguaRodRenderer.as',
  'scripts/类定义/org/flashNight/arki/render/renderer/FlameStreamRenderer.as',
  'scripts/类定义/org/flashNight/arki/render/renderer/ThermalRenderer.as',
  'scripts/类定义/org/flashNight/arki/render/renderer/PrismRenderer.as'
 )
 ExpectedTracePatterns=@(
  '(?m)^===== RayVfxManagerTest 结束: run=[1-9][0-9]*, pass=[1-9][0-9]*, fail=0 =====\r?$',
  '(?m)^RayReference Tests Passed: [1-9][0-9]*\r?$',
  '(?m)^RayReference Tests Failed: 0\r?$',
  '(?m)^\[RAY_REFERENCE_READY\] cases=13\|source=.+\|originalRenderer=true\|bodyOnly=true\|logical=1024:576\r?$',
  '(?m)^\[RAY_GPU_SCENE\] bagua_age0\r?$',
  '(?m)^\[RAY_GPU_SCENE\] bagua_age4\r?$',
  '(?m)^\[RAY_GPU_SCENE\] bagua_age8\r?$',
  '(?m)^\[RAY_GPU_SCENE\] bagua_fade11\r?$',
  '(?m)^\[RAY_GPU_SCENE\] tesla_age0\r?$',
  '(?m)^\[RAY_GPU_SCENE\] tesla_age2\r?$',
  '(?m)^\[RAY_GPU_SCENE\] resonance_age0\r?$',
  '(?m)^\[RAY_GPU_SCENE\] resonance_age2\r?$',
  '(?m)^\[RAY_GPU_SCENE\] tesla_basic_age2\r?$',
  '(?m)^\[RAY_GPU_SCENE\] flame_field\r?$',
  '(?m)^\[RAY_GPU_SCENE\] thermal_field\r?$',
  '(?m)^\[RAY_GPU_SCENE\] thermal_enhanced_field\r?$',
  '(?m)^\[RAY_GPU_SCENE\] prism_field\r?$'
 )
 SuccessSummary='Production XML original Flash renderer reference, preserved age/fade board and exact native replay wire; visual acceptance remains separate'
 TimeoutSeconds=$TimeoutSeconds
 SkipCompile=$SkipCompile
}
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') @run
exit $LASTEXITCODE