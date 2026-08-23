[CmdletBinding()]
param(
    [ValidateRange(1, 3600)]
    [int]$TimeoutSeconds = 240,
    [switch]$SkipCompile
)

$ErrorActionPreference = 'Stop'
$commonRunner = Join-Path $PSScriptRoot 'test-runners\run-focused-testloader.ps1'

$repoRoot = Split-Path -Parent $PSScriptRoot
$petPanelPath = Join-Path $repoRoot 'scripts\类定义\org\flashNight\arki\merc\PetPanelService.as'
$petPanelSource = Get-Content -LiteralPath $petPanelPath -Raw -Encoding UTF8
if ($petPanelSource -match '_root\.宠物升级加载\s*\(\s*slotIndex\s*\)' -or
    [regex]::Matches($petPanelSource, 'rebuildPetIfDeployed\s*\(').Count -ne 5) {
    throw 'PetPanelService must route managed weapon, advance, rename and level refresh through one slot-based rebuild helper.'
}
if ($petPanelSource -match '_同图部署效果继承') {
    throw 'World adopt must keep existing same-map units in place instead of rebuilding them through a temporary deployment-effect table.'
}
$advanceHandlerStart = $petPanelSource.IndexOf('public static function handleAdvance(')
$advanceHandlerEnd = $petPanelSource.IndexOf('public static function handlePreviewAdvance(', $advanceHandlerStart)
if ($advanceHandlerStart -lt 0 -or $advanceHandlerEnd -le $advanceHandlerStart) {
    throw 'PetPanelService advance handler section is missing or malformed.'
}
$advanceHandlerSection = $petPanelSource.Substring(
    $advanceHandlerStart, $advanceHandlerEnd - $advanceHandlerStart)
if ($advanceHandlerSection -notmatch 'rebuildPetIfDeployed\(\s*slotIndex,[\s\S]*?false,\s*"升级动画2",\s*"advance"\)' -or
    $advanceHandlerSection -match 'rebuildPetIfDeployed\(\s*slotIndex,[\s\S]*?true,\s*"升级动画2",\s*"advance"\)') {
    throw 'Pet advance rebuild must preserve wounded HP/MP; repeatable schemes cannot use the full-heal upgrade path.'
}
$deployStart = $petPanelSource.IndexOf('public static function handleDeploy(')
$deployEnd = $petPanelSource.IndexOf('public static function handleEquipWeapon(', $deployStart)
$renameHandlerStart = $petPanelSource.IndexOf('public static function handleRename(')
$renameCoreStart = $petPanelSource.IndexOf('public static function renamePetSlot(', $renameHandlerStart)
$tooltipStart = $petPanelSource.IndexOf('public static function handleTooltip(', $renameCoreStart)
$staminaHandlerStart = $petPanelSource.IndexOf('public static function handleRestoreStamina(', $tooltipStart)
$staminaCoreStart = $petPanelSource.IndexOf('public static function restoreStaminaSlot(', $staminaHandlerStart)
$levelHandlerStart = $petPanelSource.IndexOf('public static function handleLevelUp(')
$levelCoreStart = $petPanelSource.IndexOf('public static function levelUpSlot(', $levelHandlerStart)
$deleteHandlerStart = $petPanelSource.IndexOf('public static function handleDelete(', $levelCoreStart)
$deleteCoreStart = $petPanelSource.IndexOf('public static function deletePetSlot(', $deleteHandlerStart)
$panelOpenStart = $petPanelSource.IndexOf('public static function handlePanelOpen(', $deleteCoreStart)
$worldAdoptStart = $petPanelSource.IndexOf('public static function handleWorldAdopt(', $panelOpenStart)
$petToolsStart = $petPanelSource.IndexOf('private static function sendResponse(', $worldAdoptStart)
if ($deployStart -lt 0 -or $deployEnd -le $deployStart -or
    $renameHandlerStart -lt 0 -or $renameCoreStart -le $renameHandlerStart -or
    $tooltipStart -le $renameCoreStart -or
    $staminaHandlerStart -le $tooltipStart -or $staminaCoreStart -le $staminaHandlerStart -or
    $levelHandlerStart -le $staminaCoreStart -or
    $levelHandlerStart -lt 0 -or $levelCoreStart -le $levelHandlerStart -or
    $deleteHandlerStart -le $levelCoreStart -or $deleteCoreStart -le $deleteHandlerStart -or
    $panelOpenStart -le $deleteCoreStart -or $worldAdoptStart -le $panelOpenStart -or
    $petToolsStart -le $worldAdoptStart) {
    throw 'PetPanelService shared pet mutation sections are missing or malformed.'
}
$deploySection = $petPanelSource.Substring($deployStart, $deployEnd - $deployStart)
$renameHandlerSection = $petPanelSource.Substring(
    $renameHandlerStart, $renameCoreStart - $renameHandlerStart)
