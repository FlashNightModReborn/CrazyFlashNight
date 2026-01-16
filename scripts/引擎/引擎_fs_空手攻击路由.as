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
 * - 引擎_fs_路由基础.as（状态切换作业机制、容器初始化对象构建）
 *
 * 容器约定：
 * - 容器符号命名：空手攻击容器-<连招首帧标签>（例如：空手攻击容器-1连招、空手攻击容器-拳击1连招）
 * - 容器元件末帧调用：`_root.空手攻击路由.动画完毕(this, _parent)`
 *
 * @author flashNight
 * @version 2.0 - 容器化完成，移除兼容性分支
 */
_root.空手攻击路由 = {};

// ============================================================================
// 【兼容性实现参考 - 容器符号存在性检测】
// 用于渐进式容器化阶段，检测容器符号是否存在，不存在则回退旧帧路径
// 新增路由时若需渐进式改造可参考此实现
// ============================================================================
// _root.空手攻击路由.__containerExistsCache = {};
//
// _root.空手攻击路由.检查容器符号存在 = function(unit:MovieClip, symbolName:String):Boolean {
//     var cache:Object = _root.空手攻击路由.__containerExistsCache;
//     if (cache[symbolName] !== undefined) {
//         return cache[symbolName];
//     }
//     var testInstanceName:String = "__containerExistTest_" + getTimer() + "_" + Math.floor(Math.random() * 10000);
//     var testMan:MovieClip = unit.attachMovie(symbolName, testInstanceName, 9999);
//     var exists:Boolean = (testMan != undefined);
//     if (exists) {
//         testMan.removeMovieClip();
//     }
//     cache[symbolName] = exists;
//     return exists;
// };
// ============================================================================

