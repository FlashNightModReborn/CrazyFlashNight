[CmdletBinding()]
param([ValidateRange(1, 3600)][int]$TimeoutSeconds = 240, [switch]$SkipCompile)
$ErrorActionPreference = 'Stop'
$focusedRun = @{
    DomainId = 'blood-sword'
    TemplateRelativePath = 'scripts\test-runners\blood-sword\TestLoader.as.template'
    SuiteRelativePaths = @('scripts\类定义\org\flashNight\arki\unit\UnitComponent\Dressup\EquipmentUtil\BloodSwordLifecycleTest.as')
    SuiteFqns = @('org.flashNight.arki.unit.UnitComponent.Dressup.EquipmentUtil.BloodSwordLifecycleTest')
    AdditionalAsRelativePaths = @('scripts\逻辑\装备函数\血色光剑天秤.as', 'scripts\逻辑\单位函数\单位函数_fs_装备生命周期配置.as', 'scripts\类定义\org\flashNight\arki\component\Effect\EffectSystem.as')
    ExpectedTracePatterns = @('(?m)^BloodSwordLifecycleTest Tests Passed: 84\r?$', '(?m)^BloodSwordLifecycleTest Tests Failed: 0\r?$')
    SuccessSummary = '84/84，真实血剑与血浪素材：原70项、44帧余波、短尾收散、完整变换、特效池、取消及世界卸载'
    TimeoutSeconds = $TimeoutSeconds
    SkipCompile = $SkipCompile
}
# things0的共享库按顶层SWF相对路径装载；给scripts中的TestLoader临时路径映射。
# CS6会缓存RSL文件句柄，故使用可独立删除的目录联接，不复制或改写生产SWF。
$assetSource = [System.IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $PSScriptRoot) 'flashswf'))
$assetAlias = Join-Path $PSScriptRoot 'flashswf'
$createdAlias = $false
try {
    if (Test-Path -LiteralPath $assetAlias) {
        $existingAlias = Get-Item -LiteralPath $assetAlias -Force
        if ($existingAlias.LinkType -ne 'Junction' -or ([string[]]$existingAlias.Target)[0] -ne $assetSource) {
            throw '测试素材映射路径已占用且不指向现役素材库，拒绝覆盖。'
        }
    } else {
        New-Item -ItemType Junction -Path $assetAlias -Target $assetSource | Out-Null
        $createdAlias = $true
    }
    & (Join-Path $PSScriptRoot 'test-runners\run-focused-testloader.ps1') @focusedRun
} finally {
    if ($createdAlias) {
        $ownedAlias = Get-Item -LiteralPath $assetAlias -Force
        if ($ownedAlias.LinkType -ne 'Junction' -or ([string[]]$ownedAlias.Target)[0] -ne $assetSource) {
            throw '测试素材映射在运行中变更，拒绝自动清理。'
        }
        # 仅删除本次建立的联接；不递归、不触碰目标目录。
        [System.IO.Directory]::Delete($assetAlias)
    }
}
