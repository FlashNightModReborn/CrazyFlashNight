import org.flashNight.arki.unit.Action.Shoot.AmmoSupplyService;
import org.flashNight.arki.item.BaseItem;
import org.flashNight.arki.item.ItemUtil;

/**
 * AmmoSupplyServiceTest - 弹药补给服务单元测试
 *
 * focused runner: scripts/run-battle-supply-tests.ps1（与 PickupEffectServiceTest 同域）
 *
 * 覆盖（设计契约 docs/战场即时补给品-技术调研与首批施工准备-2026-09-12.md §13）：
 *   - scope 四值语义：longgun/pistols/equipped/all（背包枪含、仓库不含）
 *   - 同名两把分别补；slot alias 同引用只处理一次
 *   - GM6 负 shot 不动、满弹零收益、shot==undefined 背包枪不碰
 *   - tube 实例 reloadCount 清 0、非 tube 回收池保留、machineGunShot 镜像清 0
 *   - 换弹在途整包零写 rejected="reload"
 *   - 已装备长枪副武器走 reloadLinkedFree 免费补满入口（真实入口、手工装配运行态）
 *   - 补弹后 BaseItem.toObject() 序列化值正确
 *
 * hero/背包/枪械用 mock 对象（省类型注解绕编译）；HUD 写入走真实
 * ReloadManager.updateAmmoDisplay + stub 玩家必要信息界面。
 */
class org.flashNight.arki.unit.Action.Shoot.AmmoSupplyServiceTest {

    private static var passed:Number;
    private static var failed:Number;
    private static var serial:Number;
    private static var heroNames:Array;
    private static var itemDict:Object;
    private static var hud:Object;
    private static var bulletEvents:Array;

    private static var oldGetItemData:Function;
    private static var oldGameworld:Object;
    private static var oldControl;
    private static var oldSave:Object;
    private static var oldUi:Object;
    private static var oldInventory:Object;
    private static var oldItems:Object;

    private static function check(ok:Boolean, label:String):Void {
        if (ok) passed++;
        else { failed++; trace("[FAIL] AmmoSupplyServiceTest: " + label); }
    }

    private static function assertEq(expected, actual, label:String):Void {
        if (expected == actual) passed++;
        else {
            failed++;
            trace("[FAIL] AmmoSupplyServiceTest: " + label +
                " | expected: " + expected + " | actual: " + actual);
        }
    }

    public static function runAllTests():Void {
        passed = 0; failed = 0; serial = 0; heroNames = [];
        oldGetItemData = _root.getItemData;
        oldGameworld = _root.gameworld;
        oldControl = _root.控制目标;
        oldSave = _root.存档系统;
        oldUi = _root.玩家信息界面;
        oldInventory = _root.物品栏;
        oldItems = ItemUtil.itemDataDict;

        _root.gameworld = _root;
        _root.存档系统 = {dirtyMark: false};
        hud = {};
        _root.玩家信息界面 = {玩家必要信息界面: hud, 刷新hp显示: function():Void {}, 刷新mp显示: function():Void {}};
        _root.getItemData = function(name):Object { return AmmoSupplyServiceTest.itemDict[name]; };
        installItemDict();
        ItemUtil.itemDataDict = itemDict;

        try {
            testLonggunScopeOnly();
            testPistolsScopeSkipsEmptySlotAndKnifeMode();
            testEquippedScopeAllSlots();
            testAllScopeIncludesBagOnly();
            testSameNameDistinctInstancesAndAliasRef();
            testNegativeShotSkipped();
            testFullGunZeroBenefit();
            testTubeBudgetClearedNonTubeKept();
            testMachineGunShotMirrorCleared();
            testReloadInProgressRejected();
            testEquippedSubweaponFreeRefill();
            testBaseItemSerialization();
        } catch (error) {
            check(false, "unexpected exception: " + error);
        }
        finish();
    }

    private static function installItemDict():Void {
        itemDict = {};
        itemDict["测试长枪"] = {use: "长枪", data: {bullet: "普通子弹", clipname: "测试弹匣"}};
        itemDict["测试手枪"] = {use: "手枪", data: {bullet: "普通子弹", clipname: "测试弹匣"}};
        itemDict["测试管状长枪"] = {use: "长枪", data: {reloadType: "tube", bullet: "普通子弹"}};
        itemDict["测试副武器长枪"] = {use: "长枪", subweapon: {name: "测试副武器", capacity: 5, reserveName: "测试电池"},
            data: {bullet: "普通子弹"}};
        itemDict["测试电池"] = {use: "弹夹"};
        itemDict["砖"] = {use: "材料"};
    }

