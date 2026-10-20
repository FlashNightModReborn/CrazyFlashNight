[CmdletBinding()]
param([ValidateRange(1,3600)][int]$TimeoutSeconds=360,[switch]$SkipCompile)
$ErrorActionPreference='Stop'
$focusedRun=@{
    DomainId='weapon-ammo-data'
    TemplateRelativePath='scripts\test-runners\weapon-ammo-data\TestLoader.as.template'
    SuiteRelativePaths=@('scripts\类定义\org\flashNight\arki\unit\Action\Shoot\WeaponAmmoDataTest.as')
    SuiteFqns=@('org.flashNight.arki.unit.Action.Shoot.WeaponAmmoDataTest')
    ExpectedTracePatterns=@('(?m)^--- WeaponAmmoDataTest: (?<ammo>[1-9][0-9]*)/\k<ammo> passed, 0 failed ---\r?$')
    SuccessSummary='Real weapon XML, mod registry, capacity rounding and typed overload eligibility'
    TimeoutSeconds=$TimeoutSeconds
    SkipCompile=$SkipCompile
}
& (Join-Path $PSScriptRoot 'test-runners\run-focused-testloader.ps1') @focusedRun
