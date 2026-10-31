[CmdletBinding()]
param([ValidateRange(1,3600)][int]$TimeoutSeconds=1200,[switch]$SkipCompile)
$ErrorActionPreference='Stop'
$repoDirectory=Split-Path -Parent $PSScriptRoot
& python -X utf8 (Join-Path $repoDirectory 'tools/huofeng-set-assets/build_test_host.py') --check
if($LASTEXITCODE -ne 0) { throw 'Regenerate HuofengNativeHost before running the native fixture.' }
$focusedRun=@{
    DomainId='huofeng-native'
    CompileTargetRelativePath='scripts/HuofengNativeHost/HuofengNativeHost.xfl'
    CompileSwfRelativePath='scripts/HuofengNativeHost.swf'
    TemplateRelativePath='scripts/test-runners/huofeng-native/TestLoader.as.template'
    SuiteRelativePaths=@('scripts/类定义/org/flashNight/arki/unit/Action/Huofeng/HuofengNativeTest.as','scripts/类定义/org/flashNight/arki/unit/Action/Huofeng/HuofengContractTest.as','scripts/类定义/org/flashNight/arki/item/CharacterBuildProductionLifecycleTest.as')
    SuiteFqns=@('org.flashNight.arki.unit.Action.Huofeng.HuofengNativeTest','org.flashNight.arki.unit.Action.Huofeng.HuofengContractTest','org.flashNight.arki.item.CharacterBuildProductionLifecycleTest')
    AdditionalAsRelativePaths=@('scripts/类定义/org/flashNight/arki/unit/Action/Huofeng/HuofengPressureTest.as','scripts/类定义/org/flashNight/arki/unit/Action/Huofeng/HuofengPresentationTest.as','scripts/逻辑/装备函数/火凤套装.as','scripts/类定义/org/flashNight/arki/unit/Action/Skill/RockQueenBattleSkill.as','scripts/逻辑/单位函数/单位函数_雾人_aka_fs_主动战技.as','scripts/逻辑/装备函数/主唱光剑.as','scripts/逻辑/单位函数/单位函数_fs_佣兵加血加蓝.as','scripts/逻辑/功能函数/功能函数_fs_状态机用函数.as')
    ExpectedTracePatterns=@('(?m)^\[HuofengContractTest\] [1-9][0-9]+ passed, 0 failed\r?$','(?m)^CharacterBuildProductionLifecycleTest Tests Failed: 0\r?$','(?m)^HuofengNativeTest Case: 32\r?$','(?m)^HuofengNativeTest Tests Passed: [1-9][0-9]+\r?$','(?m)^HuofengNativeTest Tests Failed: 0\r?$')
    SuccessSummary='火凤真实装备XML、原生动作、R9长发、左右朝向、AABB伤害去重与动作中断'
    AsyncBehaviorTimeoutSeconds=420
    TimeoutSeconds=$TimeoutSeconds
    SkipCompile=$SkipCompile
}
# things0 的原生共享库 URL 相对宿主 SWF。TestLoader 在 scripts 下，
# 为它镜像这一项既有依赖；不改生产 SWF 或库内导入 URL。
$sharedSource=Join-Path $repoDirectory 'flashswf/arts/新版人物文字信息.swf'
$sharedTarget=Join-Path $PSScriptRoot 'flashswf/arts/新版人物文字信息.swf'
$sharedHash=(Get-FileHash -LiteralPath $sharedSource -Algorithm SHA256).Hash
$createdShared=$false
if(-not $SkipCompile) {
    if(Test-Path -LiteralPath $sharedTarget) {
        if((Get-FileHash -LiteralPath $sharedTarget -Algorithm SHA256).Hash -ne $sharedHash) {
            throw 'Test-relative shared library differs from production; preserve it and resolve the conflict.'
        }
    } else {
        [void][IO.Directory]::CreateDirectory((Split-Path -Parent $sharedTarget))
        Copy-Item -LiteralPath $sharedSource -Destination $sharedTarget
        $createdShared=$true
    }
}
try {
    & (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') @focusedRun
} finally {
    if($createdShared -and -not (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'compile_state_uncertain.marker')) -and
            -not (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'testloader_scratch_inflight.marker')) -and
            (Get-FileHash -LiteralPath $sharedTarget -Algorithm SHA256).Hash -eq $sharedHash) {
        & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'compile_test.ps1') -StopTestPlayers
        if($LASTEXITCODE -eq 0) { Remove-Item -LiteralPath $sharedTarget }
    }
}
