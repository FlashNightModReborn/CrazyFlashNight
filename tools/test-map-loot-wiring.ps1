param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = "Stop"
$script:Assertions = 0

function Read-Utf8([string]$RelativePath) {
    $path = Join-Path $ProjectRoot $RelativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Missing wiring source: $RelativePath"
    }
    return [IO.File]::ReadAllText($path, [Text.Encoding]::UTF8)
}

function Assert-True([bool]$Condition, [string]$Label) {
    $script:Assertions++
    if (-not $Condition) { throw $Label }
}

function Assert-Contains([string]$Text, [string]$Needle, [string]$Label) {
    $script:Assertions++
    if ($Text.IndexOf($Needle, [StringComparison]::Ordinal) -lt 0) {
        throw "$Label missing '$Needle'"
    }
}

function Assert-NotContains([string]$Text, [string]$Needle, [string]$Label) {
    $script:Assertions++
    if ($Text.IndexOf($Needle, [StringComparison]::Ordinal) -ge 0) {
        throw "$Label unexpectedly contains '$Needle'"
    }
}

function Assert-Ordered([string]$Text, [string[]]$Needles, [string]$Label) {
    $cursor = -1
    foreach ($needle in $Needles) {
        $script:Assertions++
        $next = $Text.IndexOf($needle, $cursor + 1, [StringComparison]::Ordinal)
        if ($next -lt 0) { throw "$Label missing/out-of-order '$needle'" }
        $cursor = $next
    }
}

function Assert-Regex([string]$Text, [string]$Pattern, [string]$Label) {
    $script:Assertions++
    if (-not [regex]::IsMatch(
            $Text,
            $Pattern,
            [Text.RegularExpressions.RegexOptions]::CultureInvariant -bor
            [Text.RegularExpressions.RegexOptions]::Singleline)) {
        throw "$Label missing regex '$Pattern'"
    }
}

function Assert-Count([string]$Text, [string]$Needle, [int]$Expected, [string]$Label) {
    $script:Assertions++
    $actual = [regex]::Matches($Text, [regex]::Escape($Needle)).Count
    if ($actual -ne $Expected) {
        throw "$Label expected $Expected occurrence(s) of '$Needle', actual $actual"
    }
}

$interaction = Read-Utf8 "scripts\类定义\org\flashNight\arki\unit\UnitComponent\Initializer\ElementComponent\InteractionHandler.as"
$arbiter = Read-Utf8 "scripts\类定义\org\flashNight\arki\unit\UnitComponent\Initializer\ElementComponent\BoxInteractionArbiter.as"
$service = Read-Utf8 "scripts\类定义\org\flashNight\arki\item\LootContainerService.as"
$map = Read-Utf8 "scripts\逻辑\关卡系统\关卡系统_lsy_地图元件.as"
$callback = Read-Utf8 "scripts\逻辑\关卡系统\关卡系统_lsy_资源箱回调.as"
$scene = Read-Utf8 "scripts\类定义\org\flashNight\arki\scene\SceneManager.as"
$sceneFlow = Read-Utf8 "scripts\逻辑\关卡系统\关卡系统_lsy_场景转换.as"
$restartCleanup = Read-Utf8 "scripts\通信\通信_fs_帧计时器.as"
$server = Read-Utf8 "scripts\类定义\org\flashNight\neur\Server\ServerManager.as"
$ui = Read-Utf8 "scripts\展现\UI交互\UI交互_lsy_UI管理.as"
$install = Read-Utf8 "scripts\逻辑系统分区\物品系统_WebView.as"

# 只锁跨文件因果，不锁 service 私有实现快照。
Assert-Ordered $interaction @(
    "ChestSessionService.beginFixture(",
    "LootContainerService.beginFixture(target)",
    "LootMaterializationPlanner.materialize(target)",
    "LootContainerService.commitReservedOpen(",
    "InteractionHandler.executePickup(box)"
) "interaction reserves and materializes before own kill"
Assert-Contains $interaction "BoxInteractionArbiter.isBoxPreset(target.presetName)" (
    "interaction uses the six-box domain arbiter")
