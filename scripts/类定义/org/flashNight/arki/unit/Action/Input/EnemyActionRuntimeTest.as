import org.flashNight.arki.unit.Action.Input.EnemyActionRuntime;
import org.flashNight.arki.unit.Action.Input.EnemyActionInputService;

/** 定向逻辑夹具；真实 XFL 帧时序和同路径 MovieClip 重建仍须候选实测。 */
class org.flashNight.arki.unit.Action.Input.EnemyActionRuntimeTest {
    private static var passed:Number;
    private static var failed:Number;

    public static function runAllTests():Void {
        passed = failed = 0;
        var saved:Object = {world:_root.gameworld, control:_root.控制目标,
            fullAuto:_root.控制目标全自动, paused:_root.暂停, timer:_root.帧计时器};
        _root.gameworld = {};
        _root.帧计时器 = {当前帧数:10};
        _root.暂停 = false;
        _root.控制目标全自动 = false;
        trace("--- EnemyActionRuntimeTest ---");
        try {
            testSharedEntryAndAuthority();
            testOwnedFlagsAndLateCallbacks();
            testTargetIdentityAndFallback();
            testInputHoldEdgesAndPause();
            testOpposedDirectionTransitions();
            testControlLossReturnsReady();
            testDeathAndRelease();
            testNativeAbilitiesAndHud();
            testAwakenedHitHop();
            testPlayerControlsAndCooldowns();
            testPlayerFacingAndDirectSkills();
            testPlayerSceneClock();
            testPlayerCancelChains();
        } catch (error:Error) {
            failed++;
            trace("FAIL unexpected: " + error);
        } finally {
            _root.gameworld = saved.world;
            _root.控制目标 = saved.control;
            _root.控制目标全自动 = saved.fullAuto;
            _root.暂停 = saved.paused;
            _root.帧计时器 = saved.timer;
        }
        trace("--- EnemyActionRuntimeTest: " + passed + "/" + (passed + failed)
            + " passed, " + failed + " failed ---");
    }

    private static function unit(name:String, player:Boolean, session:Object):Object {
        var actor:Object = {_name:name, _parent:_root.gameworld, hp:100,
            _x:100, Z轴坐标:100, 是否为敌人:false, 状态:"空手站立", calls:0, 方向:"右", 宠物属性:{冲腿龙息:true}};
        actor.状态改变 = function(nextState:String):Void { this.状态 = nextState; this.calls++; };
        actor.方向改变 = function(direction:String):Void { this.方向 = direction; };
        _root.gameworld[name] = actor;
        actor.__enemyActionPlayer = player === true;
        actor.__enemyActionCooldownSession = session;
        EnemyActionRuntime.installLee(actor);
        return actor;
    }

    private static function idle(actor:Object):Void {
        EnemyActionRuntime.finish(actor, EnemyActionRuntime.currentToken(actor));
        actor.状态改变("空手站立");
    }

    private static function testSharedEntryAndAuthority():Void {
        _root.控制目标 = "playerLee";
        var player:Object = unit("playerLee");
        var ai:Object = unit("aiLee");
        var playerToken:Object = EnemyActionRuntime.request(player,"a2","player",null);
        var aiToken:Object = EnemyActionRuntime.request(ai,"a2","ai",null);
        assert(playerToken != null && aiToken != null && player.近战招式 == ai.近战招式
            && player.状态 == ai.状态, "player and AI share the same action/state execution");
        assert(EnemyActionRuntime.request(player,"a1","player",null) == null
            && EnemyActionRuntime.currentToken(player) === playerToken, "busy action rejects a second request");
        idle(player);
        assert(EnemyActionRuntime.request(player,"a1","ai",null) == null,
            "AI cannot command the controlled actor");
        assert(EnemyActionRuntime.request(ai,"a1","player",null) == null,
            "player cannot command an unowned actor");
        idle(ai);
        ai.近战招式 = "冲腿";
        ai.状态改变("近战");
        assert(EnemyActionRuntime.currentToken(ai).actionId == "rush",
            "legacy attack state bridge enters the shared request");
        player.状态改变("空手攻击");
        assert(EnemyActionRuntime.currentToken(player) == null,
            "legacy AI state bridge cannot bypass player authority");
        player.状态改变("倒地");
        assert(EnemyActionRuntime.request(player,"a2","player",null) == null,
            "non-ready stance rejects action");
    }

