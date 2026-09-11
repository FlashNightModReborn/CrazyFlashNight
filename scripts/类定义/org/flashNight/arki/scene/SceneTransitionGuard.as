/** 共享淡出时间线的清场前校验，以及旧开门动画与延迟清场的兼容边界。 */
class org.flashNight.arki.scene.SceneTransitionGuard {
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
