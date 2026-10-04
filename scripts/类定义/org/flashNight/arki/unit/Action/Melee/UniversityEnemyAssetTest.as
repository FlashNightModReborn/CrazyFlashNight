import org.flashNight.arki.unit.Action.Melee.BladeShootCore;
import org.flashNight.arki.spatial.move.Mover;
import org.flashNight.gesh.depth.DepthManager;
import org.flashNight.arki.unit.UnitComponent.Initializer.UnitAIInitializer;

/**
 * Real AVM1 playback of the published university enemy timelines and BladeShootCore.
 * Root initialization, equipment loading and the outgoing bullet sink are fixtures.
 * Enemy walk/move helpers, attack movement helpers, Mover and chase AI use production code.
 * This verifies emission contracts and interruption, not the complete game damage pipeline.
 * It never loads a player profile or writes a save.
 */
class org.flashNight.arki.unit.Action.Melee.UniversityEnemyAssetTest {
    private static var passed:Number, failed:Number, ticks:Number, finished:Boolean;
    private static var library:MovieClip, driver:MovieClip, collision:MovieClip;
    private static var loader:MovieClipLoader, listener:Object, cases:Array, saved:Object;
    private static var prefixes:Array = ["", "狂野", "长柄", "刀剑", "长枪", "长棍"];
    // Counts from the original source's blade calls plus recovered donor area placements.
    private static var expected:Array = [33, 57, 48, 36, 60, 54];
    private static var starts:Array = [
        [[1,15,30,43,61], [78,99,123,143,167], [188,205,222,243,264],
         [284,297,311,326,339], [359,378,393,406,423], [449,463,479,496,512]],
        [[1,15,30,43,61], [78,97,118,140,160], [188,206,223,242,274],
         [293,308,323,336,349], [370,389,404,418,434], [459,473,489,506,523]]
    ];

    private static function check(ok:Boolean, label:String):Void {
        if (ok) passed++;
        else { failed++; trace("[TEST_FAIL] UniversityEnemyAssetTest: " + label); }
    }

    public static function runAllTests():Void {
        passed = failed = ticks = 0; finished = false; cases = [];
        saved = {};
        saved.depthManager = DepthManager.instance;
        var keys:Array = ["gameworld", "敌人函数", "敌人二级函数", "初始化敌人模板", "初始化思考标签",
            "装备引用配置", "子弹属性初始化", "子弹区域shoot传递", "效果", "add2map2", "控制目标", "控制目标全自动", "collisionLayer", "暂停", "帧计时器"];
        for (var i:Number = 0; i < keys.length; i++) saved[keys[i]] = _root[keys[i]];
        library = _root.createEmptyMovieClip("__universityEnemyLibrary", _root.getNextHighestDepth());
        driver = _root.createEmptyMovieClip("__universityEnemyDriver", _root.getNextHighestDepth());
        installFixtures();
        driver.waited = 0;
        driver.onEnterFrame = function():Void {
            if (++this.waited > 200) {
                UniversityEnemyAssetTest.check(false, "source load timeout");
                UniversityEnemyAssetTest.finish();
            }
        };
        listener = {onLoadInit:function(loaded:MovieClip):Void {
            UniversityEnemyAssetTest.loaded();
        }, onLoadError:function(loaded:MovieClip, error:String):Void {
            UniversityEnemyAssetTest.check(false, "actual SWF load " + error);
            UniversityEnemyAssetTest.finish();
        }};
        loader = new MovieClipLoader(); loader.addListener(listener);
        check(loader.loadClip("../flashswf/arts/new/大学人员.swf", library), "request actual published asset");
    }

