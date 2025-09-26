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
     * 性能优化（2025年9月更新）：
     * - 快慢双路径设计：正常运行时走快速路径，测试/特殊情况走防御路径
     * - 快速路径信任BulletQueueProcessor的初始化，省略防御性检查
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
        // ========== 位标志常量注入 ==========
        #include "../macros/FLAG_PIERCE.as"
        #include "../macros/FLAG_VERTICAL.as"
        #include "../macros/FLAG_NORMAL.as"
        #include "../macros/FLAG_TRANSPARENCY.as"

        var PIERCE_AND_VERTICAL_MASK:Number = FLAG_PIERCE | FLAG_VERTICAL;
        var RELEVANT_BITS_MASK:Number = FLAG_NORMAL | FLAG_TRANSPARENCY;
        var EXPECTED_STATE:Number = FLAG_NORMAL;

        // ========== 快速路径判定 ==========
        var isNormalNonTransparent:Boolean = (bullet.flags & RELEVANT_BITS_MASK) == EXPECTED_STATE;
        var hasDeferredSnapshot:Boolean = (bullet.__dfScatterBase != undefined);

        // ========== 快速路径：高频联弹场景（信任BulletQueueProcessor初始化） ==========
        if (hasDeferredSnapshot && isNormalNonTransparent) {
            // 快速路径：省略防御性检查，直接使用值
            var overlapRatio:Number = manager.overlapRatio;
            var scatterBase:Number = bullet.__dfScatterBase;
            var scatterShadow:Number = bullet.__dfScatterShadow;
            var scatterForCalc:Number = (scatterBase + scatterShadow) * 0.5;

            // 纵向穿刺削弱
            if ((bullet.flags & PIERCE_AND_VERTICAL_MASK) == PIERCE_AND_VERTICAL_MASK) {
                overlapRatio = overlapRatio * 7 / 18;
            }

            // 核心计算
            var A:Number = bullet.最小霰弹值 + overlapRatio * (scatterForCalc - bullet.最小霰弹值 + 1) * 1.2;
            var B:Number = target.损伤值 > 0 ? target.hp / target.损伤值 : target.hp;
            var C:Number = A < B ? A : B;
            var ceilC:Number = (C > (C >> 0)) ? (C >> 0) + 1 : (C >> 0);

            // 实际消耗（仅保留必要边界检查）
            var actualScatterUsed:Number = scatterShadow < ceilC ? scatterShadow : ceilC;
            if (actualScatterUsed < 0) actualScatterUsed = 0;

            // 更新影子记账
            var pendingScatter:Number = bullet.__dfScatterPending || 0;
            bullet.__dfScatterPending = pendingScatter + actualScatterUsed;

            var nextShadow:Number = scatterShadow - actualScatterUsed;
            if (nextShadow < 0) nextShadow = 0;
            bullet.__dfScatterShadow = nextShadow;

            // 设置结果
            result.actualScatterUsed = actualScatterUsed;
            result.finalScatterValue = nextShadow;
            target.损伤值 *= actualScatterUsed;
            return;
        }

        // ========== 慢速路径：防御性处理（测试/特殊情况/非标准流程） ==========
        var overlapRatio:Number = manager.overlapRatio;

        // 获取当前霰弹值（带防御检查）
        var currentScatter:Number = (bullet.霰弹值 != undefined) ? Number(bullet.霰弹值) : 0;
        if (isNaN(currentScatter)) {
            currentScatter = 0;
        }

        // 初始化基准值和影子值（带防御检查）
        var scatterBase:Number = hasDeferredSnapshot ? Number(bullet.__dfScatterBase) : currentScatter;
        if (isNaN(scatterBase)) {
            scatterBase = currentScatter;
        }

        var scatterShadow:Number = hasDeferredSnapshot ?
            ((bullet.__dfScatterShadow != undefined) ? Number(bullet.__dfScatterShadow) : scatterBase) :
            currentScatter;
        if (isNaN(scatterShadow)) {
            scatterShadow = scatterBase;
        }

        // 计算模式判定
        var useDeferred:Boolean = hasDeferredSnapshot && isNormalNonTransparent;
        var scatterForCalc:Number = useDeferred ? ((scatterBase + scatterShadow) * 0.5) : currentScatter;
        if (isNaN(scatterForCalc)) {
            scatterForCalc = currentScatter;
        }

        // 纵向穿刺削弱
        if ((bullet.flags & PIERCE_AND_VERTICAL_MASK) == PIERCE_AND_VERTICAL_MASK) {
            overlapRatio = overlapRatio * 7 / 18;
        }

        // 核心伤害计算
        var A:Number = bullet.最小霰弹值 + overlapRatio * (scatterForCalc - bullet.最小霰弹值 + 1) * 1.2;
        var thp:Number = target.hp;
        var B:Number = target.损伤值 > 0 ? thp / target.损伤值 : thp;
        var C:Number = A < B ? A : B;
        var floorC:Number = C >> 0;
        var ceilC:Number = (C > floorC) ? floorC + 1 : floorC;

        // 实际消耗计算（带防御检查）
        var availableScatter:Number = useDeferred ? scatterShadow : currentScatter;
        if (isNaN(availableScatter) || availableScatter < 0) {
            availableScatter = 0;
        }

        var actualScatterUsed:Number = availableScatter < ceilC ? availableScatter : ceilC;
        if (isNaN(actualScatterUsed) || actualScatterUsed < 0) {
            actualScatterUsed = 0;
        }

        result.actualScatterUsed = actualScatterUsed;

        // 更新霰弹值
        var finalScatter:Number = useDeferred ? scatterShadow : currentScatter;

        if (useDeferred) {
            // 影子记账模式
            var pendingScatter:Number = (bullet.__dfScatterPending != undefined) ? Number(bullet.__dfScatterPending) : 0;
            if (isNaN(pendingScatter)) {
                pendingScatter = 0;
            }
            pendingScatter += actualScatterUsed;
            bullet.__dfScatterPending = pendingScatter;

            var nextShadow:Number = scatterShadow - actualScatterUsed;
            if (isNaN(nextShadow) || nextShadow < 0) {
                nextShadow = 0;
            }
            bullet.__dfScatterShadow = nextShadow;
            finalScatter = nextShadow;
        } else if (isNormalNonTransparent) {
            // 普通模式
            currentScatter -= actualScatterUsed;
            if (currentScatter < 0) {
                currentScatter = 0;
            }
            bullet.霰弹值 = currentScatter;
            finalScatter = currentScatter;
        }

        result.finalScatterValue = finalScatter;
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