import org.flashNight.arki.item.equipment.SubweaponDataUtil;
import org.flashNight.arki.item.PlayerAssetTransaction;
import org.flashNight.arki.unit.Action.Shoot.LongGunSubWeaponCore;
import org.flashNight.arki.unit.Action.Shoot.ReloadManager;
import org.flashNight.arki.unit.Action.Shoot.ShootInitCore;
import org.flashNight.arki.unit.Action.Skill.SkillReloadCore;
import org.flashNight.arki.unit.Action.Skill.WeaponSkillInputService;
import org.flashNight.arki.unit.Action.Skill.QuickSkillInputService;
import org.flashNight.arki.unit.Action.Skill.ManualCooldownService;
import org.flashNight.arki.unit.Action.Skill.SkillReleaseGuard;
import org.flashNight.arki.unit.Action.Input.UnitActionIntentService;
import org.flashNight.arki.unit.UnitComponent.Routing.RoutingLifecycle;
import org.flashNight.arki.item.ItemUtil;
import org.flashNight.gesh.tooltip.TooltipConstants;
import org.flashNight.gesh.tooltip.TooltipTextBuilder;
import org.flashNight.neur.Event.EventDispatcher;
import org.flashNight.neur.ScheduleTimer.EnhancedCooldownWheel;
import org.flashNight.arki.unit.UnitComponent.Initializer.EventComponent.FireEventComponent;
import org.flashNight.arki.unit.UnitComponent.Dressup.EquipmentUtil.EquipmentFireIntent;

/**
 * LongGunSubWeaponCoreTest
 *
 * 覆盖长枪副武器重构的最小契约：正式 subweapon 数据、倍率、控制槽、装填和 tooltip。
 */
class org.flashNight.arki.unit.Action.Shoot.LongGunSubWeaponCoreTest {

    public static var testsRun:Number = 0;
    public static var testsPassed:Number = 0;
    public static var testsFailed:Number = 0;

    public static function runAllTests():Void {
        testsRun = testsPassed = testsFailed = 0;
        trace("--- LongGunSubWeaponCoreTest ---");

        testSubweaponNormalization();
        testConfigureUnitAndImpactChainMultiplier();
        testImpactZeroPreservesForcedKnockdown();
        testImpactChainAddsEquipmentGunpowerAfterShotgunMultiplier();
        testEquipmentGunpowerRequiresImpactChain();
        testWeaponSpecificAccuracyProjection();
        testConfigureUnitRestoresStoredReloadCount();
        testDirtyRefreshUpdatesRuntimeBridgeFields();
        testPrepareManBulletPropsRefreshesRuntimeStatsBySignature();
        testConfigureUnitRestoresStoredFiredCount();
        testSetFiredCountKeepsSnapshotsConsistent();
        testLoadedSnapshotIsNotAuthority();
        testClearUnitPreservesStoredFiredMirror();
        testClearUnitSkipsStoredMirrorDuringEquipRefresh();
        testSceneRefillPersistentShotConfiguresFullMagazine();
        testControlSlotMarker();
        testWeaponSkillInputBypassesSharedCooldownForSubweapon();
        testWeaponSkillInputKeepsSharedCooldownForNormalSkill();
        testWeaponSkillFrameInputWaitsForCooldownAndLatches();
        testWeaponSkillFrameInputConsumesFailedSubweaponAttempt();
        testWeaponSkillFrameInputRearmsOnReleaseWhileDisabled();
        testQuickSkillInputWaitsForCooldownAndLatchesPerSlot();
        testQuickSkillInputConsumesFailedAttempt();
        testQuickSkillInputRearmsAcrossDisabledFrames();
        testQuickSkillInputKeepsSlotLatchesIndependent();
        testQuickSkillInputSyncsLiveKeyLabelAndClearsUnit();
        testQuickSkillInputRejectsEmptyAndMalformedSlots();
        testSkillReleaseGuardRejectsUnknownSkillsAndInvalidCost();
        testMissingSkillContainerRecoveryUsesCanonicalExit();
        testQuickSkillInputPreservesTruthyLegacyPorts();
        testQuickSkillInputFailsClosedWithoutCooldownStarter();
        testManualReloadIntentQueuesForHeldGunStateMachine();
        testPrimaryReloadWinsAndConsumesManualReloadIntent();
        testManualReloadIntentExpiresAndRevalidates();
        testCombatIntentPriorityAndKindIsolation();
        testSubweaponWithoutMoveShootDoesNotFireFromRun();
        testSubweaponCommitRejectsWalkWithoutMoveShoot();
        testFireFromRunWithMoveShootPlaysDirectionalAnimation();
        testFireFromManUsesPassedCurrentMan();
        testShootInitSubweaponBindingRequestsCurrentMan();
        testSubweaponContinuousShootRefreshesManEachTick();
        testLongCooldownSubweaponRecoilEndsBeforeFireGate();
        testSubweaponEventIsolationAndInterval();
        testEquipmentFireIntentMainLongGunGate();
        testSubweaponEmptyDoesNotTriggerMainReload();
        testDeferredFireAbortDoesNotCommitCostOrCooldown();
        testDeferredFireInvalidatedStateDoesNotCommit();
        testManualReloadRejectsUnavailableCurrentManWithoutPendingState();
        testManualReload();
        testManualReloadFromRunNormalizesPose();
        testManualReloadUsesCurrentManLifecycle();
        testManualReloadInterruptionDoesNotLeakUnitState();
        testManualReloadAnimationCommit();
        testLinkedReload();
        testSubweaponTacticalRecoveryAccumulatesOnPaidReload();
        testSubweaponTacticalRecoveryFreeReloadWithoutReserve();
        testLinkedReloadRequiresReserve();
        testMainReloadSubmitFailurePreservesStateAndOnlyPublishesCommittedLoss();
        testTubeReloadConsumesReserveExactlyOnce();
        testReloadKeyMarksCombinedReloadWhenBothNeedAmmo();
        testGunslingerLevel9StillLinksPartialSubweaponReload();
        testGunslingerLevel10SkipsLinkedReloadWhenSubweaponNotEmpty();
        testReloadKeyStartsSubweaponWhenMainFull();
        testCombinedReloadBurdenAddsSubweaponBurden();
        testNonHeroRollReloadRefillsSubweaponWithoutInventory();
        testHeroRollReloadRefillsSubweaponWhenMainFull();
        testTooltipRendersSubweapon();

        trace("--- LongGunSubWeaponCoreTest: " + testsPassed + "/" + testsRun + " passed, " + testsFailed + " failed ---");
    }

    private static function testSubweaponNormalization():Void {
        var sub:Object = SubweaponDataUtil.normalizeSubweapon(makeSubweapon(true));
        assert(sub.capacity == 5, "subweapon normalization keeps capacity");
        assert(sub.reserveName == "火焰喷射器燃料罐", "subweapon normalization keeps reserveName");
        assert(sub.consumeMode == "onFire", "onFire consume mode is kept");
        assert(sub.consumeTiming == "onFire", "onFire consume timing is kept");
        assert(sub.mp == 100, "subweapon normalization keeps mp cost");
        assert(sub.damageType == "破击", "subweapon normalization keeps damage type");
        assert(sub.magicType == "生化", "subweapon normalization keeps magic type");
        assert(sub.manualReloadBurden == 25, "subweapon normalization sets default manual reload burden");
    }

    private static function testConfigureUnitAndImpactChainMultiplier():Void {
        var unit:Object = makeUnit();
        var itemData:Object = {weapontype: "霰弹枪", subweapon: makeSubweapon(false)};
        var ok:Boolean = LongGunSubWeaponCore.configureUnit(unit, itemData);

        assert(ok, "configureUnit accepts canonical subweapon");
        assert(unit.长枪副武器状态.loaded == 5, "configureUnit initializes loaded capacity");
        assert(unit.长枪副武器状态.groupPaid == true, "configureUnit treats initial magazine as preloaded");
        assert(unit.副武器子弹威力 == 2000, "impact chain level 10 applies 2x shotgun-host subweapon bonus");
        assert(unit.副武器子弹击倒率 == 2.5, "impact chain level 10 doubles subweapon impact force");
        assert(unit.副武器伤害类型 == "破击", "configureUnit writes damage type field");
    }

    private static function testImpactZeroPreservesForcedKnockdown():Void {
        var unit:Object = makeUnit();
        var sub:Object = makeSubweapon(false);
        sub.impact = 0;
        var ok:Boolean = LongGunSubWeaponCore.configureUnit(unit, {weapontype: "突击步枪", subweapon: sub});

        assert(ok, "configureUnit accepts subweapon with zero impact");
        assert(unit.副武器子弹击倒率 == 0, "zero impact keeps forced knockdown bridge value");

        var props:Object = LongGunSubWeaponCore.prepareManBulletProps(unit, unit.man);
        assert(props.击倒率 == 0, "zero impact keeps forced knockdown bullet prop");
    }

    private static function testImpactChainAddsEquipmentGunpowerAfterShotgunMultiplier():Void {
        var unit:Object = makeUnit();
        unit.装备枪械威力加成 = 600;
        var itemData:Object = {weapontype: "霰弹枪", subweapon: makeSubweapon(false)};
        var ok:Boolean = LongGunSubWeaponCore.configureUnit(unit, itemData);

        assert(ok, "configureUnit accepts shotgun-host subweapon with gunpower");
        assert(unit.副武器子弹威力 == 2300, "impact chain adds 50 percent equipment gunpower after shotgun multiplier");
    }

    private static function testEquipmentGunpowerRequiresImpactChain():Void {
        var unit:Object = makeUnit();
        unit.装备枪械威力加成 = 600;
        unit.被动技能.冲击连携.启用 = false;
        var itemData:Object = {weapontype: "突击步枪", subweapon: makeSubweapon(false)};
        var ok:Boolean = LongGunSubWeaponCore.configureUnit(unit, itemData);

        assert(ok, "configureUnit accepts subweapon without impact chain");
        assert(unit.副武器子弹威力 == 1000, "equipment gunpower does not affect subweapon without impact chain");
    }

    private static function testWeaponSpecificAccuracyProjection():Void {
        var unit:Object = {
            _name:"accuracyFixture",
            是否为敌人:false,
            被动技能:{},
            基础命中率:10,
            基础命中加成:20,
            手枪命中加成:30,
            手枪2命中加成:-10,
            手枪数据:{weapontype:"手枪"},
            手枪2数据:{weapontype:"手枪"}
        };
        var weaponData:Array = [];
        weaponData.split = 1;
        weaponData.diffusion = 0;
        weaponData.sound = "";
        weaponData.muzzle = "";
        weaponData.bullet = "普通子弹";
        weaponData.velocity = 10;
        weaponData.bullethit = "";
        weaponData.power = 100;
        weaponData.bulletsize = 10;
        weaponData.impact = 50;
        weaponData.targethit = "";

        var mainProps:Object = ShootInitCore.generateBulletProps(
            unit, "手枪", weaponData, {});
        var subProps:Object = ShootInitCore.generateBulletProps(
            unit, "手枪2", weaponData, {});
        assert(Math.abs(mainProps.命中率 - 15) < 0.0001,
            "main-hand bullet projects base plus main-hand accuracy");
        assert(Math.abs(subProps.命中率 - 11) < 0.0001,
            "off-hand bullet projects base plus off-hand accuracy independently");
    }

    private static function testConfigureUnitRestoresStoredReloadCount():Void {
        var unit:Object = makeUnit();
        unit.长枪.value.subweaponReloadCount = 4;
        var ok:Boolean = LongGunSubWeaponCore.configureUnit(unit, {weapontype: "突击步枪", subweapon: makeSubweapon(false)});

        assert(ok, "configureUnit accepts subweapon with stored reload count");
        assert(unit.长枪副武器.value.reloadCount == 4, "configureUnit restores subweapon tactical reload pool to virtual weapon");
        assert(unit.长枪副武器状态.reloadCount == 4, "configureUnit restores subweapon tactical reload pool to state");
        assert(unit.长枪.value.subweaponReloadCount == 4, "configureUnit keeps subweapon tactical reload pool on long gun value");
    }

    private static function testDirtyRefreshUpdatesRuntimeBridgeFields():Void {
        var unit:Object = makeUnit();
        var itemData:Object = {weapontype: "霰弹枪", subweapon: makeSubweapon(false)};
        LongGunSubWeaponCore.configureUnit(unit, itemData);
        assert(unit.副武器子弹威力 == 2000, "runtime bridge starts with resolved shotgun-host power");

        unit.装备枪械威力加成 = 600;
        LongGunSubWeaponCore.markRuntimeStatsDirty(unit);
        assert(unit.副武器子弹威力 == 2000, "dirty mark alone does not mutate bridge fields");

        LongGunSubWeaponCore.refreshRuntimeStats(unit);
        assert(unit.副武器子弹威力 == 2300, "runtime refresh updates bridge fields from resolver");
    }

    private static function testPrepareManBulletPropsRefreshesRuntimeStatsBySignature():Void {
        var unit:Object = makeUnit();
        unit.装备枪械威力加成 = 600;
        LongGunSubWeaponCore.configureUnit(unit, {weapontype: "霰弹枪", subweapon: makeSubweapon(false)});
        assert(unit.副武器子弹威力 == 2300, "signature test starts with impact-chain gunpower power");

        unit.被动技能.冲击连携.启用 = false;
        var props:Object = LongGunSubWeaponCore.prepareManBulletProps(unit, unit.man);

        assert(props.子弹威力 == 1000, "prepareManBulletProps refreshes stale power when skill signature changes");
        assert(props.击倒率 == 5, "prepareManBulletProps refreshes stale impact when skill signature changes");
        assert(unit.副武器子弹威力 == 1000, "signature refresh updates bridge power field");
        assert(unit.副武器子弹击倒率 == 5, "signature refresh updates bridge impact field");
    }

    private static function testConfigureUnitRestoresStoredFiredCount():Void {
        var unit:Object = makeUnit();
        unit.长枪.value.subweaponShot = 3;

        var ok:Boolean = LongGunSubWeaponCore.configureUnit(unit, {weapontype: "突击步枪", subweapon: makeSubweapon(false)});

        assert(ok, "configureUnit accepts subweapon with stored fired count");
        assert(unit.长枪副武器状态.loaded == 2, "configureUnit restores loaded rounds from weapon value");
        assert(unit.当前弹夹副武器已发射数 == 3, "configureUnit restores runtime fired count from weapon value");
        assert(unit.长枪.value.subweaponShot == 3, "configureUnit keeps stored subweapon fired count on equipment value");
    }

