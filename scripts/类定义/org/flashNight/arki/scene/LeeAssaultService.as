import org.flashNight.arki.scene.*;
import org.flashNight.arki.weather.WeatherSystem;
import org.flashNight.arki.weather.WorldLightingBridge;
import org.flashNight.arki.unit.Action.Regeneration.HealApplier;
import org.flashNight.arki.unit.Action.Input.EnemyActionRuntime;
import org.flashNight.arki.interaction.NativeInteractionContext;
import org.flashNight.arki.dialogue.NativeDialogueService;
import org.flashNight.arki.item.ItemUtil;
import org.flashNight.arki.component.Effect.EffectSystem;

/** 攻入篇事件编排。剧情只呈现，雷击/复活/进阶始终由本局持有。 */
class org.flashNight.arki.scene.LeeAssaultService {
    private static var _installed:Boolean = false;
    private static var _room:Object;
    private static var _watch:MovieClip;
    private static var _allowClear:Object;
    private static var _dialogueSeq:Number = 0;

    public static function install():Void {
        if (_installed) return;
        _installed = true;
        NativeInteractionContext.onSceneTeardown(teardown);
        if (_root.Lee试战 == undefined) _root.Lee试战 = {};
        _root.Lee试战.剧情记录 = function():String {
            var codec:LiteJSON = new LiteJSON();
            return codec.stringifySafe(org.flashNight.arki.scene.LeeAssaultService.snapshot());
        };
    }
    public static function snapshot():Object {
        var state:Object = _root._saveExt.bookRun.leeAssault;
        if (state == null) return null;
        var result:Object = org.flashNight.gesh.object.PersistedSnapshot.clone(state);
        if (current(_room)) {
            result.roomIndex = _room.index; result.phase = _room.phase;
            result.lighting = {progress:_room.lightProgress,min:_room.lighting.ws.minLight,max:_room.lighting.ws.maxLight};
        }
        return result;
    }
    public static function prepare(run:Object):Boolean {
        var config:Object = LeeTrialDefinition.get().assault;
        if (config == null) return true;
        if (run.bookId !== "lee-trial" || run.slot !== String(_root.savePath)) return false;
        if (run.leeAssault == null) run.leeAssault = LeeAssaultRules.create(
            LeeTrialDefinition.get().stages.length, config.boltsPerRoom, config.awakeningHits);
        var state:Object = run.leeAssault;
        if (state.coinsGranted !== true) {
            var before:Number = Number(ItemUtil.getTotal("复活币"));
            ItemUtil.singleAcquire("复活币", config.reviveCoins, {source:"lee_assault",reason:"chapter_allowance"});
            if (Number(ItemUtil.getTotal("复活币")) != before + config.reviveCoins) return false;
            state.coinsGranted = true;
        }
        return true;
    }
    public static function beginRoom(world:Object, identity:Object):Void {
        install();
        var run:Object = _root._saveExt.bookRun;
        var config:Object = LeeTrialDefinition.get().assault;
        var index:Number = StageManager.getInstance().currentStage;
        if (config == null || run.bookId !== "lee-trial" || run.outcome !== "active"
                || run.slot !== String(_root.savePath) || world !== _root.gameworld
                || identity == null || identity !== StageReturnFlow.worldIdentity(world)
                || run.leeAssault.rooms[index] == null) return;
        if (_room.owner === identity) return;
        teardown();
        var ws:Object = WeatherSystem.getInstance();
        _room = {run:run, slot:String(_root.savePath), owner:identity, world:world, index:index,
            state:run.leeAssault, record:run.leeAssault.rooms[index], config:config, dispatcher:world.dispatcher,
            phase:"entry", serial:0, lastFrame:-1, wait:0, fired:0,
            lighting:{ws:ws,min:ws.minLight,max:ws.maxLight,pause:ws.pauseDayNightCycle}};
        setLighting(_room, false);
        var actor:Object = world[_root.控制目标];
        applyAwakening(actor, run.leeAssault);
        // 全身铠甲的两种黑龙形态均保留电免；只作用于本次关卡单位参数。
        if (_watch == null || _watch._name == undefined)
            _watch = _root.createEmptyMovieClip("__leeAssault", _root.getNextHighestDepth());
        _watch.onEnterFrame = function():Void { org.flashNight.arki.scene.LeeAssaultService.tick(); };
        presentPage(_room, "lee-entry-" + index, "battle");
    }
    private static function current(room:Object):Boolean {
        return room != null && room === _room && room.run === _root._saveExt.bookRun
            && room.run.outcome === "active" && room.slot === String(_root.savePath)
            && room.owner === StageReturnFlow.worldIdentity(_root.gameworld);
    }
    /** 整个拥有中的 Lee 世界无敌方掉落；终局停留及换形态仍受同一世界身份约束。 */
    public static function suppressesEnemyDrops():Boolean {
        var room:Object = _room;
        return room != null && room.run.bookId === "lee-trial" && room.run === _root._saveExt.bookRun
            && room.slot === String(_root.savePath)
            && room.owner === StageReturnFlow.worldIdentity(_root.gameworld);
    }