    private static function installFixtures():Void {
        _root.gameworld = library;
        _root.暂停 = false;
        _root.帧计时器 = {当前帧数:0};
        collision = _root.createEmptyMovieClip("__universityEnemyCollision", _root.getNextHighestDepth());
        _root.collisionLayer = collision;
        Mover.init();
        DepthManager.instance = new DepthManager(library, 0, 1048575, 128);
        check(DepthManager.instance.calibrate(-1000, 1000), "real DepthManager calibrated");
        var productionEnemy:Object = _root.敌人函数;
        _root.控制目标 = "__no_player"; _root.控制目标全自动 = false;
        _root.敌人函数 = {行走:productionEnemy.行走, 移动:productionEnemy.移动,
            获取大学学员随机装扮:function(unit:MovieClip):Void {
                unit.fixtureDressup = "student"; unit.刀 = "破旧军刀"; unit.刀_装扮 = "fixtureBlade";
            },
            获取大学剑道社随机装扮:function(unit:MovieClip):Void {
                unit.fixtureDressup = "swordClub"; unit.刀_装扮 = "fixtureBlade";
            },
            配置音效:function(kind:String, unit:MovieClip):Void {}
        };
        _root.初始化思考标签 = function(clip:MovieClip):Void {
            clip._name = "思考标签"; clip.stop(); clip._visible = false;
        };
        _root.装备引用配置 = {配置装扮:function(container:MovieClip, linkage:String, name:String, slot:String):Void {
            var dressup:MovieClip = container.createEmptyMovieClip(name, container.getNextHighestDepth());
            for (var n:Number = 1; n <= 3; n++) {
                var point:MovieClip = dressup.createEmptyMovieClip("刀口位置" + n, n);
                point._x = n * 12; point._y = -n * 2;
            }
        }};
        _root.初始化敌人模板 = function():Void {
            this.hp = 1000; this.mp = 80;
            this.空手攻击力 = 100; this.刀属性 = {power:50}; this.刀_刀口数 = 3;
            this.被动技能 = {刀剑攻击:{启用:this.fixturePassive === true, 等级:2}};
            this.mp攻击加成 = 10; this.重量 = 10; this.体重 = 70;
            this.fixtureMoves = 0; this.fixtureWalks = 0; this.fixtureDone = 0;
            this.Z轴坐标 = 200; this._y = 200;
            this.行走X速度 = 3; this.行走Y速度 = 1.5; this.跑X速度 = 6; this.跑Y速度 = 3;
            this.version = 1;
            this.aabbCollider = {updateFromUnitArea:function(clip:MovieClip):Void {}};
            this.dispatcher = {publish:function(event:String, owner:MovieClip, target:MovieClip):Void {
                if (event == "aggroSet") owner.攻击目标 = target._name;
                else if (event == "aggroClear") owner.攻击目标 = "无";
            }};
            this.状态 = "空手站立"; this.攻击模式 = "空手";
            this.状态改变 = function(next:String):Void {
                if (this.状态 == next) return;
                this.状态 = next; this.gotoAndStop(next);
                if (this.man) this.man._xscale = this.方向 == "左" ? -100 : 100;
            };
            this.动画完毕 = function():Void {
                this.fixtureDone++;
                this.左行 = this.右行 = this.上行 = this.下行 = false;
                this.状态改变(this.hp <= 0 ? "血腥死" : "空手站立");
            };
            this.移动 = function(dir:String, speed:Number):Void {
                this.fixtureMoves++;
                _root.敌人函数.移动.call(this, dir, speed);
            };
            this.行走 = function():Void {
                this.fixtureWalks++;
                _root.敌人函数.行走.call(this);
            };
            this.方向改变 = function(dir:String):Void {
                this.方向 = dir; if (this.man) this.man._xscale = dir == "左" ? -100 : 100;
            };
            this.刀口位置生成子弹 = BladeShootCore.shoot;
            this.中招呐喊 = function():Void {};
            this.硬直 = function(clip:MovieClip, amount:Number):Void {};
            this.死亡检测 = function():Void {};
            this.击飞浮空 = function():Void {};
            this.击飞倒地 = function():Void {};
            this.gotoAndStop("空手站立");
        };
        _root.子弹属性初始化 = function(clip:MovieClip):Object {
            var unit:MovieClip = clip._parent._parent;
            var point:Object = {x:clip._x, y:clip._y};
            clip._parent.localToGlobal(point); _root.gameworld.globalToLocal(point);
            return {发射者:unit._name, shootX:point.x, shootY:point.y, shootZ:unit.Z轴坐标, 子弹威力:10, Z轴攻击范围:10, 霰弹值:1};
        };
        _root.子弹区域shoot传递 = function(properties:Object):Void {
            UniversityEnemyAssetTest.capture(properties);
        };
        _root.效果 = function():Void {};
        _root.add2map2 = function():Void {};
    }

