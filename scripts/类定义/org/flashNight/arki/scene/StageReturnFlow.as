/** 返回目的地与真实到达的进程内身份。绝不持久化自动导航意图。 */
class org.flashNight.arki.scene.StageReturnFlow {
    private static var _origin:Object;
    private static var _selected:Object;
    private static var _story;
    private static var _transition:Object;
    private static var _arrivedIdentity:Object;
    private static var _restoreIdentity:Object;
    private static var _restoring:Boolean = false;
    private static var _seq:Number = 0;

    public static function reset():Void {
        _origin = _selected = _transition = _arrivedIdentity = undefined;
        _story = undefined;
        _restoreIdentity = worldIdentity(_root.gameworld);
        _restoring = false;
    }
    /** AVM1 会将被卸载的 MovieClip 引用重指向同路径新实例；身份必须是普通对象快照。 */
    public static function worldIdentity(world:Object):Object {
        if (world == undefined) return undefined;
        if (world.__stageReturnWorldIdentity == undefined) world.__stageReturnWorldIdentity = {};
        return world.__stageReturnWorldIdentity;
    }
    public static function captureOrigin():Object {
        if (_root.当前为战斗地图 === true || _root.gameworld == undefined) return undefined;
        var frame = _root.gameworld.场景名;
        if (typeof frame == "string" && frame.indexOf("基地场景-") == 0) frame = frame.substr(5);
        if (typeof frame != "string" || frame == "") frame = _root.关卡标志;
        if ((typeof frame != "string" || frame == "") && typeof frame != "number") return undefined;
        if (frame == "基地地图" || frame == "外部地图" || frame == "无限过图") return undefined;
        return {frame:frame};
    }
    public static function begin(origin:Object):Void {
        reset();
        _origin = origin;
    }
    public static function originFrame() { return _origin == undefined ? undefined : _origin.frame; }
    public static function setStoryReturn(frame):Void { _story = frame; }
    public static function hasStoryReturn():Boolean { return _story != undefined && _story != ""; }
    public static function select(plan:Object):Void { _selected = plan; }
    public static function destination(fallback) {
        if (hasStoryReturn()) return _story;
        if (_selected != undefined) return _selected.frame;
        if (_origin != undefined) return _origin.frame;
        return fallback;
    }
    public static function prepareTransition(frame):String {
        _seq++;
        var token:String = "stage.return." + _seq + "." + getTimer();
        _transition = {token:token, run:org.flashNight.arki.scene.StageRunSession.getRunAuthority(),
            oldIdentity:worldIdentity(_root.gameworld), frame:frame, accepted:false, loading:false};
        _arrivedIdentity = undefined;
        return token;
    }
    public static function acceptTransition(token:String):Void {
        if (_transition.token === token) _transition.accepted = true;
    }
    public static function cancelTransition(token:String):Void {
        if (_transition.token === token && !_transition.accepted) _transition = undefined;
    }
    /** 加载失败页的明确返回按钮：奖励已冻结，重新绑定加载身份而不重做结算。 */
    public static function returnFromLoadFailure(fallback):Boolean {
        if (_transition == undefined) return _root.淡出动画.淡出跳转帧(fallback) === true;
        var previous:Object = _transition;
        if (previous.run !== org.flashNight.arki.scene.StageRunSession.getRunAuthority()) return false;
        var frame = previous.frame == "医务室" ? "医务室"
            : hasStoryReturn() ? _story : _origin != undefined ? _origin.frame : fallback;
        var token:String = prepareTransition(frame);
        try {
            if (_root.淡出动画.淡出跳转帧(frame, token) !== true) {
                _transition = previous; return false;
            }
        } catch (error) { _transition = previous; return false; }
        acceptTransition(token);
        _selected = undefined;
        return true;
    }
    /** 淡出清场前先检查；只有实际跳图时才进入 loading。 */
    public static function canBeginSceneLoad(token:String, frame):Boolean {
        if (_transition == undefined) return token == undefined || token == "";
        if (_transition.token !== token || _transition.frame !== frame
            || !_transition.accepted || _transition.run !== org.flashNight.arki.scene.StageRunSession.getRunAuthority()) return false;
        return true;
    }
    public static function beginSceneLoad(token:String, frame):Boolean {
        if (!canBeginSceneLoad(token, frame)) return false;
        if (_transition == undefined) return true;
        _transition.loading = true;
        return true;
    }
    public static function sceneInit(sceneName:String):Object {
        var data:Object = {场景名:sceneName, __stageReturnWorldIdentity:{}};
        if (_transition != undefined && _transition.loading && matchesScene(sceneName, _transition.frame))
            data.__stageReturnToken = _transition.token;
        return data;
    }
    private static function matchesScene(sceneName:String, frame):Boolean {
        if (typeof frame == "number") return _root.关卡标志 === frame && _root._currentframe === frame;
        return sceneName === frame || sceneName === "基地场景-" + frame;
    }
    public static function restorePending():Void {
        reset();
        _restoring = true;
    }
    public static function confirmArrival(world:Object, token:String, readyIdentity:Object):Boolean {
        if (_root.当前为战斗地图 === true) return false;
        var currentIdentity:Object = worldIdentity(_root.gameworld);
        // readyIdentity 在加载人物前捕获；不能在消费迟到事件时重新读取 MovieClip 的属性。
        if (world != undefined && (world !== _root.gameworld || readyIdentity == undefined
                || readyIdentity !== currentIdentity)) return false;
        // 已确认场景的显式「继续领取」不需要新 SceneReady，但重建后的同路径场景不能复用。
        if (_arrivedIdentity != undefined) {
            if (_arrivedIdentity === currentIdentity) return true;
            if (world == undefined) return false;
        }
        if (_transition == undefined) {
            if (!_restoring) { _arrivedIdentity = currentIdentity; return true; } // 无本轮返回的旧非关卡调用保持兼容。
            if (world == undefined || readyIdentity === _restoreIdentity) return false;
        } else {
            if (!_transition.accepted || !_transition.loading || world == undefined
                || readyIdentity === _transition.oldIdentity
                || _transition.run !== org.flashNight.arki.scene.StageRunSession.getRunAuthority()
                || token !== _transition.token || world.__stageReturnToken !== token
                || !matchesScene(String(world.场景名), _transition.frame)) return false;
        }
        _arrivedIdentity = currentIdentity;
        _restoring = false;
        // 淡出 MovieClip 跨场景复用；旧门动画会直接播放它，不能遗留已消费的返回令牌。
        // 只释放本轮令牌，迟到的 SceneReady 不得覆盖后续转场。
        if (_transition != undefined && _root.淡出动画.__stageReturnToken === _transition.token)
            _root.淡出动画.__stageReturnToken = undefined;
        _selected = _transition = undefined;
        return true;
    }
}
