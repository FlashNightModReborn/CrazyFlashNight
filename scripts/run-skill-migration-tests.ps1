[CmdletBinding()]
param(
    [ValidateRange(1, 3600)]
    [int]$TimeoutSeconds = 240,
    [switch]$SkipCompile
)

$ErrorActionPreference = 'Stop'
$commonRunner = Join-Path $PSScriptRoot 'test-runners\run-focused-testloader.ps1'
$focusedRun = @{
    DomainId = 'skill-migration'
    TemplateRelativePath = 'scripts\test-runners\skill-migration\TestLoader.as.template'
    SuiteRelativePaths = @(
        'scripts\类定义\org\flashNight\arki\skill\SkillMigrationTestSuite.as'
    )
    SuiteFqns = @(
        'org.flashNight.arki.skill.SkillMigrationTestSuite'
    )
    AdditionalAsRelativePaths = @(
        'scripts\类定义\org\flashNight\arki\skill\SkillLoadoutServiceTest.as'
        'scripts\类定义\org\flashNight\arki\skill\SkillPanelServiceTest.as'
    )
    ExpectedTracePatterns = @(
        '(?m)^=== SkillMigrationTestSuite START ===\r?$'
        '(?m)^SkillLoadoutServiceTest Tests Passed: [1-9][0-9]*\r?$'
        '(?m)^SkillLoadoutServiceTest Tests Failed: 0\r?$'
        '(?m)^SkillPanelServiceTest Tests Passed: [1-9][0-9]*\r?$'
        '(?m)^SkillPanelServiceTest Tests Failed: 0\r?$'
        '(?m)^=== SkillMigrationTestSuite END ===\r?$'
    )
    SuccessSummary = 'Skill loadout and panel assertions completed; counts in fresh trace'
    TimeoutSeconds = $TimeoutSeconds
    SkipCompile = $SkipCompile
}
& $commonRunner @focusedRun
