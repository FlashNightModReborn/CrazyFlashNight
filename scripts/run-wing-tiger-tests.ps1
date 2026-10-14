[CmdletBinding()]
param([ValidateRange(1,3600)][int]$TimeoutSeconds=240,[switch]$SkipCompile)
$focusedRun=@{
    DomainId='wing-tiger'
    TemplateRelativePath='scripts/test-runners/wing-tiger/TestLoader.as.template'
    SuiteRelativePaths=@('scripts/类定义/org/flashNight/arki/unit/UnitAI/Custom/WingTigerTest.as')
    SuiteFqns=@('org.flashNight.arki.unit.UnitAI.Custom.WingTigerTest')
    AutoStopReadOnlyPlayer=$true
    ExpectedTracePatterns=@('(?m)^WingTigerTest Tests Passed: [1-9][0-9]+\r?$','(?m)^WingTigerTest Tests Failed: 0\r?$','(?m)^WingTigerTest Native Transitions Complete: 1\r?$')
    SuccessSummary='翅虎原生烟雾/受身、蓝红阵营、有效帧、致死优先及原死亡结算'
    AsyncBehaviorTimeoutSeconds=90
    TimeoutSeconds=$TimeoutSeconds
    SkipCompile=$SkipCompile
}
node (Join-Path (Split-Path -Parent $PSScriptRoot) 'tools/check-bom.js') --file 'scripts/类定义/org/flashNight/arki/unit/UnitAI/Custom/WingTigerController.as' --file 'scripts/逻辑/单位函数/单位函数_lsy_敌人模板迁移.as'
if($LASTEXITCODE -ne 0){throw 'WingTiger production source BOM check failed.'}
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') @focusedRun