$renameCoreSection = $petPanelSource.Substring(
    $renameCoreStart, $tooltipStart - $renameCoreStart)
$staminaHandlerSection = $petPanelSource.Substring(
    $staminaHandlerStart, $staminaCoreStart - $staminaHandlerStart)
$staminaCoreSection = $petPanelSource.Substring(
    $staminaCoreStart, $levelHandlerStart - $staminaCoreStart)
$levelHandlerSection = $petPanelSource.Substring(
    $levelHandlerStart, $levelCoreStart - $levelHandlerStart)
$levelCoreSection = $petPanelSource.Substring(
    $levelCoreStart, $deleteHandlerStart - $levelCoreStart)
$deleteHandlerSection = $petPanelSource.Substring(
    $deleteHandlerStart, $deleteCoreStart - $deleteHandlerStart)
$deleteCoreSection = $petPanelSource.Substring(
    $deleteCoreStart, $panelOpenStart - $deleteCoreStart)
$worldAdoptSection = $petPanelSource.Substring(
    $worldAdoptStart, $petToolsStart - $worldAdoptStart)
if ([regex]::Matches($deploySection,
        '_root\.战宠UI函数\.尝试切换宠物出战状态').Count -ne 1 -or
    [regex]::Matches($deploySection, 'deployToggle\s*\(').Count -ne 1 -or
    $deploySection -match '\.设置宠物出战\s*\(|petInfo\s*\[\s*4\s*\]\s*=(?!=)') {
    throw 'PetPanelService.handleDeploy must mutate deploy state only through 尝试切换宠物出战状态.'
}
if ([regex]::Matches($levelHandlerSection, 'levelUpSlot\s*\(').Count -ne 1 -or
    $levelHandlerSection -match '_root\.singleSubmit|宠物信息\s*\[') {
    throw 'PetPanelService.handleLevelUp must be a thin adapter over levelUpSlot.'
}
if ([regex]::Matches($deleteHandlerSection, 'deletePetSlot\s*\(').Count -ne 1 -or
    $deleteHandlerSection -match 'ManagedLongGunService|singleAcquire|删除场景宠物|加载宠物') {
    throw 'PetPanelService.handleDelete must be a thin adapter over deletePetSlot.'
}
if ([regex]::Matches($deleteCoreSection,
        '_root\.战宠UI函数\.移除场景宠物槽\s*\(\s*slotIndex\s*\)').Count -ne 1 -or
    $deleteCoreSection -match '_root\.删除场景宠物\s*\(|_root\.加载宠物\s*\(' -or
    $deleteCoreSection -notmatch 'recordPetRefreshSafely\(\s*slotIndex,[\s\S]*?"delete"\s*\)') {
    throw 'deletePetSlot must project only the deleted slot after commit and preserve refresh-deferred reporting.'
}
if ([regex]::Matches($worldAdoptSection,
        '_root\.战宠UI函数\.设置宠物出战\s*\(').Count -ne 1 -or
    $worldAdoptSection -match '_root\.删除场景宠物\s*\(|_root\.加载宠物\s*\(' -or
    $worldAdoptSection -notmatch 'recordPetRefreshSafely\(\s*slot,[\s\S]*?"world_adopt"\s*\)') {
    throw 'World adopt must deploy only its newly committed slot and preserve existing same-map pet instances.'
}
if ([regex]::Matches($renameHandlerSection, 'renamePetSlot\s*\(').Count -ne 1 -or
    $renameHandlerSection -match 'customName\s*=|rebuildPetIfDeployed\s*\(') {
    throw 'PetPanelService.handleRename must be a thin adapter over renamePetSlot.'
}
$renameDirty = $renameCoreSection.IndexOf('_root.存档系统.dirtyMark = true;')
$renameWrite = $renameCoreSection.IndexOf('attrs.customName = newName;')
$renameRebuild = $renameCoreSection.IndexOf('rebuildPetIfDeployed(')
if ($renameDirty -lt 0 -or $renameWrite -le $renameDirty -or $renameRebuild -le $renameWrite) {
    throw 'renamePetSlot must write customName dirty-first and rebuild deployed pets from that authority.'
}
if ([regex]::Matches($staminaHandlerSection, 'restoreStaminaSlot\s*\(').Count -ne 1 -or
    $staminaHandlerSection -match '_root\.金钱|宠物信息\s*\[') {
    throw 'PetPanelService.handleRestoreStamina must be a thin adapter over restoreStaminaSlot.'
}
$staminaInsufficient = $staminaCoreSection.IndexOf('error:"insufficient_gold"')
$staminaBegin = $staminaCoreSection.IndexOf('PlayerAssetTransaction.begin(')
$staminaDirty = $staminaCoreSection.IndexOf('PlayerAssetTransaction.markDirtyRequired(')
$staminaGold = $staminaCoreSection.IndexOf('_root.金钱 -= cost;')
$staminaWrite = $staminaCoreSection.IndexOf('petInfo[2] = 200;')
$staminaCommit = $staminaCoreSection.IndexOf('PlayerAssetTransaction.commit(')
if ($staminaInsufficient -lt 0 -or $staminaBegin -le $staminaInsufficient -or
    $staminaDirty -le $staminaBegin -or $staminaGold -le $staminaDirty -or
    $staminaWrite -le $staminaGold -or $staminaCommit -le $staminaWrite -or
    $staminaCoreSection.IndexOf('PlayerAssetTransaction.settleAfterException(') -lt 0) {
    throw 'restoreStaminaSlot must reject insufficient gold without writes and bind dirty-first gold/stamina writes in one explicit transaction.'
}
$levelBegin = $levelCoreSection.IndexOf('PlayerAssetTransaction.begin(')
$levelDirty = $levelCoreSection.IndexOf('PlayerAssetTransaction.markDirtyRequired(')
$levelSubmit = $levelCoreSection.IndexOf('_root.singleSubmit(')
$levelWrite = $levelCoreSection.IndexOf('petInfo[1] = newLevel;')
$levelCommit = $levelCoreSection.IndexOf('PlayerAssetTransaction.commit(')
$levelRebuild = $levelCoreSection.IndexOf('rebuildPetIfDeployed(')
if ($levelBegin -lt 0 -or $levelDirty -le $levelBegin -or $levelSubmit -le $levelDirty -or
    $levelWrite -le $levelSubmit -or $levelCommit -le $levelWrite -or
    $levelRebuild -le $levelCommit -or
    $levelCoreSection.IndexOf('PlayerAssetTransaction.settleAfterException(') -lt 0 -or
    $levelCoreSection -notmatch 'refreshDeferred:petInfo\[4\] == 1[\s\S]*levelRebuilt !== true') {
    throw 'levelUpSlot must bind dirty-first singleSubmit and level/threshold writes in one explicit transaction before rebuild.'
}