    private static function resetState():Void {
        _root.存档系统.dirtyMark = false;
        bulletEvents = [];
    }

    private static function makeHero(mode:String):Object {
        var hero:Object = {};
        hero._name = "__ammoHero" + (++serial);
        hero.hp = 1000; hero.hp满血值 = 1000;
        hero.mp = 0; hero.mp满血值 = 1000;
        hero.攻击模式 = mode;
        hero.man = {换弹标签: false};
        hero.dispatcher = {publish: function(event:String, owner:Object, state:String,
                remaining:Number, field:String, slot:String):Void {
            AmmoSupplyServiceTest.bulletEvents.push(
                {event: event, state: state, remaining: remaining, field: field, slot: slot});
        }};
        _root[hero._name] = hero;
        heroNames.push(hero._name);
        _root.控制目标 = hero._name;
        return hero;
    }

    private static function equip(hero:Object, slot:String, name:String, shot, attrs:Object):Object {
        var item:Object = {name: name, value: {level: 1}};
        if (shot !== undefined) item.value.shot = shot;
        hero[slot] = item;
        hero[slot + "属性"] = attrs == null ? {bullet: "普通子弹", clipname: "测试弹匣"} : attrs;
        hero[slot + "弹匣容量"] = 30;
        return item;
    }

    private static function makeBag(items:Array):Object {
        var bag:Object = {items: items};
        bag.getIndexes = function():Array {
            var idx:Array = [];
            for (var i:Number = 0; i < this.items.length; i++) {
                if (this.items[i] != null) idx.push(i);
            }
            return idx;
        };
        bag.getItem = function(key:String):Object { return this.items[Number(key)]; };
        return bag;
    }

    private static function testLonggunScopeOnly():Void {
        resetState();
        var hero:Object = makeHero("长枪");
        var lg:Object = equip(hero, "长枪", "测试长枪", 5, null);
        var pi:Object = equip(hero, "手枪", "测试手枪", 3, null);
        _root.物品栏 = {背包: makeBag([]), 仓库: makeBag([])};
        var result:Object = AmmoSupplyService.supply(hero, "longgun");
        assertEq(1, result.changed, "longgun scope 只补长枪");
        assertEq(0, lg.value.shot, "长枪已补满");
        assertEq(3, pi.value.shot, "手枪未被触碰");
        check(result.rejected == null && result.details.length == 1
            && result.details[0].slot == "长枪" && result.details[0].beforeShot == 5
            && result.details[0].name == "测试长枪", "明细记录名称/槽位/补前 shot");
        check(_root.存档系统.dirtyMark == true, "补弹落脏一次");
        check(bulletEvents.length == 1 && bulletEvents[0].event == "updateBullet"
            && bulletEvents[0].field == "子弹数" && bulletEvents[0].slot == "长枪"
            && bulletEvents[0].remaining == 30, "长枪形态 typed 5 参 updateBullet 发布");
    }

    private static function testPistolsScopeSkipsEmptySlotAndKnifeMode():Void {
        resetState();
        var hero:Object = makeHero("刀");
        var main:Object = equip(hero, "手枪", "测试手枪", 3, null);
        hero.手枪2 = null;
        _root.物品栏 = {背包: makeBag([])};
        var result:Object = AmmoSupplyService.supply(hero, "pistols");
        assertEq(1, result.changed, "pistols scope 只补实际存在的手枪");
        assertEq(0, main.value.shot, "当前持刀也可补手枪");
        check(hero.手枪2 === null, "手枪2 空槽跳过不造对象");
        check(bulletEvents.length == 0, "非枪械形态不推送 HUD 字段");
    }

    private static function testEquippedScopeAllSlots():Void {
        resetState();
        var hero:Object = makeHero("双枪");
        var lg:Object = equip(hero, "长枪", "测试长枪", 2, null);
        var p1:Object = equip(hero, "手枪", "测试手枪", 3, null);
        var p2:Object = equip(hero, "手枪2", "测试手枪", 4, null);
        _root.物品栏 = {背包: makeBag([])};
        var result:Object = AmmoSupplyService.supply(hero, "equipped");
        assertEq(3, result.changed, "equipped scope 三槽并集");
        check(lg.value.shot == 0 && p1.value.shot == 0 && p2.value.shot == 0, "三槽都补满");
        check(bulletEvents.length == 2, "双枪形态只推送两手手枪字段");
        assertEq(30, hud.子弹数, "双枪主手 HUD 已刷新");
        assertEq(30, hud.子弹数_2, "双枪副手 HUD 已刷新");
    }

