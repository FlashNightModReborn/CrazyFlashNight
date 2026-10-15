[CmdletBinding()]
param([ValidateRange(1,3600)][int]$TimeoutSeconds=420,[switch]$SkipCompile)
$ErrorActionPreference='Stop'
$repoDirectory=Split-Path -Parent $PSScriptRoot
& python -X utf8 (Join-Path $repoDirectory 'tools/rock-queen-assets/build-test-host.py') --check
if($LASTEXITCODE -ne 0) { throw 'Regenerate RockQueenNativeHost before running the native fixture.' }
$focusedRun=@{
    DomainId='rock-queen'
    CompileTargetRelativePath='scripts/RockQueenNativeHost/RockQueenNativeHost.xfl'
    CompileSwfRelativePath='scripts/RockQueenNativeHost.swf'
    TemplateRelativePath='scripts/test-runners/rock-queen/TestLoader.as.template'
    SuiteRelativePaths=@('scripts/类定义/org/flashNight/arki/unit/Action/Skill/RockQueenBattleSkillTest.as')
    SuiteFqns=@('org.flashNight.arki.unit.Action.Skill.RockQueenBattleSkillTest')
    AdditionalAsRelativePaths=@('scripts/类定义/org/flashNight/arki/unit/Action/Skill/RockQueenBattleSkill.as','scripts/逻辑/单位函数/单位函数_雾人_aka_fs_主动战技.as','scripts/逻辑/装备函数/主唱光剑.as','scripts/逻辑/单位函数/单位函数_fs_佣兵加血加蓝.as','scripts/逻辑/功能函数/功能函数_fs_状态机用函数.as')
    ExpectedTracePatterns=@('(?m)^RockQueenBattleSkillTest Case: 30\r?$','(?m)^RockQueenBattleSkillTest Tests Passed: [1-9][0-9]+\r?$','(?m)^RockQueenBattleSkillTest Tests Failed: 0\r?$')
    SuccessSummary='摇滚女皇真实XML、14段原生动作、F释放、可换装武器、命中区域、弹药提交与中断回收'
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
