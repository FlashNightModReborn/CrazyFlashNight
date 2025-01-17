import org.flashNight.arki.component.Damage.*;

/**
 * DamageManager 类是伤害管理的核心类。
 * - 负责管理和执行伤害处理器。
 * - 只包含必要的处理器，由 DamageManagerFactory 注入。
 * - 专注于执行伤害处理逻辑，避免冗余存储。
 */
class org.flashNight.arki.component.Damage.DamageManager {

    // 适用的伤害处理器列表，由工厂注入
    private var _handles:Array;

    // 处理器数量
    private var _handleCount:Number;

    // 多段 / 霰弹计算的重叠比例
    public var overlapRatio:Number;

    // 目标的躲闪状态
    public var dodgeState:String;

    /**
     * 构造函数。
     * 初始化 DamageManager 实例。
     *
     * @param handles 适用的伤害处理器列表（已由工厂筛选）
     */
    public function DamageManager(handles:Array) {
        this._handles = handles;          // 直接接受工厂筛选好的处理器
        this._handleCount = handles.length; // 记录处理器数量
        this.overlapRatio = 1;            // 默认重叠比例为 1
        this.dodgeState = "";             // 默认躲闪状态为空
    }

    /**
     * 执行所有伤害处理器。
     * 遍历处理器列表，依次调用每个处理器的 handleBulletDamage 方法。
     *
     * @param bullet  子弹对象
     * @param shooter 发射者对象
     * @param target  被击中目标对象
     * @param result  伤害结果对象
     */
    public function execute(bullet:Object, shooter:Object, target:Object, result:DamageResult):Void {
        var index:Number = 0;

        // 遍历所有处理器
        do {
            _handles[index].handleBulletDamage(bullet, shooter, target, this, result);
        } while (++index < _handleCount);  // 自增操作移入条件判断
    }

    /**
     * 输出 DamageManager 的状态信息。
     * 返回包含所有处理器名称的字符串，用于调试和日志记录。
     *
     * @return String DamageManager 的状态信息
     */
    public function toString():String {
        var str:String = "DamageManager:\n";

        // 遍历所有处理器，将其名称添加到字符串中
        for (var i:Number = 0; i < _handleCount; ++i) {
            str += "  Handle: " + _handles[i].toString() + "\n";
        }

        return str;
    }
}