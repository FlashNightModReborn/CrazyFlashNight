[CmdletBinding()]
param([ValidateRange(1,3600)][int]$TimeoutSeconds=600,[switch]$SkipCompile,[switch]$Capture)
$ErrorActionPreference='Stop'
if($Capture -and -not $PSBoundParameters.ContainsKey('TimeoutSeconds')) {
    # Pixel trace capture is substantially slower than ordinary frame checks.
    $TimeoutSeconds=1800
}
$focusedRun=@{
    DomainId='sheriff-phase-two'
    CompileTargetRelativePath='scripts/SheriffPhaseTwoActionHost/SheriffPhaseTwoActionHost.xfl'
    CompileSwfRelativePath='scripts/SheriffPhaseTwoActionHost.swf'
    TemplateRelativePath='scripts/test-runners/sheriff-phase-two/TestLoader.as.template'
    SuiteRelativePaths=@('scripts/类定义/org/flashNight/arki/unit/UnitAI/Custom/SheriffPhaseTwoActionTest.as')
    SuiteFqns=@('org.flashNight.arki.unit.UnitAI.Custom.SheriffPhaseTwoActionTest')
    ExpectedTracePatterns=@('(?m)^SheriffPhaseTwoActionTest Tests Passed: [1-9][0-9]+\r?$',
      '(?m)^SheriffPhaseTwoActionTest Tests Failed: 0\r?$',
      '(?m)^SheriffPhaseTwoActionTest Native Actions Complete: 5\r?$')
    SuccessSummary='Native fixed phase-two actions: all frames, weapon draw/stow, light ports and shared endpoint pixels'
    AsyncBehaviorTimeoutSeconds=$TimeoutSeconds
    TimeoutSeconds=$TimeoutSeconds
    SkipCompile=$SkipCompile
}
if($Capture) {
    $repo=Split-Path -Parent $PSScriptRoot
    $template='tmp/former-sheriff-phase-two/TestLoader.capture.as.template'
    $body=[IO.File]::ReadAllText((Join-Path $repo $focusedRun.TemplateRelativePath))
    $body=$body.Replace('_root.phaseTwoCapture=false;','_root.phaseTwoCapture=true;')
    [IO.File]::WriteAllText((Join-Path $repo $template),$body,[Text.UTF8Encoding]::new($true))
    $focusedRun.TemplateRelativePath=$template
}
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') @focusedRun
