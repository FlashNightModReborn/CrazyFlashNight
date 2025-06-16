// org/flashNight/arki/component/Buff/BaseBuff.as
import org.flashNight.arki.component.Buff.*;

/**
 * 所有Buff实现的抽象基类。
 * 实现了IBuff接口，并处理了所有Buff共有的ID管理功能。
 * 子类需要继承它，并实现自己的核心逻辑。
 */
class org.flashNight.arki.component.Buff.BaseBuff implements IBuff {
    
    private static var nextID:Number = 0;
    private var _type:String = "BaseBuff";
    public var _id:String;

    /**
     * BaseBuff构造函数，负责初始化所有Buff共有的属性。
     */
    public function BaseBuff() {
        this._id = String(nextID++);
    }

    /**
     * IBuff接口实现：获取Buff唯一标识。
     * 这是所有子类共享的功能。
     */
    public function getId():String {
        return this._id;
    }

    // --- 以下是需要或建议子类重写的方法 ---

    /**
     * IBuff接口实现：应用效果。
     * 基类提供一个空实现，具体逻辑必须由子类提供。
     */
    public function applyEffect(calculator:IBuffCalculator, context:BuffContext):Void {
        // 子类必须重写此方法
    }

    /**
     * IBuff接口实现：获取类型。
     */
    public function getType():String {
        return _type;
    }

    /**
     * IBuff接口实现：检查激活状态。
     * 默认实现为true。如果Buff有复杂的激活条件，子类应重写。
     * 对于生命周期由容器管理的模型，这个默认实现是合适的。
     */
    public function isActive():Boolean {
        return true;
    }

    /**
     * IBuff接口实现：销毁。
     * 基类提供一个空实现，如果子类需要清理资源（如数据容器），则应重写。
     */
    public function destroy():Void {
        // 子类可重写此方法以释放资源
    }
}