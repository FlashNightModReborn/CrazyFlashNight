import org.flashNight.arki.component.Shield.*;

/**
 * IShield 接口定义了护盾系统的核心契约。
 *
 * 【设计模式】
 * 采用组合模式(Composite Pattern)，使单个护盾(Shield)和护盾栈(ShieldStack)
 * 实现相同接口，外部调用者无需关心内部结构。
 *
 * 【核心机制】
 * - 护盾强度(Strength)：过滤子弹火力的阈值，超过强度的伤害直接穿透
 * - 护盾容量(Capacity)：可吸收的总伤害量
 * - 填充机制：护盾可随时间恢复，支持延迟填充
 *
 * 【伤害处理流程】
 * 1. 调用方通过 bypassShield 参数指示是否绕过护盾
 * 2. 护盾可通过 resistBypass 属性抵抗绕过(如抗真伤盾)
 * 3. 其他伤害：absorbed = min(damage, strength * hitCount, capacity)
 * 4. 穿透伤害 = damage - absorbed
 *
 * 【联弹支持】
 * hitCount 参数用于支持联弹(单发子弹模拟多段弹幕)：
 * - 联弹的总伤害 = 单段伤害 * 段数
 * - 护盾有效强度 = 基础强度 * 段数
 * - 玩家视角：护盾能挡住的"每段伤害"仍然是强度值
 * - 例：强度50的护盾，面对10段联弹，有效强度=500
 *
 * 【事件系统】
 * - onHit: 被命中时触发，正充能护盾重置延迟，负充能不受影响
 * - onBreak: 护盾容量归零时触发
 * - onRechargeStart: 延迟结束开始充能时触发
 * - onRechargeFull: 充能完毕时触发
 * - onExpire: 临时盾持续时间结束时触发
 *
 * 【时间单位】
 * 所有时间相关参数均以帧(frame)为单位
 */
interface org.flashNight.arki.component.Shield.IShield {

    // ==================== 核心伤害处理 ====================

    /**
     * 吸收伤害并返回穿透到下一层的伤害值。
     *
     * 【处理逻辑】
     * - bypassShield=true 且护盾不抵抗绕过：直接返回原伤害
     * - 计算有效强度：effectiveStrength = strength * hitCount
     * - 吸收量：absorbed = min(damage, effectiveStrength, capacity)
     * - 命中后触发 onHit 事件
     *
     * 【联弹说明】
     * hitCount 用于联弹(单发模拟多段)场景：
     * - 普通子弹：hitCount = 1（默认）
     * - 联弹：hitCount = 段数（如10段联弹传入10）
     * - 护盾强度按段数倍增，保持玩家心智模型一致
     *
     * @param damage 输入伤害值(联弹为总伤害)
     * @param bypassShield 是否绕过护盾(如真伤)，默认false
     * @param hitCount 命中段数(联弹段数)，默认1
     * @return Number 穿透护盾后剩余的伤害值
     */
    function absorbDamage(damage:Number, bypassShield:Boolean, hitCount:Number):Number;

    /**
     * 直接消耗护盾容量（供 ShieldStack 内部调用）。
     *
     * 【与 absorbDamage 的区别】
     * - absorbDamage: 完整的伤害处理流程（强度节流 + 容量消耗 + 事件）
     * - consumeCapacity: 仅消耗容量 + 触发事件（强度节流已在栈级别完成）
     *
     * 【行为】
     * 1. 扣除指定容量（不超过当前容量）
     * 2. 触发 onHit 事件
     * 3. 若容量归零，触发 onBreak 事件
     *
     * 【组合模式支持】
     * ShieldStack 实现此方法时，将容量消耗分发给内部护盾，
     * 支持嵌套护盾栈（如"护盾组"概念）。
     *
     * @param amount 要消耗的容量
     * @return Number 实际消耗的容量
     */
    function consumeCapacity(amount:Number):Number;

