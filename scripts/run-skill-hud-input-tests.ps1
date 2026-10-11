[CmdletBinding()]
param([ValidateRange(1,3600)][int]$TimeoutSeconds=600,[switch]$SkipCompile)
$ErrorActionPreference='Stop'
$focusedRun=@{
    DomainId='skill-hud-input'
    TemplateRelativePath='scripts\test-runners\skill-hud-input\TestLoader.as.template'
    SuiteRelativePaths=@('scripts\类定义\org\flashNight\arki\skill\SkillHudInputTest.as')
    SuiteFqns=@('org.flashNight.arki.skill.SkillHudInputTest')
    AdditionalAsRelativePaths=@('scripts\类定义\org\flashNight\arki\skill\SkillLoadoutService.as')
    ExpectedTracePatterns=@(
        '(?m)^SkillHudInputTest Tests Passed: [1-9][0-9]*\r?$'
        '(?m)^SkillHudInputTest Tests Failed: 0\r?$'
    )
    SuccessSummary='Display cache hit/miss parity, direct legacy edits and no authority writes'
    TimeoutSeconds=$TimeoutSeconds
    SkipCompile=$SkipCompile
}
& (Join-Path $PSScriptRoot 'test-runners\run-focused-testloader.ps1') @focusedRun
