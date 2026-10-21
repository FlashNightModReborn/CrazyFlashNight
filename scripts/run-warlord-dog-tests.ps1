[CmdletBinding()]
param([ValidateRange(1,3600)][int]$TimeoutSeconds=300,[switch]$SkipCompile,[switch]$Capture)
$template='scripts/test-runners/warlord-dog/TestLoader.as.template'
if($Capture){
    $root=Split-Path -Parent $PSScriptRoot
    $template='tmp/warlord-dog-tests/TestLoader.capture.as.template'
    $body=[IO.File]::ReadAllText((Join-Path $root 'scripts/test-runners/warlord-dog/TestLoader.as.template'))
    [IO.File]::WriteAllText((Join-Path $root $template),"_root.ironGuardCapture=true;`n"+$body,[Text.UTF8Encoding]::new($true))
}
$focusedRun=@{
    DomainId='warlord-dog'
    CompileTargetRelativePath='scripts/WarlordDogHost/WarlordDogHost.xfl'
    CompileSwfRelativePath='scripts/WarlordDogHost.swf'
    TemplateRelativePath=$template
    SuiteRelativePaths=@('scripts/类定义/org/flashNight/arki/unit/UnitAI/Custom/WarlordDogTest.as')
    SuiteFqns=@('org.flashNight.arki.unit.UnitAI.Custom.WarlordDogTest')
    AdditionalAsRelativePaths=@('scripts/类定义/org/flashNight/arki/unit/UnitAI/Custom/WarlordDogController.as','scripts/逻辑/单位函数/单位函数_lsy_敌人模板迁移.as')
    ExpectedTracePatterns=@('(?m)^WarlordDogTest Tests Passed: [1-9][0-9]*\r?$',
        '(?m)^WarlordDogTest Tests Failed: 0\r?$',
        '(?m)^WarlordDogTest Native Poses: 9\r?$')
    SuccessSummary='Native iron guard dog, owned energy shield, synchronous toughness, discharge, recharge, focus fire and lifecycle'
    AsyncBehaviorTimeoutSeconds=$TimeoutSeconds
    TimeoutSeconds=$TimeoutSeconds
    SkipCompile=$SkipCompile
}
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') @focusedRun
