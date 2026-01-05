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
 * - 二阶：bullet_1 普通铁血飞弹
 * - 三阶：bullet_2 追踪铁血飞弹 + 击杀减CD
 * - 四阶：bullet_3 追踪铁血飞弹 + 魔法伤害 + 击杀减CD
 *
 * @param {Object} ref 生命周期反射对象
 * @param {Object} param 生命周期参数：
 *   - weapon: 武器素材名称（默认"武士铁血肩炮"）
 *   - cdSeconds: CD时间秒数（默认30）
 *   - killCdReduction: 击杀减CD秒数（默认1）
 *   - readyFrame: 待机帧（默认14）
 *   - endFrame: 发射结束帧（默认67）
 *   - totalFrames: 总帧数（默认87）
 *   - powerMultiplier: 威力倍率（默认5）
 *
 * XML bullet配置（在lifecycle同级，由系统预解析到ref.子弹配置）：
 *   - bullet_1: 二阶子弹配置（普通铁血飞弹）
 *   - bullet_2: 三阶子弹配置（追踪铁血飞弹）
 *   - bullet_3: 四阶子弹配置（追踪铁血飞弹 + 魔法伤害）
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

    var weapon:MovieClip = layer.attachMovie(ref.weaponAsset, ref.weaponName, ref.weaponDepth);
    weapon.stop(); // 停止自动播放，完全手动控制
    ref.weapon = weapon;
    ref.currentLayer = "底层背景";

    // 帧数配置（从param读取，带默认值）
    ref.readyFrame = param.readyFrame ? Number(param.readyFrame) : 14;
    ref.endFrame = param.endFrame ? Number(param.endFrame) : 67;
    ref.totalFrames = param.totalFrames ? Number(param.totalFrames) : 87;
    ref.currentFrame = ref.readyFrame; // 初始为待机帧

    // CD配置
    var fps:Number = _root.帧计时器.帧率;
    var cdSeconds:Number = (param.cdSeconds != undefined) ? Number(param.cdSeconds) : 30;
    if (isNaN(cdSeconds) || cdSeconds <= 0) cdSeconds = 30;
    ref.cdTotal = Math.ceil(cdSeconds * fps);
    if (isNaN(ref.cdTotal) || ref.cdTotal <= 0) ref.cdTotal = 900;
    ref.cdCounter = 0;

    // 击杀减CD配置（从param读取，默认1秒）
    var killCdSeconds:Number = (param.killCdReduction != undefined) ? Number(param.killCdReduction) : 1;
    if (isNaN(killCdSeconds) || killCdSeconds <= 0) killCdSeconds = 1;
    ref.killCdReduction = Math.ceil(killCdSeconds * fps);

    // 威力倍率
    ref.powerMultiplier = param.powerMultiplier ? Number(param.powerMultiplier) : 5;

    // 根据tier选择预解析的子弹配置（由系统在装载时解析到ref.子弹配置）
    if (tier == "四阶") {
        ref.bulletProps = ref.子弹配置.bullet_3;
    } else if (tier == "三阶") {
        ref.bulletProps = ref.子弹配置.bullet_2;
    } else {
        ref.bulletProps = ref.子弹配置.bullet_1;
    }

    // 状态机：cooling, startup, ready, firing, retracting
    ref.state = "ready"; // 首次装载直接进入待机状态

    // 缓存坐标转换用的点对象，避免每帧创建
    ref.localPoint = {x: 0, y: 0};
    ref.p0 = {x: 0, y: 0};
    ref.pX = {x: 100, y: 0};
    ref.pY = {x: 0, y: 100};

    target.dispatcher.subscribe("InitPlayerTemplateEnd", function() {
        // 玩家模板重新初始化时，清理残留weapon
        var layer:MovieClip = target.底层背景;

        if (layer[ref.weaponName]) {
            layer[ref.weaponName].removeMovieClip();
        }
        if (target[ref.weaponName]) {
            target[ref.weaponName].removeMovieClip();
        }
    }, target);

	// 用于同步渲染
	target.syncRequiredEquips.身体_引用 = true;
    target.dispatcher.subscribe("StatusChange", function(unit) {
        // 状态变更时立即同步渲染
        _root.装备生命周期函数.剑圣胸甲渲染更新(ref);
    }, target);

    // 三阶及以上：击杀减CD
    if (tier == "三阶" || tier == "四阶") {
        target.dispatcher.subscribe("enemyKilled", function(hitTarget:MovieClip, bullet:MovieClip) {
            ref.cdCounter += ref.killCdReduction;
        }, target);
    }

    target.dispatcher.subscribe("WeaponSkill", function(mode:String) {
        // 只有在待机状态才响应战技信号
        if (ref.state == "ready") {
            ref.state = "firing";
            ref.currentFrame = ref.readyFrame + 1; // 进入发射阶段

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
        // 使用预解析的子弹配置，更新坐标
        var bp:Object = ref.bulletProps;
        var attackPoint:MovieClip = ref.weapon.攻击点;

        // 坐标系转换
        var myPoint:Object = {x: attackPoint._x, y: attackPoint._y};
        attackPoint._parent.localToGlobal(myPoint);
        var 转换中间y:Number = myPoint.y;
        _root.gameworld.globalToLocal(myPoint);

        bp.shootX = myPoint.x;
        bp.shootY = myPoint.y;
        bp.转换中间y = 转换中间y;
        bp.shootZ = target.Z轴坐标;

        // 动态计算威力（基于当前属性）
        bp.子弹威力 = ((target.刀属性.power || 0) + target.内力) * ref.powerMultiplier;

        _root.子弹区域shoot传递(bp);
    });
};

