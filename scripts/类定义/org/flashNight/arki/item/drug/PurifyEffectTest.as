
import org.flashNight.arki.bullet.BulletComponent.Collider.AABBCollider;
import org.flashNight.arki.component.Buff.*;
import org.flashNight.arki.component.Buff.Component.*;
import org.flashNight.arki.component.Buff.Effect.*;
import org.flashNight.arki.component.Effect.EffectSystem;
import org.flashNight.arki.hud.PlayerHudBuffProjection;
import org.flashNight.arki.item.drug.DrugContext;
import org.flashNight.arki.item.drug.DrugEffectRegistry;
import org.flashNight.arki.item.drug.effects.*;
import org.flashNight.arki.unit.UnitComponent.Targetcache.*;
import org.flashNight.gesh.xml.XMLParser;
import org.flashNight.neur.Event.EventDispatcher;

/** #281：真实药剂数据、BuffManager 提交时序与净化消费者。 */
class org.flashNight.arki.item.drug.PurifyEffectTest {
    private static var passed:Number;
    private static var failed:Number;
    private static var completed:Boolean;
    private static var watchdog:MovieClip;
    private static var world:MovieClip;
    private static var saved:Object;
    private static var documents:Array;
    private static var xmlPaths:Array;
    private static var serial:Number;
    private static var emitted:Object;
    private static var shotCount:Number;
    private static var visuals:Array;

    public static function runAllTests():Void {
        passed = 0;
        failed = 0;
        completed = false;
        serial = 0;
        documents = [];
        xmlPaths = ["消耗品_药剂_食品.xml", "消耗品_酒水.xml", "消耗品_药剂.xml"];
        saved = {world:_root.gameworld, clock:_root.帧计时器, control:_root.控制目标,
            shoot:_root.子弹区域shoot传递, inventory:_root.物品栏, effect:EffectSystem["Effect"]};
        world = _root.createEmptyMovieClip("__purifyWorld", _root.getNextHighestDepth());
        _root.gameworld = world;
        _root.帧计时器 = {当前帧数:100, 帧率:30};
        try {
            testPrefixAndHudPolarity();
            testNonPrefixAttributes();
            testOutsidePurify();
            testTailAndCallbacks();
            testInvalidInputs();
            testPauseAndDeactivation();
            testPendingAdd();
            testVulnerabilityTransactions(true);
            testVulnerabilityTransactions(false);
            testPurifyDuringEject();
            testHitCallbacks();
            testScanMark();
            testParalysisFloor();
            testHudProjection();
        } catch (error) {
            check(false, "同步用例异常: " + error);
        }

        watchdog = _root.createEmptyMovieClip("__purifyWatch", _root.getNextHighestDepth());
        watchdog.startedAt = getTimer();
        watchdog.onEnterFrame = function():Void {
            if (getTimer() - this.startedAt > 12000) {
                PurifyEffectTest.check(false, "真实药剂 XML 加载超时");
                PurifyEffectTest.finish();
            }
        };
        loadDocument(0);
    }

    private static function check(ok:Boolean, label:String):Void {
        if (ok) {
            passed++;
        } else {
            failed++;
            trace("[FAIL] " + label);
        }
    }

    private static function equal(expected, actual, label:String):Void {
        check(expected === actual || (expected === null && actual == null), label + " 预期=" + expected + " 实际=" + actual);
    }

    private static function near(expected:Number, actual:Number, label:String):Void {
        check(isFinite(actual) && Math.abs(expected - actual) < 0.00001,
            label + " 预期=" + expected + " 实际=" + actual);
    }

    private static function initUnit(unit:Object, hp:Number, callbacks:Object):Void {
        unit.hp = hp;
        unit.hp满血值 = 5000;
        unit.mp = 20;
        unit.mp满血值 = 100;
        unit.麻痹值 = 100;
        unit.防御力 = 100;
        unit.伤害加成 = 50;
        unit.暴击率 = 10;
        unit.行走X速度 = 10;
        unit.躲闪率 = 100;
        unit.重量 = 60;
        unit.damageTakenMultiplier = 1;
        unit.ti61CrumbleTakenMultiplier = 1;
        unit.buffManager = new BuffManager(unit, callbacks);
    }

    private static function makeUnit(callbacks:Object):Object {
        var unit:Object = {_x:100, _y:80};
        initUnit(unit, 100, callbacks);
        return unit;
    }

    private static function context(unit:Object, name:String, item:Object, level:Number):DrugContext {
        var ctx:DrugContext = DrugContext.createWithData(name, unit, item);
        ctx.alchemyLevel = level;
        ctx.hudSource = {kind:"drug", key:name};
        return ctx;
    }

    private static function purify(unit:Object, value:Number, scale:Boolean, level:Number):Void {
        var effect:PurifyEffect = new PurifyEffect();
        effect.execute(context(unit, "净化测试", null, level), {value:value, scaleWithAlchemy:scale});
    }

    private static function makeMeta(frames:Number, property:String, calc:String, value:Number):MetaBuff {
        var components:Array = frames > 0 ? [new TimeLimitComponent(frames)] : [];
        return new MetaBuff([new PodBuff(property, calc, value)], components, 0);
    }

    private static function defenseDebuff(bm:BuffManager, id:String, frames:Number):MetaBuff {
        var meta:MetaBuff = makeMeta(frames, "防御力", BuffCalculationType.ADD_NEGATIVE, -20);
        bm.addBuffImmediate(meta, id);
        return meta;
    }

    private static function remaining(bm:BuffManager, id:String):Number {
        var meta:MetaBuff = MetaBuff(bm.getBuffById(id));
        var timer:TimeLimitComponent = meta == null ? null : meta.getPrimaryTimer();
        return timer == null ? -1 : timer.getRemaining();
    }

    private static function checkResult(result:Object, removed:Number, reduced:Number, label:String):Void {
        equal(removed, result.removed, label + " removed");
        equal(reduced, result.reduced, label + " reduced");
        equal(removed + reduced, result.affected, label + " affected");
    }

    private static function checkPodsGone(bm:BuffManager, metaId:String, pods:Array, label:String):Void {
        equal(0, bm.getInjectedPodIds(metaId).length, label + " 注入列表清空");
        for (var i:Number = 0; i < pods.length; i++) {
            equal(null, bm.getBuffById(String(pods[i])), label + " 注入 Pod 已移除 #" + i);
        }
    }

    // P02：前缀是唯一分类条件，HUD 极性不参与。
    private static function testPrefixAndHudPolarity():Void {
        var unit:Object = makeUnit(null);
        var bm:BuffManager = unit.buffManager;
        var id:String = "debuff_资格";
        var excluded:MetaBuff = defenseDebuff(bm, "临时虚弱", 300);
        excluded.hudInfo = {polarity:"harm"};
        var polarities:Array = [null, "harm", "benefit", "neutral"];
        for (var i:Number = 0; i < polarities.length; i++) {
            var label:String = "P02 " + polarities[i];
            var meta:MetaBuff = defenseDebuff(bm, id, 300);
            meta.hudInfo = i == 0 ? null : {polarity:polarities[i]};
            checkResult(bm.purifyDebuffs(5), 0, 1, label);
            equal(250, remaining(bm, id), label + " 300→250");
            checkResult(bm.purifyDebuffs(100), 1, 0, label);
            bm.update(0);
            equal(null, bm.getBuffById(id), label + " 终止");
            equal(excluded, bm.getBuffById("临时虚弱"), label + " 非前缀的 harm 保留");
            equal(300, remaining(bm, "临时虚弱"), label + " 非前缀时长不变");
        }
        bm.destroy();
    }

    // P03：数值方向与玩法收益均不改变净化资格。
    private static function testNonPrefixAttributes():Void {
        var unit:Object = makeUnit(null);
        var bm:BuffManager = unit.buffManager;
        var cases:Array = [
            ["临时虚弱", "防御力", BuffCalculationType.ADD_NEGATIVE, -20, 80],
            ["霸体减伤", "damageTakenMultiplier", BuffCalculationType.MULT_NEGATIVE, 0.5, 0.5],
            ["轻量化", "重量", BuffCalculationType.ADD_NEGATIVE, -10, 50],
            ["轻装防御", "躲闪率", BuffCalculationType.PERCENT, -0.3, 70]
        ];
        for (var i:Number = 0; i < cases.length; i++) {
            var row:Array = cases[i];
            bm.addBuff(makeMeta(300, row[1], row[2], row[3]), row[0]);
        }
        bm.update(0);
        for (var before:Number = 0; before < cases.length; before++) {
            near(cases[before][4], unit[cases[before][1]], "P03 初始属性 " + cases[before][1]);
        }
        checkResult(bm.purifyDebuffs(100), 0, 0, "P03");
        bm.update(0);
        for (var j:Number = 0; j < cases.length; j++) {
            var fixture:Array = cases[j];
            equal(300, remaining(bm, fixture[0]), "P03 保留 " + fixture[0]);
            near(fixture[4], unit[fixture[1]], "P03 属性 " + fixture[1]);
        }
        bm.destroy();
    }

