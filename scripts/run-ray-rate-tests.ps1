[CmdletBinding()]
param([ValidateRange(1,3600)][int]$TimeoutSeconds=1800,[switch]$ScanCompare,[switch]$SkipCompile)
$ErrorActionPreference='Stop'
chcp.com 65001 | Out-Null
$sourceXml=Join-Path (Split-Path -Parent $PSScriptRoot) 'data/items/bullets_cases.xml'
Write-Host ('[RAY_RATE_XML_SHA256] '+(Get-FileHash -LiteralPath $sourceXml -Algorithm SHA256).Hash)
$expectedPairs=if($ScanCompare){4}else{54}
$template=if($ScanCompare){'scripts/test-runners/ray-rate/ScanCompare.TestLoader.as.template'}else{'scripts/test-runners/ray-rate/TestLoader.as.template'}
$asyncWait=if($ScanCompare){900}else{1800}
$run=@{
 DomainId='ray-rate'
 TemplateRelativePath=$template
 SuiteRelativePaths=@('scripts/类定义/org/flashNight/arki/bullet/BulletComponent/Queue/RayRateTest.as')
 SuiteFqns=@('org.flashNight.arki.bullet.BulletComponent.Queue.RayRateTest')
 AdditionalAsRelativePaths=@(
  'scripts/类定义/org/flashNight/arki/bullet/BulletComponent/Queue/BulletQueueProcessor.as',
  'scripts/类定义/org/flashNight/arki/bullet/BulletComponent/Queue/RayComboCursor.as',
  'scripts/类定义/org/flashNight/arki/bullet/BulletComponent/Lifecycle/TeslaRayLifecycle.as',
  'scripts/类定义/org/flashNight/arki/unit/Action/Shoot/WeaponFireCore.as',
  'scripts/类定义/org/flashNight/arki/bullet/BulletComponent/Config/TeslaRayConfig.as',
  'scripts/类定义/org/flashNight/arki/render/RayVisualBridge.as',
  'scripts/类定义/org/flashNight/arki/render/RayVfxManager.as',
  'scripts/类定义/org/flashNight/arki/render/VisualRandom.as',
  'scripts/类定义/org/flashNight/arki/component/Damage/DamageCalculator.as',
  'scripts/类定义/org/flashNight/arki/component/Damage/DamageManager.as',
  'scripts/类定义/org/flashNight/arki/component/StatHandler/DodgeHandler.as'
 )
 ExpectedTracePatterns=@(
  '(?m)^RayRate Tests Passed: [1-9][0-9]*\r?$',
  '(?m)^RayRate Tests Failed: 0\r?$',
  ('(?m)^\[RAY_RATE_DONE\] pairs='+$expectedPairs+' elapsedMs=[0-9]+\r?$'),
  '(?m)^\[RAY_RATE_SCOPE\] real=production-XML,Ray/Band-collider,BQP,Dodge,DamageCalculator,'
 )
 SuccessSummary='Controlled real AS2 selection/settlement rate matrix, visual-channel off/on equivalence, bounded timings and native wire replay; not battle FPS or save/weapon validation'
 AsyncBehaviorTimeoutSeconds=$asyncWait
 TimeoutSeconds=$TimeoutSeconds
 SkipCompile=$SkipCompile
}
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') @run
exit $LASTEXITCODE
