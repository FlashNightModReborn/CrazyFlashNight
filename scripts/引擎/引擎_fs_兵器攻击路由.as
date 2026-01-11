/**
 * 兵器攻击路由器 - 兵器攻击容器化支持
 *
 * 目的：将兵器攻击中特定招式的“跳帧入口”收口到统一路由，
 *       通过主角-男的“容器”帧 attachMovie 容器元件，替代巨型影片剪辑 gotoAndPlay 的沿途 load/unload 开销。
 *
 * 当前实现：仅用于“剑气释放”的容器化实验。
 *
 * 依赖：
 * - 引擎_fs_路由基础.as（复用构建容器初始化对象）
 *
 * 约定：
 * - 触发端调用 `兵器攻击标签跳转(unit, 招式名)`
 * - 对主角-男：通过 `状态改变("兵器攻击容器")` 跳转到“容器”帧，再 attachMovie 动态man
 * - 容器元件最后一帧调用 `_root.兵器攻击路由.动画完毕(this, _parent)`
 *
 * @author flashNight
 * @version 1.0
 */

_root.兵器攻击路由 = {};

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
 * 主角-男：进入“兵器攻击”状态并加载“连招容器”
 * - 逻辑状态保持为 "兵器攻击"（兼容状态判定）
 * - 显示层跳转到 “容器” 帧（由一次性标记 __weaponAttackGotoContainer 控制）
 * - 连招在单个容器内通过 gotoAndPlay 跳帧，不做“每段连招 attachMovie 新容器”
 *
 * 注意：本函数仅负责普攻连招容器化，不覆盖 “兵器冲击/跑攻”。
 *
 * @param unit:MovieClip 执行兵器攻击的单位
 */
_root.兵器攻击路由.主角普攻连招开始 = function(unit:MovieClip):Void {
    if (unit.兵种 !== "主角-男") {
        return;
    }

    var actionName:String = _root.兵器攻击路由.获取普攻连招首帧标签(unit);
    unit.兵器攻击名 = actionName;

    // 预检容器符号是否存在（避免先跳到容器帧再回退的双重跳转）
    var testMan:MovieClip = unit.attachMovie("兵器攻击容器-" + actionName, "__containerTest", 9999);
    if (testMan == undefined) {
        // 容器符号不存在，直接走旧逻辑
        unit.状态改变("兵器攻击");
        return;
    }
    testMan.removeMovieClip();

    // 容器存在，走容器化路径
    unit.__weaponAttackGotoContainer = true;
    unit.状态改变("兵器攻击");
    delete unit.__weaponAttackGotoContainer;

    _root.兵器攻击路由.载入后跳转兵器攻击容器(unit.container, unit);
};

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
    initObj.百万突刺可派生 = _root.技能函数.百万突刺可派生;
    initObj.粉碎切割可派生 = _root.技能函数.粉碎切割可派生;
    initObj.猎影十字可派生 = _root.技能函数.猎影十字可派生;
    initObj.次元斩可派生 = _root.技能函数.次元斩可派生;
    initObj.月光斩可派生 = _root.技能函数.月光斩可派生;
    initObj.见切可派生 = _root.技能函数.见切可派生;

    return initObj;
};

/**
 * 容器化兵器攻击入口（从“兵器攻击容器”状态跳转到“容器”帧后调用）
 *
 * @param container:MovieClip “容器”帧上的占位容器
 * @param unit:MovieClip 执行兵器攻击的单位
 */
_root.兵器攻击路由.载入后跳转兵器攻击容器 = function(container:MovieClip, unit:MovieClip):MovieClip {
    var actionName:String = unit.兵器攻击名;
    var initObj:Object = _root.兵器攻击路由.构建兵器攻击容器初始化对象(container);
    var man:MovieClip = unit.attachMovie("兵器攻击容器-" + actionName, "man", 0, initObj);
    if (man == undefined) {
        _root.发布消息("兵器攻击容器-" + actionName + "符号缺失，载入失败");
        return undefined;
    }
    _root.发布消息("兵器攻击容器-" + actionName + "加载完成，进入容器化兵器攻击逻辑",man);
    // 统一结束手感：动态man被卸载/移除时写入“普攻结束/兵器攻击结束”
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
