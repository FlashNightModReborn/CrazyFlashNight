import org.flashNight.arki.item.equipment.SubweaponDataUtil;
import org.flashNight.arki.unit.Action.Shoot.LongGunSubWeaponCore;
import org.flashNight.arki.unit.Action.Shoot.ReloadManager;
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
        testManualReload();
        testManualReloadAnimationCommit();
        testLinkedReload();
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
        var unit:Object = makeUnit();
        LongGunSubWeaponCore.configureUnit(unit, {weapontype: "突击步枪", subweapon: makeSubweapon(false)});
        unit.长枪副武器状态.loaded = 0;
        unit.长枪副武器状态.groupPaid = true;
        unit.当前弹夹副武器已发射数 = unit.长枪副武器状态.capacity;

        var ok:Boolean = LongGunSubWeaponCore.reloadLinked(unit);
        assert(ok, "linked reload succeeds without reserve commit");
        assert(unit.长枪副武器状态.loaded == unit.长枪副武器状态.capacity, "linked reload refills loaded state");
        assert(unit.长枪副武器状态.groupPaid == false, "linked reload keeps first-fire payment marker");
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
            consumeTiming: onFire ? "onFire" : "linkedFirstFire",
            mp: 100,
            power: 1000,
            capacity: 5,
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
        return {
            _name: "testUnit",
            hp: 1000,
            mp: 500,
            Z轴坐标: 0,
            攻击模式: "长枪",
            状态: "长枪站立",
            man: {},
            被动技能: {冲击连携: {启用: true, 等级: 10}}
        };
    }

    private static function makeReloadClip(parent:Object):Object {
        var clip:Object = {_parent: parent, 使用弹匣名称: "主武器弹匣", 剩余弹匣数: 9};
        clip.gotoAndPlay = function(frame:String):Void {
            this.playFrame = frame;
        };
        clip.gotoAndStop = function(frame:String):Void {
            this.stopFrame = frame;
        };
        return clip;
    }

    private static var oldInventory:Object;
    private static var oldCollection:Object;
    private static var oldEquipmentDict:Object;
    private static var oldMaterialDict:Object;
    private static var oldInformationDict:Object;

    private static function installMockInventory(itemName:String, count:Number):Void {
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