Assert-Regex $interaction (
    'if\s*\(lootResult\.reserved !== true\)\s*\{[\s\S]*?' +
    'trace\("\[LootContainer\] open rejected before materialization:' +
    '[\s\S]*?return;\s*\}'
) "handled non-reservation failures are visible and fail closed"
foreach ($retired in @(
    "物化Web战利品物品栏",
    "显示Web战利品旧界面",
    "回退Web战利品到旧界面"
)) {
    Assert-NotContains $interaction $retired "interaction has no retired loot adapter"
}
foreach ($flashRendererToken in @("资源箱界面", "attachMovie(", "createInventoryLayout")) {
    Assert-NotContains $interaction $flashRendererToken (
        "interaction cannot construct a Flash loot renderer")
}
Assert-Regex $interaction (
    'var\s+lootDeath:Object\s*=\s*LootContainerService\.observeDeath\(target\);' +
    '[\s\S]*?lootDeath\.handled === true[\s\S]*?lootDeath\.ownKill !== true' +
    '[\s\S]*?trace\("\[LootContainer\] unexpected target death:'
) "unexpected loot death is visible and remains fail closed"

Assert-Ordered $service @(
    "public static function classifyFixtureShape(target:Object):String",
    "BoxInteractionArbiter.isBoxPreset(",
    "if (!knownBox) return SHAPE_NOT_WEB_LOOT_GRID",
    "!isWhole(target.row) || !isWhole(target.col)",
    "if (rows <= 0 || columns <= 0) return SHAPE_DIRECT_DELIVERY",
    "columns <= MAX_WEB_COLUMNS && capacity <= MAX_WEB_CAPACITY",
    "return SHAPE_UNSUPPORTED_GRID"
) "six-box admission precedes the single strict shape classifier"
foreach ($marker in @("chestRolloutId", "lootFlowProfile", "unlockPolicy")) {
    Assert-NotContains $service $marker "runtime route ignores obsolete rollout markers"
}

Assert-Contains $map '#include "../逻辑/关卡系统/关卡系统_lsy_资源箱回调.as"' (
    "map root includes the single chest callback source")
foreach ($retired in @(
    "掉落物转换为物品栏",
    "创建资源箱图标",
    "显示Web战利品旧界面",
    "回退Web战利品到旧界面",
    "consumeLegacyFallback",
    "claimLegacyRecoverySlot",
    "__lootClaimOnly"
)) {
    Assert-NotContains $map $retired "map root has no retired Flash loot path"
}

Assert-Ordered $callback @(
    "ChestSessionService.handleOpenFrame(target)",
    "LootContainerService.guardOpenGridFixture(target)",
    "LootContainerService.classifyFixtureShape(target)",
    'lootShape == "supported_web_grid"',
    "LootContainerService.activateReservedOpen(target)",
    "LootContainerService.requestOpenPanel()",
    'lootShape != "direct_delivery"',
    "target.掉落物判定()"
) "open frame activates Web authority or takes the explicit direct branch"
Assert-NotContains $callback "Number(target.row) > 0" (
    "open callback cannot widen the strict classifier by coercion")
foreach ($retired in @(
    "具有Web战利品标记",
    "掉落物转换为物品栏",
    "创建资源箱图标",
    "显示Web战利品旧界面",
    "回退Web战利品到旧界面"
)) {
    Assert-NotContains $callback $retired "root callback has no marker or Flash UI escape"
}
foreach ($flashRendererToken in @("资源箱界面", "attachMovie(", "createInventoryLayout")) {
    Assert-NotContains $callback $flashRendererToken (
        "root callback cannot construct a Flash loot renderer")
}
$breakStart = $callback.IndexOf("资源箱破碎脚本", [StringComparison]::Ordinal)
Assert-True ($breakStart -ge 0) "break callback missing"
$breakText = $callback.Substring($breakStart)
Assert-Ordered $breakText @(
    "ChestSessionService.handleBreakFrame(target)",
    "LootContainerService.guardBreakGridFixture(target)",
    "target.掉落物判定()"
) "break frame keeps direct-drop semantics behind the authority guard"
Assert-NotContains $breakText "LootContainerService.activateReservedOpen(target)" (
    "break path never activates an interaction reservation")

