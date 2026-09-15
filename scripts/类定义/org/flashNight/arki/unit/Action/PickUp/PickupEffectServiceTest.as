import org.flashNight.arki.component.Buff.*;
import org.flashNight.arki.unit.Action.PickUp.PickupEffectService;
import org.flashNight.arki.item.drug.DrugContext;
import org.flashNight.arki.item.drug.DrugEffectRegistry;
import org.flashNight.arki.item.drug.DrugValueParser;

/**
 * PickupEffectServiceTest - 战场即时补给领取服务单元测试
 *
 * focused runner: scripts/run-battle-supply-tests.ps1
 *
 * 覆盖（设计契约 docs/战场即时补给品-技术调研与首批施工准备-2026-09-12.md §13）：
 *   - isInstantSupply 识别 use=战场补给
 *   - 白名单拒绝未知词条 / 未注册词条（supplyAmmo 本片未开放），零写入
 *   - 满血无收益保留实体（noBenefit），缺血收益消耗（applied）
 *   - 死亡目标拒绝、距离过远 tooFar 静默、重复领取占用
 *   - 炼金中性化（高炼金等级不改变恢复量与封顶）
 *   - Buff 固定 id 刷新不叠强度；regen 独立槽不清默认药剂缓释槽
 *
 * 物品数据经 mock _root.getItemData 注入；hero/target 用真实 MovieClip 与
 * 真实 BuffManager，药效词条走真实 DrugEffectRegistry 注册实例。
 */
class org.flashNight.arki.unit.Action.PickUp.PickupEffectServiceTest {

    private static var passed:Number;
    private static var failed:Number;
    private static var serial:Number;
    private static var clips:Array;
    private static var messages:Array;
    private static var itemDict:Object;
    private static var hitResult:Boolean;

    private static var oldGetItemData:Function;
    private static var oldMessage:Function;
    private static var oldGameworld:Object;
    private static var oldControl;
    private static var oldSave:Object;
    private static var oldUi:Object;
    private static var oldPassive:Object;

    private static function check(ok:Boolean, label:String):Void {
        if (ok) passed++;
        else { failed++; trace("[FAIL] PickupEffectServiceTest: " + label); }
    }

    private static function assertEq(expected, actual, label:String):Void {
        if (expected == actual) passed++;
        else {
            failed++;
            trace("[FAIL] PickupEffectServiceTest: " + label +
                " | expected: " + expected + " | actual: " + actual);
        }
    }

    public static function runAllTests():Void {
        passed = 0; failed = 0; serial = 0; clips = [];
        oldGetItemData = _root.getItemData;
        oldMessage = _root.发布消息;
        oldGameworld = _root.gameworld;
        oldControl = _root.控制目标;
        oldSave = _root.存档系统;
        oldUi = _root.玩家信息界面;
        oldPassive = _root.主角被动技能;

        _root.gameworld = _root;
        _root.发布消息 = function(message):Void { PickupEffectServiceTest.messages.push(message); };
        _root.存档系统 = {dirtyMark: false};
        _root.玩家信息界面 = {刷新hp显示: function():Void {}, 刷新mp显示: function():Void {}};
        _root.getItemData = function(name):Object { return PickupEffectServiceTest.itemDict[name]; };
        installItemDict();

        try {
            testIsInstantSupply();
            testUnknownTypeRejectedZeroWrite();
            testUnregisteredSupplyAmmoRejected();
            testFullHpNoBenefit();
            testWoundedApplied();
            testDeadHeroRejected();
            testTooFar();
            testClaimLock();
            testAlchemyNeutralized();
            testBuffRefreshNoStack();
            testRegenIndependentSlot();
        } catch (error) {
            check(false, "unexpected exception: " + error);
        }
        finish();
    }

    private static function installItemDict():Void {
        itemDict = {};
        itemDict["战场医疗包"] = {use: "战场补给", data: {effects: {effect: [
            {type: "heal", hp: "300", mp: "0", target: "self", scaleWithAlchemy: false}
        ]}}};
        itemDict["战场复合急救包"] = {use: "战场补给", data: {effects: {effect: [
            {type: "heal", hp: "25%", mp: "50%", target: "self", scaleWithAlchemy: false},
            {type: "regen", hp: "200", duration: "300", interval: "30", mode: "total", id: "战场_缓释", scaleWithAlchemy: false}
        ]}}};
        itemDict["战场突击强化包"] = {use: "战场补给", data: {effects: {effect: [
            {type: "buff", property: "伤害加成", calc: "add", value: "50", duration: "1800", buffId: "战场_突击"}
        ]}}};
        itemDict["战场弹药包"] = {use: "战场补给", data: {effects: {effect: [
            {type: "supplyAmmo", scope: "longgun"}
        ]}}};
        itemDict["战场未知词条包"] = {use: "战场补给", data: {effects: {effect: [
            {type: "grantItem", item: "砖", count: 1}
        ]}}};
        itemDict["普通hp药剂"] = {use: "药剂", data: {effects: {effect: [
            {type: "heal", hp: "150", mp: "0", target: "self", scaleWithAlchemy: true}
        ]}}};
    }

