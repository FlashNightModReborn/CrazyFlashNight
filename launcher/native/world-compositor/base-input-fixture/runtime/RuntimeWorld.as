stop();
Stage.scaleMode = "showAll"; Stage.align = "TL";
var b1Codec:LiteJSON = new LiteJSON();
var b1Session:String = "", b1Coverage:String = "";
var b1Epoch:Number = 0, b1Ticket:Number = 0, b1Geometry:Number = 1, b1Sequence:Number = 0;
var b1Prepared:Boolean = false, b1Granted:Boolean = false;
var b1Prefix:Object = null, b1Held:Object = {};
var b1Actor:MovieClip, b1Scene:MovieClip;
var b1Frames:Number = 0, b1Events:Number = 0, b1MovementCalls:Number = 0;
var b1DeniedTasks:Number = 0, b1DeniedBusiness:Number = 0;
var b1LastDiagnostic:String = "", b1ReadySent:Boolean = false;
var b1SceneReady:Boolean = false;
#include "../services/ProductionBindings.as"
#include "../services/MedicalEnvironment.as"
#include "../services/B1Services.as"

// Qualify the production handlers BEFORE attaching the actor. Its authored 控制块
// enterFrame remains the sole walking/animation driver; our tick never walks it.
var b1ProductionWalk:Function = _root.主角函数.行走_玩家;
var b1ProductionStateMachine:Function = _root.主角函数.拳刀行走状态机;
_root.主角函数.行走_玩家 = function():Void {
    if (!b1BusinessGate()) { b1ClearHolds(); return; }
    b1MovementCalls++;
    b1ProductionWalk.call(this);
};
_root.主角函数.拳刀行走状态机 = function():Void {
    if (!b1BusinessGate()) { b1ClearHolds(); return; }
    b1ProductionStateMachine.call(this);
};
_global.__b1Receive = function(message:String):Void { b1Command(b1Codec.parse(message)); };
_global.__b1Cancel = function(reason:String):Void { b1Cancel(reason); };