    private static function testSetFiredCountKeepsSnapshotsConsistent():Void {
        var unit:Object = makeUnit();
        LongGunSubWeaponCore.configureUnit(unit, {weapontype: "突击步枪", subweapon: makeSubweapon(false)});

        LongGunSubWeaponCore.setFiredCount(unit, 4);

        assertSubweaponSnapshots(unit, 4, "setFiredCount keeps all subweapon ammo snapshots consistent");
        assert(LongGunSubWeaponCore.getLoadedCount(unit) == 1, "getLoadedCount derives remaining rounds from fired count");
    }

    private static function testLoadedSnapshotIsNotAuthority():Void {
        var unit:Object = makeUnit();
        LongGunSubWeaponCore.configureUnit(unit, {weapontype: "突击步枪", subweapon: makeSubweapon(false)});
        LongGunSubWeaponCore.setFiredCount(unit, 4);

        unit.长枪副武器状态.loaded = unit.长枪副武器状态.capacity;
        unit.当前弹夹副武器已发射数 = 0;
        unit.长枪.value.subweaponShot = 0;
        LongGunSubWeaponCore.syncSnapshots(unit);

        assertSubweaponSnapshots(unit, 4, "legacy loaded/current/stored mirrors do not override virtual fired authority");
    }

    private static function testClearUnitPreservesStoredFiredMirror():Void {
        var unit:Object = makeUnit();
        LongGunSubWeaponCore.configureUnit(unit, {weapontype: "突击步枪", subweapon: makeSubweapon(false)});
        LongGunSubWeaponCore.setFiredCount(unit, 3);

        LongGunSubWeaponCore.clearUnit(unit);
        assert(!LongGunSubWeaponCore.hasSubweapon(unit), "clearUnit removes runtime subweapon state");
        assert(unit.长枪.value.subweaponShot == 3, "clearUnit preserves stored fired mirror for next configure");
        assert(unit.当前弹夹副武器已发射数 == 0, "clearUnit clears legacy runtime fired snapshot");

        LongGunSubWeaponCore.configureUnit(unit, {weapontype: "突击步枪", subweapon: makeSubweapon(false)});
        assertSubweaponSnapshots(unit, 3, "configureUnit restores subweapon ammo after clearUnit");
    }

    private static function testClearUnitSkipsStoredMirrorDuringEquipRefresh():Void {
        var unit:Object = makeUnit();
        LongGunSubWeaponCore.configureUnit(unit, {weapontype: "突击步枪", subweapon: makeSubweapon(false)});
        LongGunSubWeaponCore.setFiredCount(unit, 3);
        unit.长枪副武器.value.reloadCount = 4;
        LongGunSubWeaponCore.syncSnapshots(unit);

        unit.长枪 = {value: {shot: 0, reloadCount: 0, subweaponShot: 0, subweaponReloadCount: 0}};
        LongGunSubWeaponCore.clearUnit(unit, false);

        assert(!LongGunSubWeaponCore.hasSubweapon(unit), "clearUnit without persist removes runtime subweapon state");
        assert(unit.长枪.value.subweaponShot == 0, "clearUnit without persist does not copy old fired mirror to refreshed long gun");
        assert(unit.长枪.value.subweaponReloadCount == 0, "clearUnit without persist does not copy old recovery pool to refreshed long gun");

        LongGunSubWeaponCore.configureUnit(unit, {weapontype: "突击步枪", subweapon: makeSubweapon(false)});
        assertSubweaponSnapshots(unit, 0, "configureUnit after equip refresh uses refreshed long-gun mirror");
        assert(unit.长枪副武器状态.reloadCount == 0, "configureUnit after equip refresh does not inherit old recovery pool");
    }

    private static function testSceneRefillPersistentShotConfiguresFullMagazine():Void {
        var unit:Object = makeUnit();
        unit.长枪.value.subweaponShot = 5;
        LongGunSubWeaponCore.configureUnit(unit, {weapontype: "突击步枪", subweapon: makeSubweapon(false)});
        assert(unit.长枪副武器状态.loaded == 0, "configureUnit sees empty subweapon before scene refill mirror reset");

        LongGunSubWeaponCore.clearUnit(unit);
        unit.长枪.value.subweaponShot = 0;
        LongGunSubWeaponCore.configureUnit(unit, {weapontype: "突击步枪", subweapon: makeSubweapon(false)});

        assertSubweaponSnapshots(unit, 0, "scene refill persistent mirror reset configures full subweapon magazine");
    }

    private static function testControlSlotMarker():Void {
        var unit:Object = makeUnit();
        LongGunSubWeaponCore.configureUnit(unit, {weapontype: "突击步枪", subweapon: makeSubweapon(false)});
        var slot:Object = LongGunSubWeaponCore.buildControlSlot(unit.长枪副武器配置);

        assert(slot.isSubweaponControl === true, "control slot keeps isSubweaponControl marker");
        assert(slot.战技函数 == undefined, "control slot does not require normal skill function");
        assert(slot.名字 == "测试副武器", "control slot uses subweapon control name");
    }

    private static function testWeaponSkillInputBypassesSharedCooldownForSubweapon():Void {
        installMockInventory("火焰喷射器燃料罐", 1);
        var unit:Object = makeUnit();
        LongGunSubWeaponCore.configureUnit(unit, {weapontype: "突击步枪", subweapon: makeSubweapon(false)});
        markSubweaponEmpty(unit, true);
        unit.主动战技 = {长枪: LongGunSubWeaponCore.buildControlSlot(unit.长枪副武器配置)};
        unit.releaseCount = 0;
        unit.释放主动战技 = function():Boolean {
            this.releaseCount++;
            return true;
        };

        assert(WeaponSkillInputService.canTriggerUnit(unit, false), "subweapon control bypasses shared active-skill cooldown gate without visible skill UI");
        var result:Object = WeaponSkillInputService.releaseUnit(unit, 100);
        assert(result.released === true, "subweapon control accepts a combat intent through input service");
        assert(result.isSubweaponControl === true, "subweapon control result keeps semantic marker");
        assert(result.startSharedCooldown === false, "subweapon control does not start shared active-skill cooldown");
        assert(unit.releaseCount == 0, "subweapon control no longer delegates to direct unit skill release");
        assert(UnitActionIntentService.has(unit, UnitActionIntentService.CHANNEL_COMBAT, UnitActionIntentService.KIND_SUBWEAPON_RELOAD, 100), "subweapon control queues generic combat intent");
        assert(unit.__subweaponManualReloadIntent == undefined
                && _root.存档系统.dirtyMark === false,
            "subweapon control creates no reload mailbox or persistence write");
        restoreMockInventory();
    }

    private static function testWeaponSkillInputKeepsSharedCooldownForNormalSkill():Void {
        var unit:Object = makeUnit();
        unit.主动战技 = {长枪: {名字: "测试战技", 冷却时间: 2500, 消耗hp: 0, 消耗mp: 0}};
        unit.releaseCount = 0;
        unit.释放主动战技 = function():Boolean {
            this.releaseCount++;
            return true;
        };

        assert(!WeaponSkillInputService.canTriggerUnit(unit, false), "normal weapon skill waits for shared active-skill cooldown");

        assert(WeaponSkillInputService.canTriggerUnit(unit, true), "normal weapon skill triggers when shared cooldown is ready");
        var result:Object = WeaponSkillInputService.releaseUnit(unit, 110);
        assert(result.released === true, "normal weapon skill release succeeds through input service");
        assert(result.isSubweaponControl === false, "normal weapon skill result is not subweapon control");
        assert(result.startSharedCooldown === true, "normal weapon skill starts shared active-skill cooldown");
        assert(result.cooldownTime == 2500, "normal weapon skill result keeps configured cooldown time");
        assert(unit.releaseCount == 1, "normal weapon skill delegates to unit release once");
        assert(!UnitActionIntentService.has(unit, UnitActionIntentService.CHANNEL_COMBAT, UnitActionIntentService.KIND_WEAPON_SKILL, 110), "normal weapon skill consumes generic combat intent in the same frame");
    }

    private static function testWeaponSkillFrameInputWaitsForCooldownAndLatches():Void {
        resetManualCooldown();
        var unit:Object = makeUnit();
        unit.主动战技 = {长枪: {名字: "测试战技", 冷却时间: 2500, 消耗hp: 0, 消耗mp: 0}};
        unit.releaseCount = 0;
        unit.释放主动战技 = function():Boolean {
            this.releaseCount++;
            return true;
        };
        var cooldownPort:Object = makeCooldownPort(false, 2200);
        ManualCooldownService.start(ManualCooldownService.WEAPON_SKILL_KEY, 34);

        var waiting:Object = WeaponSkillInputService.updateUnit(unit, true, true, cooldownPort, 120);
        assert(waiting == null, "held weapon-skill input waits while shared cooldown is unavailable");
        assert(unit.releaseCount == 0, "waiting weapon-skill input does not release early");
        assert(unit.__weaponSkillInputConsumed !== true, "waiting weapon-skill input remains armed during the same hold");

        drainManualCooldown();
        var released:Object = WeaponSkillInputService.updateUnit(unit, true, true, cooldownPort, 121);
        assert(released != null && released.released === true, "held weapon-skill input releases when shared cooldown becomes ready");
        assert(unit.releaseCount == 1, "frame input delegates exactly one release when cooldown opens");
        assert(unit.__weaponSkillInputConsumed === true, "successful frame input consumes the current hold");
        assert(!ManualCooldownService.isReady(ManualCooldownService.WEAPON_SKILL_KEY)
            && ManualCooldownService.getSnapshot(ManualCooldownService.WEAPON_SKILL_KEY).totalSteps == Math.ceil(2200 / 33.33333),
            "frame input starts the shared authoritative cooldown using the compatibility duration source");

        WeaponSkillInputService.updateUnit(unit, true, true, cooldownPort, 121);
        assert(unit.releaseCount == 1, "consumed weapon-skill hold does not repeat release");

        WeaponSkillInputService.updateUnit(unit, false, true, cooldownPort, 122);
        drainManualCooldown();
        WeaponSkillInputService.updateUnit(unit, true, true, cooldownPort, 123);
        assert(unit.releaseCount == 2, "key release rearms weapon-skill input for the next hold");
    }

    private static function testWeaponSkillFrameInputConsumesFailedSubweaponAttempt():Void {
        resetManualCooldown();
        var unit:Object = makeUnit();
        unit.主动战技 = {长枪: {名字: "副武器快装", isSubweaponControl: true, 冷却时间: 3000}};
        unit.releaseCount = 0;
        unit.释放主动战技 = function():Boolean {
            this.releaseCount++;
            return false;
        };
        var cooldownPort:Object = makeCooldownPort(false, 3000);

        var failed:Object = WeaponSkillInputService.updateUnit(unit, true, true, cooldownPort, 130);
        assert(failed != null && failed.released === false, "failed subweapon control still records one release attempt");
        assert(unit.__weaponSkillInputConsumed === true, "failed subweapon control consumes the current hold");
        assert(unit.releaseCount == 0, "failed subweapon control does not call direct unit skill release");
        assert(ManualCooldownService.isReady(ManualCooldownService.WEAPON_SKILL_KEY), "subweapon control never starts shared weapon-skill cooldown");
        assert(!UnitActionIntentService.has(unit, UnitActionIntentService.CHANNEL_COMBAT, UnitActionIntentService.KIND_SUBWEAPON_RELOAD, 130), "failed subweapon control leaves no pending combat intent");

        WeaponSkillInputService.updateUnit(unit, true, true, cooldownPort, 131);
        assert(unit.releaseCount == 0, "failed subweapon control does not retry every frame while held");
    }

    private static function testWeaponSkillFrameInputRearmsOnReleaseWhileDisabled():Void {
        resetManualCooldown();
        var unit:Object = makeUnit();
        unit.主动战技 = {长枪: {名字: "测试战技", 冷却时间: 1000}};
        unit.releaseCount = 0;
        unit.释放主动战技 = function():Boolean {
            this.releaseCount++;
            return true;
        };
        unit.__weaponSkillInputConsumed = true;
        var cooldownPort:Object = makeCooldownPort(true, 1000);

        WeaponSkillInputService.updateUnit(unit, false, false, cooldownPort, 140);
        assert(unit.__weaponSkillInputConsumed === false, "key release rearms input even while pause or player-count gate disables triggering");

        WeaponSkillInputService.updateUnit(unit, true, false, cooldownPort, 141);
        assert(unit.releaseCount == 0, "disabled frame input does not release weapon skill");
        assert(unit.__weaponSkillInputConsumed !== true, "disabled held input remains armed for resume");

        WeaponSkillInputService.updateUnit(unit, true, true, cooldownPort, 142);
        assert(unit.releaseCount == 1, "held input releases once after input gate resumes");
    }

    private static function testQuickSkillInputWaitsForCooldownAndLatchesPerSlot():Void {
        resetManualCooldown();
        var unit:Object = makeUnit();
        var view:Object = makeQuickSkillView();
        unit.quickSkillReleaseCount = 0;
        unit.释放技能 = function(skillName:String, mpCost:Number, keyCode:Number):Boolean {
            this.quickSkillReleaseCount++;
            this.lastQuickSkillName = skillName;
            this.lastQuickSkillMp = mpCost;
            this.lastQuickSkillKey = keyCode;
            return true;
        };
        ManualCooldownService.start(ManualCooldownService.quickSkillKey(1), 34);

        var waiting:Object = QuickSkillInputService.updateSlot(unit, 1, true, true, view, 49);
        assert(waiting == null, "held quick-skill input waits while its slot cooldown is unavailable");
        assert(unit.quickSkillReleaseCount == 0, "waiting quick-skill input does not release early");
        assert(unit.__quickSkillInputConsumedSlots[1] !== true, "cooldown wait leaves the quick-skill slot armed");

        drainManualCooldown();
        var released:Object = QuickSkillInputService.updateSlot(unit, 1, true, true, view, 49);
        assert(released != null && released.released === true, "held quick-skill input releases when its cooldown opens");
        assert(unit.quickSkillReleaseCount == 1, "quick-skill slot releases exactly once for one hold");
        assert(unit.lastQuickSkillName == "测试快捷技能1" && unit.lastQuickSkillMp == 11, "quick-skill release keeps slot name and mp cost");
        assert(unit.lastQuickSkillKey == 49, "quick-skill release forwards the live key code");
        assert(!ManualCooldownService.isReady(ManualCooldownService.quickSkillKey(1)), "successful quick skill starts its own authoritative cooldown");

        QuickSkillInputService.updateSlot(unit, 1, true, true, view, 49);
        assert(unit.quickSkillReleaseCount == 1, "consumed quick-skill hold does not repeat after cooldown is forced ready");

        QuickSkillInputService.updateSlot(unit, 1, false, true, view, 49);
        drainManualCooldown();
        QuickSkillInputService.updateSlot(unit, 1, true, true, view, 49);
        assert(unit.quickSkillReleaseCount == 2, "key release rearms the same quick-skill slot");
    }

