import org.flashNight.arki.unit.UnitAI.combat.UtilityEvaluator;
import org.flashNight.arki.unit.UnitAI.combat.WeaponEvaluator;
import org.flashNight.arki.unit.UnitAI.combat.WeaponDpsEstimator;
import org.flashNight.arki.unit.UnitAI.combat.StanceManager;
import org.flashNight.arki.unit.UnitAI.combat.DecisionTrace;
import org.flashNight.arki.unit.UnitAI.combat.scoring.ScoringPipeline;
import org.flashNight.arki.unit.PlayerInfoProvider;

/** Actual AVM1 scoring/selection/cache contracts; no real game or inventory writes. */
class org.flashNight.arki.unit.UnitAI.combat.AIDiagnosticsTest {
    private static var passed:Number = 0;
    private static var failed:Number = 0;
    private static var estimatorCalls:Number = 0;
    private static var logCalls:Number = 0;
    private static var logChars:Number = 0;
    private static var sink:Number = 0;

    private static function check(ok:Boolean, label:String):Void {
        if (ok) passed++; else { failed++; trace("[FAIL] AIDiagnosticsTest: " + label); }
    }
    public static function runAllTests():Void {
        passed = failed = sink = 0;
        var oldDebug = _root.AI调试模式;
        var oldLevel = _root.AI日志级别;
        var oldClock = _root.帧计时器;
        var oldServer = _root.服务器;
        _root.帧计时器 = {当前帧数:0};
        _root.服务器 = {发布服务器消息:function(msg:String):Void {
            AIDiagnosticsTest.logCalls++;
            AIDiagnosticsTest.logChars += msg.length;
        }};
        testScoringFlags();
        testWeaponFlags();
        benchmarkTrace();
        _root.AI调试模式 = oldDebug;
        _root.AI日志级别 = oldLevel;
        _root.帧计时器 = oldClock;
        _root.服务器 = oldServer;
        trace("AIDiagnosticsTest Tests Passed: " + passed);
        trace("AIDiagnosticsTest Tests Failed: " + failed);
    }
    private static function personality():Object {
        return {勇气:0, 智力:1, stanceMastery:0, stabilityFactor:1,
            weaponSwitchCost:0.2, weaponHysteresis:0.1, evalDepth:5,
            skillBaseBonus:0.15, comboPreference:0.4,
            w_damage:0.7, w_safety:0.3, w_resource:0.2, w_positioning:0.4, w_combo:0.25};
    }
    private static function candidates():Array {
        return [{name:"Attack",type:"attack"},
            {name:"Ranged",type:"skill",skill:{技能等级:7,类型:"火器",功能:"远程输出"}},
            {name:"Dodge",type:"skill",skill:{技能等级:2,类型:"格斗",功能:"躲避"}},
            {name:"Reload",type:"reload",score:0.7},
            {name:"PreBuff",type:"preBuff",score:0.4},
            {name:"Continue",type:"continue",score:0.3}];
    }
    private static function runScoring(debug:Boolean, level:Number, count:Number, record:Boolean):Object {
        _root.AI调试模式 = debug;
        _root.AI日志级别 = level;
        logCalls = logChars = 0;
        var actor:MovieClip = _root.createEmptyMovieClip("__aiScoreFixture", _root.getNextHighestDepth());
        actor.hp = 60; actor.hp满血值 = 100;
        var p:Object = personality();
        var stats:Object = {draws:0,beginCalls:0,modifyCalls:0,endCalls:0,scoredCalls:0};
        var scorer:UtilityEvaluator = new UtilityEvaluator(p);
        var scorerObject:Object = scorer;
        scorerObject._rng = {nextFloat:function():Number {
            var value:Number = ((stats.draws * 37 + 11) % 101) / 101;
            stats.draws++;
            return value;
        }};
        var mod:Object = {
            begin:function(ctx, data, scratch):Void {stats.beginCalls++; scratch.bias = ctx.frame % 3 * 0.01;},
            modify:function(c, ctx, traits, scratch):Number {stats.modifyCalls++; return scratch.bias + c.name.length * 0.001;},
            getName:function():String {return "FixtureMod";}
        };
        var post:Object = {
            begin:function(ctx, data, scratch):Void {stats.beginCalls++;},
            end:function(list, ctx, traits, scratch):Void {
                stats.endCalls++;
                for (var k:Number = 0; k < list.length; k++) {
                    if (list[k].type != "continue") list[k].score -= k * 0.013;
                }
            },
            getName:function():String {return "FixturePost";}
        };
        var pipeline:ScoringPipeline = new ScoringPipeline(scorer,[mod],[post]);
        var decisionTrace:DecisionTrace = new DecisionTrace();
        var traceObject:Object = decisionTrace;
        var originalScored:Function = traceObject.scored;
        traceObject.scored = function(c, dims, mods, posts):Void {
            stats.scoredCalls++;
            originalScored.call(this,c,dims,mods,posts);
        };
        var data = {self:actor,absdiff_x:240,xrange:300};
        var ctx = {frame:0,context:"Fixture",stance:{dimMod:[0.1,-0.1,0.05,0,0.2]},hpRatio:0.6};
        var signature:String = "";
        for (var i:Number = 0; i < count; i++) {
            ctx.frame = i;
            var list:Array = candidates();
            decisionTrace.begin("fixture",ctx,p);
            decisionTrace.setCandidateCounts(list.length,list.length);
            decisionTrace.setSourceSummary("Fixture");
            pipeline.scoreAll(list,ctx,data,actor,p,0.7,decisionTrace);
            var selected:Object = scorer.boltzmannSelect(list,0.7);
            decisionTrace.selected(selected,0.5,0.7);
            decisionTrace.flush();
            sink += selected.score;
            if (record) {
                signature += selected.name + ":";
                for (var j:Number = 0; j < list.length; j++) {
                    signature += list[j].name + "=" + list[j].score + "/" + list[j]._ew + ",";
                }
            }
        }
        var beforeEmpty:Number = stats.draws;
        check(scorer.boltzmannSelect([],0.7) == null, "empty selection " + debug + "/" + level);
        var one:Object = {name:"only",score:1};
        check(scorer.boltzmannSelect([one],0.7) === one && stats.draws == beforeEmpty,
            "empty/single selection consumes no RNG " + debug + "/" + level);
        actor.removeMovieClip();
        return {signature:signature,stats:stats,logs:logCalls,chars:logChars};
    }
    private static function testScoringFlags():Void {
        var full:Object = runScoring(true,3,24,true);
        check(full.logs == 24 && full.chars > 0, "FULL fixture exercised real formatting and log producer");
        var flags:Array = [[false,3],[true,0],[false,0],[false,1],[false,2]];
        for (var i:Number = 0; i < flags.length; i++) {
            var result:Object = runScoring(flags[i][0],flags[i][1],24,true);
            var name:String = flags[i].join("/");
            check(result.signature == full.signature, "scores/order/weights/selected action parity " + name);
            check(result.stats.draws == 24, "exact RNG count " + name);
            check(result.stats.beginCalls == 48 && result.stats.modifyCalls == 120 && result.stats.endCalls == 24,
                "modifier and post execution preserved " + name);
            if (flags[i][1] == 0) {
                check(result.logs == 0 && result.chars == 0, "OFF producer emits zero log characters " + name);
                check(result.stats.scoredCalls == 0, "OFF skips final trace-only traversal " + name);
            }
        }
    }
    private static function cacheSignature(bag:Object):String {
        if (bag == null) return "null";
        var keys:Array = [];
        for (var key:String in bag) keys.push(key);
        keys.sort();
        var result:String = "";
        for (var i:Number = 0; i < keys.length; i++) result += keys[i] + "=" + bag[keys[i]] + ";";
        return result;
    }
    private static function runWeapon(debug:Boolean, level:Number, legacy:Boolean, scenario:Number):Object {
        _root.AI调试模式 = debug; _root.AI日志级别 = level;
        estimatorCalls = logCalls = logChars = 0;
        var actor:MovieClip = _root.createEmptyMovieClip("__aiWeaponFixture",_root.getNextHighestDepth());
        actor.名字 = "fixture"; actor.hp = actor.hp满血值 = 100; actor.攻击模式 = "空手";
        if (scenario > 0) actor.刀 = {name:"fixture"};
        if (scenario > 1) {actor.手枪 = {value:{shot:0}}; actor.手枪弹匣容量 = 12;}
        if (scenario > 2) {actor.长枪 = {value:{shot:0}}; actor.长枪弹匣容量 = 30;}
        if (scenario == 4) {actor.手枪2 = {value:{shot:0}}; actor.手枪2弹匣容量 = 12;}
        actor.switches = 0;
        actor.攻击模式切换 = function(mode:String):Void {
            this.攻击模式 = mode == "手枪" && this.手枪2 ? "双枪" : mode;
            this.switches++;
            PlayerInfoProvider.invalidateDpsCache(this);
        };
        var data = {self:actor,target:null,arbiter:null,_retreatFailCount:0};
        var stance:StanceManager = new StanceManager();
        if (scenario == 5) {
            actor.攻击模式 = "长枪"; actor.长枪.value.shot = 30;
            data.target = {hp:100,hp满血值:100}; data.absdiff_x = 100;
            data.updateSelf = data.updateTarget = function():Void {};
            stance.syncStance("长枪");
        }
        var evaluator:WeaponEvaluator = new WeaponEvaluator(personality(),stance);
        var facade:Object = evaluator;
        // Frozen old behavior: before the change there was no independent post-switch warm-up.
        if (legacy) facade.warmDpsAfterSwitch = function(self:MovieClip,modes:Array):Void {};
        var scores:Array = [];
        var originalScore:Function = facade.finalModeScore;
        facade.finalModeScore = function():Number {
            var value:Number = originalScore.apply(this,arguments);
            if (this._lastWeaponSwitchFrame != _root.帧计时器.当前帧数) scores.push(arguments[1] + "=" + value);
            return value;
        };
        var frames:Array = [0,4,8,16,24,30,32,40,48,56,64,80,88,96,104];
        var signature:String = "";
        for (var i:Number = 0; i < frames.length; i++) {
            _root.帧计时器.当前帧数 = frames[i];
            if (frames[i] == 16 || frames[i] == 48) {
                actor.攻击模式 = "空手";
                PlayerInfoProvider.invalidateDpsCache(actor);
            }
            scores.length = 0;
            evaluator.evaluateWeaponMode(data);
            signature += frames[i] + ":" + actor.攻击模式 + "/" + actor.switches + "/"
                + data.xrange + "/" + data.xdistance + "/" + facade._lastWeaponSwitchFrame
                + "/" + scores.join(",") + "/" + cacheSignature(actor.估算) + "/" + estimatorCalls + "|";
        }
        var result:Object = {signature:signature,computes:estimatorCalls,switches:actor.switches,logs:logCalls};
        actor.removeMovieClip();
        return result;
    }
    private static function testWeaponFlags():Void {
        var estimator:Object = WeaponDpsEstimator;
        var oldUnarmed:Function = estimator.unarmedComboDPS;
        var oldMelee:Function = estimator.meleeComboDPS;
        var oldGun:Function = estimator.gunSustainedDPS;
        var oldReload:Function = estimator.gunReloadSeconds;
        var oldBurst:Function = estimator.gunBurstSeconds;
        estimator.unarmedComboDPS = function():Number {AIDiagnosticsTest.estimatorCalls++; return 10 + _root.帧计时器.当前帧数;};
        estimator.meleeComboDPS = function():Number {AIDiagnosticsTest.estimatorCalls++; return 60 + _root.帧计时器.当前帧数;};
        estimator.gunSustainedDPS = function(unit:MovieClip,mode:String):Number {
            AIDiagnosticsTest.estimatorCalls++;
            return (mode == "长枪" ? 180 : 120) + _root.帧计时器.当前帧数;
        };
        estimator.gunReloadSeconds = function():Number {return 1;};
        estimator.gunBurstSeconds = function():Number {return 2;};
        var witnessedOldDrift:Boolean = false;
        for (var scenario:Number = 0; scenario < 6; scenario++) {
            var oldOn:Object = runWeapon(true,3,true,scenario);
            var oldOff:Object = runWeapon(false,0,true,scenario);
            if (oldOn.signature != oldOff.signature) witnessedOldDrift = true;
            var flags:Array = [[true,3],[false,3],[true,0],[false,0]];
            for (var i:Number = 0; i < flags.length; i++) {
                var result:Object = runWeapon(flags[i][0],flags[i][1],false,scenario);
                check(result.signature == oldOn.signature, "weapon scores/cache stamps/compute count/modes parity " + scenario + "/" + flags[i].join("/"));
                if (!flags[i][0]) check(result.logs == 0, "weapon OFF has no log producer " + scenario + "/" + flags[i][1]);
            }
            if (scenario == 2) check(oldOn.switches > 0 && oldOn.computes > 0, "weapon fixture exercises actual switches and DPS cache");
        }
        check(witnessedOldDrift, "legacy debug OFF reproduces cache-timing divergence");
        var ttlActor:MovieClip = _root.createEmptyMovieClip("__aiTtlFixture",_root.getNextHighestDepth());
        estimatorCalls = 0;
        _root.帧计时器.当前帧数 = 0;
        check(PlayerInfoProvider.getUnarmedDPS(ttlActor) == 10 && estimatorCalls == 1, "DPS cache starts on actual read frame");
        _root.帧计时器.当前帧数 = 29;
        check(PlayerInfoProvider.getUnarmedDPS(ttlActor) == 10 && estimatorCalls == 1, "DPS cache is retained before the 30-frame boundary");
        _root.帧计时器.当前帧数 = 30;
        check(PlayerInfoProvider.getUnarmedDPS(ttlActor) == 40 && estimatorCalls == 2
            && ttlActor.估算._stamp_unarmed == 30, "DPS cache refreshes exactly at the 30-frame boundary");
        PlayerInfoProvider.invalidateDpsCache(ttlActor);
        check(PlayerInfoProvider.getUnarmedDPS(ttlActor) == 40 && estimatorCalls == 3, "explicit invalidation still recomputes inside the same frame");
        ttlActor.removeMovieClip();
        estimator.unarmedComboDPS = oldUnarmed; estimator.meleeComboDPS = oldMelee;
        estimator.gunSustainedDPS = oldGun; estimator.gunReloadSeconds = oldReload; estimator.gunBurstSeconds = oldBurst;
    }
    private static function benchmarkTrace():Void {
        runScoring(true,3,5,false); runScoring(false,0,5,false);
        var full:Array = []; var off:Array = [];
        for (var rep:Number = 0; rep < 5; rep++) {
            for (var lane:Number = 0; lane < 2; lane++) {
                var isFull:Boolean = ((rep + lane) % 2 == 0);
                var start:Number = getTimer();
                runScoring(isFull,isFull ? 3 : 0,80,false);
                var elapsed:Number = getTimer() - start;
                if (isFull) full.push(elapsed); else off.push(elapsed);
            }
        }
        trace("AS2_HOTPATH_BENCH ai_trace iterations=80 full_ms=" + full.join(",") + " off_ms=" + off.join(",") + " sink=" + sink);
    }
}