    // P04：无计时的 Meta、独立 Pod 与真实灰蛊控制器均置于常规管理路径。
    private static function testOutsidePurify():Void {
        var unit:Object = makeUnit(null);
        var bm:BuffManager = unit.buffManager;
        unit.dispatcher = new EventDispatcher();
        var source:Object = makeUnit(null);
        var permanent:MetaBuff = defenseDebuff(bm, "debuff_无计时", 0);
        var pod:PodBuff = new PodBuff("重量", BuffCalculationType.ADD_NEGATIVE, -10);
        bm.addBuff(pod, "debuff_独立Pod");
        var config:Object = {stackGroup:"purifyFixture", profileId:"purifyFixture",
            duration:180, hitStacks:2, damagePerStack:0.1};
        check(ToughnessVulnerabilityController.applyToTarget(unit, source, config, {}), "P04 注册真实破韧控制器");
        var controllerId:String = ToughnessVulnerabilityController.getControllerIdFor(config);
        var controller:ToughnessVulnerabilityController = ToughnessVulnerabilityController(bm.getBuffById(controllerId));
        var etchId:String = GrayGooShotgunEtch.getBuffIdFor(config);
        check(GrayGooShotgunEtch.applyToTarget(unit, source,
            {stackGroup:config.stackGroup, delayFrames:30, detonationCrumble:0.1}, {霰弹值:2}), "P04 注册真实霰弹蚀刻");
        var etch:GrayGooShotgunEtch = GrayGooShotgunEtch(bm.getBuffById(etchId));
        var candidateFrames:Number = controller.getCandidateRemainingFrames(source, config);
        var controllerFrames:Number = controller.getRemainingFrames();
        var etchFrames:Number = remaining(bm, etchId);
        equal(2, controller.getCandidateStackCount(source, config), "P04 初始蚀刻层数");
        check(candidateFrames > 0 && etch.isPending() && etchFrames == 30, "P04 控制器已启动");
        near(1.2, unit.damageTakenMultiplier, "P04 初始控制器易伤");
        checkResult(bm.purifyDebuffs(100), 0, 0, "P04 v100");
        checkResult(bm.purifyDebuffs(200), 0, 0, "P04 v200");
        bm.update(0);
        equal(permanent, bm.getBuffById("debuff_无计时"), "P04 无计时 Meta 保留");
        equal(null, permanent.getPrimaryTimer(), "P04 无主 timer");
        equal(80, unit.防御力, "P04 Meta 属性保留");
        equal(pod, bm.getBuffById("debuff_独立Pod"), "P04 独立 Pod 保留");
        equal(50, unit.重量, "P04 独立 Pod 属性保留");
        equal(controller, bm.getBuffById(controllerId), "P04 控制器身份不变");
        equal(1, controller.getCandidateCount(), "P04 候选数不变");
        equal(2, controller.getCandidateStackCount(source, config), "P04 层数不变");
        equal(candidateFrames, controller.getCandidateRemainingFrames(source, config), "P04 候选时间不变");
        equal(controllerFrames, controller.getRemainingFrames(), "P04 控制器主计时不变");
        near(1.2, unit.damageTakenMultiplier, "P04 易伤不变");
        equal(etch, bm.getBuffById(etchId), "P04 霰弹蚀刻身份不变");
        check(etch.isPending() && unit.grayGooEtchPending === true, "P04 蚀刻仍待结算");
        equal(etchFrames, remaining(bm, etchId), "P04 蚀刻时间不变");
        bm.destroy();
        unit.dispatcher.destroy();
        source.buffManager.destroy();
    }

    // P05：相邻尾段边界、纯减时不重算、Meta 与两个注入 Pod 的各自移除通知。
    private static function testTailAndCallbacks():Void {
        var observed:Object = {meta:0, pods:0, changed:0};
        var unit:Object = makeUnit({
            onBuffRemoved:function(id:String, buff:IBuff):Void {
                if (id == "debuff_尾段") observed.meta++;
                if (buff.isPod()) observed.pods++;
            },
            onPropertyChanged:function(property:String, current:Number):Void {
                observed.changed++;
            }
        });
        var bm:BuffManager = unit.buffManager;
        var id:String = "debuff_尾段";
        var meta:MetaBuff = new MetaBuff([
            new PodBuff("防御力", BuffCalculationType.ADD_NEGATIVE, -20),
            new PodBuff("伤害加成", BuffCalculationType.ADD_NEGATIVE, -10)
        ], [new TimeLimitComponent(46)], 0);
        bm.addBuffImmediate(meta, id);
        equal(80, unit.防御力, "P05 防御 Pod 生效");
        equal(40, unit.伤害加成, "P05 伤害 Pod 生效");
        var metaId:String = meta.getId();
        var pods:Array = bm.getInjectedPodIds(metaId);
        equal(2, pods.length, "P05 注入两个 Pod");
        var timer:TimeLimitComponent = meta.getPrimaryTimer();
        var changes:Number = observed.changed;
        check(changes > 0, "P05 属性变化回调已接通");
        checkResult(bm.purifyDebuffs(5), 0, 1, "P05 R=46");
        bm.update(0);
        equal(16, timer.getRemaining(), "P05 46→16");
        equal(meta, bm.getBuffById(id), "P05 16f 保留");
        equal(changes, observed.changed, "P05 纯减时没有属性回调");
        equal(0, observed.meta + observed.pods, "P05 纯减时没有移除回调");

        timer.setRemaining(45);
        checkResult(bm.purifyDebuffs(5), 1, 0, "P05 R=45");
        equal(0, timer.getRemaining(), "P05 45→0");
        bm.update(0);
        bm.update(1);
        equal(null, bm.getBuffById(id), "P05 终止后无 Meta");
        equal(1, observed.meta, "P05 Meta 只移除一次");
        equal(2, observed.pods, "P05 每个注入 Pod 移除一次");
        checkPodsGone(bm, metaId, pods, "P05");
        equal(100, unit.防御力, "P05 防御恢复");
        equal(50, unit.伤害加成, "P05 伤害恢复");
        equal(changes + 2, observed.changed, "P05 两个属性恢复各通知一次");

        var longMeta:MetaBuff = defenseDebuff(bm, "debuff_长时", 1800);
        var longTimer:TimeLimitComponent = longMeta.getPrimaryTimer();
        for (var i:Number = 0; i < 4; i++) {
            var oldRemain:Number = longTimer.getRemaining();
            checkResult(bm.purifyDebuffs(5), 0, 1, "P05 长时 #" + i);
            check(longTimer.getRemaining() < oldRemain && longTimer.getRemaining() > 15,
                "P05 长时剩余严格递减 #" + i);
        }
        bm.destroy();
    }

