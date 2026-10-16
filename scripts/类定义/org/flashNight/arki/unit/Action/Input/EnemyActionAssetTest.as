import org.flashNight.arki.unit.Action.Input.EnemyActionRuntime;
import org.flashNight.arki.unit.Action.Input.EnemyActionInputService;

/** Real published Lee timelines with the shared action runtime.
 * Spawn stats, movement bounds and outgoing damage are isolated in-memory fixtures.
 * No profile, save, rewards, hit settlement or complete stage E2E is exercised.
 */
class org.flashNight.arki.unit.Action.Input.EnemyActionAssetTest {
    private static var passed:Number, failed:Number, ticks:Number, startedAt:Number;
    private static var finished:Boolean, loaded:Boolean;
    private static var world:MovieClip, library:MovieClip, driver:MovieClip;
    private static var loader:MovieClipLoader, listener:Object, cases:Array;

    public static function runAllTests():Void {
        passed = failed = ticks = 0;
        startedAt = getTimer(); finished = loaded = false; cases = [];
        world = _root.createEmptyMovieClip("__leeAssetWorld", _root.getNextHighestDepth());
        world._visible = false;
        library = world.createEmptyMovieClip("library", world.getNextHighestDepth());
        driver = _root.createEmptyMovieClip("__leeAssetDriver", _root.getNextHighestDepth());
        _root.gameworld = library;
        fixture();
        loader = new MovieClipLoader(); listener = {};
        listener.onLoadInit = function(mc:MovieClip):Void {
            try { EnemyActionAssetTest.loadedLibrary(mc); }
            catch (error:Object) { EnemyActionAssetTest.abort("load-init", error); }
        };
        listener.onLoadError = function(mc:MovieClip, error:String):Void {
            EnemyActionAssetTest.abort("asset-load", error);
        };
        loader.addListener(listener);
        loader.loadClip("../flashswf/arts/things4.swf", library);
        driver.onEnterFrame = function():Void {
            try {
                if (getTimer() - EnemyActionAssetTest.startedAt > 25000) {
                    EnemyActionAssetTest.abort("bounded-timeout", "25 seconds");
                } else if (EnemyActionAssetTest.loaded) EnemyActionAssetTest.tick();
            } catch (error:Object) { EnemyActionAssetTest.abort("tick", error); }
        };
        trace("EnemyActionAssetTest phase=load-requested");
    }

