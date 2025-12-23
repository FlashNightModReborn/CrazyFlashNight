/**
 * 技能路由器 - Step 2: 容器化技能支持
 *
 * 目的：将所有"技能启动的跳帧入口"收口到统一路由，
 *       支持渐进式容器化改造。
 *
 * API说明：
 *   - 技能标签跳转_旧(unit, skillName): 从外部触发技能跳帧（旧实现）
 *   - 技能man载入后跳转_旧(man, unit): man加载完成后跳转到技能帧（旧实现）
 *   - 载入后跳转技能容器(container, unit): 容器化技能入口，自动判断走容器或回退旧逻辑
 *
 * @author flashNight
 * @version 2.0 - Step 2 容器化技能支持
 */

_root.技能路由 = {};

/**
 * 容器化技能注册表
 * 记录已完成容器化改造的技能名称
 * 技能名 -> true 表示该技能已容器化
 */
_root.技能路由.容器化技能注册表 = {
    寸拳: true,
    上帝之杖: true,
    死亡绽放: true
};

/**
 * 技能标签跳转（旧实现）
 * 用于外部代码触发技能时调用，如释放行为、AI释放等场景
 * 容器化技能跳过此步骤（由载入后跳转技能容器处理）
 *
 * @param unit:MovieClip 执行技能的单位（需要有man子剪辑）
 * @param skillName:String 技能名称（对应man时间轴上的帧标签）
 */
_root.技能路由.技能标签跳转_旧 = function(unit:MovieClip, skillName:String):Void {
    // 容器化技能跳过，由载入后跳转技能容器统一处理
    unit.技能名 = skillName;

    if (_root.技能路由.容器化技能注册表[skillName]) {
        unit.状态改变("技能容器");
        return;
    }
    // _root.发布消息("路由技能标签跳转", skillName);
    unit.状态改变("技能");
    unit.man.gotoAndPlay(skillName);
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
    // _root.发布消息("路由技能man载入后跳转", unit.技能名);
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
    
    var newMan:MovieClip = unit.attachMovie("技能容器-" + 技能名, "man", 0, {
        _x: container._x,
        _y: container._y,
        _xscale: container._xscale,
        _yscale: container._yscale
    });

    // 绑定技能移动函数
    newMan.攻击时移动 = _root.技能函数.攻击时移动;
    newMan.攻击时后退移动 = _root.技能函数.攻击时移动;
    newMan.攻击时按键四向移动 = _root.技能函数.攻击时按键四向移动;
    newMan.攻击时可改变移动方向 = _root.技能函数.攻击时可改变移动方向;
    newMan.攻击时可斜向改变移动方向 = _root.技能函数.攻击时可斜向改变移动方向;
    newMan.攻击时斜向移动 = _root.技能函数.攻击时斜向移动;
    newMan.攻击时可斜向改变移动方向2 = _root.技能函数.攻击时可斜向改变移动方向2;
    newMan.获取移动方向 = _root.技能函数.获取移动方向;

    // 浮空状态处理
    newMan.落地 = true;
    if (unit.temp_y > 0)
    {
        if (unit._name == _root.控制目标) {
            _root.技能浮空 = true;
        }
        unit._y = unit.temp_y;
        newMan.落地 = false;
        unit.浮空 = true;

        newMan.onEnterFrame = function()
        {
            unit._y += unit.垂直速度;
            unit.temp_y = unit._y;
            unit.垂直速度 += _root.重力加速度;
            if (unit.跳跃中上下方向 == "上")
            {
                unit.跳跃上下移动("上", unit.跳横移速度 / 2);
            }
            else if (unit.跳跃中上下方向 == "下")
            {
                unit.跳跃上下移动("下", unit.跳横移速度 / 2);
            }
            if (unit.跳跃中左右方向 == "右")
            {
                unit.移动("右", unit.跳横移速度);
            }
            else if (unit.跳跃中左右方向 == "左")
            {
                unit.移动("左", unit.跳横移速度);
            }
            if (unit._y >= unit.Z轴坐标)
            {
                unit._y = unit.Z轴坐标;
                unit.temp_y = unit._y;
                newMan.落地 = true;
                unit.浮空 = false;
                if (unit._name == _root.控制目标) {
                    _root.技能浮空 = false;
                }
                delete newMan.onEnterFrame;
            }
            else
            {
                unit.浮空 = true;
            }
        };
    }
};

_root.技能路由.动画完毕 = function(man:MovieClip, unit:MovieClip):Void {
    unit.动画完毕();
    man.removeMovieClip();
};