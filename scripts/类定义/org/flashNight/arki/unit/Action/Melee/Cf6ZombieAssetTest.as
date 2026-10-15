import flash.display.BitmapData;
import flash.geom.Matrix;

/** Actual published CF6 zombie timelines (敌人-CF6普通男僵尸 and 敌人-CF6女僵尸) in Antigravity专用素材.swf.
 * Initialization and outgoing damage are fixtures; no player profile or persistence is touched.
 */
class org.flashNight.arki.unit.Action.Melee.Cf6ZombieAssetTest {
    private static var library:MovieClip, driver:MovieClip;
    private static var loader:MovieClipLoader, listener:Object;
    private static var passed:Number, failed:Number, ticks:Number, ready:Boolean, finished:Boolean;
    private static var cases:Array, staticUnits:Array;
    private static var links:Array = ["敌人-CF6普通男僵尸", "敌人-CF6女僵尸"];

    private static function check(ok:Boolean, name:String):Void {
        if (ok) passed++;
        else { failed++; trace("[TEST_FAIL] Cf6ZombieAssetTest: " + name); }
    }

    public static function runAllTests():Void {
        passed = failed = ticks = 0;
        ready = finished = false;
        cases = [];
        staticUnits = [];
        library = _root.createEmptyMovieClip("__cf6ZombieLibrary", _root.getNextHighestDepth());
        driver = _root.createEmptyMovieClip("__cf6ZombieDriver", _root.getNextHighestDepth());
        library._visible = false;
        _root.gameworld = library;
        _root.暂停 = false;
        _root.控制目标 = "__no_player";
        _root.控制目标全自动 = false;
        _root.是否阴影 = true;
        _root.播放音效 = function():Void {};
        _root.发布消息 = function():Void {};
        _root.效果 = function():Void {};
        _root.add2map2 = function():Void {};
        _root.add2map = function():Void {};
        _root.初始化思考标签 = function(mc:MovieClip):Void {
            mc._name = "思考标签";
            mc.stop();
            mc._visible = false;
        };
        _root.敌人二级函数 = {
            攻击时移动: function():Void {},
            X轴追踪移动: function():Void {},
            Z轴追踪移动: function():Void {},
            计算攻击角度: function():Void {},
            固定角度移动: function():Void {}
        };
        _root.子弹区域shoot = function(
            sound:String, pellet:Number, spread:Number, effect:String,
            bulletType:String, power:Number, speed:Number, zRange:Number,
            hitEffect:String, shooterName:String, sx:Number, sy:Number,
            sz:Number, friendly:Boolean, knockdown:Number, spark:String
        ):Void {
            var actor:MovieClip = Cf6ZombieAssetTest.library[shooterName];
            if (actor != undefined && actor.fixtureCase != undefined) {
                Cf6ZombieAssetTest.capture({
                    fixtureCase: actor.fixtureCase,
                    子弹种类: bulletType,
                    子弹威力: power,
                    Z轴攻击范围: zRange,
                    击倒率: knockdown
                });
            }
        };
        _root.初始化敌人模板 = function():Void {
            this.hp = this.hp满血值 = 1000;
            this.mp = 0;
            this.空手攻击力 = 100;
            this.等级 = 30;
            this.状态 = "空手站立";
            this.攻击模式 = "空手";
            this.方向 = "右";
            this.攻击目标 = "无";
            this.Z轴坐标 = this._y = 200;
            this._x = 200;
            this.fixtureDone = 0;
            this.fixtureDeaths = 0;
            this.fixtureAttackMoves = 0;
            this.fixtureSoundConfigured = false;
            this.倒地 = this.浮空 = this.硬直中 = false;
            this.swapDepths = function():Void {};
            this.行走 = function():Void {};
            this.击飞浮空 = function():Void { this.fixtureAirborne = true; };
            this.击飞倒地 = function():Void { this.fixtureGrounded = true; };
            this.移动 = function(dir:String, speed:Number):Void {
                if (dir == this.方向 && (speed == 5 || speed == 25)) {
                    this.fixtureAttackMoves++;
                }
            };
            this.配置音效 = function(soundType:String, targetRef:MovieClip):Void {
                if (soundType == "僵尸" && targetRef === this) {
                    this.fixtureSoundConfigured = true;
                }
            };
            this.方向改变 = function(dir:String):Void {
                this.方向 = dir;
                if (this.man) this.man._xscale = dir == "左" ? -100 : 100;
            };
            this.状态改变 = function(next:String):Void {
                this.状态 = next;
                this.gotoAndStop(next);
                if (this.man) this.man._xscale = this.方向 == "左" ? -100 : 100;
            };
            this.动画完毕 = function():Void {
                this.fixtureDone++;
                this.man.stop();
            };
            this.死亡检测 = function():Void {
                this.fixtureDeaths++;
                if (this.状态 == "血腥死") {
                    this.man.stop();
                }
            };
            this.stop();
        };
        listener = {
            onLoadInit: function(mc:MovieClip):Void {
                Cf6ZombieAssetTest.loaded(mc);
            },
            onLoadError: function(mc:MovieClip, error:String):Void {
                Cf6ZombieAssetTest.check(false, "load " + error);
                Cf6ZombieAssetTest.finish();
            }
        };
        loader = new MovieClipLoader();
        loader.addListener(listener);
        check(loader.loadClip("../flashswf/arts/new/Antigravity专用素材.swf", library), "load actual published Antigravity专用素材.swf");
        driver.onEnterFrame = function():Void {
            Cf6ZombieAssetTest.tick();
        };
    }

