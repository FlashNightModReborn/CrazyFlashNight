stop();
Stage.scaleMode = "showAll";
Stage.align = "TL";
var codec:LiteJSON = new LiteJSON();
var wire:XMLSocket = new XMLSocket();
var online:Boolean = false;
var session:String = "", coverage:String = "";
var epoch:Number = 0, ticket:Number = 0, geometry:Number = 1, sequence:Number = 0;
var prepared:Boolean = false, granted:Boolean = false;
var held:Object = null, openIntent:Object = null;
var preparedPrefix:Object = null;
var targetIdentity:Object = {};
var events:Number = 0, rawRejected:Number = 0, opens:Number = 0;
var displayFrames:Number = 0;
var bootOkay:Boolean = org.flashNight.arki.input.IsolatedInputPolicy.isValid()
    && org.flashNight.arki.ui.PlasticSurgeryPanelService.installDraftOnly();
// No base scene, boot include, shared store, global input listener or dynamic
// executable loader is installed. These are disposable in-memory character data.
_root.savePath = "c1-island-disposable";
_root.角色名 = "输入验收角色"; _root.性别 = "男"; _root.身高 = 175;
_root.发型 = "光头"; _root.脸型 = "男变装-基本脸型"; _root.虚拟币 = 20;
_root.控制目标 = "c1Hero";
_root.gameworld = _root.createEmptyMovieClip("gameworld", 1);
var actor:MovieClip = _root.gameworld.createEmptyMovieClip("c1Hero", 1);
actor._x = 180; actor._y = 180; actor.性别 = "男";
actor.hp = 80; actor.hp满血值 = 100; actor.mp = 40; actor.mp满血值 = 60; actor.nonlinearMappingResilience = 1;
_root.等级 = 1; _root.经验值 = 25; _root.上次升级需要经验值 = 0; _root.升级需要经验值 = 100; _root.技能点数 = 0;
_root.暂停 = false;
actor.createEmptyMovieClip("man", 1).createEmptyMovieClip("parts", 1);
var body:MovieClip = actor.man.parts.createEmptyMovieClip("body", 1);
var face:MovieClip = actor.man.parts.createEmptyMovieClip("face", 2);
face._y = -36;
_root.装备引用配置 = {};
_root.装备引用配置.刷新所有装扮 = org.flashNight.arki.unit.UnitComponent.Dressup.DressupReferenceManager.refreshAll;
org.flashNight.arki.unit.UnitComponent.Dressup.DressupReferenceManager.attach(body, "C1Body", "skin", "身体_引用");
org.flashNight.arki.unit.UnitComponent.Dressup.DressupReferenceManager.attach(face, "C1Face", "skin", "面具_引用");
var opener:MovieClip = _root.attachMovie("C1SurgeryOpener", "surgeryOpener", 2);
opener._x = 340; opener._y = 150; opener.txt.text = "整形手术";
_root.createTextField("caption", 3, 28, 28, 580, 80);
_root.caption.text = "C1-I 独立冷启动：真实整形服务，只允许草稿和取消。";
_root.caption.textColor = 0xEEEEEE;
_root.beginFill(0x132A42, 100); _root.moveTo(0, 0); _root.lineTo(640, 0); _root.lineTo(640, 360); _root.lineTo(0, 360); _root.endFill();
var displayMarker:MovieClip = _root.createEmptyMovieClip("c1DisplayMarker", 4);
// Pure presentation heartbeat, not a gameplay timer or deferred business task.
_root.onEnterFrame = function():Void {
    displayFrames++;
    if (displayFrames % 15 != 1) return;
    displayMarker.clear(); displayMarker.beginFill(displayFrames % 30 < 15 ? 0xFF00FF : 0x00FF80, 100);
    displayMarker.moveTo(20, 100); displayMarker.lineTo(52, 100); displayMarker.lineTo(52, 132); displayMarker.lineTo(20, 132); displayMarker.endFill();
};
_root.server = {};
_root.server.sendSocketMessage = function(payload:String):Boolean {
    if (!online) return false;
    var message:Object = codec.parse(payload);
    if (message.task == "panel_request") {
        if (openIntent == null) { emit("opener_rejected", {}); return false; }
        message.inputIntent = openIntent;
        openIntent = null;
        opens++;
    }
    wire.send(codec.stringifySafe(message));
    return true;
};
// This is the production domain opener itself. The ordinary all-UI installer is
// deliberately absent because it also registers unrelated executable loading.
_root.打开整形手术 = org.flashNight.arki.ui.PlasticSurgeryPanelService.openPanel;
opener.onRelease = function():Void { rawRejected++; emit("raw_rejected", {}); };
function emit(kind:String, value:Object):Void {
    if (!online) return;
    value.kind = kind; value.session = session; value.coverage = coverage;
    value.epoch = epoch; value.ticket = ticket; value.geometry = geometry;
    value.scope = "M"; value.incarnation = 1; value.serial = ++events;
    wire.send(codec.stringifySafe(value));
}
function exact(p:Object):Boolean {
    return p.session === session && p.coverage === coverage && p.epoch === epoch
        && p.ticket === ticket && p.geometry === geometry;
}
function positive(value):Boolean { return typeof value == "number" && value > 0 && value < 1000000000 && value == Math.floor(value); }
// Coordinates are stage coordinates of this exact geometry, never a trusted
// caller-supplied target name. This island has one non-overlapped input target.
function targetHit(p:Object):Boolean {
    return typeof p.x == "number" && typeof p.y == "number" && isFinite(p.x) && isFinite(p.y)
        && p.x >= 0 && p.x < 640 && p.y >= 0 && p.y < 360 && opener._visible
        && opener.hitTest(p.x, p.y, true);
}
var permittedOps:Object = {HELLO:1, CANCEL:1, PREPARE:1, GRANT:1, SNAPSHOT:1, VITALS:1, VISUAL:1,
    LEGACY_TASK_PROBE:1, QUERY:1, DENY_PROBE:1, RAW_OPENER_PROBE:1, BEGIN:1, END:1};