$petEnginePath = Join-Path $repoRoot 'scripts\引擎\引擎_lsy_战宠系统.as'
$petEngineSource = Get-Content -LiteralPath $petEnginePath -Raw -Encoding UTF8
if ([regex]::Matches($petEngineSource,
        '_root\.战宠UI函数\.记录宠物刷新结果\s*=\s*function').Count -ne 1 -or
    $petEngineSource -notmatch '获取宠物显示名[\s\S]*customName' -or
    $petEngineSource -notmatch 'var 宠物名字 = _root\.战宠UI函数\.获取宠物显示名\(id\)') {
    throw 'Pet engine must expose refresh-deferred tracking and customName scene authority.'
}
if ($petEngineSource -notmatch 'var 没有MP资源:Boolean\s*=\s*候选\.mp满血值 == undefined\s*&&\s*候选\.mp == undefined' -or
    $petEngineSource -notmatch 'var MP就绪:Boolean\s*=\s*没有MP资源\s*\|\|') {
    throw 'Pet readiness must accept the production enemy-template shape only when both optional MP fields are absent.'
}
if ($petEngineSource -notmatch '验证宠物候选落位\s*=\s*function' -or
    $petEngineSource -notmatch '验证宠物初始化完成\s*=\s*function' -or
    $petEngineSource -notmatch 'typeof 候选\.__unitInitializedVersion == "undefined"\) return true' -or
    $petEngineSource -notmatch '__petResourceSettlement:资源结算') {
    throw 'Pet creation must accept placement-only attachMovie returns and carry a one-shot post-Dressup resource settlement.'
}
$petCreateStart = $petEngineSource.IndexOf('_root.战宠UI函数.创建宠物单位 = function')
$petCreateEnd = $petEngineSource.IndexOf('_root.战宠UI函数.重建宠物单位 = function', $petCreateStart)
$petRebuildEnd = $petEngineSource.IndexOf('_root.战宠UI函数.尝试切换宠物出战状态 = function', $petCreateEnd)
if ($petCreateStart -lt 0 -or $petCreateEnd -le $petCreateStart -or
    $petRebuildEnd -le $petCreateEnd) {
    throw 'Pet create/rebuild sections are missing or malformed.'
}
$petCreateSection = $petEngineSource.Substring($petCreateStart, $petCreateEnd - $petCreateStart)
$petRebuildSection = $petEngineSource.Substring($petCreateEnd, $petRebuildEnd - $petCreateEnd)
if ($petCreateSection -match '加载游戏世界人物[\s\S]*?settleSpawnResources\(宠物对象\)[\s\S]*?验证宠物候选' -or
    $petRebuildSection -match 'candidate\.(hp|mp)\s*=') {
    throw 'Pet attach return stack must not settle HP/MP before frame-0 Dressup initialization.'
}
if ($petRebuildSection -notmatch 'mode:"preserve"' -or
    $petRebuildSection -notmatch 'mode:"upgrade"' -or
    $petRebuildSection -notmatch '创建宠物单位\([\s\S]*?candidateName, resourceSettlement\)') {
    throw 'Pet rebuild must carry preserve/upgrade resource plans into the deferred initializer.'
}
$staticInitializerPath = Join-Path $repoRoot 'scripts\类定义\org\flashNight\arki\unit\UnitComponent\Initializer\StaticInitializer.as'
$staticInitializerSource = Get-Content -LiteralPath $staticInitializerPath -Raw -Encoding UTF8
$staticDressupIndex = $staticInitializerSource.IndexOf('DressupInitializer.initialize(target)')
$staticSettlementIndex = $staticInitializerSource.IndexOf('settlePendingPetResources(target)')
$staticPublishIndex = $staticInitializerSource.IndexOf('target.dispatcher.publish("UnitInitialized"')
if ($staticInitializerSource -notmatch 'StaticInitializer\.settlePendingPetResources\(target\)' -or
    $staticInitializerSource -notmatch 'DressupInitializer\.settleSpawnResources\(target, target\.__petResourceSettlement\)' -or
    $staticInitializerSource -notmatch 'delete target\.__petResourceSettlement' -or
    $staticDressupIndex -lt 0 -or $staticSettlementIndex -le $staticDressupIndex -or
    $staticPublishIndex -le $staticSettlementIndex) {
    throw 'StaticInitializer must consume the pet resource settlement after Dressup and before UnitInitialized.'
}
if ($petPanelSource -notmatch 'name:\s*_root\.战宠UI函数[\s\S]*获取宠物显示名\(i\)' -or
    $petPanelSource -notmatch 'attrs\.customName\s*=\s*newName' -or
    $petPanelSource -notmatch 'recordPetRefreshSafely\(slotIndex, rebuildSuccess, refreshReason\)' -or
    $petPanelSource -notmatch 'recordPetRefreshSafely\(slotIndex, !deleteRefreshDeferred, "delete"\)') {
    throw 'customName display authority must reach snapshot, rename storage and scene creation.'
}
$petLevelEnginePath = Join-Path $repoRoot 'scripts\引擎\引擎_lsy_等级与经验值.as'
$petLevelEngineSource = Get-Content -LiteralPath $petLevelEnginePath -Raw -Encoding UTF8
$autoLevelStart = $petLevelEngineSource.IndexOf('_root.经验值计算 = function(')
$autoLevelEnd = $petLevelEngineSource.IndexOf('_root.宠物升级加载 = function(', $autoLevelStart)
if ($autoLevelStart -lt 0 -or $autoLevelEnd -le $autoLevelStart) {
    throw 'Automatic pet experience section is missing or malformed.'
}
$autoLevelSection = $petLevelEngineSource.Substring(
    $autoLevelStart, $autoLevelEnd - $autoLevelStart)