    private static function testOwnedFlagsAndLateCallbacks():Void {
        _root.控制目标 = "flagsLee";
        var actor:Object = unit("flagsLee");
        actor.刚体 = false;
        var first:Object = EnemyActionRuntime.request(actor,"a2","player",null);
        EnemyActionRuntime.setOwnedFlag(actor,first,"刚体",true);
        EnemyActionRuntime.setOwnedFlag(actor,first,"锁定方向",true);
        actor.状态改变("被击");
        assert(!first.active && actor.刚体 === false && actor.锁定方向 == undefined,
            "interruption restores owned flags before changing state");
        actor.状态改变("空手站立");
        var second:Object = EnemyActionRuntime.request(actor,"a1","player",null);
        EnemyActionRuntime.setOwnedFlag(actor,second,"刚体",true);
        EnemyActionRuntime.cancel(actor,first,"lateUnload");
        EnemyActionRuntime.setOwnedFlag(actor,first,"锁定方向",true);
        assert(EnemyActionRuntime.isCurrent(actor,second) && actor.刚体 === true
            && actor.锁定方向 == undefined, "late token cannot cancel or mutate a newer action");
        actor.刚体 = "externalOwner";
        EnemyActionRuntime.finish(actor,second);
        assert(actor.刚体 == "externalOwner", "cleanup preserves an externally overwritten flag");
        var oldIdentity:Object = actor.__enemyActionRuntime.identity;
        EnemyActionRuntime.releaseUnit(actor,"sceneExit");
        EnemyActionRuntime.installLee(actor);
        assert(actor.__enemyActionRuntime.identity !== oldIdentity
            && !EnemyActionRuntime.isCurrent(actor,second), "new unit runtime rejects old independent identity");
    }

    private static function testTargetIdentityAndFallback():Void {
        _root.控制目标 = "targetLee";
        var actor:Object = unit("targetLee");
        var enemy:Object = {_name:"target", _parent:_root.gameworld,
            hp:100, 是否为敌人:true, _x:180, Z轴坐标:100};
        _root.gameworld.target = enemy;
        actor.攻击目标 = "target";
        var token:Object = EnemyActionRuntime.request(actor,"basic","player",null);
        assert(EnemyActionRuntime.resolveTarget(actor,token) === enemy,
            "request captures a live hostile target");
        assert(EnemyActionRuntime.getParameter(actor,token,"maxTravel") == 300,
            "tracking bounds read the one profile authority");
        enemy.__enemyActionTargetIdentity = {};
        assert(EnemyActionRuntime.resolveTarget(actor,token) == null,
            "same-path target with replaced identity falls back instead of retargeting");
        idle(actor);
        enemy.hp = 0;
        token = EnemyActionRuntime.request(actor,"basic","player",null);
        assert(token != null && EnemyActionRuntime.resolveTarget(actor,token) == null,
            "no live target still permits the direction-based action fallback");
        idle(actor);
        assert(isNaN(EnemyActionRuntime.getParameter(actor,token,"maxTravel")),
            "stale action cannot read execution parameters");
    }

    private static function testInputHoldEdgesAndPause():Void {
        _root.控制目标 = "inputLee";
        var actor:Object = unit("inputLee");
        EnemyActionInputService.updateSample(actor,16,true);
        assert(EnemyActionRuntime.currentToken(actor) == null, "entry-held key requires release");
        EnemyActionInputService.updateSample(actor,0,true);
        EnemyActionInputService.updateSample(actor,17,true);
        var first:Object = EnemyActionRuntime.currentToken(actor);
        assert(first.actionId == "a2" && actor.方向 == "左", "A hold starts controllable a2 with current direction");
        EnemyActionInputService.updateSample(actor,16,true);
        assert(EnemyActionRuntime.currentToken(actor) === first, "held primary cannot duplicate a busy action");
        idle(actor);
        EnemyActionInputService.updateSample(actor,16,true);
        assert(EnemyActionRuntime.currentToken(actor) !== first, "held primary repeats only when ready");
        EnemyActionInputService.updateSample(actor,32,true);
        idle(actor);
        EnemyActionInputService.updateSample(actor,32,true);
        assert(EnemyActionRuntime.currentToken(actor) == null, "busy special edge is consumed without buffering");
        EnemyActionInputService.updateSample(actor,0,true);
        EnemyActionInputService.updateSample(actor,32,true);
        var special:Object = EnemyActionRuntime.currentToken(actor);
        assert(special.actionId == "a1", "released special rearms on its next edge");
        EnemyActionInputService.updateSample(actor,32,false);
        assert(EnemyActionRuntime.isCurrent(actor,special) && !actor.左行,
            "pause clears input and preserves the current animation action");
        idle(actor);
        EnemyActionInputService.updateSample(actor,32,true);
        assert(EnemyActionRuntime.currentToken(actor) == null, "resume-held special cannot fire");
        EnemyActionInputService.updateSample(actor,0,true);
        EnemyActionInputService.updateSample(actor,2048,true);
        assert(EnemyActionRuntime.currentToken(actor).actionId == "strongRush",
            "second actor shortcut maps to the existing strong rush");
    }

