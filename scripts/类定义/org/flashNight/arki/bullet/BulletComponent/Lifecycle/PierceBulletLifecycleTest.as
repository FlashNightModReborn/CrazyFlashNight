import org.flashNight.arki.bullet.BulletComponent.Lifecycle.*;
import org.flashNight.arki.bullet.BulletComponent.Init.BulletInitializer;
import org.flashNight.arki.bullet.BulletComponent.Queue.BulletQueueProcessor;
import org.flashNight.arki.bullet.Factory.BulletFactory;
import org.flashNight.arki.component.Collider.ColliderFactoryRegistry;
import org.flashNight.arki.component.Damage.DamageManagerFactory;

/**
 * 真正加载现役素材SWF，原XFL帧脚本与统一profile同场逐帧对照。
 * 不用手写frame数模拟Flash；对照frame/area bounds/hook状态/销毁时点。
 * settleHit使用确定性DamageResult边界夹具，证明actual-only hook与记账；
 * 本套件不把该夹具称为完整战斗伤害公式或完整实战验收。
 */
class org.flashNight.arki.bullet.BulletComponent.Lifecycle.PierceBulletLifecycleTest {
    private static var passed:Number, failed:Number, ticks:Number, finished:Boolean;
    private static var library:MovieClip, driver:MovieClip;
    private static var loader:MovieClipLoader, listener:Object, pairs:Array;
    private static var oldProbe:Object;

    private static function check(ok:Boolean, label:String):Void {
        if (ok) passed++;
        else { failed++; trace("[TEST_FAIL] PierceBulletLifecycleTest: " + label); }
    }

    public static function runAllTests():Void {
        passed = failed = ticks = 0; finished = false; pairs = [];
        var queue:Object = BulletQueueProcessor;
        oldProbe = queue._raySettleProbe; queue._raySettleProbe = null;
        check(PierceBulletProfile.resolve("穿刺子弹") === PierceBulletProfile.resolve("无壳穿刺子弹"), "true/caseless share profile");
        check(PierceBulletProfile.resolve("单元体-次级穿刺子弹") == null, "visual units never inherit single-bullet hit profile");
        check(PierceBulletProfile.resolve("横向联弹") == null, "group lifecycle remains independent");
        check(PierceBulletProfile.resolve("次级穿刺子弹").firstHitLabel == "爆炸", "secondary transition label");
        var template:Object = {子弹种类:"次级穿刺子弹", pierceLimit:9, hitCount:0};
        var prepared:Object = PierceBulletLifecycle.prepareInit(template, PierceBulletProfile.resolve("次级穿刺子弹"));
        check(template.击中时触发函数 == undefined && template.__pierceProfile == undefined, "prepare does not mutate reusable firing template");
        check(prepared.pierceLimit == 9 && prepared.hitCount == 0, "profile leaves budget and hit accounting unchanged");
        check(typeof(prepared.击中时触发函数) == "function" && typeof(prepared.击中地图时触发函数) == "function", "secondary supplies both default hooks");
        budgetInitialization();
        library = _root.createEmptyMovieClip("__pierceSourceLibrary", _root.getNextHighestDepth());
        driver = _root.createEmptyMovieClip("__pierceTimelineDriver", _root.getNextHighestDepth());
        driver.waited = 0;
        driver.onEnterFrame = function():Void {
            if (++this.waited > 240) { PierceBulletLifecycleTest.check(false,"source load timeout"); PierceBulletLifecycleTest.finish(); }
        };
        listener = {onLoadInit:function(loaded:MovieClip):Void {
            PierceBulletLifecycleTest.loaded();
        }, onLoadError:function(loaded:MovieClip, code:String):Void {
            PierceBulletLifecycleTest.check(false,"source SWF load " + code); PierceBulletLifecycleTest.finish();
        }};
        loader = new MovieClipLoader(); loader.addListener(listener);
        check(loader.loadClip("../flashswf/arts/原版素材库-子弹.swf", library), "request actual published source library");
    }

    private static function budgetInitialization():Void {
        var initializer:Object = BulletInitializer;
        var saved:Object = initializer.attributeMap;
        initializer.attributeMap = {};
        initializer.attributeMap["次级穿刺子弹"] = {pierceLimit:3};
        initializer.attributeMap["横向联弹-次级穿刺子弹"] = {pierceLimit:2};
        var single:Object = {子弹种类:"次级穿刺子弹",霰弹值:4};
        var chain:Object = {子弹种类:"横向联弹-次级穿刺子弹",霰弹值:4};
        var unlimited:Object = {子弹种类:"穿刺子弹",霰弹值:4};
        BulletInitializer.initializeBulletProperties(single);
        BulletInitializer.initializeBulletProperties(chain);
        BulletInitializer.initializeBulletProperties(unlimited);
        check(single.pierceLimit == 12 && chain.pierceLimit == 8, "production initializer retains scatter-multiplied 3/2 presets");
        check(unlimited.pierceLimit == undefined, "true piercing remains unlimited");
        initializer.attributeMap = saved;
    }

