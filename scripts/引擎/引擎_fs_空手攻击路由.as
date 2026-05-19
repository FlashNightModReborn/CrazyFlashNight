/**
 * 空手攻击路由器 - 空手普攻连招容器化支持（主角-男）
 *
 * 目的：
 * - 将"空手攻击"的连招入口收口到统一路由
 * - 通过"状态切换作业"机制，解决 onEnterFrame 调用链在 gotoAndStop 后上下文丢失导致后续逻辑无法执行的问题
 *
 * 约束：
 * - 仅覆盖：主角-男 的空手"普攻连招"（不包含空手冲击/跑攻等路径）
 * - 逻辑状态仍保持为 "空手攻击"（兼容旧的状态判定）
 *
 * 依赖：
 * - 引擎_fs_路由基础.as（动画完毕/浮空兜底与旧资源兼容门面）
 * - RoutingIntent（状态切换作业机制、屏蔽旧man卸载、绑定容器结束写状态、同帧跳转保护）
 *
 * 容器约定：
 * - 容器符号命名：空手攻击容器-<连招首帧标签>（例如：空手攻击容器-1连招、空手攻击容器-拳击1连招）
 * - 容器元件末帧调用：`_root.空手攻击路由.动画完毕(this, _parent)`
 *
 * 渐进式容器化的兼容实现参考已外移到 docs/路由系统-容器化兼容路径.md
 *
 * @author flashNight
 * @version 2.1 - API 收编：屏蔽旧man卸载/绑定容器结束写状态/同帧跳转保护/状态字符串常量集中
 */
import org.flashNight.arki.unit.UnitComponent.Routing.*;

_root.空手攻击路由 = {};

// ============================================================================
// 状态切换作业回调（module-level named function，避免每次 producer 创建闭包）
// ============================================================================

/**
 * 状态切换作业回调：载入后跳转空手攻击容器
 * 由 主角普攻连招开始 / 空手攻击标签跳转 共用
 */
_root.空手攻击路由.__job_载入后跳转 = function(u:MovieClip):Void {
    _root.空手攻击路由.载入后跳转空手攻击容器(u.container, u);
};

/**
 * 状态切换作业回调：跨容器标签跳转
 * 通过 unit.__stateTransitionJob 上的 arg_containerName / arg_targetLabel 传参
 * （由 跨容器标签跳转 producer 在 create 后写入；下次 create / 清理会置空）
 */
_root.空手攻击路由.__job_跨容器跳转 = function(u:MovieClip):Void {
    var job:Object = u.__stateTransitionJob;
    var containerActionName:String = job.arg_containerName;
    var targetLabel:String = job.arg_targetLabel;

    var initObj:Object = _root.空手攻击路由.构建空手攻击容器初始化对象(u.container);
    var attachResult = ContainerAttachAction.attach(u, ContainerSpec.KIND_UNARMED, containerActionName, initObj);
    if (attachResult.status === ContainerAttachAction.STATUS_MISSING_ABORT) { return; }
    var man:MovieClip = attachResult.man;

    // 对齐升龙拳判定（A + B 同时按下）
    if (u._name == _root.控制目标) {
        u.读取当前飞行状态();
        if (JumpDeriveAction.tryDerive(u, man, u.被动技能.升龙拳,
                Key.isDown(u.A键) && Key.isDown(u.B键), "空手跳")) {
            return;
        }
    }
    u.格斗架势 = true;

    RoutingIntent.bindContainerEndState(man, u, RoutingIntent.SMALL_END_BAREHAND);

    man.gotoAndPlay(targetLabel);
};

/**
 * 计算空手普攻连招的首帧标签
 * - 对齐旧版"空手攻击"巨型元件的启动逻辑：优先按 unit.空手动作类型 拼接
 * - 无空手动作类型时回退到 "1连招"
 *
 * @param unit:MovieClip 执行空手攻击的单位
 * @return String 连招首帧标签（如 "拳击1连招" / "1连招"）
 */
_root.空手攻击路由.获取普攻连招首帧标签 = function(unit:MovieClip):String {
    if (unit.空手动作类型) {
        return unit.空手动作类型 + "1连招";
    }
    return "1连招";
};