    // P06：覆盖强度和计时器两个输入边界。恢复异常计时器后推进提交点以探测误排队。
    private static function testInvalidInputs():Void {
        var unit:Object = makeUnit(null);
        var bm:BuffManager = unit.buffManager;
        var id:String = "debuff_异常输入";
        var meta:MetaBuff = defenseDebuff(bm, id, 300);
        var values:Array = [NaN, Infinity, -Infinity, 0, -10, 1e308];
        check(isFinite(values[5]) && !isFinite(300 * values[5]), "P06 有限输入导致中间乘法溢出");
        for (var i:Number = 0; i < values.length; i++) {
            checkResult(bm.purifyDebuffs(values[i]), 0, 0, "P06 manager " + values[i]);
            bm.update(0);
            equal(meta, bm.getBuffById(id), "P06 输入后身份不变 #" + i);
            equal(300, remaining(bm, id), "P06 输入后时间不变 #" + i);
            equal(80, unit.防御力, "P06 输入后属性有限 #" + i);
        }

        var effectValues:Array = [NaN, Infinity, -5, 0];
        for (var mode:Number = 0; mode < 2; mode++) {
            for (var j:Number = 0; j < effectValues.length; j++) {
                var label:String = "P06 effect " + effectValues[j] + " 炼金开关=" + mode;
                purify(unit, effectValues[j], mode == 1, 0);
                equal(100, unit.麻痹值, label + " 麻痹不变");
                equal(300, remaining(bm, id), label + " timer 不变");
            }
        }
        // 有等级时 DrugContext 先换算有效强度。用长时样本区分有限的炼金加成与异常值污染。
        for (var bonusMode:Number = 0; bonusMode < 2; bonusMode++) {
            for (var testIndex:Number = 0; testIndex < effectValues.length; testIndex++) {
                meta.getPrimaryTimer().setRemaining(1800);
                unit.麻痹值 = 100;
                purify(unit, effectValues[testIndex], bonusMode == 1, 10);
                check(isFinite(unit.麻痹值), "P06 非零炼金等级不污染麻痹值 #" + testIndex);
                equal(meta, bm.getBuffById(id), "P06 非零炼金等级不误删除 #" + testIndex);
                if (testIndex == 1 || bonusMode == 0) {
                    equal(1800, remaining(bm, id), "P06 无有效强度时不减时 #" + testIndex);
                    equal(100, unit.麻痹值, "P06 无有效强度时麻痹不变 #" + testIndex);
                }
            }
        }
        meta.getPrimaryTimer().setRemaining(300);
        unit.麻痹值 = 100;

        var invalidTimers:Array = [0, -5, NaN, Infinity];
        for (var k:Number = 0; k < invalidTimers.length; k++) {
            var timer:TimeLimitComponent = new TimeLimitComponent(invalidTimers[k]);
            var edge:MetaBuff = new MetaBuff([new PodBuff("防御力", BuffCalculationType.ADD_NEGATIVE, -30)], [timer], 0);
            bm.addBuff(edge, "debuff_异常timer");
            equal(edge, bm.getBuffById("debuff_异常timer"), "P06 异常 timer 已提交 #" + k);
            checkResult(bm.purifyDebuffs(5), 0, 1, "P06 仅合法 timer 命中 #" + k);
            if (isNaN(invalidTimers[k])) {
                check(isNaN(timer.getRemaining()), "P06 NaN timer 未被修改");
            } else {
                equal(invalidTimers[k], timer.getRemaining(), "P06 异常 timer 未被修改 #" + k);
            }
            timer.setRemaining(300);
            bm.update(0);
            equal(edge, bm.getBuffById("debuff_异常timer"), "P06 修复计时后未遗留净化删除 #" + k);
            equal(300, timer.getRemaining(), "P06 修复后仍有 300f #" + k);
            equal(70, unit.防御力, "P06 恢复合法计时后 Pod 生效 #" + k);
            bm.removeBuff("debuff_异常timer");
            bm.update(0);
        }
        bm.destroy();
    }

    // P07：暂停状态不阻止净化，待停用 Meta 不会被重复处理。
    private static function testPauseAndDeactivation():Void {
        var unit:Object = makeUnit(null);
        var bm:BuffManager = unit.buffManager;
        var id:String = "debuff_暂停";
        var meta:MetaBuff = defenseDebuff(bm, id, 90);
        var timer:TimeLimitComponent = meta.getPrimaryTimer();
        timer.pause();
        checkResult(bm.purifyDebuffs(5), 0, 1, "P07 暂停期间减时");
        equal(true, timer.isPaused(), "P07 减时后仍暂停");
        equal(60, timer.getRemaining(), "P07 90→60");
        bm.update(10);
        equal(60, timer.getRemaining(), "P07 暂停时 update(10) 不消耗");
        timer.resume();
        bm.update(59);
        equal(1, remaining(bm, id), "P07 恢复后 60→1");
        bm.update(1);
        equal(100, unit.防御力, "P07 到期帧弹出 Pod");
        bm.update(0);
        equal(null, bm.getBuffById(id), "P07 自然到期后移除 Meta");
        equal(100, unit.防御力, "P07 到期属性恢复");

        var tail:MetaBuff = defenseDebuff(bm, id, 45);
        tail.getPrimaryTimer().pause();
        checkResult(bm.purifyDebuffs(5), 1, 0, "P07 暂停的尾段可终止");
        bm.update(0);
        equal(null, bm.getBuffById(id), "P07 暂停尾段提交删除");

        var pending:MetaBuff = defenseDebuff(bm, "debuff_待停用", 300);
        var pendingId:String = pending.getId();
        var pods:Array = bm.getInjectedPodIds(pendingId);
        pending.deactivate();
        equal(2, pending.getCurrentState(), "P07 PENDING_DEACTIVATE");
        bm.purifyDebuffs(5);
        equal(2, pending.getCurrentState(), "P07 净化不复活待停用状态");
        equal(String(pods), String(bm.getInjectedPodIds(pendingId)), "P07 净化不重新注入 Pod");
        bm.update(0);
        equal(null, bm.getBuffById("debuff_待停用"), "P07 正常销毁");
        checkPodsGone(bm, pendingId, pods, "P07");
        equal(100, unit.防御力, "P07 无重复注入");
        bm.destroy();
    }

    // TickComponent 在阶段 2 执行且只触发一次。先注册它，使倒序更新先处理已提交易伤。
    private static function stageTwo(bm:BuffManager, callback:Function, fixture:Object):Void {
        bm.addBuff(new MetaBuff([], [new TickComponent(1, callback, 1, fixture, false)], 0), "净化测试时序");
    }

    private static function testPendingAdd():Void {
        var unit:Object = makeUnit(null);
        var bm:BuffManager = unit.buffManager;
        var fixture:Object = {manager:bm, calls:0, id:"debuff_待新增"};
        stageTwo(bm, function(host:IBuff, count:Number, state:Object):Void {
            state.calls++;
            state.created = PurifyEffectTest.defenseDebuff(state.manager, state.id, 300);
            state.uncommitted = state.manager.getBuffById(state.id) == null;
            state.result = state.manager.purifyDebuffs(100);
        }, fixture);
        bm.update(1);
        equal(1, fixture.calls, "P08 阶段 2 仅回调一次");
        check(fixture.uncommitted === true, "P08 回调内尚未进入外部索引");
        checkResult(fixture.result, 0, 0, "P08 不追溯净化");
        equal(fixture.created, bm.getBuffById(fixture.id), "P08 flush 提交同一实例");
        equal(300, remaining(bm, fixture.id), "P08 提交初始时长");
        bm.update(0);
        equal(80, unit.防御力, "P08 Pod 正常生效");
        bm.destroy();
    }

    private static function applyVulnerability(unit:Object, elder:Boolean, peak:Number, duration:Number):Boolean {
        var behavior:Object = {peak:peak, durationFrames:duration};
        if (elder) return ElderBeamVulnerability.applyToTarget(unit, behavior);
        return FireControlVulnerability.applyToTarget(unit, behavior);
    }

    private static function checkVulnerability(unit:Object, id:String, peak:Number, duration:Number,
                                               age:Number, label:String):Void {
        var bm:BuffManager = unit.buffManager;
        var meta:MetaBuff = MetaBuff(bm.getBuffById(id));
        check(meta != null && meta.isActive(), label + " 活跃 Meta");
        equal(1, bm.getAllMetaBuffs().length, label + " 唯一 Meta");
        equal(1, bm.getBuffsByIdPrefix(id).length, label + " 唯一外部 ID");
        var stats:Object = bm.getDebugInfo();
        equal(3, stats.total, label + " 总数 1 Meta + 2 Pods");
        equal(2, stats.injectedPods, label + " 两个注入 Pod");
        if (meta == null) return;
        equal(duration - age, remaining(bm, id), label + " 主计时");
        var pods:Array = bm.getInjectedPodIds(meta.getId());
        equal(2, pods.length, label + " 实例绑定两个 Pod");
        var expected:Number = 1 + peak * (1 - age / duration);
        var properties:Object = {};
        for (var j:Number = 0; j < pods.length; j++) {
            var pod:PodBuff = PodBuff(bm.getBuffById(String(pods[j])));
            check(pod != null, label + " Pod 可寻址 #" + j);
            if (pod == null) continue;
            properties[pod.getTargetProperty()] = true;
            equal(BuffCalculationType.MULT_POSITIVE, pod.getCalculationType(), label + " Pod 计算类型 #" + j);
            near(expected, pod.getValue(), label + " Pod 衰减 #" + j);
        }
        check(properties.damageTakenMultiplier && properties.ti61CrumbleTakenMultiplier, label + " Pod 分别作用于两个真实属性");
        near(expected, unit.damageTakenMultiplier, label + " 伤害易伤");
        near(expected, unit.ti61CrumbleTakenMultiplier, label + " 击溃易伤");
    }

    private static function checkVulnerabilityGone(unit:Object, id:String, label:String):Void {
        var bm:BuffManager = unit.buffManager;
        equal(null, bm.getBuffById(id), label + " 外部 ID 清空");
        equal(0, bm.getDebugInfo().total, label + " 无残留 Meta 或 Pod");
        equal(1, unit.damageTakenMultiplier, label + " 伤害倍率恢复");
        equal(1, unit.ti61CrumbleTakenMultiplier, label + " 击溃倍率恢复");
    }