    private static function fixture():Void {
        _root.控制目标 = "__no_player"; _root.控制目标全自动 = false; _root.暂停 = false;
        _root.帧计时器 = {当前帧数:0}; _root.是否阴影 = false;
        _root.初始化思考标签 = function(mc:MovieClip):Void { mc._name = "思考标签"; mc.stop(); };
        _root.发布消息 = function():Void {};
        _root.效果 = function():Void {};
        _root.播放音效 = function():Void {};
        _root.add2map = function():Void {};
        _root.soundEffectManager = {playSound:function():Void {}};
        _root.敌人二级函数 = {};
        _root.敌人二级函数.攻击时移动 = function(speed:Number):Void {
            var direction:String = _parent.方向;
            if (speed < 0) { speed = -speed; direction = direction == "右" ? "左" : "右"; }
            _parent.移动(direction, speed);
        };
        _root.敌人二级函数.攻击时四向移动 = function(up:Number, down:Number, left:Number, right:Number):Void {
            if (up != 0) _parent.移动("上", up); else if (down != 0) _parent.移动("下", down);
            if (left != 0) { _parent.方向改变("左"); _parent.移动("左", left); }
            else if (right != 0) { _parent.方向改变("右"); _parent.移动("右", right); }
        };
        _root.子弹属性初始化 = function(area:MovieClip):Object {
            var owner:MovieClip = area;
            while (owner != undefined && owner.fixtureCase == undefined) owner = owner._parent;
            return {发射者:owner._name, shootX:owner._x, shootY:owner._y, shootZ:owner.Z轴坐标};
        };
        _root.子弹区域shoot传递 = function(properties:Object):Void { EnemyActionAssetTest.capture(properties); };
        _root.初始化敌人模板 = function():Void {
            this.hp = this.hp满血值 = 1000; this.空手攻击力 = 100;
            this.攻击模式 = "空手"; this.方向 = "右";
            this.行走X速度 = 3; this.行走Y速度 = 1.5;
            this.跑X速度 = 6; this.跑Y速度 = 3;
            this._x = 100; this._y = this.Z轴坐标 = 250;
            this.刚体 = false; this.锁定方向 = false;
            this.宠物属性 = {冲腿龙息:true};
            this.倒地 = this.浮空 = this.硬直中 = false;
            this.已加经验值 = false;
            this.攻击欲望 = this.fixtureCase.kind == "probe" ? 1 : 1000000;
            this.攻击目标 = this.fixtureCase.targetName == undefined ? "无" : this.fixtureCase.targetName;
            this.状态 = "空手站立";
            // Depth/rendering are outside this fixture; avoid native y-depth collisions.
            this.swapDepths = function():Void {};
            this.状态改变 = function(nextState:String):Void {
                if (this.状态 == nextState) return;
                this.状态 = nextState;
                this.gotoAndStop(nextState);
            };
            this.动画完毕 = function():Void {
                this.fixtureCase.completed++;
                this.状态改变(this.hp <= 0 ? "血腥死" : "空手站立");
            };
            this.行走 = function():Void {};
            this.方向改变 = function(direction:String):Void {
                if (this.锁定方向) return;
                this.方向 = direction; this._xscale = direction == "左" ? -100 : 100;
            };
            this.移动 = function(direction:String, amount:Number):Void {
                if (isNaN(amount)) { this.fixtureCase.invalidMoves++; return; }
                this.fixtureCase.moves++;
                if (direction == "右") this._x += amount;
                else if (direction == "左") this._x -= amount;
                else if (direction == "下") this._y = this.Z轴坐标 += amount;
                else if (direction == "上") this._y = this.Z轴坐标 -= amount;
            };
            this.死亡检测 = function():Void {
                if (_root.敌人动作.handleDeath(this)) return;
                this.fixtureCase.unhandledDeaths++;
                this.man.stop();
            };
            this.__enemyActionOnDeath = function(unit:Object):Boolean {
                if (!(unit.hp <= 0)) return false;
                if (!unit.fixtureCase.deathHandled) {
                    unit.fixtureCase.deathHandled = true;
                    unit.fixtureCase.deathCalls++;
                }
                return true;
            };
            EnemyActionRuntime.installLee(this);
            this.gotoAndStop("空手站立");
        };
        EnemyActionRuntime.installRootBridge(_root);
        // Observe actual native unload order without replacing cancellation behavior.
        _root.敌人动作.cancel = function(unit:Object, token:Object, reason:String):Void {
            var item:Object = unit.fixtureCase;
            var active:Object = EnemyActionRuntime.currentToken(unit);
            if (item.kind == "replace" && reason == "timeline-unload" && token === item.oldToken
                    && active != null && active !== token && active.actionId == "a1") item.nativeLateUnloads++;
            EnemyActionRuntime.cancel(unit, token, reason);
        };
    }

    private static function loadedLibrary(mc:MovieClip):Void {
        mc.stop();
        var children:Array = [];
        for (var key:String in mc) {
            var child:Object = mc[key];
            if (typeof(child) == "movieclip" && child._parent === mc) children.push(child);
        }
        for (var n:Number = 0; n < children.length; n++) {
            children[n].swapDepths(mc.getNextHighestDepth()); children[n].removeMovieClip();
        }
        var actions:Array = ["a1", "a2", "basic", "rush", "strongRush", "hop"];
        for (var i:Number = 0; i < actions.length; i++) {
            addCase("complete", actions[i], "player");
            addCase("complete", actions[i], "ai");
        }
        addCase("hit", "strongRush", "player");
        addCase("death", "strongRush", "player");
        addCase("replace", "basic", "player");
        addCase("probe", "", "ai");
        addCase("knockdown", "strongRush", "player");
        addCase("knockdown", "strongRush", "ai");
        addCase("repeat-hit", "a2", "player");
        addCase("repeat-hit", "a2", "ai");
        addCase("hit-hop", "a1", "player");
        addCase("hop-hit-cooldown", "hop", "player");
        addCase("awakened-hit", "a1", "player");
        addCase("awakened-hop-cooldown", "hop", "player");
        addCase("turn-a1", "a1", "player");
        addCase("slot-a2", "a2", "player");
        addCase("turn-rush", "rush", "player");
        addCase("turn-strongRush", "strongRush", "player");
        addCase("turn-a2", "a2", "player");
        addCase("turn-basic", "basic", "player");
        addCase("chain-rush", "a1", "player");
        addCase("chain-strongRush", "rush", "player");
        addCase("chain-a2", "strongRush", "player");
        loaded = true;
        trace("EnemyActionAssetTest phase=spawned count=" + cases.length);
    }