    private static function testQuickSkillInputConsumesFailedAttempt():Void {
        resetManualCooldown();
        var unit:Object = makeUnit();
        var view:Object = makeQuickSkillView();
        unit.quickSkillReleaseCount = 0;
        unit.释放技能 = function():Boolean {
            this.quickSkillReleaseCount++;
            return false;
        };

        var failed:Object = QuickSkillInputService.updateSlot(unit, 2, true, true, view, 50);
        assert(failed != null && failed.released === false, "failed quick skill records one release attempt");
        assert(unit.__quickSkillInputConsumedSlots[2] === true, "failed quick skill consumes the current slot hold");
        assert(ManualCooldownService.isReady(ManualCooldownService.quickSkillKey(2)), "failed quick skill does not start cooldown");

        QuickSkillInputService.updateSlot(unit, 2, true, true, view, 50);
        assert(unit.quickSkillReleaseCount == 1, "failed quick skill does not retry every frame while held");

        QuickSkillInputService.updateSlot(unit, 2, false, true, view, 50);
        QuickSkillInputService.updateSlot(unit, 2, true, true, view, 50);
        assert(unit.quickSkillReleaseCount == 2, "failed quick skill retries after release and repress");
    }

    private static function testQuickSkillInputRearmsAcrossDisabledFrames():Void {
        resetManualCooldown();
        var unit:Object = makeUnit();
        var view:Object = makeQuickSkillView();
        unit.quickSkillReleaseCount = 0;
        unit.释放技能 = function():Boolean {
            this.quickSkillReleaseCount++;
            return true;
        };
        unit.__quickSkillInputConsumedSlots = [];
        unit.__quickSkillInputConsumedSlots[3] = true;

        QuickSkillInputService.updateSlot(unit, 3, false, false, view, 51);
        assert(unit.__quickSkillInputConsumedSlots[3] === false, "quick-skill release rearms its slot while input is disabled");

        QuickSkillInputService.updateSlot(unit, 3, true, false, view, 51);
        assert(unit.quickSkillReleaseCount == 0, "disabled held quick skill does not release");
        assert(unit.__quickSkillInputConsumedSlots[3] !== true, "disabled held quick skill stays armed for resume");

        QuickSkillInputService.updateSlot(unit, 3, true, true, view, 51);
        assert(unit.quickSkillReleaseCount == 1, "held quick skill releases once when input gate resumes");
    }

    private static function testQuickSkillInputKeepsSlotLatchesIndependent():Void {
        resetManualCooldown();
        var unit:Object = makeUnit();
        var view:Object = makeQuickSkillView();
        unit.quickSkillReleaseCount = 0;
        unit.释放技能 = function(skillName:String):Boolean {
            this.quickSkillReleaseCount++;
            this.lastQuickSkillName = skillName;
            return true;
        };

        QuickSkillInputService.updateSlot(unit, 1, true, true, view, 49);
        QuickSkillInputService.updateSlot(unit, 12, true, true, view, 123);
        assert(unit.quickSkillReleaseCount == 2, "different quick-skill slots may release during the same frame");
        assert(unit.__quickSkillInputConsumedSlots[1] === true && unit.__quickSkillInputConsumedSlots[12] === true, "quick-skill slots keep independent consumed latches");

        QuickSkillInputService.updateSlot(unit, 1, false, true, view, 49);
        drainManualCooldown();
        QuickSkillInputService.updateSlot(unit, 1, true, true, view, 49);
        QuickSkillInputService.updateSlot(unit, 12, true, true, view, 123);
        assert(unit.quickSkillReleaseCount == 3, "rearming one quick-skill slot does not rearm another held slot");
    }

    private static function testQuickSkillInputSyncsLiveKeyLabelAndClearsUnit():Void {
        resetManualCooldown();
        var unit:Object = makeUnit();
        var view:Object = makeQuickSkillView();
        var root:Object = {};
        root.keyshow = function(keyCode:Number):String {
            return "KEY-" + keyCode;
        };

        QuickSkillInputService.syncKeyLabel(view, 4, 52, root);
        assert(view.控制器4.inputOwnedByAS === true, "quick-skill controller is marked as AS-owned display shell");
        assert(view.控制器4.mytext.text == "KEY-52", "quick-skill controller displays the live key binding");

        QuickSkillInputService.syncKeyLabel(view, 4, 90, root);
        assert(view.控制器4.mytext.text == "KEY-90", "quick-skill key label refreshes after runtime remap");

        QuickSkillInputService.updateSlot(unit, 4, false, true, view, 90);
        QuickSkillInputService.clearUnit(unit);
        assert(unit.__quickSkillInputConsumedSlots == undefined, "quick-skill input cleanup removes all per-slot latches");
        assert(QuickSkillInputService.getKeyName(12) == "快捷技能栏键12", "quick-skill key table covers all twelve slots");
    }

    private static function testQuickSkillInputRejectsEmptyAndMalformedSlots():Void {
        resetManualCooldown();
        var unit:Object = makeUnit();
        var view:Object = makeQuickSkillView();
        unit.quickSkillReleaseCount = 0;
        unit.释放技能 = function():Boolean {
            this.quickSkillReleaseCount++;
            return true;
        };

        var emptyNames:Array = [null, undefined, "", "空", "null", "undefined"];
        for (var i:Number = 0; i < emptyNames.length; i++) {
            view.快捷技能栏1 = {是否装备: 1, 已装备名: emptyNames[i], 消耗mp: 10, 冷却时间: 1000};
            var emptyResult:Object = QuickSkillInputService.updateSlot(unit, 1, true, true, view, 49);
            assert(emptyResult == null, "quick-skill input rejects empty sentinel index " + i);
            assert(unit.__quickSkillInputConsumedSlots[1] !== true, "rejected empty slot does not consume input index " + i);
        }

        view.快捷技能栏1 = {是否装备: 0, 已装备名: "残留技能名", 消耗mp: 10, 冷却时间: 1000};
        assert(QuickSkillInputService.updateSlot(unit, 1, true, true, view, 49) == null, "visually empty stale-name slot is rejected");

        view.快捷技能栏1 = {是否装备: 1, 已装备名: "测试快捷技能", 消耗mp: undefined, 冷却时间: 1000};
        assert(QuickSkillInputService.updateSlot(unit, 1, true, true, view, 49) == null, "slot with missing mp cost is rejected");

        view.快捷技能栏1 = {是否装备: 1, 已装备名: "测试快捷技能", 消耗mp: 10, 冷却时间: undefined};
        assert(QuickSkillInputService.updateSlot(unit, 1, true, true, view, 49) == null, "slot with missing cooldown is rejected");
        assert(unit.quickSkillReleaseCount == 0, "empty or malformed slots never reach unit release boundary");
    }

    private static function testSkillReleaseGuardRejectsUnknownSkillsAndInvalidCost():Void {
        var root:Object = {};
        root.根据技能名查找主角技能等级 = function(skillName:String):Number {
            return skillName == "合法技能" ? 3 : 0;
        };
        root.根据技能名查找全部属性 = function(skillName:String):Object {
            return skillName == "合法技能" ? {CD: 1000, MP: 20} : null;
        };

        var valid:Object = SkillReleaseGuard.resolve(root, "合法技能", 20);
        assert(valid != null && valid.skillName == "合法技能" && valid.skillLevel == 3, "release guard accepts learned skill with data");
        assert(valid != null && valid.mpCost == 20, "release guard normalizes valid mp cost");
        assert(SkillReleaseGuard.resolve(root, null, 20) == null, "release guard rejects raw null before string coercion");
        assert(SkillReleaseGuard.resolve(root, "null", 20) == null, "release guard rejects serialized null sentinel");
        assert(SkillReleaseGuard.resolve(root, "不存在的技能", 20) == null, "release guard rejects unknown skill name");
        assert(SkillReleaseGuard.resolve(root, "合法技能", undefined) == null, "release guard rejects missing mp cost");
        assert(SkillReleaseGuard.resolve(root, "合法技能", -1) == null, "release guard rejects negative mp cost");
    }

    private static function testMissingSkillContainerRecoveryUsesCanonicalExit():Void {
        var unit = {攻击模式: "兵器", bonusRestoreCount: 0, animationEndCount: 0};
        unit.根据模式重新读取武器加成 = function(mode:String):Void {
            this.bonusRestoreCount++;
            this.lastBonusMode = mode;
        };
        unit.动画完毕 = function():Void {
            this.animationEndCount++;
        };

        RoutingLifecycle.recoverMissingSkillContainer(unit);
        assert(unit.bonusRestoreCount == 1 && unit.lastBonusMode == "兵器", "missing skill container restores attack-mode bonus");
        assert(unit.animationEndCount == 1, "missing skill container exits through canonical animation end");

        var fallbackUnit = {攻击模式: "空手", 技能名: "坏技能"};
        fallbackUnit.状态改变 = function(stateName:String):Void {
            this.recoveredState = stateName;
        };
        RoutingLifecycle.recoverMissingSkillContainer(fallbackUnit);
        assert(fallbackUnit.技能名 == null && fallbackUnit.recoveredState == "空手站立", "nonstandard unit falls back to safe standing state");
    }

    private static function testQuickSkillInputPreservesTruthyLegacyPorts():Void {
        resetManualCooldown();
        var unit:Object = makeUnit();
        var view:Object = makeQuickSkillView();
        view.进度条5.冷却 = 1;
        unit.释放技能 = function():Number {
            return 1;
        };

        var released:Object = QuickSkillInputService.updateSlot(unit, 5, true, true, view, 53);
        assert(released != null && released.released === true, "quick-skill input preserves truthy legacy release result semantics");
        assert(!ManualCooldownService.isReady(ManualCooldownService.quickSkillKey(5)), "truthy legacy release result starts authoritative cooldown");
    }

    private static function testQuickSkillInputFailsClosedWithoutCooldownStarter():Void {
        resetManualCooldown();
        var unit:Object = makeUnit();
        var view:Object = makeQuickSkillView();
        unit.quickSkillReleaseCount = 0;
        unit.释放技能 = function():Boolean {
            this.quickSkillReleaseCount++;
            return true;
        };
        view.进度条6 = null;

        var result:Object = QuickSkillInputService.updateSlot(unit, 6, true, true, view, 54);
        assert(result != null && result.released === true, "quick-skill input remains reachable when cooldown renderer is unavailable");
        assert(unit.quickSkillReleaseCount == 1, "missing renderer does not block authoritative skill release");
        assert(!ManualCooldownService.isReady(ManualCooldownService.quickSkillKey(6)), "missing renderer still starts authoritative cooldown");
    }

    private static function testManualReloadIntentQueuesForHeldGunStateMachine():Void {
        installMockInventory("火焰喷射器燃料罐", 1);
        var unit:Object = makeUnit();
        LongGunSubWeaponCore.configureUnit(unit, {weapontype: "突击步枪", subweapon: makeSubweapon(false)});
        markSubweaponEmpty(unit, true);
        unit.主动战技 = {长枪: LongGunSubWeaponCore.buildControlSlot(unit.长枪副武器配置)};

        var accepted:Boolean = WeaponSkillInputService.requestSubweaponControl(unit, 200);
        assert(accepted, "manual reload input accepts a valid subweapon reload request");
        assert(UnitActionIntentService.has(unit, UnitActionIntentService.CHANNEL_COMBAT, UnitActionIntentService.KIND_SUBWEAPON_RELOAD, 200), "accepted manual reload input queues generic combat intent");

        var consumed:Object = UnitActionIntentService.take(unit, UnitActionIntentService.CHANNEL_COMBAT, UnitActionIntentService.KIND_SUBWEAPON_RELOAD, 200, false);
        assert(consumed != null && LongGunSubWeaponCore.canReloadManual(unit), "held-gun state machine consumes and revalidates fresh subweapon reload intent");
        assert(!UnitActionIntentService.has(unit, UnitActionIntentService.CHANNEL_COMBAT, UnitActionIntentService.KIND_SUBWEAPON_RELOAD, 200), "subweapon reload intent is cleared on first consumption");
        assert(UnitActionIntentService.take(unit, UnitActionIntentService.CHANNEL_COMBAT, UnitActionIntentService.KIND_SUBWEAPON_RELOAD, 200, false) == null, "subweapon reload intent cannot be consumed twice");
        assert(WeaponSkillInputService.requestSubweaponControl(unit, 200), "clearUnit fixture queues another generic reload intent");
        LongGunSubWeaponCore.clearUnit(unit);
        assert(!UnitActionIntentService.has(unit, UnitActionIntentService.CHANNEL_COMBAT,
                UnitActionIntentService.KIND_SUBWEAPON_RELOAD, 200)
                && _root.存档系统.dirtyMark === false,
            "clearUnit removes queued reload intent without marking persistence dirty");

        restoreMockInventory();
    }

    private static function testPrimaryReloadWinsAndConsumesManualReloadIntent():Void {
        installMockInventory("火焰喷射器燃料罐", 1);
        var unit:Object = makeUnit();
        LongGunSubWeaponCore.configureUnit(unit, {weapontype: "突击步枪", subweapon: makeSubweapon(false)});
        markSubweaponEmpty(unit, true);
        unit.主动战技 = {长枪: LongGunSubWeaponCore.buildControlSlot(unit.长枪副武器配置)};

        assert(WeaponSkillInputService.requestSubweaponControl(unit, 210), "simultaneous R/F fixture queues F combat intent");
        assert(UnitActionIntentService.take(unit, UnitActionIntentService.CHANNEL_COMBAT, UnitActionIntentService.KIND_SUBWEAPON_RELOAD, 210, true) == null, "primary R reload suppresses same-frame F reload intent");
        assert(!UnitActionIntentService.has(unit, UnitActionIntentService.CHANNEL_COMBAT,
                UnitActionIntentService.KIND_SUBWEAPON_RELOAD, 210)
                && _root.存档系统.dirtyMark === false,
            "R priority clears the losing F intent without marking persistence dirty");

        restoreMockInventory();
    }