    private static function addCase(enemy:Number, kind:Number, gender:String, facing:String, variant:String, passive:Boolean):Void {
        var id:String = "u" + cases.length;
        var target:MovieClip = library.createEmptyMovieClip(id + "Target", library.getNextHighestDepth());
        target.hp = 1000; target.Z轴坐标 = 200; target._x = facing == "右" ? 700 : -700; target._y = 200;
        var unit:MovieClip = library.attachMovie(enemy == 0 ? "敌人-黑铁派学员" : "敌人-剑道社社员",
            id, library.getNextHighestDepth(), {性别:gender, fixturePassive:passive});
        var item:Object = {id:id, unit:unit, target:target, enemy:enemy, kind:kind, gender:gender, facing:facing,
            variant:variant, passive:passive, hits:0, areas:0, invalid:0, firstPower:undefined, stale:0, seen:[false,false,false,false,false]};
        unit.fixtureCase = item; unit._visible = false;
        cases.push(item);
    }

    private static function loaded():Void {
        if (finished) return;
        library.stop();
        // Remove the source's import anchor preview while retaining its linkage dictionary.
        var previews:Array = [];
        for (var key:String in library) {
            var child:Object = library[key];
            if (typeof(child) == "movieclip" && child._parent === library) previews.push(child);
        }
        for (var p:Number = 0; p < previews.length; p++) {
            previews[p].swapDepths(library.getNextHighestDepth());
            previews[p].removeMovieClip();
        }
        for (var enemy:Number = 0; enemy < 2; enemy++) {
            for (var kind:Number = 0; kind < 6; kind++) {
                for (var gender:Number = 0; gender < 2; gender++) {
                    for (var face:Number = 0; face < 2; face++) {
                        addCase(enemy, kind, gender == 0 ? "男" : "女", face == 0 ? "右" : "左", "combo", false);
                    }
                }
            }
            addCase(enemy, 0, "男", "右", "short", false);
            addCase(enemy, 0, "女", "左", "short", false);
            addCase(enemy, 0, "男", "右", "passive", true);
            var extras:Array = ["迅捷", "直剑", "长刀", "hit", "dead", "remove", "lost"];
            for (var x:Number = 0; x < extras.length; x++) addCase(enemy, 0, "女", "左", extras[x], false);
            var motions:Array = ["walk右", "walk左", "walk上", "walk下", "run右", "run左", "chase"];
            for (var m:Number = 0; m < motions.length; m++) {
                addCase(enemy, 0, "男", "右", motions[m], false);
                addCase(enemy, 0, "女", "左", motions[m], false);
            }
        }
        ticks = 0;
        driver.onEnterFrame = function():Void { UniversityEnemyAssetTest.tick(); };
    }

    private static function beginCase(item:Object):Void {
        var unit:MovieClip = item.unit;
        check(unit._parent === library && unit.hp == 1000, item.id + " actual export initialized");
        check(unit.性别 == item.gender, item.id + " gender retained");
        check(unit.fixtureDressup == (item.enemy == 0 ? "student" : "swordClub"), item.id + " correct dressup entry");
        if (item.enemy == 0) check(unit.刀 == "破旧的军刀", item.id + " canonical weapon identity");
        unit.攻击目标 = item.target._name;
        if (item.variant == "chase") item.target._x = item.facing == "右" ? 3000 : -3000;
        if (item.enemy == 0 && item.kind == 4 && item.variant == "combo") {
            item.target.Z轴坐标 = item.target._y = item.facing == "右" ? 220 : 180;
        }
        item.motion = item.variant.indexOf("walk") == 0 || item.variant.indexOf("run") == 0 || item.variant == "chase";
        if (item.motion) {
            item.startX = unit._x; item.startZ = unit.Z轴坐标;
            unit.左行 = unit.右行 = unit.上行 = unit.下行 = false;
            if (item.variant == "chase") {
                unit.x轴攻击范围 = 100; unit.x轴保持距离 = 100;
                UnitAIInitializer.initialize(unit);
                check(unit.unitAI.type == "Enemy", item.id + " real Enemy AI initialized");
            } else {
                var dir:String = item.variant.substr(3);
                if (item.variant.indexOf("walk") == 0) dir = item.variant.substr(4);
                unit[dir + "行"] = true;
                if (item.variant.indexOf("run") == 0) unit.状态改变("空手跑");
            }
            return;
        }
        unit.方向 = item.facing;
        unit.兵器动作类型 = item.variant == "迅捷" || item.variant == "直剑" || item.variant == "长刀" ? item.variant : prefixes[item.kind];
        // Undefined player control and active player flags must not redirect an enemy timeline.
        unit.操控编号 = undefined; unit.动作A = unit.动作B = true; unit.左行 = unit.上行 = true;
        unit.状态改变(item.variant == "short" ? "近战" : "空手攻击");
    }

