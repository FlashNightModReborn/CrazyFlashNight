[CmdletBinding()]
param([ValidateRange(1,3600)][int]$TimeoutSeconds=600,[switch]$SkipCompile,[switch]$Capture,[switch]$CaptureLift)
$template='scripts/test-runners/phoenix-phase/TestLoader.as.template'
if($Capture -or $CaptureLift) {
    $taskRoot=Split-Path -Parent $PSScriptRoot
    $template='tmp/phoenix-phase-20261019/TestLoader.capture.as.template'
    $path=Join-Path $taskRoot $template
    [IO.Directory]::CreateDirectory((Split-Path -Parent $path)) | Out-Null
    $source=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'test-runners/phoenix-phase/TestLoader.as.template'))
    $taskCapturePrefix=''
    if($Capture){$taskCapturePrefix+="_root.phoenixPhaseCapture=true;`n"}
    if($CaptureLift){$taskCapturePrefix+="_root.phoenixLiftCapture=true;`n"}
    [IO.File]::WriteAllText($path,$taskCapturePrefix+$source,[Text.UTF8Encoding]::new($true))
}
$focusedRun=@{
    DomainId='phoenix-phase'
    CompileTargetRelativePath='scripts/PhoenixPhaseHost/PhoenixPhaseHost.xfl'
    CompileSwfRelativePath='scripts/PhoenixPhaseHost.swf'
    TemplateRelativePath=$template
    SuiteRelativePaths=@('scripts/类定义/org/flashNight/arki/unit/UnitAI/Custom/PhoenixPhaseTest.as')
    SuiteFqns=@('org.flashNight.arki.unit.UnitAI.Custom.PhoenixPhaseTest')
    AdditionalAsRelativePaths=@('scripts/类定义/org/flashNight/arki/unit/UnitAI/Custom/PhoenixPhaseController.as','scripts/逻辑/单位函数/单位函数_lsy_敌人模板迁移.as')
    ExpectedTracePatterns=@('(?m)^PhoenixPhaseTest Tests Passed: [1-9][0-9]+\r?$','(?m)^PhoenixPhaseTest Tests Failed: 0\r?$','(?m)^PhoenixPhaseTest Complete Transitions: 3\r?$',
        '(?m)^PhoenixPhaseTest Behavior: phase-one real chase both directions, depth, attacks, finish;[^\r\n]*\r?$',
        '(?m)^PhoenixPhaseTest Behavior: phase-two real chase both directions, depth, attacks, finish;[^\r\n]*\r?$',
        '(?m)^PhoenixPhaseTest Behavior: phase-three real chase both directions, depth, attacks, finish;[^\r\n]*\r?$',
        '(?m)^PhoenixPhaseTest Behavior: nirvana real chase both directions, depth, attacks, finish;[^\r\n]*\r?$')
    SuccessSummary='Real Phoenix actor: protected depleted lives, authored transitions, local collision, fused Nirvana, bidirectional real enemy chase/attacks and one final settlement'
    AsyncBehaviorTimeoutSeconds=$TimeoutSeconds
    TimeoutSeconds=$TimeoutSeconds
    SkipCompile=$SkipCompile
}
if($CaptureLift){$focusedRun.ExpectedTracePatterns+='(?m)^PhoenixPhaseTest Motion Captures: 28\r?$'}
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') @focusedRun