    private static function resetState():Void {
        messages = [];
        _root.存档系统.dirtyMark = false;
        _root.主角被动技能 = undefined;
        hitResult = true;
    }

    private static function makeHero(hp:Number, maxHp:Number, mp:Number, maxMp:Number):MovieClip {
        var heroName:String = "__bsHero" + (++serial);
        var hero:MovieClip = _root.createEmptyMovieClip(heroName, _root.getNextHighestDepth());
        clips.push(hero);
        hero.hp = hp; hero.hp满血值 = maxHp;
        hero.mp = mp; hero.mp满血值 = maxMp;
        hero.Z轴坐标 = 0;
        hero.伤害加成 = 100;
        hero.魔法抗性 = {基础: 0, 电: 0, 热: 0, 冷: 0, 波: 0, 蚀: 0, 毒: 0, 冲: 0};
        var area:MovieClip = hero.createEmptyMovieClip("area", 1);
        area.hitTest = function(target):Boolean { return PickupEffectServiceTest.hitResult; };
        hero.buffManager = new BuffManager(hero, {});
        _root.控制目标 = heroName;
        return hero;
    }

    private static function makeTarget(itemName:String, z:Number):MovieClip {
        var target:MovieClip = _root.createEmptyMovieClip("__bsTarget" + (++serial), _root.getNextHighestDepth());
        clips.push(target);
        target.物品名 = itemName;
        target.Z轴坐标 = z;
        target.createEmptyMovieClip("area", 1);
        return target;
    }

    private static function testIsInstantSupply():Void {
        resetState();
        check(PickupEffectService.isInstantSupply("战场医疗包") === true, "use=战场补给识别为即时补给");
        check(PickupEffectService.isInstantSupply("普通hp药剂") === false, "普通药剂不误判为即时补给");
        check(PickupEffectService.isInstantSupply("不存在的物品") === false, "未注册物品安全返回 false");
    }

    private static function testUnknownTypeRejectedZeroWrite():Void {
        resetState();
        var hero:MovieClip = makeHero(500, 1000, 0, 1000);
        var target:MovieClip = makeTarget("战场未知词条包", 0);
        check(PickupEffectService.tryClaim(target) == "rejected", "未知词条整包前置拒绝");
        check(hero.hp == 500 && hero.mp == 0, "未知词条零写入");
        check(messages.length == 1 && messages[0] == "补给配置无效", "未知词条播报配置无效");
        check(target._supplyClaimed === false, "拒绝后占用复位可重试");
        check(_root.存档系统.dirtyMark == false, "前置拒绝不落脏");
    }

    private static function testUnregisteredSupplyAmmoRejected():Void {
        resetState();
        var hero:MovieClip = makeHero(500, 1000, 0, 1000);
        var target:MovieClip = makeTarget("战场弹药包", 0);
        check(PickupEffectService.tryClaim(target) == "rejected", "supplyAmmo 本片未注册按配置不支持拒绝");
        check(hero.hp == 500, "supplyAmmo 拒绝零写入");
        check(messages.length == 1 && messages[0] == "补给配置无效", "supplyAmmo 拒绝播报配置无效");
        check(target._supplyClaimed === false, "supplyAmmo 拒绝后占用复位");
    }

    private static function testFullHpNoBenefit():Void {
        resetState();
        var hero:MovieClip = makeHero(1000, 1000, 1000, 1000);
        var target:MovieClip = makeTarget("战场医疗包", 0);
        check(PickupEffectService.tryClaim(target) == "noBenefit", "满血满蓝领取返回 noBenefit");
        check(hero.hp == 1000 && hero.mp == 1000, "满血无收益零写入");
        check(messages.length == 1 && messages[0] == "状态良好，无需补给", "满血播报无需补给");
        check(target._supplyClaimed === false, "noBenefit 占用复位实体保留");
        check(_root.存档系统.dirtyMark == false, "noBenefit 不落脏");
    }

    private static function testWoundedApplied():Void {
        resetState();
        var hero:MovieClip = makeHero(500, 1000, 0, 1000);
        var target:MovieClip = makeTarget("战场医疗包", 0);
        check(PickupEffectService.tryClaim(target) == "applied", "缺血领取返回 applied");
        assertEq(800, hero.hp, "固定恢复 300 到账");
        assertEq("战场医疗包：HP +300", messages[0], "收益播报汇总实际恢复");
        check(_root.存档系统.dirtyMark == true, "applied 落脏");
        check(target._supplyClaimed === true, "applied 保持占用防止消耗前重入");
    }

    private static function testDeadHeroRejected():Void {
        resetState();
        var hero:MovieClip = makeHero(0, 1000, 0, 1000);
        var target:MovieClip = makeTarget("战场医疗包", 0);
        check(PickupEffectService.tryClaim(target) == "rejected", "死亡目标拒绝领取");
        check(hero.hp == 0, "死亡零写入");
        check(messages.length == 0, "死亡拒绝静默不播报");
        check(target._supplyClaimed === false, "死亡拒绝占用复位");
    }

