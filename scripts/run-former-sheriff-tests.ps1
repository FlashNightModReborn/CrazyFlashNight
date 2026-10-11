[CmdletBinding()]
param([ValidateRange(1,3600)][int]$TimeoutSeconds=600,[switch]$SkipCompile,[switch]$Capture)
$template='scripts/test-runners/former-sheriff/TestLoader.as.template'
if($Capture) {
    $root=Split-Path -Parent $PSScriptRoot
    $template='tmp/former-sheriff-phase-one/TestLoader.capture.as.template'
    $capturePath=Join-Path $root $template
    [IO.Directory]::CreateDirectory((Split-Path -Parent $capturePath)) | Out-Null
    $text=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'test-runners/former-sheriff/TestLoader.as.template'))
    [IO.File]::WriteAllText($capturePath,"_root.formerSheriffCapture=true;`n"+$text,[Text.UTF8Encoding]::new($true))
}
$focusedRun=@{
    DomainId='former-sheriff'
    CompileTargetRelativePath='scripts/FormerSheriffNativeHost/FormerSheriffNativeHost.xfl'
    CompileSwfRelativePath='scripts/FormerSheriffNativeHost.swf'
    TemplateRelativePath=$template
    SuiteRelativePaths=@('scripts/类定义/org/flashNight/arki/unit/UnitAI/Custom/FormerSheriffTest.as')
    SuiteFqns=@('org.flashNight.arki.unit.UnitAI.Custom.FormerSheriffTest')
    AdditionalAsRelativePaths=@('scripts/类定义/org/flashNight/arki/unit/UnitAI/Custom/FormerSheriffController.as','scripts/类定义/org/flashNight/arki/unit/Action/Skill/SheriffShieldRush.as','scripts/逻辑/单位函数/单位函数_lsy_敌人模板迁移.as')
    ExpectedTracePatterns=@('(?m)^FormerSheriffTest Tests Passed: [1-9][0-9]+\r?$','(?m)^FormerSheriffTest Tests Failed: 0\r?$','(?m)^FormerSheriffTest Native Transition Complete: 1\r?$')
    SuccessSummary='Native custom NPC: weapon decisions, permanent opening buffs, hit reactions, NPC reload and protected first-life transition'
    AsyncBehaviorTimeoutSeconds=600
    TimeoutSeconds=$TimeoutSeconds
    SkipCompile=$SkipCompile
}
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') @focusedRun