    private static function loaded(mc:MovieClip):Void {
        mc.stop();
        var states:Array = ["空手站立", "空手行走", "空手跑", "躲闪", "击倒", "被投"];
        var moves:Array = ["attack", "hit0", "hit1", "down", "death0", "death1", "death2"];
        var expectedShots:Array = [2, 0, 0, 0, 0, 0, 0];
        for (var v:Number = 0; v < 2; v++) {
            for (var si:Number = 0; si < states.length; si++) {
                var staticUnit:MovieClip = library.attachMovie(links[v], "cf6Static_" + v + "_" + si, library.getNextHighestDepth(), {fixtureCase: -1});
                check(staticUnit != null, "attach static probe " + links[v] + " " + states[si]);
                staticUnits.push({unit: staticUnit, variant: v, state: states[si]});
            }
            for (var facing:Number = 0; facing < 2; facing++) {
                for (var j:Number = 0; j < moves.length; j++) {
                    add(v, facing, moves[j], expectedShots[j]);
                }
            }
        }
        ready = true;
        ticks = 0;
    }

    private static function add(variant:Number, facing:Number, move:String, expected:Number):Void {
        var index:Number = cases.length;
        var actor:MovieClip = library.attachMovie(links[variant], "cf6Case" + index, library.getNextHighestDepth(), {fixtureCase: index});
        check(actor != null, "attach " + links[variant] + " / " + move + " / " + facing);
        cases.push({
            actor: actor,
            variant: variant,
            facing: facing,
            move: move,
            expected: expected,
            shots: 0,
            powerOk: true,
            rangeOk: true,
            knockdownOk: true
        });
    }

    private static function capture(p:Object):Void {
        var c:Object = cases[p.fixtureCase];
        if (c == undefined) return;
        c.shots++;
        if (p.子弹威力 != 100) c.powerOk = false;
        if (p.Z轴攻击范围 != 30) c.rangeOk = false;
        if (p.击倒率 != 10) c.knockdownOk = false;
    }

    private static function checkVectorRender(actor:MovieClip, key:String):Void {
        var source:MovieClip = actor.man;
        var b:Object = source.getBounds(source);
        check(b.xMax > b.xMin && b.yMax > b.yMin, "nonempty native bounds " + key);
        var scale:Number = Math.min(200 / (b.xMax - b.xMin), 200 / (b.yMax - b.yMin));
        var m:Matrix = new Matrix(scale, 0, 0, scale, 10 - b.xMin * scale, 10 - b.yMin * scale);
        var bd:BitmapData = new BitmapData(220, 220, true, 0);
        bd.draw(source, m);
        var visible:Number = 0;
        for (var y:Number = 0; y < 220; y += 3) {
            for (var x:Number = 0; x < 220; x += 3) {
                if ((bd.getPixel32(x, y) >>> 24) > 128) visible++;
            }
        }
        check(visible > 200, "actual Flash vector pixels " + key + " (" + visible + ")");
        bd.dispose();

        // Also rasterize in actor space (ground at y = 180) to prove upper body AND lower body (legs/boots) are visibly rendered
        var actorBd:BitmapData = new BitmapData(200, 200, true, 0);
        var actorMat:Matrix = new Matrix(1, 0, 0, 1, 100 + source._x, 180 + source._y);
        actorBd.draw(source, actorMat);
        var upperPixels:Number = 0;
        var lowerPixels:Number = 0;
        for (var ay:Number = 65; ay <= 125; ay += 2) {
            for (var ax:Number = 40; ax <= 160; ax += 2) {
                if ((actorBd.getPixel32(ax, ay) >>> 24) > 128) upperPixels++;
            }
        }
        for (var ly:Number = 140; ly <= 178; ly += 2) {
            for (var lx:Number = 40; lx <= 160; lx += 2) {
                if ((actorBd.getPixel32(lx, ly) >>> 24) > 128) lowerPixels++;
            }
        }
        check(upperPixels > 30, "upper body raster pixels " + key + " (" + upperPixels + ")");
        check(lowerPixels > 25, "lower body leg/boot raster pixels " + key + " (" + lowerPixels + ")");
        actorBd.dispose();
    }

