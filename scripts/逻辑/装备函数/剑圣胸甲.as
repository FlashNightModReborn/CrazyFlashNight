/**
 * 剑圣胸甲（武士铁血肩炮剑圣_胸甲）- 装备生命周期函数
 *
 * 元件时间轴约定（手动控制帧数，元件内不放stop）：
 * - 第1帧：冷却状态
 * - 第2-14帧：启动阶段
 * - 第14帧：待机状态
 * - 第15-71帧：发射阶段
 * - 第71帧后：回到第1帧开始冷却
 *
 * 状态机：
 * - "cooling": 冷却中，停在第1帧，累计CD计数
 * - "startup": 启动中，每帧推进2-14帧
 * - "ready": 待机，停在第14帧，等待WeaponSkill信号
 * - "firing": 发射中，每帧推进15-67帧
 * - "retracting": 收回中，每帧推进68-87帧，完成后进入冷却
 *
 * 进阶等级效果：
 * - 无进阶：不挂载肩炮，直接移除周期函数
 * - 二阶：普通铁血飞弹
 * - 三阶：追踪铁血飞弹
 * - 四阶：追踪铁血飞弹 + 魔法伤害
 *
 * @param {Object} ref 生命周期反射对象
 * @param {Object} param 生命周期参数（支持：weapon, cdSeconds, totalFrames）
 */
_root.装备生命周期函数.剑圣胸甲初始化 = function(ref:Object, param:Object) {
    var target:MovieClip = ref.自机;

    // 获取装备进阶等级
    var equipItem:Object = target[ref.装备类型];
    var tier:String = equipItem && equipItem.value ? equipItem.value.tier : null;
    ref.tier = tier;

    // 无进阶：不挂载肩炮，直接移除周期函数
    if (!tier) {
        _root.装备生命周期函数.移除周期函数(ref);
        return;
    }

    ref.weaponAsset = param.weapon ? param.weapon : "武士铁血肩炮";
    ref.weaponDepth = 10000;
    ref.weaponName = ref.weaponAsset + "剑圣_胸甲";

    var layer:MovieClip = target.底层背景;

    // 兜底：移除可能残留的旧weapon实例
    if (layer[ref.weaponName]) {
        layer[ref.weaponName].removeMovieClip();
    }
    if (target[ref.weaponName]) {
        target[ref.weaponName].removeMovieClip();
    }

    var weapon:MovieClip = layer.attachMovie(ref.weaponAsset, ref.weaponName, ref.weaponDepth);
    weapon.stop(); // 停止自动播放，完全手动控制
    ref.weapon = weapon;
    ref.currentLayer = "底层背景";

    // 帧数配置
    ref.currentFrame = 14; // 初始为待机帧
    ref.endFrame = 67;
    ref.totalFrames = param.totalFrames ? param.totalFrames : 87;

    // CD配置
    var fps:Number = _root.帧计时器.帧率;
    var cdSeconds:Number = (param.cdSeconds != undefined) ? Number(param.cdSeconds) : 30;
    if (isNaN(cdSeconds) || cdSeconds <= 0) cdSeconds = 30;
    ref.cdTotal = Math.ceil(cdSeconds * fps);
    if (isNaN(ref.cdTotal) || ref.cdTotal <= 0) ref.cdTotal = 900;
    ref.cdCounter = 0;

    // 状态机：cooling, startup, ready, firing, retracting
    ref.state = "ready"; // 首次装载直接进入待机状态

    target.dispatcher.subscribe("WeaponSkill", function(mode:String) {
        // 只有在待机状态才响应战技信号
        if (ref.state == "ready") {
            ref.state = "firing";
            ref.currentFrame = 15;

            // 立即切换到target层
            var weapon:MovieClip = ref.weapon;
            weapon.removeMovieClip();
            weapon = target.attachMovie(ref.weaponAsset, ref.weaponName, ref.weaponDepth);
            weapon.stop();
            weapon.gotoAndStop(ref.currentFrame);
            ref.weapon = weapon;
            ref.currentLayer = "target";
        }
    }, target);

    target.dispatcher.subscribe("铁血肩炮射击", function() {
        // 初始化子弹属性
        var target:MovieClip = ref.自机;
        var tier:String = ref.tier;
        子弹属性 = _root.子弹属性初始化(ref.weapon.攻击点, null, target);

        // 设置基本属性
        子弹属性.声音 = "";
        子弹属性.霰弹值 = 3;
        子弹属性.子弹散射度 = 15;
        子弹属性.发射效果 = "";
        子弹属性.子弹威力 = (target.刀属性.power || 0 + target.内力) * 5;
        子弹属性.子弹速度 = 30;
        子弹属性.击中地图效果 = "";
        子弹属性.Z轴攻击范围 = 930;
        子弹属性.击倒率 = 0;
        子弹属性.击中后子弹的效果 = "铁血弹爆炸";
        子弹属性.水平击退速度 = NaN;
        子弹属性.垂直击退速度 = NaN;

        // 根据进阶等级设置子弹类型和伤害类型
        if (tier == "四阶") {
            // 四阶：追踪弹 + 魔法伤害
            子弹属性.子弹种类 = "追踪铁血飞弹";
            子弹属性.伤害类型 = "魔法";
            子弹属性.魔法伤害属性 = undefined;
        } else if (tier == "三阶") {
            // 三阶：追踪弹
            子弹属性.子弹种类 = "追踪铁血飞弹";
            子弹属性.伤害类型 = "破击";
            子弹属性.魔法伤害属性 = "原体";
        } else {
            // 二阶：普通弹
            子弹属性.子弹种类 = "铁血飞弹";
            子弹属性.伤害类型 = "破击";
            子弹属性.魔法伤害属性 = "原体";
        }

        _root.发布消息("铁血肩炮射击", 子弹属性.子弹威力);
        _root.子弹区域shoot传递(子弹属性);
    });
};

