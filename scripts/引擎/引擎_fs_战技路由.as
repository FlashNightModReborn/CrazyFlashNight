/**
 * 战技路由器 - 容器化战技支持
 *
 * 目的：将所有"战技启动的跳帧入口"收口到统一路由，
 *       支持渐进式容器化改造。
 *
 * 依赖：引擎_fs_路由基础.as（共享底层函数）
 *
 * 与技能路由的区别：
 *   - 技能路由处理的是"技能"状态（技能槽触发的主动技能）
 *   - 战技路由处理的是"战技"状态（武器绑定的主动战技）
 *   - 战技由装备的主动战技配置触发，走 _root.主动战技函数 链路
 *   - 二者共享武器加成逻辑（根据技能名判断空手/技能）
 *
 * API说明：
 *   - 战技标签跳转_旧(unit, skillName): 从外部触发战技跳帧（旧实现）
 *   - 战技man载入后跳转_旧(man, unit): man加载完成后跳转到战技帧（旧实现）
 *   - 载入后跳转战技容器(container, unit): 容器化战技入口
 *
 * @author flashNight
 * @version 2.0 - 抽离公共逻辑到路由基础
 */

_root.战技路由 = {};

/**
 * 战技标签跳转（旧实现）
 * 用于外部代码触发战技时调用，如主动战技函数.释放等场景
 * 容器化战技跳过此步骤（由载入后跳转战技容器处理）
 *
 * @param unit:MovieClip 执行战技的单位（需要有man子剪辑）
 * @param skillName:String 战技名称（对应man时间轴上的帧标签）
 */
_root.战技路由.战技标签跳转_旧 = function(unit:MovieClip, skillName:String):Void {
    unit.技能名 = skillName;
    _root.路由基础.确保临时Y(unit);

    // 兼容战技元件 onClipEvent(load) 的旧逻辑：hp<=0 时直接进入血腥死
    if (unit.hp <= 0) {
        unit.状态改变("血腥死");
        return;
    }

    // 进入战技状态（容器化与旧跳帧都依赖该状态载入man）
    unit.状态改变("战技");

    _root.路由基础.准备姿态与加成(unit);

    // 主角-男优先走容器化
    if (unit.兵种 === "主角-男") {
        _root.战技路由.载入后跳转战技容器(unit.container, unit);
        return;
    }

    // 回退：传统man跳帧逻辑
    var newMan:MovieClip = unit.man;
    _root.路由基础.绑定移动函数(newMan);
    _root.路由基础.绑定结束清理(newMan, unit, undefined, "技能结束", "技能浮空");
    _root.战技路由.战技man载入后跳转_旧(newMan, unit);
};

/**
 * 战技man载入后跳转（旧实现）
 * 用于man剪辑加载完成后，根据unit.技能名跳转到对应帧
 * 典型场景：主角进入"战技"状态时，man加载后的第一帧调用
 *
 * @param man:MovieClip man剪辑自身
 * @param unit:MovieClip man的父级单位（通过unit.技能名获取目标帧）
 */
_root.战技路由.战技man载入后跳转_旧 = function(man:MovieClip, unit:MovieClip):Void {
    man.gotoAndPlay(unit.技能名);
};

/**
 * 容器化战技入口（从"战技容器"状态的container onClipEvent(load)调用）
 * 入口已由战技标签跳转_旧统一判断，此处直接执行容器化逻辑
 *
 * @param container:MovieClip 战技容器状态下的占位容器（保持不可见）
 * @param unit:MovieClip 执行战技的单位
 */
_root.战技路由.载入后跳转战技容器 = function(container:MovieClip, unit:MovieClip):Void {
    var 技能名:String = unit.技能名;
    var initObj:Object = _root.路由基础.构建容器初始化对象(container);
    var newMan:MovieClip = unit.attachMovie("战技容器-" + 技能名, "man", 0, initObj);
    if (newMan == undefined) {
        // 容器符号缺失时，尝试回退到旧 man 跳帧（若当前帧仍存在man）
        _root.发布消息("战技容器-" + 技能名 + "符号缺失，尝试回退到旧跳帧逻辑");
        unit.gotoAndStop("战技"); // 保持在战技状态帧，避免重复进入容器逻辑
        var fallbackMan:MovieClip = unit.man;
        if (fallbackMan != undefined) {
            _root.路由基础.绑定移动函数(fallbackMan);
            _root.路由基础.绑定结束清理(fallbackMan, unit, undefined, "技能结束", "技能浮空");
            _root.战技路由.战技man载入后跳转_旧(fallbackMan, unit);
        }
        return;
    }

    _root.发布消息("战技容器-" + 技能名 + "加载完成，进入容器化战技逻辑");
    _root.路由基础.处理浮空(newMan, unit, "技能浮空");
    _root.路由基础.绑定结束清理(newMan, unit, undefined, "技能结束", "技能浮空");
};

/**
 * 动画完毕处理
 */
_root.战技路由.动画完毕 = function(man:MovieClip, unit:MovieClip):Void {
    _root.路由基础.动画完毕(man, unit);
};