    private static function testManualReloadIntentExpiresAndRevalidates():Void {
        installMockInventory("火焰喷射器燃料罐", 1);
        var unit:Object = makeUnit();
        LongGunSubWeaponCore.configureUnit(unit, {weapontype: "突击步枪", subweapon: makeSubweapon(false)});
        markSubweaponEmpty(unit, true);
        unit.主动战技 = {长枪: LongGunSubWeaponCore.buildControlSlot(unit.长枪副武器配置)};

        assert(WeaponSkillInputService.requestSubweaponControl(unit, 220), "expiry fixture queues generic reload intent");
        assert(UnitActionIntentService.has(unit, UnitActionIntentService.CHANNEL_COMBAT, UnitActionIntentService.KIND_SUBWEAPON_RELOAD, 222), "subweapon reload intent survives two frames for run-to-walk man initialization");
        assert(UnitActionIntentService.take(unit, UnitActionIntentService.CHANNEL_COMBAT, UnitActionIntentService.KIND_SUBWEAPON_RELOAD, 223, false) == null, "subweapon reload intent expires after the bounded man-ready window");
        assert(!UnitActionIntentService.has(unit, UnitActionIntentService.CHANNEL_COMBAT, UnitActionIntentService.KIND_SUBWEAPON_RELOAD, 223), "expired subweapon reload intent is cleared while failing closed");

        assert(WeaponSkillInputService.requestSubweaponControl(unit, 224), "revalidation fixture queues a fresh generic reload intent");
        unit.man.换弹标签 = true;
        var intent:Object = UnitActionIntentService.take(unit, UnitActionIntentService.CHANNEL_COMBAT, UnitActionIntentService.KIND_SUBWEAPON_RELOAD, 224, false);
        assert(intent != null && !LongGunSubWeaponCore.canReloadManual(unit), "state-machine consumption revalidates current-man reload availability outside generic mailbox");
        assert(!UnitActionIntentService.has(unit, UnitActionIntentService.CHANNEL_COMBAT,
                UnitActionIntentService.KIND_SUBWEAPON_RELOAD, 224)
                && _root.存档系统.dirtyMark === false,
            "failed business revalidation consumes intent without marking persistence dirty");

        restoreMockInventory();
    }

    private static function testCombatIntentPriorityAndKindIsolation():Void {
        var unit:Object = {};
        var subQueued:Boolean = UnitActionIntentService.submit(
            unit,
            UnitActionIntentService.CHANNEL_COMBAT,
            UnitActionIntentService.KIND_SUBWEAPON_RELOAD,
            230,
            1,
            null,
            20
        );
        assert(subQueued, "generic combat mailbox accepts first high-priority intent");

        var normalQueued:Boolean = UnitActionIntentService.submit(
            unit,
            UnitActionIntentService.CHANNEL_COMBAT,
            UnitActionIntentService.KIND_WEAPON_SKILL,
            230,
            1,
            null,
            10
        );
        assert(!normalQueued, "lower-priority combat intent cannot overwrite pending higher-priority intent");
        assert(UnitActionIntentService.take(unit, UnitActionIntentService.CHANNEL_COMBAT, UnitActionIntentService.KIND_WEAPON_SKILL, 230, false) == null, "consumer cannot take another kind from the same combat channel");
        assert(UnitActionIntentService.has(unit, UnitActionIntentService.CHANNEL_COMBAT, UnitActionIntentService.KIND_SUBWEAPON_RELOAD, 230), "kind mismatch leaves pending combat intent intact");
        assert(UnitActionIntentService.take(unit, UnitActionIntentService.CHANNEL_COMBAT, UnitActionIntentService.KIND_SUBWEAPON_RELOAD, 230, false) != null, "matching consumer takes pending combat intent");

        assert(UnitActionIntentService.submit(
            unit,
            UnitActionIntentService.CHANNEL_COMBAT,
            UnitActionIntentService.KIND_SUBWEAPON_RELOAD,
            231,
            2,
            null,
            20
        ), "manual reload can queue before primary reload arbitration");
        assert(UnitActionIntentService.submit(
            unit,
            UnitActionIntentService.CHANNEL_COMBAT,
            UnitActionIntentService.KIND_PRIMARY_RELOAD,
            231,
            2,
            null,
            30
        ), "primary reload overwrites lower-priority F intent while waiting for man readiness");
        assert(UnitActionIntentService.has(unit, UnitActionIntentService.CHANNEL_COMBAT, UnitActionIntentService.KIND_PRIMARY_RELOAD, 233), "one-shot running R survives the bounded man-ready window");
        assert(UnitActionIntentService.take(unit, UnitActionIntentService.CHANNEL_COMBAT, UnitActionIntentService.KIND_PRIMARY_RELOAD, 233, false) != null, "ready held-gun state consumes the preserved running R intent");
    }

    private static function testSubweaponWithoutMoveShootDoesNotFireFromRun():Void {
        var oldShoot:Function = _root.子弹区域shoot传递;
        var oldControlTarget:String = _root.控制目标;
        var previousGameworld:Object = _root.gameworld;
        var shot:Object = null;
        _root.控制目标 = "testUnit";
        _root.gameworld = {};
        _root.gameworld.globalToLocal = function(point:Object):Void {};
        _root.子弹区域shoot传递 = function(props:Object):Void {
            shot = props;
        };

        var unit:Object = makeUnit();
        unit.状态 = "长枪跑";
        unit.移动射击 = false;
        unit.man = makeActionClip(unit, 0, 0, 0, 0);
        LongGunSubWeaponCore.configureUnit(unit, {weapontype: "突击步枪", subweapon: makeSubweapon(false)});

        var ok:Boolean = LongGunSubWeaponCore.fire(unit);
        assert(!ok, "subweapon without move-shoot does not fire from run state");
        assert(unit.状态 == "长枪站立", "subweapon without move-shoot only normalizes run to stand");
        assert(unit.行走冷却帧 == 2, "subweapon without move-shoot protects normalized pose");
        assert(shot == null, "subweapon without move-shoot does not emit bullet while moving");
        assert(unit.长枪副武器状态.loaded == unit.长枪副武器状态.capacity, "subweapon without move-shoot does not consume loaded round while moving");
        assert(unit.长枪.value.subweaponShot == 0, "subweapon without move-shoot does not mutate stored fired count while moving");

        _root.子弹区域shoot传递 = oldShoot;
        _root.控制目标 = oldControlTarget;
        _root.gameworld = previousGameworld;
    }

    private static function testSubweaponCommitRejectsWalkWithoutMoveShoot():Void {
        var oldShoot:Function = _root.子弹区域shoot传递;
        var previousGameworld:Object = _root.gameworld;
        var shot:Object = null;
        _root.gameworld = {};
        _root.gameworld.globalToLocal = function(point:Object):Void {};
        _root.子弹区域shoot传递 = function(props:Object):Void {
            shot = props;
        };

        var unit:Object = makeUnit();
        unit.状态 = "长枪行走";
        unit.移动射击 = false;
        unit.man = makeActionClip(unit, 100, 50, 3, 4);
        LongGunSubWeaponCore.configureUnit(unit, {weapontype: "突击步枪", subweapon: makeSubweapon(false)});
        var props:Object = LongGunSubWeaponCore.prepareManBulletProps(unit, unit.man);
        var muzzle:Object = unit.man.枪.枪.装扮.枪口位置;

        var ok:Boolean = unit.长枪副武器射击(muzzle, props);
        assert(!ok, "subweapon commit rejects walk state without move-shoot");
        assert(shot == null, "subweapon commit does not emit bullet while walking without move-shoot");
        assert(unit.长枪副武器状态.loaded == unit.长枪副武器状态.capacity, "subweapon commit does not consume loaded round while walking without move-shoot");
        assert(unit.长枪副武器.value.shot == 0, "subweapon commit does not increment virtual shot while walking without move-shoot");

        _root.子弹区域shoot传递 = oldShoot;
        _root.gameworld = previousGameworld;
    }

    private static function testFireFromRunWithMoveShootPlaysDirectionalAnimation():Void {
        var oldShoot:Function = _root.子弹区域shoot传递;
        var oldControlTarget:String = _root.控制目标;
        var previousGameworld:Object = _root.gameworld;
        var shot:Object = null;
        _root.控制目标 = "testUnit";
        _root.gameworld = {};
        _root.gameworld.globalToLocal = function(point:Object):Void {};
        _root.子弹区域shoot传递 = function(props:Object):Void {
            shot = props;
        };

        var unit:Object = makeUnit();
        unit.状态 = "长枪跑";
        unit.移动射击 = true;
        unit.下行 = true;
        unit.man = makeActionClip(unit, 0, 0, 0, 0);
        var oldMan:Object = unit.man;
        var newMan:Object = makeActionClip(unit, 200, 100, 7, 9);
        unit.状态改变 = function(state:String):Void {
            this.状态 = state;
            this.man = newMan;
            var job:Object = this.__stateTransitionJob;
            if (job != undefined && job.callback != undefined) {
                var cb:Function = job.callback;
                job.callback = undefined;
                job.gotoLabel = undefined;
                cb(this);
            }
        };
        LongGunSubWeaponCore.configureUnit(unit, {weapontype: "突击步枪", subweapon: makeSubweapon(false)});

        var ok:Boolean = LongGunSubWeaponCore.fire(unit);
        assert(ok, "subweapon fire succeeds from long-gun run state when move-shoot is enabled");
        assert(unit.状态 == "长枪行走", "subweapon fire normalizes run to walk when move-shoot is enabled");
        assert(unit.行走冷却帧 == 2, "subweapon fire protects normalized pose from next walk tick");
        assert(unit.man !== oldMan, "subweapon fire waits for refreshed man after pose transition");
        assert(oldMan.playFrame == undefined, "subweapon fire does not play stale run man");
        assert(unit.man.playFrame == "下射击", "subweapon fire plays directional shoot animation");
        assert(shot != null && shot.角度偏移 == 30, "subweapon fire passes directional angle offset");
        assert(shot != null && shot.shootX == 207, "subweapon fire reads refreshed muzzle X");
        assert(shot != null && shot.shootY == 109, "subweapon fire reads refreshed muzzle Y");
        assert(unit.长枪副武器状态.loaded == unit.长枪副武器状态.capacity - 1, "subweapon fire consumes one loaded round");
        assert(unit.长枪.value.subweaponShot == 1, "subweapon fire stores fired count on long gun value");
        assertSubweaponSnapshots(unit, 1, "subweapon fire keeps ammo snapshots consistent");

        _root.子弹区域shoot传递 = oldShoot;
        _root.控制目标 = oldControlTarget;
        _root.gameworld = previousGameworld;
    }

    private static function testFireFromManUsesPassedCurrentMan():Void {
        var oldShoot:Function = _root.子弹区域shoot传递;
        var oldControlTarget:String = _root.控制目标;
        var previousGameworld:Object = _root.gameworld;
        var shot:Object = null;
        _root.控制目标 = "testUnit";
        _root.gameworld = {};
        _root.gameworld.globalToLocal = function(point:Object):Void {};
        _root.子弹区域shoot传递 = function(props:Object):Void {
            shot = props;
        };

        var unit:Object = makeUnit();
        unit.状态 = "长枪站立";
        unit.下行 = true;
        unit.man = makeActionClip(unit, 0, 0, 0, 0);
        var staleMan:Object = unit.man;
        var currentMan:Object = makeActionClip(unit, 300, 120, 11, 13);
        LongGunSubWeaponCore.configureUnit(unit, {weapontype: "突击步枪", subweapon: makeSubweapon(false)});

        var ok:Boolean = LongGunSubWeaponCore.fireFromMan(unit, currentMan);
        assert(ok, "subweapon fireFromMan succeeds on current man");
        assert(staleMan.playFrame == undefined, "subweapon fireFromMan ignores stale unit.man animation");
        assert(currentMan.playFrame == "下射击", "subweapon fireFromMan plays passed man animation");
        assert(shot != null && shot.shootX == 311, "subweapon fireFromMan reads passed man muzzle X");
        assert(shot != null && shot.shootY == 133, "subweapon fireFromMan reads passed man muzzle Y");

        _root.子弹区域shoot传递 = oldShoot;
        _root.控制目标 = oldControlTarget;
        _root.gameworld = previousGameworld;
    }

    private static function testShootInitSubweaponBindingRequestsCurrentMan():Void {
        installMockInventory("主武器弹匣", 3, "火焰喷射器燃料罐", 1);
        var oldShoot:Function = _root.子弹区域shoot传递;
        var oldControlTarget:String = _root.控制目标;
        var previousGameworld:Object = _root.gameworld;
        var shot:Object = null;
        _root.控制目标 = "testUnit";
        _root.gameworld = {};
        _root.gameworld.globalToLocal = function(point:Object):Void {};
        _root.子弹区域shoot传递 = function(props:Object):Void {
            shot = props;
        };

        var unit:Object = makeUnit();
        unit.状态 = "长枪站立";
        unit.下行 = true;
        unit.长枪数据 = {weapontype: "突击步枪"};
        unit.长枪弹匣容量 = 30;
        var staleMan:MovieClip = _root.createEmptyMovieClip("__subweaponBindingStaleMan" + getTimer(), _root.getNextHighestDepth());
        var currentMan:Object = makeActionClip(unit, 400, 150, 9, 12);
        unit.man = currentMan;
        LongGunSubWeaponCore.configureUnit(unit, {weapontype: "突击步枪", subweapon: makeSubweapon(false)});

        var weaponData:Object = {
            interval: 300,
            clipname: "主武器弹匣",
            singleshoot: false,
            split: 1,
            diffusion: 3,
            sound: "test.wav",
            muzzle: "",
            bullet: "测试子弹",
            velocity: 30,
            bullethit: "",
            power: 100,
            bulletsize: 50,
            impact: 5,
            targethit: ""
        };
        ShootInitCore.initWeaponSystem(staleMan, unit, {
            weaponType: "长枪",
            isDualGun: false,
            weaponData: weaponData,
            extraParams: {}
        });

        assert(typeof staleMan.开始副武器换弹 == "function", "ShootInitCore binds explicit subweapon reload entry after man initialization");
        staleMan.开始副武器射击();

        assert(staleMan.playFrame == undefined, "ShootInitCore subweapon binding does not play bound stale man");
        assert(currentMan.playFrame == "下射击", "ShootInitCore subweapon binding plays current unit.man");
        assert(shot != null && shot.shootX == 409, "ShootInitCore subweapon binding uses current muzzle X");
        assert(shot != null && shot.shootY == 162, "ShootInitCore subweapon binding uses current muzzle Y");

        var reloadStarted:Boolean = staleMan.开始副武器换弹();
        assert(reloadStarted, "initialized man subweapon reload entry starts reload on current unit.man");
        assert(currentMan.换弹标签 === true && currentMan.playFrame == "换弹匣"
                && _root.存档系统.dirtyMark === false,
            "reload entry owns current man timeline without committing persistence early");

        _root.子弹区域shoot传递 = oldShoot;
        _root.控制目标 = oldControlTarget;
        _root.gameworld = previousGameworld;
        staleMan.removeMovieClip();
        restoreMockInventory();
    }