/**
 * 剑圣胸甲 - 周期函数
 *
 * @param {Object} ref 生命周期反射对象
 * @param {Object} param 生命周期参数
 */
_root.装备生命周期函数.剑圣胸甲周期 = function(ref:Object, param:Object) {
    _root.装备生命周期函数.移除异常周期函数(ref);

    var weapon:MovieClip = ref.weapon;
    var target:MovieClip = ref.自机;
    var cuirass:MovieClip = target.身体_引用;

    // 状态机逻辑
    switch (ref.state) {
        case "cooling":
            // 冷却中，累计计数
            ref.cdCounter++;
            if (ref.cdCounter >= ref.cdTotal) {
                ref.cdCounter = 0;
                ref.state = "startup";
                ref.currentFrame = 2;
            }
            break;

        case "startup":
            // 启动阶段，推进帧数
            ref.currentFrame++;
            if (ref.currentFrame >= 14) {
                ref.currentFrame = 14;
                ref.state = "ready";
            }
            break;

        case "ready":
            // 待机状态，等待WeaponSkill信号，不推进帧数
            break;

        case "firing":
            // 发射阶段，推进帧数
            ref.currentFrame++;
            if (ref.currentFrame > ref.endFrame) {
                // 发射结束，进入收回阶段
                ref.currentFrame = ref.endFrame + 1; // 68帧
                ref.state = "retracting";

                // 切换回底层背景
                weapon.removeMovieClip();
                weapon = target.底层背景.attachMovie(ref.weaponAsset, ref.weaponName, ref.weaponDepth);
                weapon.stop();
                ref.weapon = weapon;
                ref.currentLayer = "底层背景";
            }
            break;

        case "retracting":
            // 收回阶段，推进帧数
            ref.currentFrame++;
            if (ref.currentFrame > ref.totalFrames) {
                // 收回结束，进入冷却状态
                ref.currentFrame = 1;
                ref.state = "cooling";
            }
            break;
    }

    // 更新weapon显示帧
    weapon.gotoAndStop(ref.currentFrame);

    // 判断当前应该在哪个层
    var needTargetLayer:Boolean = (ref.state == "firing");

    // 将胸甲的局部坐标转换为全局坐标
    var globalPoint:Object = {x: cuirass._x, y: cuirass._y};
    cuirass._parent.localToGlobal(globalPoint);

    // 将全局坐标转换为weapon所在容器的局部坐标
    var localPoint:Object = {x: globalPoint.x, y: globalPoint.y};
    var weaponLayer:MovieClip = needTargetLayer ? target : target.底层背景;
    weaponLayer.globalToLocal(localPoint);

    weapon._x = localPoint.x;
    weapon._y = localPoint.y;

    // 计算累积缩放（检测翻转）
    var scaleX:Number = cuirass._xscale * cuirass._parent._xscale * cuirass._parent._parent._xscale / 10000;
    var isFlipped:Boolean = scaleX < 0;

    // 计算旋转角度
    var rotation:Number = cuirass._rotation + cuirass._parent._rotation + cuirass._parent._parent._rotation;

    // 根据翻转状态调整weapon
    if (isFlipped) {
        weapon._xscale = -100;
        weapon._rotation = -rotation;
    } else {
        weapon._xscale = 100;
        weapon._rotation = rotation;
    }
};
