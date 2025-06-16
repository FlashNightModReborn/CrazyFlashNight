// org/flashNight/arki/component/Buff/BuffContext.as

/**
 * Buff效果计算时的上下文信息。
 * 这是一个在单次属性计算过程中传递的数据容器，
 * 负责提供计算所需的环境信息，例如计算目标、事件来源等。
 * 它本身是无状态的，其生命周期仅限于一次计算。
 */
class org.flashNight.arki.component.Buff.BuffContext {

    /**
     * 当前正在计算的属性名称 (例如: "attack", "health", "moveSpeed")。
     * 这是Buff判断是否需要对当前计算产生影响的核心依据。
     */
    public var propertyName:String;

    /**
     * 属性计算的归属者 (例如: 某个角色、怪物实例)。
     * Buff可以从target上获取其他属性，用于复杂的逻辑判断。
     * 例如："如果目标血量低于50%，则攻击力增加20%"。
     */
    public var target:Object;

    /**
     * 触发本次计算的来源对象 (可选)。
     * 这在处理与来源相关的效果时非常有用。
     * 例如: 
     * - 在计算伤害时，source是攻击者。
     * - 在一个光环Buff中，source是光环的提供者。
     */
    public var source:Object;

    /**
     * 一个开放的、临时的共享数据容器。
     * 用于在单次计算中，传递一些不适合放在固定字段里的临时数据。
     * 例如，一次技能攻击可能附带了特殊的标签 "fire", "critical"。
     * 一个Buff可以检查 context.sharedData.isCritical 是否为 true。
     * 注意：这个容器里的数据在每次计算开始时都应该是全新的。
     */
    public var sharedData:Object;


    /**
     * BuffContext 构造函数
     * @param propertyName 正在计算的属性名。
     * @param target 属性的归属者。
     * @param source (可选) 触发计算的来源。
     * @param sharedData (可选) 临时的共享数据。
     */
    public function BuffContext(
        propertyName:String, 
        target:Object, 
        source:Object,
        sharedData:Object
    ) {
        this.propertyName = propertyName;
        this.target = target;
        this.source = source;
        this.sharedData = sharedData || {}; // 如果不提供，则初始化为空对象，防止null引用
    }
}