    private static function testSubweaponContinuousShootRefreshesManEachTick():Void {
        var oldShoot:Function = _root.子弹区域shoot传递;
        var oldControlTarget:String = _root.控制目标;
        var previousGameworld:Object = _root.gameworld;
        EnhancedCooldownWheel.I().reset();

        var shots:Array = [];
        _root.控制目标 = "testUnit";
        _root.gameworld = {};
        _root.gameworld.globalToLocal = function(point:Object):Void {};
        _root.子弹区域shoot传递 = function(props:Object):Void {
            shots.push({shootX: props.shootX, shootY: props.shootY});
        };

        var unit:Object = makeUnit();
        unit.状态 = "长枪站立";
        unit.下行 = true;
        unit.man = makeActionClip(unit, 10, 20, 1, 2);
        var firstMan:Object = unit.man;
        var sub:Object = makeSubweapon(false);
        sub.cd = 34;
        LongGunSubWeaponCore.configureUnit(unit, {weapontype: "突击步枪", subweapon: sub});

        var ok:Boolean = LongGunSubWeaponCore.fire(unit);
        var secondMan:Object = makeActionClip(unit, 100, 200, 3, 4);
        unit.man = secondMan;
        for (var i:Number = 0; i < 4; i++) {
            EnhancedCooldownWheel.I().tick();
        }

        assert(ok, "subweapon continuous shoot starts from current man");
        assert(shots.length >= 2, "subweapon continuous shoot emits a second scheduled shot");
        assert(firstMan.playFrame == "下射击", "initial subweapon shot plays initial man");
        assert(secondMan.playFrame == "下射击", "scheduled subweapon shot plays refreshed man");
        assert(shots[0].shootX == 11, "initial subweapon shot uses initial muzzle X");
        assert(shots[0].shootY == 22, "initial subweapon shot uses initial muzzle Y");
        assert(shots[1].shootX == 103, "scheduled subweapon shot uses refreshed muzzle X");
        assert(shots[1].shootY == 204, "scheduled subweapon shot uses refreshed muzzle Y");
        assert(unit.长枪.value.subweaponShot >= 2, "scheduled subweapon shot commits ammo on refreshed man");

        _root.子弹区域shoot传递 = oldShoot;
        _root.控制目标 = oldControlTarget;
        _root.gameworld = previousGameworld;
        EnhancedCooldownWheel.I().reset();
    }

    private static function testLongCooldownSubweaponRecoilEndsBeforeFireGate():Void {
        var oldShoot:Function = _root.子弹区域shoot传递;
        var oldControlTarget:String = _root.控制目标;
        var previousGameworld:Object = _root.gameworld;
        EnhancedCooldownWheel.I().reset();

        var shotCount:Number = 0;
        _root.控制目标 = "testUnit";
        _root.gameworld = {};
        _root.gameworld.globalToLocal = function(point:Object):Void {};
        _root.子弹区域shoot传递 = function(props:Object):Void {
            shotCount++;
        };

        var unit:Object = makeUnit();
        unit.状态 = "长枪行走";
        unit.移动射击 = true;
        unit.man = makeActionClip(unit, 10, 20, 1, 2);
        var sub:Object = makeSubweapon(false);
        sub.cd = 3000;
        LongGunSubWeaponCore.configureUnit(unit, {weapontype: "突击步枪", subweapon: sub});

        var ok:Boolean = LongGunSubWeaponCore.fire(unit);
        assert(ok && shotCount == 1, "long-cooldown subweapon commits its first shot");
        assert(unit.副武器射击中 === true && unit.射击最大后摇中 === true, "long-cooldown subweapon initially enters shooting recoil state");
        for (var i:Number = 0; i < 10; i++) {
            EnhancedCooldownWheel.I().tick();
        }
        assert(unit.副武器射击中 === false && unit.射击最大后摇中 === false, "subweapon movement recoil ends at the 300ms cap");
        assert(unit.长枪副武器状态.nextFireTime > getTimer(), "full subweapon fire-rate gate remains active after movement recoil ends");
        assert(!LongGunSubWeaponCore.fire(unit) && shotCount == 1, "recoil release cannot bypass the remaining subweapon fire-rate gate");

        org.flashNight.arki.unit.Action.Shoot.ShootCore.cleanup(unit);
        _root.子弹区域shoot传递 = oldShoot;
        _root.控制目标 = oldControlTarget;
        _root.gameworld = previousGameworld;
        EnhancedCooldownWheel.I().reset();
    }

    private static function testSubweaponEventIsolationAndInterval():Void {
        var oldShoot:Function = _root.子弹区域shoot传递;
        var previousGameworld:Object = _root.gameworld;
        var shot:Object = null;
        _root.gameworld = {};
        _root.gameworld.globalToLocal = function(point:Object):Void {};
        _root.子弹区域shoot传递 = function(props:Object):Void {
            shot = props;
        };

        var unit:Object = makeUnit();
        unit.状态 = "长枪站立";
        unit.man = makeActionClip(unit, 50, 40, 5, 6);
        LongGunSubWeaponCore.configureUnit(unit, {weapontype: "突击步枪", subweapon: makeSubweapon(false)});

        var mainProcessCount:Number = 0;
        var subProcessCount:Number = 0;
        var mainUpdateCount:Number = 0;
        var subUpdateCount:Number = 0;
        unit.dispatcher.subscribe("processShot", function(owner:MovieClip, weaponType:String) {
            if (weaponType == "长枪") mainProcessCount++;
            if (weaponType == "长枪副武器") subProcessCount++;
        });
        unit.dispatcher.subscribe("updateBullet", function(owner:MovieClip, shootStateName:String, magazineRemaining:Number, playerBulletField:String, weaponType:String) {
            if (weaponType == "长枪") mainUpdateCount++;
            if (weaponType == "长枪副武器") subUpdateCount++;
        });

        var ok:Boolean = LongGunSubWeaponCore.fire(unit);

        assert(ok, "subweapon lane fire succeeds through ShootCore");
        assert(mainProcessCount == 0, "subweapon processShot does not masquerade as long-gun shot");
        assert(subProcessCount == 1, "subweapon processShot publishes subweapon weaponType");
        assert(mainUpdateCount == 0, "subweapon updateBullet does not masquerade as long-gun update");
        assert(subUpdateCount == 1, "subweapon updateBullet publishes subweapon weaponType");
        assert(shot != null && shot.发射间隔毫秒 == unit.长枪副武器配置.cd, "subweapon lane uses config.cd as fire interval");
        assert(unit.长枪副武器.value.shot == 1, "subweapon lane increments virtual shot through processShot");
        assert(unit.长枪副武器状态.loaded == unit.长枪副武器状态.capacity - 1, "subweapon lane syncs loaded snapshot after processShot");
        assertSubweaponSnapshots(unit, 1, "subweapon lane fire keeps ammo snapshots consistent");

        _root.子弹区域shoot传递 = oldShoot;
        _root.gameworld = previousGameworld;
    }

    private static function testEquipmentFireIntentMainLongGunGate():Void {
        var unit:Object = makeUnit();
        unit.攻击模式 = "长枪";

        assert(EquipmentFireIntent.isMainLongGunProcessShot(unit, "长枪"), "fire intent accepts main long-gun processShot");
        assert(!EquipmentFireIntent.isMainLongGunProcessShot(unit, "长枪副武器"), "fire intent rejects subweapon processShot");

        assert(EquipmentFireIntent.isMainLongGunUpdateBullet(unit, "子弹数", "长枪"), "fire intent accepts typed main long-gun updateBullet");
        assert(!EquipmentFireIntent.isMainLongGunUpdateBullet(unit, "子弹数_2", "长枪副武器"), "fire intent rejects typed subweapon updateBullet");
        assert(EquipmentFireIntent.isMainLongGunUpdateBullet(unit, "子弹数", undefined), "fire intent accepts legacy main long-gun updateBullet");
        assert(!EquipmentFireIntent.isMainLongGunUpdateBullet(unit, "子弹数_2", undefined), "fire intent rejects legacy non-main updateBullet");

        unit.攻击模式 = "手枪";
        assert(!EquipmentFireIntent.isMainLongGunProcessShot(unit, "长枪"), "fire intent rejects processShot outside long-gun mode");
        assert(!EquipmentFireIntent.isMainLongGunUpdateBullet(unit, "子弹数", "长枪"), "fire intent rejects updateBullet outside long-gun mode");

        var publishCount:Number = 0;
        var publishedWeaponType:String = null;
        var publishedBulletField:String = null;
        unit.dispatcher.subscribe("updateBullet", function(owner:MovieClip, shootStateName:String, magazineRemaining:Number, playerBulletField:String, weaponType:String) {
            publishCount++;
            publishedBulletField = playerBulletField;
            publishedWeaponType = weaponType;
        });
        EquipmentFireIntent.publishMainLongGunUpdateBullet(unit.dispatcher, unit, "长枪射击中", 7);

        assert(publishCount == 1, "fire intent publishes one updateBullet event");
        assert(publishedBulletField == "子弹数", "fire intent publish uses main bullet field");
        assert(publishedWeaponType == "长枪", "fire intent publish carries main long-gun weaponType");
    }

    private static function testSubweaponEmptyDoesNotTriggerMainReload():Void {
        var unit:Object = makeUnit();
        unit.man = makeActionClip(unit, 0, 0, 0, 0);
        unit.man.mainReloadCount = 0;
        unit.man.开始换弹 = function():Void {
            this.mainReloadCount++;
        };
        LongGunSubWeaponCore.configureUnit(unit, {weapontype: "突击步枪", subweapon: makeSubweapon(false)});
        markSubweaponEmpty(unit, true);

        var ok:Boolean = LongGunSubWeaponCore.fire(unit);

        assert(!ok, "empty subweapon K fire is rejected");
        assert(unit.man.mainReloadCount == 0, "empty subweapon K fire does not trigger main reload");
        assert(unit.长枪.value.shot == 0, "empty subweapon K fire does not mutate main long-gun shot");
    }

    private static function testDeferredFireAbortDoesNotCommitCostOrCooldown():Void {
        installMockInventory("火焰喷射器燃料罐", 1);
        EnhancedCooldownWheel.I().reset();

        var oldShoot:Function = _root.子弹区域shoot传递;
        var previousGameworld:Object = _root.gameworld;
        var shot:Object = null;
        _root.gameworld = {};
        _root.gameworld.globalToLocal = function(point:Object):Void {};
        _root.子弹区域shoot传递 = function(props:Object):Void {
            shot = props;
        };

        var unit:Object = makeUnit();
        unit.状态 = "长枪跑";
        unit.移动射击 = true;
        unit.man = makeActionClip(unit, 0, 0, 0, 0);
        var badMan:Object = makeActionClip(unit, undefined, 0, 0, 0);
        unit.状态改变 = function(state:String):Void {
            this.状态 = state;
            this.man = badMan;
            var job:Object = this.__stateTransitionJob;
            if (job != undefined && job.callback != undefined) {
                var cb:Function = job.callback;
                job.callback = undefined;
                job.gotoLabel = undefined;
                cb(this);
            }
        };
        LongGunSubWeaponCore.configureUnit(unit, {weapontype: "突击步枪", subweapon: makeSubweapon(true)});

        var ok:Boolean = LongGunSubWeaponCore.fire(unit);
        for (var i:Number = 0; i < 12; i++) {
            EnhancedCooldownWheel.I().tick();
        }

        assert(ok, "deferred subweapon fire is accepted before pose callback resolves");
        assert(shot == null, "deferred subweapon fire aborts without shooting when refreshed man has no muzzle");
        assert(unit.长枪副武器状态.loaded == unit.长枪副武器状态.capacity, "deferred abort does not consume loaded round");
        assert(unit.mp == 500, "deferred abort does not consume mp");
        assert(ItemUtil.getTotal("火焰喷射器燃料罐") == 1
                && _root.存档系统.dirtyMark === false,
            "deferred abort neither consumes onFire reserve nor marks persistence dirty");
        assert(unit.长枪副武器状态.nextFireTime == 0, "deferred abort clears tentative cooldown");
        assert(unit.__subweaponPendingFireCdUntil == undefined, "deferred abort clears pending fire lock");

        shot = null;
        unit.man = makeActionClip(unit, 100, 50, 3, 4);
        unit.状态改变 = function(state:String):Void {
            this.状态 = state;
        };
        var retryOk:Boolean = LongGunSubWeaponCore.fire(unit);
        assert(retryOk, "subweapon can fire again after deferred abort");
        assert(shot != null && shot.shootX == 103, "retry after deferred abort emits bullet from valid muzzle");
        assert(unit.mp == 400, "successful retry commits mp cost");
        assert(ItemUtil.getTotal("火焰喷射器燃料罐") == 0
                && _root.存档系统.dirtyMark === true,
            "successful retry commits onFire reserve and marks persistence dirty");

        _root.子弹区域shoot传递 = oldShoot;
        _root.gameworld = previousGameworld;
        EnhancedCooldownWheel.I().reset();
        restoreMockInventory();
    }

