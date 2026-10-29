[CmdletBinding()]
param([ValidateRange(1, 3600)][int]$TimeoutSeconds = 360)
$ErrorActionPreference = 'Stop'
& python -X utf8 (Join-Path $PSScriptRoot '..\tools\unified61-assets\check_mod_policy.py')
if ($LASTEXITCODE -ne 0) { throw '封闭改装数据检查失败。' }
$focusedRun = @{
    DomainId = 'closed-mod-policy'
    TemplateRelativePath = 'scripts\test-runners\closed-mod-policy\TestLoader.as.template'
    SuiteRelativePaths = @('scripts\类定义\org\flashNight\arki\item\equipment\ClosedModPolicyTest.as')
    SuiteFqns = @('org.flashNight.arki.item.equipment.ClosedModPolicyTest')
    AdditionalAsRelativePaths = @('scripts\类定义\org\flashNight\arki\item\equipment\TagManager.as', 'scripts\类定义\org\flashNight\arki\item\equipment\ModRegistry.as', 'scripts\类定义\org\flashNight\arki\item\EquipmentUtil.as', 'scripts\类定义\org\flashNight\arki\item\equipment\EquipmentCalculator.as')
    ExpectedTracePatterns = @('(?m)^ClosedModPolicyTest Tests Passed: [1-9][0-9]*\r?$', '(?m)^ClosedModPolicyTest Tests Failed: 0\r?$')
    SuccessSummary = '现役XML的26件封闭装备：目录过滤、安装门、全部插件拒绝面、等级实际计算与例外保持'
    TimeoutSeconds = $TimeoutSeconds
    AsyncBehaviorTimeoutSeconds = 120
}
& (Join-Path $PSScriptRoot 'test-runners\run-focused-testloader.ps1') @focusedRun