    private static function testAllScopeIncludesBagOnly():Void {
        resetState();
        var hero:Object = makeHero("刀");
        equip(hero, "长枪", "测试长枪", 0, null);
        var bagGun:Object = {name: "测试手枪", value: {level: 1, shot: 4}};
        var bagGunUndefined:Object = {name: "测试手枪", value: {level: 1}};
        var warehouseGun:Object = {name: "测试长枪", value: {level: 1, shot: 9}};
        _root.物品栏 = {背包: makeBag([bagGun, {name: "砖", value: 5}, bagGunUndefined]),
                        仓库: makeBag([warehouseGun])};
        var result:Object = AmmoSupplyService.supply(hero, "all");
        assertEq(1, result.changed, "all scope 只补需要补的背包枪");
        assertEq(0, bagGun.value.shot, "背包枪已补满");
        assertEq(9, warehouseGun.value.shot, "仓库枪不被触碰");
        check(bagGunUndefined.value.shot === undefined, "shot==undefined 背包枪不凭空造收益");
        check(result.details.length == 1 && result.details[0].slot == "背包", "背包补弹明细标注来源");
        check(_root.存档系统.dirtyMark == true, "背包补弹同样落脏");
    }

    private static function testSameNameDistinctInstancesAndAliasRef():Void {
        resetState();
        var hero:Object = makeHero("刀");
        var a:Object = equip(hero, "手枪", "测试手枪", 2, null);
        var b:Object = equip(hero, "手枪2", "测试手枪", 6, null);
        var result:Object = AmmoSupplyService.supply(hero, "pistols");
        assertEq(2, result.changed, "同名两把分别补");
        check(a.value.shot == 0 && b.value.shot == 0, "同名两实例都补满");

        var hero2:Object = makeHero("刀");
        var shared:Object = equip(hero2, "手枪", "测试手枪", 7, null);
        hero2.手枪2 = shared; // RuntimeEquipmentProjection alias：两槽同一对象引用
        var result2:Object = AmmoSupplyService.supply(hero2, "pistols");
        assertEq(1, result2.changed, "slot alias 同引用只处理一次");
        assertEq(0, shared.value.shot, "alias 实例本身已补满");
    }

    private static function testNegativeShotSkipped():Void {
        resetState();
        var hero:Object = makeHero("刀");
        var gm6:Object = equip(hero, "长枪", "测试长枪", -5, null);
        var result:Object = AmmoSupplyService.supply(hero, "longgun");
        assertEq(0, result.changed, "GM6 负 shot 不产生收益");
        assertEq(-5, gm6.value.shot, "负 shot 原样保留");
        check(_root.存档系统.dirtyMark == false, "零收益不落脏");
    }

    private static function testFullGunZeroBenefit():Void {
        resetState();
        var hero:Object = makeHero("刀");
        equip(hero, "长枪", "测试长枪", 0, null);
        var result:Object = AmmoSupplyService.supply(hero, "longgun");
        assertEq(0, result.changed, "满弹枪零收益");
        check(result.rejected == null, "满弹不是 rejected");
    }

    private static function testTubeBudgetClearedNonTubeKept():Void {
        resetState();
        var hero:Object = makeHero("刀");
        var tubeGun:Object = equip(hero, "长枪", "测试管状长枪", 8, {reloadType: "tube", bullet: "普通子弹"});
        tubeGun.value.reloadCount = 7;
        var normalGun:Object = equip(hero, "手枪", "测试手枪", 8, null);
        normalGun.value.reloadCount = 7;
        var result:Object = AmmoSupplyService.supply(hero, "equipped");
        assertEq(2, result.changed, "两把都补满");
        check(tubeGun.value.shot == 0 && tubeGun.value.reloadCount == 0, "tube 实例补后清逐发装填预算");
        check(normalGun.value.shot == 0 && normalGun.value.reloadCount == 7, "非 tube 战术回收池保留");
    }

