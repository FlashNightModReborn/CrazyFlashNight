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
     * @param bullet 子弹对象
     * @return Boolean 如果子弹具有联弹属性则返回 true，否则返回 false
     */
    public function canHandle(bullet:Object):Boolean {
        // 使用位标志优化联弹检测性能
        #include "../macros/FLAG_CHAIN.as"
        return (bullet.flags & FLAG_CHAIN) != 0;
    }

    /**
     * 处理联弹伤害。
     * - 根据子弹的霰弹值、目标的血量和损伤值，计算实际消耗的霰弹值。
     * - 更新子弹的霰弹值和目标的损伤值，并将结果存储在 DamageResult 中。
     *
     * @param bullet  子弹对象
     * @param shooter 射击者对象
     * @param target  目标对象
     * @param manager 管理器对象
     * @param result  伤害结果对象
     */
    public function handleBulletDamage(bullet:Object, shooter:Object, target:Object, manager:Object, result:DamageResult):Void {
        var overlapRatio:Number = manager.overlapRatio;
        #include "../macros/FLAG_PIERCE.as"
        #include "../macros/FLAG_VERTICAL.as"

        // 2. 使用“按位或”(|)运算符，将多个标志合并成一个组合掩码
        //    这个掩码现在代表了“既是穿刺又是纵向”这个复合条件
        var PIERCE_AND_VERTICAL_MASK:Number = FLAG_PIERCE | FLAG_VERTICAL;

        // 原来的代码:
        // if(bullet.穿刺检测 && bullet.纵向检测)

        // 3. 替换为一次性的、原子的位运算检测
        //    将 bullet.flags 与我们的组合掩码进行“按位与”(&)
        //    如果结果正好等于组合掩码自身，说明 bullet.flags 中包含了掩码要求的所有位。
        if ((bullet.flags & PIERCE_AND_VERTICAL_MASK) == PIERCE_AND_VERTICAL_MASK) 
        {
            overlapRatio = overlapRatio * 7 / 18; // 对纵向穿刺联弹削弱覆盖率
            // _root.发布消息("联弹覆盖率削弱: " + overlapRatio);
        }
        // 计算 A = bullet.最小霰弹值 + overlapRatio * (bullet.霰弹值 - bullet.最小霰弹值 + 1) * 1.2
        var A:Number = bullet.最小霰弹值 + overlapRatio * (bullet.霰弹值 - bullet.最小霰弹值 + 1) * 1.2;

        // 计算 B = target.hp / (target.损伤值 > 0 ? target.损伤值 : 1)
        var thp:Number = target.hp;
        var B:Number = target.损伤值 > 0 ? thp / target.损伤值 : thp;

        // 计算 min(A, B)
        var C:Number = A < B ? A : B;

        // 计算 ceil(C)
        // 使用位运算实现向下取整
        var floorC:Number = C >> 0;
        var ceilC:Number;
        if (C > floorC) {
            ceilC = floorC + 1;
        } else {
            ceilC = floorC;
        }
        

        // 计算 min(bullet.霰弹值, ceilC)
        var actualScatterUsed:Number;
        if (bullet.霰弹值 < ceilC) {
            actualScatterUsed = bullet.霰弹值;
        } else {
            actualScatterUsed = ceilC;
        }

        // 设置 DamageResult
        result.actualScatterUsed = actualScatterUsed;

        // 更新 bullet 和 target
        // 重要：只有带"普通"前缀的子弹才会降低霰弹值
        // 原因：联弹霰弹值降到0后，剩余段数会全部miss（包括近战联弹）
        // 解决方案：给喷子用的会衰减的单元体都要带"普通"前缀
        // 历史问题：之前普通子弹、加强普通子弹都正常，但无壳子弹没有"普通"前缀导致问题
        // 现在"普通"也是词条了，所以需要显式检查普通检测


        // 1. 在编译时注入所有需要的局部常量，确保零运行时开销
        #include "../macros/FLAG_NORMAL.as"
        #include "../macros/FLAG_TRANSPARENCY.as"

        // 2. 创建一个“关注位掩码(Relevant Bits Mask)”，它包含了所有我们需要检查的位。
        //    我们关心“普通”和“透明”这两个位的状态。
        var RELEVANT_BITS_MASK:Number = FLAG_NORMAL | FLAG_TRANSPARENCY;

        // 3. 我们期望的最终结果是：“普通”位为 1，“透明”位为 0。
        //    这个期望的状态，其值恰好就是 FLAG_NORMAL 本身。
        var EXPECTED_STATE:Number = FLAG_NORMAL;

        // 原来的代码:
        // if(bullet.普通检测 && !bullet.透明检测)

        // 4. 将“提取”和“比较”合并为一次原子操作：
        //    (bullet.flags & RELEVANT_BITS_MASK) 会提取出子弹中“普通”和“透明”位的当前状态。
        //    然后将这个提取出的状态与我们期望的状态 (EXPECTED_STATE) 进行比较。
        if ((bullet.flags & RELEVANT_BITS_MASK) == EXPECTED_STATE) 
        {
            // 只有非透明的普通子弹才会进入这里
            bullet.霰弹值 -= actualScatterUsed;
        }

        result.finalScatterValue = bullet.霰弹值;

        // _root.发布消息("au:" + actualScatterUsed + ",fv:" + bullet.霰弹值 + ", dg:" + target.损伤值);

        // 乘以实际消耗霰弹值
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