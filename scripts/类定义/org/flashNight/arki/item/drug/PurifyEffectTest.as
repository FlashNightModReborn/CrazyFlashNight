import org.flashNight.arki.item.drug.DrugContext;
import org.flashNight.arki.item.drug.effects.PurifyEffect;
import org.flashNight.arki.item.drug.effects.BuffEffect;
import org.flashNight.arki.item.drug.effects.PlayEffectEffect;
import org.flashNight.arki.component.Buff.BuffManager;
import org.flashNight.arki.component.Buff.BuffCalculationType;
import org.flashNight.arki.component.Buff.MetaBuff;
import org.flashNight.arki.component.Buff.PodBuff;
import org.flashNight.arki.component.Buff.Component.TimeLimitComponent;
import org.flashNight.arki.weather.WeatherSystem;
import org.flashNight.arki.component.Effect.EffectSystem;

/**
 * PurifyEffectTest - Issue #281 药剂净化值、debuff 减时/消除、地形系数与群体净化测试
 */
class org.flashNight.arki.item.drug.PurifyEffectTest {

    private static var passed:Number = 0;
    private static var failed:Number = 0;

    private static var oldTerrainCoeff;
    private static var oldFrameTimer;
    private static var oldEffectFn:Function;

    private static function check(ok:Boolean, label:String):Void {
        if (ok) {
            passed++;
        } else {
            failed++;
            trace("[FAIL] PurifyEffectTest: " + label);
        }
    }

    private static function assertEq(expected, actual, label:String):Void {
        if (expected == actual) {
            passed++;
        } else {
            failed++;
            trace("[FAIL] PurifyEffectTest: " + label + " | expected=" + expected + " | actual=" + actual);
        }
    }

    private static function assertNear(expected:Number, actual:Number, eps:Number, label:String):Void {
        var diff:Number = expected - actual;
        if (diff < 0) diff = -diff;
        if (!isNaN(actual) && diff <= eps) {
            passed++;
        } else {
            failed++;
            trace("[FAIL] PurifyEffectTest: " + label + " | expected=" + expected + " | actual=" + actual);
        }
    }

    private static function makeUnit(hp:Number, x:Number, y:Number, defense:Number):Object {
        return {
            hp: hp,
            hp满血值: hp > 0 ? hp : 100,
            mp: 100,
            mp满血值: 100,
            _x: x,
            _y: y,
            防御力: defense,
            伤害加成: 50,
            行走X速度: 10
        };
    }

    private static function makeCtx(itemName:String, target:Object, alchemyLevel:Number):DrugContext {
        var ctx:DrugContext = DrugContext.createWithData(itemName, target, {data: {}});
        ctx.alchemyLevel = alchemyLevel;
        return ctx;
    }

    public static function runAllTests():Void {
        passed = 0;
        failed = 0;
        oldTerrainCoeff = _root.地形伤害系数;
        oldFrameTimer = _root.帧计时器;
        oldEffectFn = EffectSystem.Effect;

        try {
            testWeatherSystemTerrainReset();
            testTerrainMonotonicDecay();
            testSameFrameIdDedup();
            testParalysisFloorProtection();
            testBuffPolarityAndPurifyDebuffs();
            testGroupPurifyAndPlayEffect();
        } catch (err) {
            failed++;
            trace("[FAIL] PurifyEffectTest unexpected exception: " + err);
        }

        PurifyEffect.groupTargetResolver = null;
        PlayEffectEffect.groupTargetResolver = null;
        PurifyEffect.resetTerrainDedupForTest();
        EffectSystem["Effect"] = oldEffectFn;
        _root.帧计时器 = oldFrameTimer;
        _root.地形伤害系数 = oldTerrainCoeff;

        trace("PurifyEffectTest Tests Passed: " + passed);
        trace("PurifyEffectTest Tests Failed: " + failed);
    }