    private static function testVulnerabilityTransactions(elder:Boolean):Void {
        var id:String = elder ? ElderBeamVulnerability.ID : FireControlVulnerability.ID;
        var peak:Number = elder ? 0.25 : 0.75;
        var low:Number = elder ? 0.10 : 0.30;
        var duration:Number = elder ? 180 : 30;
        testVulnerabilityOrder(elder, id, low, peak, duration, true);
        testVulnerabilityOrder(elder, id, low, peak, duration, false);
        testVulnerabilityPending(elder, id, low, peak, duration, false);
        testVulnerabilityPending(elder, id, low, peak, duration, true);
    }

    // P09：两种顺序共享真实阶段 2 回调，P09A 的旧 timer 在 flush 替换前仍可查询。
    private static function testVulnerabilityOrder(elder:Boolean, id:String, low:Number, peak:Number,
                                                    duration:Number, purifyFirst:Boolean):Void {
        var label:String = (purifyFirst ? "P09A " : "P09B ") + id;
        var unit:Object = makeUnit(null);
        var bm:BuffManager = unit.buffManager;
        var fixture:Object = {unit:unit, manager:bm, elder:elder, peak:peak, duration:duration,
            id:id, calls:0, purifyFirst:purifyFirst};
        stageTwo(bm, function(host:IBuff, count:Number, state:Object):Void {
            state.calls++;
            state.before = PurifyEffectTest.remaining(state.manager, state.id);
            if (state.purifyFirst) state.result = state.manager.purifyDebuffs(100);
            state.applied = PurifyEffectTest.applyVulnerability(state.unit, state.elder, state.peak, state.duration);
            state.sameDuring = state.manager.getBuffById(state.id) === state.old;
            state.afterApply = PurifyEffectTest.remaining(state.manager, state.id);
            if (!state.purifyFirst) state.result = state.manager.purifyDebuffs(100);
            state.afterPurify = PurifyEffectTest.remaining(state.manager, state.id);
        }, fixture);
        check(applyVulnerability(unit, elder, low, duration), label + " 注册旧实例");
        var oldMeta:MetaBuff = MetaBuff(bm.getBuffById(id));
        var oldMetaId:String = oldMeta.getId();
        var oldPods:Array = bm.getInjectedPodIds(oldMetaId);
        fixture.old = oldMeta;
        bm.update(1);
        equal(1, fixture.calls, label + " 同次 update 只回调一次");
        equal(duration - 1, fixture.before, label + " 旧实例先完成本帧 tick");
        check(fixture.applied === true && fixture.sameDuring === true, label + " 调用期间仍映射旧实例");
        equal(purifyFirst ? 0 : duration, fixture.afterApply, label + " 新建入队或原位刷新");
        equal(0, fixture.afterPurify, label + " 旧 timer 归零");
        checkResult(fixture.result, 1, 0, label);
        if (purifyFirst) {
            var replacement:IBuff = bm.getBuffById(id);
            check(replacement != null && replacement !== oldMeta, label + " flush 后是新实例");
            equal(duration, remaining(bm, id), label + " flush 后满时长");
            bm.update(1);
            equal(replacement, bm.getBuffById(id), label + " 下一提交点保留新实例");
            checkVulnerability(unit, id, peak, duration, 1, label);
        } else {
            equal(oldMeta, bm.getBuffById(id), label + " stage 1 已过，仍待移除");
            bm.update(0);
            checkVulnerabilityGone(unit, id, label);
        }
        checkPodsGone(bm, oldMetaId, oldPods, label);
        bm.destroy();
    }

    // P10/P11：首次 pending 创建与同一回调两次创建都走真实 flush。
    private static function testVulnerabilityPending(elder:Boolean, id:String, low:Number, peak:Number,
                                                      duration:Number, twice:Boolean):Void {
        var label:String = (twice ? "P11 " : "P10 ") + id;
        var lifecycle:Object = {published:[], oldPods:[]};
        var unit:Object = makeUnit({onBuffAdded:function(buffId:String, buff:IBuff):Void {
            if (buffId != id) return;
            lifecycle.published.push(buff);
            if (lifecycle.published.length == 1) lifecycle.oldPods = lifecycle.manager.getInjectedPodIds(buff.getId());
        }});
        var bm:BuffManager = unit.buffManager;
        lifecycle.manager = bm;
        var fixture:Object = {unit:unit, manager:bm, elder:elder, duration:duration, peak:peak,
            low:low, twice:twice, id:id, calls:0};
        stageTwo(bm, function(host:IBuff, count:Number, state:Object):Void {
            state.calls++;
            state.initiallyAbsent = state.manager.getBuffById(state.id) == null;
            if (state.twice) {
                state.first = PurifyEffectTest.applyVulnerability(state.unit, state.elder, state.low, state.duration);
                state.firstPending = state.manager.getBuffById(state.id) == null;
            }
            state.last = PurifyEffectTest.applyVulnerability(state.unit, state.elder, state.peak, state.duration);
            state.lastPending = state.manager.getBuffById(state.id) == null;
        }, fixture);
        bm.update(1);
        equal(1, fixture.calls, label + " 阶段 2 回调一次");
        check(fixture.initiallyAbsent === true && fixture.last === true && fixture.lastPending === true, label + " 新建先入队");
        equal(twice ? 2 : 1, lifecycle.published.length, label + " flush 新建数");
        if (twice) {
            check(fixture.first === true && fixture.firstPending === true, label + " 第一次也未提前提交");
            check(lifecycle.published[0] !== lifecycle.published[1], label + " 两次注册不同实例");
            equal(lifecycle.published[1], bm.getBuffById(id), label + " 后入队者胜出");
            checkPodsGone(bm, lifecycle.published[0].getId(), lifecycle.oldPods, label);
        }
        equal(duration, remaining(bm, id), label + " 提交时未提前计时");
        bm.update(1);
        checkVulnerability(unit, id, peak, duration, 1, label);
        var midpoint:Number = duration / 2;
        bm.update(midpoint - 1);
        checkVulnerability(unit, id, peak, duration, midpoint, label);
        if (elder) {
            checkResult(bm.purifyDebuffs(100), 1, 0, label + " 强净化");
            bm.update(0);
        } else {
            bm.update(duration - midpoint);
            equal(1, unit.damageTakenMultiplier, label + " 到期帧归还伤害倍率");
            equal(1, unit.ti61CrumbleTakenMultiplier, label + " 到期帧归还击溃倍率");
            bm.update(0);
        }
        checkVulnerabilityGone(unit, id, label);
        bm.destroy();
    }

    // P12：_removePodBuffCore 的移除回调早于旧 Meta 外部映射的删除。
    private static function testPurifyDuringEject():Void {
        var id:String = ElderBeamVulnerability.ID;
        var state:Object = {id:id, calls:0, podCalls:0, oldWindow:0};
        var unit:Object = makeUnit({onBuffRemoved:function(removedId:String, buff:IBuff):Void {
            if (!buff.isPod() || state.pods == null ||
                (removedId != state.pods[0] && removedId != state.pods[1])) return;
            state.podCalls++;
            if (state.manager.getBuffById(state.id) === state.old) state.oldWindow++;
            state.seenTimer = state.timer.getRemaining();
            // 从真实注入 Pod 的通知重入净化。两个 Pod 分别验证该窗口。
            state.reentryRemoved += state.manager.purifyDebuffs(100).affected;
        }});
        var bm:BuffManager = unit.buffManager;
        state.manager = bm;
        state.unit = unit;
        state.reentryRemoved = 0;
        stageTwo(bm, function(host:IBuff, count:Number, fixture:Object):Void {
            fixture.calls++;
            fixture.outer = fixture.manager.purifyDebuffs(100);
            fixture.applied = ElderBeamVulnerability.applyToTarget(fixture.unit, {peak:0.25, durationFrames:180});
            fixture.stillOld = fixture.manager.getBuffById(fixture.id) === fixture.old;
        }, state);
        check(ElderBeamVulnerability.applyToTarget(unit, {peak:0.10, durationFrames:180}), "P12 旧实例注册");
        var oldMeta:MetaBuff = MetaBuff(bm.getBuffById(id));
        var oldMetaId:String = oldMeta.getId();
        state.old = oldMeta;
        state.pods = bm.getInjectedPodIds(oldMetaId);
        state.timer = oldMeta.getPrimaryTimer();
        bm.update(1);
        equal(1, state.calls, "P12 阶段 2 回调一次");
        check(state.applied === true && state.stillOld === true, "P12 旧实例归零后新实例仍在待提交队列");
        checkResult(state.outer, 1, 0, "P12 外层净化");
        equal(2, state.podCalls, "P12 两个旧 Pod 移除通知");
        equal(2, state.oldWindow, "P12 Pod 通知时外部 ID 仍指向旧 Meta");
        equal(0, state.seenTimer, "P12 回调观察到旧 timer 已归零");
        equal(0, state.reentryRemoved, "P12 重入不再处理已归零的 Meta");
        var replacement:IBuff = bm.getBuffById(id);
        check(replacement != null && replacement !== oldMeta, "P12 新实例已注册");
        bm.update(0);
        bm.update(1);
        equal(replacement, bm.getBuffById(id), "P12 后续提交点没有遗留删除");
        checkPodsGone(bm, oldMetaId, state.pods, "P12");
        checkVulnerability(unit, id, 0.25, 180, 1, "P12");
        bm.destroy();
    }

