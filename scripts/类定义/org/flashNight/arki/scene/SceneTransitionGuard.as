/** 共享淡出时间线的清场前校验，以及旧开门动画与延迟清场的兼容边界。 */
class org.flashNight.arki.scene.SceneTransitionGuard {
    private static var _leeStageWatch:MovieClip;
    private static var _leeStagePending:Object;
    /** 业务转场身份属于根对象；加载幕本身的重建不代表关卡请求已经换人。 */
    public static function beginNavigation(root:Object):Void {
        root.__leeStageNavigationIdentity = {};
        if (_leeStagePending != undefined && _leeStagePending.root === root)
            stopLeeStage(_leeStagePending,"navigation_replaced");
    }
    private static function navigationIdentity(root:Object):Object {
        if (root.__leeStageNavigationIdentity == undefined) root.__leeStageNavigationIdentity = {};
        return root.__leeStageNavigationIdentity;
    }
    /** 同一槽位的规范化副本必须携带完全相同的持久旅程身份。 */
    private static function ownsLeeRun(root:Object, pending:Object):Boolean {
        var current:Object = root._saveExt.bookRun;
        if (current.bookId !== "lee-trial" || current.outcome !== "active"
                || current.slot !== pending.slot || String(root.savePath) !== pending.slot
                || current.seed !== pending.seed || current.originSlot !== pending.originSlot
                || current.startedAt !== pending.startedAt) return false;
        if (current === pending.run) return true;
        return typeof pending.seed == "number" && !isNaN(pending.seed)
            && typeof pending.originSlot == "string" && pending.originSlot.length > 0
            && typeof pending.startedAt == "number" && pending.startedAt > 0;
    }
    /** 原第17帧自行释放初始化占用；接续不得提前清掉此标记。 */
    private static function stageAdmissionReady(root:Object):Boolean {
        return root.场景转换中 !== true && root.淡出动画.__returnFadeActive !== true;
    }
    /** 快速重入可先到达世界load，再到淡出第17帧；此时保留原准入凭据等待。 */
    public static function initializeStage(root:Object, manager:Object):Void {
        var run:Object = root._saveExt.bookRun;
        if (run.bookId === "lee-trial" && run.outcome === "active"
                && run.slot === String(root.savePath) && !stageAdmissionReady(root)) {
            var pending:Object = captureLeeStage(root,manager);
            if (pending != undefined) armLeeStage(root,pending,"waiting_admission");
            return;
        }
        manager.initStage();
    }
    private static function armLeeStage(root:Object, pending:Object, state:String):Void {
        if (_leeStageWatch == undefined || _leeStageWatch._name == undefined || _leeStageWatch._parent !== root)
            _leeStageWatch = root.createEmptyMovieClip("__leeStageLoadHandoff", root.getNextHighestDepth());
        _leeStagePending = pending;
        _leeStageWatch.__leeStageLoadState = state;
        _leeStageWatch.onEnterFrame = org.flashNight.arki.scene.SceneTransitionGuard.continueLeeStage;
    }
    /** 基地由根时间线定位器的 onLoad 创建；同一显示帧不会再次触发 onLoad。 */
    public static function rememberBaseSceneFrame(root:Object, scene:String):Void {
        if (scene.indexOf("基地场景-") == 0) root.__baseSceneFrame = Number(root._currentframe);
    }
    public static function rememberSharedSceneFrame(root:Object, scene:String):Void {
        rememberBaseSceneFrame(root,scene);
        if (scene === "wuxianguotu_1") {
            root.__leeBattleSceneFrame = Number(root._currentframe);
        }
    }
    /** 在离开旧根帧之前登记；load 内创建的回调可能随定位器卸载而失去执行上下文。 */
    public static function watchLeeStageNavigation(root:Object, manager:Object, frame:Number):Boolean {
        var run:Object = root._saveExt.bookRun;
        var projection:Object = root.淡出动画.__transitionProjectionIdentity;
        if (run.bookId !== "lee-trial" || run.outcome !== "active"
                || run.slot !== String(root.savePath) || root.gameworld != undefined
                || projection == undefined || !(frame > 0) || manager.isActive !== true
                || manager.isFailed === true || manager.isFinished === true) return false;
        var pending:Object = {root:root, run:run, slot:String(root.savePath), projection:projection,
            navigation:navigationIdentity(root), seed:run.seed, originSlot:run.originSlot, startedAt:run.startedAt,
            manager:manager, stage:manager.currentStage, frame:frame, waited:0, claimed:false};
        armLeeStage(root,pending,"waiting_world");
        return true;
    }
    private static function stopLeeStage(pending:Object, state:String):Void {
        if (_leeStagePending !== pending) return;
        _leeStagePending = undefined;
        delete _leeStageWatch.onEnterFrame;
        _leeStageWatch.__leeStageLoadState = state;
        var root:Object = pending.root;
        var current:Object = root._saveExt.bookRun;
        _leeStageWatch.__leeStageLoadProbe = {state:state,
            sameRunReference:current === pending.run, sameRun:ownsLeeRun(root,pending),
            sameNavigation:root.__leeStageNavigationIdentity === pending.navigation,
            sameProjection:root.淡出动画.__transitionProjectionIdentity === pending.projection,
            active:pending.manager.isActive, failed:pending.manager.isFailed, finished:pending.manager.isFinished,
            stage:pending.manager.currentStage, expectedStage:pending.stage, frame:Number(root._currentframe)};
    }
    public static function captureLeeStage(root:Object, manager:Object):Object {
        var run:Object = root._saveExt.bookRun;
        var world:Object = root.gameworld;
        var projection:Object = root.淡出动画.__transitionProjectionIdentity;
        if (run.bookId !== "lee-trial" || run.outcome !== "active"
                || run.slot !== String(root.savePath) || world == undefined
                || world.场景名 !== "wuxianguotu_1" || projection == undefined
                || root.当前为战斗地图 === true || manager.isActive !== true
                || manager.isFailed === true || manager.isFinished === true) return undefined;
        return {root:root, run:run, slot:String(root.savePath), projection:projection,
            navigation:navigationIdentity(root), seed:run.seed, originSlot:run.originSlot, startedAt:run.startedAt,
            world:org.flashNight.arki.scene.StageReturnFlow.worldIdentity(world),
            manager:manager, stage:manager.currentStage, frame:Number(root._currentframe), waited:0, worldAt:0, claimed:false};
    }
    public static function completeLeeStage(root:Object, manager:Object, pending:Object):Boolean {
        if (pending == undefined || pending.claimed === true || pending.manager !== manager
                || !stageAdmissionReady(root)
                || !ownsLeeRun(root,pending)
                || pending.navigation !== root.__leeStageNavigationIdentity
                || pending.frame !== Number(root._currentframe)
                || pending.world !== org.flashNight.arki.scene.StageReturnFlow.worldIdentity(root.gameworld)
                || root.gameworld.场景名 !== "wuxianguotu_1"
                || pending.run.bookId !== "lee-trial" || pending.run.slot !== pending.slot
                || pending.run.outcome !== "active" || root.当前为战斗地图 === true
                || manager.isActive !== true || manager.isFailed === true || manager.isFinished === true
                || manager.currentStage !== pending.stage) return false;
        // 先消费一次性凭据。initStage 自己完成 run admission/失败收口，不重放失败的初始化。
        pending.claimed = true;
        trace("[LeeStageLoadHandoff] init stage=" + pending.stage + " slot=" + pending.slot);
        manager.initStage();
        return true;
    }
    public static function continueLeeStage():Void {
        var pending:Object = _leeStagePending;
        if (pending == undefined) { delete _leeStageWatch.onEnterFrame; return; }
        var root:Object = pending.root;
        var manager:Object = pending.manager;
        pending.waited++;
        if (!ownsLeeRun(root,pending) || pending.navigation !== root.__leeStageNavigationIdentity
                || manager.isActive !== true || manager.isFailed === true || manager.isFinished === true) {
            stopLeeStage(pending,"context_changed"); return;
        }
        if (manager.currentStage !== pending.stage || root.当前为战斗地图 === true) {
            stopLeeStage(pending,"native_initialized"); return;
        }
        if (pending.waited > 120) { stopLeeStage(pending,"world_timeout"); return; }
        var world:Object = root.gameworld;
        if (Number(root._currentframe) !== pending.frame || world == undefined
                || world.场景名 !== "wuxianguotu_1" || world.dispatcher == undefined) return;
        var identity:Object = org.flashNight.arki.scene.StageReturnFlow.worldIdentity(world);
        if (pending.world == undefined) {
            pending.world = identity; pending.worldAt = pending.waited;
            _leeStageWatch.__leeStageLoadState = "world_observed";
            return;
        }
        if (pending.world !== identity) { stopLeeStage(pending,"world_replaced"); return; }
        if (pending.waited - pending.worldAt < 2) return;
        if (!stageAdmissionReady(root)) {
            _leeStageWatch.__leeStageLoadState = "waiting_admission";
            return;
        }
        stopLeeStage(pending,"initializing");
        var completed:Boolean = completeLeeStage(root,manager,pending);
        _leeStageWatch.__leeStageLoadState = completed ? "initialized" : "rejected";
    }
    /** 仅本次Lee临时槽可跳过重复入场的多帧加载段，其他战斗入口不变。 */
    public static function observedSharedSceneFrame(root:Object, targetFrame:String):Number {
        if (targetFrame === "基地地图") return observedBaseSceneFrame(root,targetFrame);
        var run:Object = root._saveExt.bookRun;
        return targetFrame === "wuxianguotu_1" && run.bookId === "lee-trial"
            && run.outcome === "active" && run.slot === String(root.savePath)
            && typeof root.__leeBattleSceneFrame == "number" && root.__leeBattleSceneFrame > 0
            && root.gameworld == undefined ? root.__leeBattleSceneFrame : 0;
    }
    public static function observedBaseSceneFrame(root:Object, targetFrame:String):Number {
        return targetFrame === "基地地图" && typeof root.__baseSceneFrame == "number"
            && root.__baseSceneFrame > 0 && root.gameworld == undefined ? root.__baseSceneFrame : 0;
    }
    public static function canReloadBaseScene(root:Object, targetFrame:String):Boolean {
        var frame:Number = observedBaseSceneFrame(root,targetFrame);
        return frame > 0 && root._currentframe === frame;
    }
    /** 旧门元件仍在动画结束时直接 gotoAndPlay(2)，因此在开门前登记普通转场。 */
    public static function prepareDoor(frame):Boolean {
        var fade:Object = _root.淡出动画;
        if (fade == undefined || fade.跳转中标签 || fade.__returnFadeActive === true
                || frame == undefined || frame == ""
                || !org.flashNight.arki.scene.StageReturnFlow.canBeginSceneLoad(undefined, frame)) return false;
        fade.__sceneCleanupTicket = undefined;
        fade.__stageReturnToken = undefined;
        fade.__returnFadeActive = true;
        fade.跳转中 = true;
        fade.跳转帧 = frame;
        return true;
    }
    public static function captureCleanup():Object {
        var fade:Object = _root.淡出动画;
        if (fade == undefined) return undefined;
        var ticket:Object = {frame:fade.跳转帧, token:fade.__stageReturnToken, pausedFrame:fade._currentframe,
            worldIdentity:org.flashNight.arki.scene.StageReturnFlow.worldIdentity(_root.gameworld)};
        // 普通 Object 身份不会像 MovieClip 引用那样重指向同路径的新实例。
        fade.__sceneCleanupTicket = ticket;
        return ticket;
    }
    public static function ownsFade(ticket:Object):Boolean {
        var fade:Object = _root.淡出动画;
        return ticket != undefined && fade != undefined && fade.__sceneCleanupTicket === ticket
            && fade.跳转帧 === ticket.frame && fade.__stageReturnToken === ticket.token
            && fade._currentframe === ticket.pausedFrame;
    }
    public static function isCurrent(ticket:Object):Boolean {
        return ownsFade(ticket)
            && org.flashNight.arki.scene.StageReturnFlow.worldIdentity(_root.gameworld) === ticket.worldIdentity;
    }
    /** 无效请求停在清场之前，保留当前世界并撤下遮罩；旧重试则直接失效。 */
    public static function allowCleanup(ticket:Object):Boolean {
        if (!isCurrent(ticket)) return false;
        if (org.flashNight.arki.scene.StageReturnFlow.canBeginSceneLoad(ticket.token, ticket.frame)) return true;
        var fade:Object = _root.淡出动画;
        fade.__sceneCleanupTicket = undefined;
        fade.__returnFadeActive = false;
        fade.跳转中 = false;
        fade.__stageReturnToken = undefined;
        fade.gotoAndStop("空");
        var diagnostic:String = "[SceneTransition] cleanup_rejected frame=" + ticket.frame + " token=" + ticket.token;
        trace(diagnostic);
        if (typeof _root.服务器.发布服务器消息 == "function") _root.服务器.发布服务器消息(diagnostic);
        if (typeof _root.发布消息 == "function") _root.发布消息("场景切换已取消，请重新尝试。");
        return false;
    }
}
