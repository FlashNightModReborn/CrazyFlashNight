[CmdletBinding()]
param(
    [ValidateRange(1, 3600)]
    [int]$TimeoutSeconds = 240,
    [switch]$SkipCompile
)

$ErrorActionPreference = 'Stop'
$commonRunner = Join-Path $PSScriptRoot 'test-runners\run-focused-testloader.ps1'
$projectDir = Split-Path -Parent $PSScriptRoot
$drugIconSource = Get-Content -LiteralPath (
    Join-Path $projectDir 'scripts\类定义\org\flashNight\arki\item\itemIcon\DrugIcon.as'
) -Raw -Encoding UTF8
$mutationSource = Get-Content -LiteralPath (
    Join-Path $projectDir 'scripts\类定义\org\flashNight\arki\item\DrugHudMutationService.as'
) -Raw -Encoding UTF8
$dirtyIndex = $mutationSource.IndexOf('PlayerAssetTransaction.markDirtyRequired(root.存档系统)')
$moveIndex = $mutationSource.IndexOf('source.move(')
if ($drugIconSource.IndexOf('DrugHudMutationService.unequip(') -lt 0 -or
        $dirtyIndex -lt 0 -or $moveIndex -le $dirtyIndex) {
    throw 'DrugIcon and native HUD must share the dirty-before-move domain operation.'
}

$focusedRun = @{
    DomainId = 'player-manual-input'
    TemplateRelativePath = 'scripts\test-runners\player-manual-input\TestLoader.as.template'
    SuiteRelativePaths = @(
        'scripts\类定义\org\flashNight\arki\unit\Action\Shoot\LongGunSubWeaponCoreTest.as'
        'scripts\类定义\org\flashNight\arki\unit\Action\Skill\ManualCooldownServiceTest.as'
        'scripts\类定义\org\flashNight\arki\unit\Action\Skill\DrugInputServiceTest.as'
        'scripts\类定义\org\flashNight\arki\key\KeyManagerTest.as'
    )
    SuiteFqns = @(
        'org.flashNight.arki.unit.Action.Shoot.LongGunSubWeaponCoreTest'
        'org.flashNight.arki.unit.Action.Skill.ManualCooldownServiceTest'
        'org.flashNight.arki.unit.Action.Skill.DrugInputServiceTest'
        'org.flashNight.arki.key.KeyManagerTest'
    )
    ExpectedTracePatterns = @(
        '(?m)^--- LongGunSubWeaponCoreTest: 486/486 passed, 0 failed ---\r?$'
        '(?m)^--- ManualCooldownServiceTest: 57/57 passed, 0 failed ---\r?$'
        '(?m)^--- DrugInputServiceTest: 58/58 passed, 0 failed ---\r?$'
        '(?m)^--- KeyManagerMigrationTest: 14/14 passed, 0 failed ---\r?$'
    )
    SuccessSummary = 'LongGun 486/486, ManualCooldown 57/57, DrugInput 58/58, KeyManagerMigration 14/14'
    TimeoutSeconds = $TimeoutSeconds
    SkipCompile = $SkipCompile
}
& $commonRunner @focusedRun