    private static function testOpposedDirectionTransitions():Void {
        // Both press orders and either release order must leave one movement
        // direction whose facing agrees before the native timeline consumes it.
        for (var running:Number = 0; running < 2; running++) {
            var name:String = "opposedLee" + running;
            _root.控制目标 = name;
            var actor:Object = unit(name);
            var runBit:Number = running == 1 ? 128 : 0;
            EnemyActionInputService.updateSample(actor,0,true);
            EnemyActionInputService.updateSample(actor,runBit | 1,true);
            assert(actor.左行 && !actor.右行 && actor.方向 == "左",
                "left movement starts facing left, running=" + running);
            EnemyActionInputService.updateSample(actor,runBit | 3,true);
            assert(actor.右行 && !actor.左行 && actor.方向 == "右",
                "adding right agrees with native right-priority movement, running=" + running);
            EnemyActionInputService.updateSample(actor,runBit | 2,true);
            assert(actor.右行 && !actor.左行 && actor.方向 == "右",
                "releasing left keeps right movement and facing, running=" + running);
            EnemyActionInputService.updateSample(actor,runBit | 3,true);
            assert(actor.右行 && !actor.左行 && actor.方向 == "右",
                "adding left cannot flip facing against right movement, running=" + running);
            EnemyActionInputService.updateSample(actor,runBit | 1,true);
            assert(actor.左行 && !actor.右行 && actor.方向 == "左",
                "releasing right immediately restores left movement and facing, running=" + running);
            EnemyActionInputService.updateSample(actor,runBit,true);
            assert(!actor.左行 && !actor.右行 && actor.方向 == "左",
                "releasing both clears movement without a phantom turn, running=" + running);
            EnemyActionInputService.updateSample(actor,runBit | 12,true);
            assert(actor.下行 && !actor.上行,
                "opposed vertical input agrees with native down-priority movement, running=" + running);
            EnemyActionInputService.updateSample(actor,runBit | 4,true);
            assert(actor.上行 && !actor.下行,
                "releasing down immediately restores up movement, running=" + running);
            EnemyActionInputService.updateSample(actor,runBit | 15 | 256,true);
            var hop:Object = EnemyActionRuntime.currentToken(actor);
            assert(hop.actionId == "hop" && hop.hopX == 1 && hop.hopZ == 1
                && actor.方向 == "右", "hop uses the same resolved directions, running=" + running);
            idle(actor);
        }
    }

    private static function testControlLossReturnsReady():Void {
        _root.控制目标 = "handoffLee";
        var actor:Object = unit("handoffLee");
        var token:Object = EnemyActionRuntime.request(actor,"a2","player",null);
        EnemyActionRuntime.setOwnedFlag(actor,token,"刚体",true);
        _root.控制目标 = "anotherActor";
        EnemyActionRuntime.abortToReady(actor,token,"controlLost");
        assert(actor.状态 == "空手站立" && actor.__enemyActionRuntime.active == null
            && actor.刚体 != true, "control loss cancels and exits the old live action container");
        var next:Object = EnemyActionRuntime.request(actor,"a1","ai",null);
        assert(next != null && next.source == "ai", "AI can request an action after control loss");
        EnemyActionRuntime.abortToReady(actor,token,"lateControlLost");
        assert(actor.状态 == "近战" && EnemyActionRuntime.isCurrent(actor,next),
            "late control loss cannot reset the replacement action");
        actor.状态 = "被击";
        EnemyActionRuntime.abortToReady(actor,next,"controlLost");
        assert(actor.状态 == "被击", "control loss never overwrites a newer hit or death state");
    }

    private static function testDeathAndRelease():Void {
        _root.控制目标 = "deathLee";
        var actor:Object = unit("deathLee");
        var token:Object = EnemyActionRuntime.request(actor,"a2","player",null);
        EnemyActionRuntime.setOwnedFlag(actor,token,"刚体",true);
        actor.__enemyActionOnDeath = function(target:Object):Boolean {
            this.deathSawClean = !target.__enemyActionRuntime.active && target.刚体 != true;
            return true;
        };
        assert(!EnemyActionRuntime.handleDeath(actor) && EnemyActionRuntime.isCurrent(actor,token)
            && actor.刚体 === true, "live managed unit death polling has zero side effects");
        actor.hp = NaN;
        assert(!EnemyActionRuntime.handleDeath(actor) && token.active === true,
            "unknown hp is not promoted to confirmed death");
        var ordinary:Object = {hp:0, 左行:true};
        assert(!EnemyActionRuntime.handleDeath(ordinary) && ordinary.左行 === true,
            "ordinary enemy death polling does not enter managed cleanup");
        actor.hp = 0;
        assert(EnemyActionRuntime.handleDeath(actor) && actor.deathSawClean,
            "death callback observes canceled action and restored flags");
        assert(!EnemyActionRuntime.isCurrent(actor,token), "death revokes old frame side effects");
        var original:Function = actor.__enemyActionRuntime.originalStateChange;
        EnemyActionRuntime.releaseUnit(actor,"sceneExit");
        assert(actor.__enemyActionRuntime == undefined && actor.状态改变 === original,
            "release restores the state entry without rebuilding the unit");
        EnemyActionRuntime.cancel(actor,token,"lateUnload");
        assert(actor.__enemyActionRuntime == undefined, "late unload after release is harmless");
    }