    private static function testDeferredFireInvalidatedStateDoesNotCommit():Void {
        installMockInventory("火焰喷射器燃料罐", 1);
        EnhancedCooldownWheel.I().reset();

        var oldShoot:Function = _root.子弹区域shoot传递;
        var previousGameworld:Object = _root.gameworld;
        var shot:Object = null;
        _root.gameworld = {};
        _root.gameworld.globalToLocal = function(point:Object):Void {};
        _root.子弹区域shoot传递 = function(props:Object):Void {
            shot = props;
        };

        var unit:Object = makeUnit();
        unit.状态 = "长枪跑";
        unit.移动射击 = true;
        unit.man = makeActionClip(unit, 0, 0, 0, 0);
        var newMan:Object = makeActionClip(unit, 120, 80, 6, 8);
        unit.状态改变 = function(state:String):Void {
            this.状态 = state;
            this.man = newMan;
            this.攻击模式 = "兵器";
            var job:Object = this.__stateTransitionJob;
            if (job != undefined && job.callback != undefined) {
                var cb:Function = job.callback;
                job.callback = undefined;
                job.gotoLabel = undefined;
                cb(this);
            }
        };
        LongGunSubWeaponCore.configureUnit(unit, {weapontype: "突击步枪", subweapon: makeSubweapon(true)});

        var ok:Boolean = LongGunSubWeaponCore.fire(unit);

        assert(ok, "deferred subweapon fire request is accepted before attack mode invalidation");
        assert(shot == null, "deferred subweapon fire aborts when attack mode changes before commit");
        assert(unit.长枪副武器状态.loaded == unit.长枪副武器状态.capacity, "invalidated deferred fire keeps loaded round");
        assert(unit.mp == 500, "invalidated deferred fire does not consume mp");
        assert(ItemUtil.getTotal("火焰喷射器燃料罐") == 1
                && _root.存档系统.dirtyMark === false,
            "invalidated deferred fire neither consumes reserve nor marks persistence dirty");
        assert(unit.长枪副武器状态.nextFireTime == 0, "invalidated deferred fire clears tentative cooldown");
        assert(unit.__subweaponPendingFireCdUntil == undefined, "invalidated deferred fire clears pending lock");

        _root.子弹区域shoot传递 = oldShoot;
        _root.gameworld = previousGameworld;
        EnhancedCooldownWheel.I().reset();
        restoreMockInventory();
    }

    private static function testManualReloadRejectsUnavailableCurrentManWithoutPendingState():Void {
        installMockInventory("火焰喷射器燃料罐", 1);
        EnhancedCooldownWheel.I().reset();

        var unit:Object = makeUnit();
        unit.状态 = "长枪跑";
        unit.移动射击 = false;
        unit.man = makeReloadClip(unit);
        var notReadyMan:Object = {};
        unit.状态改变 = function(state:String):Void {
            this.状态 = state;
            this.man = notReadyMan;
        };
        LongGunSubWeaponCore.configureUnit(unit, {weapontype: "突击步枪", subweapon: makeSubweapon(false)});
        markSubweaponEmpty(unit, true);

        var ok:Boolean = LongGunSubWeaponCore.startManualReloadAnimation(unit);
        var readyMan:Object = makeReloadClip(unit);
        LongGunSubWeaponCore.clearUnit(unit);
        unit.man = readyMan;
        for (var i:Number = 0; i < 8; i++) {
            EnhancedCooldownWheel.I().tick();
        }

        assert(!ok, "subweapon manual reload fails closed when refreshed current man cannot play reload animation");
        assert(LongGunSubWeaponCore.getReloadRequest(notReadyMan) == null, "unavailable current man receives no reload request");
        assert(notReadyMan.换弹标签 !== true, "unavailable current man receives no reload tag");
        assert(unit.__subweaponManualReloadLock == undefined, "synchronous manual reload creates no unit-level movement lock");
        assert(unit.__subweaponDeferredReloadRetries == undefined, "synchronous manual reload creates no deferred retry state");
        assert(!LongGunSubWeaponCore.hasSubweapon(unit), "clearUnit removes subweapon after synchronous reload rejection");
        assert(readyMan.playFrame == undefined, "rejected manual reload schedules no delayed mutation after clearUnit");
        assert(readyMan.换弹标签 !== true && _root.存档系统.dirtyMark === false,
            "rejected manual reload cannot revive or mark persistence on a later current man");

        EnhancedCooldownWheel.I().reset();
        restoreMockInventory();
    }

    private static function testManualReload():Void {
        installMockInventory("火焰喷射器燃料罐", 2);
        var unit:Object = makeUnit();
        LongGunSubWeaponCore.configureUnit(unit, {weapontype: "突击步枪", subweapon: makeSubweapon(false)});
        markSubweaponEmpty(unit, true);

        var ok:Boolean = LongGunSubWeaponCore.reloadManual(unit);
        assert(ok, "manual reload succeeds when reserve is available");
        assert(unit.长枪副武器状态.loaded == unit.长枪副武器状态.capacity, "manual reload refills loaded state");
        assert(unit.长枪副武器状态.groupPaid == true, "manual reload marks group paid on commit");
        assert(ItemUtil.getTotal("火焰喷射器燃料罐") == 1
                && _root.存档系统.dirtyMark === true,
            "manual reload consumes one reserve clip and marks persistence dirty on commit");
        assert(unit.当前弹夹副武器已发射数 == 0, "manual reload resets fired count");
        assert(unit.长枪.value.subweaponShot == 0, "manual reload resets stored fired count");
        assertSubweaponSnapshots(unit, 0, "manual reload keeps ammo snapshots consistent");
        restoreMockInventory();
    }

    private static function testManualReloadFromRunNormalizesPose():Void {
        installMockInventory("火焰喷射器燃料罐", 2);
        var unit:Object = makeUnit();
        unit.状态 = "长枪跑";
        unit.移动射击 = false;
        unit.man = makeReloadClip(unit);
        var oldMan:Object = unit.man;
        var newMan:Object = makeReloadClip(unit);
        unit.状态改变 = function(state:String):Void {
            this.状态 = state;
            this.man = newMan;
            var job:Object = this.__stateTransitionJob;
            if (job != undefined && job.callback != undefined) {
                var cb:Function = job.callback;
                job.callback = undefined;
                job.gotoLabel = undefined;
                cb(this);
            }
        };
        LongGunSubWeaponCore.configureUnit(unit, {weapontype: "突击步枪", subweapon: makeSubweapon(false)});
        markSubweaponEmpty(unit, true);

        var ok:Boolean = LongGunSubWeaponCore.startManualReloadAnimation(unit);
        assert(ok, "subweapon manual reload starts from long-gun run state");
        assert(unit.状态 == "长枪站立", "subweapon manual reload normalizes run to stand");
        assert(unit.行走冷却帧 == 2, "subweapon manual reload protects normalized pose from next walk tick");
        assert(unit.man !== oldMan, "subweapon manual reload waits for refreshed man after pose transition");
        assert(!LongGunSubWeaponCore.isManualReloadRequest(oldMan), "subweapon manual reload does not mark stale run man");
        assert(LongGunSubWeaponCore.isManualReloadRequest(unit.man), "subweapon manual reload marks manual reload request");
        assert(unit.man.subweaponManualReload == undefined, "subweapon manual reload does not use legacy manual marker");
        assert(unit.__subweaponManualReloadLock == undefined, "subweapon manual reload does not create unit-level movement lock");
        assert(unit.__subweaponDeferredReloadRetries == undefined, "subweapon manual reload does not create deferred retry state");
        assert(!LongGunSubWeaponCore.canReloadManual(unit), "current man reload request rejects duplicate manual reload");
        assert(unit.man.playFrame == "换弹匣" && _root.存档系统.dirtyMark === false,
            "subweapon manual reload enters animation without committing persistence early");
        restoreMockInventory();
    }

    private static function testManualReloadUsesCurrentManLifecycle():Void {
        installMockInventory("火焰喷射器燃料罐", 2);
        var unit:Object = makeUnit();
        unit.man = makeReloadClip(unit);
        LongGunSubWeaponCore.configureUnit(unit, {weapontype: "突击步枪", subweapon: makeSubweapon(false)});
        markSubweaponEmpty(unit, true);

        var ok:Boolean = LongGunSubWeaponCore.startManualReloadAnimation(unit);
        assert(ok, "subweapon manual reload starts on current pose");
        assert(LongGunSubWeaponCore.isManualReloadRequest(unit.man), "current man owns manual reload request during animation");
        assert(unit.man.换弹标签 === true, "current man reload tag gates movement during animation");
        assert(unit.__subweaponManualReloadLock == undefined, "manual reload lifecycle has no unit-level movement lock");

        ReloadManager.finishReload(unit.man);
        assert(LongGunSubWeaponCore.getReloadRequest(unit.man) == null, "finish reload clears current man reload request");
        assert(unit.man.换弹标签 == false && _root.存档系统.dirtyMark === false,
            "finish without commit clears current man reload tag and leaves persistence clean");
        restoreMockInventory();
    }

    private static function testManualReloadInterruptionDoesNotLeakUnitState():Void {
        installMockInventory("火焰喷射器燃料罐", 2);
        var unit:Object = makeUnit();
        var reloadMan:Object = makeReloadClip(unit);
        unit.man = reloadMan;
        LongGunSubWeaponCore.configureUnit(unit, {weapontype: "突击步枪", subweapon: makeSubweapon(false)});
        markSubweaponEmpty(unit, true);

        var ok:Boolean = LongGunSubWeaponCore.startManualReloadAnimation(unit);
        assert(ok && LongGunSubWeaponCore.isManualReloadRequest(reloadMan), "manual reload interruption fixture starts on original man");

        unit.状态 = "技能";
        unit.man = makeReloadClip(unit);
        assert(LongGunSubWeaponCore.getReloadRequest(unit.man) == null, "replacement man does not inherit interrupted manual reload request");
        assert(unit.man.换弹标签 !== true, "replacement man is not movement-locked by interrupted reload");
        assert(unit.__subweaponManualReloadLock == undefined, "interrupted manual reload leaves no unit-level lock");
        assert(unit.__subweaponDeferredReloadRetries == undefined, "interrupted manual reload leaves no deferred retry state");

        unit.状态 = "长枪站立";
        assert(LongGunSubWeaponCore.canReloadManual(unit)
                && _root.存档系统.dirtyMark === false,
            "interrupted man can start a fresh reload without a phantom persistence write");
        restoreMockInventory();
    }

    private static function testManualReloadAnimationCommit():Void {
        installMockInventory("火焰喷射器燃料罐", 2);
        var unit:Object = makeUnit();
        unit.长枪 = {value: {shot: 3, reloadCount: 0}};
        unit.长枪弹匣容量 = 30;
        unit.长枪属性 = {reloadType: "tube", reloadPenalty: 99};
        unit.man = makeReloadClip(unit);

        LongGunSubWeaponCore.configureUnit(unit, {weapontype: "突击步枪", subweapon: makeSubweapon(false)});
        markSubweaponEmpty(unit, true);

        assert(LongGunSubWeaponCore.canReloadManual(unit), "manual reload precheck passes before animation");
        LongGunSubWeaponCore.setManualReloadRequest(unit.man, unit);
        unit.man.换弹标签 = true;

        ReloadManager.initReloadBurden(unit.man, 42, 50, 43, 74, [51, 56, 64]);
        assert(unit.man.perRoundReload == false, "subweapon manual reload bypasses tube per-round path");
        assert(unit.man.reloadBurden == 25, "subweapon manual reload uses manual reload burden");
        assert(unit.man.reloadFrameControlRequest === true, "subweapon manual reload enables frame control");

        ReloadManager.reloadMagazine(unit.man, unit, _root);
        assert(unit.长枪.value.shot == 3, "subweapon animation commit does not reset main weapon shot");
        assert(unit.长枪副武器状态.loaded == unit.长枪副武器状态.capacity, "subweapon animation commit refills loaded state");
        assert(unit.长枪副武器状态.groupPaid == true, "subweapon animation commit marks group paid");
        assert(unit.长枪.value.subweaponShot == 0, "subweapon animation commit resets stored fired count");
        assert(ItemUtil.getTotal("火焰喷射器燃料罐") == 1
                && _root.存档系统.dirtyMark === true,
            "subweapon animation commit consumes one reserve clip and marks persistence dirty");
        assertSubweaponSnapshots(unit, 0, "subweapon animation commit keeps ammo snapshots consistent");

        ReloadManager.finishReload(unit.man);
        assert(LongGunSubWeaponCore.getReloadRequest(unit.man) == null, "finish reload clears subweapon reload request");
        assert(unit.man.subweaponManualReload == undefined, "finish reload clears legacy subweapon manual marker");
        assert(unit.man.换弹标签 == false, "finish reload clears reload tag");
        assert(unit.man.stopFrame == "空闲", "finish reload returns timeline to idle");
        restoreMockInventory();
    }

    private static function testLinkedReload():Void {
        installMockInventory("火焰喷射器燃料罐", 1);
        var unit:Object = makeUnit();
        LongGunSubWeaponCore.configureUnit(unit, {weapontype: "突击步枪", subweapon: makeSubweapon(false)});
        markSubweaponEmpty(unit, true);

        var ok:Boolean = LongGunSubWeaponCore.reloadLinked(unit);
        assert(ok, "linked reload succeeds with reserve commit");
        assert(unit.长枪副武器状态.loaded == unit.长枪副武器状态.capacity, "linked reload refills loaded state");
        assert(unit.长枪副武器状态.groupPaid == true, "linked reload marks group paid on commit");
        assert(unit.长枪.value.subweaponShot == 0, "linked reload resets stored fired count");
        assert(ItemUtil.getTotal("火焰喷射器燃料罐") == 0
                && _root.存档系统.dirtyMark === true,
            "linked reload consumes reserve and marks persistence dirty on commit");
        assertSubweaponSnapshots(unit, 0, "linked reload keeps ammo snapshots consistent");
        restoreMockInventory();
    }

    private static function testSubweaponTacticalRecoveryAccumulatesOnPaidReload():Void {
        installMockInventory("火焰喷射器燃料罐", 1);
        var unit:Object = makeUnit();
        unit.被动技能.枪械师 = {启用: true, 等级: 10};
        LongGunSubWeaponCore.configureUnit(unit, {weapontype: "突击步枪", subweapon: makeSubweapon(false)});
        LongGunSubWeaponCore.setFiredCount(unit, 2);
        installMockHero(unit);

        var ok:Boolean = LongGunSubWeaponCore.reloadManual(unit);

        assert(ok, "subweapon tactical recovery allows paid manual reload");
        assert(unit.长枪副武器.value.reloadCount == 3, "subweapon tactical recovery stores recovered partial magazine");
        assert(unit.长枪副武器状态.reloadCount == 3, "subweapon tactical recovery mirrors recovered count to state");
        assert(unit.长枪.value.subweaponReloadCount == 3, "subweapon tactical recovery mirrors recovered count to long gun value");
        assert(ItemUtil.getTotal("火焰喷射器燃料罐") == 0
                && _root.存档系统.dirtyMark === true,
            "paid tactical recovery consumes reserve and marks persistence dirty when pool is short");
        assertSubweaponSnapshots(unit, 0, "subweapon paid tactical recovery reload keeps snapshots consistent");

        LongGunSubWeaponCore.configureUnit(unit, {weapontype: "突击步枪", subweapon: makeSubweapon(false)});
        assert(unit.长枪副武器.value.reloadCount == 3, "subweapon tactical reload pool survives configureUnit");
        assert(unit.长枪副武器状态.reloadCount == 3, "subweapon tactical reload pool state survives configureUnit");

        restoreMockHero();
        restoreMockInventory();
    }