    private static function loaded():Void {
        if (finished) return;
        factorySmoke();
        addPair("pierce-flight", "穿刺子弹", "idle");
        addPair("caseless-flight", "无壳穿刺子弹", "idle");
        addPair("pierce-vanish", "穿刺子弹", "vanish");
        addPair("caseless-vanish", "无壳穿刺子弹", "vanish");
        addPair("pierce-map", "穿刺子弹", "map");
        addPair("caseless-map", "无壳穿刺子弹", "map");
        addPair("secondary-flight", "次级穿刺子弹", "idle");
        addPair("secondary-hit", "次级穿刺子弹", "hit");
        addPair("secondary-repeat-same-tick", "次级穿刺子弹", "repeat");
        addPair("secondary-repeat-later", "次级穿刺子弹", "later");
        addPair("secondary-miss-hit", "次级穿刺子弹", "miss");
        addPair("secondary-map", "次级穿刺子弹", "map");
        addPair("secondary-unknown-label", "次级穿刺子弹", "vanish");
        addPair("secondary-custom-hit", "次级穿刺子弹", "custom-hit");
        addPair("secondary-custom-map", "次级穿刺子弹", "custom-map");
        var unit:MovieClip = library.attachMovie("单元体-次级穿刺子弹", "nestedSecondary", library.getNextHighestDepth());
        driver.nestedUnit = unit;
        check(unit._parent === library, "actual chain-unit linkage exists");
        driver.onEnterFrame = function():Void { PierceBulletLifecycleTest.tick(); };
    }

    private static function factorySmoke():Void {
        var oldWorld:Object = _root.gameworld;
        _root.gameworld = library;
        library.子弹区域 = library;
        ColliderFactoryRegistry.init();
        DamageManagerFactory.init();
        var names:Array = ["穿刺子弹", "次级穿刺子弹", "无壳穿刺子弹"];
        for (var i:Number = 0; i < names.length; i++) {
            var source:Object = {子弹种类:names[i], baseAsset:names[i], flags:4, stateFlags:0,
                _x:0, _y:0, shootX:0, shootY:0, shootZ:0, Z轴坐标:0, 霰弹值:1,
                发射者名:"fixtureShooter", 子弹速度:1, 子弹散射度:0, hitCount:0};
            if (i == 1) source.pierceLimit = 3;
            var bullet:MovieClip = BulletFactory.createBulletInstance(source, driver, 0);
            check(bullet._parent === library && bullet.__pierceProfile === PierceBulletProfile.resolve(names[i]),
                "production factory wires profile " + names[i]);
            check(bullet.aabbCollider != null && typeof(bullet.onEnterFrame) == "function"
                && typeof(bullet.updateMovement) == "function", "production factory retains normal lifecycle " + names[i]);
            check(bullet.pierceLimit == source.pierceLimit && bullet.hitCount == 0 && bullet.霰弹值 == 1,
                "production factory preserves budget and logical scatter " + names[i]);
            bullet.removeMovieClip();
        }
        delete library.子弹区域;
        _root.gameworld = oldWorld;
    }

    private static function addPair(label:String, linkage:String, mode:String):Void {
        var source:Object = {子弹种类:linkage, baseAsset:linkage, hitCount:0, stateFlags:0};
        if (mode == "custom-hit") source.击中时触发函数 = function():Void { this.customHits = (this.customHits | 0) + 1; };
        if (mode == "custom-map") source.击中地图时触发函数 = function():Void { this.customMaps = (this.customMaps | 0) + 1; };
        var first:MovieClip = library.attachMovie(linkage, label + "Old", library.getNextHighestDepth(), source);
        var second:MovieClip = library.attachMovie(linkage, label + "New", library.getNextHighestDepth(),
            PierceBulletLifecycle.prepareInit(source, PierceBulletProfile.resolve(linkage)));
        var pair:Object = {label:label, mode:mode, oldBullet:first, newBullet:second,
            oldState:{removed:false,removedTick:-1}, newState:{removed:false,removedTick:-1}, record:[]};
        installRemoveTracker(first, pair.oldState, first.removeMovieClip);
        installRemoveTracker(second, pair.newState, second.removeMovieClip);
        check(first._parent === library && second._parent === library, "source/candidate attached " + label);
        pairs.push(pair);
    }

