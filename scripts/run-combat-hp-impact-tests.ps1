[CmdletBinding()]
param(
    [ValidateRange(1, 3600)]
    [int]$TimeoutSeconds = 240,
    [switch]$SkipCompile
)

$ErrorActionPreference = 'Stop'
$commonRunner = Join-Path $PSScriptRoot 'test-runners\run-focused-testloader.ps1'
$repoRoot = Split-Path -Parent $PSScriptRoot
$bqpPath = Join-Path $repoRoot 'scripts\类定义\org\flashNight\arki\bullet\BulletComponent\Queue\BulletQueueProcessor.as'
$bqpSource = Get-Content -LiteralPath $bqpPath -Raw -Encoding UTF8
$damageCalculatorSource = Get-Content -LiteralPath (Join-Path $repoRoot 'scripts\类定义\org\flashNight\arki\component\Damage\DamageCalculator.as') -Raw -Encoding UTF8
$damageResultSource = Get-Content -LiteralPath (Join-Path $repoRoot 'scripts\类定义\org\flashNight\arki\component\Damage\DamageResult.as') -Raw -Encoding UTF8
$hitUpdaterSource = Get-Content -LiteralPath (Join-Path $repoRoot 'scripts\类定义\org\flashNight\arki\unit\UnitComponent\Updater\HitUpdater.as') -Raw -Encoding UTF8
$impactStateSource = Get-Content -LiteralPath (Join-Path $repoRoot 'scripts\类定义\org\flashNight\arki\unit\UnitComponent\Status\ImpactStateHandler.as') -Raw -Encoding UTF8
if ($bqpSource.IndexOf('DamageResult.hasActualHit(', [StringComparison]::Ordinal) -ge 0 `
        -or $damageCalculatorSource.IndexOf('DamageResult.isResolvedMiss(', [StringComparison]::Ordinal) -ge 0 `
        -or $hitUpdaterSource.IndexOf('DamageResult.isResolvedMiss(', [StringComparison]::Ordinal) -ge 0 `
        -or $impactStateSource.IndexOf('DamageResult.hasActualHit(', [StringComparison]::Ordinal) -ge 0) {
    throw 'Combat hot-path contract failed: resolved MISS classification must not add repeated DamageResult calls to normal hit settlement/updaters.'
}
if ($bqpSource.IndexOf('ctx.actualHit = actualHit;', [StringComparison]::Ordinal) -lt 0 `
        -or $bqpSource.IndexOf('fireLegacyHitHook && bullet.命中前伤害参数函数 != undefined', [StringComparison]::Ordinal) -lt 0) {
    throw 'Combat hot-path contract failed: settleHit must cache one classification and skip the transform helper for ordinary bullets.'
}
if ($bqpSource.IndexOf('ctx.actualHit || damageResult === DamageResult.NULL', [StringComparison]::Ordinal) -lt 0 `
        -or $bqpSource.IndexOf('flameActualHit || damageResult === DamageResult.NULL', [StringComparison]::Ordinal) -lt 0 `
        -or $bqpSource.IndexOf('_hitCtx.actualHit || settlementResult === DamageResult.NULL', [StringComparison]::Ordinal) -lt 0) {
    throw 'Combat NULL contract failed: actual-first short circuit must retain ray/flame/main geometric hit effects.'
}
if ($damageResultSource.IndexOf('_actualTerminal', [StringComparison]::Ordinal) -ge 0 `
        -or $damageCalculatorSource.IndexOf('_actualTerminal', [StringComparison]::Ordinal) -ge 0) {
    throw 'Combat hot-path contract failed: rare terminal bullets must not add a per-hit pooled-result reset slot.'
}
if ($bqpSource.IndexOf('fireMapHitHook(bullet);', [StringComparison]::Ordinal) -lt 0) {
    throw 'Combat static contract failed: map finalization must use fireMapHitHook.'
}

$mapHookAssets = @(
    'flashswf\arts\new\3XD的素材\LIBRARY\5武器特效和子弹\高爆子弹\Symbol 585.xml',
    'flashswf\arts\new\3XD的素材\LIBRARY\5武器特效和子弹\爆炸狙击子弹\Symbol 585.xml',
    'flashswf\arts\new\瓦巴杰克\LIBRARY\特效与子弹\伸手及月.xml',
    'flashswf\arts\new\瓦巴杰克\LIBRARY\特效与子弹\新电球.xml',
    'flashswf\arts\new\瓦巴杰克\LIBRARY\特效与子弹\电浆球.xml',
    'flashswf\arts\new\瓦巴杰克\LIBRARY\特效与子弹\蜘蛛王2.xml',
    'flashswf\arts\new\瓦巴杰克\LIBRARY\特效与子弹\蜘蛛网.xml',
    'flashswf\arts\原版素材库-子弹\LIBRARY\子弹-普通与穿刺组\次级穿刺子弹.xml'
)
foreach ($relativePath in $mapHookAssets) {
    $assetSource = Get-Content -LiteralPath (Join-Path $repoRoot $relativePath) -Raw -Encoding UTF8
    if ($assetSource.IndexOf('击中地图时触发函数', [StringComparison]::Ordinal) -lt 0) {
        throw "Combat static contract failed: explicit map hook missing from $relativePath"
    }
}
$angelAssetPath = Join-Path $repoRoot 'flashswf\arts\new\偷吃屑鱼坟头贡品\LIBRARY\天使虫.xml'
$angelAssetSource = Get-Content -LiteralPath $angelAssetPath -Raw -Encoding UTF8
$bulletCasesPath = Join-Path $repoRoot 'data\items\bullets_cases.xml'
[xml]$bulletCases = Get-Content -LiteralPath $bulletCasesPath -Raw -Encoding UTF8
$angelBullet = @(@($bulletCases.bullets.bullet) | Where-Object { $_.name -eq '天使虫' })
$hasAngelTerminalCapability = $angelBullet.Count -eq 1 `
    -and [string]$angelBullet[0].attribute.actualTerminal -eq 'true'
$hasLegacyAngelTargetHook = $angelAssetSource.IndexOf(
    'this.击中时触发函数',
    [StringComparison]::Ordinal
) -ge 0
$hasDuplicateAngelTimelineCapability = $angelAssetSource.IndexOf(
    '实际命中强制击杀',
    [StringComparison]::Ordinal
) -ge 0
if (!$hasAngelTerminalCapability -or $hasLegacyAngelTargetHook `
        -or $hasDuplicateAngelTimelineCapability) {
    throw 'Combat static contract failed: Angel terminal authority must live in bullets_cases only, without legacy or duplicate timeline hooks.'
}
$focusedRun = @{
    DomainId = 'combat-hp-impact'
    TemplateRelativePath = 'scripts\test-runners\combat-hp-impact\TestLoader.as.template'
    SuiteRelativePaths = @(
        'scripts\类定义\org\flashNight\arki\bullet\BulletComponent\Queue\ToughnessVulnerabilityPipelineTest.as'
    )
    SuiteFqns = @(
        'org.flashNight.arki.bullet.BulletComponent.Queue.ToughnessVulnerabilityPipelineTest'
    )
    ExpectedTracePatterns = @(
        '(?m)^=== ToughnessVulnerabilityPipelineTest result: passed=153 failed=0 ===\r?$'
    )
    SuccessSummary = 'ToughnessVulnerabilityPipelineTest 153/153 assertions'
    TimeoutSeconds = $TimeoutSeconds
    SkipCompile = $SkipCompile
}
& $commonRunner @focusedRun
