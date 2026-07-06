import org.flashNight.arki.item.equipment.SubweaponDataUtil;
import org.flashNight.arki.unit.Action.Shoot.LongGunSubWeaponCore;
import org.flashNight.arki.unit.Action.Shoot.ReloadManager;
import org.flashNight.arki.unit.Action.Skill.SkillReloadCore;
import org.flashNight.arki.unit.Action.Skill.WeaponSkillInputService;
import org.flashNight.arki.item.ItemUtil;
import org.flashNight.gesh.tooltip.TooltipConstants;
import org.flashNight.gesh.tooltip.TooltipTextBuilder;

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
        testControlSlotMarker();
        testWeaponSkillInputBypassesSharedCooldownForSubweapon();
        testWeaponSkillInputKeepsSharedCooldownForNormalSkill();
        testFireFromRunPlaysDirectionalAnimation();
        testFireFromManUsesPassedCurrentMan();
        testManualReload();
        testManualReloadFromRunNormalizesPose();
        testManualReloadMovementLockClearsOnFinish();
        testManualReloadAnimationCommit();
        testLinkedReload();
        testLinkedReloadRequiresReserve();
        testReloadKeyMarksCombinedReloadWhenBothNeedAmmo();
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
        assert(unit.副武器子弹威力 == 1250, "impact chain level 10 applies 25 percent subweapon bonus");
        assert(unit.副武器伤害类型 == "破击", "configureUnit writes damage type field");
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
        var unit:Object = makeUnit();
        LongGunSubWeaponCore.configureUnit(unit, {weapontype: "突击步枪", subweapon: makeSubweapon(false)});
        unit.主动战技 = {长枪: LongGunSubWeaponCore.buildControlSlot(unit.长枪副武器配置)};
        unit.releaseCount = 0;
        unit.释放主动战技 = function():Boolean {
            this.releaseCount++;
            return true;
        };
        installMockHero(unit);
        installWeaponSkillInputRootState();

        var controller:Object = makeSkillController("", false, 3000);
        assert(WeaponSkillInputService.canTrigger(controller), "subweapon control bypasses shared active-skill cooldown gate without visible skill UI");
        var result:Object = WeaponSkillInputService.release(controller);
        assert(result.released === true, "subweapon control release succeeds through input service");
        assert(result.isSubweaponControl === true, "subweapon control result keeps semantic marker");
        assert(result.startSharedCooldown === false, "subweapon control does not start shared active-skill cooldown");
        assert(unit.releaseCount == 1, "subweapon control delegates to unit release once");

        restoreWeaponSkillInputRootState();
        restoreMockHero();
    }

    private static function testWeaponSkillInputKeepsSharedCooldownForNormalSkill():Void {
        var unit:Object = makeUnit();
        unit.主动战技 = {长枪: {名字: "测试战技", 冷却时间: 2500, 消耗hp: 0, 消耗mp: 0}};
        unit.releaseCount = 0;
        unit.释放主动战技 = function():Boolean {
            this.releaseCount++;
            return true;
        };
        installMockHero(unit);
        installWeaponSkillInputRootState();

        var blockedController:Object = makeSkillController("测试战技", false, 2200);
        assert(!WeaponSkillInputService.canTrigger(blockedController), "normal weapon skill waits for shared active-skill cooldown");

        var readyController:Object = makeSkillController("测试战技", true, 2200);
        assert(WeaponSkillInputService.canTrigger(readyController), "normal weapon skill triggers when shared cooldown is ready");
        var result:Object = WeaponSkillInputService.release(readyController);
        assert(result.released === true, "normal weapon skill release succeeds through input service");
        assert(result.isSubweaponControl === false, "normal weapon skill result is not subweapon control");
        assert(result.startSharedCooldown === true, "normal weapon skill starts shared active-skill cooldown");
        assert(result.cooldownTime == 2200, "normal weapon skill uses UI cooldown time for visual bar");
        assert(unit.releaseCount == 1, "normal weapon skill delegates to unit release once");

        restoreWeaponSkillInputRootState();
        restoreMockHero();
    }

    private static function testFireFromRunPlaysDirectionalAnimation():Void {
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
        assert(ok, "subweapon fire succeeds from long-gun run state");
        assert(unit.状态 == "长枪站立", "subweapon fire normalizes run to stand when move-shoot is disabled");
        assert(unit.行走冷却帧 == 2, "subweapon fire protects normalized pose from next walk tick");
        assert(unit.man !== oldMan, "subweapon fire waits for refreshed man after pose transition");
        assert(oldMan.playFrame == undefined, "subweapon fire does not play stale run man");
        assert(unit.man.playFrame == "下射击", "subweapon fire plays directional shoot animation");
        assert(shot != null && shot.角度偏移 == 30, "subweapon fire passes directional angle offset");
        assert(shot != null && shot.shootX == 207, "subweapon fire reads refreshed muzzle X");
        assert(shot != null && shot.shootY == 109, "subweapon fire reads refreshed muzzle Y");
        assert(unit.长枪副武器状态.loaded == unit.长枪副武器状态.capacity - 1, "subweapon fire consumes one loaded round");

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

    private static function testManualReload():Void {
        installMockInventory("火焰喷射器燃料罐", 2);
        var unit:Object = makeUnit();
        LongGunSubWeaponCore.configureUnit(unit, {weapontype: "突击步枪", subweapon: makeSubweapon(false)});
        unit.长枪副武器状态.loaded = 0;
        unit.长枪副武器状态.groupPaid = true;
        unit.当前弹夹副武器已发射数 = unit.长枪副武器状态.capacity;

        var ok:Boolean = LongGunSubWeaponCore.reloadManual(unit);
        assert(ok, "manual reload succeeds when reserve is available");
        assert(unit.长枪副武器状态.loaded == unit.长枪副武器状态.capacity, "manual reload refills loaded state");
        assert(unit.长枪副武器状态.groupPaid == true, "manual reload marks group paid on commit");
        assert(ItemUtil.getTotal("火焰喷射器燃料罐") == 1, "manual reload consumes one reserve clip on commit");
        assert(unit.当前弹夹副武器已发射数 == 0, "manual reload resets fired count");
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
        unit.长枪副武器状态.loaded = 0;
        unit.长枪副武器状态.groupPaid = true;
        unit.当前弹夹副武器已发射数 = unit.长枪副武器状态.capacity;

        var ok:Boolean = LongGunSubWeaponCore.startManualReloadAnimation(unit);
        assert(ok, "subweapon manual reload starts from long-gun run state");
        assert(unit.状态 == "长枪站立", "subweapon manual reload normalizes run to stand");
        assert(unit.行走冷却帧 == 2, "subweapon manual reload protects normalized pose from next walk tick");
        assert(unit.man !== oldMan, "subweapon manual reload waits for refreshed man after pose transition");
        assert(oldMan.subweaponManualReload != true, "subweapon manual reload does not mark stale run man");
        assert(unit.man.subweaponManualReload === true, "subweapon manual reload marks manual reload path");
        assert(LongGunSubWeaponCore.isManualReloadMovementLocked(unit), "subweapon manual reload keeps unit-level movement lock");
        assert(!LongGunSubWeaponCore.canReloadManual(unit), "subweapon manual reload lock rejects duplicate manual reload");
        assert(unit.man.playFrame == "换弹匣", "subweapon manual reload enters reload animation");
        restoreMockInventory();
    }

    private static function testManualReloadMovementLockClearsOnFinish():Void {
        installMockInventory("火焰喷射器燃料罐", 2);
        var unit:Object = makeUnit();
        unit.man = makeReloadClip(unit);
        LongGunSubWeaponCore.configureUnit(unit, {weapontype: "突击步枪", subweapon: makeSubweapon(false)});
        unit.长枪副武器状态.loaded = 0;
        unit.长枪副武器状态.groupPaid = true;
        unit.当前弹夹副武器已发射数 = unit.长枪副武器状态.capacity;

        var ok:Boolean = LongGunSubWeaponCore.startManualReloadAnimation(unit);
        assert(ok, "subweapon manual reload starts on current pose");
        assert(LongGunSubWeaponCore.isManualReloadMovementLocked(unit), "subweapon manual reload locks movement while animation owns timeline");

        ReloadManager.finishReload(unit.man);
        assert(!LongGunSubWeaponCore.isManualReloadMovementLocked(unit), "finish reload clears subweapon movement lock");
        assert(unit.man.换弹标签 == false, "finish reload clears current reload tag after movement lock cleanup");
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
        unit.长枪副武器状态.loaded = 0;
        unit.长枪副武器状态.groupPaid = true;
        unit.当前弹夹副武器已发射数 = unit.长枪副武器状态.capacity;

        assert(LongGunSubWeaponCore.canReloadManual(unit), "manual reload precheck passes before animation");
        unit.man.subweaponManualReload = true;
        unit.man.换弹标签 = true;

        ReloadManager.initReloadBurden(unit.man, 42, 50, 43, 74, [51, 56, 64]);
        assert(unit.man.perRoundReload == false, "subweapon manual reload bypasses tube per-round path");
        assert(unit.man.reloadBurden == 25, "subweapon manual reload uses manual reload burden");
        assert(unit.man.reloadFrameControlRequest === true, "subweapon manual reload enables frame control");

        ReloadManager.reloadMagazine(unit.man, unit, _root);
        assert(unit.长枪.value.shot == 3, "subweapon animation commit does not reset main weapon shot");
        assert(unit.长枪副武器状态.loaded == unit.长枪副武器状态.capacity, "subweapon animation commit refills loaded state");
        assert(unit.长枪副武器状态.groupPaid == true, "subweapon animation commit marks group paid");
        assert(ItemUtil.getTotal("火焰喷射器燃料罐") == 1, "subweapon animation commit consumes one reserve clip");

        ReloadManager.finishReload(unit.man);
        assert(unit.man.subweaponManualReload == undefined, "finish reload clears subweapon manual marker");
        assert(unit.man.换弹标签 == false, "finish reload clears reload tag");
        assert(unit.man.stopFrame == "空闲", "finish reload returns timeline to idle");
        restoreMockInventory();
    }

    private static function testLinkedReload():Void {
        installMockInventory("火焰喷射器燃料罐", 1);
        var unit:Object = makeUnit();
        LongGunSubWeaponCore.configureUnit(unit, {weapontype: "突击步枪", subweapon: makeSubweapon(false)});
        unit.长枪副武器状态.loaded = 0;
        unit.长枪副武器状态.groupPaid = true;
        unit.当前弹夹副武器已发射数 = unit.长枪副武器状态.capacity;

        var ok:Boolean = LongGunSubWeaponCore.reloadLinked(unit);
        assert(ok, "linked reload succeeds with reserve commit");
        assert(unit.长枪副武器状态.loaded == unit.长枪副武器状态.capacity, "linked reload refills loaded state");
        assert(unit.长枪副武器状态.groupPaid == true, "linked reload marks group paid on commit");
        assert(ItemUtil.getTotal("火焰喷射器燃料罐") == 0, "linked reload consumes reserve on commit");
        restoreMockInventory();
    }

    private static function testLinkedReloadRequiresReserve():Void {
        installMockInventory("火焰喷射器燃料罐", 0);
        var unit:Object = makeUnit();
        LongGunSubWeaponCore.configureUnit(unit, {weapontype: "突击步枪", subweapon: makeSubweapon(false)});
        unit.长枪副武器状态.loaded = 0;
        unit.长枪副武器状态.groupPaid = true;
        unit.当前弹夹副武器已发射数 = unit.长枪副武器状态.capacity;

        var ok:Boolean = LongGunSubWeaponCore.reloadLinked(unit);
        assert(!ok, "linked reload fails when reserve is unavailable");
        assert(unit.长枪副武器状态.loaded == 0, "linked reload does not refill without reserve");
        assert(unit.长枪副武器状态.groupPaid == true, "failed linked reload keeps previous payment state");
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
        unit.长枪副武器状态.loaded = 0;
        unit.长枪副武器状态.groupPaid = true;
        unit.当前弹夹副武器已发射数 = unit.长枪副武器状态.capacity;
        installMockHero(unit);

        ReloadManager.startReload(unit.man, unit, _root);
        assert(unit.man.subweaponLinkedReload === true, "R marks combined reload when main and subweapon both need ammo");
        assert(unit.man.subweaponManualReload != true, "combined R reload keeps main reload path");
        assert(unit.man.playFrame == "换弹匣", "combined R reload enters main reload animation");

        ReloadManager.reloadMagazine(unit.man, unit, _root);
        assert(unit.长枪.value.shot == 0, "combined R reload refills main weapon");
        assert(unit.长枪副武器状态.loaded == unit.长枪副武器状态.capacity, "combined R reload refills subweapon");
        assert(ItemUtil.getTotal("主武器弹匣") == 0, "combined R reload consumes main reserve");
        assert(ItemUtil.getTotal("火焰喷射器燃料罐") == 1, "combined R reload consumes subweapon reserve");

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
        unit.长枪副武器状态.loaded = 0;
        unit.长枪副武器状态.groupPaid = true;
        unit.当前弹夹副武器已发射数 = unit.长枪副武器状态.capacity;
        installMockHero(unit);

        ReloadManager.startReload(unit.man, unit, _root);
        assert(unit.man.subweaponManualReload === true, "R starts subweapon reload when main weapon is full");
        assert(unit.man.playFrame == "换弹匣", "R subweapon reload enters reload animation");

        ReloadManager.reloadMagazine(unit.man, unit, _root);
        assert(unit.长枪副武器状态.loaded == unit.长枪副武器状态.capacity, "R subweapon reload refills loaded state");
        assert(ItemUtil.getTotal("火焰喷射器燃料罐") == 1, "R subweapon reload consumes reserve on commit");

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
        unit.man.subweaponLinkedReload = true;
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
        unit.长枪副武器状态.loaded = 0;
        unit.长枪副武器状态.groupPaid = false;
        unit.当前弹夹副武器已发射数 = unit.长枪副武器状态.capacity;
        var previousControlTarget:String = _root.控制目标;
        _root.控制目标 = "heroUnit";

        SkillReloadCore.reloadAllWeapons(unit);

        assert(unit.长枪.value.shot == 0, "non-hero roll reload refills long gun without reserve");
        assert(unit.手枪.value.shot == 0, "non-hero roll reload refills pistol");
        assert(unit.手枪2.value.shot == 0, "non-hero roll reload refills second pistol");
        assert(unit.长枪副武器状态.loaded == unit.长枪副武器状态.capacity, "non-hero roll reload refills subweapon without reserve");
        assert(unit.长枪副武器状态.groupPaid == true, "non-hero roll reload marks free subweapon group paid");
        assert(ItemUtil.getTotal("火焰喷射器燃料罐") == 0, "non-hero roll reload does not consume player reserve");
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
        unit.长枪副武器状态.loaded = 0;
        unit.长枪副武器状态.groupPaid = false;
        unit.当前弹夹副武器已发射数 = unit.长枪副武器状态.capacity;
        installMockHero(unit);

        SkillReloadCore.reloadAllWeapons(unit);

        assert(unit.长枪.value.shot == 0, "hero roll reload keeps full long gun");
        assert(unit.长枪副武器状态.loaded == unit.长枪副武器状态.capacity, "hero roll reload refills subweapon when main is full");
        assert(unit.长枪副武器状态.groupPaid == true, "hero roll reload marks linked subweapon group paid");
        assert(ItemUtil.getTotal("火焰喷射器燃料罐") == 0, "hero roll reload consumes one subweapon reserve");
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
            被动技能: {冲击连携: {启用: true, 等级: 10}}
        };
        unit.状态改变 = function(state:String):Void {
            this.状态 = state;
        };
        return unit;
    }

    private static function makeActionClip(parent:Object, worldX:Number, worldY:Number, muzzleX:Number, muzzleY:Number):Object {
        var clip:Object = {_parent: parent};
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

    private static function makeSkillController(skillName:String, cooldownReady:Boolean, cooldownTime:Number):Object {
        var holder:Object = {};
        holder.战技栏 = {已装备名: skillName, 冷却时间: cooldownTime};
        holder.战技进度条 = {冷却: cooldownReady};
        return {_parent: holder, 控制参数: "战技栏", 控制参数2: "战技进度条"};
    }

    private static var oldInventory:Object;
    private static var oldCollection:Object;
    private static var oldEquipmentDict:Object;
    private static var oldMaterialDict:Object;
    private static var oldInformationDict:Object;
    private static var oldGameworld:Object;
    private static var oldControlTarget:String;
    private static var oldPaused:Object;
    private static var oldPlayerCount:Object;

    private static function installMockInventory(itemName:String, count:Number, itemName2:String, count2:Number):Void {
        oldInventory = _root.物品栏;
        oldCollection = _root.收集品栏;
        oldEquipmentDict = ItemUtil.equipmentDict;
        oldMaterialDict = ItemUtil.materialDict;
        oldInformationDict = ItemUtil.informationMaxValueDict;

        ItemUtil.equipmentDict = {};
        ItemUtil.materialDict = {};
        ItemUtil.informationMaxValueDict = {};

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

    private static function installWeaponSkillInputRootState():Void {
        oldPaused = _root.暂停;
        oldPlayerCount = _root.当前玩家总数;
        _root.暂停 = false;
        _root.当前玩家总数 = 1;
    }

    private static function restoreWeaponSkillInputRootState():Void {
        _root.暂停 = oldPaused;
        _root.当前玩家总数 = oldPlayerCount;
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
