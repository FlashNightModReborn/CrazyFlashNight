[CmdletBinding()]
param(
    [ValidateRange(1, 3600)][int]$TimeoutSeconds = 300,
    [switch]$SkipCompile
)
$ErrorActionPreference = 'Stop'
$commonRunner = Join-Path $PSScriptRoot 'test-runners\run-focused-testloader.ps1'
$focusedRun = @{
    DomainId = 'npc-capsule-shop'
    TemplateRelativePath = 'scripts\test-runners\npc-capsule-shop\TestLoader.as.template'
    SuiteRelativePaths = @(
        'scripts\类定义\org\flashNight\arki\item\NpcShopPanelServiceTest.as',
        'scripts\类定义\org\flashNight\arki\item\NpcCapsuleShopServiceTest.as'
    )
    SuiteFqns = @('org.flashNight.arki.item.NpcShopPanelServiceTest', 'org.flashNight.arki.item.NpcCapsuleShopServiceTest')
    AdditionalAsRelativePaths = @(
        'scripts\逻辑系统分区\商店系统_兼容.as',
        'scripts\展现\UI交互\UI交互_lsy_物品栏UI.as',
        'scripts\类定义\org\flashNight\arki\item\NpcCapsuleShopService.as'
    )
    ExpectedTracePatterns = @(
        '(?m)^NpcShopPanelServiceTest Tests Passed: 108\r?$',
        '(?m)^NpcShopPanelServiceTest Tests Failed: 0\r?$',
        '(?m)^NpcCapsuleShopServiceTest Tests Passed: 66\r?$',
        '(?m)^NpcCapsuleShopServiceTest Tests Failed: 0\r?$'
    )
    SuccessSummary = 'NPC 108/108; capsule service 66/66 including production BaseItem binding, delayed binding and real MC retargeting'
    TimeoutSeconds = $TimeoutSeconds
    AsyncBehaviorTimeoutSeconds = 90
    SkipCompile = $SkipCompile
}
& $commonRunner @focusedRun
exit $LASTEXITCODE
