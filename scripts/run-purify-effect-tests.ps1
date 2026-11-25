[CmdletBinding()]
param([ValidateRange(1,3600)][int]$TimeoutSeconds=240,[switch]$SkipCompile)
$ErrorActionPreference='Stop'
$focusedRun=@{
    DomainId='purify-effect'
    TemplateRelativePath='scripts\test-runners\purify-effect\TestLoader.as.template'
    SuiteRelativePaths=@('scripts\类定义\org\flashNight\arki\item\drug\PurifyEffectTest.as')
    SuiteFqns=@('org.flashNight.arki.item.drug.PurifyEffectTest')
    AdditionalAsRelativePaths=@(
        'scripts\类定义\org\flashNight\arki\item\drug\effects\PurifyEffect.as'
        'scripts\类定义\org\flashNight\arki\item\drug\effects\BuffEffect.as'
        'scripts\类定义\org\flashNight\arki\item\drug\effects\PlayEffectEffect.as'
        'scripts\类定义\org\flashNight\arki\component\Buff\BuffManager.as'
        'scripts\类定义\org\flashNight\arki\weather\WeatherSystem.as'
        'scripts\逻辑\关卡系统\关卡系统_lsy_add2map_加载背景.as'
    )
    ExpectedTracePatterns=@(
        '(?m)^PurifyEffectTest Tests Passed: [1-9][0-9]*\r?$'
        '(?m)^PurifyEffectTest Tests Failed: 0\r?$'
    )
    SuccessSummary='PurifyEffect terrain coefficient, debuff reduction/dispel, paralysis floor and group purify'
    TimeoutSeconds=$TimeoutSeconds
    SkipCompile=$SkipCompile
}
& (Join-Path $PSScriptRoot 'test-runners\run-focused-testloader.ps1') @focusedRun