/**
 * 计算空手普攻连招的首帧标签
 * - 对齐旧版“空手攻击”巨型元件的启动逻辑：优先按 unit.空手动作类型 拼接
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

    // 容器化路径：跳转到"容器"帧，attachMovie 动态容器
    unit.__stateTransitionJob = _root.路由基础.创建状态切换作业("容器", function(u:MovieClip):Void {
        _root.空手攻击路由.载入后跳转空手攻击容器(u.container, u);
    });

    unit.状态改变("空手攻击");
};

// ============================================================================
// 【兼容性实现参考 - 渐进式容器化的普攻连招开始】
// 检测容器符号是否存在，存在走容器路径，不存在回退旧帧路径
// ============================================================================
// _root.空手攻击路由.主角普攻连招开始 = function(unit:MovieClip):Void {
//     if (unit.兵种 !== "主角-男") {
//         return;
//     }
//     var actionName:String = _root.空手攻击路由.获取普攻连招首帧标签(unit);
//     unit.空手攻击名 = actionName;
//     var symbolName:String = "空手攻击容器-" + actionName;
//     var containerExists:Boolean = _root.空手攻击路由.检查容器符号存在(unit, symbolName);
//     if (containerExists) {
//         _root.发布消息("使用容器路径加载 " + symbolName);
//         unit.__stateTransitionJob = _root.路由基础.创建状态切换作业("容器", function(u:MovieClip):Void {
//             _root.空手攻击路由.载入后跳转空手攻击容器(u.container, u);
//         });
//     } else {
//         _root.发布消息("容器不存在，使用旧帧路径加载 " + symbolName);
//         unit.__stateTransitionJob = _root.路由基础.创建状态切换作业(null, function(u:MovieClip):Void {
//             _root.空手攻击路由.空手攻击帧载入(u.man, u);
//         });
//     }
//     unit.状态改变("空手攻击");
// };
// ============================================================================

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
    // 说明：容器化后，空手普攻容器的 enterFrame 里通常是 “空手攻击搓招() -> 变招判定()”，
    // 若搓招在前半段触发了标签跳转，同帧后半段的变招判定仍可能覆盖状态/结束动画，导致K相关招式极难触发。
    unit.__skipBarehandChangeFrame = _root.帧计时器.当前帧数;

    // 非主角-男：继续走旧man跳帧（不引入容器化状态依赖）
    if (unit.兵种 !== "主角-男") {
        if (unit.man != undefined) {
            unit.man.gotoAndPlay(actionName);
        }
        return;
    }

    // 切换阶段屏蔽卸载回调（真正结束由新容器man卸载时统一处理）
    if (unit.man != undefined) {
        unit.man.onUnload = function() {};
    }

    // 若当前逻辑状态与显示帧都已在"容器"，状态改变将因"无跳转"而清理作业不执行回调；
    // 通过临时改写 __stateGotoLabel 强制触发一次 gotoAndStop，从而保证作业回调执行。
    if (unit.状态 === "空手攻击" && unit.__stateGotoLabel === "容器") {
        unit.__stateGotoLabel = "空手攻击";
    }

    unit.__stateTransitionJob = _root.路由基础.创建状态切换作业("容器", function(u:MovieClip):Void {
        _root.空手攻击路由.载入后跳转空手攻击容器(u.container, u);
    });
    unit.状态改变("空手攻击");
};

// ============================================================================
// 【兼容性实现参考 - 渐进式容器化的标签跳转】
// 检测容器符号是否存在，存在走容器路径，不存在回退旧帧路径
// ============================================================================
// _root.空手攻击路由.空手攻击标签跳转 = function(unit:MovieClip, actionName:String):Void {
//     unit.空手攻击名 = actionName;
//     if (unit.兵种 !== "主角-男") {
//         if (unit.man != undefined) {
//             unit.man.gotoAndPlay(actionName);
//         }
//         return;
//     }
//     var symbolName:String = "空手攻击容器-" + actionName;
//     var containerExists:Boolean = _root.空手攻击路由.检查容器符号存在(unit, symbolName);
//     if (containerExists) {
//         _root.发布消息("使用容器路径加载 " + symbolName);
//         if (unit.man != undefined) {
//             unit.man.onUnload = function() {};
//         }
//         if (unit.状态 === "空手攻击" && unit.__stateGotoLabel === "容器") {
//             unit.__stateGotoLabel = "空手攻击";
//         }
//         unit.__stateTransitionJob = _root.路由基础.创建状态切换作业("容器", function(u:MovieClip):Void {
//             _root.空手攻击路由.载入后跳转空手攻击容器(u.container, u);
//         });
//         unit.状态改变("空手攻击");
//         return;
//     }
//     _root.发布消息("容器不存在，使用旧帧路径加载 " + symbolName);
//     if (unit.man != undefined && !unit.man.__isDynamicMan) {
//         _root.空手攻击路由.空手攻击帧载入(unit.man, unit);
//         unit.man.gotoAndPlay(actionName);
//         return;
//     }
//     unit.__stateTransitionJob = _root.路由基础.创建状态切换作业(null, function(u:MovieClip):Void {
//         _root.空手攻击路由.空手攻击帧载入(u.man, u);
//         if (u.man != undefined) {
//             u.man.gotoAndPlay(actionName);
//         }
//     });
//     unit.状态改变("空手攻击");
// };
// ============================================================================

// ============================================================================
// 【兼容性实现参考 - 旧帧路径的载入处理】
// 用于渐进式容器化阶段，容器符号不存在时回退到旧帧的 load 逻辑
// ============================================================================
// _root.空手攻击路由.空手攻击帧载入 = function(man:MovieClip, unit:MovieClip):Void {
//     if (unit._name == _root.控制目标) {
//         unit.读取当前飞行状态();
//         if (!unit.飞行浮空 && unit.被动技能.升龙拳 && unit.被动技能.升龙拳.启用 && Key.isDown(unit.B键)) {
//             unit.跳横移速度 = unit.行走X速度;
//             unit.跳跃中移动速度 = unit.行走X速度;
//             unit.状态改变("空手跳");
//             return;
//         }
//     }
//     unit.格斗架势 = true;
//     if (man != undefined) {
//         var prevOnUnload:Function = man.onUnload;
//         man.onUnload = function() {
//             if (prevOnUnload != undefined) {
//                 prevOnUnload.apply(this);
//             }
//             unit.UpdateBigSmallState("普攻结束", "空手攻击结束");
//         };
//     }
// };
// ============================================================================

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
    if (unit.__skipBarehandChangeFrame === _root.帧计时器.当前帧数) {
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
 * @param container:MovieClip "容器"帧上的占位容器（用于获取位置和缩放）
 * @return Object 初始化参数对象
 */
