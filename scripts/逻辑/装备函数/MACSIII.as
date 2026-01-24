/**
 * MACSIII 初始化函数
 *
 * 可配置参数列表（XML initParam 中配置）：
 * - executeLevel: 解锁处决（斩杀）功能的最低强化等级，默认3
 * - lifeStealLevel: 解锁汲取（吸血）功能的最低强化等级，默认6
 * - selfDamageMultiplierTier1~4: 自伤系数分段配置，默认3/4/5/6
 * - tierThreshold1~3: 自伤系数分段阈值，默认2/5/10
 * - emergencyShutdownLevel: 紧急停机功能解锁等级，默认8
 * - emergencyShutdownHpThreshold: 紧急停机触发的血量百分比，默认0.1（10%）
 * - idleDamageReductionLevel: 停火自伤减免解锁等级，默认14（实际禁用）
 * - idleDamageReductionRatio: 停火时自伤减免比例，默认0.5（50%）
 * - executeValueSingle: 仅斩杀模式下的斩杀值，默认8
 * - executeValueCombo: 斩杀+吸血模式下的斩杀值，默认10
 * - lifeStealValueSingle: 仅吸血模式下的吸血值，默认10
 * - lifeStealValueCombo: 斩杀+吸血模式下的吸血值，默认18
 */
_root.装备生命周期函数.MACSIII初始化 = function(ref:Object, param:Object) {
    var target:MovieClip = ref.自机;

    // --- 状态变量 ---
    ref.gunFrame = 1.0; // 当前循环动画帧 (普通/过载共用)
    ref.isFiring = false; // 是否正在射击
    ref.animBudget = 0.0; // 动画预算，用于平滑启停

    // --- 新增：状态机变量 ---
    ref.state = "NORMAL"; // 初始状态为 "普通"
    ref.transitionCounter = 0; // 过渡动画播放计数器

    var upgradeLevel:Number = target.长枪.value.level;

    // 【可配置】解锁处决和吸血功能的强化等级要求
    var executeLevel:Number = param.executeLevel || 3;
    var lifeStealLevel:Number = param.lifeStealLevel || 6;

    // === 【可配置】自伤系数分段配置 ===
    // 超载状态下每帧自伤伤害 = 强化等级 × 系数
    // 分段设计：等级越高，自伤系数越大，风险与收益成正比
    var tier1Multiplier:Number = param.selfDamageMultiplierTier1 || 3;  // 1-2级系数
    var tier2Multiplier:Number = param.selfDamageMultiplierTier2 || 4;  // 3-5级系数
    var tier3Multiplier:Number = param.selfDamageMultiplierTier3 || 5;  // 6-10级系数
    var tier4Multiplier:Number = param.selfDamageMultiplierTier4 || 6;  // 11+级系数
    var threshold1:Number = param.tierThreshold1 || 2;   // 第一档阈值
    var threshold2:Number = param.tierThreshold2 || 5;   // 第二档阈值
    var threshold3:Number = param.tierThreshold3 || 10;  // 第三档阈值

    // 根据强化等级计算对应的自伤系数
    var damageMultiplier:Number;
    if (upgradeLevel <= threshold1) {
        damageMultiplier = tier1Multiplier;
    } else if (upgradeLevel <= threshold2) {
        damageMultiplier = tier2Multiplier;
    } else if (upgradeLevel <= threshold3) {
        damageMultiplier = tier3Multiplier;
    } else {
        damageMultiplier = tier4Multiplier;
    }

    // 计算每帧自伤伤害值
    ref.selfDamagePerFrame = upgradeLevel * damageMultiplier;

    // === 【可配置】紧急停机系统 ===
    // 当宿主生命值过低时，强制终止超载模式以确保存活
    var emergencyShutdownLevel:Number = param.emergencyShutdownLevel || 8;
    ref.hasEmergencyShutdown = (upgradeLevel >= emergencyShutdownLevel);
    // 触发紧急停机的血量百分比阈值（0.1 = 10%血量）
    ref.emergencyShutdownHpThreshold = param.emergencyShutdownHpThreshold || 0.1;

    // === 【可配置】停火自伤减免 ===
    // 停止射击时减少自伤伤害，默认等级14解锁（实际禁用）
    var idleDamageReductionLevel:Number = param.idleDamageReductionLevel || 14;
    ref.hasIdleDamageReduction = (upgradeLevel >= idleDamageReductionLevel);
    // 停火时自伤减免比例（0.5 = 减半，即50%伤害）
    ref.idleDamageReductionRatio = param.idleDamageReductionRatio || 0.5;

    // === 【可配置】超载模式下的斩杀和吸血数值 ===
    // 单独斩杀模式的斩杀值
    var executeValueSingle:Number = param.executeValueSingle || 8;
    // 斩杀+吸血组合模式的斩杀值（更强）
    var executeValueCombo:Number = param.executeValueCombo || 10;
    // 单独吸血模式的吸血值
    var lifeStealValueSingle:Number = param.lifeStealValueSingle || 10;
    // 斩杀+吸血组合模式的吸血值（更强）
    var lifeStealValueCombo:Number = param.lifeStealValueCombo || 18;

    var execBonus:Number = (upgradeLevel >= executeLevel) ? 10 : 0;
    var lifeBonus:Number = (upgradeLevel >= lifeStealLevel) ? 18 : 0;

    var combo:Number = (execBonus ? 1 : 0) | (lifeBonus ? 2 : 0);

    function mkHandler0(ref:Object):Function {
        return function() {
            ref.isFiring = true;
            ref.自机.man.子弹属性.区域定位area = ref.自机.长枪_引用.枪口位置;
        };
    }
    function mkHandlerE(ref:Object, executeVal:Number):Function {
        return function() {
            ref.isFiring = true;
            var mc = ref.自机;
            var prop = mc.man.子弹属性;
            prop.区域定位area = mc.长枪_引用.枪口位置;
            if (mc.MACSIII超载打击许可) {
                prop.斩杀 = executeVal;
            }
        };
    }
    function mkHandlerL(ref:Object, lifeStealVal:Number):Function {
        return function() {
            ref.isFiring = true;
            var mc = ref.自机;
            var prop = mc.man.子弹属性;
            prop.区域定位area = mc.长枪_引用.枪口位置;
            if (mc.MACSIII超载打击许可) {
                prop.吸血 = lifeStealVal;
            }
        };
    }
    function mkHandlerEL(ref:Object, executeVal:Number, lifeStealVal:Number):Function {
        return function() {
            ref.isFiring = true;
            var mc = ref.自机;
            var prop = mc.man.子弹属性;
            prop.区域定位area = mc.长枪_引用.枪口位置;
            if (mc.MACSIII超载打击许可) {
                prop.斩杀 = executeVal;
                prop.吸血 = lifeStealVal;
            }
        };
    }

    var handlerTable:Array = [
        mkHandler0(ref),
        mkHandlerE(ref, executeValueSingle),
        mkHandlerL(ref, lifeStealValueSingle),
        mkHandlerEL(ref, executeValueCombo, lifeStealValueCombo)
    ];
    target.dispatcher.subscribe("长枪射击", handlerTable[combo]);
};