    private static function addCase(kind:String, action:String, source:String):Void {
        var item:Object = {id:"leeCase" + cases.length, kind:kind, action:action, source:source,
            hits:0, staleHits:0, invalidMoves:0, moves:0, completed:0, hitTicks:{}, hitFrames:{},
            deathCalls:0, unhandledDeaths:0, nativeLateUnloads:0, damage:0, hitDirections:{}, hurtSamples:0, hurtViolations:0};
        if (kind == "probe" || kind == "turn-strongRush") {
            var target:MovieClip = library.createEmptyMovieClip(item.id + "Target", library.getNextHighestDepth());
            target.hp = 1000; target.是否为敌人 = true; target._x = 150; target._y = target.Z轴坐标 = 250;
            var area:MovieClip = target.createEmptyMovieClip("area", 1);
            area.beginFill(0, 0); area.moveTo(-600, -300); area.lineTo(600, -300);
            area.lineTo(600, 100); area.lineTo(-600, 100); area.lineTo(-600, -300); area.endFill();
            item.targetName = target._name;
        }
        cases.push(item);
        item.unit = library.attachMovie("敌人-李小龙", item.id, library.getNextHighestDepth(),
            {fixtureCase:item, 兵种:"敌人-李小龙", 是否为敌人:false,
             __enemyActionPlayer:source == "player", 宠物属性:{冲腿龙息:true}});
        check(item.unit != undefined, item.id + " published linkage attaches");
    }

    private static function capture(properties:Object):Void {
        var unit:MovieClip = library[properties.发射者];
        var item:Object = unit.fixtureCase;
        if (item == undefined) { check(false, "damage without fixture owner"); return; }
        item.hits++; item.damage += properties.子弹威力;
        item.hitDirections[unit.方向] = true;
        if (item.kind.substr(0,6) == "chain-" && item.chainStarted && unit.man.__enemyActionToken !== item.token) item.staleHits++;
        item.hitTicks[String(ticks)] = true;
        item.hitFrames[String(unit.man._currentframe)] = true;
        if (!EnemyActionRuntime.isCurrent(unit, EnemyActionRuntime.currentToken(unit))) item.staleHits++;
        if (item.interrupted && item.kind != "replace") item.staleHits++;
    }