$autoLevelFact = $autoLevelSection.IndexOf('当前宠物信息[1]++;')
$autoLevelThreshold = $autoLevelSection.IndexOf('当前宠物信息[5].宠物升级所需经验 =', $autoLevelFact)
$autoLevelRebuild = $autoLevelSection.IndexOf('_root.宠物升级加载(i) === true', $autoLevelThreshold)
$autoLevelRecord = $autoLevelSection.IndexOf('_root.战宠UI函数.记录宠物刷新结果(', $autoLevelRebuild)
if ($autoLevelFact -lt 0 -or $autoLevelThreshold -le $autoLevelFact -or
    $autoLevelRebuild -le $autoLevelThreshold -or $autoLevelRecord -le $autoLevelRebuild -or
    $autoLevelSection -notmatch '"auto_level_up"') {
    throw 'Automatic pet level-up must commit level/threshold before honoring rebuild Boolean and recording refresh deferred.'
}
$advanceLogicPath = Join-Path $repoRoot 'scripts\逻辑\单位函数\单位函数_aka_战宠进阶.as'
$advanceLogicSource = Get-Content -LiteralPath $advanceLogicPath -Raw -Encoding UTF8
$managedTemplatePath = Join-Path $repoRoot 'scripts\test-runners\managed-longgun\TestLoader.as.template'
$managedTemplateSource = Get-Content -LiteralPath $managedTemplatePath -Raw -Encoding UTF8
$templatePetEngine = $managedTemplateSource.IndexOf('#include "引擎/引擎_lsy_战宠系统.as"')
$templatePetLevel = $managedTemplateSource.IndexOf('#include "引擎/引擎_lsy_等级与经验值.as"')
$templatePetAdvance = $managedTemplateSource.IndexOf('#include "逻辑/单位函数/单位函数_aka_战宠进阶.as"')
if ($templatePetEngine -lt 0 -or $templatePetLevel -le $templatePetEngine -or
    $templatePetAdvance -le $templatePetLevel) {
    throw 'Managed-longgun focused template must load pet engine, level engine and pet advance logic in production order.'
}
if ($advanceLogicSource -match '(?m)^\s*刷新当前宠物\s*\(\s*\)\s*;\s*$') {
    throw 'Pet advance scheme functions must not trigger a second unit refresh outside the caller boundary.'
}
if ($advanceLogicSource.Contains('_root.最上层发布文字提示') -or
    $advanceLogicSource.Contains('_root.敌人函数.应用影子色彩(this)')) {
    throw 'Pet advance scheme execution must remain authority-only; presentation and live-unit projection belong after service commit.'
}
$hairSchemeStart = $advanceLogicSource.IndexOf('_root.战宠进阶函数.切换发型 = {')
$hairSchemeEnd = $advanceLogicSource.IndexOf('_root.战宠进阶函数.常驻淬毒 = {', $hairSchemeStart)
if ($hairSchemeStart -lt 0 -or $hairSchemeEnd -le $hairSchemeStart) {
    throw 'Pet hair-toggle advance section is missing or malformed.'
}
$hairSchemeSection = $advanceLogicSource.Substring(
    $hairSchemeStart, $hairSchemeEnd - $hairSchemeStart)
