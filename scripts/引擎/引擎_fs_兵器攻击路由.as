/**
 * 兵器攻击路由器 - 兵器攻击容器化支持
 *
 * 目的：将兵器攻击的"跳帧入口"收口到统一路由，
 *       通过主角-男的"容器"帧 attachMovie 容器元件，替代巨型影片剪辑 gotoAndPlay 的沿途 load/unload 开销。
 *       同时将 xml 中的 onClipEvent 代码迁移到 AS 文件，消除资产文件中的代码依赖。
 *
 * 依赖：
 * - 引擎_fs_路由基础.as（复用构建容器初始化对象、状态切换作业机制）
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
 * @author flashNight
 * @version 3.0 - 容器化完成，移除兼容性分支
 */

_root.兵器攻击路由 = {};

// ============================================================================
// 【兼容性实现参考 - 容器符号存在性检测】
// 用于渐进式容器化阶段，检测容器符号是否存在，不存在则回退旧帧路径
// 新增路由时若需渐进式改造可参考此实现
// ============================================================================
// _root.兵器攻击路由.__containerExistsCache = {};
//
// _root.兵器攻击路由.检查容器符号存在 = function(unit:MovieClip, symbolName:String):Boolean {
//     var cache:Object = _root.兵器攻击路由.__containerExistsCache;
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

    // 容器化路径：跳转到"容器"帧，attachMovie 动态容器
    unit.__stateTransitionJob = _root.路由基础.创建状态切换作业("容器", function(u:MovieClip):Void {
        _root.兵器攻击路由.载入后跳转兵器攻击容器(u.container, u);
    });

    // 统一入口：状态改变会触发 gotoAndStop，然后执行作业回调
    // 注意：gotoAndStop 会卸载当前 man（拳刀行走状态机的执行上下文），后续代码不会执行
    unit.状态改变("兵器攻击");
};

// ============================================================================
// 【兼容性实现参考 - 渐进式容器化的普攻连招开始】
// 检测容器符号是否存在，存在走容器路径，不存在回退旧帧路径
// ============================================================================
// _root.兵器攻击路由.主角普攻连招开始 = function(unit:MovieClip):Void {
//     if (unit.兵种 !== "主角-男") {
//         return;
//     }
//     var actionName:String = _root.兵器攻击路由.获取普攻连招首帧标签(unit);
//     unit.兵器攻击名 = actionName;
//     var symbolName:String = "兵器攻击容器-" + actionName;
//     var containerExists:Boolean = _root.兵器攻击路由.检查容器符号存在(unit, symbolName);
//     if (containerExists) {
//         _root.发布消息("使用容器路径加载 " + symbolName);
//         unit.__stateTransitionJob = _root.路由基础.创建状态切换作业("容器", function(u:MovieClip):Void {
//             _root.兵器攻击路由.载入后跳转兵器攻击容器(u.container, u);
//         });
//     } else {
//         _root.发布消息("容器不存在，使用旧帧路径加载 " + symbolName);
//         unit.__stateTransitionJob = _root.路由基础.创建状态切换作业(null, function(u:MovieClip):Void {
//             _root.兵器攻击路由.兵器攻击帧载入(u.man, u);
//         });
//     }
//     unit.状态改变("兵器攻击");
// };
// ============================================================================

/**
 * 兵器攻击标签跳转入口
 * - 主角-男：跳到“容器”帧并 attachMovie 对应的“兵器攻击容器-招式名”
 * - 其他单位：维持旧逻辑（man.gotoAndPlay）
 *
 * @param unit:MovieClip 执行兵器攻击的单位
 * @param actionName:String 招式名（例如 "剑气释放"）
 */
_root.兵器攻击路由.兵器攻击标签跳转 = function(unit:MovieClip, actionName:String):Void {
    unit.兵器攻击名 = actionName;

    // 非主角-男：继续走旧man跳帧（不引入容器化状态依赖）
    if (unit.兵种 !== "主角-男") {
        unit.man.gotoAndPlay(actionName);
        return;
    }

    // 切到“容器”帧会卸载旧man；旧man.onUnload 会写入“普攻结束/兵器攻击结束”。
    // 容器化切换阶段必须屏蔽该卸载回调（真正结束由新容器man卸载时统一处理）。
    if (unit.man != undefined && !unit.man.__isDynamicMan) {
        unit.man.onUnload = function() {};
    }

    unit.状态改变("兵器攻击容器");
    _root.兵器攻击路由.载入后跳转兵器攻击容器(unit.container, unit);
};

/**
 * 构建兵器攻击容器初始化对象
 * - 复用路由基础提供的位置/缩放与移动函数绑定
 * - 补齐兵器攻击容器所需的搓招/派生函数引用（对齐旧"兵器攻击"man的挂载集合）
 *
 * @param container:MovieClip "容器"帧上的占位容器（用于获取位置和缩放）
 * @return Object 初始化参数对象
 */