function b1Emit(kind:String, value:Object):Void {
    if (typeof _global.__b1Emit != "function") return;
    value.kind = kind; value.session = b1Session; value.coverage = b1Coverage;
    value.epoch = b1Epoch; value.ticket = b1Ticket; value.geometry = b1Geometry;
    value.scope = "M"; value.incarnation = 1; value.serial = ++b1Events;
    _global.__b1Emit(b1Codec.stringifySafe(value));
}
function b1Boundary():Boolean {
    return _global.__b1TransportOpen() === true && _global.__b1InputBoundaryIntact() === true
        && org.flashNight.arki.input.IsolatedInputPolicy.forbidsLegacyDrivers();
}
function b1ReadyReason():String {
    if (!b1Boundary()) return "bootstrap_boundary_or_transport";
    if (!b1SceneReady) return "scene_services";
    if (b1Actor == undefined) return "actor_attach";
    if (typeof b1Actor.初始化玩家模板 != "function") return "player_template";
    if (b1Actor.__unitInitializedVersion == null || b1Actor.version !== b1Actor.__unitInitializedVersion) return "static_initializer_completion";
    if (typeof b1Actor.行走 != "function" || typeof b1Actor.移动 != "function" || typeof b1Actor.状态改变 != "function") return "production_movement_functions";
    if (b1Actor.dispatcher == undefined || b1Actor.aabbCollider == undefined || b1Actor.buffManager == undefined) return "unit_components";
    if (!isFinite(b1Actor._x) || !isFinite(b1Actor._y) || !isFinite(b1Actor.Z轴坐标)) return "actor_coordinates";
    if (!isFinite(b1Actor.行走X速度) || !isFinite(b1Actor.行走Y速度) || !(b1Actor.行走X速度 > 0)) return "derived_movement_speed";
    if (!isFinite(b1Actor.hp) || !isFinite(b1Actor.mp)) return "derived_vitals";
    if (b1Actor.man == undefined || b1Actor.身体_引用 == undefined || !(b1Actor.身体_引用._width > 0)) return "real_rig_body_attachment";
    if (typeof b1Actor.控制块.onEnterFrame != "function") return "authored_animation_driver";
    return "";
}
function b1BusinessGate():Boolean { return b1Granted && b1ReadyReason() === ""; }
function b1ClearHolds():Void {
    b1Held = {};
    b1Actor.上行 = b1Actor.下行 = b1Actor.左行 = b1Actor.右行 = false;
    b1Actor.动作A = b1Actor.动作B = b1Actor.动作C = false;
}
function b1Cancel(reason:String):Void {
    b1Granted = b1Prepared = false; b1Prefix = null; b1ClearHolds();
    b1Emit("CANCELLED", {gateClosed:true,pending:0,reason:reason});
}
function b1State():Object {
    var reason:String = b1ReadyReason();
    return {actorReady:reason === "",missing:reason,scene:"医务室",actor:"主角-男",gateClosed:!b1Granted,
        x:b1Actor._x,y:b1Actor._y,z:b1Actor.Z轴坐标,state:b1Actor.状态,
        hp:b1Actor.hp,mp:b1Actor.mp,walkX:b1Actor.行走X速度,walkY:b1Actor.行走Y速度,
        actorFrame:b1Actor._currentframe,manFrame:b1Actor.man._currentframe,frames:b1Frames,movementCalls:b1MovementCalls,
        bodyAttached:b1Actor.身体_引用 != undefined,initializerVersion:b1Actor.__unitInitializedVersion,
        boundaryIntact:_global.__b1InputBoundaryIntact(),deniedTasks:b1DeniedTasks,deniedBusiness:b1DeniedBusiness,
        keyPollPresent:typeof _root.keyPollMC.onEnterFrame == "function",
        frameTimerPresent:typeof _root.__FRAME_TIMER_INSTANCE__.onEnterFrame == "function",
        cooldownDriverPresent:typeof _root._cdWheel.onEnterFrame == "function",
        persistenceInstalled:_root.存档系统 != undefined,lastDiagnostic:b1LastDiagnostic};
}
function b1Positive(value):Boolean { return typeof value == "number" && value > 0 && value < 1000000000 && value == Math.floor(value); }
function b1Exact(p:Object):Boolean {
    return p.session === b1Session && p.coverage === b1Coverage && p.epoch === b1Epoch
        && p.ticket === b1Ticket && p.geometry === b1Geometry && p.scope === "M" && p.incarnation === 1;
}
function b1Command(p:Object):Void {
    if (p == null || typeof p.op != "string" || !b1Boundary()) { b1ClearHolds(); b1Granted = false; return; }
    if (p.op === "HELLO") {
        if (b1Session !== "" || typeof p.session != "string" || p.session.length !== 32
            || typeof p.coverage != "string" || p.coverage.length !== 64) return;
        b1Session = p.session; b1Coverage = p.coverage;
        b1Emit("REGISTER", b1State()); return;
    }
    if (b1Session === "" || p.session !== b1Session || p.coverage !== b1Coverage) return;
    if (p.op === "CANCEL") {
        if (!b1Positive(p.epoch) || !b1Positive(p.ticket) || !b1Positive(p.geometry)
            || p.epoch < b1Epoch || p.ticket < b1Ticket) return;
        b1Epoch = p.epoch; b1Ticket = p.ticket; b1Geometry = p.geometry; b1Cancel("host_cancel"); return;
    }
    if (p.op === "STATE" || p.op === "SNAPSHOT") { b1Emit("STATE",b1State()); return; }
    if (p.op === "VITALS") { b1Emit("VITALS",{vitals:org.flashNight.arki.hud.PlayerHudService.readVitalsSnapshot(b1Actor),
        characterName:_root.角色名,gender:_root.性别,height:_root.身高,actorReady:b1ReadyReason() === ""}); return; }
    if (p.op === "PREPARE") {
        if (b1Granted || b1Prepared || b1ReadyReason() !== "" || p.epoch !== b1Epoch
            || !b1Positive(p.ticket) || p.ticket <= b1Ticket || p.geometry !== b1Geometry
            || p.scope !== "M" || p.incarnation !== 1
            || !b1Positive(p.prefix.generation) || !b1Positive(p.prefix.sequence)) return;
        b1Ticket = p.ticket; b1Prepared = true;
        b1Prefix = {generation:p.prefix.generation,sequence:p.prefix.sequence};
        b1Emit("PREPARED",{gateClosed:true,prefix:b1Prefix}); return;
    }
    if (!b1Exact(p)) { b1Emit("stale_rejected",{}); return; }
    if (p.op === "GRANT") {
        if (!b1Prepared || p.sequence !== b1Prefix.sequence || p.sourceGeneration !== b1Prefix.generation || b1ReadyReason() !== "") return;
        b1Sequence = p.sequence; b1Granted = true; b1Prepared = false; b1Emit("GRANTED",{}); return;
    }
    if (p.op !== "KEYHOLD" && p.op !== "KEYRELEASE") { b1Emit("unsupported_operation",{requested:p.op}); return; }
    if (!b1BusinessGate() || !b1Positive(p.sequence) || p.sequence <= b1Sequence) { b1Emit("closed_rejected",{}); return; }
    var keyName:String = String(p.key).toUpperCase();
    var keyTable:Object = {W:"87",A:"65",S:"83",D:"68",UP:"38",DOWN:"40",LEFT:"37",RIGHT:"39",ARROWUP:"38",ARROWDOWN:"40",ARROWLEFT:"37",ARROWRIGHT:"39"};
    if (keyTable[keyName] != undefined) keyName = keyTable[keyName];
    if (keyName !== "87" && keyName !== "65" && keyName !== "83" && keyName !== "68"
        && keyName !== "38" && keyName !== "40" && keyName !== "37" && keyName !== "39") { b1Emit("key_rejected",{}); return; }
    b1Sequence = p.sequence; b1Held[keyName] = p.op === "KEYHOLD";
    b1Actor.上行 = b1Held["87"] || b1Held["38"]; b1Actor.下行 = b1Held["83"] || b1Held["40"];
    b1Actor.左行 = b1Held["65"] || b1Held["37"]; b1Actor.右行 = b1Held["68"] || b1Held["39"];
    b1Emit("KEY_APPLIED",{key:keyName,held:p.op === "KEYHOLD",sequence:b1Sequence});
}

