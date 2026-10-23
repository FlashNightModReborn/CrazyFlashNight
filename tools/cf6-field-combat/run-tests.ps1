[CmdletBinding()]
param([ValidateRange(1,3600)][int]$TimeoutSeconds=420)
$ErrorActionPreference='Stop'
chcp.com 65001 | Out-Null
$fieldRoot=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path
python -X utf8 (Join-Path $PSScriptRoot 'prepare.py') --check
if($LASTEXITCODE -ne 0) { throw 'Field combat source preparation check failed.' }
& (Join-Path $fieldRoot 'scripts/test-runners/run-focused-testloader.ps1') `
    -DomainId 'cf6-field-combat' `
    -CompileTargetRelativePath 'scripts/tmp-cf6-field-combat3-host/Cf6FieldCombatNativeHost.xfl' `
    -CompileSwfRelativePath 'Cf6FieldCombat3NativeHost.swf' `
    -TemplateRelativePath 'tools/cf6-field-combat/TestLoader.as.template' `
    -SuiteRelativePaths @('scripts/类定义/org/flashNight/arki/scene/Cf6FieldCombatTest.as') `
    -SuiteFqns @('org.flashNight.arki.scene.Cf6FieldCombatTest') `
    -AdditionalAsRelativePaths @('scripts/类定义/org/flashNight/arki/scene/Cf6FieldCombatData.as','scripts/类定义/org/flashNight/arki/unit/Cf6BodyScaleRules.as','scripts/引擎/引擎_fs_常用工具函数.as','scripts/逻辑/关卡系统/关卡系统_lsy_地图元件.as','scripts/类定义/org/flashNight/gesh/xml/LoadXml/EnemyPropertiesLoader.as','scripts/类定义/org/flashNight/arki/spatial/animation/FragmentAnimator.as','scripts/类定义/org/flashNight/arki/scene/Cf6TutorialTurretService.as','scripts/类定义/org/flashNight/arki/scene/Cf6InteractivePropService.as','scripts/类定义/org/flashNight/arki/scene/WaveSpawner.as','scripts/类定义/org/flashNight/arki/scene/WaveSpawnWheel.as','scripts/类定义/org/flashNight/arki/scene/Cf6BossEncounter.as','scripts/逻辑/单位函数/单位函数_lsy_敌人模板迁移.as','scripts/逻辑/战斗系统/战斗系统_fs_lsy_aka_重写子弹生成逻辑.as','scripts/逻辑/关卡系统/关卡系统_lsy_场景转换.as') `
    -ExpectedTracePatterns @('(?m)^Cf6FieldCombatTest Tests Passed: 65\r?$', '(?m)^Cf6FieldCombatTest Tests Failed: 0\r?$') `
    -SuccessSummary '65 native assertions: projectiles, pod handoff, elder death, real headbot/guard capacity and cancellation' `
    -AsyncBehaviorTimeoutSeconds 180 -TimeoutSeconds $TimeoutSeconds
exit $LASTEXITCODE