    private static function testNativeAbilitiesAndHud():Void {
        _root.控制目标 = "nativeLee";
        var actor:Object = unit("nativeLee");
        var attack:Object = EnemyActionRuntime.request(actor,"a2","player",null);
        actor.状态改变("击倒");
        assert(!attack.active && actor.状态 == "被击", "unsupported knockdown uses Lee's real escape timeline");
        actor.状态改变("空手站立");
        actor.左行 = true;
        var hop:Object = EnemyActionRuntime.request(actor,"hop","player",null);
        assert(hop != null && hop.hopX == -1 && actor.状态 == "小跳", "hop is a native direction-aware ability");
        var moves:Number = 0;
        actor.移动 = function(direction:String, amount:Number):Void { this.movedDirection=direction; this.movedAmount=amount; };
        EnemyActionRuntime.moveHop(actor,hop);
        assert(actor.movedDirection == "左" && actor.movedAmount == 20, "native hop honors held direction");
        idle(actor);
        assert(EnemyActionRuntime.request(actor,"hop","player",null) == null, "hop cooldown belongs to the real ability");
        var hud:Object = EnemyActionRuntime.hudDescriptors(actor);
        assert(hud.slots.length == 12 && hud.slots[0].skillKey == "小跳" && hud.slots[1].skillKey == "寸拳",
            "native loadout projects named hop and punch without learned main-character skills");
        assert(hud.slots[2].equipped && hud.slots[3].skillKey == "强力冲腿" && hud.slots[0].writeBlocked,
            "promoted abilities are visible and fixed loadout forbids management writes");
        var cooldowns:Array = EnemyActionRuntime.hudCooldowns(actor);
        assert(cooldowns.length == 18 && cooldowns[1][0] === 0, "native HUD consumes unit cooldown authority");
        assert(EnemyActionRuntime.hudDescriptors(actor) === hud, "unchanged native descriptors retain their display snapshot");
        actor.宠物属性.冲腿龙息 = false;
        assert(EnemyActionRuntime.request(actor,"strongRush","player",null) == null,
            "unpromoted unit cannot bypass capability admission");
        var plain:Object = EnemyActionRuntime.hudDescriptors(actor);
        assert(plain.revision > hud.revision && !plain.slots[3].equipped && hud.slots[3].equipped,
            "promotion change invalidates display without mutating old snapshots");
        _root.控制目标 = "otherLee";
        var other:Object = unit("otherLee");
        assert(EnemyActionRuntime.request(other,"hop","player",null) != null, "two units never share a slot cooldown");
        idle(other);
        other.浮空 = true;
        assert(EnemyActionRuntime.request(other,"hop","player",null) == null, "hop cannot escape the airborne admission boundary");
        other.浮空 = false;
        _root.帧计时器.当前帧数 += 31;
        var busy:Object = EnemyActionRuntime.request(other,"a1","player",null);
        var escaped:Object = EnemyActionRuntime.request(other,"hop","player",null);
        assert(escaped != null && !busy.active, "manual hop can cancel the unit's own attack through shared lifecycle");
        idle(other);
        _root.控制目标 = "nativeLee";
        actor.hp = 0;
        assert(EnemyActionRuntime.request(actor,"hop","player",null) == null, "dead actors cannot cast a mobility ability");
    }

