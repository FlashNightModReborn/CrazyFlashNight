/**
 * 路由基础 - 技能/战技路由共享的底层函数
 *
 * 目的：抽离技能路由与战技路由的公共逻辑，避免代码重复。
 *       战技本质上是特殊触发的技能，二者共享大量底层逻辑。
 *
 * 共享逻辑：
 *   - 临时Y坐标处理（空中释放技能/战技）
 *   - 移动函数绑定
 *   - 浮空处理
 *   - 容器初始化对象构建
 *
 * @author flashNight
 * @version 1.0
 */
import org.flashNight.arki.unit.*;
import org.flashNight.neur.ScheduleTimer.*;

_root.路由基础 = {};

/**
 * 设置通用姿态与武器加成
 * 技能和战技共用同一套逻辑：根据技能名判断使用空手还是技能加成
 *
 * @param unit:MovieClip 执行技能/战技的单位
 */
_root.路由基础.准备姿态与加成 = function(unit:MovieClip):Void {
    unit.格斗架势 = true;
    if (HeroUtil.isFistSkill(unit.技能名)) {
        unit.根据模式重新读取武器加成("空手");
    } else {
        unit.根据模式重新读取武器加成("技能");
    }
};

/**
 * 确保触发时正确记录空中Y坐标
 * 避免部分调用路径未提前写入temp_y导致空中技能/战技无法判定为浮空
 *
 * @param unit:MovieClip 执行技能/战技的单位
 */
_root.路由基础.确保临时Y = function(unit:MovieClip):Void {
    if (unit.temp_y > 0) {
        return;
    }
    if (unit.浮空 === true) {
        unit.temp_y = unit._y;
        return;
    }
    // 兼容：部分跳跃实现可能未同步浮空标记，使用y与Z轴坐标的关系兜底判定
    if (!isNaN(unit.Z轴坐标) && unit._y < unit.Z轴坐标) {
        unit.temp_y = unit._y;
        return;
    }
    unit.temp_y = 0;
};

/**
 * 绑定移动函数到man
 * 技能和战技共用同一套移动函数
 *
 * @param man:MovieClip 技能/战技的man剪辑
 */
_root.路由基础.绑定移动函数 = function(man:MovieClip):Void {
    man.攻击时移动 = _root.技能函数.攻击时移动;
    man.攻击时后退移动 = _root.技能函数.攻击时移动;
    man.攻击时按键四向移动 = _root.技能函数.攻击时按键四向移动;
    man.攻击时可改变移动方向 = _root.技能函数.攻击时可改变移动方向;
    man.攻击时可斜向改变移动方向 = _root.技能函数.攻击时可斜向改变移动方向;
    man.攻击时斜向移动 = _root.技能函数.攻击时斜向移动;
    man.攻击时可斜向改变移动方向2 = _root.技能函数.攻击时可斜向改变移动方向2;
    man.获取移动方向 = _root.技能函数.获取移动方向;
};

/**
 * 构建容器初始化对象
 * 技能容器和战技容器共用同一套初始化参数
 *
 * @param container:MovieClip 容器剪辑（用于获取位置和缩放）
 * @return Object 初始化参数对象
 */
_root.路由基础.构建容器初始化对象 = function(container:MovieClip):Object {
    return {
        __isDynamicMan: true,
        _x: container._x,
        _y: container._y,
        _xscale: container._xscale,
        _yscale: container._yscale,
        攻击时移动: _root.技能函数.攻击时移动,
        攻击时后退移动: _root.技能函数.攻击时移动,
        攻击时按键四向移动: _root.技能函数.攻击时按键四向移动,
        攻击时可改变移动方向: _root.技能函数.攻击时可改变移动方向,
        攻击时可斜向改变移动方向: _root.技能函数.攻击时可斜向改变移动方向,
        攻击时斜向移动: _root.技能函数.攻击时斜向移动,
        攻击时可斜向改变移动方向2: _root.技能函数.攻击时可斜向改变移动方向2,
        获取移动方向: _root.技能函数.获取移动方向
    };
};

/**
 * 绑定结束时的通用清理逻辑
 *
 * @param clip:MovieClip 触发onUnload的剪辑（普通技能/战技为man，容器化为container）
 * @param unit:MovieClip 执行技能/战技的单位
 * @param excludeState:String 排除的状态名（技能排除"战技"，战技排除"技能"）
 * @param endBigState:String 结束时的大状态名（"技能结束"或"战技结束"）
 * @param floatFlag:String 浮空标记名（"技能浮空"或"战技浮空"）
 */
