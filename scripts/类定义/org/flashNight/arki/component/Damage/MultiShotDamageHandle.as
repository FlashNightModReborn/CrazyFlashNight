import org.flashNight.arki.component.Damage.*;
import org.flashNight.arki.component.StatHandler.*;
import org.flashNight.naki.RandomNumberEngine.*;

/**
 * MultiShotDamageHandle 类是用于处理联弹伤害的处理器。
 * - 当子弹具有联弹属性且不穿刺时，根据子弹的霰弹值、目标的血量和损伤值，计算实际消耗的霰弹值。
 * - 更新子弹的霰弹值和目标的损伤值，并将结果存储在 DamageResult 中。
 */
class org.flashNight.arki.component.Damage.MultiShotDamageHandle extends BaseDamageHandle implements IDamageHandle {

    // ========== 单例实例 ==========

    /** 单例实例 */
    public static var instance:MultiShotDamageHandle = new MultiShotDamageHandle();

    // ========== 随机数引擎（联弹分段躲闪建模用） ==========

    private static var RNG:LinearCongruentialEngine = LinearCongruentialEngine.getInstance();

    // 预分配的采样结果数组（避免每次调用时创建新数组）
    // [missCount, bounceCount, penCount, instantCount]
    private static var sampleCounts:Array = [0, 0, 0, 0];

    // ========== 构造函数 ==========

    /**
     * 构造函数。
     * 调用父类构造函数以初始化基类。
     */
    public function MultiShotDamageHandle() {
        super();
    }

    /**
     * 获取 MultiShotDamageHandle 的单例实例。
     * 
     * - 若实例不存在，则创建一个新的 MultiShotDamageHandle 实例并返回。
     * - 若实例已存在，则直接返回已创建的实例。
     * - 此方法通过闭包优化后续调用，避免多次判断，提升性能。
     * 
     * @return MultiShotDamageHandle 单例实例
     */
    public static function getInstance():MultiShotDamageHandle {
        return instance;
    }

    // ========== 公共方法 ==========

    /**
     * 判断子弹是否具有联弹属性
     *
     * 历史变更：
     * - 早期版本：判断条件为 bullet.联弹检测 && !bullet.穿刺检测（联弹且不穿刺）
     * - 位运算优化：使用位标志 FLAG_CHAIN 替代布尔属性检测，提升性能
     * - 当前版本：仅检测联弹标志，穿刺处理逻辑移至 handleBulletDamage 中
     *
     * @param bullet 子弹对象
     * @return Boolean 如果子弹具有联弹属性则返回 true，否则返回 false
     */
    public function canHandle(bullet:Object):Boolean {
        // 使用位标志优化联弹检测性能
        // FLAG_CHAIN 为联弹属性的位掩码
        #include "../macros/FLAG_CHAIN.as"
        return (bullet.flags & FLAG_CHAIN) != 0;
    }

