[CmdletBinding()]
param([ValidateRange(1,3600)][int]$TimeoutSeconds=360,[switch]$SkipCompile)
$ErrorActionPreference='Stop'
chcp.com 65001 | Out-Null
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') `
    -DomainId 'cf6-type61' `
    -TemplateRelativePath 'scripts/test-runners/cf6-type61/TestLoader.as.template' `
    -SuiteRelativePaths @('scripts/类定义/org/flashNight/arki/scene/Cf6Type61ServiceTest.as') `
    -SuiteFqns @('org.flashNight.arki.scene.Cf6Type61ServiceTest') `
    -AdditionalAsRelativePaths @('scripts/类定义/org/flashNight/arki/scene/Cf6Type61Service.as','scripts/类定义/org/flashNight/arki/scene/Cf6ActorLoadout.as','scripts/类定义/org/flashNight/arki/scene/Cf6Type61Fixture.as','scripts/类定义/org/flashNight/arki/scene/Cf6EconomyRules.as','scripts/类定义/org/flashNight/arki/item/ChoiceRewardService.as','scripts/类定义/org/flashNight/arki/item/RewardStashService.as','scripts/类定义/org/flashNight/neur/Server/SaveManager.as','scripts/引擎/引擎_lsy_等级与经验值.as','scripts/逻辑/单位函数/单位函数_lsy_敌人模板迁移.as','scripts/展现/UI交互/UI交互_lsy_物品栏UI.as') `
    -ExpectedTracePatterns @('(?m)^Cf6Type61ServiceTest Tests Passed: 103\r?$','(?m)^Cf6Type61ServiceTest Tests Failed: 0\r?$') `
    -SuccessSummary '103/103 Type61 assertions; isolated nonce storage, no player-save or play-feel claim' `
    -TimeoutSeconds $TimeoutSeconds -SkipCompile:$SkipCompile