    private static function tick():Void {
        if (finished) return;
        ticks++;
        if (!ready) {
            if (ticks > 300) {
                check(false, "load timeout");
                finish();
            }
            return;
        }
        if (ticks == 3) {
            for (var si:Number = 0; si < staticUnits.length; si++) {
                var sp:Object = staticUnits[si];
                var u:MovieClip = sp.unit;
                if (sp.state == "空手站立") {
                    check(u.fixtureSoundConfigured === true, "zombie sound config called with explicit target " + links[sp.variant]);
                }
                u.状态改变(sp.state);
            }
            // Launch all 28 timeline cases (2 variants * 2 facings * 7 moves)
            for (var i:Number = 0; i < cases.length; i++) {
                var c:Object = cases[i];
                var actor:MovieClip = c.actor;
                actor.fixtureDone = 0;
                actor.fixtureDeaths = 0;
                actor.fixtureAttackMoves = 0;
                c.shots = 0;
                c.powerOk = c.rangeOk = c.knockdownOk = true;
                actor.方向改变(c.facing == 0 ? "右" : "左");
                if (c.move == "attack") {
                    actor.状态改变("空手攻击");
                } else if (c.move.substr(0, 3) == "hit") {
                    actor.状态改变("被击");
                    actor.man.gotoAndPlay("a" + c.move.substr(3));
                } else if (c.move == "down") {
                    actor.状态改变("倒地");
                } else if (c.move.substr(0, 5) == "death") {
                    actor.状态改变("血腥死");
                    actor.man.gotoAndPlay("a" + c.move.substr(5));
                }
            }
        }
        if (ticks == 4) {
            for (var sj:Number = 0; sj < staticUnits.length; sj++) {
                var spCheck:Object = staticUnits[sj];
                var uCheck:MovieClip = spCheck.unit;
                check(uCheck.man != undefined && uCheck.man._width > 0 && uCheck.man._height > 0, links[spCheck.variant] + " state " + spCheck.state + " has man clip");
                if (spCheck.state == "空手站立") {
                    checkVectorRender(uCheck, spCheck.variant == 0 ? "cf6-male-zombie" : "cf6-female-zombie");
                } else if (spCheck.state == "击倒") {
                    check(uCheck.fixtureAirborne === true, links[spCheck.variant] + " knockdown onLoad callback");
                }
            }
        }
        if (ticks == 105) {
            for (var k:Number = 0; k < cases.length; k++) {
                var item:Object = cases[k];
                var act:MovieClip = item.actor;
                check(item.shots == item.expected, "actual emission " + k + " " + item.move + " = " + item.shots + " / " + item.expected);
                check(item.powerOk && item.rangeOk && item.knockdownOk, "hitbox contract " + k + " " + item.move);
                if (item.move == "attack") {
                    check(act.fixtureAttackMoves >= 1, "attack lunge move called " + k);
                    check(act.fixtureDone == 1, "attack terminal callback " + k);
                } else if (item.move.substr(0, 3) == "hit") {
                    check(act.fixtureDone == 1, "hit terminal callback " + k + " " + item.move);
                } else if (item.move == "down") {
                    check(act.fixtureGrounded === true, "down onLoad callback " + k);
                    check(act.fixtureDeaths == 2, "down death-check callbacks " + k + " = " + act.fixtureDeaths);
                    check(act.fixtureDone == 1, "down terminal callback " + k);
                } else if (item.move.substr(0, 5) == "death") {
                    check(act.fixtureDeaths == 1, "death terminal callback " + k + " " + item.move + " = " + act.fixtureDeaths);
                }
                check(act.man._width > 0 && act.man._height > 0, "body persists through terminal frame " + k + " " + item.move);
            }
            finish();
        }
    }

    private static function finish():Void {
        if (finished) return;
        finished = true;
        delete driver.onEnterFrame;
        if (loader != null) loader.removeListener(listener);
        trace("Cf6ZombieAssetTest: " + passed + " passed, " + failed + " failed; " + cases.length + " actual timeline cases");
        library.removeMovieClip();
        driver.removeMovieClip();
        _root.cf6ZombieAssetComplete();
    }
}