    /**
     * 处理联弹伤害
     *
     * 核心功能：
     * - 根据子弹霰弹值、目标血量和损伤值计算实际消耗
     * - 使用影子记账机制优化对群手感
     * - 支持纵向穿刺联弹的覆盖率削弱
     *
     * 性能优化（2025年9月）：
     * - 信任BulletQueueProcessor的初始化，移除冗余检查
     * - 使用位运算优化类型检测和数值计算
     * - 简化为单一快速路径，减少分支判断
     *
     * @param bullet  子弹对象
     * @param shooter 射击者对象
     * @param target  目标对象
     * @param manager 管理器对象
     * @param result  伤害结果对象
     */
    public function handleBulletDamage(bullet:Object, shooter:Object, target:Object, manager:Object, result:DamageResult):Void {
        // 位标志常量注入（编译时零开销）
        #include "../macros/FLAG_PIERCE.as"
        #include "../macros/FLAG_VERTICAL.as"
        #include "../macros/FLAG_NORMAL.as"
        #include "../macros/FLAG_TRANSPARENCY.as"

        var PIERCE_AND_VERTICAL_MASK:Number = FLAG_PIERCE | FLAG_VERTICAL;
        var RELEVANT_BITS_MASK:Number = FLAG_NORMAL | FLAG_TRANSPARENCY;
        var EXPECTED_STATE:Number = FLAG_NORMAL;

        var overlapRatio:Number = manager.overlapRatio;
        var isNormalNonTransparent:Boolean = (bullet.flags & RELEVANT_BITS_MASK) == EXPECTED_STATE;

        // 影子记账检测：原位位编码方案
        // 编码格式：bullet.霰弹值 = -((S₀ << 16) | available)
        // 甄别：sc < -65535（NaN < x → undefined → falsy，安全；用 < 不用 <= 规避 AS2 NaN 陷阱）
        var sc:Number = bullet.霰弹值;                    // H01: 局部化缓存，1 次哈希查找
        var isShadow:Boolean = (sc < -65535);             // ~29ns 算术比较，替代 ~158ns 属性 miss 检查

        // DodgeStateDamageHandle 若提前退出，会设置该标记：联弹需要在此处做分段躲闪建模（方案B）
        var useSegmentDodgeModel:Boolean = (result.deferChainDodgeState === true);

        // 获取霰弹值：位解码 或 直接读取
        var currentScatter:Number, scatterForCalc:Number;
        var baseSc:Number, available:Number;

        if (isShadow) {
            // 影子记账模式：从编码负值中解码 base 和 available
            var state:Number = -sc;                       // 取负还原为正数
            baseSc = state >>> 16;                        // 高16位 = S₀（基准值）
            available = state & 0xFFFF;                   // 低16位 = 剩余可用值
            scatterForCalc = baseSc;                      // INV-5: 用解码基准值估算期望伤害
        } else {
            // 直接模式：使用当前霰弹值（未经编码的正数或0）
            currentScatter = sc > 0 ? sc : 0;             // 用缓存的 sc，不重读属性
            scatterForCalc = currentScatter;
        }

        // 纵向穿刺削弱（覆盖率降至39%）
        if ((bullet.flags & PIERCE_AND_VERTICAL_MASK) == PIERCE_AND_VERTICAL_MASK) {
            overlapRatio = overlapRatio * 7 / 18;
        }

        // 核心伤害计算
        var A:Number = bullet.最小霰弹值 + overlapRatio * (scatterForCalc - bullet.最小霰弹值 + 1) * 1.2;
        var B:Number;

        var rawDamage:Number, bounceDamage:Number, penetrationDamage:Number;
        var dodgeProb:Number, bounceProb:Number;

        if (useSegmentDodgeModel) {
            rawDamage = target.损伤值;
            if (rawDamage != rawDamage) rawDamage = 0;

            var def:Number = target.防御力;

            // 跳弹/过穿单段伤害（内联，避免函数调用开销）
            var t:Number = (rawDamage - (def / 5)) | 0;
            bounceDamage = (t < 1) ? 1 : t;
            t = (rawDamage * 300 / (def + 300)) >> 0;
            penetrationDamage = (t < 1) ? 1 : t;

            // 是否为 NOT_DODGE 路径：外层 sigmoid 已 roll 失败 → 弹丸不进入躲闪系统。
            // 仅在 target.懒闪避>0 时这条路径才会进入分段建模（DodgeStateDamageHandle 已守门）。
            var isNotDodge:Boolean = (manager.dodgeState === DodgeStatus.NOT_DODGE);

            // 躲闪系统内：MISS概率（与 DodgeHandler.checkDodgeState 一致）
            // NOT_DODGE：dodgeProb=0，不能每段重抽 MISS，否则等同于双重判定。
            var weight:Number = target.重量;
            var tmp:Number;
            if (isNotDodge) {
                dodgeProb = 0;
            } else {
                tmp = (target.等级 - weight);
                dodgeProb = (tmp < 0) ? 0 : ((tmp > 100) ? 1 : (tmp / 100));
                if (dodgeProb != dodgeProb) dodgeProb = 0;
            }

            // 缓存类级常量（避免重复属性查找开销）
            var PENETRATION_BASE:Number = DodgeHandler.PENETRATION_BASE_WEIGHT;
            var BOUNCE_BASE:Number = DodgeHandler.JUMP_BOUNCE_BASE_WEIGHT;
            var BOUNCE_RANGE:Number = DodgeHandler.BOUNCE_PENETRATION_RANGE_WEIGHT;

            // 躲闪系统内：跳弹概率（条件于未MISS，逻辑与 DodgeHandler.checkDodgeState 一致）
            tmp = weight - PENETRATION_BASE;
            bounceProb = (tmp < 0) ? 0 : (weight >= BOUNCE_BASE ? 1 : (tmp / BOUNCE_RANGE));
            if (bounceProb != bounceProb) bounceProb = 0;

            // 躲闪系统内单段命中伤害期望（不考虑懒闪避）
            var hitDamageInDodgeSystem:Number = bounceProb * bounceDamage + (1 - bounceProb) * penetrationDamage;

            // 单段实际命中伤害：用于 instantProb 的校准基线
            // - NOT_DODGE：rawDamage（非 instant 弹丸全伤命中，不二次衰减）
            // - 已躲闪系统：hitDamageInDodgeSystem（bounce/pen 加权）
            var perPelletHitDamage:Number = isNotDodge ? rawDamage : hitDamageInDodgeSystem;

            // 预计算懒闪避概率（用于 B 计算和后续采样）
            // 注意：此处计算的 instantProb 后续在分段建模时直接复用，避免重复调用 calcLazyMissProbability
            var lazyMissValue:Number = target.懒闪避;
            var instantProb:Number = 0;
            if (lazyMissValue > 0) {
                instantProb = RNG.calcLazyMissProbability(target.hp, target.hp满血值, lazyMissValue, perPelletHitDamage);
            }

            // 期望单段伤害（考虑懒闪避）：
            // - NOT_DODGE：E[伤害] = (1 - instantProb) * rawDamage（非 instant 全伤）
            // - 已躲闪系统：E[伤害] = (1 - instantProb) * (1 - dodgeProb) * hitDamageInDodgeSystem
            var expectedPelletDamage:Number = isNotDodge
                ? (1 - instantProb) * rawDamage
                : (1 - instantProb) * (1 - dodgeProb) * hitDamageInDodgeSystem;
            B = (expectedPelletDamage > 0) ? (target.hp / expectedPelletDamage) : target.hp;

        } else {
            B = target.损伤值 > 0 ? target.hp / target.损伤值 : target.hp;
        }
        var C:Number = A < B ? A : B;
        var ceilC:Number = (C > (C >> 0)) ? (C >> 0) + 1 : (C >> 0);

        // 计算实际消耗
        var availableScatter:Number = isShadow ? available : currentScatter;
        var actualScatterUsed:Number = availableScatter < ceilC ? availableScatter : ceilC;

        // 向上取整避免0段
        if (actualScatterUsed < 1) actualScatterUsed = 1;

        // 更新霰弹值
        if (isShadow && isNormalNonTransparent) {
            // 影子记账：扣减可用值并重新编码写回（1 次哈希写入）
            available -= actualScatterUsed;
            if (available < 0) available = 0;
            bullet.霰弹值 = -((baseSc << 16) | available);
            result.finalScatterValue = available;
        } else if (isShadow) {
            // 影子模式下的非普通子弹（穿刺/透明）：不消耗，不编码
            result.finalScatterValue = available;
        } else if (isNormalNonTransparent) {
            // 直接模式：扣减并写回正数
            currentScatter -= actualScatterUsed;
            if (currentScatter < 0) currentScatter = 0;
            bullet.霰弹值 = currentScatter;
            result.finalScatterValue = currentScatter;
        } else {
            // 非普通子弹且非影子模式：不消耗
            result.finalScatterValue = currentScatter;
        }

        // 设置结果
        result.actualScatterUsed = actualScatterUsed;

        // ==================== 方案B：联弹分段躲闪建模 ====================
        // 将联弹视作"n次独立命中试验"的统计模型，按外层 dodgeState 选择类别空间。
        //
        // 【概率模型说明】
        // 原始流程中事件发生顺序：
        //   1. 懒闪避判定（独立于躲闪系统，优先级最高）
        //   2. 躲闪系统判定（进入后分为 MISS/跳弹/过穿；未进入则普通命中）
        //
        // 类别空间按外层 dodgeState 分叉：
        //
        // (a) NOT_DODGE 路径（外层 sigmoid 已 roll 失败，弹丸不进入躲闪系统）
        //     仅 target.懒闪避>0 时由 DodgeStateDamageHandle 放进来。
        //     二类别 Bernoulli：
        //       P(直感)     = instantProb                  - 懒闪避触发，伤害 0
        //       P(普通命中) = 1 - instantProb              - 全伤命中（rawDamage，不二次衰减）
        //
        // (b) 已进入躲闪系统（DODGE/JUMP_BOUNCE/PENETRATION/INSTANT_FEEL）
        //     四类别互斥概率分布（需归一化到和为1）：
        //       P(直感) = pInstant                                       - 懒闪避触发
        //       P(MISS) = (1-pInstant) * dodgeProb                       - 未懒闪避 → 躲闪系统 → MISS
        //       P(跳弹) = (1-pInstant) * (1-dodgeProb) * bounceProb      - 未懒闪避 → 躲闪系统 → 未MISS → 跳弹
        //       P(过穿) = (1-pInstant) * (1-dodgeProb) * (1-bounceProb)  - 剩余
        if (useSegmentDodgeModel) {
            // ========== 懒闪避概率已在上方 B 计算时预计算（instantProb），直接复用 ==========
            var missCount:Number;
            var bounceCount:Number;
            var penCount:Number;
            var instantCount:Number;
            var normalCount:Number;
            var totalDamage:Number;

            if (isNotDodge) {
                // ========== NOT_DODGE：二元 Bernoulli（instant ↔ normal） ==========
                // 不二次衰减：与单弹 NOT_DODGE 默认分支语义一致；
                // bounceProb/dodgeProb 不参与采样，避免把"普通命中"错误归类为跳弹/过穿。
                missCount = 0;
                bounceCount = 0;
                penCount = 0;
                if (instantProb == 0) {
                    // 短路：本次无懒闪避概率，所有弹丸 normal，省 N 次 nextFloat()
                    instantCount = 0;
                } else {
                    // 小 n 直接循环：1 比较/弹丸，比 multinomialSample4 的 2 比较更省
                    instantCount = 0;
                    var i:Number = 0;
                    do {
                        if (RNG.nextFloat() < instantProb) instantCount++;
                    } while (++i < actualScatterUsed);
                }
                normalCount = actualScatterUsed - instantCount;

                // 汇总主伤害：只有 normal 段造成伤害，instant 段为 0
                // 单段伤害取整对齐 DodgeStateDamageHandle.default 分支：(d>1)?(d|0):1
                // 避免 totalDamage 在事件分发与飘字阶段保留浮点尾数。
                var pelletDamage:Number = (rawDamage > 1) ? (rawDamage | 0) : 1;
                totalDamage = normalCount * pelletDamage;
                target.损伤值 = totalDamage;

                // 颜色不覆盖：保留 UniversalDamageHandle 设置的常规命中色（物理/破击/魔法/真伤）

                // 伤害数字大小：normalCount/actualScatterUsed 作为命中比例
                if (actualScatterUsed > 0) {
                    result.damageSize *= (0.5 + 0.5 * (normalCount / actualScatterUsed));
                }

                // 写入 DamageResult：normal 计数 + instant 合并到 miss 槽
                result.scatterModelEnabled = true;
                result.scatterNormalCount = normalCount;
                result.scatterBounceCount = 0;
                result.scatterPenetrationCount = 0;
                result.scatterMissCount = instantCount;  // 直感复用 miss 显示通道
                result.scatterNormalDamage = pelletDamage;
                result.scatterBounceDamage = 0;
                result.scatterPenetrationDamage = 0;
            } else {
                // ========== 已进入躲闪系统：四类别建模 ==========
                // 关键：必须保证 pInstant + pMiss + pBounce + pPen = 1
                var notInstant:Number = 1 - instantProb;
                var pMiss:Number = notInstant * dodgeProb;
                var pBounce:Number = notInstant * (1 - dodgeProb) * bounceProb;
                // pPen = notInstant * (1 - dodgeProb) * (1 - bounceProb) = 1 - pInstant - pMiss - pBounce

                // 优化路径选择：
                // - instantProb == 0 时走三类别简化版本（省一次类别判定）
                // - n ≤ 12 时直接循环（性能测试平衡点 n=11，游戏中霰弹值典型范围 3-12）
                // - n > 12 时使用高斯近似
                if (instantProb == 0) {
                    // 无懒闪避：使用三类别采样
                    RNG.multinomialSample3(actualScatterUsed, dodgeProb, (1 - dodgeProb) * bounceProb, sampleCounts);
                    missCount = sampleCounts[0];
                    bounceCount = sampleCounts[1];
                    penCount = sampleCounts[2];
                    instantCount = 0;
                } else {
                    // 有懒闪避：使用四类别采样
                    RNG.multinomialSample4(actualScatterUsed, pMiss, pBounce, instantProb, sampleCounts);
                    missCount = sampleCounts[0];
                    bounceCount = sampleCounts[1];
                    penCount = sampleCounts[2];
                    instantCount = sampleCounts[3];
                }

                // 汇总主伤害：只有跳弹和过穿造成伤害，MISS 和直感不造成伤害
                totalDamage = bounceCount * bounceDamage + penCount * penetrationDamage;
                target.损伤值 = totalDamage;

                // 颜色选择：取占比最高的命中分支作为整串颜色
                if (bounceCount >= penCount) {
                    result._dmgColorId = bullet.是否为敌人 ? 7 : 8; // 跳弹
                } else {
                    result._dmgColorId = bullet.是否为敌人 ? 9 : 10; // 过穿
                }

                // 近似缩放伤害数字大小
                var denom:Number = actualScatterUsed * rawDamage;
                if (denom > 0) {
                    result.damageSize *= (0.5 + 0.5 * (totalDamage / denom));
                }

                // 写入 DamageResult
                result.scatterModelEnabled = true;
                result.scatterNormalCount = 0;
                result.scatterBounceCount = bounceCount;
                result.scatterPenetrationCount = penCount;
                result.scatterMissCount = missCount + instantCount; // MISS 和直感合并显示
                result.scatterNormalDamage = 0;
                result.scatterBounceDamage = bounceDamage;
                result.scatterPenetrationDamage = penetrationDamage;
            }

        } else {
            // 旧行为：直接按段数放大本次伤害
            target.损伤值 *= actualScatterUsed;
        }
        // ==================== 分段躲闪建模结束 ====================
    }

    /**
     * 返回类的字符串表示。
     *
     * @return String 类的名称
     */
    public function toString():String {
        return "MultiShotDamageHandle";
    }
}