    private static function testTooFar():Void {
        resetState();
        var hero:MovieClip = makeHero(500, 1000, 0, 1000);
        var farTarget:MovieClip = makeTarget("战场医疗包", 100);
        check(PickupEffectService.tryClaim(farTarget) == "tooFar", "Z 轴差 100 返回 tooFar");
        check(messages.length == 0 && hero.hp == 500, "tooFar 静默且零写入");
        hitResult = false;
        var blockedTarget:MovieClip = makeTarget("战场医疗包", 0);
        check(PickupEffectService.tryClaim(blockedTarget) == "tooFar", "area.hitTest 不命中同样 tooFar");
        check(messages.length == 0, "hitTest 不命中也静默");
        check(farTarget._supplyClaimed === false && blockedTarget._supplyClaimed === false, "tooFar 占用复位实体保留");
    }

    private static function testClaimLock():Void {
        resetState();
        var hero:MovieClip = makeHero(500, 1000, 0, 1000);
        var target:MovieClip = makeTarget("战场医疗包", 0);
        PickupEffectService.tryClaim(target);
        check(PickupEffectService.tryClaim(target) == "rejected", "已占用实体重复领取拒绝");
        check(hero.hp == 800, "重复领取不二次恢复");
        var preClaimed:MovieClip = makeTarget("战场医疗包", 0);
        preClaimed._supplyClaimed = true;
        check(PickupEffectService.tryClaim(preClaimed) == "rejected", "外部置位占用同样最前端拒绝");
    }

    private static function testAlchemyNeutralized():Void {
        resetState();
        _root.主角被动技能 = {炼金: {启用: true, 等级: 10}};
        var hero:MovieClip = makeHero(990, 1000, 0, 1000);
        var target:MovieClip = makeTarget("战场医疗包", 0);
        check(PickupEffectService.tryClaim(target) == "applied", "高炼金下领取仍生效");
        assertEq(1000, hero.hp, "炼金中性化：恢复量与封顶不吃炼金加成");
        assertEq("战场医疗包：HP +10", messages[0], "收益播报按中性上下文实际增量");
    }

    private static function testBuffRefreshNoStack():Void {
        resetState();
        var hero:MovieClip = makeHero(1000, 1000, 1000, 1000);
        var first:MovieClip = makeTarget("战场突击强化包", 0);
        check(PickupEffectService.tryClaim(first) == "applied", "满血强化包按 Buff 新增计收益");
        check(hero.伤害加成 == 150, "伤害加成 100+50 立即生效");
        check(hero.buffManager.getBuffById("战场_突击") != null, "固定 buffId 已注册");
        check(messages[0] == "战场突击强化包：已获得强化（伤害加成 +50）", "强化收益文案");
        var second:MovieClip = makeTarget("战场突击强化包", 0);
        check(PickupEffectService.tryClaim(second) == "applied", "重复领取按 Buff 延长仍计收益");
        check(hero.伤害加成 == 150, "固定 id 刷新不叠强度");
    }

    private static function testRegenIndependentSlot():Void {
        resetState();
        var hero:MovieClip = makeHero(500, 1000, 0, 1000);
        // 用真实 regen 词条预置默认药剂缓释槽，而不是空壳 MetaBuff（会被管理器立即清理）
        var preCtx:DrugContext = DrugContext.createWithData("普通hp药剂", hero, itemDict["普通hp药剂"]);
        preCtx.alchemyLevel = 0;
        DrugEffectRegistry.get("regen").execute(preCtx,
            {type: "regen", hp: "10", duration: "600", interval: "30", mode: "perTick"});
        check(hero.buffManager.getBuffById("药剂_缓释_HP") != null, "预置默认药剂缓释槽成功");
        var target:MovieClip = makeTarget("战场复合急救包", 0);
        check(PickupEffectService.tryClaim(target) == "applied", "复合急救包领取生效");
        assertEq(750, hero.hp, "百分比恢复 25%HP 到账");
        assertEq(500, hero.mp, "百分比恢复 50%MP 到账");
        check(hero.buffManager.getBuffById("药剂_缓释_HP") != null, "战场缓释不清默认药剂缓释槽");
        check(hero.buffManager.getBuffById("战场_缓释_HP") != null, "战场缓释独立槽已建立");
        assertEq("战场复合急救包：HP +250，MP +500，已获得持续恢复", messages[0], "复合收益播报");
        check(hero.buffManager.getBuffById("战场_缓释_HP") !== hero.buffManager.getBuffById("药剂_缓释_HP"), "两槽为不同实例");
    }

    private static function finish():Void {
        for (var i:Number = 0; i < clips.length; i++) {
            if (clips[i]._parent) {
                if (clips[i].buffManager) clips[i].buffManager.destroy();
                clips[i].removeMovieClip();
            }
        }
        _root.getItemData = oldGetItemData;
        _root.发布消息 = oldMessage;
        _root.gameworld = oldGameworld;
        _root.控制目标 = oldControl;
        _root.存档系统 = oldSave;
        _root.玩家信息界面 = oldUi;
        _root.主角被动技能 = oldPassive;
        trace("PickupEffectServiceTest Tests Passed: " + passed);
        trace("PickupEffectServiceTest Tests Failed: " + failed);
    }
}