b1Emit("BOOT",{gateClosed:true,actorReady:false,phase:"services_installed"});
if (b1Boundary()) {
    b1Scene = _root.attachMovie("基地场景-医务室","gameworld",1);
    b1SceneReady = b1CreateSceneServices(b1Scene);
    if (b1SceneReady) {
        b1Actor = b1Scene.attachMovie("主角-男","b1Hero",900000,
            {_x:602.5,_y:340.9,等级:1,身高:175,性别:"男",名字:"基地验收角色",兵种:"主角-男",是否为敌人:false,
             不掉钱:true,不掉装备:true,unitAIType:"None",攻击模式:"空手",方向:"右",hp:200,mp:100});
        b1ClearHolds();
    }
}
_root.onEnterFrame = function():Void {
    b1Frames++; _root.帧计时器.当前帧数 = b1Frames + 1;
    if (!b1Boundary()) { if (b1Granted || b1Prepared) b1Cancel("boundary_lost"); return; }
    var missing:String = b1ReadyReason();
    if (missing === "" && !b1ReadySent) { b1ReadySent = true; b1Emit("ACTOR_READY",b1State()); }
    if (missing !== "" && b1Frames % 30 === 1) b1Emit("NOT_READY",b1State());
    // No legacy scheduler update, polling driver, movement or duplicate control-clip tick.
};