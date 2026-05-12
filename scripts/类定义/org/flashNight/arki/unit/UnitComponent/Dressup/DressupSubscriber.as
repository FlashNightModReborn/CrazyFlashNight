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
 *
 * ============================================================================
 * § 使用指引（基于 2026-05-12 T9 实测）
 * ============================================================================
 *
 * 【默认选 onPlacement】
 *   doConfig 内 attachMovie 同步返回后 publish，handler 内可信读：
 *     - unit[refName] 引用本身（doConfig 已同步赋值）
 *     - 引用及其递归 placement 子树的 _x / _y / _xscale / _yscale / _visible / _parent
 *     - 子树 MovieClip 内置方法 (gotoAndStop / localToGlobal / removeMovieClip)
 *   对绝大多数 lifecycle 用法（视觉同步、坐标计算、动画推帧）足够。
 *   样例：scripts/逻辑/装备函数/电感切割刃.as（无门控架构）
 *
 * 【慎选 onReady】
 *   只有以下场景才用：
 *     1. 子 MC 在自己 onClipEvent(load) 内**写入了字段**（如 child.弹药数 = N）且 handler 需读它
 *     2. 子 MC 的 onLoad 内**嵌套 attachMovie** 产生孙级 MC，handler 需读孙级
 *   反例：纯 transform / localToGlobal / gotoAndStop —— placement 已足够
 *
 *   ★【时序漏洞】onReady 对 enterFrame-phase 触发的 refresh **延后 1 帧 fire**：
 *      高 depth handler (pickup/action/input) 同步触发 doConfig → onPlacement 同步 fire（关门）；
 *      同 enterFrame phase 内 _root.onEnterFrame (低 depth) 跑时 onReady 还没派发；
 *      因为 AS2 load flush 不在多 handler 间 interleave —— 整 phase 跑完才统一 flush。
 *      详见 agentsDoc/as2-load-timing.md 第 2.4 节 T9。
 *
 *   订阅方应对：
 *     - 输入驱动逻辑（瞬时事件，无法补触发）：要么改用 onPlacement，
 *       要么显式 loadReady 门控 + 接受首帧丢失
 *     - 状态驱动逻辑（可幂等补触发）：onReady handler 直接 apply state；
 *       门控对状态驱动可省，自然由下一帧 onReady 补齐
 *
 * 【避坑】祖先 transform 链不要用 onClipEvent(load) 写 _x/_y/_xscale ——
 *   这会让 localToGlobal 在 placement 阶段出错（被门控掩盖反而难诊断）。
 *   所有 transform 应来自 FLA-level PlaceObject 矩阵。
 *
 * ============================================================================
 * § stale-ref window —— 2026-05-12 主唱光剑 trace 实测确认
 * ============================================================================
 *
 * 现象：subscriber 读 unit[refName] 拿到 detached MovieClip（_parent==null），
 *   读其子级（如 saber.刀口位置3）= undefined，调 localToGlobal 不走 parent
 *   chain → 退化为接近 (0,0) 的坐标。视觉表现：子弹 / 特效在 (0,0) 出现，过
 *   几帧 timeline 重建完成后才"同步到主角"。
 *
 * 触发场景：
 *   - timeline 切帧（动作改变 / mc 层级改变）触发 FLA 自动 destroy 旧 holder mc
 *   - 旧 saber 跟着 detach (_parent=null)，但 unit[refName] 仍持有旧引用
 *   - 新 holder 的 onClipEvent(load) 尚未跑到 → 新 doConfig 未触发 swap
 *   - 这个 window 内任何 publish 都会让 subscriber 读 stale → 退化坐标
 *   - 实测高频触发态：兵器冲击（player 冲刺时跨越 timeline 切帧）
 *
 * Idiom A —— 静默跳过（适合可丢事件：视觉特效 / 提示音 / 累计 buff 等）：
 *   var ref:MovieClip = unit[refName];
 *   if (!ref || !ref._parent) return;
 *   // 后续可信读 ref / ref placement 子树
 *
 * Idiom B —— cache 回落（适合不可丢事件：玩家攻击判定 / 输入响应）：
 *   用 [[StaleRefCache]] 工具类，挂载方周期函数 snapshot()，订阅方 callback
 *   resolve()。两个调用各 1 行，三级回落由 class 内部封装：
 *     ① saber live → 精确算 / ② stale → 上次 snapshot / ③ 全失败返 null
 *   样例：scripts/逻辑/装备函数/主唱光剑.as 的"主唱光剑光刃"订阅；
 *         挂载方见 scripts/逻辑/装备函数/通用装备函数.as 通用特效刀口周期。
 *   误差边界：cache 滞后 ≤1 帧玩家位移（~10-15px @ 30fps），低于人眼帧间分辨。
 *
 * 选 Idiom A 还是 B：取决于该订阅事件**丢失**对玩家感知的代价：
 *   - 视觉补触发 / 状态推帧 → A：丢一帧无所谓，下次 doConfig 自然修复
 *   - 攻击判定 / 输入响应 → B：丢失=玩家觉得"操作没响应"，必须 cache 兜底
 *
 * ★ 不要试图在订阅者侧主动 "修复" stale —— 修复 (重 attach) 是
 *   DressupReferenceManager 的责任，订阅者只负责 stale 时回落。下一个
 *   doConfig 会重新 publish onPlacement，订阅者就能拿到 NEW skin。
 *
 * 源头截断（callback 挂载方共同约定）：每帧周期里挂 callback 到 unit[refName]
 *   的子级时，先验 unit[refName]._parent；stale 就清理外挂引用并 return，
 *   避免后续动作帧脚本通过外挂引用反向 publish。返回前**保留** cache 字段
 *   不清——Idiom B 的订阅者依赖它跨 stale window 提供回落坐标。
 *
 * ============================================================================
 *
 * 【scope 约定】EventBus v3 的精确退订/去重依赖 (callback, scope) 组合键。本 API 把
 * scope 默认设为 unit（fn.call(unit, ...) 让 handler 内的 this 指向 unit MovieClip），
 * 保证所有 dressup 订阅都走 EventBus 的精确模式而非 for...in 兼容回退模式。
 * 调用方无需显式传 scope；若需要更细粒度（如装备级 selective unsubscribe），可显式传 ref。
 */
