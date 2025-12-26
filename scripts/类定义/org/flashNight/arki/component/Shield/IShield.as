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
 * 3. 其他伤害：absorbed = min(damage, strength, capacity)
 * 4. 穿透伤害 = damage - absorbed
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
     * - 其他情况：吸收 min(damage, strength, capacity)，返回剩余
     * - 命中后触发 onHit 事件
     *
     * @param damage 输入伤害值
     * @param bypassShield 是否绕过护盾(如真伤)，默认false
     * @return Number 穿透护盾后剩余的伤害值
     */
    function absorbDamage(damage:Number, bypassShield:Boolean):Number;

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

    // ==================== 生命周期管理 ====================

    /**
     * 帧更新方法。
     * 处理护盾的填充、衰减、延迟计时等逻辑。
     * @param deltaTime 帧间隔(通常为1)
     */
    function update(deltaTime:Number):Void;

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