_root.路由基础.绑定结束清理 = function(clip:MovieClip, unit:MovieClip, excludeState:String, endBigState:String, floatFlag:String):Void {
    var prevOnUnload:Function = clip.onUnload;
    clip.onUnload = function() {
        if (prevOnUnload != undefined) {
            prevOnUnload.apply(this);
        }
        unit.无敌 = false;
        var needReset:Boolean = (unit.状态 != excludeState);
        if (needReset) {
            unit.temp_y = 0;
        }
        unit.UpdateBigSmallState(endBigState, endBigState);
        unit.根据模式重新读取武器加成(unit.攻击模式);
        if (needReset) {
            // 清理浮空标记
            // 例外：enableDoubleJump 需要把浮空标记带到跳跃状态加载阶段（onClipEvent(load)→启动跳跃浮空）
            // 否则会出现“动画完毕设置为 true，但下一帧启动跳跃浮空读取为 false”的时序问题。
            if (unit.__preserveFloatFlagOnUnload == floatFlag) {
                delete unit.__preserveFloatFlagOnUnload;
            } else {
                unit[floatFlag] = false;
            }
        }
        // AI 事件：技能/战技动画结束（man 被卸载）
        // 订阅方（ActionArbiter）据此立即释放帧锁，消除"技能后发呆"
        if (unit.dispatcher != undefined && unit.dispatcher != null) {
            unit.dispatcher.publish("skillEnd", unit);
        }
    };
};

/**
 * 空中浮空处理（基于unit.temp_y）
 * - 设置浮空标记，用于技能/战技结束后回跳跃状态
 * - 使用 单位级空中控制器 统一纵向物理（避免与喷气背包/跳跃等系统并发写入 _y）
 *
 * @param man:MovieClip 技能/战技的man剪辑
 * @param unit:MovieClip 执行技能/战技的单位
 * @param floatFlag:String 浮空标记名（"技能浮空"或"战技浮空"）
 */
_root.路由基础.处理浮空 = function(man:MovieClip, unit:MovieClip, floatFlag:String):Void {
    man.落地 = true;
    if (unit.temp_y <= 0) {
        return;
    }

    // 设置单位级别的浮空标记
    unit[floatFlag] = true;
    unit._y = unit.temp_y;
    // 重置起始Y为地面坐标，确保影子高度计算正确
    unit.起始Y = unit.Z轴坐标;
    man.落地 = false;
    unit.浮空 = true;

    // 清理旧定时器（兼容旧实现）
    _root.路由基础.清理浮空任务(unit);

    // 与旧逻辑一致：进入技能浮空时让出自然落地/跳跃浮空的控制权
    if (_root.空中控制器 != undefined) {
        _root.空中控制器.关闭自然落地(unit);
        _root.空中控制器.关闭跳跃浮空(unit);
        _root.空中控制器.启用技能浮空(unit, floatFlag, man);
    }
};

/**
 * 清理技能浮空任务
 * @param unit:MovieClip 执行技能/战技的单位
 */
_root.路由基础.清理浮空任务 = function(unit:MovieClip):Void {
    if (_root.空中控制器 != undefined) {
        _root.空中控制器.关闭技能浮空(unit);
    }
    if (unit.__技能浮空任务ID != null) {
        EnhancedCooldownWheel.I().removeTask(unit.__技能浮空任务ID);
        unit.__技能浮空任务ID = null;
    }
};

/**
 * 清理自然落地任务
 * @param unit:MovieClip 执行技能/战技的单位
 */
_root.路由基础.清理自然落地任务 = function(unit:MovieClip):Void {
    if (_root.空中控制器 != undefined) {
        _root.空中控制器.关闭自然落地(unit);
    }
    if (unit.__自然落地任务ID != null) {
        EnhancedCooldownWheel.I().removeTask(unit.__自然落地任务ID);
        unit.__自然落地任务ID = null;
    }
};

/**
 * 启动自然落地任务
 * 技能在空中结束时，让角色自然下落而不是瞬间传送到地面
 *
 * @param unit:MovieClip 执行技能/战技的单位
 */
_root.路由基础.启动自然落地任务 = function(unit:MovieClip):Void {
    // 清理已存在的任务（防止重复）
    _root.路由基础.清理自然落地任务(unit);

    if (_root.空中控制器 != undefined) {
        _root.空中控制器.启用自然落地(unit);
    }
};

/**
 * 动画完毕处理
 * 调用单位的动画完毕方法并移除容器化man
 *
 * @param man:MovieClip 技能/战技的man或容器
 * @param unit:MovieClip 执行技能/战技的单位
 * @param enableDoubleJump:Boolean 可选，传入true则保留技能浮空标记触发空中二段跳特性，默认不触发
 */