    private static function capture(properties:Object):Void {
        var unit:MovieClip = library[properties.发射者];
        var item:Object = unit.fixtureCase;
        if (item == undefined) { check(false, "emission has actual owning enemy"); return; }
        item.hits++;
        if (item.firstPower == undefined) item.firstPower = properties.子弹威力;
        if (properties.区域定位area._name == "area") item.areas++;
        if (isNaN(properties.子弹威力) || !(properties.子弹威力 > 0)
            || isNaN(properties.shootX) || isNaN(properties.shootY) || isNaN(properties.shootZ)
            || !(properties.Z轴攻击范围 > 0) || !(properties.霰弹值 > 0)) {
            if (item.invalid == 0) trace("UniversityEnemyAssetTest invalid " + item.id + " frame=" + unit.man._currentframe
                + " power=" + properties.子弹威力 + " x=" + properties.shootX + " y=" + properties.shootY
                + " z=" + properties.shootZ + " range=" + properties.Z轴攻击范围 + " count=" + properties.霰弹值
                + " area=" + properties.区域定位area + " blade=" + unit.man.刀);
            item.invalid++;
        }
        if (!(unit.hp > 0) || (unit.状态 != "空手攻击" && unit.状态 != "近战")) item.stale++;
        if (item.interrupted && item.variant != "lost") item.stale++;
    }

    private static function tick():Void {
        if (finished) return;
        ticks++;
        _root.帧计时器.当前帧数 = ticks;
        if (ticks == 3) {
            for (var i:Number = 0; i < cases.length; i++) beginCase(cases[i]);
            return;
        }
        if (ticks < 4) return;
        for (var j:Number = 0; j < cases.length; j++) {
            var item:Object = cases[j];
            var unit:MovieClip = item.unit;
            if (item.motion && !item.motionStopped && !_root.暂停 && ticks % 4 == 0 && unit.unitAI) unit.unitAI.update();
            if (item.motion && ticks == 168) {
                item.pausedX = unit._x; item.pausedZ = unit.Z轴坐标; item.pausedWalks = unit.fixtureWalks;
            }
            if (item.motion && ticks == 169) check(unit._x == item.pausedX && unit.Z轴坐标 == item.pausedZ && unit.fixtureWalks == item.pausedWalks, item.id + " pause stops movement consumer");
            if (item.motion && ticks == 171) {
                if (unit._x == item.pausedX && unit.Z轴坐标 == item.pausedZ) trace("UniversityEnemyAssetTest resume diagnostic " + item.id + " x=" + unit._x + " z=" + unit.Z轴坐标 + " state=" + unit.状态 + " right=" + unit.右行 + " left=" + unit.左行 + " up=" + unit.上行 + " down=" + unit.下行);
                check(unit._x != item.pausedX || unit.Z轴坐标 != item.pausedZ, item.id + " resume consumes movement flags");
            }
            if (item.motion && ticks == 172) {
                item.motionStopped = true;
                unit.左行 = unit.右行 = unit.上行 = unit.下行 = false;
                item.stoppedX = unit._x; item.stoppedZ = unit.Z轴坐标;
            }
            if (unit.状态 == "空手攻击") {
                var points:Array = starts[item.enemy][item.kind];
                var frame:Number = unit.man._currentframe;
                for (var n:Number = 0; n < 5; n++) {
                    if (frame >= points[n] && (n == 4 || frame < points[n + 1])) item.seen[n] = true;
                }
            }
            if (ticks == 15 && (item.variant == "hit" || item.variant == "dead" || item.variant == "remove" || item.variant == "lost")) {
                item.beforeInterrupt = item.hits; item.movesAtInterrupt = unit.fixtureMoves; item.interrupted = true;
                if (item.variant == "hit") unit.状态改变("被击");
                else if (item.variant == "dead") { unit.hp = 0; unit.状态改变("血腥死"); }
                else if (item.variant == "remove") unit.removeMovieClip();
                else item.target.hp = 0;
            }
        }
        if (ticks == 168) _root.暂停 = true;
        if (ticks == 170) _root.暂停 = false;
        if (ticks >= 175) {
            for (var c:Number = 0; c < cases.length; c++) verify(cases[c]);
            finish();
        }
    }

