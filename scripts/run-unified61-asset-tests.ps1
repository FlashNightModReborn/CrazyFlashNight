[CmdletBinding()]
param([ValidateRange(1, 3600)][int]$TimeoutSeconds = 300, [switch]$SkipCompile)
$ErrorActionPreference = 'Stop'
& python -X utf8 (Join-Path $PSScriptRoot '..\tools\unified61-assets\sync_probe.py') --check
if ($LASTEXITCODE -ne 0) { throw '生产切枪函数与测试投影不一致；先同步模板并重新编译。' }
$focusedRun = @{
    DomainId = 'unified61-assets'
    TemplateRelativePath = 'scripts\test-runners\unified61-assets\TestLoader.as.template'
    SuiteRelativePaths = @('scripts\类定义\org\flashNight\arki\unit\UnitComponent\Initializer\test\UnifiedType61AssetTest.as')
    SuiteFqns = @('org.flashNight.arki.unit.UnitComponent.Initializer.test.UnifiedType61AssetTest')
    AdditionalAsRelativePaths = @('scripts\逻辑\单位函数\单位函数_fs_aka_玩家模板迁移.as')
    ExpectedTracePatterns = @('(?m)^UnifiedType61AssetTest Tests Passed: 107\r?$', '(?m)^UnifiedType61AssetTest Tests Failed: 0\r?$')
    SuccessSummary = '统合61式原生导出、像素绘制、胸炮三态、图标双帧与真实切枪事件'
    TimeoutSeconds = $TimeoutSeconds
    AsyncBehaviorTimeoutSeconds = 120
    SkipCompile = $SkipCompile
}
& (Join-Path $PSScriptRoot 'test-runners\run-focused-testloader.ps1') @focusedRun