    private static function installRemoveTracker(target:MovieClip, state:Object, original:Function):Void {
        target.removeMovieClip = function():Void {
            state.removed = true; state.removedTick = PierceBulletLifecycleTest.ticks;
            original.call(this);
        };
    }

    private static function hit(target:MovieClip, miss:Boolean, scatter:Number):Void {
        if (!target._parent) return;
        var queue:Object = BulletQueueProcessor;
        var result:Object = {actualScatterUsed:scatter, dodgeStatus:miss ? "MISS" : "HIT",
            scatterModelEnabled:false, triggerDisplay:function():Void {}};
        var damage:Object = {result:result, calculateDamage:function():Object { return this.result; }};
        var enemy:MovieClip = driver.createEmptyMovieClip("fixedTarget", 3);
        enemy.hp = 100; enemy.dispatcher = {publish:function():Void {}};
        var ctx:Object = {bullet:target, shooter:driver, Damage:damage, flags:0, meleeMask:768};
        queue.settleHit(ctx, enemy, {overlapCenter:{x:0,y:0}}, 1, miss ? "MISS" : "未躲闪", true);
        enemy.removeMovieClip();
    }

    private static function trigger(target:MovieClip, mode:String):Void {
        if (!target._parent) return;
        if (mode == "hit" || mode == "later" || mode == "custom-hit") hit(target, false, 1);
        else if (mode == "repeat") { hit(target, false, 1); hit(target, false, 2); }
        else if (mode == "miss") hit(target, true, 1);
        else if (mode == "vanish") target.gotoAndPlay("消失");
        else if (mode == "map" || mode == "custom-map") {
            target.击中地图 = true;
            if (target.击中地图时触发函数) target.击中地图时触发函数();
            if (target._parent) target.gotoAndPlay("消失");
        }
    }

    private static function snapshot(target:MovieClip, state:Object):String {
        if (state.removed) return "removed@" + state.removedTick;
        var text:String = "frame=" + target._currentframe + ";area=";
        if (target.area) {
            var bounds:Object = target.area.getBounds(target);
            text += bounds.xMin + "," + bounds.yMin + "," + bounds.xMax + "," + bounds.yMax;
        } else text += "none";
        return text + ";exploded=" + target.已爆炸 + ";hook=" + Boolean(target.击中时触发函数)
            + ";hits=" + target.hitCount + ";custom=" + target.customHits + "," + target.customMaps;
    }

    private static function tick():Void {
        if (finished) return;
        ticks++;
        for (var i:Number = 0; i < pairs.length; i++) {
            var pair:Object = pairs[i];
            if (ticks == 2) { trigger(pair.oldBullet, pair.mode); trigger(pair.newBullet, pair.mode); }
            if (ticks == 5 && (pair.mode == "later" || pair.mode == "miss")) {
                hit(pair.oldBullet, false, 1); hit(pair.newBullet, false, 1);
            }
            var oldValue:String = snapshot(pair.oldBullet, pair.oldState);
            var newValue:String = snapshot(pair.newBullet, pair.newState);
            check(oldValue == newValue, pair.label + " tick " + ticks + " expected " + oldValue + " actual " + newValue);
            pair.record.push(oldValue);
            if (ticks == 3 && (pair.mode == "idle" || pair.mode == "miss")) {
                check(pair.newBullet._currentframe == 1 && pair.newBullet.area, "flight stays on real first frame " + pair.label);
            }
            if (ticks == 2 && pair.mode == "repeat") {
                check(pair.newBullet.hitCount == 3 && pair.newBullet.击中时触发函数 === false,
                    "same tick settlements preserve actualScatterUsed and disable repeat hook");
            }
        }
        if (ticks == 20) {
            var unit:MovieClip = driver.nestedUnit;
            check(unit._parent === library && unit.击中时触发函数 == undefined, "chain visual unit has no group hit dispatch");
            for (var p:Number = 0; p < pairs.length; p++) {
                var row:Object = pairs[p];
                trace("PierceTimeline " + row.label + ": " + row.record.join(" | "));
            }
            finish();
        }
    }

    private static function finish():Void {
        if (finished) return;
        finished = true;
        var queue:Object = BulletQueueProcessor; queue._raySettleProbe = oldProbe;
        loader.removeListener(listener);
        driver.removeMovieClip(); library.removeMovieClip();
        trace("PierceBulletLifecycleTest Tests Passed: " + passed);
        trace("PierceBulletLifecycleTest Tests Failed: " + failed);
        _root.pierceBulletFocusedComplete();
    }
}