    // ==================== 属性访问器 ====================

    /**
     * 获取当前护盾容量。
     * @return Number 当前剩余容量
     */
    function getCapacity():Number;

    /**
     * 获取护盾最大容量。
     * @return Number 最大容量上限
     */
    function getMaxCapacity():Number;

    /**
     * 获取护盾目标容量。
     * 填充时恢复到此值而非最大值，支持部分回复效果。
     * @return Number 目标容量
     */
    function getTargetCapacity():Number;

    /**
     * 获取护盾强度。
     * 对于ShieldStack，返回当前最外层活跃护盾的强度。
     * @return Number 护盾强度值
     */
    function getStrength():Number;

    /**
     * 获取护盾填充速度。
     * 正数表示充能，负数表示衰减。
     * @return Number 每帧的填充量
     */
    function getRechargeRate():Number;

    /**
     * 获取填充延迟时间。
     * 受击后需等待此时间才开始填充(仅对正充能有效)。
     * @return Number 延迟帧数
     */
    function getRechargeDelay():Number;

    // ==================== 状态查询 ====================

    /**
     * 检查护盾是否已耗尽。
     * @return Boolean 容量为0时返回true
     */
    function isEmpty():Boolean;

    /**
     * 检查护盾是否处于激活状态。
     * 未激活的护盾将被护盾栈弹出。
     * @return Boolean 激活状态
     */
    function isActive():Boolean;

    /**
     * 获取抵抗绕过的护盾计数。
     *
     * 【组合模式支持】
     * - BaseShield: 返回 0 或 1（取决于 resistBypass 属性）
     * - ShieldStack: 返回所有子护盾的计数之和（递归统计）
     *
     * 用于判断护盾栈是否能抵抗绕过效果（如真伤）。
     * 任意一层有抵抗能力（计数 > 0）即可生效。
     *
     * @return Number 抵抗绕过的护盾数量
     */
    function getResistantCount():Number;

    // ==================== 生命周期管理 ====================

    /**
     * 帧更新方法。
     * 处理护盾的填充、衰减、延迟计时等逻辑。
     *
     * 【返回值语义】
     * 返回 true 表示护盾状态发生了变化（容量、激活状态等），
     * 调用方可据此决定是否需要更新缓存或触发其他逻辑。
     *
     * 【变化场景】
     * - 容量因充能/衰减而改变
     * - 护盾因耗尽/过期而失活
     * - 延迟计时器状态变化
     *
     * @param deltaTime 帧间隔(通常为1)
     * @return Boolean 是否发生了状态变化
     */
    function update(deltaTime:Number):Boolean;

    /**
     * 护盾被命中事件。
     *
     * 【触发时机】
     * 每次 absorbDamage 成功吸收伤害后触发。
     *
     * 【行为】
     * - 正充能护盾(rechargeRate > 0)：重置延迟计时器
     * - 负充能护盾(rechargeRate <= 0)：不受影响，继续衰减
     *
     * @param absorbed 本次吸收的伤害量
     */
    function onHit(absorbed:Number):Void;

    /**
     * 护盾击碎事件回调。
     * 当护盾容量降至0时触发。
     */
    function onBreak():Void;

    /**
     * 护盾开始填充事件回调。
     * 填充延迟结束、开始恢复时触发。
     */
    function onRechargeStart():Void;

    /**
     * 护盾填充完毕事件回调。
     * 容量恢复到目标值时触发。
     */
    function onRechargeFull():Void;

    // ==================== 排序支持 ====================

    /**
     * 获取护盾的排序优先级。
     * 用于ShieldStack内部排序，决定伤害吸收顺序。
     * 优先级高的护盾先承受伤害。
     *
     * 【默认排序规则】
     * 1. 强度高者优先
     * 2. 强度相同时，填充速度低者优先(临时盾优先消耗)
     *
     * @return Number 排序优先级值(越大越优先)
     */
    function getSortPriority():Number;
}
