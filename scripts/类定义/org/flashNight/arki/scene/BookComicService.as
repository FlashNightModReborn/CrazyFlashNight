import org.flashNight.arki.pause.PauseManager;
import org.flashNight.arki.interaction.NativeInteractionContext;
import org.flashNight.arki.scene.StageReturnFlow;

/** Web 漫画只呈现；场景身份、暂停和一次性续演始终由游戏持有。 */
class org.flashNight.arki.scene.BookComicService {
    private static var _installed:Boolean = false;
    private static var _seq:Number = 0;
    private static var _active:Object;
    private static var _records:Object;
    private static var _order:Array;
    private static var _watch:MovieClip;

    public static function install():Void {
        if (_installed) return;
        _installed = true;
        _records = {}; _order = [];
        PauseManager.install();
        NativeInteractionContext.install();
        NativeInteractionContext.onSceneTeardown(onSceneTeardown);
        if (_root.gameCommands == undefined) _root.gameCommands = {};
        _root.gameCommands["bookComicPrepared"] = function(p:Object):Void {
            org.flashNight.arki.scene.BookComicService.handle("prepared", p);
        };
        _root.gameCommands["bookComicFinish"] = function(p:Object):Void {
            org.flashNight.arki.scene.BookComicService.handle("finish", p);
        };
    }

