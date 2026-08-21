[CmdletBinding()]
param(
    [ValidateRange(1, 3600)]
    [int]$TimeoutSeconds = 240,
    [switch]$SkipCompile
)

$ErrorActionPreference = 'Stop'
$commonRunner = Join-Path $PSScriptRoot 'test-runners\run-focused-testloader.ps1'
$focusedRun = @{
    DomainId = 'player-manual-input'
    TemplateRelativePath = 'scripts\test-runners\player-manual-input\TestLoader.as.template'
    SuiteRelativePaths = @(
        'scripts\类定义\org\flashNight\arki\unit\Action\Shoot\LongGunSubWeaponCoreTest.as'
        'scripts\类定义\org\flashNight\arki\unit\Action\Skill\ManualCooldownServiceTest.as'
        'scripts\类定义\org\flashNight\arki\unit\Action\Skill\DrugInputServiceTest.as'
    )
    SuiteFqns = @(
        'org.flashNight.arki.unit.Action.Shoot.LongGunSubWeaponCoreTest'
        'org.flashNight.arki.unit.Action.Skill.ManualCooldownServiceTest'
        'org.flashNight.arki.unit.Action.Skill.DrugInputServiceTest'
    )
    ExpectedTracePatterns = @(
        '(?m)^--- LongGunSubWeaponCoreTest: 474/474 passed, 0 failed ---\r?$'
        '(?m)^--- ManualCooldownServiceTest: 50/50 passed, 0 failed ---\r?$'
        '(?m)^--- DrugInputServiceTest: 19/19 passed, 0 failed ---\r?$'
    )
    SuccessSummary = 'LongGun 474/474, ManualCooldown 50/50, DrugInput 19/19'
    TimeoutSeconds = $TimeoutSeconds
    SkipCompile = $SkipCompile
}
& $commonRunner @focusedRun
