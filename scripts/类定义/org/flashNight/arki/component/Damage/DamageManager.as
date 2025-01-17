import org.flashNight.arki.component.Damage.*;

/**
 * 精简版 DamageManager
 * - 只包含必要的处理器，由 DamageManagerFactory 注入。
 * - 专注于执行伤害处理逻辑，避免冗余存储。
 */
class org.flashNight.arki.component.Damage.DamageManager {

    private var _handles:Array;       // 适用的处理器，由工厂注入
    private var _handleCount:Number;  // 处理器数量

    public var overlapRatio:Number;   // 多段 / 霰弹计算
    public var dodgeState:String;     // 躲闪状态

    /**
     * 构造函数
     * @param handles 适用的伤害处理器列表（已筛选）
     */
    public function DamageManager(handles:Array) {
        this._handles = handles;          // 直接接受工厂筛选好的处理器
        this._handleCount = handles.length;
        this.overlapRatio = 1;
        this.dodgeState = "";
    }

    /**
     * 执行所有处理器
     * @param bullet   子弹
     * @param shooter  发射者
     * @param target   被击中目标
     * @param result   DamageResult
     */
    public function execute(bullet:Object, shooter:Object, target:Object, result:DamageResult):Void {
        var index:Number = 0;
        while(index < _handleCount)
        {
            _handles[index++].handleBulletDamage(bullet, shooter, target, this, result);
        }
    }

    /**
     * 输出 DamageManager 状态信息
     */
    public function toString():String {
        var str:String = "DamageManager:\n";
        for (var i:Number = 0; i < _handleCount; ++i) {
            str += "  Handle: " + _handles[i].toString() + "\n";
        }
        return str;
    }
}
