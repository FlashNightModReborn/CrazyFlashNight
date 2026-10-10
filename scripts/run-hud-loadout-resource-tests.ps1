[CmdletBinding()]
param([ValidateRange(1,3600)][int]$TimeoutSeconds=600,[switch]$SkipCompile)
$ErrorActionPreference='Stop'
$focusedRun=@{
    DomainId='hud-loadout-resources'
    TemplateRelativePath='scripts\test-runners\hud-loadout-resources\TestLoader.as.template'
    SuiteRelativePaths=@('scripts\类定义\org\flashNight\arki\hud\PlayerHudLoadoutResourceTest.as')
    SuiteFqns=@('org.flashNight.arki.hud.PlayerHudLoadoutResourceTest')
    AdditionalAsRelativePaths=@(
        'scripts\类定义\org\flashNight\arki\hud\PlayerHudService.as'
        'scripts\类定义\org\flashNight\arki\skill\SkillResourceService.as'
        'scripts\类定义\org\flashNight\arki\skill\SkillResourceSnapshotLegacyFixture.as'
        'scripts\类定义\org\flashNight\arki\hud\PlayerHudSnapshotLegacyFixture.as'
    )
    ExpectedTracePatterns=@(
        '(?m)^PlayerHudLoadoutResourceTest Tests Passed: [1-9][0-9]*\r?$'
        '(?m)^PlayerHudLoadoutResourceTest Tests Failed: 0\r?$'
    )
    SuccessSummary='Loadout/resource wire parity, item revision gates, no cross-frame stock cache'
    TimeoutSeconds=$TimeoutSeconds
    SkipCompile=$SkipCompile
}
& (Join-Path $PSScriptRoot 'test-runners\run-focused-testloader.ps1') @focusedRun