    private static function testAwakenedHitHop():Void {
        _root.控制目标 = "hitHopPolicy";
        var actor:Object = unit("hitHopPolicy",true,null);
        actor.宠物属性.冲腿龙息 = false;
        actor.状态 = "被击"; actor.moves = 0;
        actor.移动 = function(direction:String, amount:Number):Void { this.moves++; this.amount=amount; };
        EnemyActionRuntime.moveHitHop(actor,"上");
        assert(!EnemyActionRuntime.usesHitHop(actor) && actor.moves == 0,"ordinary player retains grounded hit reaction");
        actor.宠物属性.冲腿龙息 = true;
        actor.__enemyActionRuntime.cooldowns.hop = 999999;
        EnemyActionRuntime.moveHitHop(actor,"下");
        assert(EnemyActionRuntime.usesHitHop(actor) && actor.moves == 1 && actor.amount == 20
            && actor.__enemyActionRuntime.cooldowns.hop == 999999 && EnemyActionRuntime.currentToken(actor) == null,
            "awakened reflex moves even during manual hop cooldown without spending or refunding it");
        actor.hp = 0; EnemyActionRuntime.moveHitHop(actor,"上");
        assert(actor.moves == 1,"dead awakened player cannot receive passive displacement");
        actor.hp = 100; actor.状态 = "空手站立"; EnemyActionRuntime.moveHitHop(actor,"上");
        assert(actor.moves == 1,"reflex never moves a player outside native hit frames");
        actor.__enemyActionPlayer = false; actor.宠物属性.冲腿龙息 = false; actor.状态 = "被击";
        EnemyActionRuntime.moveHitHop(actor,"上");
        assert(EnemyActionRuntime.usesHitHop(actor) && actor.moves == 2,"AI keeps its original hit escape without promotion");
    }

    private static function testPlayerControlsAndCooldowns():Void {
        _root.控制目标 = "cdPlayer";
        var actor:Object = unit("cdPlayer", true, null);
        var profile:Object = actor.__enemyActionRuntime.profile;
        assert(profile.actions.a1.cooldownFrames == 48 && profile.actions.a2.cooldownFrames == 105
            && profile.actions.basic.cooldownFrames == 141 && profile.actions.hop.cooldownFrames == 75
            && profile.actions.rush.cooldownFrames == 180 && profile.actions.strongRush.cooldownFrames == 270,
            "only player profile receives the six first-trial cooldown values");
        EnemyActionInputService.updateSample(actor,16,true);
        assert(EnemyActionRuntime.currentToken(actor) == null, "new player mapping still requires entry key release");
        EnemyActionInputService.updateSample(actor,0,true);
        EnemyActionInputService.updateSample(actor,16,true);
        var attack:Object = EnemyActionRuntime.currentToken(actor);
        var start:Number = _root.帧计时器.当前帧数;
        assert(attack.actionId == "a1" && actor.近战招式 == "a1",
            "ordinary J now requests the original interception timeline");
        idle(actor);
        _root.帧计时器.当前帧数 = start + 47;
        EnemyActionInputService.updateSample(actor,16,true);
        assert(EnemyActionRuntime.currentToken(actor) == null, "held J cannot beat the interception cooldown");
        EnemyActionInputService.updateSample(actor,4096,true);
        assert(EnemyActionRuntime.currentToken(actor) == null, "P cannot bypass the cooldown started by ordinary J");
        _root.帧计时器.当前帧数++;
        EnemyActionInputService.updateSample(actor,16,true);
        assert(EnemyActionRuntime.currentToken(actor).actionId == "a1", "held J repeats exactly at cooldown readiness");
        idle(actor);
        _root.帧计时器.当前帧数 += 48;
        EnemyActionInputService.updateSample(actor,2 | 128 | 16,true);
        var combo:Object = EnemyActionRuntime.currentToken(actor);
        assert(combo.actionId == "a2" && actor.右行 && actor.方向 == "右",
            "same-frame run movement plus J selects the original combo");
        idle(actor);
        _root.帧计时器.当前帧数++;
        EnemyActionInputService.updateSample(actor,2 | 128 | 8192,true);
        assert(EnemyActionRuntime.currentToken(actor) == null, "combo quick slot shares the running J cooldown");
        EnemyActionInputService.updateSample(actor,2 | 128 | 16,true);
        assert(EnemyActionRuntime.currentToken(actor) == null && actor.状态 == "空手跑",
            "holding running J during combo cooldown still enters actual running movement");
        _root.帧计时器.当前帧数++;
        EnemyActionInputService.updateSample(actor,2 | 16,true);
        assert(EnemyActionRuntime.currentToken(actor).actionId == "a1",
            "releasing run while moving switches the same held J back to interception immediately");
        idle(actor);
        _root.帧计时器.当前帧数 = combo.startedAt + 105;
        EnemyActionInputService.updateSample(actor,0,true);
        EnemyActionInputService.updateSample(actor,8192,true);
        assert(EnemyActionRuntime.currentToken(actor).actionId == "a2"
            && !EnemyActionRuntime.isRunning(actor),
            "ready combo skill casts directly while stationary");
        idle(actor);
        EnemyActionInputService.updateSample(actor,0,true);
        _root.帧计时器.当前帧数++;
        EnemyActionInputService.updateSample(actor,128 | 16,true);
        assert(EnemyActionRuntime.currentToken(actor).actionId == "a1", "stationary run key plus J remains ordinary interception");
        idle(actor);
        EnemyActionInputService.updateSample(actor,0,true);
        _root.帧计时器.当前帧数++;
        EnemyActionInputService.updateSample(actor,32,true);
        var rush:Object = EnemyActionRuntime.currentToken(actor);
        assert(rush.actionId == "rush", "K requests the same dragon rush as I");
        var rushDeadline:Number = actor.__enemyActionRuntime.cooldowns.rush;
        EnemyActionInputService.updateSample(actor,256,true);
        var hop:Object = EnemyActionRuntime.currentToken(actor);
        assert(hop.actionId == "hop" && !rush.active
            && actor.__enemyActionRuntime.cooldowns.rush == rushDeadline,
            "manual hop cancels recovery without refunding the attack cooldown");
        idle(actor);
        EnemyActionInputService.updateSample(actor,1024,true);
        assert(EnemyActionRuntime.currentToken(actor) == null,
            "I cannot bypass the cooldown committed by K before hop cancellation");
        var basic:Object = EnemyActionRuntime.request(actor,"basic","player",null);
        var hopDeadline:Number = actor.__enemyActionRuntime.cooldowns.hop;
        assert(basic != null && EnemyActionRuntime.request(actor,"hop","player",null) == null
            && EnemyActionRuntime.currentToken(actor) === basic && basic.active
            && actor.__enemyActionRuntime.cooldowns.hop == hopDeadline,
            "rejected early hop neither cancels the current attack nor restarts its cooldown");
        idle(actor);
        var hud:Object = EnemyActionRuntime.hudDescriptors(actor);
        assert(hud.slots[0].cooldownMs == 2500 && hud.slots[1].cooldownMs == 4700
            && hud.slots[2].cooldownMs == 6000 && hud.slots[3].cooldownMs == 9000
            && hud.slots[4].cooldownMs == 1600 && hud.slots[5].cooldownMs == 3500,
            "native skill-bar descriptors expose the same six player cooldown durations");
        actor.宠物属性.冲腿龙息 = false;
        _root.帧计时器.当前帧数 += 300;
        assert(EnemyActionRuntime.request(actor,"rush","player",null) == null
            && EnemyActionRuntime.request(actor,"strongRush","player",null) == null
            && actor.__enemyActionRuntime.cooldowns.rush == rushDeadline,
            "key remapping neither unlocks dragon abilities nor consumes cooldown on locked attempts");
        assert(EnemyActionRuntime.request(actor,"a1","ai",null) == null,
            "AI cannot take over the trial player even after control changes");
        var ai:Object = unit("cdEnemy", false, null);
        assert(ai.__enemyActionRuntime.profile.actions.a1.cooldownFrames == undefined
            && ai.__enemyActionRuntime.profile.actions.a2.cooldownFrames == undefined
            && ai.__enemyActionRuntime.profile.actions.hop.cooldownFrames == 30,
            "enemy cooldown profile retains original attack pacing and one-second active hop");
        var aiAttack:Object = EnemyActionRuntime.request(ai,"a2","ai",null);
        idle(ai);
        assert(aiAttack != null && EnemyActionRuntime.request(ai,"a2","ai",null) != null,
            "enemy combo still admits from standing without a new player cooldown");
    }