if ($hairSchemeSection.Contains('宠物信息界面') -or
    $hairSchemeSection.Contains('宠物mc库') -or
    $hairSchemeSection.Contains('gotoAndStop')) {
    throw 'Pet hair-toggle scheme must only update saved attributes; live/UI projection belongs to the post-commit rebuild.'
}
$poisonHookStart = $advanceLogicSource.IndexOf('_root.战宠进阶函数.常驻淬毒 = {')
$poisonHookEnd = $advanceLogicSource.IndexOf('_root.战宠进阶函数.冲腿龙息 = {', $poisonHookStart)
if ($poisonHookStart -lt 0 -or $poisonHookEnd -le $poisonHookStart) {
    throw 'Persistent poison advance section is missing or malformed.'
}
$poisonHookSection = $advanceLogicSource.Substring(
    $poisonHookStart, $poisonHookEnd - $poisonHookStart)
$poisonDelayGuard = $poisonHookSection.IndexOf('if(this.延迟常驻淬毒结算 === true) return;')
$poisonDirty = $poisonHookSection.IndexOf('PlayerAssetTransaction.markDirtyRequired(')
$poisonMoneyWrite = $poisonHookSection.IndexOf('_root.金钱 -= poisonCost;')
if ($poisonDelayGuard -lt 0 -or $poisonDirty -le $poisonDelayGuard -or
    $poisonMoneyWrite -le $poisonDirty) {
    throw 'Persistent poison must skip tentative candidates and mark dirty before its per-map gold write.'
}
$petCandidateDelay = $petEngineSource.IndexOf('延迟常驻淬毒结算:true')
$petRebuildSwap = $petEngineSource.IndexOf('_root.宠物mc库[found] = candidate;')
$petRebuildEffects = $petEngineSource.IndexOf(
    '_root.战宠UI函数.结算宠物部署效果(candidate, inheritedDeploymentEffects);', $petRebuildSwap)