# 审真实 XFL publish closure，不绑定脆弱帧号。
$mapXflDocumentRelative = "flashswf\arts\new\素材库-地图元件\DOMDocument.xml"
$mapXflDocument = Read-Utf8 $mapXflDocumentRelative
[xml]$mapXflXml = $mapXflDocument
$includeHrefs = @($mapXflXml.SelectNodes("//*[local-name()='Include']") | ForEach-Object {
    [string]$_.href
})
Assert-True ($includeHrefs.Count -gt 0) "map XFL Include closure is empty"
$mapXflLibraryRoot = Join-Path $ProjectRoot "flashswf\arts\new\素材库-地图元件\LIBRARY"
$includedSymbols = @{}
$missingIncludes = New-Object System.Collections.Generic.List[string]
foreach ($href in $includeHrefs) {
    $symbolPath = Join-Path $mapXflLibraryRoot ($href -replace '/', '\')
    if (-not (Test-Path -LiteralPath $symbolPath -PathType Leaf)) {
        $missingIncludes.Add($href)
        continue
    }
    $includedSymbols[$href] = [IO.File]::ReadAllText(
        $symbolPath,
        [Text.Encoding]::UTF8)
}
Assert-True ($missingIncludes.Count -eq 0) (
    "map XFL has missing Include target(s): " + ($missingIncludes -join ", "))

$chestSymbols = @(
    [pscustomobject]@{ Name="保险柜"; Href="箱子素材/保险柜/保险柜.xml"; Breaks=1 },
    [pscustomobject]@{ Name="生存箱"; Href="箱子素材/生存箱/生存箱.xml"; Breaks=0 },
    [pscustomobject]@{ Name="装备箱"; Href="箱子素材/装备箱/装备箱.xml"; Breaks=0 },
    [pscustomobject]@{ Name="资源箱"; Href="箱子素材/资源箱/资源箱.xml"; Breaks=1 },
    [pscustomobject]@{ Name="纸箱"; Href="箱子素材/纸箱/纸箱.xml"; Breaks=1 },
    [pscustomobject]@{ Name="隐藏资源点"; Href="箱子素材/隐藏资源点.xml"; Breaks=0 }
)
$boxPresetStart = $arbiter.IndexOf(
    "public static function isBoxPreset",
    [StringComparison]::Ordinal)
$boxPresetEnd = if ($boxPresetStart -ge 0) {
    $arbiter.IndexOf(
        "public static function initialize",
        $boxPresetStart,
        [StringComparison]::Ordinal)
} else {
    -1
}
Assert-True ($boxPresetStart -ge 0 -and $boxPresetEnd -gt $boxPresetStart) (
    "BoxInteractionArbiter isBoxPreset bounds missing")
$boxPresetBody = $arbiter.Substring(
    $boxPresetStart,
    $boxPresetEnd - $boxPresetStart)
$arbiterBoxNames = @(
    [regex]::Matches($boxPresetBody, 'presetName\s*===\s*"(?<name>[^"]+)"') |
        ForEach-Object { $_.Groups["name"].Value }
)
Assert-True ($arbiterBoxNames.Count -eq $chestSymbols.Count) (
    "arbiter and canonical XFL chest domains differ in size")
Assert-True (($arbiterBoxNames | Sort-Object -Unique).Count -eq $arbiterBoxNames.Count) (
    "arbiter box preset domain contains duplicates")
foreach ($chest in $chestSymbols) {
    Assert-True ($arbiterBoxNames -ccontains $chest.Name) (
        "arbiter does not admit canonical chest: " + $chest.Name)
}
$includedCorpus = ($includedSymbols.Values -join [Environment]::NewLine)
foreach ($chest in $chestSymbols) {
    Assert-True (@($includeHrefs | Where-Object { $_ -ceq $chest.Href }).Count -eq 1) (
        "map XFL must include exactly one canonical $($chest.Name) symbol")
    $symbol = [string]$includedSymbols[$chest.Href]
    Assert-Count $includedCorpus ('linkageIdentifier="' + $chest.Name + '"') 1 (
        "included linkage is unique for " + $chest.Name)
    Assert-Count $symbol ('_root.地图元件.初始化地图元件(this, "' + $chest.Name + '")') 1 (
        "canonical symbol initializes " + $chest.Name)
    Assert-Count $symbol "_root.地图元件.资源箱开启脚本(this)" 1 (
        "canonical symbol uses the root open callback: " + $chest.Name)
    Assert-Count $symbol "_root.地图元件.资源箱破碎脚本(this)" $chest.Breaks (
        "canonical symbol break topology: " + $chest.Name)
    foreach ($retired in @(
        "_root.创建可拾取物",
        "掉落物转换为物品栏",
        "创建资源箱图标",
        "显示Web战利品旧界面",
        "回退Web战利品到旧界面",
        "__lootClaimOnly"
    )) {
        Assert-NotContains $symbol $retired (
            "canonical chest has no direct/Flash UI bypass: " + $chest.Name)
    }
}
Assert-True (-not ($includeHrefs -ccontains "资源箱.xml")) (
    "orphan top-level resource-box symbol entered the publish closure")
Assert-True (-not ($includeHrefs -ccontains "隐藏资源点.xml")) (
    "orphan top-level hidden-resource symbol entered the publish closure")
foreach ($retired in @(
    "掉落物转换为物品栏",
    "创建资源箱图标",
    "显示Web战利品旧界面",
    "回退Web战利品到旧界面",
    "__lootClaimOnly"
)) {
    Assert-NotContains $includedCorpus $retired (
        "published map XFL closure has no Flash loot renderer")
}

# 场景销毁与暂停释放必须继续跨文件等待 loot authority 收束。
$sceneRemoveStart = $scene.IndexOf(
    "public function removeGameWorld",
    [StringComparison]::Ordinal)
$sceneRemoveEnd = $scene.IndexOf(
    "public function dispose",
    $sceneRemoveStart,
    [StringComparison]::Ordinal)
Assert-True ($sceneRemoveStart -ge 0 -and $sceneRemoveEnd -gt $sceneRemoveStart) (
    "SceneManager removeGameWorld bounds missing")
$sceneRemoveText = $scene.Substring(
    $sceneRemoveStart,
    $sceneRemoveEnd - $sceneRemoveStart)
Assert-Ordered $sceneRemoveText @(
    'LootContainerService.expireScene("scene_cleanup")',
    "lootExpiry.success !== true",
    "return false",
    "this.active = false",
    "gameworld.dispatcher.destroy()",
    "gameworld.removeMovieClip()",
    "return true"
) "scene teardown waits for loot expiry before destructive cleanup"

$rootCleanupStart = $sceneFlow.IndexOf(
    "_root.清除游戏世界组件 = function",
    [StringComparison]::Ordinal)
$rootCleanupEnd = $sceneFlow.IndexOf(
    "_root.注释结束();",
    $rootCleanupStart,
    [StringComparison]::Ordinal)
Assert-True ($rootCleanupStart -ge 0 -and $rootCleanupEnd -gt $rootCleanupStart) (
    "root scene cleanup bounds missing")
$rootCleanupText = $sceneFlow.Substring(
    $rootCleanupStart,
    $rootCleanupEnd - $rootCleanupStart)
Assert-Ordered $rootCleanupText @(
    "if (!SceneManager.instance.removeGameWorld())",
    "_root.淡出动画.stop()",
    "_root.__安排游戏世界清理重试()",
    "return false",
    "CollisionLayerRenderer.clearAll()"
) "fade timeline blocks before root teardown"

$restartStart = $restartCleanup.IndexOf(
    "_root.cleanupForRestart = function():Boolean {",
    [StringComparison]::Ordinal)
$restartEnd = if ($restartStart -ge 0) {
    $restartCleanup.IndexOf(
        "};",
        $restartStart,
        [StringComparison]::Ordinal)
} else {
    -1
}
Assert-True ($restartStart -ge 0 -and $restartEnd -gt $restartStart) (
    "cleanupForRestart bounds missing")
$restartText = $restartCleanup.Substring(
    $restartStart,
    $restartEnd - $restartStart)
Assert-Ordered $restartText @(
    "org.flashNight.arki.item.LootContainerService.expireScene(",
    "if (lootExpiry == null || lootExpiry.success !== true) {",
    "return false;",
    "StageManager.instance.dispose();",
    "return true;"
) "restart cleanup preflights loot before manager disposal"

Assert-Ordered $server @(
    "ChestS0SocketBridge.handleSocketClosed()",
    "LootContainerService.reconcileSocketDetach(null)"
) "socket loss enters Web-only authority convergence"
Assert-NotContains $server "PauseManager.releaseLease(_root._webPanelPauseLease)" (
    "socket lifecycle cannot release pause outside loot proof")
Assert-Ordered $ui @(
    'gameCommands["webPanelUnpause"]',
    "LootContainerService.releaseSuspendedPauseForClose()",
    "LootContainerService.hasPendingTransportDetach()",
    "PauseManager.releaseLease"
) "generic unpause cannot cross an unresolved loot handoff"
Assert-Contains $install "LootContainerService.install()" "loot command install"

# 全 production AS2 与 stage corpus 的不可回退门。
$productionLootAsFiles = @(
    Get-ChildItem -LiteralPath (Join-Path $ProjectRoot "scripts") -Recurse -File -Filter "*.as" |
        Where-Object {
            $_.Name -notlike "*Test.as" -and
            $_.FullName -notlike "*\test-runners\*"
        }
)
$retiredLootRefs = @(
    $productionLootAsFiles |
        Select-String -Pattern (
            '掉落物转换为物品栏|创建资源箱图标|' +
            '显示Web战利品旧界面|回退Web战利品到旧界面|' +
            'consumeLegacyFallback|confirmLegacyRenderer|' +
            'claimLegacyRecoverySlot|attachLegacyRecoveryObserver|__lootClaimOnly'
        )
)
Assert-True ($retiredLootRefs.Count -eq 0) (
    "production AS2 still references retired Flash loot UI: " +
    (($retiredLootRefs | ForEach-Object { $_.Path }) -join ", "))

$stageRoot = Join-Path $ProjectRoot "data\stages"
$stageFiles = @(
    Get-ChildItem -LiteralPath $stageRoot -Recurse -File -Filter "*.xml" |
        Sort-Object FullName
)
$stageCorpus = (
    $stageFiles |
        ForEach-Object {
            [IO.File]::ReadAllText($_.FullName, [Text.Encoding]::UTF8)
        }
) -join [Environment]::NewLine
Assert-NotContains $stageCorpus "<chestRolloutId>" (
    "production stages contain per-box rollout ids")
Assert-NotContains $stageCorpus "<lootFlowProfile>" (
    "production stages contain per-box loot profiles")
Assert-NotContains $stageCorpus "<unlockPolicy>" (
    "production stages contain per-box unlock policy")
Assert-NotContains $stageCorpus "<chestS0FixtureId>" (
    "production stages contain S0 fixture markers")

Write-Output ("[PASS] map-loot-wiring: {0} assertions" -f $script:Assertions)