_root.空手攻击路由.构建空手攻击容器初始化对象 = function(container:MovieClip):Object {
    var initObj:Object = _root.路由基础.构建容器初始化对象(container);

    // 迁移自旧空手攻击元件的移动/变招逻辑
    initObj.攻击时移动 = _root.空手攻击路由.攻击时移动;
    initObj.攻击时后退移动 = _root.空手攻击路由.攻击时移动;
    initObj.攻击时按键四向移动 = _root.空手攻击路由.攻击时按键四向移动;
    initObj.攻击时可改变移动方向 = _root.空手攻击路由.攻击时可改变移动方向;
    initObj.攻击时可斜向改变移动方向 = _root.空手攻击路由.攻击时可斜向改变移动方向;
    initObj.攻击时斜向移动 = _root.空手攻击路由.攻击时斜向移动;
    initObj.攻击时可斜向改变移动方向2 = _root.空手攻击路由.攻击时可斜向改变移动方向2;
    initObj.获取移动方向 = _root.技能函数.获取移动方向;
    initObj.变招判定 = _root.空手攻击路由.变招判定;

    // 搓招/派生函数（对齐旧空手攻击元件的挂载集合）
    initObj.空手攻击搓招 = _root.技能函数.空手攻击搓招;
    initObj.诛杀步可派生搓招 = _root.技能函数.诛杀步可派生搓招;
    initObj.后撤步可派生搓招 = _root.技能函数.后撤步可派生搓招;
    initObj.波动拳可派生搓招 = _root.技能函数.波动拳可派生搓招;
    initObj.能量喷泉可派生搓招 = _root.技能函数.能量喷泉可派生搓招;
    initObj.燃烧指节可派生搓招 = _root.技能函数.燃烧指节可派生搓招;
    initObj.狼炮可派生搓招 = _root.技能函数.狼炮可派生搓招;

    return initObj;
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
    var man:MovieClip = unit.attachMovie("空手攻击容器-" + actionName, "man", 0, initObj);
    if (man == undefined) {
        return undefined;
    }

    // 对齐原空手攻击帧的 load 逻辑（升龙拳判定等）
    if (unit._name == _root.控制目标) {
        unit.读取当前飞行状态();
        if (!unit.飞行浮空 && 
            unit.被动技能.升龙拳 && 
            unit.被动技能.升龙拳.启用 &&
            Key.isDown(unit.A键) && 
            Key.isDown(unit.B键)) {
            unit.跳横移速度 = unit.行走X速度;
            unit.跳跃中移动速度 = unit.行走X速度;
            unit.状态改变("空手跳");
            man.removeMovieClip();
            return undefined;
        }
    }
    unit.格斗架势 = true;

    var prevOnUnload:Function = man.onUnload;
    man.onUnload = function() {
        if (prevOnUnload != undefined) {
            prevOnUnload.apply(this);
        }
        unit.UpdateBigSmallState("普攻结束", "空手攻击结束");
    };

    man.gotoAndPlay(actionName);
    return man;
};

/**
 * 动画完毕处理（由容器元件末帧调用）
 *
 * @param man:MovieClip 当前容器化空手攻击man
 * @param unit:MovieClip 执行空手攻击的单位
 */
_root.空手攻击路由.动画完毕 = function(man:MovieClip, unit:MovieClip):Void {
    unit.动画完毕();
    man.removeMovieClip();
};