$petInitialPush = $petEngineSource.IndexOf('_root.宠物mc库.push(宠物对象);')
$petInitialEffects = $petEngineSource.IndexOf(
    '_root.战宠UI函数.结算宠物部署效果(宠物对象, null);', $petInitialPush)
if ($petEngineSource.IndexOf('_root.战宠UI函数.结算宠物部署效果 = function') -lt 0 -or
    $petCandidateDelay -lt 0 -or $petRebuildSwap -lt 0 -or
    $petRebuildEffects -le $petRebuildSwap -or $petInitialPush -lt 0 -or
    $petInitialEffects -le $petInitialPush) {
    throw 'Pet candidates must defer persistent poison until the unit is formally adopted and inherit same-map state on rebuild.'
}
$petDeploymentSnapshot = $petEngineSource.IndexOf(
    'var inheritedDeploymentEffects:Object =', $petCreateEnd)
$petOldRemove = $petEngineSource.IndexOf('安全移除装备单位(oldUnit)', $petDeploymentSnapshot)
if ($petDeploymentSnapshot -lt 0 -or $petOldRemove -le $petDeploymentSnapshot -or
    $petRebuildSwap -le $petOldRemove) {
    throw 'Pet rebuild must snapshot paid deployment effects before detaching the old MovieClip.'
}
$safeRemoveStart = $petEngineSource.IndexOf('_root.战宠UI函数.安全移除装备单位 = function')
$safeRemoveEnd = $petEngineSource.IndexOf('_root.战宠UI函数._宠物刷新待处理', $safeRemoveStart)
if ($safeRemoveStart -lt 0 -or $safeRemoveEnd -le $safeRemoveStart) {
    throw 'Pet safe-remove section is missing or malformed.'
}
$safeRemoveSection = $petEngineSource.Substring($safeRemoveStart, $safeRemoveEnd - $safeRemoveStart)
if ([regex]::Matches($safeRemoveSection, '(?m)^\s*removeMovieClip\(单位对象\);').Count -ne 1 -or
    $safeRemoveSection -match '单位对象\.removeMovieClip\s*\(' -or
    $safeRemoveSection -match '单位对象\._parent|原父级\s*\[') {
    throw 'Pet safe-remove must issue one bare native removal and must not synchronously read display-tree liveness.'
}
$removeSlotStart = $petEngineSource.IndexOf('_root.战宠UI函数.移除场景宠物槽 = function')
$removeSlotEnd = $petEngineSource.IndexOf('_root.战宠UI函数._宠物刷新待处理', $removeSlotStart)
if ($removeSlotStart -lt 0 -or $removeSlotEnd -le $removeSlotStart) {
    throw 'Pet slot-projection removal helper is missing or malformed.'
}
$removeSlotSection = $petEngineSource.Substring(
    $removeSlotStart, $removeSlotEnd - $removeSlotStart)