/**
 * MACSIII 周期函数
 *
 * 可配置参数列表（XML initParam 中配置）：
 * - normalLoopFrames: 普通循环动画的总帧数，默认4
 * - overloadOffset: 过载循环动画的帧偏移量，默认4
 * - toOverloadStartFrame: 普通→过载过渡动画的起始帧，默认9
 * - toOverloadTotalFrames: 普通→过载过渡动画的总帧数，默认4
 * - toNormalStartFrame: 过载→普通过渡动画的起始帧，默认13
 * - toNormalTotalFrames: 过载→普通过渡动画的总帧数，默认4
 * - animBudgetIncrease: 射击时动画预算增长速率，默认10.0
 * - animBudgetMax: 动画预算上限，默认60.0
 * - emergencyShutdownMessage: 紧急停机时显示的消息文本
 * - emergencyShutdownColor: 紧急停机消息的颜色，默认#FF6600
 */
_root.装备生命周期函数.MACSIII周期 = function(ref:Object, param:Object) {
    //_root.装备生命周期函数.移除异常周期函数(ref);

    var target:MovieClip = ref.自机;
    var gun:MovieClip = target.长枪_引用;

    // === 【可配置】动画帧常量定义 ===
    var NORMAL_LOOP_FRAMES:Number = param.normalLoopFrames || 4;         // 普通循环动画总帧数
    var OVERLOAD_OFFSET:Number = param.overloadOffset || 4;              // 过载动画帧偏移（帧5=1+4）
    var TO_OVERLOAD_START_FRAME:Number = param.toOverloadStartFrame || 9;    // 普通→过载过渡起始帧
    var TO_OVERLOAD_TOTAL_FRAMES:Number = param.toOverloadTotalFrames || 4;  // 普通→过载过渡帧数
    var TO_NORMAL_START_FRAME:Number = param.toNormalStartFrame || 13;       // 过载→普通过渡起始帧
    var TO_NORMAL_TOTAL_FRAMES:Number = param.toNormalTotalFrames || 4;      // 过载→普通过渡帧数

    var animFrame:Number; // 最终要播放的动画帧

    // === 【可配置】动画预算系统 ===
    // 动画预算用于实现平滑的启停效果，射击时快速播放，停火时缓慢减速
    var animBudgetIncrease:Number = param.animBudgetIncrease || 10.0;  // 射击时预算增长速率
    var animBudgetMax:Number = param.animBudgetMax || 60.0;            // 预算上限，防止无限累积

    // 动画预算增长逻辑
    if (ref.isFiring)
        ref.animBudget += animBudgetIncrease;  // 射击时增加预算
    if (ref.animBudget > animBudgetMax)
        ref.animBudget = animBudgetMax;        // 限制上限

    var frameAdvance:Number = 0.0;
    if (ref.animBudget >= 1.0) {
        frameAdvance = 1.0;
        ref.animBudget -= 1.0;
    } else if (ref.animBudget > 0.0) {
        frameAdvance = ref.animBudget;
        ref.animBudget = 0.0;
    }

    // ========== 超载自伤机制 ==========
    if (target.MACSIII超载打击许可 && target.MACSIII超载打击剩余时间 > 0) {
        var selfDamage:Number = ref.selfDamagePerFrame;

        // 【可配置】停火时自伤减免（通过等级配置控制是否启用）
        if (ref.hasIdleDamageReduction && !ref.isFiring) {
            selfDamage = (selfDamage * ref.idleDamageReductionRatio) | 0;
        }

        // 应用自伤并更新血条显示
        target.hp -= selfDamage;
        BloodBarEffectHandler.updateStatus(target);

        // === 【可配置】紧急停机系统 ===
        // 当血量低于阈值时，强制终止超载模式
        if (ref.hasEmergencyShutdown && target.hp < target.hp满血值 * ref.emergencyShutdownHpThreshold) {
            target.MACSIII超载打击许可 = false;
            target.MACSIII超载打击剩余时间 = 0;
            target.man.初始化长枪射击函数(); // 紧急停机时刷新射击函数

            // 【可配置】显示紧急停机消息
            var shutdownMsg:String = param.emergencyShutdownMessage || "⚠ 纳米机器人紧急停机！";
            var shutdownColor:String = param.emergencyShutdownColor || "#FF6600";
            _root.发布消息("<font color='" + shutdownColor + "'>" + shutdownMsg + "</font>");
        }

        // 死亡检测
        if (target.hp <= 0) {
            target.hp = 0;
            target.MACSIII超载打击许可 = false;
            target.dispatcher.publish("kill", target);
        }
    }

    // --- 核心状态机 ---
    switch (ref.state) {
        case "NORMAL":
            // 检查是否要启动超载
            if (target.MACSIII超载打击许可 && target.MACSIII超载打击剩余时间 > 0) {
                ref.state = "TO_OVERLOAD";
                ref.transitionCounter = 0;
            } else {
                // 播放普通循环动画
                ref.gunFrame += frameAdvance;
                if (ref.gunFrame > NORMAL_LOOP_FRAMES)
                    ref.gunFrame -= NORMAL_LOOP_FRAMES;
                animFrame = Math.floor(ref.gunFrame);
            }
            break;

        case "TO_OVERLOAD": // 播放"普通 -> 过载"过渡动画
            animFrame = TO_OVERLOAD_START_FRAME + ref.transitionCounter;
            ref.transitionCounter++;
            if (ref.transitionCounter >= TO_OVERLOAD_TOTAL_FRAMES) {
                ref.state = "OVERLOAD"; // 过渡完毕，进入过载状态
                ref.gunFrame = 1.0; // 重置循环帧，准备播放过载循环
            }
            break;

        case "OVERLOAD":
            // 检查超载时间是否结束
            if (--target.MACSIII超载打击剩余时间 < 0) {
                target.MACSIII超载打击许可 = false;
                ref.state = "TO_NORMAL"; // 时间到，进入"过载 -> 普通"过渡
                ref.transitionCounter = 0;

                // 超载结束时刷新射击函数，确保斩杀和吸血属性被卸载
                target.man.初始化长枪射击函数();
            } else {
                // 播放过载循环动画
                ref.gunFrame += frameAdvance;
                if (ref.gunFrame > NORMAL_LOOP_FRAMES)
                    ref.gunFrame -= NORMAL_LOOP_FRAMES;
                animFrame = Math.floor(ref.gunFrame) + OVERLOAD_OFFSET;
            }
            break;

        case "TO_NORMAL": // 播放"过载 -> 普通"过渡动画
            animFrame = TO_NORMAL_START_FRAME + ref.transitionCounter;
            ref.transitionCounter++;
            if (ref.transitionCounter >= TO_NORMAL_TOTAL_FRAMES) {
                ref.state = "NORMAL"; // 过渡完毕，返回普通状态
                ref.gunFrame = 1.0; // 重置循环帧，准备播放普通循环
            }
            break;
    }

    // 安全检查并应用最终帧
    if (animFrame) {
        gun.gotoAndStop(Math.floor(animFrame));
    }

    // 重置射击状态
    ref.isFiring = false;
};