_root.路由基础.动画完毕 = function(man:MovieClip, unit:MovieClip, enableDoubleJump:Boolean):Void {
    // 清理技能浮空任务
    _root.路由基础.清理浮空任务(unit);

    // 检测是否在空中（在 removeMovieClip 之前检测）
    var 在空中:Boolean = unit._y < unit.Z轴坐标 - 0.5;

    // 关键时序修复：
    // 1) 如果需要二段跳，在调用 unit.动画完毕() 之前设置 技能浮空=true，让其进入跳跃状态
    // 2) unit.动画完毕() 内部会调用 状态改变(...) → gotoAndStop；旧 man/容器通常会在此过程中触发 onUnload
    // 3) 绑定结束清理默认会在 onUnload 中清掉 unit[floatFlag]，导致下一帧跳跃 onClipEvent(load) 读不到 技能浮空
    // 4) 因此 enableDoubleJump 时需要保留一次“技能浮空”，交给 跳跃状态 load → 启动跳跃浮空 消费并自行清空
    if (enableDoubleJump && 在空中) {
        // 在调用 动画完毕 之前设置标记，让它进入跳跃状态
        unit.技能浮空 = true;
        // 保留本次 onUnload 的浮空标记清理：让跳跃状态 load 读取到 true 并消费（启动跳跃浮空会自行清空）
        unit.__preserveFloatFlagOnUnload = "技能浮空";
    }

    // 执行动画完毕：如果 技能浮空=true，会进入跳跃状态
    // 跳跃状态的 onClipEvent (load) 通常在下一帧触发，此时需要仍能读到 技能浮空=true
    unit.动画完毕();

    // 移除容器：触发 onUnload
    // - 默认会清理 unit[floatFlag]
    // - enableDoubleJump 场景会保留一次“技能浮空”，交给跳跃状态初始化消费后再清理
    man.removeMovieClip();

    // 处理非二段跳但仍在空中的情况
    if (!enableDoubleJump && 在空中) {
        // 技能在空中结束但不启用二段跳：启动自然落地任务
        _root.路由基础.启动自然落地任务(unit);
    }
};

// ============================================================================
// 状态切换作业机制 - 用于处理 gotoAndStop 后需要执行的回调
// ============================================================================
//
// 背景问题：
// AS2 的 gotoAndStop 会立即卸载当前帧的 MovieClip，如果调用链在被卸载的 MovieClip
// 的 onEnterFrame 中（例如拳刀行走状态机），那么 gotoAndStop 之后的代码将不会执行。
//
// 解决方案：
// 将需要在 gotoAndStop 后执行的逻辑封装为"作业"(job)，由状态改变函数在 gotoAndStop
// 后统一调度执行。这样无论调用方的执行上下文是否被销毁，作业都能正确执行。
//
// 使用方式：
// 1. 调用方设置 unit.__stateTransitionJob = { gotoLabel: "容器", callback: function }
// 2. 状态改变函数检测到 __stateTransitionJob 后：
//    a) 使用 job.gotoLabel 覆盖默认跳转帧
//    b) 执行 gotoAndStop
//    c) 调用 job.callback(unit)
//    d) 清理 __stateTransitionJob
// ============================================================================

/**
 * 创建状态切换作业
 * 用于需要在 gotoAndStop 后执行回调的场景（例如：拳刀行走状态机触发的兵器攻击容器化）
 *
 * @param gotoLabel:String 覆盖的跳转帧标签（传 null 则不覆盖）
 * @param callback:Function 在 gotoAndStop 后执行的回调函数，签名为 function(unit:MovieClip)
 * @return Object 作业对象
 */
_root.路由基础.创建状态切换作业 = function(gotoLabel:String, callback:Function):Object {
    return {
        gotoLabel: gotoLabel,
        callback: callback
    };
};

/**
 * 执行状态切换作业
 * 由状态改变函数在 gotoAndStop 后调用
 *
 * @param unit:MovieClip 执行状态改变的单位
 */
_root.路由基础.执行状态切换作业 = function(unit:MovieClip):Void {
    var job:Object = unit.__stateTransitionJob;
    if (job == undefined) {
        return;
    }
    // 清理作业（必须在回调前清理，防止回调中再次触发状态改变导致重入）
    delete unit.__stateTransitionJob;
    // 执行回调
    if (job.callback != undefined) {
        job.callback(unit);
    };
};

/**
 * 获取状态切换作业的跳转帧覆盖
 * 由状态改变函数在计算 gotoLabel 时调用
 *
 * @param unit:MovieClip 执行状态改变的单位
 * @return String 覆盖的跳转帧标签，无覆盖时返回 null
 */
_root.路由基础.获取作业跳转帧覆盖 = function(unit:MovieClip):String {
    var job:Object = unit.__stateTransitionJob;
    if (job == undefined || job.gotoLabel == undefined) {
        return null;
    }
    return job.gotoLabel;
};
