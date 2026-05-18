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
import org.flashNight.arki.unit.UnitComponent.Routing.*;

_root.路由基础 = {};

// ============================================================================
// 路由系统公共状态/帧名字符串常量
// 集中化的目的：让第二步 class 化时重命名只改一处，而不是全工程 grep 字符串。
// 容器 XML 末帧 callback 与状态机 onUnload 写入的状态名都对齐这里。
// ============================================================================
_root.路由基础.LABEL_CONTAINER         = "容器";          // 主角-男 用于容器化 attachMovie 的占位帧
_root.路由基础.STATE_WEAPON            = "兵器攻击";       // 普攻连招逻辑状态（兵器）
_root.路由基础.STATE_WEAPON_CONTAINER  = "兵器攻击容器";   // 兵器搓招触发新容器时用的辅助状态
_root.路由基础.STATE_BAREHAND          = "空手攻击";       // 普攻连招逻辑状态（空手）
_root.路由基础.BIG_END_PUNCH           = "普攻结束";       // onUnload 写入的大状态名
_root.路由基础.SMALL_END_WEAPON        = "兵器攻击结束";   // onUnload 写入的小状态名（兵器）
_root.路由基础.SMALL_END_BAREHAND      = "空手攻击结束";   // onUnload 写入的小状态名（空手）

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
 * 技能容器和战技容器共用同一套初始化参数。
 *
 * 实现：委派到 ContainerInitScratch.getPublic(container) 的 singleton scratch，
 *       消除每次 new Object literal 的 GC 压力。装配字段对齐契约由 ContainerInitScratch 维护。
 *
 * @param container:MovieClip 容器剪辑（用于获取位置和缩放）
 * @return Object 初始化参数对象（singleton scratch，attachMovie 同步消费后即可复用）
 */
_root.路由基础.构建容器初始化对象 = function(container:MovieClip):Object {
    return ContainerInitScratch.getPublic(container);
};

/**
 * 屏蔽旧 man 的 onUnload 回调
 * 容器化切换阶段（兵器攻击标签跳转 / 空手攻击标签跳转 / 跨容器标签跳转）使用：
 * 旧容器 man 上的 onUnload 会写入"普攻结束/<XX>攻击结束"，但本次切换的目的是
 * 接力到新容器 man，由新 man 的 onUnload 统一写状态。本函数将旧 man.onUnload 置空，
 * 避免新容器 man.attachMovie 引发 gotoAndStop 卸载旧 man 时误写结束状态。
 *
 * @param unit:MovieClip 持有旧 man 的单位
 */
_root.路由基础.屏蔽旧man卸载 = function(unit:MovieClip):Void {
    if (unit.man != undefined) {
        unit.man.onUnload = function() {};
    }
};

// ============================================================================
// 同帧跳转保护
// ----------------------------------------------------------------------------
// 容器化普攻的执行链通常是 `<攻击>搓招() -> 变招判定()`。若搓招在前半段触发了
// 标签跳转（新 attachMovie），同帧后半段的变招判定仍会执行，可能覆盖状态/动画
// 完毕到刚加载的新容器上。这里用 unit-local 的帧戳标记本帧已发生跳转，变招判定
// 在标记命中时早退即可。
//
// 字段分离（__skipWeaponChangeFrame / __skipBarehandChangeFrame）是为了让兵器/
// 空手两条并发逻辑互不干扰；第二步 class 化时若决定收成单字段，改这四个 API
// 函数体即可，调用方不需改动。
// ============================================================================

_root.路由基础.标记同帧跳转兵器 = function(unit:MovieClip):Void {
    unit.__skipWeaponChangeFrame = _root.帧计时器.当前帧数;
};
_root.路由基础.是否同帧跳转兵器 = function(unit:MovieClip):Boolean {
    return unit.__skipWeaponChangeFrame === _root.帧计时器.当前帧数;
};
_root.路由基础.标记同帧跳转空手 = function(unit:MovieClip):Void {
    unit.__skipBarehandChangeFrame = _root.帧计时器.当前帧数;
};
_root.路由基础.是否同帧跳转空手 = function(unit:MovieClip):Boolean {
    return unit.__skipBarehandChangeFrame === _root.帧计时器.当前帧数;
};

/**
 * 绑定容器化普攻 man 的 onUnload 写状态
 * 容器化普攻（兵器/空手）的 man 被卸载时统一写 (BIG_END_PUNCH, smallEndState)。
 * chain 前序 onUnload，避免覆盖容器自身可能挂的清理逻辑。
 *
 * @param man:MovieClip 容器化 man（attachMovie 返回值）
 * @param unit:MovieClip 持有 man 的单位
 * @param smallEndState:String 小状态名（推荐传 STATE_END_WEAPON / STATE_END_BAREHAND）
 */