    // P13：走装备/战技入口和实际手部发射帧，只在射击分发端捕获属性。
    private static function testHitCallbacks():Void {
        var shooter:MovieClip = world.createEmptyMovieClip("hitShooter", world.getNextHighestDepth());
        initUnit(shooter, 100, null);
        shooter.version = 1;
        shooter.内力 = 10;
        shooter.空手攻击力 = 50;
        shooter.攻击模式 = "空手";
        shooter.Z轴坐标 = 80;
        shooter._y = 80;
        shooter.按键检测 = function():Boolean { return true; };
        shooter.状态改变 = function(state:String):Void { this.状态 = state; };
        shooter.根据模式重新读取武器加成 = function():Void {};
        var hand:MovieClip = shooter.createEmptyMovieClip("man", 1);
        hand.攻击点 = hand.createEmptyMovieClip("attackPoint", 1);
        hand.测试手部发射帧 = _root.技能函数.手部发射攻击;

        _root.物品栏 = {装备栏:{
            glove:{value:{当前战技:1}},
            getNameString:function(slot:String):String { return ""; },
            getItem:function(slot:String):Object { return this.glove; }
        }};
        shotCount = 0;
        _root.子弹区域shoot传递 = function(properties:Object):Void {
            PurifyEffectTest.emitted = properties;
            PurifyEffectTest.shotCount++;
        };
        try {
            testSpeedOrders(shooter, hand, "蜘蛛网", 90);
            testSpeedOrders(shooter, hand, "伸手及月", 150);
        } finally {
            _root.子弹区域shoot传递 = saved.shoot;
            _root.物品栏 = saved.inventory;
            delete hand.onUnload;
            shooter.buffManager.destroy();
            shooter.removeMovieClip();
        }
    }

    private static function hitWithSkill(shooter:MovieClip, hand:MovieClip, target:Object, kind:String):Void {
        emitted = null;
        var previousCount:Number = shotCount;
        if (kind == "蜘蛛网") {
            var ref:Object = {自机:shooter, 是否为主角:true, 版本号:shooter.version};
            _root.装备生命周期函数.蜘蛛侠蛛丝初始化(ref, {});
            shooter.防具技能冷却时长 = 1000;
            _root.装备生命周期函数.蜘蛛侠蛛丝周期(ref, {});
        } else {
            _root.主动战技函数.空手.贯空天盖战技.释放(shooter);
        }
        // 空 MovieClip 没有作品时间轴，且 TestLoader 在 _root 作用域内 include 主角技能时裸 _parent 指向 _root._parent。
        // 直接从真实战技入口写入的 shooter.手部发射子弹属性 组装并分发生产子弹对象。
        equal("手部发射", shooter.技能名, "P13 " + kind + " 走真实战技路由");
        check(shooter.手部发射子弹属性 != null, "P13 " + kind + " 写入真实手部发射子弹属性");
        var bullet:Object = _root.子弹属性初始化(hand.攻击点);
        if (shooter.手部发射子弹属性 != null) {
            for (var propKey:String in shooter.手部发射子弹属性) {
                bullet[propKey] = shooter.手部发射子弹属性[propKey];
            }
            delete shooter.手部发射子弹属性;
        }
        _root.子弹区域shoot传递(bullet);
        equal(previousCount + 1, shotCount, "P13 " + kind + " 发射帧只分发一次");
        equal(kind, emitted.子弹种类, "P13 捕获真实构造的 " + kind);
        check(typeof emitted.击中时触发函数 == "function", "P13 " + kind + " 有生产命中回调");
        if (typeof emitted.击中时触发函数 != "function") return;
        emitted.命中对象 = target;
        emitted.已爆炸 = true; // 只跳过美术的爆炸帧跳转。
        emitted.击中时触发函数();
        target.buffManager.update(0);
    }

    private static function testSpeedOrders(shooter:MovieClip, hand:MovieClip, kind:String, frames:Number):Void {
        var id:String = "debuff_" + kind;
        for (var order:Number = 0; order < 2; order++) {
            var label:String = "P13 " + kind + " 顺序 " + order;
            var target:Object = makeUnit(null);
            var bm:BuffManager = target.buffManager;
            var speed:MetaBuff = makeMeta(300, "行走X速度", BuffCalculationType.MULT_POSITIVE, 1.2);
            if (order == 0) {
                bm.addBuffImmediate(speed, "正速度");
                near(12, target.行走X速度, label + " 正加速先到");
            }
            hitWithSkill(shooter, hand, target, kind);
            if (order == 1) {
                near(1, target.行走X速度, label + " 只有减速时");
                bm.addBuffImmediate(speed, "正速度");
            }
            equal(frames, remaining(bm, id), label + " 外部 ID 与首个时长");
            near(1.2, target.行走X速度, label + " 10 × 1.2 × 0.1");
            if (order == 1) {
                bm.update(20);
                equal(frames - 20, remaining(bm, id), label + " 刷新前已消耗");
                hitWithSkill(shooter, hand, target, kind);
                equal(frames, remaining(bm, id), label + " 重施恢复默认时长");
                equal(1, bm.getBuffsByIdPrefix(id).length, label + " 刷新仍唯一");
                near(1.2, target.行走X速度, label + " 刷新不累乘");
            }
            var speedRemain:Number = remaining(bm, "正速度");
            purify(target, 100, false, 0);
            equal(null, bm.getBuffById(id), label + " 强净化清除真实命中减速");
            equal(speed, bm.getBuffById("正速度"), label + " 正加速实例保留");
            equal(speedRemain, remaining(bm, "正速度"), label + " 正加速时长保留");
            near(12, target.行走X速度, label + " 净化后速度恢复到加速值");
            bm.destroy();
        }
    }

    private static function testScanMark():Void {
        var enemy:MovieClip = world.createEmptyMovieClip("scanEnemy", world.getNextHighestDepth());
        initUnit(enemy, 100, null);
        enemy.是否为敌人 = true;
        var bm:BuffManager = enemy.buffManager;
        var id:String = "debuff_剑圣扫描标记";
        for (var cycle:Number = 0; cycle < 2; cycle++) {
            _root.装备生命周期函数.施加扫描标记(enemy, 1.5, 120);
            bm.update(0);
            equal(120, remaining(bm, id), "P14 扫描周期 " + cycle + " 注册外部 ID 与时长");
            near(150, enemy.躲闪率, "P14 实际闪避降低");
            purify(enemy, 100, false, 0);
            equal(null, bm.getBuffById(id), "P14 扫描标记被净化");
            equal(100, enemy.躲闪率, "P14 躲闪率恢复");
        }
        _root.装备生命周期函数.施加扫描标记(enemy, 1.5, 0);
        bm.update(0);
        var mark:MetaBuff = MetaBuff(bm.getBuffById(id));
        check(mark != null && mark.getPrimaryTimer() == null, "P14 duration=0 创建无计时标记");
        purify(enemy, 200, false, 0);
        equal(mark, bm.getBuffById(id), "P14 无计时扫描标记保留");
        near(150, enemy.躲闪率, "P14 无计时扫描属性保留");
        bm.destroy();
        enemy.removeMovieClip();
    }

    // P22：麻痹值下限、现有更强抗性及非有限值。
    private static function testParalysisFloor():Void {
        var unit:Object = makeUnit(null);
        var initial:Array = [undefined, NaN, 100, -1000];
        var expected:Array = [-50, -50, -50, -1000];
        for (var i:Number = 0; i < initial.length; i++) {
            unit.麻痹值 = initial[i];
            purify(unit, 5, false, 0);
            equal(expected[i], unit.麻痹值, "P22 初值 " + initial[i]);
        }
        purify(unit, 200, false, 0);
        equal(-2000, unit.麻痹值, "P22 更强净化压低已有抗性");
        purify(unit, Infinity, true, 10);
        purify(unit, -Infinity, false, 0);
        purify(unit, NaN, false, 0);
        equal(-2000, unit.麻痹值, "P22 非有限净化不污染麻痹值");
        unit.buffManager.destroy();
    }

