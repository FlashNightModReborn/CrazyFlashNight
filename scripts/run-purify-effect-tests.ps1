
[CmdletBinding()]
param([ValidateRange(1,3600)][int]$TimeoutSeconds=240,[switch]$SkipCompile)
$ErrorActionPreference='Stop'
$focusedRun=@{
    DomainId='purify-effect'
    TemplateRelativePath='scripts\test-runners\purify-effect\TestLoader.as.template'
    SuiteRelativePaths=@('scripts\类定义\org\flashNight\arki\item\drug\PurifyEffectTest.as')
    SuiteFqns=@('org.flashNight.arki.item.drug.PurifyEffectTest')
    AdditionalAsRelativePaths=@(
        'scripts\类定义\org\flashNight\arki\item\drug\DrugContext.as'
        'scripts\类定义\org\flashNight\arki\item\drug\DrugEffectRegistry.as'
        'scripts\类定义\org\flashNight\arki\item\drug\effects\PurifyEffect.as'
        'scripts\类定义\org\flashNight\arki\item\drug\effects\BuffEffect.as'
        'scripts\类定义\org\flashNight\arki\item\drug\effects\BuffDomainEffect.as'
        'scripts\类定义\org\flashNight\arki\item\drug\effects\PlayEffectEffect.as'
        'scripts\类定义\org\flashNight\arki\component\Buff\BuffManager.as'
        'scripts\类定义\org\flashNight\arki\component\Buff\Effect\ElderBeamVulnerability.as'
        'scripts\类定义\org\flashNight\arki\component\Buff\Effect\FireControlVulnerability.as'
        'scripts\类定义\org\flashNight\arki\component\Buff\Effect\ToughnessVulnerabilityController.as'
        'scripts\类定义\org\flashNight\arki\component\Buff\Effect\GrayGooShotgunEtch.as'
        'scripts\类定义\org\flashNight\arki\hud\PlayerHudBuffProjection.as'
        'scripts\类定义\org\flashNight\arki\unit\UnitComponent\Targetcache\TargetCacheManager.as'
        'scripts\类定义\org\flashNight\arki\unit\UnitComponent\Targetcache\TargetCacheUpdater.as'
        'scripts\类定义\org\flashNight\arki\unit\UnitComponent\Targetcache\FactionManager.as'
        'scripts\逻辑\单位函数\单位函数_fs_装备生命周期配置.as'
        'scripts\引擎\引擎_fs_战技路由.as'
        'scripts\逻辑\单位函数\单位函数_lsy_主角技能.as'
        'scripts\逻辑\单位函数\单位函数_雾人_aka_fs_主动战技.as'
        'scripts\逻辑\装备函数\毒液蜘蛛侠.as'
        'scripts\逻辑\装备函数\剑圣头部装甲.as'
        'scripts\逻辑\战斗系统\战斗系统_fs_lsy_aka_重写子弹生成逻辑.as'
        'scripts\逻辑\单位函数\单位函数_fs_佣兵加血加蓝.as'
    )
    ExpectedTracePatterns=@(
        '(?m)^PurifyEffectTest Tests Passed: [1-9][0-9]*\r?$'
        '(?m)^PurifyEffectTest Tests Failed: 0\r?$'
    )
    SuccessSummary='#281 真实药剂 XML、定时 debuff 净化、Buff 提交与重入、装备命中、友军快照、麻痹抗性及 HUD/单体特效'
    TimeoutSeconds=$TimeoutSeconds
    AsyncBehaviorTimeoutSeconds=30
    SkipCompile=$SkipCompile
}
& (Join-Path $PSScriptRoot 'test-runners\run-focused-testloader.ps1') @focusedRun