/**
 * 主角-男：进入"空手攻击"状态并加载"连招容器"
 *
 * @param unit:MovieClip 执行空手攻击的单位
 */
_root.空手攻击路由.主角普攻连招开始 = function(unit:MovieClip):Void {
    if (unit.兵种 !== "主角-男") {
        return;
    }

    var actionName:String = _root.空手攻击路由.获取普攻连招首帧标签(unit);
    unit.空手攻击名 = actionName;

    RoutingIntent.triggerStateTransitionJob(
        unit,
        RoutingIntent.STATE_BAREHAND,
        RoutingIntent.LABEL_CONTAINER,
        _root.空手攻击路由.__job_载入后跳转,
        RoutingIntent.LABEL_CONTAINER
    );
};

/**
 * 空手攻击标签跳转入口（供搓招逻辑调用）
 * - 主角-男：走容器化路径
 * - 其他单位：维持旧逻辑（man.gotoAndPlay）
 *
 * @param unit:MovieClip 执行空手攻击的单位
 * @param actionName:String 招式名（对应man时间轴上的帧标签）
 */
_root.空手攻击路由.空手攻击标签跳转 = function(unit:MovieClip, actionName:String):Void {
    unit.空手攻击名 = actionName;

    // 标记：本帧由搓招逻辑触发了空手攻击容器跳转
    // 用于屏蔽同帧内旧容器/旧帧脚本继续执行的变招判定（尤其是B键跳跃与方向键导致的动画完毕）
    // 说明：容器化后，空手普攻容器的 enterFrame 里通常是 "空手攻击搓招() -> 变招判定()"，
    // 若搓招在前半段触发了标签跳转，同帧后半段的变招判定仍可能覆盖状态/结束动画，导致K相关招式极难触发。
    RoutingIntent.markBarehandSameFrameJump(unit, _root.帧计时器.当前帧数);

    // 非主角-男：继续走旧man跳帧（不引入容器化状态依赖）
    if (unit.兵种 !== "主角-男") {
        if (unit.man != undefined) {
            unit.man.gotoAndPlay(actionName);
        }
        return;
    }

    // 切换阶段屏蔽卸载回调（真正结束由新容器man卸载时统一处理）
    RoutingIntent.suppressOldManUnload(unit);

    RoutingIntent.triggerStateTransitionJob(
        unit,
        RoutingIntent.STATE_BAREHAND,
        RoutingIntent.LABEL_CONTAINER,
        _root.空手攻击路由.__job_载入后跳转,
        RoutingIntent.LABEL_CONTAINER
    );
};

/**
 * 跨容器标签跳转（供搓招派生跨容器连段使用）
 * 当目标帧标签所在容器与帧标签名不一致时使用。
 * 例：诛杀步(独立容器) → 破极拳5连招(在破极拳1连招容器内)
 *
 * @param unit:MovieClip 执行空手攻击的单位
 * @param containerActionName:String 容器首帧标签（用于拼接 attachMovie 的 linkageIdentifier）
 * @param targetLabel:String 实际要跳转到的帧标签
 */
_root.空手攻击路由.跨容器标签跳转 = function(unit:MovieClip, containerActionName:String, targetLabel:String):Void {
    unit.空手攻击名 = targetLabel;
    RoutingIntent.markBarehandSameFrameJump(unit, _root.帧计时器.当前帧数);

    // 非主角-男：继续走旧man跳帧
    if (unit.兵种 !== "主角-男") {
        if (unit.man != undefined) {
            unit.man.gotoAndPlay(targetLabel);
        }
        return;
    }

    // 屏蔽旧容器卸载回调
    RoutingIntent.suppressOldManUnload(unit);

    var job:Object = RoutingIntent.createStateTransitionJob(
        unit,
        RoutingIntent.LABEL_CONTAINER,
        _root.空手攻击路由.__job_跨容器跳转
    );
    job.arg_containerName = containerActionName;
    job.arg_targetLabel = targetLabel;
    RoutingIntent.submitStateTransitionJob(
        unit,
        RoutingIntent.STATE_BAREHAND,
        RoutingIntent.LABEL_CONTAINER
    );
};

