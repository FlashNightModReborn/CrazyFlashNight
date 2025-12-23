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
    能量盾: true,
    聚气: true,
    战术目镜: true,
    追猎射击: true,
    移动射击: true,
    旋风腿: true,
    升龙拳: true,
    升天斩: true,
    火舞旋风: true,
    不卸之力: true,
    空间斩: true,
    翻滚换弹: true,
    兽王崩拳: true,
    虎拳: true,
    抡枪: true,
    重力井: true,
    重力场: true,
    时间停止: true,
    一瞬千击: true,
    迅斩: true,
    觉醒震地: true,
    觉醒不坏金身: true,
    觉醒霸体: true,
    拔刀术: true,
    六连: true,
    龙斩: true,
    地震: true,
    闪现: true,
    小跳: true,
    瞬步斩: true,
    凶斩: true,
    抱腿摔: true,
    兴奋剂: true,
    组合拳: true,
    日字冲拳: true,
    踩人: true,
    气动波: true,
    背摔: true,
    火力支援: true,
    死亡绽放: true
};
// 以后严禁在技能名里面加符号！！！
_root.技能路由.容器化技能注册表["径庭拳/黑闪"] = true;

/**
 * 确保技能触发时正确记录空中Y坐标
 * 避免部分调用路径未提前写入temp_y导致空中技能无法判定为浮空
 *
 * @param unit:MovieClip 执行技能的单位
 */
_root.技能路由._确保技能临时Y = function(unit:MovieClip):Void {
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
 * 设置技能通用姿态与武器加成
 *
 * @param unit:MovieClip 执行技能的单位
 */
_root.技能路由._准备技能姿态与加成 = function(unit:MovieClip):Void {
    unit.格斗架势 = true;
    if (unit.技能名 != undefined && unit.技能名.indexOf("拳") > -1) {
        unit.根据模式重新读取武器加成("空手");
    } else {
        unit.根据模式重新读取武器加成("技能");
    }
};

/**
 * 绑定技能移动函数到技能man
 *
 * @param man:MovieClip 技能man
 */
_root.技能路由._绑定技能移动函数 = function(man:MovieClip):Void {
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
 * 绑定技能结束时的通用清理逻辑
 *
 * @param clip:MovieClip 触发onUnload的剪辑（普通技能为man，容器技能为container）
 * @param unit:MovieClip 执行技能的单位
 */
_root.技能路由._绑定技能结束清理 = function(clip:MovieClip, unit:MovieClip):Void {
    var prevOnUnload:Function = clip.onUnload;
    clip.onUnload = function() {
        if (prevOnUnload != undefined) {
            prevOnUnload.apply(this);
        }
        unit.无敌 = false;
        if (unit.状态 != "战技") {
            unit.temp_y = 0;
        }
        unit.UpdateBigSmallState("技能结束", "技能结束");
        unit.根据模式重新读取武器加成(unit.攻击模式);
    };
};

/**
 * 空中技能浮空处理（基于unit.temp_y）
 * - 设置_root.技能浮空用于技能结束后回跳跃状态
 * - 在man没有自带onEnterFrame处理时，挂载一个最小重力更新
 *
 * @param man:MovieClip 技能man
 * @param unit:MovieClip 执行技能的单位
 */
_root.技能路由._处理技能浮空 = function(man:MovieClip, unit:MovieClip):Void {
    man.落地 = true;
    if (unit.temp_y <= 0) {
        return;
    }

    if (unit._name == _root.控制目标) {
        _root.技能浮空 = true;
    }
    unit._y = unit.temp_y;
    man.落地 = false;
    unit.浮空 = true;

    var targetUnit:MovieClip = unit;
    man.onEnterFrame = function() {
        targetUnit._y += targetUnit.垂直速度;
        targetUnit.temp_y = targetUnit._y;
        targetUnit.垂直速度 += _root.重力加速度;
        if (targetUnit.跳跃中上下方向 == "上") {
            targetUnit.跳跃上下移动("上", targetUnit.跳横移速度 / 2);
        } else if (targetUnit.跳跃中上下方向 == "下") {
            targetUnit.跳跃上下移动("下", targetUnit.跳横移速度 / 2);
        }
        if (targetUnit.跳跃中左右方向 == "右") {
            targetUnit.移动("右", targetUnit.跳横移速度);
        } else if (targetUnit.跳跃中左右方向 == "左") {
            targetUnit.移动("左", targetUnit.跳横移速度);
        }
        // _root.发布消息(targetUnit._y, targetUnit.Z轴坐标);

        // 使用容差值解决浮点数精度问题（_y属性精度有限）
        if (targetUnit._y >= targetUnit.Z轴坐标 - 0.5) {
            targetUnit._y = targetUnit.Z轴坐标;
            targetUnit.temp_y = targetUnit._y;
            this.落地 = true;
            targetUnit.浮空 = false;
            if (targetUnit._name == _root.控制目标) {
                _root.技能浮空 = false;
            }
            delete this.onEnterFrame;
        } else {
            targetUnit.浮空 = true;
        }
    };
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
    _root.技能路由._确保技能临时Y(unit);

    if (_root.技能路由.容器化技能注册表[skillName]) {
        unit.状态改变("技能容器");
        _root.技能路由._准备技能姿态与加成(unit);
        _root.技能路由.载入后跳转技能容器(unit.container, unit);
        _root.技能路由._绑定技能结束清理(unit.container, unit);
        return;
    }
    // _root.发布消息("路由技能标签跳转", skillName);
    unit.状态改变("技能");

    var newMan:MovieClip = unit.man;
    _root.技能路由._准备技能姿态与加成(unit);
    _root.技能路由._绑定技能移动函数(newMan);
    _root.技能路由._绑定技能结束清理(newMan, unit);
    _root.技能路由._处理技能浮空(newMan, unit);
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
    // _root.发布消息("路由技能man载入后跳转", unit.技能名);
    man.gotoAndPlay(unit.技能名);
    // _root.发布消息(unit.man._currentframe, unit.技能名);
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
    var initObj:Object = {
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

    var newMan:MovieClip = unit.attachMovie("技能容器-" + 技能名, "man", 0, initObj);
    _root.技能路由._处理技能浮空(newMan, unit);
};

_root.技能路由.动画完毕 = function(man:MovieClip, unit:MovieClip):Void {
    unit.动画完毕();
    man.removeMovieClip();
};