    private static function testWeatherSystemTerrainReset():Void {
        var ws:WeatherSystem = WeatherSystem.getInstance();
        _root.地形伤害系数 = 0.25;
        ws.resetTerrainDamageFactor(1);
        assertNear(1, _root.地形伤害系数, 0.0001, "resetTerrainDamageFactor(1)");
        assertNear(1, ws.getTerrainDamageFactor(), 0.0001, "getTerrainDamageFactor() == 1");

        ws.resetTerrainDamageFactor(NaN);
        assertNear(1, _root.地形伤害系数, 0.0001, "resetTerrainDamageFactor(NaN) falls back to 1");

        ws.resetTerrainDamageFactor(-5);
        assertNear(1, _root.地形伤害系数, 0.0001, "resetTerrainDamageFactor(-5) falls back to 1");

        ws.resetTerrainDamageFactor(0);
        assertNear(1, _root.地形伤害系数, 0.0001, "resetTerrainDamageFactor(0) falls back to 1");

        ws.resetTerrainDamageFactor(1.5);
        assertNear(1.5, _root.地形伤害系数, 0.0001, "resetTerrainDamageFactor(1.5)");

        ws.configureEnvironment({});
        assertNear(1, _root.地形伤害系数, 0.0001, "configureEnvironment({}) resets terrain coeff to 1");

        ws.configureEnvironment({地形伤害系数: 1.75});
        assertNear(1.75, _root.地形伤害系数, 0.0001, "configureEnvironment custom terrain coeff");
        assertNear(1.75, ws.getTerrainDamageFactor(), 0.0001, "getTerrainDamageFactor reads 1.75");
    }

    private static function testTerrainMonotonicDecay():Void {
        PurifyEffect.resetTerrainDedupForTest();
        var purify:PurifyEffect = new PurifyEffect();
        var unit:Object = makeUnit(100, 0, 0, 100);
        var ctx:DrugContext = makeCtx("测试净化", unit, 0);

        // value=5（如奶/蒜蓉炒空心菜）不得反向放大，应 1.0 -> 0.87
        _root.地形伤害系数 = 1;
        purify.execute(ctx, {type: "purify", value: 5, scaleWithAlchemy: false});
        assertNear(0.87, _root.地形伤害系数, 0.0001, "value=5 decays 1.0 to 0.87");
        check(_root.地形伤害系数 < 1, "value=5 strictly < 1");

        // value=30 -> 0.545
        _root.地形伤害系数 = 1;
        purify.execute(ctx, {type: "purify", value: 30, scaleWithAlchemy: false});
        assertNear(0.545, _root.地形伤害系数, 0.0001, "value=30 decays 1.0 to 0.545");

        // value=50 连续两次单调递减
        _root.地形伤害系数 = 1;
        purify.execute(ctx, {type: "purify", value: 50, scaleWithAlchemy: false});
        assertNear(0.43125, _root.地形伤害系数, 0.0001, "value=50 first dose");
        purify.execute(ctx, {type: "purify", value: 50, scaleWithAlchemy: false});
        assertNear(0.21796875, _root.地形伤害系数, 0.0001, "value=50 second dose monotonic");

        // value=100（炼金满级净化药剂）-> 0.30
        _root.地形伤害系数 = 1;
        var ctxAlc:DrugContext = makeCtx("净化药剂", unit, 10);
        purify.execute(ctxAlc, {type: "purify", value: 50, scaleWithAlchemy: true});
        assertNear(0.30, _root.地形伤害系数, 0.0001, "alchemy lv10 value=50->100 decays to 0.30");

        // 低于或等于下限 0.09 不反向增大
        _root.地形伤害系数 = 0.05;
        purify.execute(ctx, {type: "purify", value: 50, scaleWithAlchemy: false});
        assertNear(0.05, _root.地形伤害系数, 0.0001, "cur <= base does not increase");

        // applyTerrain=false 跳过地形衰减
        _root.地形伤害系数 = 1;
        purify.execute(ctx, {type: "purify", value: 50, scaleWithAlchemy: false, applyTerrain: false});
        assertNear(1, _root.地形伤害系数, 0.0001, "applyTerrain=false preserves terrain coeff");
    }

    private static function testSameFrameIdDedup():Void {
        PurifyEffect.resetTerrainDedupForTest();
        _root.帧计时器 = {当前帧数: 100};
        _root.地形伤害系数 = 1;

        var purify:PurifyEffect = new PurifyEffect();
        var a1:Object = makeUnit(100, 0, 0, 50);
        var a2:Object = makeUnit(100, 10, 0, 50);
        var a3:Object = makeUnit(100, 20, 0, 50);

        purify.execute(makeCtx("白女仆", a1, 0), {type: "purify", value: 20, id: "白女仆_群体治疗_净化", scaleWithAlchemy: false});
        assertNear(0.636, _root.地形伤害系数, 0.0001, "frame 100 first ally decays terrain to 0.636");
        assertEq(-200, a1.麻痹值, "ally1 paralysis applied");

        purify.execute(makeCtx("白女仆", a2, 0), {type: "purify", value: 20, id: "白女仆_群体治疗_净化", scaleWithAlchemy: false});
        assertNear(0.636, _root.地形伤害系数, 0.0001, "frame 100 second ally same id skips duplicate terrain decay");
        assertEq(-200, a2.麻痹值, "ally2 paralysis still applied");

        purify.execute(makeCtx("白女仆", a3, 0), {type: "purify", value: 20, id: "白女仆_群体治疗_净化", scaleWithAlchemy: false});
        assertNear(0.636, _root.地形伤害系数, 0.0001, "frame 100 third ally same id skips duplicate terrain decay");
        assertEq(-200, a3.麻痹值, "ally3 paralysis still applied");

        _root.帧计时器.当前帧数 = 101;
        purify.execute(makeCtx("白女仆", a1, 0), {type: "purify", value: 20, id: "白女仆_群体治疗_净化", scaleWithAlchemy: false});
        assertNear(0.4176, _root.地形伤害系数, 0.0001, "frame 101 allows new terrain decay");
    }

