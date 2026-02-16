/**
 * 技能路由器 - 容器化技能支持
 *
 * 目的：将所有"技能启动的跳帧入口"收口到统一路由。
 * 说明：技能容器化已完成，本文件只负责复用路由基础逻辑，不做额外兼容/兜底。
 *
 * 依赖：引擎_fs_路由基础.as（共享底层函数）
 *
 * API说明：
 *   - 技能标签跳转_旧(unit, skillName): 从外部触发技能跳帧入口
 *   - 技能man载入后跳转_旧(man, unit): man加载完成后跳转到技能帧（旧实现）
 *   - 载入后跳转技能容器(container, unit): 容器化技能入口
 *
 * @author flashNight
 * @version 3.0 - 使用路由基础收敛结构
 */

_root.技能路由 = {};

/**
 * 技能标签跳转（旧实现）
 * 用于外部代码触发技能时调用，如释放行为、AI释放等场景
 *
 * @param unit:MovieClip 执行技能的单位
 * @param skillName:String 技能名称（对应man时间轴上的帧标签）
 */
_root.技能路由.技能标签跳转_旧 = function(unit:MovieClip, skillName:String):Void {
    unit.技能名 = skillName;
    _root.路由基础.确保临时Y(unit);

    // 进入技能状态（主角-男会在状态改变中映射到"容器"帧）
    unit.状态改变("技能");
    _root.路由基础.准备姿态与加成(unit);

    // AI 事件：技能释放开始（供日志/分析/未来响应式系统）
    if (unit.dispatcher != undefined && unit.dispatcher != null) {
        unit.dispatcher.publish("skillStart", unit, skillName);
    }

    // 主角-男使用技能容器（attachMovie 动态man）
    if (unit.兵种 === "主角-男") {
        _root.技能路由.载入后跳转技能容器(unit.container, unit);
        return;
    }

    // 其他单位维持旧 man 跳帧
    var man:MovieClip = unit.man;
    _root.路由基础.绑定移动函数(man);
    _root.路由基础.绑定结束清理(man, unit, "战技", "技能结束", "技能浮空");
    _root.技能路由.技能man载入后跳转_旧(man, unit);
};

/**
 * 技能man载入后跳转（旧实现）
 * 用于man剪辑加载完成后，根据unit.技能名跳转到对应帧
 *
 * @param man:MovieClip man剪辑自身
 * @param unit:MovieClip man的父级单位（通过unit.技能名获取目标帧）
 */
_root.技能路由.技能man载入后跳转_旧 = function(man:MovieClip, unit:MovieClip):Void {
    man.gotoAndPlay(unit.技能名);
};

/**
 * 容器化技能入口（从"技能容器"状态的container onClipEvent(load)调用）
 *
 * @param container:MovieClip 技能容器状态下的占位容器（保持不可见）
 * @param unit:MovieClip 执行技能的单位
 */
_root.技能路由.载入后跳转技能容器 = function(container:MovieClip, unit:MovieClip):Void {
    var 技能名:String = unit.技能名;
    var initObj:Object = _root.路由基础.构建容器初始化对象(container);
    var man:MovieClip = unit.attachMovie("技能容器-" + 技能名, "man", 0, initObj);
    _root.路由基础.处理浮空(man, unit, "技能浮空");
    _root.路由基础.绑定结束清理(man, unit, "战技", "技能结束", "技能浮空");
};

/**
 * 动画完毕处理
 * @param enableDoubleJump:Boolean 可选，传入true则保留空中二段跳特性
 */
_root.技能路由.动画完毕 = function(man:MovieClip, unit:MovieClip, enableDoubleJump:Boolean):Void {
    _root.路由基础.动画完毕(man, unit, enableDoubleJump);
};
