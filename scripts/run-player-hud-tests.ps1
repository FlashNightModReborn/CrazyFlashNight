[CmdletBinding()]
param([ValidateRange(1,3600)][int]$TimeoutSeconds=600,[switch]$SkipCompile)
$ErrorActionPreference='Stop'
$focusedRun=@{
    DomainId='player-hud'
    TemplateRelativePath='scripts\test-runners\player-hud\TestLoader.as.template'
    SuiteRelativePaths=@('scripts\类定义\org\flashNight\arki\hud\PlayerHudServiceTest.as','scripts\类定义\org\flashNight\arki\hud\PlayerHudHotPathTest.as')
    SuiteFqns=@('org.flashNight.arki.hud.PlayerHudServiceTest','org.flashNight.arki.hud.PlayerHudHotPathTest')
    AdditionalAsRelativePaths=@(
        'scripts\类定义\org\flashNight\arki\hud\PlayerHudService.as'
        'scripts\类定义\org\flashNight\arki\skill\SkillResourceService.as'
        'scripts\类定义\org\flashNight\arki\hud\PlayerHudShieldProjection.as'
        'scripts\类定义\org\flashNight\arki\hud\PlayerHudBuffProjection.as'
        'scripts\类定义\org\flashNight\arki\item\DrugHudMutationService.as'
        'scripts\类定义\org\flashNight\arki\unit\Action\Skill\ManualCooldownService.as'
    )
    ExpectedTracePatterns=@(
        '(?m)^--- PlayerHudServiceTest: ([1-9][0-9]*)/\1 passed, 0 failed ---\r?$'
        '(?m)^PlayerHudHotPathTest Tests Passed: [1-9][0-9]*\r?$'
        '(?m)^PlayerHudHotPathTest Tests Failed: 0\r?$'
    )
    SuccessSummary='PlayerHud state/wire, cooldown batching, immutable resync and hot-path A/B'
    TimeoutSeconds=$TimeoutSeconds
    SkipCompile=$SkipCompile
}
& (Join-Path $PSScriptRoot 'test-runners\run-focused-testloader.ps1') @focusedRun