    private static function testParalysisFloorProtection():Void {
        var purify:PurifyEffect = new PurifyEffect();
        var uUndef:Object = makeUnit(100, 0, 0, 50);
        var uPos:Object = makeUnit(100, 0, 0, 50);
        uPos.麻痹值 = 100;
        var uResist:Object = makeUnit(100, 0, 0, 50);
        uResist.麻痹值 = -500;
        var uNaN:Object = makeUnit(100, 0, 0, 50);
        uNaN.麻痹值 = NaN;

        purify.execute(makeCtx("奶", uUndef, 0), {type: "purify", value: 5, scaleWithAlchemy: false, applyTerrain: false});
        assertEq(-50, uUndef.麻痹值, "undefined paralysis becomes -50");

        purify.execute(makeCtx("奶", uNaN, 0), {type: "purify", value: 5, scaleWithAlchemy: false, applyTerrain: false});
        assertEq(-50, uNaN.麻痹值, "NaN paralysis becomes -50");

        purify.execute(makeCtx("奶", uPos, 0), {type: "purify", value: 5, scaleWithAlchemy: false, applyTerrain: false});
        assertEq(-50, uPos.麻痹值, "+100 paralysis drops to -50");

        purify.execute(makeCtx("奶", uResist, 0), {type: "purify", value: 5, scaleWithAlchemy: false, applyTerrain: false});
        assertEq(-500, uResist.麻痹值, "existing -500 resistance is NOT weakened to -50");

        purify.execute(makeCtx("强净化", uResist, 0), {type: "purify", value: 60, scaleWithAlchemy: false, applyTerrain: false});
        assertEq(-600, uResist.麻痹值, "stronger value=60 lowers -500 to -600");
    }

