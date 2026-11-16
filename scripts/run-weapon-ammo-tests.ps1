[CmdletBinding()]
param([ValidateRange(1,3600)][int]$TimeoutSeconds=360,[switch]$SkipCompile)
$ErrorActionPreference='Stop'
$focusedRun=@{
    DomainId='weapon-ammo'
    TemplateRelativePath='scripts\test-runners\weapon-ammo\TestLoader.as.template'
    SuiteRelativePaths=@('scripts\类定义\org\flashNight\arki\unit\Action\Shoot\WeaponAmmoRuntimeTest.as')
    SuiteFqns=@('org.flashNight.arki.unit.Action.Shoot.WeaponAmmoRuntimeTest')
    AdditionalAsRelativePaths=@('scripts\类定义\org\flashNight\arki\unit\Action\Shoot\WeaponAmmoRuntime.as','scripts/类定义/org/flashNight/arki/unit/Action/Shoot/ReloadManager.as','scripts/类定义/org/flashNight/arki/unit/Action/Shoot/WeaponStateManager.as')
    ExpectedTracePatterns=@('(?m)^--- WeaponAmmoRuntimeTest: (?<ammo>[1-9][0-9]*)/\k<ammo> passed, 0 failed ---\r?$')
    SuccessSummary='Weapon ammo conservation, typed overload, reload interruption and serialization'
    TimeoutSeconds=$TimeoutSeconds
    SkipCompile=$SkipCompile
}
& (Join-Path $PSScriptRoot 'test-runners\run-focused-testloader.ps1') @focusedRun