    // P24：真实 BuffEffect 的元信息与常规 HUD snapshot 消费路径。
    private static function testHudProjection():Void {
        var unit:Object = makeUnit(null);
        var bm:BuffManager = unit.buffManager;
        var ctx:DrugContext = context(unit, "测试药剂", null, 0);
        var domain:BuffDomainEffect = new BuffDomainEffect();
        check(domain.execute(ctx, {domain:"enhancer"}), "P24 声明真实药剂域");
        var effect:BuffEffect = new BuffEffect();
        var cases:Array = [
            ["debuff_HUD", "add_negative", -20, "harm"],
            ["正加法", "add_positive", 3, "neutral"],
            ["负加法", "add_negative", -3, "neutral"],
            ["负乘法", "multiply", 0.8, "neutral"]
        ];
        for (var i:Number = 0; i < cases.length; i++) {
            var item:Array = cases[i];
            check(effect.execute(ctx, {property:"防御力", buffId:item[0], calc:item[1],
                value:item[2], duration:300}), "P24 BuffEffect 注册 " + item[0]);
            var meta:MetaBuff = MetaBuff(bm.getBuffById(item[0]));
            var info:Object = meta.hudInfo;
            equal(item[3], info.polarity, "P24 极性 " + item[0]);
            equal(ctx.hudSource, info.source, "P24 source " + item[0]);
            equal(ctx.itemName, info.name, "P24 name " + item[0]);
            equal("药剂效果，影响属性：防御力", info.description, "P24 description " + item[0]);
            equal(0, info.stacks, "P24 stacks " + item[0]);
            equal(item[0], unit._drugBuffDomainRegistry.enhancer[i], "P24 归入真实注册域");
            equal(item[0], meta["__regId"], "P24 域 ID 对应真实实例");
        }
        equal(cases.length, unit._drugBuffDomainRegistry.enhancer.length, "P24 域登记完整");
        var timed:MetaBuff = MetaBuff(bm.getBuffById("debuff_HUD"));
        timed.hudPresentation = {groupId:"purify_fixture", primary:true, mods:true};
        var projection:PlayerHudBuffProjection = new PlayerHudBuffProjection();
        projection.setDeckDetails(true);
        projection.setDetailsEnabled(true);
        projection.initialize(bm);
        var before:Object = findHudRow(projection.snapshot(), timed.getId());
        check(before != null && before.timed === true, "P24 初次采样真实计时卡");
        equal(300, before.remaining, "P24 初次采样 300f");
        equal(300, before.total, "P24 初次采样总时长");
        checkResult(bm.purifyDebuffs(5), 0, 1, "P24 纯减时");
        var after:Object = findHudRow(projection.snapshot(), timed.getId());
        equal(250, after.remaining, "P24 下一次 snapshot 立即采到 250f");
        equal(300, before.remaining, "P24 旧快照保持 300f");
        equal(300, after.total, "P24 原总时长保留");
        equal(before.id, after.id, "P24 卡片身份保持");
        equal(ctx.hudSource, after.source, "P24 snapshot 保留来源");
        equal("1:purify_fixture", after.group.id, "P24 snapshot 分组保持");
        equal(true, after.group.primary, "P24 主分组标识保持");
        equal("harm", after.info.polarity, "P24 snapshot 保留极性");
        equal(ctx.itemName, after.info.name, "P24 snapshot 保留名称");
        equal(1, after.mods.length, "P24 snapshot 属性明细");
        equal("防御力", after.mods[0].property, "P24 snapshot 属性名");
        equal(BuffCalculationType.ADD_NEGATIVE, after.mods[0].calc, "P24 snapshot 计算类型");
        equal(-20, after.mods[0].value, "P24 snapshot 属性值");
        projection.deinitialize();
        bm.destroy();
    }

    private static function findHudRow(rows:Array, id:String):Object {
        for (var i:Number = 0; i < rows.length; i++) {
            if (rows[i].incarnation === id) return rows[i];
        }
        return null;
    }

    private static function loadDocument(index:Number):Void {
        var document = new XML();
        document.ignoreWhite = true;
        document.fixtureIndex = index;
        document.onLoad = function(ok:Boolean):Void {
            if (PurifyEffectTest.completed) return;
            var node:XMLNode = this.firstChild;
            while (node != null && node.nodeType != 1) node = node.nextSibling;
            PurifyEffectTest.receiveDocument(this.fixtureIndex, ok, node);
        };
        document.load("../data/items/" + xmlPaths[index]);
    }

    private static function receiveDocument(index:Number, ok:Boolean, rootNode:XMLNode):Void {
        try {
            var fileName:String = xmlPaths[index];
            if (!ok || rootNode == null) {
                check(false, "真实 XML 加载失败 " + fileName);
                finish();
                return;
            }
            var parsed:Object = XMLParser.parseXMLNode(rootNode);
            var items:Array = XMLParser.configureDataAsArray(parsed.item);
            check(items.length > 0, "XMLParser 解析物品 " + fileName);
            documents[index] = items;
            if (index + 1 < xmlPaths.length) {
                loadDocument(index + 1);
                return;
            }
            testXmlDrugs();
        } catch (error) {
            check(false, "异步 XML 用例异常: " + error);
        }
        finish();
    }

    private static function findItem(items:Array, name:String):Object {
        for (var i:Number = 0; i < items.length; i++) {
            if (items[i].name == name) return items[i];
        }
        return null;
    }

    private static function itemEffects(item:Object):Array {
        return XMLParser.configureDataAsArray(item.data.effects.effect);
    }

    private static function findEffect(effects:Array, type:String):Object {
        for (var i:Number = 0; i < effects.length; i++) {
            if (effects[i].type == type) return effects[i];
        }
        return null;
    }

    private static function testXmlDrugs():Void {
        var milk:Object = findItem(documents[0], "奶");
        var potion:Object = findItem(documents[2], "净化药剂");
        var kit:Object = findItem(documents[2], "战队药箱");
        check(milk != null && potion != null && kit != null, "XML 奶 / 净化药剂 / 战队药箱齐全");
        if (milk == null || potion == null || kit == null) return;
        var milkPurify:Object = findEffect(itemEffects(milk), "purify");
        var potionPurify:Object = findEffect(itemEffects(potion), "purify");
        var kitPurify:Object = findEffect(itemEffects(kit), "purify");
        var kitHeal:Object = findEffect(itemEffects(kit), "heal");
        equal(5, milkPurify.value, "P01 奶的真实净化值");
        equal(50, potionPurify.value, "P01 净化药剂的真实净化值");
        equal(undefined, potionPurify.clearDebuffs, "P17 净化药剂无 clearDebuffs");
        check(typeof potion.description == "string" && potion.description.indexOf("地形伤害") < 0,
            "P17 净化药剂描述无地形伤害");
        equal(15, kitPurify.value, "P17 药箱基础净化值");
        equal("group", kitPurify.target, "P17 药箱净化面向群体");
        equal(1500, kitHeal.hp, "P17 药箱基础治疗量");
        equal("group", kitHeal.target, "P17 药箱治疗面向群体");

        var foodCount:Number = testMealRows(documents[0], "蜜汁烤鸡", milk, potion);
        var drinkCount:Number = testMealRows(documents[1], "火星爆", milk, potion);
        equal(6, foodCount, "P01 食品负防御词条数");
        equal(25, drinkCount, "P01 酒水负防御词条数");
        equal(31, foodCount + drinkCount, "P01 合计 31 条真实负防御词条");
        testGroupKit(kit, 3);
        testGroupKit(kit, 12);
        testGroupSnapshot(kit);
        testSameFramePotions(milk, potion);
        testSinglePlayEffect();
    }

    // P01：逐条使用 XML 的 meal 域与持续词条，随后在两个代表性组合上消费真实净化词条。
    private static function testMealRows(items:Array, representative:String, milk:Object, potion:Object):Number {
        var id:String = "debuff_药剂_防御力";
        var count:Number = 0;
        var representativeCount:Number = 0;
        for (var i:Number = 0; i < items.length; i++) {
            var item:Object = items[i];
            var effects:Array = itemEffects(item);
            var persistent:Array = [];
            var defense:Object = null;
            for (var j:Number = 0; j < effects.length; j++) {
                var effect:Object = effects[j];
                if (effect.type == "buffDomain" || effect.type == "buff" || effect.type == "regen") persistent.push(effect);
                if (effect.type == "buff" && effect.buffId == id) {
                    check(defense == null, "P01 " + item.name + " 不重复声明负防御");
                    count++;
                    defense = effect;
                }
            }
            if (defense == null) continue;
            var label:String = "P01 " + item.name;
            var unit:Object = makeUnit(null);
            var bm:BuffManager = unit.buffManager;
            var ctx:DrugContext = context(unit, item.name, item, 0);
            equal("防御力", defense.property, label + " 真实负防御");
            check(defense.value < 0, label + " 负防御数值");
            equal(persistent.length, DrugEffectRegistry.executeAll(persistent, ctx), label + " 真实持续词条全部执行");
            equal("meal", ctx.activeBuffDomain, label + " meal 域");
            var meta:MetaBuff = MetaBuff(bm.getBuffById(id));
            check(meta != null, label + " 按固定外部 ID 取得 Meta");
            if (meta != null) {
                equal(id, meta["__regId"], label + " 真实外部 ID");
                equal(1800, meta.getPrimaryTimer().getTotal(), label + " 主计时总长");
                equal(1800, remaining(bm, id), label + " 主计时剩余");
                equal("harm", meta.hudInfo.polarity, label + " HUD harm");
                var ids:Array = unit._drugBuffDomainRegistry.meal;
                var registered:Number = 0;
                for (var k:Number = 0; k < ids.length; k++) {
                    if (ids[k] == id && bm.getBuffById(ids[k]) === meta) registered++;
                }
                equal(1, registered, label + " meal 域记录唯一真实注册 ID");
                equal(100 + defense.value, unit.防御力, label + " 负防御实际生效");
                if (item.name == representative) {
                    representativeCount++;
                    testMealPurification(unit, ids, id, defense.value, milk, potion, label);
                }
            }
            bm.destroy();
        }
        equal(1, representativeCount, "P01 多词条代表 " + representative);
        return count;
    }