    private static function testSubweaponTacticalRecoveryFreeReloadWithoutReserve():Void {
        installMockInventory("火焰喷射器燃料罐", 0);
        var unit:Object = makeUnit();
        unit.被动技能.枪械师 = {启用: true, 等级: 10};
        LongGunSubWeaponCore.configureUnit(unit, {weapontype: "突击步枪", subweapon: makeSubweapon(false)});
        LongGunSubWeaponCore.setFiredCount(unit, 2);
        unit.长枪副武器.value.reloadCount = 2;
        unit.长枪副武器状态.reloadCount = 2;
        installMockHero(unit);

        assert(LongGunSubWeaponCore.canReloadManual(unit), "subweapon tactical recovery free pool opens manual reload without reserve");
        var ok:Boolean = LongGunSubWeaponCore.reloadManual(unit);

        assert(ok, "subweapon tactical recovery completes free reload without reserve");
        assert(unit.长枪副武器.value.reloadCount == 0, "subweapon tactical free reload spends recovered pool");
        assert(unit.长枪副武器状态.reloadCount == 0, "subweapon tactical free reload syncs spent pool to state");
        assert(unit.长枪.value.subweaponReloadCount == 0, "subweapon tactical free reload syncs spent pool to long gun value");
        assert(ItemUtil.getTotal("火焰喷射器燃料罐") == 0
                && _root.存档系统.dirtyMark === false,
            "subweapon tactical free reload neither consumes reserve nor marks persistence dirty");
        assertSubweaponSnapshots(unit, 0, "subweapon tactical free reload keeps snapshots consistent");

        restoreMockHero();
        restoreMockInventory();
    }

    private static function testLinkedReloadRequiresReserve():Void {
        installMockInventory("火焰喷射器燃料罐", 0);
        var unit:Object = makeUnit();
        LongGunSubWeaponCore.configureUnit(unit, {weapontype: "突击步枪", subweapon: makeSubweapon(false)});
        markSubweaponEmpty(unit, true);

        var ok:Boolean = LongGunSubWeaponCore.reloadLinked(unit);
        assert(!ok, "linked reload fails when reserve is unavailable");
        assert(unit.长枪副武器状态.loaded == 0, "linked reload does not refill without reserve");
        assert(unit.长枪副武器状态.groupPaid == true
                && _root.存档系统.dirtyMark === false,
            "failed linked reload keeps previous payment state without marking persistence dirty");
        restoreMockInventory();
    }

    private static function testMainReloadSubmitFailurePreservesStateAndOnlyPublishesCommittedLoss():Void {
        installMockInventory("主武器弹匣", 1);
        var unit:Object = makeUnit();
        unit.被动技能.枪械师 = {启用:true, 等级:10};
        unit.长枪 = {value:{shot:29, reloadCount:7}};
        unit.长枪弹匣容量 = 30;
        unit.长枪属性 = {reloadType:"normal", reloadPenalty:50,
            bullet:"普通", split:1};
        unit.man = makeReloadClip(unit);
        installMockHero(unit);
        var receipts:Array = [];
        PlayerAssetTransaction.resetForTests();
        PlayerAssetTransaction.setTestSink(function(receipt:Object):Void {
            receipts.push(receipt);
        });

        ReloadManager.startReload(unit.man, unit, _root);
        assert(unit.man.playFrame == "换弹匣",
            "main reload race fixture passes animation-time reserve precheck");
        // 模拟动画期间库存被另一权威操作消耗；最终 submit 必须 fail-closed。
        _root.物品栏.背包.items[0] = null;
        ReloadManager.reloadMagazine(unit.man, unit, _root);
        assert(unit.长枪.value.shot == 29,
            "failed main reload submit keeps fired-count authority unchanged");
        assert(unit.长枪.value.reloadCount == 7,
            "failed main reload submit restores tactical recovery pool");
        assert(receipts.length == 0 && _root.存档系统.dirtyMark === false,
            "failed main reload submit emits no phantom loss receipt or dirty mark");

        _root.物品栏.背包.items[0] = {name:"主武器弹匣", value:1};
        ReloadManager.reloadMagazine(unit.man, unit, _root);
        assert(unit.长枪.value.shot == 0,
            "successful retry refills only after authoritative reserve submit");
        assert(ItemUtil.getTotal("主武器弹匣") == 0
                && _root.存档系统.dirtyMark === true,
            "successful retry consumes exactly one reserve magazine and marks persistence dirty");
        assert(receipts.length == 1 && receipts[0].effects.length == 1
                && receipts[0].effects[0].direction == "loss"
                && receipts[0].effects[0].source == "reload"
                && receipts[0].effects[0].count == 1,
            "successful reload publishes one exact loss receipt");

        PlayerAssetTransaction.resetForTests();
        restoreMockHero();
        restoreMockInventory();
    }

    private static function testTubeReloadConsumesReserveExactlyOnce():Void {
        installMockInventory("主武器弹匣", 1);
        var unit:Object = makeUnit();
        unit.长枪 = {value:{shot:2, reloadCount:0}};
        unit.长枪弹匣容量 = 5;
        unit.长枪属性 = {reloadType:"tube", reloadPenalty:50,
            bullet:"普通", split:1};
        unit.man = makeReloadClip(unit);
        unit.man.perRoundReload = true;
        unit.man.reloadFrameControlActive = true;
        unit.man.reloadEndFrame = 74;
        unit.man.reloadLoopBackFrame = 51;
        installMockHero(unit);
        var receipts:Array = [];
        PlayerAssetTransaction.resetForTests();
        PlayerAssetTransaction.setTestSink(function(receipt:Object):Void {
            receipts.push(receipt);
        });

        ReloadManager.handleReloadGate(unit.man);
        assert(unit.长枪.value.shot == 1 && unit.长枪.value.reloadCount == 4,
            "tube reload first cycle injects one round from committed pool");
        assert(ItemUtil.getTotal("主武器弹匣") == 0
                && _root.存档系统.dirtyMark === true,
            "tube reload acquires its pool by consuming one reserve magazine and marks persistence dirty");
        assert(receipts.length == 1 && receipts[0].effects.length == 1
                && receipts[0].effects[0].direction == "loss"
                && receipts[0].effects[0].count == 1,
            "tube reload publishes reserve loss once when pool is acquired");

        ReloadManager.handleReloadGate(unit.man);
        assert(unit.长枪.value.shot == 0 && unit.长枪.value.reloadCount == 3,
            "tube reload later cycle consumes existing pool without another reserve");
        assert(receipts.length == 1,
            "tube reload later cycle does not duplicate loss receipt");

        PlayerAssetTransaction.resetForTests();
        restoreMockHero();
        restoreMockInventory();
    }

    private static function testReloadKeyMarksCombinedReloadWhenBothNeedAmmo():Void {
        installMockInventory("火焰喷射器燃料罐", 2, "主武器弹匣", 1);
        var unit:Object = makeUnit();
        unit.长枪 = {value: {shot: 3, reloadCount: 0}};
        unit.长枪弹匣容量 = 30;
        unit.长枪属性 = {reloadType: "normal", reloadPenalty: 50};
        unit.man = makeReloadClip(unit);
        LongGunSubWeaponCore.configureUnit(unit, {weapontype: "突击步枪", subweapon: makeSubweapon(false)});
        markSubweaponEmpty(unit, true);
        installMockHero(unit);

        ReloadManager.startReload(unit.man, unit, _root);
        assert(LongGunSubWeaponCore.isLinkedReloadRequest(unit.man), "R marks combined reload request when main and subweapon both need ammo");
        assert(!LongGunSubWeaponCore.isManualReloadRequest(unit.man), "combined R reload keeps main reload path");
        assert(unit.man.subweaponLinkedReload == undefined, "combined R reload does not use legacy linked marker");
        assert(unit.man.subweaponManualReload == undefined, "combined R reload does not use legacy manual marker");
        assert(unit.man.playFrame == "换弹匣", "combined R reload enters main reload animation");

        ReloadManager.reloadMagazine(unit.man, unit, _root);
        assert(unit.长枪.value.shot == 0, "combined R reload refills main weapon");
        assert(unit.长枪副武器状态.loaded == unit.长枪副武器状态.capacity, "combined R reload refills subweapon");
        assert(ItemUtil.getTotal("主武器弹匣") == 0, "combined R reload consumes main reserve");
        assert(ItemUtil.getTotal("火焰喷射器燃料罐") == 1
                && _root.存档系统.dirtyMark === true,
            "combined R reload consumes subweapon reserve and marks persistence dirty");
        assertSubweaponSnapshots(unit, 0, "combined R reload keeps ammo snapshots consistent");

        restoreMockHero();
        restoreMockInventory();
    }

    private static function testGunslingerLevel9StillLinksPartialSubweaponReload():Void {
        installMockInventory("火焰喷射器燃料罐", 2, "主武器弹匣", 1);
        var unit:Object = makeUnit();
        unit.被动技能.枪械师 = {启用: true, 等级: 9};
        unit.长枪 = {value: {shot: 3, reloadCount: 0}};
        unit.长枪弹匣容量 = 30;
        unit.长枪属性 = {reloadType: "normal", reloadPenalty: 50};
        unit.man = makeReloadClip(unit);
        LongGunSubWeaponCore.configureUnit(unit, {weapontype: "突击步枪", subweapon: makeSubweapon(false)});
        LongGunSubWeaponCore.setFiredCount(unit, 2);
        installMockHero(unit);

        ReloadManager.startReload(unit.man, unit, _root);
        assert(LongGunSubWeaponCore.isLinkedReloadRequest(unit.man), "gunslinger level 9 still links partial subweapon reload");

        ReloadManager.reloadMagazine(unit.man, unit, _root);
        assert(unit.长枪副武器状态.loaded == unit.长枪副武器状态.capacity, "gunslinger level 9 linked reload refills partial subweapon");
        assert(ItemUtil.getTotal("火焰喷射器燃料罐") == 1
                && _root.存档系统.dirtyMark === true,
            "gunslinger level 9 linked reload consumes reserve and marks persistence dirty");
        assertSubweaponSnapshots(unit, 0, "gunslinger level 9 linked reload keeps snapshots consistent");

        restoreMockHero();
        restoreMockInventory();
    }

    private static function testGunslingerLevel10SkipsLinkedReloadWhenSubweaponNotEmpty():Void {
        installMockInventory("火焰喷射器燃料罐", 2, "主武器弹匣", 1);
        var unit:Object = makeUnit();
        unit.被动技能.枪械师 = {启用: true, 等级: 10};
        unit.长枪 = {value: {shot: 3, reloadCount: 0}};
        unit.长枪弹匣容量 = 30;
        unit.长枪属性 = {reloadType: "normal", reloadPenalty: 50};
        unit.man = makeReloadClip(unit);
        LongGunSubWeaponCore.configureUnit(unit, {weapontype: "突击步枪", subweapon: makeSubweapon(false)});
        LongGunSubWeaponCore.setFiredCount(unit, 2);
        installMockHero(unit);

        ReloadManager.startReload(unit.man, unit, _root);
        assert(!LongGunSubWeaponCore.isLinkedReloadRequest(unit.man), "gunslinger level 10 keeps non-empty subweapon out of main reload");
        assert(unit.man.playFrame == "换弹匣", "gunslinger level 10 still starts main reload");

        ReloadManager.reloadMagazine(unit.man, unit, _root);
        assert(unit.长枪.value.shot == 0, "gunslinger level 10 reload refills main weapon");
        assert(unit.长枪副武器状态.loaded == 3, "gunslinger level 10 keeps existing subweapon loaded rounds");
        assert(ItemUtil.getTotal("火焰喷射器燃料罐") == 2
                && _root.存档系统.dirtyMark === true,
            "gunslinger level 10 preserves subweapon reserve while main reload marks persistence dirty");
        assertSubweaponSnapshots(unit, 2, "gunslinger level 10 keeps subweapon snapshots unchanged");

        restoreMockHero();
        restoreMockInventory();
    }

    private static function testReloadKeyStartsSubweaponWhenMainFull():Void {
        installMockInventory("火焰喷射器燃料罐", 2);
        var unit:Object = makeUnit();
        unit.长枪 = {value: {shot: 0, reloadCount: 0}};
        unit.长枪弹匣容量 = 30;
        unit.长枪属性 = {reloadType: "normal", reloadPenalty: 100};
        unit.man = makeReloadClip(unit);

        LongGunSubWeaponCore.configureUnit(unit, {weapontype: "突击步枪", subweapon: makeSubweapon(false)});
        markSubweaponEmpty(unit, true);
        installMockHero(unit);

        ReloadManager.startReload(unit.man, unit, _root);
        assert(LongGunSubWeaponCore.isManualReloadRequest(unit.man), "R starts subweapon reload request when main weapon is full");
        assert(unit.man.subweaponManualReload == undefined, "R subweapon reload does not use legacy manual marker");
        assert(unit.man.playFrame == "换弹匣", "R subweapon reload enters reload animation");

        ReloadManager.reloadMagazine(unit.man, unit, _root);
        assert(unit.长枪副武器状态.loaded == unit.长枪副武器状态.capacity, "R subweapon reload refills loaded state");
        assert(ItemUtil.getTotal("火焰喷射器燃料罐") == 1
                && _root.存档系统.dirtyMark === true,
            "R subweapon reload consumes reserve and marks persistence dirty on commit");
        assertSubweaponSnapshots(unit, 0, "R subweapon reload keeps ammo snapshots consistent");

        restoreMockHero();
        restoreMockInventory();
    }

    private static function testCombinedReloadBurdenAddsSubweaponBurden():Void {
        var unit:Object = makeUnit();
        unit.长枪 = {value: {shot: 3, reloadCount: 0}};
        unit.长枪弹匣容量 = 30;
        unit.长枪属性 = {reloadType: "normal", reloadPenalty: 50};
        unit.man = makeReloadClip(unit);
        LongGunSubWeaponCore.configureUnit(unit, {weapontype: "突击步枪", subweapon: makeSubweapon(false)});

        ReloadManager.initReloadBurden(unit.man, 42, 50, 43, 74, [51, 56, 64]);
        assert(unit.man.reloadBurden == 150, "main-only reload burden uses long gun burden");

        ReloadManager.finishReload(unit.man);
        unit.man = makeReloadClip(unit);
        LongGunSubWeaponCore.setLinkedReloadRequest(unit.man, unit);
        ReloadManager.initReloadBurden(unit.man, 42, 50, 43, 74, [51, 56, 64]);
        assert(unit.man.reloadBurden == 175, "combined reload burden adds subweapon burden");
    }