    private static function testMachineGunShotMirrorCleared():Void {
        resetState();
        var hero:Object = makeHero("刀");
        var guitar:Object = equip(hero, "长枪", "测试长枪", 3, null);
        guitar.value.machineGunShot = 3;
        var result:Object = AmmoSupplyService.supply(hero, "longgun");
        check(guitar.value.shot == 0 && guitar.value.machineGunShot == 0, "machineGunShot 持久镜像同步清 0");
        assertEq(1, result.changed, "镜像清理不另计收益");
    }

    private static function testReloadInProgressRejected():Void {
        resetState();
        var hero:Object = makeHero("刀");
        var gun:Object = equip(hero, "长枪", "测试长枪", 5, null);
        hero.man.换弹标签 = true;
        check(AmmoSupplyService.isReloadInProgress(hero) == true, "换弹在途判据命中");
        var result:Object = AmmoSupplyService.supply(hero, "longgun");
        check(result.rejected == "reload" && result.changed == 0, "换弹在途整包零写 rejected");
        assertEq(5, gun.value.shot, "换弹在途不写 shot");
        check(_root.存档系统.dirtyMark == false, "rejected 不落脏");
    }

    private static function testEquippedSubweaponFreeRefill():Void {
        resetState();
        var hero:Object = makeHero("长枪");
        var lg:Object = equip(hero, "长枪", "测试副武器长枪", 0, null);
        lg.value.subweaponShot = 3;
        lg.value.subweaponReloadCount = 1;
        // 手工装配副武器运行态（对齐 installVirtualWeapon 产物形态）
        hero.长枪副武器配置 = {capacity: 5, reserveName: "测试电池", basePower: 100,
            powerMultiplier: 1, hostPowerMultiplier: 1, impact: 0.01, cd: 500};
        hero.长枪副武器状态 = {loaded: 2, capacity: 5, reserveName: "测试电池",
            reloadCount: 1, groupPaid: false, nextFireTime: 0};
        hero.长枪副武器 = {name: "测试副武器", value: {shot: 3, reloadCount: 1}};
        _root.物品栏 = {背包: makeBag([])};
        var result:Object = AmmoSupplyService.supply(hero, "longgun");
        assertEq(1, result.changed, "主仓满但副武器缺弹仍计收益");
        assertEq(0, hero.长枪副武器.value.shot, "虚拟副武器已发射数清 0");
        assertEq(0, lg.value.subweaponShot, "长枪 value 副武器镜像清 0");
        assertEq(5, hero.长枪副武器状态.loaded, "副武器状态已补满");
        check(hero.长枪副武器状态.groupPaid == true, "免费补满入口标记 groupPaid");
        assertEq(1, lg.value.subweaponReloadCount, "入口保留副武器回收池镜像");
        var again:Object = AmmoSupplyService.supply(hero, "longgun");
        assertEq(0, again.changed, "副武器已满零收益");
    }

    private static function testBaseItemSerialization():Void {
        resetState();
        var hero:Object = makeHero("刀");
        var realItem:BaseItem = BaseItem.createFromObject(
            {name: "测试长枪", value: {level: 1, shot: 6}, lastUpdate: 123});
        check(realItem != null, "真实 BaseItem 已创建");
        hero.长枪 = realItem;
        hero.长枪属性 = {bullet: "普通子弹"};
        hero.长枪弹匣容量 = 30;
        var result:Object = AmmoSupplyService.supply(hero, "longgun");
        assertEq(1, result.changed, "BaseItem 实例补弹");
        var snapshot:Object = realItem.toObject();
        assertEq(0, snapshot.value.shot, "toObject 序列化 shot 已为 0");
        check(snapshot.name == "测试长枪" && snapshot.value.level == 1
            && snapshot.lastUpdate == 123, "序列化其余字段不变");
    }

    private static function finish():Void {
        for (var i:Number = 0; i < heroNames.length; i++) delete _root[heroNames[i]];
        _root.getItemData = oldGetItemData;
        _root.gameworld = oldGameworld;
        _root.控制目标 = oldControl;
        _root.存档系统 = oldSave;
        _root.玩家信息界面 = oldUi;
        _root.物品栏 = oldInventory;
        ItemUtil.itemDataDict = oldItems;
        trace("AmmoSupplyServiceTest Tests Passed: " + passed);
        trace("AmmoSupplyServiceTest Tests Failed: " + failed);
    }
}