    private static function useXmlPurify(unit:Object, item:Object):Void {
        var ctx:DrugContext = context(unit, item.name, item, 0);
        var effect:Object = findEffect(itemEffects(item), "purify");
        equal(1, DrugEffectRegistry.executeAll([effect], ctx), item.name + " 的真实净化词条执行成功");
    }

    private static function testMealPurification(unit:Object, ids:Array, debuffId:String, penalty:Number,
                                                  milk:Object, potion:Object, label:String):Void {
        var bm:BuffManager = unit.buffManager;
        var positives:Array = [];
        for (var i:Number = 0; i < ids.length; i++) {
            var id:String = ids[i];
            if (id.indexOf("debuff_") == 0) continue;
            var meta:MetaBuff = MetaBuff(bm.getBuffById(id));
            var child:PodBuff = PodBuff(meta.getChildBuff(0));
            var property:String = child.getTargetProperty();
            positives.push({id:id, meta:meta, property:property, value:unit[property], frames:remaining(bm, id)});
        }
        check(positives.length >= 2 && unit.伤害加成 > 50, label + " 有多项正向子效果且攻击已提高");
        useXmlPurify(unit, milk);
        equal(1500, remaining(bm, debuffId), label + " 奶 1800→1500");
        equal(100 + penalty, unit.防御力, label + " 仅减时仍维持防御惩罚");
        checkPositiveMeal(unit, positives, label + " 奶后");
        // 第一次强药从 1500 缩到 500，再从 500 逐次推到终止尾段。
        useXmlPurify(unit, potion);
        equal(500, remaining(bm, debuffId), label + " 净化药剂 1500→500");
        checkPositiveMeal(unit, positives, label + " 强净化减时后");
        useXmlPurify(unit, potion);
        equal(166, remaining(bm, debuffId), label + " 净化药剂 500→166");
        checkPositiveMeal(unit, positives, label + " 第二次强净化后");
        useXmlPurify(unit, potion);
        equal(null, bm.getBuffById(debuffId), label + " 净化药剂终止负防御");
        equal(100, unit.防御力, label + " 防御恢复");
        checkPositiveMeal(unit, positives, label + " 终止后");
    }

    private static function checkPositiveMeal(unit:Object, positives:Array, label:String):Void {
        var bm:BuffManager = unit.buffManager;
        for (var i:Number = 0; i < positives.length; i++) {
            var record:Object = positives[i];
            equal(record.meta, bm.getBuffById(record.id), label + " 保持 " + record.id);
            equal(record.frames, remaining(bm, record.id), label + " 时长 " + record.id);
            equal(record.value, unit[record.property], label + " 属性 " + record.property);
        }
    }

    private static function resetGroup():Void {
        TargetCacheManager.clear();
        for (var key:String in world) {
            var child = world[key];
            if (typeof child == "movieclip" && child.buffManager != null) {
                child.buffManager.destroy();
                child.removeMovieClip();
            }
        }
    }

    private static function groupUnit(name:String, x:Number, hp:Number,
                                      enemy:Boolean, callbacks:Object):MovieClip {
        var unit:MovieClip = world.createEmptyMovieClip(name + "_" + (++serial), world.getNextHighestDepth());
        initUnit(unit, hp, callbacks);
        unit._x = x;
        unit._y = 60;
        unit.是否为敌人 = enemy;
        var area:MovieClip = unit.createEmptyMovieClip("area", 1);
        area.beginFill(0);
        area.moveTo(-2, -4);
        area.lineTo(2, -4);
        area.lineTo(2, 4);
        area.lineTo(-2, 4);
        area.lineTo(-2, -4);
        area.endFill();
        unit.area = area;
        unit.aabbCollider = new AABBCollider(0, 0, 0, 0);
        TargetCacheManager.addUnit(unit);
        return unit;
    }

    private static function startGroup():Void {
        resetGroup();
        check(TargetCacheManager.initialize(), "真实目标缓存初始化");
        check(FactionManager.areAllies(FactionManager.FACTION_PLAYER, FactionManager.FACTION_PLAYER),
            "真实阵营表已初始化");
    }

    // P17/P19：完整 XML effects 调用真实群疗和净化，覆盖普通炼金与上限。
    private static function testGroupKit(kit:Object, level:Number):Void {
        startGroup();
        var label:String = "P17 炼金=" + level;
        var caster:MovieClip = groupUnit("caster", 20, 4900, false, null);
        var hurt:MovieClip = groupUnit("injured", 40, 100, false, null);
        var full:MovieClip = groupUnit("full", 60, 5000, false, null);
        var dead:MovieClip = groupUnit("dead", 80, 0, false, null);
        var enemy:MovieClip = groupUnit("enemy", 100, 100, true, null);
        _root.控制目标 = caster._name;
        var id:String = "debuff_药箱";
        defenseDebuff(caster.buffManager, id, 1000);
        defenseDebuff(hurt.buffManager, id, 80);
        defenseDebuff(full.buffManager, id, 80);
        defenseDebuff(dead.buffManager, id, 80);
        defenseDebuff(enemy.buffManager, id, 80);
        var allies:Array = TargetCacheManager.getCachedAlly(caster, 5);
        equal(3, allies.length, label + " 真实缓存仅含存活友军");
        equal(caster, allies[0], label + " 缓存自身出现一次");
        equal(hurt, allies[1], label + " 缓存受伤友军");
        equal(full, allies[2], label + " 缓存满血友军");

        var ctx:DrugContext = context(caster, kit.name, kit, level);
        equal(2, DrugEffectRegistry.executeAll(itemEffects(kit), ctx), label + " 群疗与净化均执行");
        var strength:Number = 15 + Math.min(Math.floor(5 * level), 50);
        var cut:Number = Math.max(Math.ceil(1000 * strength / (strength + 25)), Math.floor(6 * strength));
        equal(1000 - cut, remaining(caster.buffManager, id), label + " 自身 1000f 只净化一次");
        equal(-10 * strength, caster.麻痹值, label + " 自身炼金净化强度");
        equal(-10 * strength, hurt.麻痹值, label + " 受伤友军炼金净化强度");
        equal(80, caster.防御力, label + " 自身状态仍存活");
        equal(null, hurt.buffManager.getBuffById(id), label + " 受伤友军状态移除");
        equal(100, hurt.防御力, label + " 受伤友军防御恢复");
        equal(80, remaining(dead.buffManager, id), label + " 死者状态不变");
        equal(80, remaining(enemy.buffManager, id), label + " 敌军状态不变");
        equal(100, dead.麻痹值, label + " 死者麻痹不变");
        equal(100, enemy.麻痹值, label + " 敌军麻痹不变");
        equal(5000, caster.hp, label + " 自身 HP 封顶");
        equal(100 + 1500 + Math.min(Math.floor(1500 * level * 0.05), 500), hurt.hp,
            label + " 受伤友军获得真实治疗量");
        equal(0, dead.hp, label + " 死者 HP 不变");
        equal(100, enemy.hp, label + " 敌军 HP 不变");
        equal(null, full.buffManager.getBuffById(id), "P19 满血友军也净化");
        equal(100, full.防御力, "P19 满血友军防御恢复");
        equal(-10 * strength, full.麻痹值, "P19 满血友军麻痹更新");
        equal(5000, full.hp, "P19 满血友军 HP 不抬高");
        resetGroup();
    }

