[CmdletBinding()]
param([ValidateRange(1,3600)][int]$TimeoutSeconds=420)
$ErrorActionPreference='Stop'
chcp.com 65001 | Out-Null
$bodyRoot=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path
python -X utf8 (Join-Path $PSScriptRoot 'prepare.py') --check
if($LASTEXITCODE -ne 0) { throw 'Body scale native host check failed.' }
& (Join-Path $bodyRoot 'scripts/test-runners/run-focused-testloader.ps1') `
    -DomainId 'cf6-body-scale' `
    -CompileTargetRelativePath 'scripts/tmp-cf6-body-scale-host/Cf6BodyScaleNativeHost.xfl' `
    -CompileSwfRelativePath 'Cf6BodyScaleNativeHost.swf' `
    -TemplateRelativePath 'tools/cf6-body-scale/TestLoader.as.template' `
    -SuiteRelativePaths @('scripts/类定义/org/flashNight/arki/unit/Cf6BodyScaleNativeTest.as') `
    -SuiteFqns @('org.flashNight.arki.unit.Cf6BodyScaleNativeTest') `
    -AdditionalAsRelativePaths @('scripts/类定义/org/flashNight/arki/unit/Cf6BodyScaleNativeData.as','scripts/类定义/org/flashNight/arki/unit/Cf6BodyScaleLiveProbe.as','scripts/类定义/org/flashNight/arki/unit/Cf6BodyScaleRules.as','scripts/引擎/引擎_fs_常用工具函数.as','scripts/类定义/org/flashNight/gesh/xml/LoadXml/EnemyPropertiesLoader.as','scripts/逻辑/关卡系统/关卡系统_lsy_地图元件.as','scripts/逻辑/单位函数/单位函数_lsy_敌人模板迁移.as','scripts/逻辑/战斗系统/战斗系统_fs_lsy_aka_重写子弹生成逻辑.as','scripts/逻辑/关卡系统/关卡系统_lsy_场景转换.as') `
    -ExpectedTracePatterns @('(?m)^Cf6BodyScaleLiveProbe: 7 measured, 0 failed\r?$', '(?m)^Cf6BodyScaleNativeTest Tests Passed: 21\r?$', '(?m)^Cf6BodyScaleNativeTest Tests Failed: 0\r?$') `
    -SuccessSummary '21 native assertions: seven alpha body heights and fourteen owned-scale left/right direction checks' `
    -AsyncBehaviorTimeoutSeconds 60 -TimeoutSeconds $TimeoutSeconds
exit $LASTEXITCODE
