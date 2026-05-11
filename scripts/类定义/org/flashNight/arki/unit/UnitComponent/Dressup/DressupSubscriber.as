/**
 * DressupSubscriber - dressup 事件订阅意图 API
 *
 * 把 unit.syncRefs[key] = true + unit.dispatcher.subscribe(key, fn) 的两步协议
 * 合并成单次意图调用，避免"只置 syncRefs 不订阅"或"只订阅不置 syncRefs"的孤儿写法
 *（后者让 publish 永不触发，因为 doConfig 检查 syncRefs 决定是否广播）。
 *
 * 通道语义详见 DressupReferenceManager 类头与 agentsDoc/as2-load-timing.md。
 *
 * 三个通道对应三个静态方法，全部为 init-time 调用，性能可忽略：
 *   onReady     → "<refName>:ready"        deferred (load-fully-ready)
 *   onPlacement → "<refName>"              sync (placement-ready)
 *   onRefreshed → "dressup:refreshed"      group (refreshAll done)
 */
class org.flashNight.arki.unit.UnitComponent.Dressup.DressupSubscriber {

    /**
     * Deferred 通道 — 下一帧开头（render 之后）触发，比 onPlacement 晚 1 帧物理时间。
     * 仅在确实必要时用，否则会引入 1 帧视觉滞后。
     *
     * 何时必须用：
     *   - 回调要读子 MC 在自己 onClipEvent(load) 里**写入的字段**（如 child.弹药数 = N）
     *   - 回调要读子 MC 在 onLoad 内**嵌套 attachMovie** 出来的孙级
     *
     * 反例（应改用 onPlacement）：
     *   - 只读 placement 子树（含递归 grand-placement）的内置属性 _x/_y/_visible/_xscale
     *   - 只调 MovieClip 内置方法 gotoAndStop / localToGlobal
     *   placement 子树在 attachMovie 同步返回时就已就绪，sync 已够用
     */
    public static function onReady(unit:MovieClip, refName:String, handler:Function):Void {
        var key:String = refName + ":ready";
        unit.syncRefs[key] = true;
        unit.dispatcher.subscribe(key, handler);
    }

    /**
     * Sync 通道 — attach 完成立即触发，仍在调用栈内、当帧 render 之前。**默认选这个**。
     *
     * 可信读：
     *   - unit[refName] 引用本身及其 _x/_y/_visible/_parent
     *   - 递归 placement 子树（设计期 FLA 子级 / 孙级）的内置属性
     *   - MovieClip 内置方法（gotoAndStop / localToGlobal / removeMovieClip）
     * 不可信读：
     *   - 子 MC 在自己 onClipEvent(load) 里写入的字段（拿到 undefined）
     *   - 子 MC 的 onLoad 内嵌套 attachMovie 出来的孙级
     */
    public static function onPlacement(unit:MovieClip, refName:String, handler:Function):Void {
        unit.syncRefs[refName] = true;
        unit.dispatcher.subscribe(refName, handler);
    }

    /**
     * 组级 refresh 通道 — refreshAll 串行遍历完所有 entry 后 publish 一次。
     */
    public static function onRefreshed(unit:MovieClip, handler:Function):Void {
        unit.syncRefs["dressup:refreshed"] = true;
        unit.dispatcher.subscribe("dressup:refreshed", handler);
    }
}
