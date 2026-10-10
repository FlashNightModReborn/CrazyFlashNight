[CmdletBinding()]
param([ValidateRange(1,3600)][int]$TimeoutSeconds=600,[switch]$SkipCompile)
$ErrorActionPreference='Stop'
$focusedRun=@{
    DomainId='player-hud-snapshot'
    TemplateRelativePath='scripts\test-runners\player-hud-snapshot\TestLoader.as.template'
    SuiteRelativePaths=@('scripts\类定义\org\flashNight\arki\hud\PlayerHudSnapshotTest.as')
    SuiteFqns=@('org.flashNight.arki.hud.PlayerHudSnapshotTest')
    AdditionalAsRelativePaths=@(
        'scripts\类定义\org\flashNight\arki\hud\PlayerHudService.as'
        'scripts\类定义\org\flashNight\arki\hud\PlayerHudShieldProjection.as'
        'scripts\类定义\org\flashNight\arki\hud\PlayerHudBuffProjection.as'
        'scripts\类定义\org\flashNight\arki\hud\PlayerHudSnapshotLegacyFixture.as'
        'scripts\类定义\org\flashNight\arki\hud\PlayerHudShieldProjectionLegacyFixture.as'
        'scripts\类定义\org\flashNight\arki\hud\PlayerHudBuffProjectionLegacyFixture.as'
    )
    ExpectedTracePatterns=@(
        '(?m)^PlayerHudSnapshotTest Tests Passed: [1-9][0-9]*\r?$'
        '(?m)^PlayerHudSnapshotTest Tests Failed: 0\r?$'
    )
    SuccessSummary='HUD scalar/wire parity, immutable snapshots, live timer and grouped A/B'
    TimeoutSeconds=$TimeoutSeconds
    SkipCompile=$SkipCompile
}
& (Join-Path $PSScriptRoot 'test-runners\run-focused-testloader.ps1') @focusedRun
