[CmdletBinding()]
param([ValidateRange(1,3600)][int]$TimeoutSeconds=600,[switch]$SkipCompile)
$ErrorActionPreference='Stop'
$focusedRun=@{
    DomainId='player-hud'
    TemplateRelativePath='scripts\test-runners\player-hud\TestLoader.as.template'
    SuiteRelativePaths=@('scripts\类定义\org\flashNight\arki\hud\PlayerHudServiceTest.as')
    SuiteFqns=@('org.flashNight.arki.hud.PlayerHudServiceTest')
    AdditionalAsRelativePaths=@(
        'scripts\类定义\org\flashNight\arki\hud\PlayerHudService.as'
        'scripts\类定义\org\flashNight\arki\hud\PlayerHudBuffProjection.as'
        'scripts\类定义\org\flashNight\arki\item\DrugHudMutationService.as'
    )
    ExpectedTracePatterns=@('(?m)^--- PlayerHudServiceTest: ([1-9][0-9]*)/\1 passed, 0 failed ---\r?$')
    SuccessSummary='PlayerHud state, wire, Buff ownership, drug mutation and real MovieClip generation'
    TimeoutSeconds=$TimeoutSeconds
    SkipCompile=$SkipCompile
}
& (Join-Path $PSScriptRoot 'test-runners\run-focused-testloader.ps1') @focusedRun