_root.路由基础.绑定容器结束写状态 = function(man:MovieClip, unit:MovieClip, smallEndState:String):Void {
    var prevOnUnload:Function = man.onUnload;
    var bigEnd:String = _root.路由基础.BIG_END_PUNCH;
    man.onUnload = function() {
        if (prevOnUnload != undefined) {
            prevOnUnload.apply(this);
        }
        unit.UpdateBigSmallState(bigEnd, smallEndState);
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
// 1. 调用方优先使用 _root.路由基础.触发状态切换作业(unit, logicalState, gotoLabel, callback, forceGotoLabel)
//    - 该入口封装 producer-set → 状态改变 → consumer 的同步嵌套契约
//    - forceGotoLabel 用于当前已在同一显示帧时强制触发一次 gotoAndStop（例如 "容器"）
// 2. 需要附加参数时，先调用 _root.路由基础.创建状态切换作业(...)，写入 arg_*，
//    再立刻调用 _root.路由基础.提交状态切换作业(unit, logicalState, forceGotoLabel)
//    - 内部 lazy-alloc unit.__stateTransitionJob 单例，仅 mutate gotoLabel/callback 字段
//    - 复用 unit-local job 对象，稳态 0 alloc；callback 推荐传 module-level named function
//    - 如需附加参数，在返回的 job 对象上挂已约定的 arg_* 字段（同 unit-local，下次自动覆盖）
// 3. consumer 由 unit.状态改变(...) 同步触发：
//    a) 状态改变函数读 unit.__stateTransitionJob.gotoLabel 覆盖默认跳转帧
//    b) 执行 gotoAndStop
//    c) 取出 job.callback，把 callback/gotoLabel 设为 undefined（标记空闲，对象保留）
//    d) 调用 callback(unit)
// 4. 状态改变未发生跳转的兜底路径调用 _root.路由基础.清理状态切换作业(unit)
//
// 关键不变量：
// - 单 unit 的 producer→consumer 是同步嵌套（producer-set → 状态改变 → gotoAndStop
//   → 执行状态切换作业），job 不跨帧滞留
// - unit-local 复用：每个 unit 自己持有一份 job 对象，gotoAndStop 期间子帧脚本对其他
//   unit producer-set 不会污染当前 unit 的 job
//
// job 字段契约（第二步 class 化时 StateTransitionJob 的字段集）：
//   gotoLabel:String          — 覆盖的跳转帧标签；consumer 取走后置 undefined
//   callback:Function         — gotoAndStop 后执行的回调，签名 function(unit:MovieClip):Void
//                               consumer 取走后置 undefined（标记 job 空闲，对象保留供 unit 下次复用）
//   arg_containerName:String  — 跨容器标签跳转专用：容器首帧标签
//   arg_targetLabel:String    — 跨容器标签跳转专用：实际要跳转到的帧标签
//
// 新增 arg_* 字段时务必同步在 创建状态切换作业 / 清理状态切换作业 中加 undefined 置空，
// 否则 unit-local 复用会让 producer 跨路由读到上一轮的脏值。
// ============================================================================

/**
 * 创建状态切换作业
 * 用于需要在 gotoAndStop 后执行回调的场景（例如：拳刀行走状态机触发的兵器攻击容器化）
 *
 * @param unit:MovieClip 持有作业的单位（每个 unit 持有自己的 job 单例）
 * @param gotoLabel:String 覆盖的跳转帧标签（传 null 则不覆盖）
 * @param callback:Function 在 gotoAndStop 后执行的回调函数，签名为 function(unit:MovieClip)
 *                          推荐传 module-level named function，避免每次创建闭包
 * @return Object 作业对象（unit-local 单例，可附加 arg_* 字段传参）
 */
_root.路由基础.创建状态切换作业 = function(unit:MovieClip, gotoLabel:String, callback:Function):Object {
    var job:Object = unit.__stateTransitionJob;
    if (job == undefined) {
        job = {};
        unit.__stateTransitionJob = job;
    }
    job.gotoLabel = gotoLabel;
    job.callback = callback;
    // 清理已知附加参数，调用方若需要参数必须在 create 后立即重写。
    // 避免 unit-local job 复用时跨路由读到上一轮的参数。
    job.arg_containerName = undefined;
    job.arg_targetLabel = undefined;
    return job;
};

/**
 * 提交已创建的状态切换作业
 * 调用方必须在创建 job / 写入 arg_* 后立刻调用本函数，保持 producer→consumer 同步嵌套。
 *
 * @param unit:MovieClip 持有作业的单位
 * @param logicalState:String 传给 unit.状态改变 的逻辑状态
 * @param forceGotoLabel:String 可选；若当前显示帧已是该标签，则改写上一显示帧标记强制本次 gotoAndStop
 */
_root.路由基础.提交状态切换作业 = function(unit:MovieClip, logicalState:String, forceGotoLabel:String):Void {
    if (forceGotoLabel != null && unit.__stateGotoLabel === forceGotoLabel) {
        unit.__stateGotoLabel = logicalState;
    }
    unit.状态改变(logicalState);

    // 正常路径由 状态改变 消费或清理 job。若状态改变早退且当前调用栈仍存活，兜底清掉本轮 producer。
    var job:Object = unit.__stateTransitionJob;
    if (job != undefined && job.callback != undefined) {
        _root.路由基础.清理状态切换作业(unit);
    }
};

/**
 * 创建并提交状态切换作业
 * 无附加参数的首选入口，避免调用方手写 create → 状态改变 的同步协议。
 *
 * @param unit:MovieClip 持有作业的单位
 * @param logicalState:String 传给 unit.状态改变 的逻辑状态
 * @param gotoLabel:String 覆盖的跳转帧标签
 * @param callback:Function 在 gotoAndStop 后执行的回调函数
 * @param forceGotoLabel:String 可选；当前显示帧已是该标签时强制跳转
 * @return Object 作业对象
 */
_root.路由基础.触发状态切换作业 = function(unit:MovieClip, logicalState:String, gotoLabel:String, callback:Function, forceGotoLabel:String):Object {
    var job:Object = _root.路由基础.创建状态切换作业(unit, gotoLabel, callback);
    _root.路由基础.提交状态切换作业(unit, logicalState, forceGotoLabel);
    return job;
};

/**
 * 执行状态切换作业
 * 由状态改变函数在 gotoAndStop 后调用
 *
 * @param unit:MovieClip 执行状态改变的单位
 */
_root.路由基础.执行状态切换作业 = function(unit:MovieClip):Void {
    var job:Object = unit.__stateTransitionJob;
    if (job == undefined || job.callback == undefined) {
        return;
    }
    // 取出回调并标记 job 为空闲（必须在回调前标记，防止回调中再次触发状态改变导致重入）
    // 仅置空 callback/gotoLabel 字段，保留对象本身供 unit 下次复用，避免 GC
    var cb:Function = job.callback;
    job.callback = undefined;
    job.gotoLabel = undefined;
    cb(unit);
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

/**
 * 清理状态切换作业（兜底路径用）
 * 状态改变未实际发生跳转时调用，标记 job 为空闲（保留对象供复用）
 *
 * @param unit:MovieClip 持有作业的单位
 */
_root.路由基础.清理状态切换作业 = function(unit:MovieClip):Void {
    var job:Object = unit.__stateTransitionJob;
    if (job != undefined) {
        job.callback = undefined;
        job.gotoLabel = undefined;
        job.arg_containerName = undefined;
        job.arg_targetLabel = undefined;
    }
};

// ============================================================================
// 诊断钩子
// ----------------------------------------------------------------------------
// 在 testloader / 玩家复现现场时一行 dump 全部路由相关状态。返回字符串而不直接
// trace，由调用方决定输出方式（_root.发布消息 / trace / 写日志）。
// 用例：
//   _root.发布消息(_root.路由基础.__dump状态(unit));
// ============================================================================

_root.路由基础.__dump状态 = function(unit:MovieClip):String {
    if (unit == undefined) {
        return "[路由dump] unit=undefined";
    }
    var s:String = "[路由dump]";
    s += " 帧=" + _root.帧计时器.当前帧数;
    s += " name=" + unit._name;
    s += " 状态=" + unit.状态;
    s += " 旧状态=" + unit.旧状态;
    s += " __stateGotoLabel=" + unit.__stateGotoLabel;
    s += " 兵器攻击名=" + unit.兵器攻击名;
    s += " 空手攻击名=" + unit.空手攻击名;
    s += " 技能名=" + unit.技能名;
    s += " __skipWeapon=" + unit.__skipWeaponChangeFrame;
    s += " __skipBare=" + unit.__skipBarehandChangeFrame;
    var job:Object = unit.__stateTransitionJob;
    if (job == undefined) {
        s += " job=undefined";
    } else {
        s += " job{goto=" + job.gotoLabel
          +  " cb=" + (job.callback != undefined)
          +  " arg_cn=" + job.arg_containerName
          +  " arg_tl=" + job.arg_targetLabel + "}";
    }
    s += " 浮空=" + unit.浮空;
    s += " temp_y=" + unit.temp_y;
    s += " _y=" + unit._y;
    s += " Z=" + unit.Z轴坐标;
    s += " 技能浮空=" + unit.技能浮空;
    s += " 战技浮空=" + unit.战技浮空;
    s += " __preserve=" + unit.__preserveFloatFlagOnUnload;
    s += " man=" + (unit.man != undefined);
    s += " man.__isDynamic=" + unit.man.__isDynamicMan;
    return s;
};
