/**
 * 兵器攻击路由器 - 兵器攻击容器化支持
 *
 * 目的：将兵器攻击的"跳帧入口"收口到统一路由，
 *       通过主角-男的"容器"帧 attachMovie 容器元件，替代巨型影片剪辑 gotoAndPlay 的沿途 load/unload 开销。
 *       同时将 xml 中的 onClipEvent 代码迁移到 AS 文件，消除资产文件中的代码依赖。
 *
 * 依赖：
 * - 引擎_fs_路由基础.as（动画完毕/浮空兜底与旧资源兼容门面）
 * - RoutingIntent（状态切换作业机制、屏蔽旧man卸载、绑定容器结束写状态、同帧跳转保护）
 *
 * 架构说明：
 * - 所有路径统一使用"状态切换作业"机制：
 *   1. 拳刀行走状态机（man.onEnterFrame）触发 主角普攻连招开始()
 *   2. 设置 __stateTransitionJob（包含跳转帧覆盖和回调函数）
 *   3. 调用 状态改变("兵器攻击") -> gotoAndStop 会销毁 man
 *   4. 状态改变函数在 gotoAndStop 后执行作业回调
 *   （此机制解决了：man 被卸载后调用方后续代码无法执行的问题）
 *
 * - 容器化路径：跳转到"容器"帧，attachMovie 动态容器
 *
 * 约定：
 * - 普攻入口：主角行走状态机 -> 主角普攻连招开始(unit)
 * - 搓招入口：兵器攻击标签跳转(unit, 招式名)
 * - 容器元件最后一帧调用 `_root.兵器攻击路由.动画完毕(this, _parent)`
 *
 * 渐进式容器化的兼容实现参考已外移到 docs/路由系统-容器化兼容路径.md
 *
 * @author flashNight
 * @version 3.1 - API 收编：屏蔽旧man卸载/绑定容器结束写状态/同帧跳转保护/状态字符串常量集中
 */

import org.flashNight.arki.unit.UnitComponent.Routing.*;

_root.兵器攻击路由 = {};

// ============================================================================
// 状态切换作业回调（module-level named function，避免每次 producer 创建闭包）
// ============================================================================

/**
 * 状态切换作业回调：载入后跳转兵器攻击容器
 */
_root.兵器攻击路由.__job_载入后跳转 = function(u:MovieClip):Void {
    _root.兵器攻击路由.载入后跳转兵器攻击容器(u.container, u);
};

/**
 * 计算兵器普攻连招的首帧标签
 * - 对齐旧版巨型兵器攻击元件的启动逻辑：优先按 unit.兵器动作类型 拼接
 * - 无兵器动作类型时回退到 "1连招"
 *
 * @param unit:MovieClip 执行兵器攻击的单位
 * @return String 连招首帧标签（如 "刀剑1连招"）
 */
_root.兵器攻击路由.获取普攻连招首帧标签 = function(unit:MovieClip):String {
    if (unit.兵器动作类型) {
        return unit.兵器动作类型 + "1连招";
    }
    return "1连招";
};

/**
 * 主角-男：进入"兵器攻击"状态并加载"连招容器"
 * - 逻辑状态保持为 "兵器攻击"（兼容状态判定）
 * - 显示层跳转到 "容器" 帧（通过状态切换作业机制）
 * - 连招在单个容器内通过 gotoAndPlay 跳帧，不做"每段连招 attachMovie 新容器"
 *
 * 注意：本函数仅负责普攻连招容器化，不覆盖 "兵器冲击/跑攻"。
 *
 * @param unit:MovieClip 执行兵器攻击的单位
 */
_root.兵器攻击路由.主角普攻连招开始 = function(unit:MovieClip):Void {
    if (unit.兵种 !== "主角-男") {
        return;
    }

    var actionName:String = _root.兵器攻击路由.获取普攻连招首帧标签(unit);
    unit.兵器攻击名 = actionName;

    // 统一入口：状态改变会触发 gotoAndStop，然后执行作业回调
    // 注意：gotoAndStop 会卸载当前 man（拳刀行走状态机的执行上下文），后续代码不会执行
    RoutingIntent.triggerStateTransitionJob(
        unit,
        RoutingIntent.STATE_WEAPON,
        RoutingIntent.LABEL_CONTAINER,
        _root.兵器攻击路由.__job_载入后跳转,
        RoutingIntent.LABEL_CONTAINER
    );
};

/**
 * 兵器攻击标签跳转入口
 * - 主角-男：通过状态切换作业跳到"容器"帧，并在 gotoAndStop 后 attachMovie 对应容器
 * - 其他单位：维持旧逻辑（man.gotoAndPlay）
 *
 * @param unit:MovieClip 执行兵器攻击的单位
 * @param actionName:String 招式名（例如 "剑气释放"）
 */
