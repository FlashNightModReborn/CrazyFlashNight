[CmdletBinding()]
param([ValidateRange(1,3600)][int]$TimeoutSeconds=600,[switch]$SkipCompile)
$ErrorActionPreference='Stop'
$focusedRun=@{
    DomainId='buff-manager'
    TemplateRelativePath='scripts\test-runners\buff-manager\TestLoader.as.template'
    SuiteRelativePaths=@('scripts\类定义\org\flashNight\arki\component\Buff\test\BuffManagerTest.as')
    SuiteFqns=@('org.flashNight.arki.component.Buff.test.BuffManagerTest')
    AdditionalAsRelativePaths=@(
        'scripts\类定义\org\flashNight\arki\component\Buff\BuffManager.as'
        'scripts\类定义\org\flashNight\arki\component\Buff\test\BugfixRegressionTest.as'
        'scripts\类定义\org\flashNight\arki\component\Buff\test\PathBindingTest.as'
    )
    ExpectedTracePatterns=@(
        '(?m)^BuffManagerTest Tests Passed: [1-9][0-9]*\r?$'
        '(?m)^BuffManagerTest Tests Failed: 0\r?$'
        '(?m)^BuffManagerBugfix Tests Passed: [1-9][0-9]*\r?$'
        '(?m)^BuffManagerBugfix Tests Failed: 0\r?$'
        '(?m)^BuffManagerPathBinding Tests Passed: [1-9][0-9]*\r?$'
        '(?m)^BuffManagerPathBinding Tests Failed: 0\r?$'
    )
    SuccessSummary='Buff calculations, reentry/lifecycle regressions and path binding'
    TimeoutSeconds=$TimeoutSeconds
    SkipCompile=$SkipCompile
}
& (Join-Path $PSScriptRoot 'test-runners\run-focused-testloader.ps1') @focusedRun