    private static function tick():Void {
        ticks++; _root.帧计时器.当前帧数 = ticks;
        for (var i:Number = 0; i < cases.length; i++) {
            var item:Object = cases[i]; var unit:MovieClip = item.unit;
            if (ticks == 3 && item.kind != "probe") {
                _root.控制目标 = item.source == "player" ? unit._name : "__no_player";
                if (item.kind == "turn-a1" || item.kind == "slot-a2") {
                    EnemyActionInputService.updateSample(unit,0,true);
                    EnemyActionInputService.updateSample(unit,item.kind == "turn-a1" ? 16 : 8192,true);
                    item.token = EnemyActionRuntime.currentToken(unit);
                    check(!EnemyActionRuntime.isRunning(unit), item.id + " skill/attack starts while stationary");
                } else item.token = EnemyActionRuntime.request(unit, item.action, item.source, null);
                check(item.token != null, item.id + " " + item.source + " requests " + item.action);
            }
            if (item.kind.substr(0,5) == "turn-" && item.expectedFacing != undefined
                    && EnemyActionRuntime.isCurrent(unit,item.token)) {
                check(unit.方向 == item.expectedFacing,item.id + " facing survives native movement/phase transitions at " + ticks);
            }
            if (item.kind.substr(0,5) == "turn-" && (ticks == 8 || ticks == 18 || ticks == 34 || ticks == 60 || ticks == 78)
                    && EnemyActionRuntime.isCurrent(unit,item.token)) {
                var nativeFrame:Number = unit.man._currentframe;
                var deadline:Number = unit.__enemyActionRuntime.cooldowns[item.action];
                var right:Boolean = ticks == 18 || ticks == 60;
                EnemyActionInputService.updateSample(unit,0,true);
                EnemyActionInputService.updateSample(unit,right ? 3 : 1,true);
                item.expectedFacing = right ? "右" : "左";
                item.turns = Number(item.turns || 0) + 1;
                check(unit.方向 == item.expectedFacing
                    && (right ? unit._xscale > 0 : unit._xscale < 0)
                    && unit.man._currentframe == nativeFrame
                    && EnemyActionRuntime.currentToken(unit) === item.token
                    && unit.__enemyActionRuntime.cooldowns[item.action] == deadline,
                    item.id + " native attack turns without rewinding its frame/token/cooldown at " + ticks);
            }
            if (ticks == 7 && item.kind.substr(0,6) == "chain-") {
                item.oldToken = item.token;
                item.sourceDeadline = unit.__enemyActionRuntime.cooldowns[item.action];
                _root.控制目标 = unit._name; unit.左行 = true; unit.右行 = false;
                item.token = EnemyActionRuntime.request(unit,item.kind.substr(6),"player",null);
                item.chainStarted = true;
                check(item.token != null && !item.oldToken.active,
                    item.id + " explicit same-state skill cancellation commits a replacement token");
            }
            if (ticks == 9 && item.kind.substr(0,6) == "chain-") {
                check(unit.man.__enemyActionToken === item.token && EnemyActionRuntime.isCurrent(unit,item.token),
                    item.id + " replacement actually reconstructs its native timeline with the new token");
            }
            if (item.kind == "probe" && item.token == undefined) {
                var probed:Object = EnemyActionRuntime.currentToken(unit);
                if (probed != null) { item.token = probed; unit.攻击目标 = "无"; }
            }
            if (ticks == 7 && item.source == "player" && (item.kind == "hit" || item.kind == "knockdown"
                || item.kind == "repeat-hit" || item.kind == "hit-hop" || item.kind == "hop-hit-cooldown")) {
                unit.宠物属性.冲腿龙息 = false;
            }
            if (ticks == 7 && (item.kind == "awakened-hit" || item.kind == "awakened-hop-cooldown")) {
                item.oldToken = item.token; item.movesAtHit = item.moves;
                item.hopDeadline = unit.__enemyActionRuntime.cooldowns.hop;
                unit.状态改变("被击");
                check(!item.oldToken.active && !unit.刚体, item.id + " awakened hit cancels owned attack flags");
            }
            if (ticks == 11 && item.kind == "awakened-hop-cooldown") {
                _root.控制目标 = unit._name;
                check(EnemyActionRuntime.request(unit,"hop","player",null) == null,
                    item.id + " reflex does not reopen the manual hop cooldown");
            }
            if (ticks == 7 && item.kind == "hit") {
                item.interrupted = true; unit.状态改变("被击");
                check(!item.token.active && !unit.刚体, item.id + " native hit interrupts and clears owned flags");
            }
            if (ticks == 7 && (item.kind == "knockdown" || item.kind == "repeat-hit")) {
                item.interrupted = true;
                item.movesAtHit = item.moves;
                unit.状态改变(item.kind == "knockdown" ? "击倒" : "被击");
                check(!item.token.active && unit.状态 == "被击", item.id + " hit enters native reaction state");
            }
            if (ticks == 11 && item.kind == "repeat-hit") unit.状态改变("被击");
            if (ticks == 7 && (item.kind == "hit-hop" || item.kind == "hop-hit-cooldown")) {
                item.oldToken = item.token;
                unit.状态改变("被击");
                item.movesAtHit = item.moves;
                check(!item.oldToken.active && !unit.刚体, item.id + " native hit revokes the old action");
            }
            if (ticks == 11 && item.kind == "hit-hop") {
                _root.控制目标 = unit._name; unit.右行 = true;
                item.token = EnemyActionRuntime.request(unit,"hop","player",null);
                check(item.token != null && item.token.actionId == "hop" && unit.状态 == "小跳",
                    item.id + " player must actively request a ready hop to escape hitstun");
            }
            if (ticks == 11 && item.kind == "hop-hit-cooldown") {
                _root.控制目标 = unit._name;
                check(EnemyActionRuntime.request(unit,"hop","player",null) == null && unit.状态 == "被击",
                    item.id + " native hit does not reset the manual hop cooldown");
            }
            if (ticks == 7 && item.kind == "death") {
                item.interrupted = true; unit.hp = 0; unit.状态改变("血腥死");
                check(!item.token.active && !unit.刚体, item.id + " native death revokes action");
            }
            if (ticks == 7 && item.kind == "replace") {
                item.oldToken = item.token;
                EnemyActionRuntime.cancel(unit, item.oldToken, "fixture-replace");
                // Deliberately retain old man while publishing a new action token,
                // exercising real onUnload against newer ownership during goto.
                unit.状态 = "空手站立";
                _root.控制目标 = unit._name;
                item.token = EnemyActionRuntime.request(unit, "a1", "player", null);
                check(item.token != null && item.token !== item.oldToken, item.id + " replacement action accepted");
            }
            if (ticks == 9 && item.kind == "replace") {
                check(EnemyActionRuntime.isCurrent(unit, item.token), item.id + " native old unload preserves new token");
            }
            if (ticks >= 9 && unit.状态 == "被击") observeHurtPose(unit,item);
        }
        _root.控制目标 = "__no_player";
        if (ticks >= 160) finish();
    }