/**
 * 剑圣胸甲 - 渲染更新函数
 * 更新weapon的位置、旋转和帧数显示
 *
 * @param {Object} ref 生命周期反射对象
 */
_root.装备生命周期函数.剑圣胸甲渲染更新 = function(ref:Object) {
    var weapon:MovieClip = ref.weapon;
    var target:MovieClip = ref.自机;
    var cuirass:MovieClip = target.身体_引用;

    if (!weapon || !cuirass)
        return;

    // 更新weapon显示帧
    weapon.gotoAndStop(ref.currentFrame);

    // weapon 的实际容器（以 weapon._parent 为准，避免状态与容器不同步）
    var container:MovieClip = weapon._parent ? weapon._parent : (ref.state == "firing" ? target : target.底层背景);

    // —— 位移：以 身体_引用 的原点作为挂点 ——
    // 复用缓存的点对象，重置坐标值
    var localPoint:Object = ref.localPoint;
    localPoint.x = 0;
    localPoint.y = 0;
    cuirass.localToGlobal(localPoint);
    container.globalToLocal(localPoint);
    weapon._x = localPoint.x;
    weapon._y = localPoint.y;

    // —— 旋转/翻转：用坐标变换求真实朝向，兼容动作中身体引用被镜像 ——
    // 取 身体_引用 的局部坐标系基向量，映射到 container 坐标系，得到旋转角与镜像符号
    // 复用缓存的点对象，重置坐标值
    var p0:Object = ref.p0;
    var pX:Object = ref.pX;
    var pY:Object = ref.pY;
    p0.x = 0;   p0.y = 0;
    pX.x = 100; pX.y = 0;
    pY.x = 0;   pY.y = 100;

    cuirass.localToGlobal(p0);
    cuirass.localToGlobal(pX);
    cuirass.localToGlobal(pY);
    container.globalToLocal(p0);
    container.globalToLocal(pX);
    container.globalToLocal(pY);

    var vxX:Number = pX.x - p0.x;
    var vxY:Number = pX.y - p0.y;
    var vyX:Number = pY.x - p0.x;
    var vyY:Number = pY.y - p0.y;

    var angle:Number = Math.atan2(vxY, vxX) * 180 / Math.PI;
    var det:Number = vxX * vyY - vxY * vyX; // <0 表示发生镜像（左右翻转）
    var mirrored:Boolean = (det < 0);

    if (mirrored) {
        // 镜像时用负 xscale 表达，并把由镜像带来的 180° 偏差抵消掉
        angle -= 180;
        if (weapon._xscale > 0)
            weapon._xscale = -weapon._xscale;
    } else {
        if (weapon._xscale < 0)
            weapon._xscale = -weapon._xscale;
    }
    weapon._rotation = angle;
};

/**
 * 剑圣胸甲 - 周期函数
 * 所有配置参数已在初始化时存入ref，无需param
 *
 * @param {Object} ref 生命周期反射对象（包含所有配置和状态）
 */
_root.装备生命周期函数.剑圣胸甲周期 = function(ref:Object) {
    _root.装备生命周期函数.移除异常周期函数(ref);

    var weapon:MovieClip = ref.weapon;
    var target:MovieClip = ref.自机;

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
            if (ref.currentFrame >= ref.readyFrame) {
                ref.currentFrame = ref.readyFrame;
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

    // 调用渲染更新
    _root.装备生命周期函数.剑圣胸甲渲染更新(ref);
};