_root.兵器攻击路由.兵器攻击标签跳转 = function(unit:MovieClip, actionName:String):Void {
    unit.兵器攻击名 = actionName;
    // 同帧跳转保护：搓招已触发新容器后，跳过旧容器本帧剩余的变招/后摇判定。
    RoutingIntent.markWeaponSameFrameJump(unit, _root.帧计时器.当前帧数);

    // 非主角-男：继续走旧man跳帧（不引入容器化状态依赖）
    if (unit.兵种 !== "主角-男") {
        if (unit.man != undefined) {
            unit.man.gotoAndPlay(actionName);
        }
        return;
    }

    // 切到"容器"帧会卸载旧man；旧man.onUnload 会写入"普攻结束/兵器攻击结束"。
    // 容器化切换阶段必须屏蔽该卸载回调（真正结束由新容器man卸载时统一处理）。
    RoutingIntent.suppressOldManUnload(unit);

    RoutingIntent.triggerStateTransitionJob(
        unit,
        RoutingIntent.STATE_WEAPON_CONTAINER,
        RoutingIntent.LABEL_CONTAINER,
        _root.兵器攻击路由.__job_载入后跳转,
        RoutingIntent.LABEL_CONTAINER
    );
};

/**
 * 构建兵器攻击容器初始化对象
 *
 * 实现：委派到 ContainerInitScratch.getWeapon(container) 的 singleton scratch，
 *       消除每次 new Object literal 的 GC 压力。
 *       装配字段对齐契约由 ContainerInitScratch 维护（含兵器专用移动函数、变招判定/
 *       刀口触发特效/兵器攻击、以及对齐 兵器攻击.xml 的搓招/派生函数集合）。
 *
 * @param container:MovieClip "容器"帧上的占位容器（用于获取位置和缩放）
 * @return Object 初始化参数对象（singleton scratch，attachMovie 同步消费后即可复用）
 */
_root.兵器攻击路由.构建兵器攻击容器初始化对象 = function(container:MovieClip):Object {
    return ContainerInitScratch.getWeapon(container);
};

/**
 * 容器化兵器攻击入口（从"兵器攻击容器"状态跳转到"容器"帧后调用）
 *
 * @param container:MovieClip "容器"帧上的占位容器
 * @param unit:MovieClip 执行兵器攻击的单位
 */
_root.兵器攻击路由.载入后跳转兵器攻击容器 = function(container:MovieClip, unit:MovieClip):MovieClip {
    var actionName:String = unit.兵器攻击名;
    var initObj:Object = _root.兵器攻击路由.构建兵器攻击容器初始化对象(container);
    var man:MovieClip = unit.attachMovie("兵器攻击容器-" + actionName, "man", 0, initObj);
    if (man == undefined) {
        return undefined;
    }

    // ========== 对齐原兵器攻击帧的 onClipEvent(load) 逻辑 ==========
    // 原逻辑位于 主角-男.xml 兵器攻击帧（index 618）

    // 1. 读取飞行状态（仅控制目标）
    if (unit._name == _root.控制目标) {
        unit.读取当前飞行状态();

        // 2. 上挑派生检测：按住B键时触发被动技能"上挑"跳转到"兵器跳"
        if (JumpDerivePredicate.shouldTrigger(unit.被动技能.上挑, unit.飞行浮空, Key.isDown(unit.B键))) {
            unit.跳横移速度 = unit.行走X速度;
            unit.跳跃中移动速度 = unit.行走X速度;
            unit.状态改变("兵器跳");
            // 已切换状态，移除刚创建的容器man
            man.removeMovieClip();
            return undefined;
        }
    }

    // 统一结束手感：动态man被卸载/移除时写入"普攻结束/兵器攻击结束"
    RoutingIntent.bindContainerEndState(man, unit, RoutingIntent.SMALL_END_WEAPON);

    man.gotoAndPlay(actionName);
    return man;
};

/**
 * 动画完毕处理（由容器元件末帧调用）
 *
 * 委派到 RoutingLifecycle.completeAnimation：站立常态下与"两行内联版"等价（清理浮空任务/在空中检测
 * 都是 no-op），但在边界情况（跨容器残留浮空标记 / 跳跃落地瞬间触发普攻）能走自然落地兜底，
 * 避免直接 removeMovieClip 留下不一致的 _y。
 *
 * 普攻不应启用二段跳，enableDoubleJump 固定传 false。
 *
 * @param man:MovieClip 当前容器化兵器攻击man
 * @param unit:MovieClip 执行兵器攻击的单位
 */
_root.兵器攻击路由.动画完毕 = function(man:MovieClip, unit:MovieClip):Void {
    RoutingLifecycle.completeAnimation(man, unit, false);
};
