import org.flashNight.arki.hud.*;
import org.flashNight.arki.skill.SkillLoadoutService;
import org.flashNight.arki.component.Shield.AdaptiveShield;
import org.flashNight.arki.component.Shield.Shield;
import org.flashNight.arki.component.Shield.ShieldStack;
import org.flashNight.neur.Event.EventDispatcher;

/** Real AVM1 readers against a frozen prior source, including live field edits. */
class org.flashNight.arki.hud.PlayerHudSnapshotTest {
    private static var passed:Number = 0;
    private static var failed:Number = 0;
    private static var checksum:Number = 0;
    private static var api:Object;
    private static var oldApi:Object;
    private static var previous:Object;
    private static var actor:Object;
    private static var projection:Object;
    private static var legacyProjection:Object;
    private static var codec:LiteJSON;
    private static function check(value:Boolean, message:String):Void {
        if (value) passed++; else { failed++; trace("[FAIL] PlayerHudSnapshotTest: " + message); }
    }
    private static function equal(actual, expected, message:String):Void {
        check(PlayerHudService.testOnlySameProjection(actual, expected), message);
    }
    private static function flags(value:Boolean):Void {
        api.poiseDetailsEnabled = oldApi.poiseDetailsEnabled = value;
        api.shieldDetailsEnabled = oldApi.shieldDetailsEnabled = value;
        api.poiseVisualsEnabled = oldApi.poiseVisualsEnabled = value;
    }
    private static function read(kind:String, legacy:Boolean):Object {
        var value:Object;
        if (kind == "vitals") value = legacy ? oldApi.readVitals(actor) : api.readVitals(actor);
        else if (kind == "combat") value = legacy ? oldApi.readCombat(actor) : api.readCombat(actor);
        else value = legacy ? legacyProjection.snapshot() : projection.snapshot();
        var groups:Object = {};
        if (legacy) {
            if (!PlayerHudService.testOnlySameProjection(previous[kind], value)) { previous[kind] = value; groups[kind] = value; }
        } else api.addGroup(groups, kind, value, false);
        return groups;
    }
    private static function time(kind:String, legacy:Boolean, iterations:Number, changing:Boolean):Number {
        var start:Number = getTimer();
        for (var i:Number = 0; i < iterations; i++) {
            if (changing) {
                actor.hp = 50 + (i & 1);
                actor.主动战技.空手.消耗mp = i & 1;
                if (projection.rowsForTest.length > 0) projection.rowsForTest[0].timer.remaining = 100 - (i & 1);
            }
            var groups:Object = read(kind, legacy);
            if (groups[kind] != undefined) checksum++;
        }
        return getTimer() - start;
    }
    private static function bench(kind:String, label:String, changing:Boolean):Void {
        var original:Array = [], candidate:Array = [];
        time(kind, true, 10, changing); time(kind, false, 10, changing);
        for (var round:Number = 0; round < 5; round++) {
            if ((round & 1) == 0) { original.push(time(kind, true, 150, changing)); candidate.push(time(kind, false, 150, changing)); }
            else { candidate.push(time(kind, false, 150, changing)); original.push(time(kind, true, 150, changing)); }
        }
        trace("[AS2_HOTPATH_BENCH] " + kind + "_" + label + "|iterations=150|baselineMs=" + original.join(",") + "|candidateMs=" + candidate.join(","));
    }
    private static function compareVitals(label:String):Void {
        var expected:Object = oldApi.readVitals(actor);
        var actual:Object = api.readVitals(actor);
        equal(actual, expected, label);
        check(codec.stringifySafe(actual) == codec.stringifySafe(expected), label + " exact wire bytes/order");
        var before:String = codec.stringifySafe(actual);
        api.rawGroups.vitals = actual;
        actor.hp += 1;
        var next:Object = api.readVitals(actor);
        check(codec.stringifySafe(actual) == before, label + " preserves previously emitted snapshot");
        equal(next, oldApi.readVitals(actor), label + " same-frame direct edit");
        api.rawGroups.vitals = next;
    }
    private static function orderedActor():Object {
        var events:Array = [];
        var shield:Object = {capacity:100,maximum:100,events:events};
        shield.getCapacity = function():Number { this.events.push("capacity:" + this.capacity); return this.capacity; };
        shield.getMaxCapacity = function():Number { this.events.push("maximum"); return this.maximum; };
        var value:Object = {events:events,shield:shield,hp满血值:100,mp满血值:100};
        value.addProperty("hp",function():Number { this.events.push("hp"); this.shield.capacity--; return 50; },null);
        value.addProperty("mp",function():Number { this.events.push("mp"); return 70; },null);
        value.addProperty("nonlinearMappingResilience",function():Number { this.events.push("poise"); this.shield.capacity=40; return 1; },null);
        return value;
    }
    private static function testReadOrder():Void {
        flags(false);
        var actualUnit:Object = orderedActor(), expectedUnit:Object = orderedActor();
        var expected:Object = oldApi.readVitals(expectedUnit), actual:Object = api.readVitals(actualUnit);
        trace("[HUD_READ_ORDER] baseline=" + expectedUnit.events.join(",") + "|candidate=" + actualUnit.events.join(","));
        equal(actual,expected,"accessor side effects preserve the original live-value sampling order");
        check(actualUnit.events.join(",") == expectedUnit.events.join(","), "getter call order remains exact");
    }
    private static function testVitals():Void {
        flags(false); actor.shield = null;
        compareVitals("legacy capabilities/missing shield");
        flags(true);
        var shield:AdaptiveShield = new AdaptiveShield(100, 40, 2, 60, "sampling", "rechargeable");
        actor.shield = shield; shield.consumeCapacity(25);
        compareVitals("flat waiting shield");
        shield.update(15); compareVitals("delay advance");
        shield.update(45); compareVitals("charging");
        shield.update(100); compareVitals("full");
        var values:Array = [Number.NaN, Number.POSITIVE_INFINITY, Number.NEGATIVE_INFINITY, null, undefined, -5, "17", ""];
        for (var i:Number = 0; i < values.length; i++) {
            actor.hp = values[i]; actor.mp = values[i]; actor.nonlinearMappingResilience = values[i];
            _root.等级 = values[i]; _root.技能点数 = values[i];
            compareVitals("scalar normalization " + i);
        }
        actor.hp = 50; actor.mp = 70; _root.等级 = 12; _root.技能点数 = 3;
        var force:Array = [0, 25, 25.001, 100, 100.001];
        for (i = 0; i < force.length; i++) { actor.remainingImpactForce = force[i]; compareVitals("poise boundary " + i); }
        actor.浮空 = true; actor.刚体 = true; actor.倒地 = true; compareVitals("simultaneous posture");
        actor.浮空 = false; actor.刚体 = false; actor.倒地 = false;
        var first:Shield = Shield.createRechargeable(100, 40, 1, 30, "first");
        var second:Shield = Shield.createRechargeable(100, 80, 1, 120, "second");
        var stack:ShieldStack = new ShieldStack();
        first.consumeCapacity(20); second.consumeCapacity(20); stack.addShield(first); stack.addShield(second);
        actor.shield = stack; compareVitals("aggregate next wait");
        var external:Object = {owned:second, value:"health"};
        external.ownsHudShield = function(value:Object):Boolean { return value === this.owned; };
        external.getHudRecoveryState = function():Object { return {state:this.value, progress:0, remainingMs:0, totalMs:0}; };
        actor.__titaniumType61 = external; compareVitals("external equipment recovery");
        external.value = "unavailable"; compareVitals("unknown aggregate");
        delete actor.__titaniumType61;
        first.update(30); compareVitals("charging aggregate precedence");
        var beforeCapacity:Number = stack.getCapacity();
        var beforeDelay:Number = second.getDelayTimer();
        for (i = 0; i < 20; i++) api.readVitals(actor);
        check(stack.getCapacity() == beforeCapacity && second.getDelayTimer() == beforeDelay, "projection never advances authoritative recovery");
        flags(false); compareVitals("capabilities removed after prior rich snapshot");
        flags(true); _root.暂停 = true; _root.__nativeHudDecorations = false; compareVitals("paused and decorations");
        _root.暂停 = false; _root.__nativeHudDecorations = true;
        actor.shield = shield;
        flags(false); bench("vitals", "base_unchanged", false);
        flags(true); bench("vitals", "rich_unchanged", false); bench("vitals", "rich_changing", true);
        var full:Object = {}, snapshot:Object = api.readVitals(actor);
        api.rawGroups.vitals = snapshot;
        check(api.addGroup(full, "vitals", api.readVitals(actor), true) && full.vitals != null, "force-full sends unchanged vitals");
        api.rawGroups = {};
        var reset:Object = {};
        check(api.addGroup(reset, "vitals", api.readVitals(actor), false), "cleared context republishes all vitals");
    }
    private static function testCombat():Void {
        var attackModes:Array = ["空手", "手枪", "双枪", "长枪", "兵器", "手雷", "unknown"];
        for (var i:Number = 0; i < attackModes.length; i++) {
            actor.攻击模式 = attackModes[i];
            var actual:Object = api.readCombat(actor), expected:Object = oldApi.readCombat(actor);
            equal(actual, expected, "combat mode " + attackModes[i]);
            var before:String = codec.stringifySafe(actual);
            api.ammo[0] = oldApi.ammo[0] = "10/30";
            var next:Object = api.readCombat(actor);
            equal(next, oldApi.readCombat(actor), "ammo direct edit " + i);
            check(codec.stringifySafe(actual) == before, "combat prior snapshot unchanged " + i);
        }
        actor.攻击模式 = "空手";
        var skill:Object = actor.主动战技.空手;
        skill.名字 = "重拳\"\n中文"; skill.消耗mp = 10; skill.冷却时间 = 2000;
        equal(api.readCombat(actor), oldApi.readCombat(actor), "weapon live edit");
        _root.武器技能键 = 70; equal(api.readCombat(actor), oldApi.readCombat(actor), "weapon key rebinding");
        bench("combat", "unchanged", false); bench("combat", "changing", true);
    }
    private static function timerBuff(id:String, total:Number, remain:Number):Object {
        var timer:Object = {total:total, remaining:remain};
        timer.getTotal = function():Number { return this.total; };
        timer.getRemaining = function():Number { return this.remaining; };
        var buff:Object = {__regId:id, timer:timer};
        buff.getPrimaryTimer = function():Object { return this.timer; };
        return buff;
    }
    private static function makeManager(rows:Array):Object {
        var manager:Object = {rows:rows, eventDispatcher:new EventDispatcher()};
        manager.getAllMetaBuffs = function():Array { return this.rows; };
        return manager;
    }
    private static function compareBuffs(label:String):Void {
        var actual:Array = projection.snapshot(), expected:Array = legacyProjection.snapshot();
        equal(actual, expected, label);
        check(codec.stringifySafe(actual) == codec.stringifySafe(expected), label + " exact wire bytes/order");
    }
    private static function testBuffs():Void {
        projection = new PlayerHudBuffProjection(); legacyProjection = new PlayerHudBuffProjectionLegacyFixture();
        projection.rowsForTest = [];
        compareBuffs("cold empty"); bench("buffs", "empty", false);
        var rows:Array = [], i:Number;
        for (i = 0; i < 12; i++) rows.push(timerBuff("b" + i, 100, 70));
        var manager:Object = makeManager(rows);
        projection.initialize(manager); legacyProjection.initialize(manager); projection.rowsForTest = rows;
        compareBuffs("initial real dispatcher");
        var original:Array = projection.snapshot(); var before:String = codec.stringifySafe(original);
        rows[2].timer.remaining = 69; compareBuffs("live timer tick");
        check(codec.stringifySafe(original) == before, "timer update cannot mutate an earlier row or array");
        rows[2].timer = null; compareBuffs("timer removed");
        rows[2].timer = rows[3].timer; compareBuffs("timer replacement");
        rows[3].timer.remaining = -1; rows[3].timer.total = Number.NaN; compareBuffs("invalid timer normalization");
        rows[3].timer.remaining = Number.POSITIVE_INFINITY; compareBuffs("infinite timer normalization");
        manager.eventDispatcher.publish("remove", "b0"); compareBuffs("middle ownership list removal");
        var extra:Object = timerBuff("new", 20, 10);
        manager.eventDispatcher.publish("add", "new", extra); compareBuffs("callback append");
        manager.eventDispatcher.publish("add", "new", extra); compareBuffs("duplicate callback");
        projection.rowsForTest = [rows[1]];
        bench("buffs", "12_unchanged", false); bench("buffs", "12_changing", true);
        var replacement:Object = makeManager([rows[0]]);
        projection.initialize(replacement); legacyProjection.initialize(replacement); compareBuffs("replaced manager generation");
        manager.eventDispatcher.publish("add", "stale", extra); compareBuffs("old dispatcher detached");
        projection.deinitialize(); legacyProjection.deinitialize(); compareBuffs("teardown");
        manager.eventDispatcher.destroy(); replacement.eventDispatcher.destroy();
    }
    private static function timeBuffCadence(legacy:Boolean,period:Number):Number {
        var start:Number=getTimer();
        for(var frame:Number=0;frame<160;frame++) {
            if(frame%period==0) for(var i:Number=0;i<projection.rowsForTest.length;i++) projection.rowsForTest[i].timer.remaining=80-(Math.floor(frame/period)&1);
            read("buffs",legacy);
        }
        return getTimer()-start;
    }
    private static function benchBuffCadence(period:Number):Void {
        var rows:Array=[];
        for(var i:Number=0;i<12;i++) rows.push(timerBuff("cadence"+i,100,80));
        var manager:Object=makeManager(rows);
        projection.initialize(manager);legacyProjection.initialize(manager);projection.rowsForTest=rows;
        compareBuffs("cadence fixture " + period);
        var initial:Array=projection.snapshot();
        check(projection.snapshot()===initial,"unchanged Buff snapshot reuses its detached array");
        var before:String=codec.stringifySafe(initial);
        timeBuffCadence(true,period);timeBuffCadence(false,period);
        check(codec.stringifySafe(initial)==before,"cadence never overwrites an earlier full snapshot");
        var oldTimes:Array=[],newTimes:Array=[];
        for(var round:Number=0;round<5;round++) {
            if((round&1)==0){oldTimes.push(timeBuffCadence(true,period));newTimes.push(timeBuffCadence(false,period));}
            else{newTimes.push(timeBuffCadence(false,period));oldTimes.push(timeBuffCadence(true,period));}
        }
        compareBuffs("cadence final values " + period);
        trace("[AS2_HOTPATH_BENCH] buffs12_change_every_"+period+"|iterations=160|baselineMs="+oldTimes.join(",")+"|candidateMs="+newTimes.join(","));
        projection.deinitialize();legacyProjection.deinitialize();manager.eventDispatcher.destroy();
    }
    public static function runAllTests():Void {
        passed = failed = checksum = 0; codec = new LiteJSON(); previous = {}; api = org.flashNight.arki.hud.PlayerHudService; oldApi = org.flashNight.arki.hud.PlayerHudSnapshotLegacyFixture;
        var rootKeys:Array = ["经验值", "上次升级需要经验值", "升级需要经验值", "等级", "角色名", "技能点数", "暂停", "__nativeHudDecorations", "帧计时器", "武器技能键", "keyshow"];
        var fields:Array = ["rawGroups", "poiseDetailsEnabled", "shieldDetailsEnabled", "poiseVisualsEnabled", "ammo", "ammoMode", "primaryOwner", "secondaryOwner", "lastCombat", "compat"];
        var savedRoot:Object = {}, savedApi:Object = {}, i:Number;
        for (i = 0; i < rootKeys.length; i++) savedRoot[rootKeys[i]] = _root[rootKeys[i]];
        for (i = 0; i < fields.length; i++) savedApi[fields[i]] = api[fields[i]];
        try {
            _root.经验值 = 10; _root.上次升级需要经验值 = 0; _root.升级需要经验值 = 100;
            _root.等级 = 12; _root.角色名 = "中文\"\n测量"; _root.技能点数 = 3;
            _root.暂停 = false; _root.__nativeHudDecorations = true; _root.帧计时器 = {帧率:30};
            _root.武器技能键 = 65; _root.keyshow = function(code:Number):String { return "K" + code; };
            api.rawGroups = {}; api.ammo = ["", "", "", ""]; api.ammoMode = "";
            api.primaryOwner = api.secondaryOwner = api.lastCombat = null; api.compat = {玩家必要信息界面:{}};
            actor = {hp:50, hp满血值:100, mp:70, mp满血值:100, nonlinearMappingResilience:0.9,
                韧性上限:100, impactStaggerBoundary:25, remainingImpactForce:0, man:{}, 攻击模式:"空手", 主动战技:{}, 手枪:{}, 手枪2:{}, 长枪:{}};
            actor.主动战技.空手 = {名字:"重拳", 消耗mp:2, 冷却时间:500};
            testReadOrder(); testVitals(); testCombat(); testBuffs(); benchBuffCadence(1); benchBuffCadence(4);
        } finally {
            for (i = 0; i < rootKeys.length; i++) _root[rootKeys[i]] = savedRoot[rootKeys[i]];
            for (i = 0; i < fields.length; i++) api[fields[i]] = savedApi[fields[i]];
        }
        trace("PlayerHudSnapshotTest Tests Passed: " + passed);
        trace("PlayerHudSnapshotTest Tests Failed: " + failed);
    }
}