    private static function testBuffPolarityAndPurifyDebuffs():Void {
        var purify:PurifyEffect = new PurifyEffect();
        var buffEffect:BuffEffect = new BuffEffect();
        var unit:Object = makeUnit(100, 0, 0, 100);
        var bm:BuffManager = new BuffManager(unit, null);
        unit.buffManager = bm;
        var ctx:DrugContext = makeCtx("测试物", unit, 0);

        // BuffEffect 极性自动标记
        buffEffect.execute(ctx, {property: "防御力", calc: "add_negative", value: -30, duration: 1800, buffId: "debuff_药剂_防御力"});
        buffEffect.execute(ctx, {property: "伤害加成", calc: "add_positive", value: 40, duration: 1800, buffId: "药剂_伤害加成"});
        buffEffect.execute(ctx, {property: "防御力", calc: "multiply", value: 0.8, duration: 600, buffId: "debuff_药剂_易伤"});
        buffEffect.execute(ctx, {property: "伤害加成", calc: "multiply", value: 1.2, duration: 600, buffId: "药剂_倍增"});

        var defDebuff:MetaBuff = MetaBuff(bm.getBuffById("debuff_药剂_防御力"));
        var dmgBenefit:MetaBuff = MetaBuff(bm.getBuffById("药剂_伤害加成"));
        var multHarm:MetaBuff = MetaBuff(bm.getBuffById("debuff_药剂_易伤"));
        var multBenefit:MetaBuff = MetaBuff(bm.getBuffById("药剂_倍增"));

        assertEq("harm", defDebuff.hudInfo.polarity, "add_negative + debuff_ has polarity=harm");
        assertEq("benefit", dmgBenefit.hudInfo.polarity, "add_positive has polarity=benefit");
        assertEq("harm", multHarm.hudInfo.polarity, "multiply 0.8 has polarity=harm");
        assertEq("benefit", multBenefit.hudInfo.polarity, "multiply 1.2 has polarity=benefit");

        // 移除多余测试 buff，准备精确断言
        bm.removeBuff("debuff_药剂_易伤");
        bm.removeBuff("药剂_倍增");
        bm.update(0);
        assertEq(70, unit.防御力, "initial defense reduced to 70");
        assertEq(90, unit.伤害加成, "initial damage boosted to 90");

        // 无 debuff_ 前缀的战斗负面状态（仅靠 polarity="harm" 识别，如蜘蛛网）
        var webMeta:MetaBuff = new MetaBuff(
            [new PodBuff("行走X速度", BuffCalculationType.MULT_NEGATIVE, 0.5)],
            [new TimeLimitComponent(200)],
            0
        );
        webMeta.hudInfo = {name: "蜘蛛网", description: "减速", polarity: "harm", stacks: 0};
        bm.addBuff(webMeta, "蜘蛛网");

        // 无计时器常驻 debuff（门槛 >= 50）
        var permMeta:MetaBuff = new MetaBuff(
            [new PodBuff("伤害加成", BuffCalculationType.ADD_NEGATIVE, -10)],
            [],
            0
        );
        permMeta.hudInfo = {name: "常驻虚弱", description: "虚弱", polarity: "harm", stacks: 0};
        bm.addBuff(permMeta, "debuff_常驻_虚弱");
        bm.update(0);

        assertEq(5, unit.行走X速度, "web slows speed to 5");
        assertEq(80, unit.伤害加成, "permanent debuff lowers damage to 80");

        // 1) 未写 clearDebuffs（如奶，value=5）默认按 debuff_ + harm 缩短时间
        purify.execute(ctx, {type: "purify", value: 5, scaleWithAlchemy: false, applyTerrain: false});
        assertNear(1500, defDebuff.getPrimaryTimer().getRemaining(), 0.001, "value=5 cuts 1800f debuff to 1500f");
        assertNear(166, webMeta.getPrimaryTimer().getRemaining(), 0.001, "value=5 cuts 200f harm web to 166f");
        assertNear(1800, dmgBenefit.getPrimaryTimer().getRemaining(), 0.001, "benefit buff timer untouched");
        check(bm.getBuffById("debuff_常驻_虚弱") != null, "value=5 does not dispel permanent debuff");

        // 2) clearDebuffs="none" 关闭 debuff 净化，只影响麻痹值
        purify.execute(ctx, {type: "purify", value: 100, scaleWithAlchemy: false, clearDebuffs: "none", applyTerrain: false});
        assertNear(1500, defDebuff.getPrimaryTimer().getRemaining(), 0.001, "clearDebuffs=none skips debuff reduction");
        check(bm.getBuffById("debuff_常驻_虚弱") != null, "clearDebuffs=none skips permanent dispel");
        assertEq(-1000, unit.麻痹值, "clearDebuffs=none still sets paralysis floor");

        // 3) 短残余 <= 15 帧直接清除
        var shortMeta:MetaBuff = new MetaBuff(
            [new PodBuff("防御力", BuffCalculationType.ADD, -5)],
            [new TimeLimitComponent(20)],
            0
        );
        shortMeta.hudInfo = {name: "短debuff", polarity: "harm", stacks: 0};
        bm.addBuff(shortMeta, "debuff_短残余");
        bm.update(0);
        purify.execute(ctx, {type: "purify", value: 5, scaleWithAlchemy: false, applyTerrain: false});
        check(bm.getBuffById("debuff_短残余") == null, "residual <= 15f is immediately removed");

        // 4) 净化药剂 value=50：166f 蜘蛛网归零消除、常驻 debuff 达到阈值 50 清除、长食品 debuff 缩至约 1/3
        var remBefore50:Number = defDebuff.getPrimaryTimer().getRemaining(); // 1250
        purify.execute(ctx, {type: "purify", value: 50, scaleWithAlchemy: false, clearDebuffs: "debuff_", applyTerrain: false});
        var expected50:Number = remBefore50 - Math.ceil(remBefore50 * 50 / 75);
        assertNear(expected50, defDebuff.getPrimaryTimer().getRemaining(), 0.001, "value=50 cuts remaining time by 2/3");
        check(bm.getBuffById("蜘蛛网") == null, "value=50 dispels timed combat harm buff immediately");
        assertEq(10, unit.行走X速度, "speed restored immediately to 10");
        check(bm.getBuffById("debuff_常驻_虚弱") == null, "value=50 dispels permanent debuff");
        assertEq(90, unit.伤害加成, "damage restored to 90 while benefit buff preserved");
        assertNear(1800, dmgBenefit.getPrimaryTimer().getRemaining(), 0.001, "benefit buff still intact");

        bm.destroy();
    }