    private static function testNonHeroRollReloadRefillsSubweaponWithoutInventory():Void {
        installMockInventory("火焰喷射器燃料罐", 0);
        var unit:Object = makeUnit();
        unit._name = "allyUnit";
        unit.长枪 = {value: {shot: 3, reloadCount: 0}};
        unit.手枪 = {value: {shot: 2}};
        unit.手枪2 = {value: {shot: 1}};
        LongGunSubWeaponCore.configureUnit(unit, {weapontype: "突击步枪", subweapon: makeSubweapon(false)});
        markSubweaponEmpty(unit, false);
        var previousControlTarget:String = _root.控制目标;
        _root.控制目标 = "heroUnit";

        SkillReloadCore.reloadAllWeapons(unit);

        assert(unit.长枪.value.shot == 0, "non-hero roll reload refills long gun without reserve");
        assert(unit.手枪.value.shot == 0, "non-hero roll reload refills pistol");
        assert(unit.手枪2.value.shot == 0, "non-hero roll reload refills second pistol");
        assert(unit.长枪副武器状态.loaded == unit.长枪副武器状态.capacity, "non-hero roll reload refills subweapon without reserve");
        assert(unit.长枪副武器状态.groupPaid == true, "non-hero roll reload marks free subweapon group paid");
        assert(ItemUtil.getTotal("火焰喷射器燃料罐") == 0
                && _root.存档系统.dirtyMark === false,
            "non-hero roll reload neither consumes player reserve nor marks persistence dirty");
        assertSubweaponSnapshots(unit, 0, "non-hero roll reload keeps ammo snapshots consistent");
        _root.控制目标 = previousControlTarget;
        restoreMockInventory();
    }

    private static function testHeroRollReloadRefillsSubweaponWhenMainFull():Void {
        installMockInventory("火焰喷射器燃料罐", 1);
        var unit:Object = makeUnit();
        unit._name = "heroUnit";
        unit.长枪 = {value: {shot: 0}};
        unit.长枪属性 = {clipname: "主武器弹匣"};
        unit.手枪 = {value: {shot: 0}};
        unit.手枪属性 = {clipname: "手枪弹匣"};
        unit.手枪2 = {value: {shot: 0}};
        unit.手枪2属性 = {clipname: "手枪弹匣"};
        LongGunSubWeaponCore.configureUnit(unit, {weapontype: "突击步枪", subweapon: makeSubweapon(false)});
        markSubweaponEmpty(unit, false);
        installMockHero(unit);

        SkillReloadCore.reloadAllWeapons(unit);

        assert(unit.长枪.value.shot == 0, "hero roll reload keeps full long gun");
        assert(unit.长枪副武器状态.loaded == unit.长枪副武器状态.capacity, "hero roll reload refills subweapon when main is full");
        assert(unit.长枪副武器状态.groupPaid == true, "hero roll reload marks linked subweapon group paid");
        assert(ItemUtil.getTotal("火焰喷射器燃料罐") == 0
                && _root.存档系统.dirtyMark === true,
            "hero roll reload consumes one subweapon reserve and marks persistence dirty");
        assertSubweaponSnapshots(unit, 0, "hero roll reload keeps ammo snapshots consistent");
        restoreMockHero();
        restoreMockInventory();
    }

    private static function testTooltipRendersSubweapon():Void {
        var result:Array = TooltipTextBuilder.buildSubweaponInfo(makeSubweapon(true));
        var joined:String = result.join("");

        assertContains(joined, TooltipConstants.LBL_SUBWEAPON, "tooltip renders subweapon block");
        assertNotContains(joined, TooltipConstants.LBL_ACTIVE_SKILL, "tooltip does not label subweapon as active skill");
        assertContains(joined, "火焰喷射器燃料罐", "tooltip shows subweapon ammo");
        assertContains(joined, "破击", "tooltip shows damage type");
        assertContains(joined, "100", "tooltip shows mp cost");
    }

    private static function markSubweaponEmpty(unit:Object, groupPaid:Boolean):Void {
        LongGunSubWeaponCore.setFiredCount(unit, unit.长枪副武器状态.capacity);
        unit.长枪副武器状态.groupPaid = groupPaid;
    }

    private static function assertSubweaponSnapshots(unit:Object, fired:Number, msg:String):Void {
        var loaded:Number = unit.长枪副武器状态.capacity - fired;
        assert(LongGunSubWeaponCore.getFiredCount(unit) == fired, msg + ": fired count");
        assert(unit.长枪副武器.value.shot == fired, msg + ": virtual shot");
        assert(unit.当前弹夹副武器已发射数 == fired, msg + ": legacy fired count");
        assert(unit.长枪.value.subweaponShot == fired, msg + ": stored mirror");
        assert(unit.长枪副武器状态.loaded == loaded, msg + ": loaded snapshot");
        assert(unit.subWeapon.loaded == loaded, msg + ": subWeapon loaded snapshot");
    }

    private static function makeSubweapon(onFire:Boolean):Object {
        return {
            name: "测试副武器",
            controlName: "测试副武器",
            description: "测试副武器说明。",
            cd: 3000,
            consumeMode: onFire ? "onFire" : "onLoadGroup",
            consumeTiming: onFire ? "onFire" : "onReloadCommit",
            mp: 100,
            power: 1000,
            capacity: 5,
            initialLoaded: 5,
            reserveName: "火焰喷射器燃料罐",
            bullet: "测试榴弹",
            sound: "test.wav",
            split: 1,
            diffusion: 3,
            velocity: 30,
            range: 50,
            impact: 5,
            damageType: "破击",
            magicType: "生化"
        };
    }

    private static function makeUnit():Object {
        var unit:Object = {
            _name: "testUnit",
            _x: 10,
            _y: 20,
            hp: 1000,
            mp: 500,
            Z轴坐标: 0,
            攻击模式: "长枪",
            状态: "长枪站立",
            man: {},
            enableShoot: true,
            dispatcher: new EventDispatcher(),
            动作A: false,
            动作B: true,
            上下移动射击: false,
            射击最大后摇中: false,
            长枪: {value: {shot: 0, reloadCount: 0}},
            被动技能: {冲击连携: {启用: true, 等级: 10}}
        };
        unit.状态改变 = function(state:String):Void {
            this.状态 = state;
        };
        unit.dispatcher.subscribe("processShot", FireEventComponent.processShot, unit);
        return unit;
    }

    private static function makeActionClip(parent:Object, worldX:Number, worldY:Number, muzzleX:Number, muzzleY:Number):Object {
        var clip:Object = {_parent: parent, 射击许可标签: true, 换弹标签: false, 射击速度: 300, 剩余弹匣数: 0, 是否单发: false};
        clip.gotoAndPlay = function(frame:String):Void {
            this.playFrame = frame;
        };
        if (worldX != undefined) {
            var holder:Object = {worldX: worldX, worldY: worldY};
            holder.localToGlobal = function(point:Object):Void {
                point.x += this.worldX;
                point.y += this.worldY;
            };
            holder.枪口位置 = {_x: muzzleX, _y: muzzleY};
            holder.枪口位置._parent = holder;
            clip.枪 = {枪: {装扮: holder}};
        }
        return clip;
    }

    private static function makeReloadClip(parent:Object):Object {
        var clip:Object = {_parent: parent, 使用弹匣名称: "主武器弹匣", 剩余弹匣数: 9};
        clip.开始换弹 = function():Void {};
        clip.换弹匣 = function():Void {};
        clip.结束换弹 = function():Void {};
        clip.gotoAndPlay = function(frame:String):Void {
            this.playFrame = frame;
        };
        clip.gotoAndStop = function(frame:String):Void {
            this.stopFrame = frame;
        };
        return clip;
    }

    private static var manualCooldownQueue:Array = [];

    private static function resetManualCooldown():Void {
        manualCooldownQueue = [];
        ManualCooldownService.resetForTests();
        ManualCooldownService.setSchedulerForTests(function(callback:Function):Void {
            manualCooldownQueue.push(callback);
        });
    }

    private static function drainManualCooldown():Void {
        var guard:Number = 0;
        while (manualCooldownQueue.length > 0 && guard++ < 10000) {
            var callback = manualCooldownQueue.shift();
            callback();
        }
    }

    private static function makeCooldownPort(ready:Boolean, cooldownTime:Number):Object {
        var port:Object = {
            ready: ready,
            cooldownTime: cooldownTime,
            renderer: {冷却: ready}
        };
        port.getCooldownTime = function(skill:Object):Number {
            return this.cooldownTime;
        };
        port.bindRenderer = function():Void {
            ManualCooldownService.bindRenderer(ManualCooldownService.WEAPON_SKILL_KEY, this.renderer);
        };
        return port;
    }

    private static function makeQuickSkillView():Object {
        var view:Object = {__skillInputFixture:true};
        for (var slotIndex:Number = 1; slotIndex <= QuickSkillInputService.SLOT_COUNT; slotIndex++) {
            view["快捷技能栏" + slotIndex] = {
                是否装备: 1,
                已装备名: "测试快捷技能" + slotIndex,
                消耗mp: 10 + slotIndex,
                冷却时间: 1000 + slotIndex
            };

            var cooldownBar:Object = {
                冷却: true,
                startCount: 0,
                lastCooldown: 0
            };
            cooldownBar.冷却开始 = function(cooldownTime:Number):Void {
                this.startCount++;
                this.lastCooldown = cooldownTime;
                this.冷却 = false;
            };
            view["进度条" + slotIndex] = cooldownBar;
            view["控制器" + slotIndex] = {mytext: {text: ""}};
        }
        return view;
    }

    private static var oldInventory:Object;
    private static var oldCollection:Object;
    private static var oldEquipmentDict:Object;
    private static var oldMaterialDict:Object;
    private static var oldInformationDict:Object;
    private static var oldSaveSystem:Object;
    private static var oldSaveSystemWasPresent:Boolean;
    private static var oldGameworld:Object;
    private static var oldControlTarget:String;

    private static function installMockInventory(itemName:String, count:Number, itemName2:String, count2:Number):Void {
        oldInventory = _root.物品栏;
        oldCollection = _root.收集品栏;
        oldEquipmentDict = ItemUtil.equipmentDict;
        oldMaterialDict = ItemUtil.materialDict;
        oldInformationDict = ItemUtil.informationMaxValueDict;
        oldSaveSystemWasPresent = _root.hasOwnProperty("存档系统");
        oldSaveSystem = _root.存档系统;

        ItemUtil.equipmentDict = {};
        ItemUtil.materialDict = {};
        ItemUtil.informationMaxValueDict = {};
        // ItemUtil 的提交路径以真实 `_root.存档系统` 为权威；测试库存只在自身
        // fixture 生命周期内提供 owner，避免依赖 TestLoader 是否装载完整存档系统。
        _root.存档系统 = {dirtyMark:false};

        var backpack:Object = {items: []};
        backpack.items[0] = {name: itemName, value: count};
        if (itemName2 != undefined && itemName2 != null && itemName2 != "") {
            backpack.items[1] = {name: itemName2, value: count2};
        }
        backpack.getIndexes = function():Array {
            var result:Array = [];
            for (var i:String in this.items) {
                if (this.items[i] != null && this.items[i].value > 0) result.push(Number(i));
            }
            return result;
        };
        backpack.getItem = function(index:Number):Object {
            return this.items[index];
        };
        backpack.addValue = function(index:Number, delta:Number):Void {
            this.items[index].value += delta;
            if (this.items[index].value <= 0) this.items[index] = null;
        };
        backpack.remove = function(index:Number):Void {
            this.items[index] = null;
        };

        var emptyInventory:Object = {};
        emptyInventory.getIndexes = function():Array { return []; };
        emptyInventory.getItem = function(index:Number):Object { return null; };
        emptyInventory.addValue = function(index:Number, delta:Number):Void {};
        emptyInventory.remove = function(index:Number):Void {};

        var zeroCollection:Object = {};
        zeroCollection.getValue = function(name:String):Number { return 0; };
        zeroCollection.addValue = function(name:String, delta:Number):Void {};

        _root.物品栏 = {背包: backpack, 药剂栏: emptyInventory};
        _root.收集品栏 = {材料: zeroCollection, 情报: zeroCollection};
    }

    private static function restoreMockInventory():Void {
        _root.物品栏 = oldInventory;
        _root.收集品栏 = oldCollection;
        ItemUtil.equipmentDict = oldEquipmentDict;
        ItemUtil.materialDict = oldMaterialDict;
        ItemUtil.informationMaxValueDict = oldInformationDict;
        if (oldSaveSystemWasPresent) {
            _root.存档系统 = oldSaveSystem;
        } else {
            delete _root.存档系统;
        }
        oldSaveSystem = undefined;
        oldSaveSystemWasPresent = false;
    }

    private static function installMockHero(unit:Object):Void {
        oldGameworld = _root.gameworld;
        oldControlTarget = _root.控制目标;
        _root.gameworld = {};
        _root.控制目标 = unit._name;
        _root.gameworld[unit._name] = unit;
    }

    private static function restoreMockHero():Void {
        _root.gameworld = oldGameworld;
        _root.控制目标 = oldControlTarget;
    }

    private static function assert(cond:Boolean, msg:String):Void {
        testsRun++;
        if (cond) {
            testsPassed++;
            trace("[PASS] " + msg);
        } else {
            testsFailed++;
            trace("[FAIL] " + msg);
        }
    }

    private static function assertContains(haystack:String, needle:String, msg:String):Void {
        testsRun++;
        if (haystack != null && haystack.indexOf(needle) >= 0) {
            testsPassed++;
            trace("[PASS] " + msg);
        } else {
            testsFailed++;
            trace("[FAIL] " + msg + " '" + needle + "' not found");
        }
    }

    private static function assertNotContains(haystack:String, needle:String, msg:String):Void {
        testsRun++;
        if (haystack == null || haystack.indexOf(needle) < 0) {
            testsPassed++;
            trace("[PASS] " + msg);
        } else {
            testsFailed++;
            trace("[FAIL] " + msg + " '" + needle + "' was found but should not be");
        }
    }
}