    /** WaveSpawner 只提交一次清场；该门将开门/终局延后至剧情链完成。 */
    public static function interceptClear(manager:Object, world:Object):Boolean {
        var room:Object = _room;
        if (!current(room) || world !== room.world) return false;
        if (_allowClear === room.owner) { _allowClear = null; return false; }
        if (room.record.cleared === true) return true;
        room.record.cleared = true;
        room.manager = manager;
        room.world.允许通行 = false;
        room.phase = "await_alive";
        return true;
    }
    public static function canAdvance():Boolean {
        return !current(_room) || _room.phase === "open";
    }
    private static function presentPage(room:Object, page:String, next:String):Void {
        if (!current(room)) return;
        room.next = next; room.serial++;
        var follow:Function = continuation(room, room.serial);
        var rows:Array = room.config.dialogues[page];
        if (rows instanceof Array && rows.length > 0) {
            // 关卡内对白沿用原生剧情轮子；仅显式结束消费一次后续事件。
            room.phase = "dialogue";
            room.dialogueEvent = "LeeAssaultDialogue:" + (++_dialogueSeq);
            room.dialogueFollow = follow;
            room.dispatcher.subscribeOnce(room.dialogueEvent, follow, null);
            NativeDialogueService.beginStage(rows, {name:room.dialogueEvent});
        } else {
            // 漫画只用于第三图之后的偷袭、被俘、挣脱和双结局。
            room.phase = "comic";
            if (!BookComicService.begin(page, follow)) follow();
        }
    }
    private static function continuation(room:Object, serial:Number):Function {
        return function():Void { org.flashNight.arki.scene.LeeAssaultService.continued(room, serial); };
    }
    public static function continued(room:Object, serial:Number):Void {
        if (!current(room) || (room.phase != "comic" && room.phase != "dialogue") || room.serial != serial) return;
        if (room.dialogueFollow != null) {
            room.dispatcher.unsubscribe(room.dialogueEvent, room.dialogueFollow, null);
            room.dialogueFollow = null;
        }
        room.phase = room.next; room.wait = 0;
    }
    public static function tick():Void {
        var room:Object = _room;
        if (!current(room)) {
            // 结局只结束玩法，仍在同一房间时保留断电；真正离场才归还天气。
            if (room != null && room.phase == "finished" && room.run.outcome == "victory"
                    && room.run === _root._saveExt.bookRun && room.slot === String(_root.savePath)
                    && room.owner === StageReturnFlow.worldIdentity(_root.gameworld)) {
                delete _watch.onEnterFrame;
                return;
            }
            teardown(); return;
        }
        if (_root.暂停 === true || _root.场景转换中 === true) return;
        var clock:Number = Number(StageRunSession.getRunAuthority().activeFrames);
        if (isNaN(clock) || room.lastFrame === clock) return;
        room.lastFrame = clock;
        var actor:MovieClip = _root.gameworld[_root.控制目标];
        if (actor.__enemyActionPlayer !== true) return;
        advancePowerDrain(room);
        // 决战奖励：仅活体战斗帧缓慢自愈，约每秒最大生命的 1%；暂停/对白不偷跑。
        if (room.index == 3 && room.phase == "battle" && actor.hp > 0) {
            HealApplier.applyHpCapped(actor, Math.ceil(actor.hp满血值 / room.config.finalRecoveryFrames), actor.hp满血值);
        }
        if (room.phase == "await_alive") {
            if (actor.hp > 0) {
                if (room.index == 3) {
                    drainPower(room, 1, room.config.warningFrames + room.config.gapFrames);
                    room.phase = "final_outage";
                } else presentPage(room, "lee-clear-" + room.index, "warning");
            }
            return;
        }
        if (room.phase == "final_outage") {
            if (room.lightProgress >= 1 && actor.hp > 0) {
                room.record.powerOff = true;
                presentPage(room, "lee-clear-3", "final_recover");
            }
        } else if (room.phase == "warning") {
            if (!(actor.hp > 0)) return;
            if (room.fired < room.config.boltsPerRoom) {
                room.aimX = actor._x; room.aimY = actor.Z轴坐标;
                room.wait = room.config.warningFrames; room.phase = "aim";
                showWarning(room);
            } else { room.wait = 30; room.phase = "tail"; }
        } else if (room.phase == "aim") {
            if (--room.wait > 0) return;
            removeWarning(room);
            if (actor.hp > 0) fireLightning(room, actor);
            room.fired++; room.record.fired = room.fired;
            drainPower(room, room.fired / room.config.boltsPerRoom, room.config.gapFrames);
            room.wait = room.config.gapFrames; room.phase = "gap";
        } else if (room.phase == "gap") {
            if (--room.wait <= 0) room.phase = "warning";
        } else if (room.phase == "tail") {
            if (--room.wait > 0) return;
            var awakened:Boolean = LeeAssaultRules.resolve(room.state, room.index, actor.hp > 0);
            if (awakened) applyAwakening(actor, room.state);
            setLighting(room, true);
            room.phase = "after_wait";
        } else if (room.phase == "after_wait") {
            // 死亡弹窗保持可用。雷停后复活依旧可以续关，但该次复活已记入觉醒条件。
            if (actor.hp > 0) presentPage(room, awakenedPage(room), "recover");
        } else if (room.phase == "recover" || room.phase == "final_recover") {
            if (!(actor.hp > 0)) return;
            var amount:Number = Math.ceil(actor.hp满血值 / room.config.recoveryFrames);
            HealApplier.applyHpCapped(actor, amount, actor.hp满血值);
            if (actor.hp < actor.hp满血值) return;
            if (room.phase == "final_recover") presentPage(room, "lee-after-3", "victory_comic");
            else if (room.index == 2) presentPage(room, "lee-ambush", "capture");
            else openRoom(room, false);
        } else if (room.phase == "capture") {
            // 剧情倒下只存在于漫画。普通死亡/复活/扣币都不参与这次演出。
            if (room.state.awakened) presentPage(room, "lee-breakout", "breakout");
            else presentPage(room, "lee-ending-normal", "ending_normal");
        } else if (room.phase == "breakout") openRoom(room, true);
        else if (room.phase == "victory_comic") presentPage(room, "lee-ending-hidden", "ending_hidden");
        else if (room.phase == "ending_normal" || room.phase == "ending_hidden") {
            room.state.ending = room.phase == "ending_hidden" ? "hidden" : "normal";
            room.phase = "finished";
            // 普通结局在第三张图终止；隐藏结局完成最终图后提交同一正规胜利路径。
            room.manager.finishStage();
        }
    }
    private static function awakenedPage(room:Object):String {
        if (room.state.awakeningRoom == room.index) return "lee-awaken";
        return "lee-after-" + room.index + (room.state.revives > 0 ? "-revived" : "");
    }
    private static function openRoom(room:Object, advance:Boolean):Void {
        if (!current(room)) return;
        room.phase = "open"; _allowClear = room.owner;
        room.manager.clearStage();
        if (advance) room.manager.nextStage();
    }
    private static function showWarning(room:Object):Void {
        var mark:MovieClip = room.world.createEmptyMovieClip("__leeLightningMark", room.world.getNextHighestDepth());
        mark._x = room.aimX; mark._y = room.aimY;
        mark.lineStyle(2, 0xFFCA66, 95);
        mark.moveTo(-28, 0); mark.lineTo(28, 0); mark.moveTo(0, -13); mark.lineTo(0, 13);
        mark.moveTo(-24, -9); mark.lineTo(24, -9); mark.lineTo(24, 9); mark.lineTo(-24, 9); mark.lineTo(-24, -9);
    }
    private static function removeWarning(room:Object):Void { room.world.__leeLightningMark.removeMovieClip(); }
    private static function fireLightning(room:Object, actor:MovieClip):Void {
        var emitter:MovieClip = room.world.__leeTrapEmitter;
        if (emitter == undefined) {
            emitter = room.world.createEmptyMovieClip("__leeTrapEmitter", room.world.getNextHighestDepth());
            emitter.dispatcher = new org.flashNight.neur.Event.EventDispatcher();
            emitter.是否为敌人 = true; emitter.等级 = 35; emitter.伤害加成 = 0;
            emitter.命中率 = 100000; emitter._xscale = 100; emitter.方向 = "右";
        }
        emitter._x = room.aimX; emitter._y = room.aimY; emitter.Z轴坐标 = room.aimY;
        var receipt:Object = {room:room, bolt:room.fired, target:actor.__controlledEnemyContext,
            hp:Number(actor.hp), consumed:false};
        var bullet:Object = {声音:"", 发射效果:"", 子弹种类:"诛神闪电", 子弹威力:0,
            固伤:LeeAssaultRules.lightningSolid(actor, room.config.damagePerBolt),
            百分比伤害:0, 霰弹值:1, 最小霰弹值:1, 子弹散射度:0, 子弹速度:0,
            发射者:emitter._name, shootX:room.aimX, shootY:room.aimY, shootZ:room.aimY,
            转换中间y:room.aimY, Z轴攻击范围:300, 伤害类型:"魔法", 魔法伤害属性:"电",
            命中率:100000, 击倒率:0, 水平击退速度:0, 垂直击退速度:0, 角度偏移:0,
            击中地图效果:"", 击中后子弹的效果:"", __leeTrapReceipt:receipt,
            击中时触发函数:lightningHit()};
        _root.子弹区域shoot传递(bullet);
    }
    private static function lightningHit():Function {
        return function():Void {
        var bullet:Object = this;
        var receipt:Object = bullet.__leeTrapReceipt;
        org.flashNight.arki.scene.LeeAssaultService.acceptHit(receipt, bullet.命中对象);
        };
    }
    public static function acceptHit(receipt:Object, actor:Object):Boolean {
        var room:Object = receipt.room;
        if (!current(room) || receipt.consumed === true || receipt.target !== actor.__controlledEnemyContext
                || actor._name !== _root.控制目标) return false;
        receipt.consumed = true;
        return LeeAssaultRules.recordHit(room.state, room.index, receipt.bolt,
            Math.max(0, receipt.hp - Number(actor.hp)));
    }
    public static function onRespawn(actor:Object):Void {
        var room:Object = _room;
        if (!current(room) || actor.__enemyActionPlayer !== true) return;
        LeeAssaultRules.respawn(room.state);
        actor.__controlledEnemyContext.handled = false;
        applyAwakening(actor, room.state);
    }
    public static function applyAwakening(actor:Object, state:Object):Void {
        if (actor.__enemyActionPlayer !== true || state.awakened !== true) return;
        if (actor.宠物属性.冲腿龙息 !== true) {
            actor.宠物属性.冲腿龙息 = true;
            _root.战宠进阶函数.冲腿龙息.单位进阶执行.call(actor);
            _root.玩家信息界面.刷新hp显示();
        }
    }
    private static function setLighting(room:Object, outage:Boolean):Void {
        var ws:Object = room.lighting.ws;
        ws.pauseDayNightCycle = true;
        room.lightProgress = outage ? 1 : 0;
        room.lightFrames = 0;
        var bounds:Object = LeeAssaultRules.powerBounds(room.config.battleLight, room.config.outageLight, room.lightProgress);
        ws.minLight = bounds.min; ws.maxLight = bounds.max;
        if (!outage) WorldLightingBridge.snapNext();
        WorldLightingBridge.publish(ws, true);
    }
    private static function drainPower(room:Object, progress:Number, frames:Number):Void {
        room.lightFrom = Number(room.lightProgress || 0);
        room.lightTarget = Math.max(room.lightFrom, Math.min(1, progress));
        room.lightFrames = Math.max(1, frames); room.lightStep = 0;
    }
    private static function advancePowerDrain(room:Object):Void {
        if (!(room.lightFrames > 0)) return;
        room.lightStep++;
        var ratio:Number = Math.min(1, room.lightStep / room.lightFrames);
        room.lightProgress = ratio == 1 ? room.lightTarget : room.lightFrom + (room.lightTarget-room.lightFrom) * ratio;
        var bounds:Object = LeeAssaultRules.powerBounds(room.config.battleLight, room.config.outageLight, room.lightProgress);
        room.lighting.ws.minLight = bounds.min; room.lighting.ws.maxLight = bounds.max;
        // 连续投影，不逐次 snap；最后一道也在雷停前抵达既定断电值。
        WorldLightingBridge.publish(room.lighting.ws, true);
        if (ratio == 1) room.lightFrames = 0;
    }
    private static function teardown():Void {
        var room:Object = _room;
        _room = null; _allowClear = null;
        if (_watch != undefined) delete _watch.onEnterFrame;
        if (room == null) return;
        if (room.dialogueFollow != null)
            room.dispatcher.unsubscribe(room.dialogueEvent, room.dialogueFollow, null);
        removeWarning(room);
        room.world.__leeTrapEmitter.removeMovieClip();
        var light:Object = room.lighting;
        light.ws.minLight = light.min; light.ws.maxLight = light.max;
        light.ws.pauseDayNightCycle = light.pause;
        WorldLightingBridge.snapNext();
    }
}