    private static function testPlayerFacingAndDirectSkills():Void {
        _root.帧计时器.当前帧数 = 10000;
        _root.控制目标 = "turnPlayer";
        var actor:Object = unit("turnPlayer",true,null);
        actor.方向改变 = function(direction:String):Void {
            if (!this.锁定方向) this.方向 = direction;
        };
        EnemyActionInputService.updateSample(actor,0,true);
        EnemyActionInputService.updateSample(actor,16,true);
        var token:Object = EnemyActionRuntime.currentToken(actor);
        var deadline:Number = actor.__enemyActionRuntime.cooldowns.a1;
        var calls:Number = actor.calls;
        _root.帧计时器.当前帧数++;
        EnemyActionInputService.updateSample(actor,1 | 16,true);
        assert(actor.方向 == "左" && EnemyActionRuntime.currentToken(actor) === token
            && token.active && actor.calls == calls,
            "held ordinary attack turns left during the same action without replaying state");
        EnemyActionInputService.updateSample(actor,3 | 16,true);
        assert(actor.方向 == "右" && actor.右行 && !actor.左行,
            "mid-attack opposed directions use the same right-priority arbitration");
        EnemyActionInputService.updateSample(actor,4 | 16,true);
        assert(actor.方向 == "右", "vertical-only input retains the current attack facing");
        assert(actor.__enemyActionRuntime.cooldowns.a1 == deadline && token.startedAt == 10000,
            "turning cannot restart or refund the admitted attack cooldown");
        actor.锁定方向 = true; // 外部锁向，不属于这个可转向动作。
        EnemyActionInputService.updateSample(actor,1 | 16,true);
        assert(actor.方向 == "右", "facing input preserves an external direction lock");
        actor.锁定方向 = false;
        EnemyActionRuntime.setOwnedFlag(actor,token,"锁定方向",false);
        EnemyActionInputService.updateSample(actor,1 | 16,true);
        assert(actor.方向 == "左", "turning resumes when the native direction lock clears");
        EnemyActionInputService.updateSample(actor,2 | 16,false);
        assert(actor.方向 == "左" && token.active,
            "disabled input cannot turn or cancel the current attack");
        idle(actor);

        // Every equipped skill uses its own key, with no run/chord requirement.
        var ids:Array = ["hop","basic","rush","strongRush","a1","a2"];
        for (var slot:Number = 0; slot < ids.length; slot++) {
            var name:String = "directSkill" + slot;
            _root.控制目标 = name;
            actor = unit(name,true,null);
            var hud:Object = EnemyActionRuntime.hudDescriptors(actor);
            EnemyActionInputService.updateSample(actor,0,true);
            EnemyActionInputService.updateSample(actor,1 << (8 + slot),true);
            token = EnemyActionRuntime.currentToken(actor);
            assert(hud.slots[slot].equipped && token != null && token.actionId == ids[slot]
                && !EnemyActionRuntime.isRunning(actor),
                "equipped slot " + (slot + 1) + " casts directly from neutral input");
            if (ids[slot] == "a2") {
                deadline = actor.__enemyActionRuntime.cooldowns.a2;
                idle(actor);
                EnemyActionInputService.updateSample(actor,0,true);
                EnemyActionInputService.updateSample(actor,2 | 128 | 16,true);
                assert(EnemyActionRuntime.currentToken(actor) == null
                    && actor.__enemyActionRuntime.cooldowns.a2 == deadline,
                    "running J cannot bypass cooldown started by the direct combo skill");
            } else idle(actor);
        }

        _root.控制目标 = "fixedFacing";
        actor = unit("fixedFacing",true,null);
        EnemyActionRuntime.request(actor,"basic","player",null);
        EnemyActionInputService.updateSample(actor,0,true);
        EnemyActionInputService.updateSample(actor,1,true);
        assert(actor.方向 == "左", "the fixed player skill loadout now accepts mid-action facing");
        idle(actor);
        var ai:Object = unit("aiFacing",false,null);
        assert(ai.__enemyActionRuntime.profile.actions.a1.allowFacingInput !== true,
            "AI action profile does not acquire player mid-attack facing input");
    }

