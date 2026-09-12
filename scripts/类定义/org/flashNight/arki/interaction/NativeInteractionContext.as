import org.flashNight.neur.Event.EventBus;

/**
 * org.flashNight.arki.interaction.NativeInteractionContext
 * native_interaction 通道（menu / tooltip 两路共用）的进程内共享上下文。
 *
 * 职责（刻意小型，无状态机）：
 *   1) sceneId：同一当前场景内所有通道取得同一不可复用代号；
 *      由 SceneChanged 事件驱动轮换。场景身份用 StageReturnFlow.worldIdentity
 *      的普通对象 token 判定，不用 MovieClip 引用相等（同路径重建会让旧引用
 *      重新指向新实例）。
 *   2) requestId：全局共享单调递增序号，精确形式 "ni:<正整数>"，menu/tooltip
 *      共用一个序号；场景切换不重置，仅完整启动会话重建（本类静态域重建，
 *      对应 Host 断线重置）才回 1。
 *   3) 场景切换顺序：先按注册序回调各通道 teardown（撤销/隐藏旧浮层），
 *      再轮换场景身份——避免另一通道的 show 被本侧误当成新场景请求。
 *
 * 接入：NativeMenuBridge.install() 内调用 install() 完成接线；
 *      NativeTooltipBridge 直接调用 getSceneId() / nextRequestId() /
 *      onSceneTeardown()，不另建一套场景号/计数。
 */
class org.flashNight.arki.interaction.NativeInteractionContext {
    private static var _installed:Boolean = false;
    private static var _sceneSeq:Number = 0;
    private static var _sceneId:String = "";
    private static var _sceneIdentity:Object = undefined;
    private static var _reqSeq:Number = 0;
    private static var _teardowns:Array = null;

    /** 幂等安装：订阅 SceneChanged。boot 注册或任一通道首用均可触发。 */
    public static function install():Void {
        if (_installed) return;
        _installed = true;
        _teardowns = [];
        rotateScene();
        EventBus.getInstance().subscribe("SceneChanged", onSceneChanged, NativeInteractionContext);
    }

    /** 当前场景不可复用代号（"ni.scene.<seq>.<timer>"）。 */
    public static function getSceneId():String {
        install();
        return _sceneId;
    }

    /** 当前场景普通对象身份 token；gameworld 不在位时为 undefined。 */
    public static function getSceneIdentity():Object {
        install();
        return _sceneIdentity;
    }

    /**
     * 传入世界是否仍属当前场景身份（供通道对迟到动作做活场景校验）。
     * world 为 undefined 或身份未捕获时一律 false（fail-closed）。
     */
    public static function isCurrentWorld(world:Object):Boolean {
        install();
        if (world == undefined) return false;
        var tok:Object = org.flashNight.arki.scene.StageReturnFlow.worldIdentity(world);
        if (_sceneIdentity == undefined) _sceneIdentity = tok; // 懒捕获：gameworld 就位早于首个 SceneChanged
        return tok === _sceneIdentity;
    }

    /** 全局共享递增请求号，精确形式 "ni:<正整数>"；跨场景不重置。 */
    public static function nextRequestId():String {
        install();
        _reqSeq++;
        return "ni:" + _reqSeq;
    }

    /**
     * 注册本通道的场景切换 teardown（先于身份轮换执行）。
     * 回调以 scope=null 调用；通道在内部完成「发 hide + 清待决」。
     */
    public static function onSceneTeardown(fn:Function):Void {
        install();
        if (fn == undefined) return;
        _teardowns.push(fn);
    }

    private static function onSceneChanged():Void {
        var arr:Array = _teardowns;
        if (arr != null) {
            for (var i:Number = 0; i < arr.length; i++) {
                arr[i].call(null);
            }
        }
        rotateScene();
    }

    private static function rotateScene():Void {
        _sceneSeq++;
        _sceneId = "ni.scene." + _sceneSeq + "." + getTimer();
        _sceneIdentity = org.flashNight.arki.scene.StageReturnFlow.worldIdentity(_root.gameworld);
    }
}