class org.flashNight.arki.unit.UnitComponent.Dressup.DressupSubscriber {

    /**
     * Deferred 通道 — load flush 末尾触发；对 enterFrame-phase 触发的 refresh **延后 1 帧**。
     *
     * ★ 时序漏洞：T9 实测（2026-05-12，详见 agentsDoc/as2-load-timing.md 2.4 节）
     *   AS2 load flush 不在同 phase 多 handler 间 interleave。
     *   高 depth handler (pickup / action / input) 同步触发 doConfig 后，
     *   同 enterFrame phase 内 _root.onEnterFrame 跑时 onReady 还没派发。
     *   订阅方在此 phase 内的 `周期` 工作会读到"旧 ready 状态"。
     *
     * 何时必须用：
     *   - 回调要读子 MC 在自己 onClipEvent(load) 里**写入的字段**（如 child.弹药数 = N）
     *   - 回调要读子 MC 在 onLoad 内**嵌套 attachMovie** 出来的孙级
     *
     * 反例（应改用 onPlacement）：
     *   - 只读 placement 子树（含递归 grand-placement）的内置属性 _x/_y/_visible/_xscale
     *   - 只调 MovieClip 内置方法 gotoAndStop / localToGlobal
     *   placement 子树在 attachMovie 同步返回时就已就绪，sync 已够用且无 T9 漏洞
     *
     * @param scope 可选，省略时默认为 unit；handler 内 this 指向该 scope
     */
    public static function onReady(unit:MovieClip, refName:String, handler:Function, scope:Object):Void {
        var key:String = refName + ":ready";
        unit.syncRefs[key] = true;
        unit.dispatcher.subscribe(key, handler, (scope != undefined) ? scope : unit);
    }

    /**
     * Sync 通道 — attach 完成立即触发，仍在调用栈内、当帧 render 之前。**默认选这个**。
     *
     * 优势：无 T9 时序漏洞（详见类头 § 使用指引）。doConfig 同步赋值 unit[refName] +
     * 同步 publish，所有同 enterFrame phase 后续 handler 读到的是 NEW skin + placement
     * 就位状态。
     *
     * 可信读：
     *   - unit[refName] 引用本身及其 _x/_y/_visible/_parent
     *   - 递归 placement 子树（设计期 FLA 子级 / 孙级）的内置属性
     *   - MovieClip 内置方法（gotoAndStop / localToGlobal / removeMovieClip）
     * 不可信读：
     *   - 子 MC 在自己 onClipEvent(load) 里写入的字段（拿到 undefined）
     *   - 子 MC 的 onLoad 内嵌套 attachMovie 出来的孙级
     *
     * @param scope 可选，省略时默认为 unit；handler 内 this 指向该 scope
     */
    public static function onPlacement(unit:MovieClip, refName:String, handler:Function, scope:Object):Void {
        unit.syncRefs[refName] = true;
        unit.dispatcher.subscribe(refName, handler, (scope != undefined) ? scope : unit);
    }

    /**
     * 组级 refresh 通道 — refreshAll 串行遍历完所有 entry 后 publish 一次。
     *
     * @param scope 可选，省略时默认为 unit；handler 内 this 指向该 scope
     */
    public static function onRefreshed(unit:MovieClip, handler:Function, scope:Object):Void {
        unit.syncRefs["dressup:refreshed"] = true;
        unit.dispatcher.subscribe("dressup:refreshed", handler, (scope != undefined) ? scope : unit);
    }
}