if ([regex]::Matches($removeSlotSection, '安全移除装备单位\s*\(').Count -ne 1 -or
    [regex]::Matches($removeSlotSection, '宠物mc库\.splice\s*\(').Count -ne 1 -or
    [regex]::Matches($removeSlotSection, '出战宠物id库\.splice\s*\(').Count -ne 1 -or
    $removeSlotSection -match '删除场景宠物\s*\(|加载宠物\s*\(') {
    throw 'Pet slot-projection removal must touch exactly one paired runtime entry without full-scene reload.'
}

# 本 suite 现有循环会把 118 个静态 check 调用展开为 126 次运行时断言；把调用点
# 与下方 trace 期望同时锁住，避免 focused 施工只改测试却遗忘 runner 计数。
$managedTestPath = Join-Path $repoRoot 'scripts\类定义\org\flashNight\arki\merc\ManagedLongGunServiceTest.as'
$managedTestSource = Get-Content -LiteralPath $managedTestPath -Raw -Encoding UTF8
$managedCheckCallSites = [regex]::Matches(
    $managedTestSource, '(?m)^\s*check\s*\(').Count
if ($managedCheckCallSites -ne 118) {
    throw "ManagedLongGunServiceTest check call-site count drifted: expected 118, actual $managedCheckCallSites. Recalculate the 126 runtime assertion contract."
}
if ($managedTestSource -notmatch 'softAliasUnit\._parent\s*===\s*softAliasParent' -or
    $managedTestSource -notmatch 'softAliasParent\.softAliasPet\s*===\s*softAliasUnit' -or
    $managedTestSource -notmatch 'toggleAliasParent\.toggleAliasPet\s*===\s*toggleAliasUnit' -or
    $managedTestSource -notmatch 'fullReloadCalls\s*==\s*0' -or
    $managedTestSource -notmatch 'worldDeployCalls\s*==\s*1') {
    throw 'ManagedLongGunServiceTest must cover delayed aliases plus targeted delete/world-adopt projection without a full reload.'
}

$focusedRun = @{
    DomainId = 'managed-longgun'
    TemplateRelativePath = 'scripts\test-runners\managed-longgun\TestLoader.as.template'
    SuiteRelativePaths = @(
        'scripts\类定义\org\flashNight\arki\merc\ManagedLongGunServiceTest.as'
        'scripts\类定义\org\flashNight\arki\unit\UnitComponent\Dressup\DressupReferenceManagerTest.as'
        'scripts\类定义\org\flashNight\neur\Event\EventBusTest.as'
    )
    SuiteFqns = @(
        'org.flashNight.arki.merc.ManagedLongGunServiceTest'
        'org.flashNight.arki.unit.UnitComponent.Dressup.DressupReferenceManagerTest'
        'org.flashNight.neur.Event.EventBusTest'
    )
    AdditionalAsRelativePaths = @(
        'scripts\类定义\org\flashNight\arki\merc\ManagedLongGunService.as'
        'scripts\类定义\org\flashNight\arki\merc\PetPanelService.as'
        'scripts\类定义\org\flashNight\arki\unit\Action\Shoot\ShootInitCore.as'
        'scripts\类定义\org\flashNight\arki\unit\UnitComponent\Initializer\DressupInitializer.as'
        'scripts\类定义\org\flashNight\arki\unit\UnitComponent\Initializer\StaticInitializer.as'
        'scripts\类定义\org\flashNight\arki\unit\UnitComponent\Dressup\EquipmentUtil\PlacementVisual.as'
        'scripts\逻辑\装备函数\M134.as'
        'scripts\引擎\引擎_lsy_战宠系统.as'
        'scripts\引擎\引擎_lsy_等级与经验值.as'
        'scripts\逻辑\单位函数\单位函数_aka_战宠进阶.as'
    )
    ExpectedTracePatterns = @(
        '(?m)^ManagedLongGunServiceTest Tests Passed: 126\r?$'
        '(?m)^ManagedLongGunServiceTest Tests Failed: 0\r?$'
        '(?m)^Result: (?<dressup>[1-9][0-9]*)/\k<dressup> passed, 0 failed  \([0-9]+ ms\)\r?$'
        '(?m)^All tests completed\.\r?$'
    )
    SuccessSummary = 'ManagedLongGunServiceTest 126/126 + DressupReferenceManagerTest + EventBusTest all passed'
    TimeoutSeconds = $TimeoutSeconds
    SkipCompile = $SkipCompile
}
& $commonRunner @focusedRun