_root.兵器攻击路由.构建兵器攻击容器初始化对象 = function(container:MovieClip):Object {
    var initObj:Object = _root.路由基础.构建容器初始化对象(container);

    // ========== 兵器攻击专用移动函数（覆盖路由基础的通用版本） ==========
    // 兵器攻击的移动逻辑与技能不同：
    // - 始终按角色朝向移动，速度正负决定前进/后退
    // - 按键只影响快/慢速度选择，不改变移动方向
    initObj.攻击时移动 = _root.技能函数.兵器攻击时移动;
    initObj.攻击时按键四向移动 = _root.技能函数.兵器攻击时按键四向移动;

    // ========== 兵器攻击核心函数 ==========
    // 变招判定：普攻连招中的招式切换/跳跃/移动判定
    initObj.变招判定 = _root.技能函数.变招判定;
    // 刀口触发特效：触发刀口位置上的特效
    initObj.刀口触发特效 = _root.技能函数.刀口触发特效;
    // 兵器攻击：近战攻击子弹生成
    initObj.兵器攻击 = _root.技能函数.兵器攻击;

    // ========== 搓招/派生函数 ==========
    // 对齐 flashswf/arts/things0/LIBRARY/容器/兵器攻击容器/兵器攻击.xml 中的函数挂载
    initObj.轻型武器攻击搓招 = _root.技能函数.轻型武器攻击搓招;
    initObj.大型武器攻击搓招 = _root.技能函数.大型武器攻击搓招;
    initObj.剑气释放搓招窗口 = _root.技能函数.剑气释放搓招窗口;
    initObj.飞沙走石搓招窗口 = _root.技能函数.飞沙走石搓招窗口;
    initObj.贯穿突刺搓招窗口 = _root.技能函数.贯穿突刺搓招窗口;
    initObj.蓄力重劈搓招窗口 = _root.技能函数.蓄力重劈搓招窗口;
    initObj.十六夜月华可派生 = _root.技能函数.十六夜月华可派生;
    initObj.千山破晓钟可派生 = _root.技能函数.千山破晓钟可派生;
    initObj.幻影剑舞可派生 = _root.技能函数.幻影剑舞可派生;
    initObj.百万突刺可派生 = _root.技能函数.百万突刺可派生;
    initObj.粉碎切割可派生 = _root.技能函数.粉碎切割可派生;
    initObj.猎影十字可派生 = _root.技能函数.猎影十字可派生;
    initObj.空坠强袭可派生 = _root.技能函数.空坠强袭可派生;
    initObj.次元斩可派生 = _root.技能函数.次元斩可派生;
    initObj.追地祀可派生 = _root.技能函数.追地祀可派生;
    initObj.月光斩可派生 = _root.技能函数.月光斩可派生;
    initObj.见切可派生 = _root.技能函数.见切可派生;

    return initObj;
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
        if (!unit.飞行浮空 && unit.被动技能.上挑 && unit.被动技能.上挑.启用 && Key.isDown(unit.B键)) {
            unit.跳横移速度 = unit.行走X速度;
            unit.跳跃中移动速度 = unit.行走X速度;
            unit.状态改变("兵器跳");
            // 已切换状态，移除刚创建的容器man
            man.removeMovieClip();
            return undefined;
        }
    }

    // 统一结束手感：动态man被卸载/移除时写入"普攻结束/兵器攻击结束"
    var prevOnUnload:Function = man.onUnload;
    man.onUnload = function() {
        if (prevOnUnload != undefined) {
            prevOnUnload.apply(this);
        }
        unit.UpdateBigSmallState("普攻结束", "兵器攻击结束");
    };

    man.gotoAndPlay(actionName);
    return man;
};

// ============================================================================
// 【兼容性实现参考 - 旧帧路径的载入处理】
// 用于渐进式容器化阶段，容器符号不存在时回退到旧帧的 load 逻辑
// ============================================================================
// _root.兵器攻击路由.兵器攻击帧载入 = function(man:MovieClip, unit:MovieClip):Void {
//     if (unit._name == _root.控制目标) {
//         unit.读取当前飞行状态();
//         if (!unit.飞行浮空 && unit.被动技能.上挑 && unit.被动技能.上挑.启用 && Key.isDown(unit.B键)) {
//             unit.跳横移速度 = unit.行走X速度;
//             unit.跳跃中移动速度 = unit.行走X速度;
//             unit.状态改变("兵器跳");
//             return;
//         }
//     }
//     man.onUnload = function() {
//         unit.UpdateBigSmallState("普攻结束", "兵器攻击结束");
//     };
// };
// ============================================================================

/**
 * 动画完毕处理（由容器元件末帧调用）
 *
 * @param man:MovieClip 当前容器化兵器攻击man
 * @param unit:MovieClip 执行兵器攻击的单位
 */
_root.兵器攻击路由.动画完毕 = function(man:MovieClip, unit:MovieClip):Void {
    unit.动画完毕();
    man.removeMovieClip();
};
