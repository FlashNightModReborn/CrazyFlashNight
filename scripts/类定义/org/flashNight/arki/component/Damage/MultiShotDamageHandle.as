import org.flashNight.arki.component.Damage.*;

/**
 * MultiShotDamageHandle 类是用于处理联弹伤害的处理器。
 * - 当子弹具有联弹属性且不穿刺时，根据子弹的霰弹值、目标的血量和损伤值，计算实际消耗的霰弹值。
 * - 更新子弹的霰弹值和目标的损伤值，并将结果存储在 DamageResult 中。
 */
class org.flashNight.arki.component.Damage.MultiShotDamageHandle extends BaseDamageHandle implements IDamageHandle {

    // ========== 单例实例 ==========

    /** 单例实例 */
    public static var instance:MultiShotDamageHandle = new MultiShotDamageHandle();

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
        if (instance == null) {
            instance = new MultiShotDamageHandle();
            getInstance = function():MultiShotDamageHandle {
                return instance;
            };
        }
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
     * 处理联弹伤害。
     *
     * 核心逻辑：
     * - 根据子弹的霰弹值、目标的血量和损伤值，计算实际消耗的霰弹值
     * - 使用影子记账机制优化对群手感（2025年9月新增）
     * - 支持纵向穿刺联弹的覆盖率削弱
     * - 更新子弹的霰弹值和目标的损伤值，并将结果存储在 DamageResult 中
     *
     * 性能优化：
     * - 使用位运算替代布尔属性检测
     * - 使用位移运算实现向下取整
     * - 合并多个条件判断为原子操作
     *
     * @param bullet  子弹对象，包含霰弹值、最小霰弹值、flags等属性
     * @param shooter 射击者对象
     * @param target  目标对象，包含hp、损伤值等属性
     * @param manager 管理器对象，提供overlapRatio（覆盖率）
     * @param result  伤害结果对象，用于存储计算结果
     */
    public function handleBulletDamage(bullet:Object, shooter:Object, target:Object, manager:Object, result:DamageResult):Void {
        // ========== 初始化和位标志定义 ==========
        var overlapRatio:Number = manager.overlapRatio;  // 联弹覆盖率

        // 编译时注入位标志常量，确保零运行时开销
        #include "../macros/FLAG_PIERCE.as"        // 穿刺标志
        #include "../macros/FLAG_VERTICAL.as"      // 纵向标志
        #include "../macros/FLAG_NORMAL.as"        // 普通标志
        #include "../macros/FLAG_TRANSPARENCY.as"  // 透明标志

        // 组合掩码定义
        var PIERCE_AND_VERTICAL_MASK:Number = FLAG_PIERCE | FLAG_VERTICAL;  // 纵向穿刺组合
        var RELEVANT_BITS_MASK:Number = FLAG_NORMAL | FLAG_TRANSPARENCY;    // 普通/透明检测掩码
        var EXPECTED_STATE:Number = FLAG_NORMAL;                            // 期望状态：普通且非透明

        // ========== 霰弹值获取与影子记账初始化 ==========
        // 影子记账机制说明（2025年9月新增）：
        // 用于优化联弹对群体目标的手感，避免霰弹值过早耗尽导致后续目标无伤害
        // __dfScatterBase: 基准霰弹值快照，记录子弹初始状态
        // __dfScatterShadow: 影子霰弹值，用于实际计算和扣除
        // __dfScatterPending: 待处理的霰弹值消耗累计

        // 获取当前霰弹值，确保数值有效性
        var currentScatter:Number = (bullet.霰弹值 != undefined) ? Number(bullet.霰弹值) : 0;
        if (isNaN(currentScatter)) {
            currentScatter = 0;
        }

        // 检查是否已有影子记账快照
        var hasDeferredSnapshot:Boolean = (bullet.__dfScatterBase != undefined);

        // 初始化基准值（首次命中时记录）
        var scatterBase:Number = hasDeferredSnapshot ? Number(bullet.__dfScatterBase) : currentScatter;
        if (isNaN(scatterBase)) {
            scatterBase = currentScatter;
        }

        // 初始化影子值（用于实际扣除计算）
        var scatterShadow:Number = hasDeferredSnapshot ? ((bullet.__dfScatterShadow != undefined) ? Number(bullet.__dfScatterShadow) : scatterBase) : currentScatter;
        if (isNaN(scatterShadow)) {
            scatterShadow = scatterBase;
        }

        // ========== 霰弹值计算模式判定 ==========
        // 判断是否为普通非透明子弹（只有这类子弹会消耗霰弹值）
        // 位运算优化：一次原子操作同时检测"普通"和"透明"两个标志
        var isNormalNonTransparent:Boolean = (bullet.flags & RELEVANT_BITS_MASK) == EXPECTED_STATE;

        // 决定是否使用影子记账模式
        // 条件：已有快照 且 是普通非透明子弹
        var useDeferred:Boolean = hasDeferredSnapshot && isNormalNonTransparent;

        // 计算用霰弹值（影子模式下使用基准值和影子值的平均值）
        var scatterForCalc:Number = useDeferred ? ((scatterBase + scatterShadow) * 0.5) : currentScatter;
        if (isNaN(scatterForCalc)) {
            scatterForCalc = currentScatter;
        }

        // ========== 纵向穿刺联弹特殊处理 ==========
        // 对纵向穿刺联弹进行覆盖率削弱，避免伤害过高
        // 位运算优化：使用组合掩码一次性检测"穿刺"和"纵向"两个标志
        // 削弱系数：7/18（约0.39），大幅降低覆盖率
        if ((bullet.flags & PIERCE_AND_VERTICAL_MASK) == PIERCE_AND_VERTICAL_MASK)
        {
            overlapRatio = overlapRatio * 7 / 18;  // 纵向穿刺联弹覆盖率削弱
        }

        // ========== 核心伤害计算公式 ==========
        // A值：基于覆盖率的理论霰弹消耗
        // 公式：最小霰弹值 + 覆盖率 * (当前霰弹值 - 最小霰弹值 + 1) * 1.2
        // 1.2为伤害系数，提升联弹效果
        var A:Number = bullet.最小霰弹值 + overlapRatio * (scatterForCalc - bullet.最小霰弹值 + 1) * 1.2;

        // B值：目标可承受的霰弹数量
        // 公式：目标血量 / 单发损伤值
        var thp:Number = target.hp;
        var B:Number = target.损伤值 > 0 ? thp / target.损伤值 : thp;

        // C值：实际需要消耗的霰弹值（取A、B较小值）
        var C:Number = A < B ? A : B;

        // 向上取整（使用位运算优化）
        var floorC:Number = C >> 0;  // 位移运算实现向下取整
        var ceilC:Number;
        if (C > floorC) {
            ceilC = floorC + 1;
        } else {
            ceilC = floorC;
        }

        // ========== 实际霰弹消耗计算 ==========
        // 获取可用霰弹值（影子模式使用影子值，否则使用当前值）
        var availableScatter:Number = useDeferred ? scatterShadow : currentScatter;
        if (isNaN(availableScatter) || availableScatter < 0) {
            availableScatter = 0;  // 防护：确保非负
        }

        // 计算实际消耗值（不超过可用值和需求值）
        var actualScatterUsed:Number;
        if (availableScatter < ceilC) {
            actualScatterUsed = availableScatter;  // 可用值不足，消耗全部
        } else {
            actualScatterUsed = ceilC;  // 可用值充足，按需消耗
        }
        if (isNaN(actualScatterUsed) || actualScatterUsed < 0) {
            actualScatterUsed = 0;  // 防护：确保非负
        }

        // 记录实际消耗值到结果对象
        result.actualScatterUsed = actualScatterUsed;

        // ========== 霰弹值更新与影子记账处理 ==========
        var finalScatter:Number = useDeferred ? scatterShadow : currentScatter;

        if (useDeferred) {
            // ===== 影子记账模式 =====
            // 累计待处理的消耗值（延迟实际扣除）
            var pendingScatter:Number = (bullet.__dfScatterPending != undefined) ? Number(bullet.__dfScatterPending) : 0;
            if (isNaN(pendingScatter)) {
                pendingScatter = 0;
            }
            pendingScatter += actualScatterUsed;  // 累加本次消耗
            bullet.__dfScatterPending = pendingScatter;  // 更新待处理值

            // 更新影子值（立即扣除，用于后续计算）
            var nextShadow:Number = scatterShadow - actualScatterUsed;
            if (isNaN(nextShadow) || nextShadow < 0) {
                nextShadow = 0;  // 防护：确保非负
            }
            bullet.__dfScatterShadow = nextShadow;  // 保存新的影子值
            finalScatter = nextShadow;
        } else if (isNormalNonTransparent) {
            // ===== 普通模式（仅普通非透明子弹） =====
            // 直接扣除霰弹值
            currentScatter -= actualScatterUsed;
            if (currentScatter < 0) {
                currentScatter = 0;  // 防护：确保非负
            }
            bullet.霰弹值 = currentScatter;  // 更新子弹霰弹值
            finalScatter = currentScatter;
        }
        // 注意：透明子弹和非普通子弹不会消耗霰弹值

        // 记录最终霰弹值到结果对象
        result.finalScatterValue = finalScatter;

        // 调试输出（已注释）
        // _root.发布消息("au:" + actualScatterUsed + ",fv:" + bullet.霰弹值 + ", dg:" + target.损伤值);

        // ========== 目标损伤值计算 ==========
        // 将损伤值乘以实际消耗的霰弹值，实现联弹多段伤害
        target.损伤值 *= actualScatterUsed;
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