    /** World coordinates alone cannot detect a passive hop hidden inside the body timeline. */
    private static function observeHurtPose(unit:MovieClip, item:Object):Void {
        var bounds:Object = unit.man.getBounds(unit);
        if (item.hurtSamples == 0) {
            item.hurtBounds = bounds;
            item.hurtX = unit._x; item.hurtY = unit._y; item.hurtZ = unit.Z轴坐标;
            item.hurtHopDeadline = unit.__enemyActionRuntime.cooldowns.hop;
        }
        item.hurtSamples++;
        if (item.source == "player" && !EnemyActionRuntime.usesHitHop(unit)) {
            if (unit.man.__leePlayerHit !== true || unit.man._currentframe < 26
                || unit.man._currentframe > 41 || EnemyActionRuntime.currentToken(unit) != null
                || Math.abs(bounds.yMin-item.hurtBounds.yMin) > 0.05
                || Math.abs(bounds.yMax-item.hurtBounds.yMax) > 0.05
                || unit._x != item.hurtX || unit._y != item.hurtY || unit.Z轴坐标 != item.hurtZ
                || unit.__enemyActionRuntime.cooldowns.hop !== item.hurtHopDeadline) item.hurtViolations++;
        } else if (unit.man.__leePlayerHit === true || unit.man._currentframe > 16) item.hurtViolations++;
    }

    private static function countKeys(value:Object):Number {
        var count:Number = 0;
        for (var key:String in value) count++;
        return count;
    }