    private static function testGroupPurifyAndPlayEffect():Void {
        PurifyEffect.resetTerrainDedupForTest();
        var purify:PurifyEffect = new PurifyEffect();

        var caster:Object = makeUnit(100, 100, 100, 100);
        caster.麻痹值 = 80;
        caster.buffManager = new BuffManager(caster, null);

        var allyNear:Object = makeUnit(100, 150, 120, 100);
        allyNear.麻痹值 = 60;
        allyNear.buffManager = new BuffManager(allyNear, null);

        var allyFar:Object = makeUnit(100, 900, 100, 100);
        allyFar.麻痹值 = 40;

        var allyDead:Object = makeUnit(0, 110, 100, 100);
        allyDead.麻痹值 = 40;

        var cDebuff:MetaBuff = new MetaBuff([new PodBuff("防御力", BuffCalculationType.ADD_NEGATIVE, -20)], [new TimeLimitComponent(200)], 0);
        cDebuff.hudInfo = {name: "毒雾", polarity: "harm", stacks: 0};
        caster.buffManager.addBuff(cDebuff, "debuff_毒雾");

        var aDebuff:MetaBuff = new MetaBuff([new PodBuff("防御力", BuffCalculationType.ADD_NEGATIVE, -20)], [new TimeLimitComponent(80)], 0);
        aDebuff.hudInfo = {name: "毒雾", polarity: "harm", stacks: 0};
        allyNear.buffManager.addBuff(aDebuff, "debuff_毒雾");
        caster.buffManager.update(0);
        allyNear.buffManager.update(0);

        // 含重复施法者、超距友军与死亡友军
        PurifyEffect.groupTargetResolver = function(u):Array {
            return [u, allyNear, allyFar, allyDead];
        };

        _root.地形伤害系数 = 1;
        var ctx:DrugContext = makeCtx("战队药箱", caster, 0);
        purify.execute(ctx, {type: "purify", value: 15, target: "group", scaleWithAlchemy: false, rangeX: 200, rangeY: 200});

        // 地形伤害系数只下降一次：0.09 + 0.91 * 30 / 45 = 0.6966666...
        assertNear(0.6966666667, _root.地形伤害系数, 0.0001, "group purify decays terrain coeff ONCE");
        assertEq(-150, caster.麻痹值, "caster paralysis updated");
        assertEq(-150, allyNear.麻痹值, "near ally paralysis updated");
        assertEq(40, allyFar.麻痹值, "far ally skipped by range");
        assertEq(40, allyDead.麻痹值, "dead ally skipped");

        assertNear(110, cDebuff.getPrimaryTimer().getRemaining(), 0.001, "caster debuff shortened 200->110");
        check(allyNear.buffManager.getBuffById("debuff_毒雾") == null, "near ally 80f debuff cleared immediately");
        assertEq(100, allyNear.防御力, "near ally defense restored to 100");

        // 不设 rangeX/rangeY 时（战队药箱全图友军）：远端活友军生效，死亡友军仍跳过，地形系数仅再降一次
        purify.execute(ctx, {type: "purify", value: 15, target: "group", scaleWithAlchemy: false});
        assertEq(-150, allyFar.麻痹值, "full-scene group purify reaches allyFar");
        assertEq(40, allyDead.麻痹值, "dead ally still skipped without range");
        assertNear(0.4944444444, _root.地形伤害系数, 0.0001, "second group cast decays terrain coeff once more");

        // PlayEffectEffect target="group" 覆盖
        var recorded:Array = [];
        EffectSystem["Effect"] = function(effectType:String, x:Number, y:Number, scaleX:Number):MovieClip {
            recorded.push({name: effectType, x: x, y: y, scale: scaleX});
            return null;
        };
        PlayEffectEffect.groupTargetResolver = function(u):Array {
            return [u, allyNear, allyFar, allyDead];
        };
        var fx:PlayEffectEffect = new PlayEffectEffect();
        fx.execute(ctx, {type: "playEffect", name: "净化动画", target: "group", scale: 120});
        assertEq(3, recorded.length, "group playEffect emits for 3 living targets");
        assertEq(150, recorded[1].x, "second effect targets allyNear.x");
        assertEq(120, recorded[1].scale, "group playEffect preserves scale");

        caster.buffManager.destroy();
        allyNear.buffManager.destroy();
    }
}