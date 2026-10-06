import org.flashNight.neur.Event.EventDispatcher;
import org.flashNight.neur.ScheduleTimer.EnhancedCooldownWheel;
import org.flashNight.naki.RandomNumberEngine.LinearCongruentialEngine;
import org.flashNight.arki.unit.UnitComponent.Initializer.EventComponent.FireEventComponent;
import org.flashNight.arki.bullet.Factory.BulletFactory;
import org.flashNight.arki.bullet.BulletComponent.Chain.ChainGroup;
import org.flashNight.arki.bullet.BulletComponent.Chain.ChainUnitData;
import org.flashNight.arki.unit.Action.Shoot.WeaponFireCore;

/** 真实提交事件、游戏帧时钟、原 RNG 与生产纵向组装/补弹的定向回归。 */
class org.flashNight.arki.unit.Action.Shoot.WeaponSpreadRuntimeTest {
    private static var passed:Number;
    private static var failed:Number;
    private static var clock:Number;
    private static var actorId:Number;
    private static var bus:EventDispatcher;
    private static var actors:Array;
    private static var submitted:Array;
    private static var spans:Array;

    private static function check(ok:Boolean, label:String):Void {
        if (ok) passed++;
        else { failed++; trace("[TEST_FAIL] WeaponSpreadRuntimeTest: " + label); }
    }
    private static function close(actual:Number, expected:Number, label:String):Void {
        check(Math.abs(actual - expected) < 0.000001, label);
    }
    private static function copy(source:Object):Object {
        var target:Object = {};
        for (var key:String in source) target[key] = source[key];
        return target;
    }
    private static function actor():MovieClip {
        var unit:MovieClip = _root.gameworld.createEmptyMovieClip("spreadActor" + (++actorId), _root.gameworld.getNextHighestDepth());
        unit.状态 = "站立";
        unit.Z轴坐标 = 0;
        unit.长枪 = {name:"测试枪", value:{shot:0}};
        unit.手枪 = {name:"同型号手枪", value:{shot:0}};
        unit.手枪2 = {name:"同型号手枪", value:{shot:0}};
        unit.长枪弹匣容量 = unit.手枪弹匣容量 = unit.手枪2弹匣容量 = 200;
        unit.长枪属性 = unit.手枪属性 = unit.手枪2属性 = {interval:100};
        unit.长枪数据 = unit.手枪数据 = unit.手枪2数据 = {weapontype:"突击步枪"};
        unit.dispatcher = new EventDispatcher();
        unit.enableShoot = true;
        FireEventComponent.initialize(unit);
        unit.man = unit.createEmptyMovieClip("man", unit.getNextHighestDepth());
        _root.控制目标 = unit._name;
        actors[actors.length] = unit;
        return unit;
    }
    private static function props(base:Number, moving:Number, type:String):Object {
        return {站立子弹散射度:base, 移动子弹散射度:moving, 子弹散射度:base,
            子弹种类:type, 子弹威力:1, 子弹速度:20, 霰弹值:1, 角度偏移:0};
    }
    private static function tick(count:Number):Void {
        for (var i:Number = 0; i < count; i++) {
            _root.帧计时器.当前帧数 = ++clock;
            bus.publish("frameUpdate", clock);
        }
    }
    private static function fire(unit:MovieClip, slot:String, p:Object, interval:Number):Boolean {
        unit.__pendingFireInterval = interval;
        return WeaponFireCore.executeShot(unit, slot, unit.man, p);
    }
    private static function density():Void {
        var unit:MovieClip = actor();
        var p:Object = props(10, 20, "普通子弹");
        for (var i:Number = 0; i < 5; i++) {
            if (i > 0) tick(3);
            check(fire(unit, "长枪", p, 100), "连续开火成功 " + i);
            close(p.武器扩散倍率, 0.6 + i * 0.1, "包含本次的密度 " + i);
            close(p.子弹散射度, 10, "原散射字段不连乘 " + i);
        }
        tick(3);
        fire(unit, "长枪", p, 100);
        close(p.武器扩散倍率, 1, "窗口左边界排除恰好15帧前的事件");
        check(unit.__weaponSpreadStates[0].total == 5, "满速稳态始终五次");
        tick(15);
        fire(unit, "长枪", p, 100);
        close(p.武器扩散倍率, 0.6, "停火500ms恢复首发");
        var first:Object = submitted[submitted.length - 1];
        tick(3);
        unit.man = unit.createEmptyMovieClip("man", unit.getNextHighestDepth());
        fire(unit, "长枪", props(10, 20, "普通子弹"), 100);
        close(submitted[submitted.length - 1].武器扩散倍率, 0.7, "动画重建保留历史");
        close(first.武器扩散倍率, 0.6, "已发子弹快照不追读下一发倍率");

        unit = actor(); p = props(10, 20, "普通子弹");
        fire(unit, "长枪", p, 100); tick(3); fire(unit, "长枪", p, 100); tick(3); fire(unit, "长枪", p, 100);
        tick(9); fire(unit, "长枪", p, 100);
        close(p.武器扩散倍率, 0.8, "三发后停300ms部分恢复");
        check(unit.__weaponSpreadStates[0].total == 3, "三发点射窗口计数");

        var intervals:Array = [466, 470, 499, 500, 501, 800];
        var expected:Array = [29/30, 1, 1, 1, 1, 1];
        for (i = 0; i < intervals.length; i++) {
            unit = actor(); p = props(10, 20, "普通子弹");
            fire(unit, "长枪", p, intervals[i]);
            close(p.武器扩散倍率, expected[i], "向上取整及500ms边界 " + intervals[i]);
        }
        unit = actor(); p = props(10, 20, "普通子弹");
        unit.长枪属性 = {interval:800};
        fire(unit, "长枪", p, 120);
        close(p.武器扩散倍率, 19/30, "本次配件/技能间隔戳优先于静态射速");
        close(p.发射间隔毫秒, 120, "事件消费前盖本次间隔戳");
        check(unit.__pendingFireInterval == 0, "间隔预置只消费一次");
    }
    private static function identityAndPause():Void {
        var unit:MovieClip = actor(); var p:Object = props(10, 20, "普通子弹");
        var a:Object = unit.长枪; var b:Object = {name:a.name, value:{shot:0}};
        fire(unit, "长枪", p, 100); tick(1);
        unit.长枪 = b; fire(unit, "长枪", p, 100);
        close(p.武器扩散倍率, 0.6, "同型号不同实际武器独立");
        unit.长枪 = a; fire(unit, "长枪", p, 100);
        close(p.武器扩散倍率, 0.7, "切回旧武器不刷新精度");
        unit.长枪 = {name:a.name, value:a.value}; fire(unit, "长枪", p, 100);
        close(p.武器扩散倍率, 0.8, "同value的包装重建保留身份");
        unit.手枪 = unit.长枪; fire(unit, "手枪", p, 100);
        close(p.武器扩散倍率, 0.9, "同实际武器换手仍保留历史");
        check(a.value.__weaponSpreadStates == undefined && a.__weaponSpreadStates == undefined,
            "物品和value不承接运行态记录");

        unit = actor(); p = props(10, 20, "普通子弹");
        fire(unit, "手枪", p, 100); fire(unit, "手枪", p, 100);
        close(p.武器扩散倍率, 0.7, "主手第二发");
        fire(unit, "手枪2", p, 100); close(p.武器扩散倍率, 0.6, "副手首发独立");
        fire(unit, "手枪2", p, 100); close(p.武器扩散倍率, 0.7, "副手第二发独立");
        _root.暂停 = true;
        var count:Number = unit.手枪.value.shot;
        check(!fire(unit, "手枪", p, 100), "暂停拒绝开火");
        check(unit.手枪.value.shot == count, "暂停不扣弹");
        tick(60); _root.暂停 = false;
        fire(unit, "手枪", p, 100); close(p.武器扩散倍率, 0.8, "暂停不恢复窗口");
        tick(15); fire(unit, "手枪", p, 100); close(p.武器扩散倍率, 0.6, "恢复后按活动游戏帧恢复");
        for (var i:Number = 0; i < 100; i++) fire(unit, "手枪2", p, 100);
        var states:Array = unit.__weaponSpreadStates;
        check(states[states.length - 1].buckets == 1 && states[states.length - 1].ticks.length == 15,
            "同帧大量提交合桶且存储有界");
        close(p.武器扩散倍率, 1, "同帧大量提交最多满扩散");
    }
    private static function failuresAndScope():Void {
        var unit:MovieClip = actor(); var p:Object = props(10, 20, "普通子弹");
        fire(unit, "长枪", p, 100);
        var shot:Number = unit.长枪.value.shot;
        unit.长枪弹匣容量 = shot;
        check(!fire(unit, "长枪", p, 100), "空仓拒绝");
        unit.长枪弹匣容量 = 200;
        unit.__pendingFireInterval = 100;
        check(!WeaponFireCore.executeShot(unit, "长枪", unit.man, p, function():Boolean { return false; }), "提交守卫拒绝");
        check(unit.长枪.value.shot == shot, "拒绝不扣弹");
        fire(unit, "长枪", p, 100); close(p.武器扩散倍率, 0.7, "失败不增加密度");
        p.子弹威力 = NaN; fire(unit, "长枪", p, 100);
        p.子弹威力 = 1; fire(unit, "长枪", p, 100); close(p.武器扩散倍率, 0.8, "无效弹道不增加密度");

        unit = actor(); p = props(10, 20, "普通子弹"); unit.状态 = "行走";
        fire(unit, "长枪", p, 100); close(p.子弹散射度, 20, "原移动散射字段不变");
        close(p.武器扩散倍率 * p.子弹散射度, 16, "基础10乘0.6，移动惩罚10保留");
        unit = actor(); p = props(10, 12, "普通子弹"); unit.状态 = "行走";
        fire(unit, "长枪", p, 100); close(p.武器扩散倍率 * p.子弹散射度, 8, "移动射击技能减少后的惩罚保留");
        unit = actor(); p = props(0, 10, "普通子弹"); unit.状态 = "行走";
        fire(unit, "长枪", p, 100); close(p.武器扩散倍率, 1, "零基础散布不削减移动惩罚");

        var excluded:Array = ["横向联弹-普通子弹", "横向拖尾联弹-小型导弹", "近战联弹", "喷火束", "普通弩箭", "小型导弹", "火焰集束爆炸"];
        for (var i:Number = 0; i < excluded.length; i++) {
            unit = actor(); p = props(10, 20, excluded[i]);
            fire(unit, "长枪", p, 100); close(p.武器扩散倍率, 1, "特殊弹种保持原行为 " + excluded[i]);
            check(unit.__weaponSpreadStates == undefined, "特殊弹种不记窗口 " + excluded[i]);
        }
        unit = actor(); p = props(10, 20, "普通子弹"); _root.控制目标 = "其他角色";
        fire(unit, "长枪", p, 100); close(p.武器扩散倍率, 1, "NPC保持原散布");
        check(unit.__weaponSpreadStates == undefined, "NPC不维护窗口");
    }
    private static function sampling():Void {
        var rng:LinearCongruentialEngine = LinearCongruentialEngine.getInstance();
        var originalSeed:Number = rng.captureState();
        var p:Object = {子弹散射度:1, 武器扩散倍率:0.6};
        var maximum:Number = 0;
        for (var i:Number = 0; i < 30; i++) {
            var seed:Number = rng.captureState();
            var original:Number = rng.randomOffset(1); var next:Number = rng.captureState();
            rng.restoreState(seed); var sampled:Number = BulletFactory.sampleScatterOffset(p);
            close(sampled, original * 0.6, "原整数抽样后缩放 " + i);
            check(rng.captureState() == next, "RNG消耗不增加 " + i);
            if (Math.abs(sampled) > maximum) maximum = Math.abs(sampled);
        }
        check(maximum <= 0.6, "1度基础的0.6倍率不会抽出1.4度");
        p = {子弹散射度:7}; seed = rng.captureState(); original = rng.randomOffset(7);
        rng.restoreState(seed); close(BulletFactory.sampleScatterOffset(p), original, "技能/非枪械未盖戳旁路保持原抽样");
        rng.restoreState(originalSeed);
    }
    private static function createUnit(group:ChainGroup, rotation:Number):ChainUnitData {
        var u:ChainUnitData = new ChainUnitData();
        u.x = u.y = 0; u.rot = rotation;
        u.sin = Math.sin(rotation * Math.PI / 180); u.cos = Math.cos(rotation * Math.PI / 180);
        group.单元体列表[group.单元体列表.length] = u;
        return u;
    }
    private static function vertical():Void {
        var unit:MovieClip = actor(); var p:Object = props(7, 17, "纵向机枪联弹-加强普通子弹");
        p.霰弹值 = 5; fire(unit, "长枪", p, 150);
        close(p.武器扩散倍率, 2/3, "五颗纵向联弹按一组计数");
        check(unit.__weaponSpreadStates[0].total == 1, "split不重复增加次数");
        var b:Object = copy(submitted[submitted.length - 1]);
        b._x = b._y = b._rotation = 0; b.xmov = 10;
        var group:ChainGroup = new ChainGroup(null, b, null, null);
        group.盒x = 7; group.盒y = -5; group.盒宽 = group.盒高 = 10;
        spans = [];
        var oldRandom:Function = _root.随机偏移;
        var oldCreate:Function = _root.联弹系统.生成单元体;
        var oldRender:Function = _root.联弹系统.渲染组;
        try {
            _root.随机偏移 = function(span:Number):Number { WeaponSpreadRuntimeTest.spans.push(span); return span; };
            _root.联弹系统.生成单元体 = createUnit;
            _root.联弹系统.渲染组 = function():Void {};
            group.render = _root.联弹系统.渲染组;
            _root.联弹系统.纵向联弹组装(group);
            close(group.武器扩散倍率, 2/3, "组装冻结倍率");
            b.武器扩散倍率 = 1;
            for (var i:Number = 0; i < 5; i++) {
                b._x += b.xmov;
                _root.联弹系统.纵向联弹更新(group);
            }
            check(group.count == 5 && group.补弹分子 == 4 && group.补弹分母 == 5, "补弹计数及节奏不变");
            close(b.子弹散射度, 7, "原散射字段保留");
            for (i = 0; i < group.单元体列表.length; i++) close(group.单元体列表[i].rot, 14/3, "首颗与补弹倍率一致 " + i);
            check(spans.length == 9, "首颗一次、补弹角度和间距各一次抽样");
            for (i = 1; i < spans.length; i += 2) {
                close(spans[i], 7, "角度仍按原整数半径抽样 " + i);
                close(spans[i + 1], 13 + (i - 1) / 2, "纵向间距随机半径保留 " + i);
            }
        } finally {
            _root.随机偏移 = oldRandom;
            _root.联弹系统.生成单元体 = oldCreate;
            _root.联弹系统.渲染组 = oldRender;
        }
    }
    public static function runAllTests():Void {
        passed = failed = clock = actorId = 0; actors = []; submitted = [];
        var oldWorld:MovieClip = _root.gameworld; var oldClock:Object = _root.帧计时器;
        var oldTarget:String = _root.控制目标; var oldPaused = _root.暂停;
        var oldShoot:Function = _root.子弹区域shoot传递;
        var wheel:EnhancedCooldownWheel = EnhancedCooldownWheel.I(); var oldFrameMs:Number = wheel.每帧毫秒;
        var world:MovieClip = _root.createEmptyMovieClip("spreadTestWorld", _root.getNextHighestDepth());
        bus = new EventDispatcher();
        try {
            _root.gameworld = world; _root.帧计时器 = {eventBus:bus, 当前帧数:0};
            _root.暂停 = false; wheel.每帧毫秒 = 1000 / 30;
            _root.子弹区域shoot传递 = function(p:Object):Void { WeaponSpreadRuntimeTest.submitted.push(WeaponSpreadRuntimeTest.copy(p)); };
            density(); identityAndPause(); failuresAndScope(); sampling(); vertical();
        } catch (error:Error) {
            failed++; trace("[TEST_FAIL] WeaponSpreadRuntimeTest exception: " + error);
        } finally {
            for (var i:Number = 0; i < actors.length; i++) actors[i].dispatcher.destroy();
            bus.destroy(); world.removeMovieClip();
            _root.gameworld = oldWorld; _root.帧计时器 = oldClock; _root.控制目标 = oldTarget;
            _root.暂停 = oldPaused; _root.子弹区域shoot传递 = oldShoot; wheel.每帧毫秒 = oldFrameMs;
        }
        trace("WeaponSpreadRuntimeTest Tests Passed: " + passed);
        trace("WeaponSpreadRuntimeTest Tests Failed: " + failed);
    }
}