    /** 返回 true 即接管续演义务；即使发送同步失败也只消费一次。 */
    public static function begin(pageId:String, continuation:Function):Boolean {
        install();
        var run:Object = _root._saveExt.bookRun;
        var server:Object = _root.server;
        if (_active != null || (pageId != "prologue" && pageId != "boss")
                || run == null || run.outcome != "active" || run.slot !== String(_root.savePath)
                || _root.gameworld == undefined || server.isSocketConnected !== true
                || typeof server.sendTaskWithCallback != "function") return false;
        var s:Object = {v:1, presentationId:"bookcomic:" + (++_seq), slot:String(_root.savePath),
            sceneId:NativeInteractionContext.getSceneId(), pageId:pageId, panelInstanceId:"",
            owner:StageReturnFlow.worldIdentity(_root.gameworld), run:run,
            phase:"opening", began:getTimer(), continuation:continuation};
        s.lease = PauseManager.lease(true, "book_comic");
        _active = s; _records[s.presentationId] = s; _order.push(s.presentationId);
        if (_order.length > 32) delete _records[String(_order.shift())];
        ensureWatch();
        server.sendTaskWithCallback("panel_request", {panel:"book-comic", source:"book_chapter",
            initData:{v:1, presentationId:s.presentationId, slot:s.slot, sceneId:s.sceneId, pageId:s.pageId}},
            null, admissionCallback(s), 20000);
        return true;
    }
    // 参数捕获工厂避免帧脚本卸载和 AS2 局部寄存器复用影响迟到回调。
    private static function admissionCallback(s:Object):Function {
        return function(reply:Object):Void {
            org.flashNight.arki.scene.BookComicService.admitted(s, reply);
        };
    }
    private static function admitted(s:Object, reply:Object):Void {
        if (_active !== s || s.phase != "opening") return;
        if (!current(s)) { expire(s, false, "scene_changed"); return; }
        if (reply.success !== true || reply.accepted !== true || reply.panel !== "book-comic"
                || reply.presentationId !== s.presentationId) expire(s, true, "open_failed");
    }
    private static function current(s:Object):Boolean {
        return s != null && s.slot === String(_root.savePath) && s.run === _root._saveExt.bookRun
            && s.run.outcome == "active" && s.owner != undefined
            && s.owner === StageReturnFlow.worldIdentity(_root.gameworld)
            && s.sceneId === NativeInteractionContext.getSceneId();
    }
    private static function valid(p:Object):Boolean {
        return p != null && p.v === 1 && typeof p.callId == "number" && p.callId > 0
            && p.callId < 2147483647 && Math.floor(p.callId) == p.callId
            && typeof p.presentationId == "string" && p.presentationId.length <= 80
            && typeof p.slot == "string" && p.slot.length > 0 && p.slot.length <= 160
            && typeof p.sceneId == "string" && p.sceneId.length > 0 && p.sceneId.length <= 160
            && (p.pageId === "prologue" || p.pageId === "boss")
            && typeof p.panelInstanceId == "string" && p.panelInstanceId.length > 0 && p.panelInstanceId.length <= 160;
    }
    private static function matches(s:Object, p:Object):Boolean {
        return s != null && s.presentationId === p.presentationId && s.slot === p.slot
            && s.sceneId === p.sceneId && s.pageId === p.pageId
            && (s.panelInstanceId == "" || s.panelInstanceId === p.panelInstanceId);
    }
    public static function handle(operation:String, p:Object):Void {
        if (!valid(p) || (operation != "prepared" && operation != "finish")) return;
        var s:Object = _records[p.presentationId];
        if (!matches(s, p)) { respond(p, operation, false, "expired", "stale_identity"); return; }
        if (s.phase == "finished" || s.phase == "expired") {
            // 旧身份只能确认自己的终态，绝不绑定或关闭后来打开的漫画。
            respond(p, operation, true, s.phase, ""); return;
        }
        if (s !== _active || !current(s)) {
            expire(s, false, "scene_changed");
            respond(p, operation, true, "expired", ""); return;
        }
        if (operation == "prepared") {
            if (s.panelInstanceId == "") s.panelInstanceId = p.panelInstanceId;
            s.phase = "presenting";
            respond(p, operation, true, "presenting", "");
            return;
        }
        var reason:String = p.reason;
        if (reason != "continue" && reason != "skip" && reason != "closed" && reason != "failed") {
            respond(p, operation, false, s.phase, "invalid_reason"); return;
        }
        // 加载失败或关窗可能发生在 prepared 之前，仍需绑定并释放本次责任。
        if (s.panelInstanceId == "") s.panelInstanceId = p.panelInstanceId;
        var follow:Function = retire(s, reason == "failed" ? "expired" : "finished", true);
        respond(p, operation, true, s.phase, "");
        if (follow != null) follow();
    }
    private static function respond(p:Object, operation:String, success:Boolean, phase:String, error:String):Void {
        var server:Object = _root.server;
        if (server.isSocketConnected !== true || typeof server.sendTaskToNode != "function") return;
        server.sendTaskToNode("book_comic_response", {callId:p.callId, v:1,
            presentationId:p.presentationId, slot:p.slot, sceneId:p.sceneId, pageId:p.pageId,
            panelInstanceId:p.panelInstanceId, operation:operation, success:success, phase:phase, error:error}, null);
    }
    private static function retire(s:Object, phase:String, resume:Boolean):Function {
        if (s.phase == "finished" || s.phase == "expired") return null;
        var follow:Function = resume && current(s) ? s.continuation : null;
        s.phase = phase; s.continuation = null;
        if (_active === s) _active = null;
        PauseManager.releaseLease(s.lease); s.lease = undefined;
        return follow;
    }
    private static function expire(s:Object, resume:Boolean, reason:String):Void {
        if (s == null || s.phase == "finished" || s.phase == "expired") return;
        var follow:Function = retire(s, "expired", resume);
        // callId 0 是游戏主动退休；prepared 前 panelInstanceId 尚未分配。
        respond({callId:0, presentationId:s.presentationId, slot:s.slot, sceneId:s.sceneId,
            pageId:s.pageId, panelInstanceId:s.panelInstanceId}, "finish", true, "expired", reason);
        trace("[BookComic] expired " + s.presentationId + " " + reason);
        if (follow != null) follow();
    }
    private static function onSceneTeardown():Void { expire(_active, false, "scene_changed"); }
    public static function onTransportDisconnected():Void { expire(_active, true, "disconnected"); }
    private static function ensureWatch():Void {
        if (_watch == null || _watch._name == undefined)
            _watch = _root.createEmptyMovieClip("__bookComicLifecycle", _root.getNextHighestDepth());
        _watch.onEnterFrame = function():Void { org.flashNight.arki.scene.BookComicService.tick(); };
    }
    public static function tick():Void {
        var s:Object = _active;
        if (s == null) { delete _watch.onEnterFrame; return; }
        if (!current(s)) { expire(s, false, "scene_changed"); return; }
        if (s.phase == "opening" && getTimer() - s.began >= 30000) expire(s, true, "prepare_timeout");
    }
}
