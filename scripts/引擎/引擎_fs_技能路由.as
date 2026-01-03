/**
 * 技能路由器 - Step 2: 容器化技能支持
 *
 * 目的：将所有"技能启动的跳帧入口"收口到统一路由，
 *       支持渐进式容器化改造。
 *
 * 依赖：引擎_fs_路由基础.as（共享底层函数）
 *
 * API说明：
 *   - 技能标签跳转_旧(unit, skillName): 从外部触发技能跳帧（旧实现）
 *   - 技能man载入后跳转_旧(man, unit): man加载完成后跳转到技能帧（旧实现）
 *   - 载入后跳转技能容器(container, unit): 容器化技能入口，自动判断走容器或回退旧逻辑
 *
 * @author flashNight
 * @version 3.0 - 抽离公共逻辑到路由基础
 */

_root.技能路由 = {};

/**
 * 技能标签跳转（旧实现）
 * 用于外部代码触发技能时调用，如释放行为、AI释放等场景
 * 容器化技能跳过此步骤（由载入后跳转技能容器处理）
 *
 * @param unit:MovieClip 执行技能的单位（需要有man子剪辑）
 * @param skillName:String 技能名称（对应man时间轴上的帧标签）
 */
_root.技能路由.技能标签跳转_旧 = function(unit:MovieClip, skillName:String):Void {
    unit.技能名 = skillName;
    _root.路由基础.确保临时Y(unit);

    if (unit.兵种 === "主角-男") {
        // 容器化技能对外伪装为"技能"状态（状态改变内部会映射到"技能容器"帧）
        unit.状态改变("技能");
        _root.路由基础.准备姿态与加成(unit);
        _root.技能路由.载入后跳转技能容器(unit.container, unit);
        return;
    }

    // 非主角-男兵种走传统man跳帧逻辑
    unit.状态改变("技能");

    var newMan:MovieClip = unit.man;
    _root.路由基础.准备姿态与加成(unit);
    _root.路由基础.绑定移动函数(newMan);
    _root.路由基础.绑定结束清理(newMan, unit, "战技", "技能结束", "技能浮空");
    // _root.路由基础.处理浮空(newMan, unit, "技能浮空");
    // 主角-尾上世莉架、主角-文天等非主角-男兵种会走这条路径
    // 这些单位的资源文件为fla格式，未xfl化，导致d41aa3c提交中
    // 将_root.技能浮空重构为unit.技能浮空时未能同步适配
    //
    // 问题表现：释放技能后单位持续上升
    // 原因分析：
    //   1. 处理浮空会设置unit.技能浮空=true和unit.浮空=true
    //   2. 这些单位使用敌人版动画完毕函数，不检查技能浮空标记
    //   3. 技能结束后直接切换到站立状态，但浮空标记未清理
    //   4. 与升空函数(fly type=1)的flyOnGround/jetpackCheck产生冲突
    //      这些函数检测到技能浮空!=true时会设置flySpeed=-1导致持续上升
    //
    // 临时方案：注释掉浮空处理，禁用这些单位的空中技能浮空功能
    // 待办：将这些单位的fla资源xfl化后，统一适配新的浮空逻辑

    _root.技能路由.技能man载入后跳转_旧(newMan, unit);
};

/**
 * 技能man载入后跳转（旧实现）
 * 用于man剪辑加载完成后，根据unit.技能名跳转到对应帧
 * 典型场景：主角进入"技能"状态时，man加载后的第一帧调用
 *
 * @param man:MovieClip man剪辑自身
 * @param unit:MovieClip man的父级单位（通过unit.技能名获取目标帧）
 */
_root.技能路由.技能man载入后跳转_旧 = function(man:MovieClip, unit:MovieClip):Void {
    man.gotoAndPlay(unit.技能名);
};

/**
 * 容器化技能入口（从"技能容器"状态的container onClipEvent(load)调用）
 * 入口已由技能标签跳转_旧统一判断，此处直接执行容器化逻辑
 *
 * @param container:MovieClip 技能容器状态下的占位容器（保持不可见）
 * @param unit:MovieClip 执行技能的单位
 */
_root.技能路由.载入后跳转技能容器 = function(container:MovieClip, unit:MovieClip):Void {
    var 技能名:String = unit.技能名;
    var initObj:Object = _root.路由基础.构建容器初始化对象(container);
    var newMan:MovieClip = unit.attachMovie("技能容器-" + 技能名, "man", 0, initObj);
    _root.路由基础.处理浮空(newMan, unit, "技能浮空");
    _root.路由基础.绑定结束清理(newMan, unit, "战技", "技能结束", "技能浮空");
};

/**
 * 动画完毕处理
 */
_root.技能路由.动画完毕 = function(man:MovieClip, unit:MovieClip):Void {
    _root.路由基础.动画完毕(man, unit);
};
