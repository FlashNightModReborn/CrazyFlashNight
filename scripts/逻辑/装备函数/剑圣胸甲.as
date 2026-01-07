/**
 * 剑圣胸甲（武士铁血肩炮剑圣_胸甲）- 装备生命周期函数
 *
 * ═══════════════════════════════════════════════════════════════════════════
 * 【平衡性设计思路】
 * ═══════════════════════════════════════════════════════════════════════════
 *
 * 核心问题：肩炮只能对单体，在怪海里真正缺的是"可用频率/存在感"，而不是单次伤害。
 *
 * 设计目标：
 * - Boss（0击杀）：维持30s基准CD（避免无成本峰值常驻）
 * - 中等怪海（约1 kill/s）：冷却完成期望落在6.5-8s（接近常见战技CD）
 * - 高密度怪海（≥2 kill/s）：基本做到每次战技都能带肩炮
 *
 * ═══════════════════════════════════════════════════════════════════════════
 * 【数学建模】
 * ═══════════════════════════════════════════════════════════════════════════
 *
 * 进度条模型：把CD看成"需要被时间+击杀共同填满的进度条"
 *
 * - 基础CD：T0 = 30s
 * - 自然流逝：每秒 +1s 进度
 * - 每次击杀：额外 +ri 进度，其中 ri = min(max, base × comboCount)
 *
 * 冷却完成条件：在时间t内，t + Σri ≥ T0
 *
 * 反推公式：
 * 假设玩家在一次战技间隔tskill内大约打出Nkill次击杀，
 * 则需要的平均每杀减CD约为：r_avg ≈ (T0 - tskill) / Nkill
 *
 * 举例（T0=30s，目标tskill≈6s，需补足24s）：
 * - 6秒内杀12只（2 kill/s）：r_avg ≈ 2.0s/kill
 * - 6秒内杀6只（1 kill/s）：r_avg ≈ 4.0s/kill
 *
 * ═══════════════════════════════════════════════════════════════════════════
 * 【连杀递增模型】reduction = base × comboCount，cap到max
 * ═══════════════════════════════════════════════════════════════════════════
 *
 * 三个旋钮的作用：
 *
 * 1) killCdReduction (base)：低频击杀时的"手感底噪"
 *    - 太低：只有极高连杀才明显，怪海仍觉得"等很久"
 *    - 太高：小规模战斗也会显著缩CD，30s形同虚设
 *    - 建议区间：1.0-1.3s
 *
 * 2) maxKillCdReduction (cap)：高连杀时的"上限补偿力度"
 *    - 这是怪海体验的关键，肩炮对群为0，只能靠频率补偿
 *    - 建议区间：4.0-5.0s
 *    - 直观含义：base=1.3，cap=5.0 → 连杀到4以后，每杀都减5秒
 *
 * 3) comboWindow：连杀判定的"苛刻程度"
 *    - 太短：稍微断一下就回到1倍，怪海也不稳定
 *    - 太长：拉怪、走位都能维持高连杀，上限收益更容易常驻
 *    - 建议区间：4-5s
 *
 * ═══════════════════════════════════════════════════════════════════════════
 * 【预设方案与量化对照】
 * ═══════════════════════════════════════════════════════════════════════════
 *
 * 默认参数（偏爽方案）：base=1.3s, max=5.0s, window=5s
 *
 * 不同击杀率下的冷却完成期望：
 * | 击杀率      | 冷却完成期望 | 能否跟上6-7s战技CD |
 * |------------|-------------|-------------------|
 * | 0.5 kill/s | ~11.6s      | 偶尔跟不上        |
 * | 1.0 kill/s | ~6.5s       | 基本跟上          |
 * | 2.0 kill/s | ~3.5s       | 肯定跟上          |
 *
 * 备选方案（偏平衡）：base=1.0s, max=4.0s, window=4s
 * | 击杀率      | 冷却完成期望 |
 * |------------|-------------|
 * | 0.5 kill/s | ~13.4s      |
 * | 1.0 kill/s | ~7.5s       |
 * | 2.0 kill/s | ~4.2s       |
 *
 * ═══════════════════════════════════════════════════════════════════════════
 * 【风险与约束建议】
 * ═══════════════════════════════════════════════════════════════════════════
 *
 * 潜在exploit：玩家若能稳定产出低成本击杀（可控刷怪/召唤物），会把30s CD击穿
 *
 * 低成本约束方案（按工程代价从低到高）：
 * 1. 仅在cooling状态接受减CD（避免ready状态吃减CD浪费但放大波次收益）
 * 2. 按敌人等级/血量做权重（杂兵1.0，精英2.0，召唤物0.2）
 * 3. 每轮冷却周期设"可获得的最大击杀减CD总量"（如T0×0.8）
 *
 * ═══════════════════════════════════════════════════════════════════════════
 * 【元件时间轴约定】（手动控制帧数，元件内不放stop）
 * ═══════════════════════════════════════════════════════════════════════════
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
 *   - killCdReduction: 基础击杀减CD秒数（默认1.3，偏爽方案）
 *   - maxKillCdReduction: 最大单次减CD秒数（默认5，偏爽方案）
 *   - comboWindow: 连杀窗口秒数（默认5）
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
    // 【连杀递增减CD系统配置】
    // 公式：reduction = min(max, base × comboCount)
    // 设计目标：怪海中1 kill/s时冷却期望≈6.5s，能跟上常见战技CD
    // ═══════════════════════════════════════════════════════════════════════

    // base（基础减CD）：控制低频击杀时的"手感底噪"
    // 建议区间1.0-1.3s，太低怪海等很久，太高小规模战斗也过度缩CD
    var killCdSeconds:Number = (param.killCdReduction != undefined) ? Number(param.killCdReduction) : 1.3;
    if (isNaN(killCdSeconds) || killCdSeconds <= 0) killCdSeconds = 1.3;
    ref.baseKillCdReduction = Math.ceil(killCdSeconds * fps);

    // max（上限减CD）：控制高连杀时的"补偿力度"，怪海体验的关键旋钮
    // 建议区间4.0-5.0s，base=1.3时连杀≥4后每杀都减max秒
    var maxKillCdSeconds:Number = (param.maxKillCdReduction != undefined) ? Number(param.maxKillCdReduction) : 5;
    if (isNaN(maxKillCdSeconds) || maxKillCdSeconds <= 0) maxKillCdSeconds = 5;
    ref.maxKillCdReduction = Math.ceil(maxKillCdSeconds * fps);

    // window（连杀窗口）：控制连杀判定的"苛刻程度"
    // 建议区间4-5s，太短断连杀太快，太长容易exploit
    var comboWindowSeconds:Number = (param.comboWindow != undefined) ? Number(param.comboWindow) : 5;
    if (isNaN(comboWindowSeconds) || comboWindowSeconds <= 0) comboWindowSeconds = 5;
    ref.comboWindow = Math.ceil(comboWindowSeconds * fps);

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

    // ═══════════════════════════════════════════════════════════════════════
    // 【三阶及以上：连杀递增减CD事件处理】
    //
    // 算法：
    // 1. 检查当前击杀是否在comboWindow内（与上次击杀的帧间隔）
    // 2. 窗口内→comboCount++，窗口外→comboCount=1
    // 3. reduction = min(max, base × comboCount)
    // 4. cdCounter += reduction（进度条累加）
    //
    // 量化示例（偏爽方案 base=1.3s, max=5s, window=5s）：
    // - 第1杀：1.3s
    // - 第2杀：2.6s
    // - 第3杀：3.9s
    // - 第4杀及以后：5.0s（触及上限）
    // ═══════════════════════════════════════════════════════════════════════
    if (tier == "三阶" || tier == "四阶") {
        target.dispatcher.subscribe("enemyKilled", function(hitTarget:MovieClip, bullet:MovieClip) {
            var currentFrameCount:Number = _root.帧计时器.当前帧数;

            // 连杀窗口判定：上次击杀后window秒内的击杀视为连杀
            if (currentFrameCount - ref.lastKillFrame <= ref.comboWindow) {
                ref.comboCount++;  // 窗口内递增
            } else {
                ref.comboCount = 1;  // 窗口外重置
            }
            ref.lastKillFrame = currentFrameCount;

            // 计算本次减CD量：base × comboCount，上限cap到max
            var reduction:Number = ref.baseKillCdReduction * ref.comboCount;
            if (reduction > ref.maxKillCdReduction) {
                reduction = ref.maxKillCdReduction;
            }

            // 累加到CD进度条（cdCounter在cooling状态下自然+1/帧）
            ref.cdCounter += reduction;

            // 调试信息（取消注释可查看连杀效果）
            // _root.发布消息("连杀x" + ref.comboCount + " 减CD:" + (reduction / fps) + "秒");
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