/**
 * 空手攻击：攻击时移动（迁移自旧空手攻击元件）
 */
_root.空手攻击路由.攻击时移动 = function(慢速度:Number, 快速度:Number):Void {
    if (_parent.方向 == "右") {
        if (Key.isDown(_root.右键) == true) {
            _parent.移动("右", 快速度);
        } else {
            _parent.移动("右", 慢速度);
        }
    } else if (_parent.方向 == "左") {
        if (Key.isDown(_root.左键) == true) {
            _parent.移动("左", 快速度);
        } else {
            _parent.移动("左", 慢速度);
        }
    }
};

/**
 * 空手攻击：攻击时按键四向移动（迁移自旧空手攻击元件）
 */
_root.空手攻击路由.攻击时按键四向移动 = function(慢速度:Number, 快速度:Number):Void {
    var 上下未按键:Number = 0;
    var 左右未按键:Number = 0;

    if (Key.isDown(_parent.上键) == true) {
        _parent.移动("上", 快速度 / 2);
    } else if (Key.isDown(_parent.下键) == true) {
        _parent.移动("下", 快速度 / 2);
    } else {
        上下未按键 = 1;
    }

    if (Key.isDown(_parent.左键) == true) {
        _parent.移动("左", 快速度);
    } else if (Key.isDown(_parent.右键) == true) {
        _parent.移动("右", 快速度);
    } else {
        左右未按键 = 1;
    }

    if (上下未按键 && 左右未按键) {
        _root.空手攻击路由.攻击时移动.call(this, 慢速度, 快速度);
    }
};

_root.空手攻击路由.攻击时可改变移动方向 = function(速度:Number):Void {
    if (Key.isDown(_parent.右键) == true) {
        _parent.方向改变("右");
    } else if (Key.isDown(_parent.左键) == true) {
        _parent.方向改变("左");
    }

    if (_parent.方向 == "右") {
        _parent.移动("右", 速度);
    } else if (_parent.方向 == "左") {
        _parent.移动("左", 速度);
    }
};

_root.空手攻击路由.攻击时斜向移动 = function(慢速度:Number, 快速度:Number):Void {
    if (_parent.方向 == "右") {
        if (Key.isDown(_parent.右键) == true) {
            _parent.移动("右", 快速度);
        } else {
            _parent.移动("右", 慢速度);
        }
    } else if (_parent.方向 == "左") {
        if (Key.isDown(_parent.左键) == true) {
            _parent.移动("左", 快速度);
        } else {
            _parent.移动("左", 慢速度);
        }
    }

    if (Key.isDown(_parent.上键) == true) {
        _parent.移动("上", 快速度);
    } else if (Key.isDown(_parent.下键) == true) {
        _parent.移动("下", 快速度);
    }
};

_root.空手攻击路由.攻击时可斜向改变移动方向 = function(速度:Number):Void {
    if (Key.isDown(_parent.右键) == true) {
        _parent.方向改变("右");
    } else if (Key.isDown(_parent.左键) == true) {
        _parent.方向改变("左");
    }

    if (_parent.方向 == "右") {
        _parent.移动("右", 速度);
    } else if (_parent.方向 == "左") {
        _parent.移动("左", 速度);
    }

    if (Key.isDown(_parent.上键) == true) {
        _parent.移动("上", 速度 / 2);
    } else if (Key.isDown(_parent.下键) == true) {
        _parent.移动("下", 速度 / 2);
    }
};

_root.空手攻击路由.攻击时可斜向改变移动方向2 = function(速度:Number, 上下:Number):Void {
    if (Key.isDown(_parent.右键) == true) {
        _parent.方向改变("右");
    } else if (Key.isDown(_parent.左键) == true) {
        _parent.方向改变("左");
    }

    if (_parent.方向 == "右") {
        _parent.移动("右", 速度 / 2);
    } else if (_parent.方向 == "左") {
        _parent.移动("左", 速度 / 2);
    }

    if (上下 > 0) {
        _parent.移动("上", 速度);
    } else if (上下 < 0) {
        _parent.移动("下", 速度);
    }
};

