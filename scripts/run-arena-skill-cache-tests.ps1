[CmdletBinding()]
param(
    [ValidateRange(1, 3600)][int]$TimeoutSeconds = 240,
    [switch]$SkipCompile
)

$ErrorActionPreference = 'Stop'
$focusedRun = @{
    DomainId = 'arena-skill-cache'
    TemplateRelativePath = 'scripts\test-runners\arena-skill-cache\TestLoader.as.template'
    SuiteRelativePaths = @('scripts\类定义\org\flashNight\arki\merc\ArenaSkillCacheTest.as')
    SuiteFqns = @('org.flashNight.arki.merc.ArenaSkillCacheTest')
    AdditionalAsRelativePaths = @(
        'scripts\类定义\org\flashNight\arki\merc\ArenaSkillCache.as'
        'scripts\逻辑\单位函数\单位函数_fs_aka_玩家模板迁移.as'
    )
    ExpectedTracePatterns = @(
        '(?m)^ArenaSkillCacheTest Tests Passed: 21\r?$'
        '(?m)^ArenaSkillCacheTest Tests Failed: 0\r?$'
    )
    SuccessSummary = '斗兽标定技能冷/热缓存与逐单位冷却隔离 21/21'
    TimeoutSeconds = $TimeoutSeconds
    SkipCompile = $SkipCompile
}
& (Join-Path $PSScriptRoot 'test-runners\run-focused-testloader.ps1') @focusedRun