    // P18：在首个候选的真实 Meta 移除回调中改写世界与缓存。
    private static function groupMutationCallback(state:Object):Function {
        return function(id:String, buff:IBuff):Void {
            if (id != state.id || state.calls != 0) return;
            state.calls++;
            state.dying.hp = 0;
            state.removed._deInitialized = true;
            TargetCacheManager.removeUnit(state.removed);
            state.removed.removeMovieClip();
            state.defector.是否为敌人 = true;
            TargetCacheManager.addUnit(state.defector);
            state.joiner = PurifyEffectTest.groupUnit("joiner", 65, 5000, false, null);
            PurifyEffectTest.defenseDebuff(state.joiner.buffManager, state.id, 80);
            // 真实缓存的小数组复用同一数据缓冲，迫使施放方消费自己的快照。
            var refreshed:Array = TargetCacheManager.getCachedAlly(state.caster, 5);
            for (var i:Number = 0; i < refreshed.length; i++) {
                if (refreshed[i] === state.joiner) state.foundJoiner = true;
            }
        };
    }

    private static function testGroupSnapshot(kit:Object):Void {
        startGroup();
        var id:String = "debuff_群体快照";
        var state:Object = {id:id, calls:0, foundJoiner:false};
        var caster:MovieClip = groupUnit("snapshotCaster", 20, 5000, false,
            {onBuffRemoved:groupMutationCallback(state)});
        state.caster = caster;
        state.dying = groupUnit("dying", 40, 5000, false, null);
        state.removed = groupUnit("removed", 60, 5000, false, null);
        state.defector = groupUnit("defector", 80, 5000, false, null);
        var survivor:MovieClip = groupUnit("survivor", 100, 5000, false, null);
        var tail:MovieClip = groupUnit("tail", 120, 5000, false, null);
        _root.控制目标 = caster._name;
        defenseDebuff(caster.buffManager, id, 80);
        defenseDebuff(state.dying.buffManager, id, 80);
        var removedName:String = state.removed._name;
        var removedManager:BuffManager = state.removed.buffManager;
        var removedMeta:MetaBuff = defenseDebuff(removedManager, id, 80);
        defenseDebuff(state.defector.buffManager, id, 80);
        defenseDebuff(survivor.buffManager, id, 300);
        defenseDebuff(tail.buffManager, id, 80);
        var before:Array = TargetCacheManager.getCachedAlly(caster, 5);
        equal(6, before.length, "P18 初始快照六个合法成员");
        equal(caster, before[0], "P18 回调施法者位于第一位");
        equal(state.dying, before[1], "P18 后续候选将死亡");
        equal(state.removed, before[2], "P18 后续候选将卸载");
        equal(state.defector, before[3], "P18 后续候选将变敌");
        equal(survivor, before[4], "P18 后续合法候选");
        equal(tail, before[5], "P18 最后合法候选");

        equal(2, DrugEffectRegistry.executeAll(itemEffects(kit), context(caster, kit.name, kit, 0)),
            "P18 真实药箱词条执行");
        equal(1, state.calls, "P18 首个 Meta 的移除回调执行一次");
        check(state.foundJoiner === true, "P18 回调内真实缓存已纳入新增友军");
        equal(null, caster.buffManager.getBuffById(id), "P18 首个状态已移除");
        equal(0, state.dying.hp, "P18 候选已死亡");
        equal(80, remaining(state.dying.buffManager, id), "P18 死亡目标跳过");
        equal(100, state.dying.麻痹值, "P18 死亡目标麻痹不变");
        equal(null, world[removedName], "P18 目标剪辑已从世界移除");
        equal(removedMeta, removedManager.getBuffById(id), "P18 已卸载目标保持旧 Meta");
        equal(80, remaining(removedManager, id), "P18 已卸载目标未减时");
        check(!FactionManager.areUnitsAllies(caster, state.defector), "P18 阵营关系已变敌");
        equal(80, remaining(state.defector.buffManager, id), "P18 变敌目标跳过");
        equal(100, state.defector.麻痹值, "P18 变敌目标麻痹不变");
        equal(80, remaining(state.joiner.buffManager, id), "P18 新增友军不追溯净化");
        equal(100, state.joiner.麻痹值, "P18 新增友军麻痹值不变");
        equal(187, remaining(survivor.buffManager, id), "P18 合法友军仅净化一次 300→187");
        equal(null, tail.buffManager.getBuffById(id), "P18 最后合法友军也净化");
        equal(100, tail.防御力, "P18 最后合法友军防御恢复");
        removedManager.destroy();
        resetGroup();
    }

    private static function testSameFramePotions(milk:Object, potion:Object):Void {
        var first:Object = makeUnit(null);
        var second:Object = makeUnit(null);
        var id:String = "debuff_同帧";
        defenseDebuff(first.buffManager, id, 1800);
        defenseDebuff(second.buffManager, id, 1800);
        var frame:Number = _root.帧计时器.当前帧数;
        var previous = _root.地形伤害系数;
        var terrain:Object = {value:0.72, reads:0, writes:0};
        delete _root.地形伤害系数;
        check(_root.addProperty("地形伤害系数", function():Number {
            terrain.reads++;
            return terrain.value;
        }, function(value:Number):Void {
            terrain.writes++;
            terrain.value = value;
        }), "P21 安装地形字段访问探针");
        try {
            useXmlPurify(first, potion);
            equal(600, remaining(first.buffManager, id), "P21 同帧首次强净化");
            useXmlPurify(first, potion);
            equal(200, remaining(first.buffManager, id), "P21 同帧第二次独立强净化");
            useXmlPurify(first, milk);
            equal(166, remaining(first.buffManager, id), "P21 A 第一次");
            equal(1800, remaining(second.buffManager, id), "P21 A 不影响尚未使用的 B");
            useXmlPurify(second, potion);
            equal(600, remaining(second.buffManager, id), "P21 B 净化");
            equal(166, remaining(first.buffManager, id), "P21 B 不影响 A");
            useXmlPurify(first, milk);
            equal(136, remaining(first.buffManager, id), "P21 A/B/A 再次净化 A");
            equal(600, remaining(second.buffManager, id), "P21 A 不影响已使用的 B");
            equal(frame, _root.帧计时器.当前帧数, "P21 全部发生在同一帧");
            equal(0, terrain.reads, "P21 净化未读取地形系数");
            equal(0, terrain.writes, "P21 净化未写入地形系数");
            equal(0.72, _root.地形伤害系数, "P21 地形值原样保留");
        } finally {
            delete _root.地形伤害系数;
            if (previous !== undefined) _root.地形伤害系数 = previous;
            first.buffManager.destroy();
            second.buffManager.destroy();
        }
    }

    private static function testSinglePlayEffect():Void {
        startGroup();
        var target:MovieClip = groupUnit("visualTarget", 20, 100, false, null);
        var ally:MovieClip = groupUnit("visualAlly", 90, 100, false, null);
        equal(2, TargetCacheManager.getCachedAlly(target, 5).length, "P24 特效用例有真实友军");
        ally._y = 100;
        visuals = [];
        EffectSystem["Effect"] = function(name:String, x:Number, y:Number, scale:Number):MovieClip {
            PurifyEffectTest.visuals.push({name:name, x:x, y:y, scale:scale});
            return null;
        };
        try {
            var player:PlayEffectEffect = new PlayEffectEffect();
            var ctx:DrugContext = context(target, "特效测试", null, 0);
            check(player.execute(ctx, {name:"净化动画", target:"group", offsetX:7, offsetY:-3, scale:125}),
                "P24 旧 group 配置仍执行成功");
            equal(1, visuals.length, "P24 旧 group 配置只播放一次");
            equal("净化动画", visuals[0].name, "P24 特效名");
            equal(27, visuals[0].x, "P24 X 使用目标与偏移");
            equal(57, visuals[0].y, "P24 Y 使用目标与偏移");
            equal(125, visuals[0].scale, "P24 缩放");
            check(player.execute(ctx, {name:"净化动画", x:0, y:10, offsetX:8, offsetY:9}),
                "P24 显式坐标的单体特效执行成功");
            equal(2, visuals.length, "P24 默认单体只播放一次");
            equal(0, visuals[1].x, "P24 显式 X=0 优先");
            equal(10, visuals[1].y, "P24 显式 Y 优先");
            equal(100, visuals[1].scale, "P24 默认缩放");
        } finally {
            EffectSystem["Effect"] = saved.effect;
            resetGroup();
        }
    }

    private static function finish():Void {
        if (completed) return;
        completed = true;
        if (watchdog != null) watchdog.removeMovieClip();
        watchdog = null;
        try {
            resetGroup();
            if (world != null) world.removeMovieClip();
        } catch (error) {
            check(false, "测试世界清理异常: " + error);
        }
        _root.gameworld = saved.world;
        _root.帧计时器 = saved.clock;
        _root.控制目标 = saved.control;
        _root.物品栏 = saved.inventory;
        _root.子弹区域shoot传递 = saved.shoot;
        EffectSystem["Effect"] = saved.effect;
        world = null;
        documents = [];
        trace("PurifyEffectTest Tests Passed: " + passed);
        trace("PurifyEffectTest Tests Failed: " + failed);
        _root.purifyEffectFocusedComplete();
    }
}