/**
 * 空手攻击：变招判定（迁移自旧空手攻击元件）
 * - 保持旧行为：跳跃 -> 空手跳；键1 -> 攻击模式切换；动作A -> 连招跳帧
 *
 * @param 招式名:String 可派生的目标招式名（若为空则不允许连招）
 * @param 招式是否结束:Boolean 当前招式是否已结束（用于AI连招判定）
 * @param 是否屏蔽跳跃:Boolean 是否屏蔽跳跃（部分招式不允许B跳取消）
 */
_root.空手攻击路由.变招判定 = function(招式名:String, 招式是否结束:Boolean, 是否屏蔽跳跃:Boolean):Void {
    var unit:MovieClip = _parent;

    // 同帧跳转保护：搓招触发空手攻击标签跳转后，跳过本帧剩余的变招判定，避免覆盖/打断新招式
    if (RoutingIntent.isBarehandSameFrameJump(unit, _root.帧计时器.当前帧数)) {
        return;
    }

    if (unit.操控编号 != -1 && _root.控制目标全自动 == false) {
        // 玩家控制
        if (!unit.飞行浮空 && unit.动作B && !是否屏蔽跳跃) {
            unit.状态改变("空手跳");
        } else if (!unit.飞行浮空 && Key.isDown(_root.键1)) {
            unit.状态改变("攻击模式切换");
        } else if (unit.动作A && 招式名) {
            if (unit.左行) {
                unit.右行 = 0;
                unit.方向改变("左");
            } else if (unit.右行) {
                unit.左行 = 0;
                unit.方向改变("右");
            }
            gotoAndPlay(招式名);
        } else if (unit.左行 || unit.右行 || unit.上行 || unit.下行) {
            unit.动画完毕();
        }
    } else if (招式名 && !招式是否结束) {
        // AI控制：继续连招
        gotoAndPlay(招式名);
    }
};

/**
 * 构建空手攻击容器初始化对象
 *
 * 实现：委派到 ContainerInitScratch.getUnarmed(container) 的 singleton scratch，
 *       消除每次 new Object literal 的 GC 压力。装配字段对齐契约由 ContainerInitScratch 维护。
 *
 * @param container:MovieClip "容器"帧上的占位容器（用于获取位置和缩放）
 * @return Object 初始化参数对象（singleton scratch，attachMovie 同步消费后即可复用）
 */
_root.空手攻击路由.构建空手攻击容器初始化对象 = function(container:MovieClip):Object {
    return ContainerInitScratch.getUnarmed(container);
};

/**
 * 容器化空手攻击入口（从"容器"帧回调后调用）
 *
 * @param container:MovieClip "容器"帧上的占位容器
 * @param unit:MovieClip 执行空手攻击的单位
 */
_root.空手攻击路由.载入后跳转空手攻击容器 = function(container:MovieClip, unit:MovieClip):MovieClip {
    var actionName:String = unit.空手攻击名;
    var initObj:Object = _root.空手攻击路由.构建空手攻击容器初始化对象(container);
    var attachResult = ContainerAttachAction.attach(unit, ContainerSpec.KIND_UNARMED, actionName, initObj);
    if (attachResult.status === ContainerAttachAction.STATUS_MISSING_ABORT) {
        return undefined;
    }
    var man:MovieClip = attachResult.man;

    // 对齐原空手攻击帧的 load 逻辑（升龙拳判定 A + B）
    if (unit._name == _root.控制目标) {
        unit.读取当前飞行状态();
        if (JumpDeriveAction.tryDerive(unit, man, unit.被动技能.升龙拳,
                Key.isDown(unit.A键) && Key.isDown(unit.B键), "空手跳")) {
            return undefined;
        }
    }
    unit.格斗架势 = true;

    RoutingIntent.bindContainerEndState(man, unit, RoutingIntent.SMALL_END_BAREHAND);

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
 * @param man:MovieClip 当前容器化空手攻击man
 * @param unit:MovieClip 执行空手攻击的单位
 */
_root.空手攻击路由.动画完毕 = function(man:MovieClip, unit:MovieClip):Void {
    RoutingLifecycle.completeAnimation(man, unit, false);
};
