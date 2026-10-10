[CmdletBinding()]
param([ValidateRange(1,3600)][int]$TimeoutSeconds=600,[switch]$SkipCompile)
$ErrorActionPreference='Stop'
$focusedRun=@{
    DomainId='buff-hotpath'
    TemplateRelativePath='scripts\test-runners\buff-hotpath\TestLoader.as.template'
    SuiteRelativePaths=@('scripts\类定义\org\flashNight\arki\component\Buff\test\BuffManagerHotPathTest.as')
    SuiteFqns=@('org.flashNight.arki.component.Buff.test.BuffManagerHotPathTest')
    AdditionalAsRelativePaths=@(
        'scripts\类定义\org\flashNight\arki\component\Buff\BuffManager.as'
        'scripts\类定义\org\flashNight\arki\component\Buff\test\BuffManagerLegacyUpdateFixture.as'
    )
    ExpectedTracePatterns=@(
        '(?m)^BuffManagerHotPathTest Tests Passed: [1-9][0-9]*\r?$'
        '(?m)^BuffManagerHotPathTest Tests Failed: 0\r?$'
    )
    SuccessSummary='Actual Buff manager event/timer parity and alternating update A/B'
    TimeoutSeconds=$TimeoutSeconds
    SkipCompile=$SkipCompile
}
& (Join-Path $PSScriptRoot 'test-runners\run-focused-testloader.ps1') @focusedRun