    private static function verify(item:Object):Void {
        var unit:MovieClip = item.unit;
        if (item.motion) {
            var dx:Number = unit._x - item.startX;
            var dz:Number = unit.Z轴坐标 - item.startZ;
            var dir:String = item.variant.indexOf("walk") == 0 ? item.variant.substr(4) : item.variant.substr(3);
            if (item.variant == "chase") dir = item.facing;
            check(dir == "右" ? dx > 0 : dir == "左" ? dx < 0 : dir == "上" ? dz < 0 : dz > 0, item.id + " actual walk/run/AI changes expected coordinate");
            check(isFinite(dx) && isFinite(dz), item.id + " finite real Mover coordinates");
            check(unit._y == unit.Z轴坐标, item.id + " real Mover maintains Z coordinate");
            check(unit.fixtureWalks > 0 && unit.fixtureMoves > 0, item.id + " controller consumes AI or explicit flags");
            check(unit.状态 == "空手站立" && unit._x == item.stoppedX && unit.Z轴坐标 == item.stoppedZ, item.id + " cleared flags stop and return idle");
            check(item.hits == 0, item.id + " movement does not invoke attack");
            return;
        }
        check(item.invalid == 0, item.id + " finite positive bullet attributes and coordinates");
        check(item.stale == 0, item.id + " no stale emission");
        if (item.variant == "hit" || item.variant == "dead" || item.variant == "remove" || item.variant == "lost") {
            check(item.beforeInterrupt > 0, item.id + " interruption after a real strike");
            if (item.variant != "lost") check(item.hits == item.beforeInterrupt, item.id + " interrupted clip stops attacking");
            if (item.variant == "hit") check(unit.状态 == "空手站立", item.id + " actual hit timeline returns to idle");
            if (item.variant == "lost") check(unit.状态 == "空手站立" && !item.seen[1], item.id + " lost target ends before next segment");
            return;
        }
        var count:Number = item.variant == "short" ? (item.enemy == 0 ? 12 : 6) : expected[item.kind];
        check(item.hits == count, item.id + " all original strike windows emitted " + item.hits + "/" + count);
        check(unit.状态 == "空手站立" && unit.fixtureDone == 1, item.id + " finishes exactly once");
        check(unit.fixtureWalks > 0, item.id + " idle movement consumer resumes after attack");
        check(unit.mp == 80, item.id + " no player MP expenditure");
        if (item.variant != "short") {
            check(item.seen[0] && item.seen[1] && item.seen[2] && item.seen[3] && item.seen[4], item.id + " visits all five segments");
            check(unit.fixtureMoves > 0, item.id + " real movement events call enemy movement");
            check(item.facing == "右" ? unit._x > 0 : unit._x < 0, item.id + " movement follows enemy facing");
            if (item.kind == 4 && item.variant == "combo") {
                // Only the black-iron gun timeline has target-Z movement placements.
                if (item.enemy == 0) check(item.facing == "右" ? unit.Z轴坐标 > 200 && unit.Z轴坐标 <= 220 : unit.Z轴坐标 < 200 && unit.Z轴坐标 >= 180, item.id + " actual attack follows target Z without overshoot");
                else check(unit.Z轴坐标 == 200, item.id + " sword-club horizontal attack preserves Z");
                check(unit._y == unit.Z轴坐标, item.id + " actual attack movement keeps Z coordinate synchronized");
            }
            if (item.kind == 1 || item.kind == 2 || item.kind == 3) check(item.areas == 6, item.id + " all six area placements fire");
        }
        if (item.variant == "passive") {
            var power:Number = item.enemy == 0 ? 94 : 87.5;
            check(Math.abs(item.firstPower - power) < 0.0001, item.id + " original passive and MP bonus formula");
        }
    }

    private static function finish():Void {
        if (finished) return;
        finished = true;
        delete driver.onEnterFrame;
        for (var c:Number = 0; c < cases.length; c++) cases[c].unit.unitAI.destroy();
        library.removeMovieClip(); driver.removeMovieClip(); collision.removeMovieClip();
        DepthManager.instance = saved.depthManager;
        delete saved.depthManager;
        for (var key:String in saved) _root[key] = saved[key];
        trace("UniversityEnemyAssetTest: " + passed + " passed, " + failed + " failed; " + cases.length + " actual timeline cases");
        if (failed == 0) trace("[PASS] university-enemies actual timelines, emissions, movement and interruption");
        else trace("[TEST_FAIL] university-enemies asset behavior");
        _root.universityEnemyAssetComplete();
    }
}
