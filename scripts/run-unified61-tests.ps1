[CmdletBinding()]
param([ValidateRange(1, 3600)][int]$TimeoutSeconds = 360)
$ErrorActionPreference = 'Stop'
& python -X utf8 (Join-Path $PSScriptRoot '..\tools\unified61-assets\sync_probe.py') --check
if ($LASTEXITCODE -ne 0) { throw '生产切枪函数与测试投影不一致；先同步模板并重新编译。' }
& python -X utf8 (Join-Path $PSScriptRoot '..\tools\unified61-assets\check_mod_policy.py')
if ($LASTEXITCODE -ne 0) { throw '封闭改装数据检查失败。' }
$focusedRun = @{
    DomainId = 'unified61-final'
    TemplateRelativePath = 'scripts\test-runners\unified61-final\TestLoader.as.template'
    SuiteRelativePaths = @('scripts\类定义\org\flashNight\arki\unit\UnitComponent\Initializer\test\UnifiedType61RuntimeTest.as', 'scripts\类定义\org\flashNight\arki\unit\UnitComponent\Initializer\test\UnifiedType61AssetTest.as', 'scripts\类定义\org\flashNight\arki\item\equipment\ClosedModPolicyTest.as')
    SuiteFqns = @('org.flashNight.arki.unit.UnitComponent.Initializer.test.UnifiedType61RuntimeTest', 'org.flashNight.arki.unit.UnitComponent.Initializer.test.UnifiedType61AssetTest', 'org.flashNight.arki.item.equipment.ClosedModPolicyTest')
    AdditionalAsRelativePaths = @('scripts\类定义\org\flashNight\arki\unit\UnitComponent\Initializer\UnifiedType61Runtime.as', 'scripts\逻辑\装备函数\统合61套装.as', 'scripts\逻辑\单位函数\单位函数_fs_aka_玩家模板迁移.as', 'scripts\逻辑\单位函数\单位函数_fs_装备生命周期配置.as', 'scripts\类定义\org\flashNight\arki\unit\Action\Shoot\ReloadManager.as', 'scripts\类定义\org\flashNight\arki\unit\Action\Shoot\WeaponAmmoRuntime.as')
    ExpectedTracePatterns = @('(?m)^UnifiedType61RuntimeTest Tests Passed: 94\r?$', '(?m)^UnifiedType61RuntimeTest Tests Failed: 0\r?$', '(?m)^UnifiedType61AssetTest Tests Passed: 107\r?$', '(?m)^UnifiedType61AssetTest Tests Failed: 0\r?$', '(?m)^ClosedModPolicyTest Tests Passed: 3115\r?$', '(?m)^ClosedModPolicyTest Tests Failed: 0\r?$')
    SuccessSummary = '统合61式3316项：逻辑与HUD94、原生资产与生产切枪107、封闭插件3115'
    TimeoutSeconds = $TimeoutSeconds
    AsyncBehaviorTimeoutSeconds = 120
}
& (Join-Path $PSScriptRoot 'test-runners\run-focused-testloader.ps1') @focusedRun