    private static function testPlayerCancelChains():Void {
        _root.帧计时器.当前帧数 = 60000;
        var ids:Array = ["a1","a2","basic","rush","strongRush","hop"];
        for (var i:Number = 0; i < ids.length; i++) {
            for (var j:Number = 0; j < ids.length; j++) {
                if (i == j) continue;
                _root.控制目标 = "chain" + i + "_" + j;
                var actor:Object = unit(_root.控制目标,true,null);
                var first:Object = EnemyActionRuntime.request(actor,ids[i],"player",null);
                var deadline:Number = actor.__enemyActionRuntime.cooldowns[ids[i]];
                EnemyActionRuntime.setOwnedFlag(actor,first,"刚体",true);
                var next:Object = EnemyActionRuntime.request(actor,ids[j],"player",null);
                assert(next != null && !first.active && actor.__enemyActionRuntime.cooldowns[ids[i]] == deadline,
                    "player cancels " + ids[i] + " into " + ids[j] + " without refunding the first cooldown");
                EnemyActionRuntime.cancel(actor,first,"late-old-container");
                assert(EnemyActionRuntime.currentToken(actor) === next && !actor.刚体,
                    "late old ownership cannot steal the replacement " + ids[j]);
            }
        }
        _root.控制目标 = "heldChain";
        actor = unit("heldChain",true,null);
        EnemyActionInputService.updateSample(actor,0,true);
        EnemyActionInputService.updateSample(actor,16,true);
        first = EnemyActionRuntime.currentToken(actor);
        EnemyActionInputService.updateSample(actor,16 | 32,true);
        next = EnemyActionRuntime.currentToken(actor);
        EnemyActionInputService.updateSample(actor,16,true);
        assert(next.actionId == "rush" && !first.active && EnemyActionRuntime.currentToken(actor) === next,
            "held J cannot take back a freshly cast skill");
        var kept:Number = actor.__enemyActionRuntime.cooldowns.rush;
        actor.__enemyActionRuntime.cooldowns.basic = 999999;
        EnemyActionInputService.updateSample(actor,16 | 512,true);
        assert(EnemyActionRuntime.currentToken(actor) === next && next.active
            && actor.__enemyActionRuntime.cooldowns.rush == kept,
            "unready cancellation leaves the running action and all committed cooldowns intact");
        EnemyActionRuntime.setOwnedFlag(actor,next,"锁定方向",true);
        assert(!actor.锁定方向 && next.ownedFlags.锁定方向 == undefined,
            "steerable player skills do not take native direction-lock ownership");
        actor.移动 = function(direction:String, speed:Number):Void { this.movedDirection=direction; this.movedAmount=speed; };
        EnemyActionRuntime.finish(actor,next); actor.状态 = "空手站立";
        next = EnemyActionRuntime.request(actor,"strongRush","player",null);
        actor.方向 = "左"; EnemyActionRuntime.moveTracking(actor,next,15);
        assert(actor.movedDirection == "左" && actor.movedAmount == 15,"advanced tracking uses current facing to move left");
        actor.方向 = "右"; EnemyActionRuntime.moveTracking(actor,next,15);
        assert(actor.movedDirection == "右","advanced tracking changes its actual travel direction");
        EnemyActionRuntime.finish(actor,next); actor.movedDirection = "";
        EnemyActionRuntime.moveTracking(actor,next,15);
        assert(actor.movedDirection == "","cancelled tracking tokens produce no late movement");
        actor.状态 = "被击"; actor.硬直中 = true;
        assert(EnemyActionRuntime.request(actor,"a2","player",null) != null && !actor.硬直中,
            "manual skill admission can break grounded hitstun like main-character skills");
        actor.浮空 = true;
        assert(EnemyActionRuntime.request(actor,"hop","player",null) == null,
            "broader skill cancellation still respects the existing airborne boundary");
        _root.控制目标 = "noAIChain";
        var ai:Object = unit("stillAI",false,null);
        first = EnemyActionRuntime.request(ai,"a1","ai",null);
        assert(EnemyActionRuntime.request(ai,"rush","ai",null) == null && EnemyActionRuntime.currentToken(ai) === first,
            "AI does not acquire player skill cancellation");
    }

