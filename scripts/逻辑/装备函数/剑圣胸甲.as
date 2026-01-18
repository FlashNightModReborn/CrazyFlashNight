/**
 * 剑圣胸甲（武士铁血肩炮剑圣_胸甲）- 装备生命周期函数
 *
 * ═══════════════════════════════════════════════════════════════════════════
 * 【平衡性设计思路】
 * ═══════════════════════════════════════════════════════════════════════════
 *
 * 核心问题：肩炮只能对单体，在怪海里真正缺的是"可用频率/存在感"，而不是单次伤害。
 *
 * 设计目标（基于敌人击杀时间）：
 * - 普通怪（0.5-1s击杀）：主吃连杀割草，冷却期望≈2-3s
 * - 精英怪（1.5-3s击杀）：均衡收益，冷却期望≈4-5s
 * - 首领（15-30s击杀）：主吃基础奖励，冷却期望≈17-20s
 *
 * ═══════════════════════════════════════════════════════════════════════════
 * 【双系数击杀减CD模型】
 * ═══════════════════════════════════════════════════════════════════════════
 *
 * 核心公式：
 *   reduction = baseReward × baseMult[level] + comboReward × comboMult[level]
 *   其中：comboReward = min(maxComboReward, comboBase × comboCount)
 *
 * 双系数设计意图：
 * - baseReward（基础奖励）：不受连杀影响的固定收益，首领击杀的主要收益来源
 * - comboReward（连杀奖励）：随连杀数递增，割草的主要收益来源
 * - baseMult[level]：基础奖励系数，首领高（2.5）、普通低（0.5）
 * - comboMult[level]：连杀奖励系数，普通高（1.2）、首领相对低（0.8）
 *
 * 敌人等级系数矩阵（默认值）：
 * | 敌人等级 | baseMult | comboMult | 单杀base占比 | 满连杀base占比 |
 * |---------|----------|-----------|-------------|---------------|
 * | 普通(0) | 0.5      | 1.2       | 38%         | 14%           |
 * | 精英(1) | 1.0      | 1.0       | 60%         | 27%           |
 * | 首领(2) | 2.5      | 0.8       | 82%         | 54%           |
 *
 * ═══════════════════════════════════════════════════════════════════════════
 * 【量化对照表】（默认参数：baseReward=1.5s, comboBase=1.0s, maxCombo=4.0s）
 * ═══════════════════════════════════════════════════════════════════════════
 *
 * 单次击杀减CD（秒）：
 * | 敌人   | combo=1 | combo=2 | combo=3 | combo=4+ |
 * |--------|---------|---------|---------|----------|
 * | 普通   | 1.95s   | 3.15s   | 4.35s   | 5.55s    |
 * | 精英   | 2.5s    | 3.5s    | 4.5s    | 5.5s     |
 * | 首领   | 4.55s   | 5.35s   | 6.15s   | 6.95s    |
 *
 * 场景冷却期望：
 * - 纯割草（2 kill/s普通怪，6秒12杀）：≈2-3s
 * - 精英混战（6秒内2精英+4普通）：≈4-5s
 * - Boss战（25s内4次伤害阶段，窗口断裂）：≈17-20s
 *
 * ═══════════════════════════════════════════════════════════════════════════
 * 【防exploit设计】
 * ═══════════════════════════════════════════════════════════════════════════
 *
 * 通过敌人等级系数自然约束：
 * - 刷小怪：baseMult=0.5，单杀基础收益低，必须维持高连杀
 * - 召唤物：可额外配置为更低系数（如baseMult=0, comboMult=0.3）
 * - Boss战：连杀窗口自然断裂，无法exploit高连杀收益
 *
 * ═══════════════════════════════════════════════════════════════════════════
 * 【元件时间轴约定】（手动控制帧数，元件内不放stop）
 * ═══════════════════════════════════════════════════════════════════════════
 * - 第1帧：冷却状态
 * - 第2-14帧：启动阶段
 * - 第14帧：待机状态
 * - 第15-67帧：发射阶段
 * - 第68-87帧：收回阶段，完成后进入冷却
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
 * - 二阶：bullet_1 普通铁血飞弹（无击杀减CD）
 * - 三阶：bullet_2 追踪铁血飞弹 + 双系数击杀减CD
 * - 四阶：bullet_3 追踪铁血飞弹 + 魔法伤害 + 双系数击杀减CD
 *
 * @param {Object} ref 生命周期反射对象
 * @param {Object} param 生命周期参数：
 *   - weapon: 武器素材名称（默认"武士铁血肩炮"）
 *   - cdSeconds: CD时间秒数（默认30）
 *   - baseReward: 基础击杀奖励秒数（默认1.5）
 *   - comboBase: 连杀递增基数秒数（默认1.0）
 *   - maxComboReward: 连杀奖励上限秒数（默认4.0）
 *   - comboWindow: 连杀窗口秒数（默认5）
 *   - baseMultNormal/baseMultElite/baseMultBoss: 基础奖励系数（默认0.5/1.0/2.5）
 *   - comboMultNormal/comboMultElite/comboMultBoss: 连杀奖励系数（默认1.2/1.0/0.8）
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

    // ═══════════════════════════════════════════════════════════════════════
    // 【双系数击杀减CD系统】
    //
    // 公式：reduction = baseReward × baseMult + comboReward × comboMult
    // 其中：comboReward = min(maxComboReward, comboBase × comboCount)
    //
    // 设计目标：
    // - 普通怪：基础奖励低，主吃连杀割草（割草2 kill/s → 冷却≈2-3s）
    // - 精英怪：均衡收益（混合战 → 冷却≈4-5s）
    // - 首领：基础奖励高，连杀锦上添花（Boss战 → 冷却≈17-20s）
    //
    // 收益占比设计：
    // | 敌人   | 单杀base占比 | 满连杀base占比 |
    // |--------|-------------|---------------|
    // | 普通   | 38%         | 14%           |
    // | 精英   | 60%         | 27%           |
    // | 首领   | 82%         | 54%           |
    // ═══════════════════════════════════════════════════════════════════════

    // baseReward：基础击杀奖励（秒），不受连杀影响的固定收益
    var baseRewardSeconds:Number = (param.baseReward != undefined) ? Number(param.baseReward) : 1.5;
    if (isNaN(baseRewardSeconds) || baseRewardSeconds <= 0) baseRewardSeconds = 1.5;
    ref.baseReward = Math.ceil(baseRewardSeconds * fps);

    // comboBase：连杀递增基数（秒），每次连杀增加的额外奖励
    var comboBaseSeconds:Number = (param.comboBase != undefined) ? Number(param.comboBase) : 1.0;
    if (isNaN(comboBaseSeconds) || comboBaseSeconds <= 0) comboBaseSeconds = 1.0;
    ref.comboBase = Math.ceil(comboBaseSeconds * fps);

    // maxComboReward：连杀奖励上限（秒），防止无限叠加
    var maxComboSeconds:Number = (param.maxComboReward != undefined) ? Number(param.maxComboReward) : 4.0;
    if (isNaN(maxComboSeconds) || maxComboSeconds <= 0) maxComboSeconds = 4.0;
    ref.maxComboReward = Math.ceil(maxComboSeconds * fps);

    // comboWindow：连杀窗口（秒），超时则连杀数重置
    var comboWindowSeconds:Number = (param.comboWindow != undefined) ? Number(param.comboWindow) : 5;
    if (isNaN(comboWindowSeconds) || comboWindowSeconds <= 0) comboWindowSeconds = 5;
    ref.comboWindow = Math.ceil(comboWindowSeconds * fps);

    // 敌人等级系数矩阵 [普通(0), 精英(1), 首领(2)]
    // baseMult：基础奖励系数，首领高、普通低
    // comboMult：连杀奖励系数，普通高、首领相对低
    // 支持两种配置方式：
    // 1. 数组形式：baseMultipliers=[0.5,1.0,2.5]
    // 2. 分离参数：baseMultNormal/baseMultElite/baseMultBoss
    if (param.baseMultipliers) {
        ref.baseMultipliers = param.baseMultipliers;
    } else {
        ref.baseMultipliers = [
            (param.baseMultNormal != undefined) ? Number(param.baseMultNormal) : 0.5,
            (param.baseMultElite != undefined) ? Number(param.baseMultElite) : 1.0,
            (param.baseMultBoss != undefined) ? Number(param.baseMultBoss) : 2.5
        ];
    }
    if (param.comboMultipliers) {
        ref.comboMultipliers = param.comboMultipliers;
    } else {
        ref.comboMultipliers = [
            (param.comboMultNormal != undefined) ? Number(param.comboMultNormal) : 1.2,
            (param.comboMultElite != undefined) ? Number(param.comboMultElite) : 1.0,
            (param.comboMultBoss != undefined) ? Number(param.comboMultBoss) : 0.8
        ];
    }

    // 连杀状态追踪
    ref.comboCount = 0;        // 当前连杀数（窗口内递增，超时重置为1）
    ref.lastKillFrame = 0;     // 上次击杀的帧数（用于判断是否在窗口内）

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
    // 锁定发射者属性：肩炮作为独立装备，不继承当前武器模式的吸血/暴击/斩杀等
    ref.bulletProps.lockShooterAttributes = true;

    // 状态机：cooling, startup, ready, firing, retracting
    ref.state = "ready"; // 首次装载直接进入待机状态

    // 缓存坐标转换用的点对象，避免每帧创建
    ref.localPoint = {x: 0, y: 0};
    ref.p0 = {x: 0, y: 0};
    ref.pX = {x: 100, y: 0};
    ref.pY = {x: 0, y: 100};

    target.dispatcher.subscribe("UnitReInitialized", function() {
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

    // ═══════════════════════════════════════════════════════════════════════
    // 【三阶及以上：双系数击杀减CD事件处理】
    //
    // 算法：
    // 1. 获取敌人精英等级（0=普通, 1=精英, 2=首领）
    // 2. 检查当前击杀是否在comboWindow内，更新comboCount
    // 3. 计算连杀奖励：comboReward = min(maxComboReward, comboBase × comboCount)
    // 4. 应用双系数：reduction = baseReward × baseMult[level] + comboReward × comboMult[level]
    // 5. cdCounter += reduction
    //
    // 量化示例（默认参数）：
    // | 敌人   | combo=1 | combo=4+ |
    // |--------|---------|----------|
    // | 普通   | 1.95s   | 5.55s    |
    // | 精英   | 2.5s    | 5.5s     |
    // | 首领   | 4.55s   | 6.95s    |
    // ═══════════════════════════════════════════════════════════════════════
    if (tier == "三阶" || tier == "四阶") {
        target.dispatcher.subscribe("enemyKilled", function(hitTarget:MovieClip, bullet:MovieClip) {
            var currentFrameCount:Number = _root.帧计时器.当前帧数;

            // 获取敌人精英等级：0=普通, 1=精英, 2=首领
            var eliteLevel:Number = UnitUtil.getEliteLevel(hitTarget);
            var level:Number = Math.max(0, Math.min(2, eliteLevel)); // 限制在0-2范围

            // 连杀窗口判定：上次击杀后window秒内的击杀视为连杀
            if (currentFrameCount - ref.lastKillFrame <= ref.comboWindow) {
                ref.comboCount++;  // 窗口内递增
            } else {
                ref.comboCount = 1;  // 窗口外重置
            }
            ref.lastKillFrame = currentFrameCount;

            // 计算连杀奖励：comboBase × comboCount，上限cap到maxComboReward
            var comboReward:Number = ref.comboBase * ref.comboCount;
            if (comboReward > ref.maxComboReward) {
                comboReward = ref.maxComboReward;
            }

            // 获取该等级敌人的系数
            var baseMult:Number = ref.baseMultipliers[level];
            var comboMult:Number = ref.comboMultipliers[level];

            // 双系数公式：reduction = baseReward × baseMult + comboReward × comboMult
            var reduction:Number = ref.baseReward * baseMult + comboReward * comboMult;
            // 累加到CD进度条
            ref.cdCounter += reduction;

            // 调试信息（取消注释可查看效果）
            // var levelNames:Array = ["普通", "精英", "首领"];
            // _root.发布消息(levelNames[level] + " 连杀x" + ref.comboCount + " 减CD:" + (reduction / fps) + "秒");
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