function command(p:Object):Void {
    if (p == null || typeof p.op != "string") return;
    if (permittedOps[p.op] !== 1) { emit("unsupported_operation", {requested:p.op}); return; }
    if (p.op == "HELLO") {
        if (session != "" || !bootOkay || typeof p.session != "string" || p.session.length != 32
                || typeof p.coverage != "string" || p.coverage.length != 64) return;
        session = p.session; coverage = p.coverage;
        emit("REGISTER", {gateClosed:true, pending:0, policy:org.flashNight.arki.input.IsolatedInputPolicy.snapshot(),
            keyPollPresent:typeof _root.keyPollMC.onEnterFrame == "function",
            frameTimerPresent:typeof _root.__FRAME_TIMER_INSTANCE__.onEnterFrame == "function",
            cooldownDriverPresent:typeof _root._cdWheel.onEnterFrame == "function",
            actorReady:org.flashNight.arki.unit.UnitComponent.Dressup.LiveAppearanceUpdater.isReady(actor),
            bodyAttached:body.skin != undefined, faceAttached:face.skin != undefined, persistenceInstalled:_root.存档系统 != undefined});
        return;
    }
    if (session == "" || p.session !== session || p.coverage !== coverage) return;
    if (p.op == "CANCEL") {
        if (!positive(p.epoch) || !positive(p.ticket) || !positive(p.geometry)
                || p.epoch < epoch || p.ticket < ticket) return;
        granted = prepared = false; held = openIntent = preparedPrefix = null;
        epoch = p.epoch; ticket = p.ticket; geometry = p.geometry;
        emit("CANCELLED", {gateClosed:true, pending:0}); return;
    }
    if (p.op == "PREPARE") {
        if (granted || held != null || p.epoch !== epoch || !positive(p.ticket) || p.ticket <= ticket || p.geometry !== geometry) return;
        if (!positive(p.prefix.generation) || !positive(p.prefix.sequence)) return;
        ticket = p.ticket; prepared = true;
        preparedPrefix = {generation:p.prefix.generation, sequence:p.prefix.sequence};
        emit("PREPARED", {gateClosed:true, prefix:preparedPrefix}); return;
    }
    if (!exact(p)) { emit("stale_rejected", {}); return; }
    if (p.op == "GRANT") {
        if (!prepared || p.sequence !== preparedPrefix.sequence || p.sourceGeneration !== preparedPrefix.generation) return;
        sequence = p.sequence; granted = true; prepared = false; emit("GRANTED", {}); return;
    }
    if (p.op == "SNAPSHOT") {
        // A read-only preparation request is allowed while business input is closed.
        org.flashNight.arki.ui.PlasticSurgeryPanelService.handle("snapshot", {v:1, callId:p.callId}); return;
    }
    if (p.op == "VITALS") { emit("VITALS", {vitals:org.flashNight.arki.hud.PlayerHudService.readVitalsSnapshot(actor)}); return; }
    if (p.op == "VISUAL") { emit("VISUAL", {frames:displayFrames, rootVisible:_root._visible, rootAlpha:_root._alpha,
        stageWidth:Stage.width, stageHeight:Stage.height, rootBounds:_root.getBounds(_root),
        actorWidth:actor._width, actorHeight:actor._height, bodyWidth:body.skin._width, buttonWidth:opener._width, buttonBounds:opener.getBounds(_root)}); return; }
    if (p.op == "LEGACY_TASK_PROBE") {
        _root.legacyProbeExecuted = 0;
        var forbidden:Function = function():Void { _root.legacyProbeExecuted++; };
        var timer:Object = org.flashNight.neur.Timer.FrameTimer.getInstance();
        timer.addTask(forbidden); timer.update();
        var wheel:Object = org.flashNight.neur.ScheduleTimer.CooldownWheel.I();
        wheel.add(1, forbidden); wheel.tick();
        var enhanced:Object = org.flashNight.neur.ScheduleTimer.EnhancedCooldownWheel.I();
        var first:Number = enhanced.addTask(forbidden, 33, false);
        var second:Number = enhanced.addDelayedTask(1, forbidden);
        enhanced.add(1, forbidden);
        enhanced.addOrUpdateTask({}, "candidateProbe", forbidden, 33, true);
        enhanced.reset(); enhanced.addDelayedTask(1, forbidden);
        timer.destroy(); timer = org.flashNight.neur.Timer.FrameTimer.getInstance();
        timer.addTask(forbidden); timer.update();
        wheel.reset(); wheel.add(1, forbidden);
        // Deliberate runtime bypass probe: AS2 private access is a compiler rule,
        // not an input capability boundary. The installed denial must still hold.
        var legacyKeys:Object = org.flashNight.arki.key.KeyManager;
        legacyKeys["pollKeys"]();
        _global.__cf7InputIsolationBootstrapV1.mode = "legacy";
        delete _global.__cf7InputIsolationBootstrapV1;
        wheel.tick(); wheel.tick();
        emit("LEGACY_TASKS_DENIED", {executed:_root.legacyProbeExecuted, taskId:first, delayedId:second,
            bootstrapMode:_global.__cf7InputIsolationBootstrapV1.mode,
            keyPollPresent:typeof _root.keyPollMC.onEnterFrame == "function",
            frameTimerPresent:typeof _root.__FRAME_TIMER_INSTANCE__.onEnterFrame == "function",
            cooldownDriverPresent:typeof _root._cdWheel.onEnterFrame == "function",
            policy:org.flashNight.arki.input.IsolatedInputPolicy.snapshot()}); return;
    }
    if (p.op == "QUERY") { org.flashNight.arki.ui.PlasticSurgeryPanelService.handle("query", p); return; }
    if (p.op == "DENY_PROBE") {
        var initial:Object = org.flashNight.arki.ui.PlasticSurgeryPanelService.execute("snapshot", {v:1});
        var result:Object = org.flashNight.arki.ui.PlasticSurgeryPanelService.execute("commit", {v:1, token:initial.token,
            draft:{characterName:"不应写入", gender:"female", height:180}});
        emit("WRITE_DENIED", {error:result.error, name:_root.角色名, balance:_root.虚拟币, persistenceInstalled:_root.存档系统 != undefined}); return;
    }
    if (p.op == "RAW_OPENER_PROBE") { emit("RAW_OPENER_RESULT", {accepted:_root.打开整形手术()}); return; }
    if (!granted || !positive(p.sequence) || p.sequence <= sequence) { emit("closed_rejected", {}); return; }
    sequence = p.sequence;
    if (p.op == "BEGIN") {
        if (held != null || p.button !== 1 || !positive(p.gesture) || !targetHit(p)) return;
        held = {gesture:p.gesture, button:1, begin:p.sequence, identity:targetIdentity}; emit("BEGIN", {gesture:p.gesture}); return;
    }
    if (p.op == "END") {
        if (held == null || p.gesture !== held.gesture || p.begin !== held.begin || p.button !== held.button || held.identity !== targetIdentity || !targetHit(p)) {
            held = null; emit("end_miss", {op:"END", gesture:p.gesture, begin:p.begin}); return;
        }
        // Freeze the completed gesture into the real opener request BEFORE the
        // Host revokes this epoch. No retry replays the old Down/End.
        openIntent = {session:session, coverage:coverage, epoch:epoch, ticket:ticket, geometry:geometry,
            scope:"M", incarnation:1, gesture:held.gesture, begin:held.begin, end:p.sequence};
        held = null; _root.打开整形手术();
        // A real opener that did not emit panel_request still resolves this END.
        if (openIntent != null) { emit("end_no_intent", {op:"END", gesture:openIntent.gesture, begin:openIntent.begin}); openIntent = null; }
        return;
    }
}
wire.onConnect = function(value:Boolean):Void { online = value; if (value) emit("BOOT", {closed:true}); };
wire.onClose = function():Void { online = false; granted = prepared = false; held = openIntent = preparedPrefix = null; };
wire.onData = function(value:String):Void { if (value.length <= 16384) command(codec.parse(value)); };
wire.connect("127.0.0.1", 32188);
