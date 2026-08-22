[CmdletBinding()]
param(
    [ValidateRange(1, 3600)]
    [int]$TimeoutSeconds = 240,
    [switch]$SkipCompile
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$rootFacadePath = Join-Path $projectRoot 'scripts\引擎\引擎_鸡蛋_lsy_物品系统.as'

# 独立 XFL/SWF 没有稳定的 scripts/类定义 classpath；时间轴必须只依赖
# asLoader 注入的 _root 门面。这个静态门防止后续生产者再次把事务类版本
# 编进各自资产，形成无法加载或版本漂移。
$forbiddenAssetReferences = & git -C $projectRoot grep -n -E `
    'org\.flashNight\.arki\.item\.(PlayerAssetTransaction|ItemUtil)' -- `
    'flashswf/**/*.xml' 2>$null
$grepExitCode = $LASTEXITCODE
if ($grepExitCode -eq 0) {
    throw ("XFL 资产不得直接调用玩家物资类库；请改用 asLoader _root 门面：`n" +
        ($forbiddenAssetReferences -join "`n"))
}
if ($grepExitCode -ne 1) {
    throw "无法完成 XFL 玩家物资类库边界扫描，git grep exit=$grepExitCode"
}

$rootFacadeSource = Get-Content -LiteralPath $rootFacadePath -Raw -Encoding UTF8
$requiredRootFacadeFunctions = @(
    '开始玩家物资事务',
    '提交玩家物资事务',
    '回滚玩家物资事务',
    '记录玩家物资变化',
    '记录玩家货币变化',
    '玩家物品是否装备'
)
foreach ($facadeFunction in $requiredRootFacadeFunctions) {
    if ($rootFacadeSource -notmatch ('_root\.' + [regex]::Escape($facadeFunction) +
            '\s*=\s*function\s*\(')) {
        throw "asLoader 缺少玩家物资 XFL 门面函数: _root.$facadeFunction"
    }
}

$commonRunner = Join-Path $PSScriptRoot 'test-runners\run-focused-testloader.ps1'
$focusedRun = @{
    DomainId = 'player-asset-transaction'
    TemplateRelativePath = 'scripts\test-runners\player-asset-transaction\TestLoader.as.template'
    SuiteRelativePaths = @(
        'scripts\类定义\org\flashNight\arki\item\PlayerAssetTransactionTest.as'
    )
    SuiteFqns = @(
        'org.flashNight.arki.item.PlayerAssetTransactionTest'
    )
    ExpectedTracePatterns = @(
        '(?m)^PlayerAssetTransactionTest Tests Passed: 61\r?$'
        '(?m)^PlayerAssetTransactionTest Tests Failed: 0\r?$'
    )
    SuccessSummary = 'PlayerAssetTransactionTest 61/61'
    TimeoutSeconds = $TimeoutSeconds
    SkipCompile = $SkipCompile
}
& $commonRunner @focusedRun