    private static function finish():Void {
        if (finished) return;
        finished = true; delete driver.onEnterFrame;
        for (var i:Number = 0; i < cases.length; i++) {
            var item:Object = cases[i]; var unit:MovieClip = item.unit;
            check(item.staleHits == 0 && item.invalidMoves == 0, item.id + " no stale damage or invalid movement");
            if (item.kind == "hit" || item.kind == "knockdown" || item.kind == "repeat-hit"
                || item.kind == "hit-hop" || item.kind == "hop-hit-cooldown") {
                check(item.hurtSamples > 0 && item.hurtViolations == 0
                    && (item.source != "player" || item.kind == "hit-hop" || item.hurtSamples >= 12),
                    item.id + " player stays grounded without a hop token/deadline; AI retains native hit escape");
            }
            if (item.kind == "complete") {
                check(item.completed == 1 && unit.状态 == "空手站立" && !item.token.active,
                    item.id + " actual " + item.action + " finishes exactly once");
                check((item.action == "hop" ? item.hits == 0 && item.moves > 0 : item.hits > 0)
                    && !unit.刚体 && !unit.锁定方向, item.id + " native effects and owned-state cleanup occur");
                if (item.action == "basic") check(item.hits == 4 && countKeys(item.hitTicks) == 1
                    && countKeys(item.hitFrames) == 1 && item.hitFrames["3"] === true,
                    item.id + " four independent hits share native frame three");
            } else if (item.kind == "turn-a1") {
                check(item.completed == 1 && !item.token.active && unit.状态 == "空手站立"
                    && item.hitDirections.左 === true && item.hitDirections.右 === true,
                    item.id + " same native attack damages in both chosen directions and finishes once");
            } else if (item.kind.substr(0,5) == "turn-") {
                check(item.turns >= 2 && item.completed == 1 && !item.token.active && item.hits > 0
                    && unit.状态 == "空手站立" && !unit.锁定方向,
                    item.id + " actual player skill steers through its phases, damages and returns ready");
            } else if (item.kind.substr(0,6) == "chain-") {
                check(item.token != null && item.completed == 1 && !item.token.active && item.hits > 0
                    && !item.oldToken.active && unit.状态 == "空手站立" && !unit.刚体 && !unit.锁定方向
                    && unit.__enemyActionRuntime.cooldowns[item.action] == item.sourceDeadline,
                    item.id + " real replacement plays to completion without stale damage or refunded cooldown");
            } else if (item.kind == "slot-a2") {
                check(item.token.actionId == "a2" && item.completed == 1 && item.hits > 0
                    && !item.token.active && !unit.锁定方向 && unit.状态 == "空手站立",
                    item.id + " stationary combo skill plays and cleans up the real native timeline");
            } else if (item.kind == "hit") {
                check(item.hits == 0 && unit.状态 == "空手站立", item.id + " old attack never damages after native hit");
            } else if (item.kind == "knockdown" || item.kind == "repeat-hit") {
                check(unit.状态 == "空手站立" && !unit.刚体 && !item.token.active
                    && (item.source == "player" ? item.moves == item.movesAtHit : item.moves > item.movesAtHit),
                    item.id + " only AI retains passive hit movement and both restore readiness");
            } else if (item.kind == "awakened-hit" || item.kind == "awakened-hop-cooldown") {
                check(item.hurtSamples > 0 && item.hurtViolations == 0 && item.moves > item.movesAtHit
                    && unit.__enemyActionRuntime.cooldowns.hop === item.hopDeadline
                    && unit.状态 == "空手站立" && item.completed == 1 && !item.oldToken.active && !unit.刚体,
                    item.id + " actual awakened reaction hops despite cooldown and returns ready without changing it");
            } else if (item.kind == "hit-hop") {
                check(item.moves > item.movesAtHit && item.completed == 1
                    && !item.token.active && unit.状态 == "空手站立" && !unit.刚体,
                    item.id + " only the admitted manual hop moves the player after a hit");
            } else if (item.kind == "hop-hit-cooldown") {
                check(item.moves == item.movesAtHit && item.completed == 1 && unit.状态 == "空手站立"
                    && !item.token.active && !unit.刚体,
                    item.id + " interrupted hop cannot gain free passive displacement while on cooldown");
            } else if (item.kind == "death") {
                check(item.hits == 0 && item.deathCalls == 1 && item.unhandledDeaths == 0
                    && unit._parent === library && unit.状态 == "血腥死",
                    item.id + " native death keeps controlled corpse and notifies once");
            } else if (item.kind == "replace") {
                check(item.nativeLateUnloads == 1 && item.completed == 1 && item.hits > 0
                    && unit.状态 == "空手站立" && !item.token.active && !item.oldToken.active,
                    item.id + " actual old container unload cannot cancel replacement action");
            } else if (item.kind == "probe") {
                check(item.token != null && item.token.source == "ai" && item.completed == 1
                    && item.hits > 0 && unit.状态 == "空手站立", item.id + " real AI probe enters shared request then completes");
            }
        }
        complete();
    }

    private static function check(ok:Boolean, label:String):Void {
        if (ok) passed++;
        else { failed++; trace("[TEST_FAIL] EnemyActionAssetTest: " + label); }
    }

    private static function abort(phase:String, error:Object):Void {
        if (finished) return;
        finished = true; delete driver.onEnterFrame;
        failed++; trace("[TEST_FAIL] EnemyActionAssetTest: " + phase + " " + error);
        complete();
    }

    private static function complete():Void {
        trace("EnemyActionAssetTest: " + passed + " passed, " + failed + " failed; "
            + cases.length + " actual timeline cases; elapsed-ms=" + (getTimer() - startedAt));
        loader.removeListener(listener); loader.unloadClip(library); world.removeMovieClip(); driver.removeMovieClip();
        _root.leeActionAssetComplete();
    }
}