    private static function testPlayerSceneClock():Void {
        var clock:Object = {activeFrames:100};
        var session:Object = {clock:clock, deadlines:{}};
        _root.控制目标 = "clockPlayer";
        var actor:Object = unit("clockPlayer",true,session);
        var token:Object = EnemyActionRuntime.request(actor,"basic","player",null);
        assert(token != null && session.deadlines.basic == 241, "player deadline starts on the admitted active game frame");
        idle(actor);
        _root.暂停 = true;
        _root.帧计时器.当前帧数 += 1000;
        var pausedHud:Array = EnemyActionRuntime.hudCooldowns(actor);
        assert(pausedHud[2][1] == 0 && pausedHud[2][2] == 141
            && EnemyActionRuntime.request(actor,"hop","player",null) == null
            && session.deadlines.hop == undefined,
            "communication frames during pause cannot advance game-clock cooldowns or admit a new action");
        _root.暂停 = false;
        clock.activeFrames = 140;
        assert(EnemyActionRuntime.hudCooldowns(actor)[2][1] == 40,
            "HUD cooldown progress consumes only the shared active-frame authority");
        EnemyActionRuntime.releaseUnit(actor,"sceneExit");
        actor = unit("clockPlayer",true,session);
        assert(EnemyActionRuntime.request(actor,"basic","player",null) == null
            && EnemyActionRuntime.hudCooldowns(actor)[2][1] == 40,
            "new unit on the next map retains the previous remaining cooldown");
        EnemyActionRuntime.cancel(actor,token,"late-old-world-unload");
        assert(session.deadlines.basic == 241, "old-world token cannot erase the shared action deadline");
        clock.activeFrames = 240;
        assert(EnemyActionRuntime.request(actor,"basic","player",null) == null, "last cooldown frame is still blocked after a map change");
        clock.activeFrames++;
        assert(EnemyActionRuntime.request(actor,"basic","player",null) != null, "carried cooldown admits exactly on its game-frame deadline");
        EnemyActionRuntime.releaseUnit(actor,"trialEnd");
        actor = unit("clockPlayer",true,{clock:{activeFrames:0},deadlines:{}});
        assert(EnemyActionRuntime.request(actor,"basic","player",null) != null,
            "a new trial begins with independent cooldown authority");
    }

    private static function assert(condition:Boolean, message:String):Void {
        if (condition) passed++;
        else { failed++; trace("FAIL " + message); }
    }
}