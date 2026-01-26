// org/flashNight/arki/component/Buff/BaseBuff.as
import org.flashNight.arki.component.Buff.*;

/**
 * 所有Buff实现的抽象基类。
 * 实现了IBuff接口，并处理了所有Buff共有的ID管理功能。
 * 子类需要继承它，并实现自己的核心逻辑。
 *
 * 版本历史:
 * v1.3 (2026-01) - 文档增强
 *   [DOC] applyEffect添加警告：直接实例化BaseBuff无效
 *
 * v1.2 (2026-01) - 文档补充
 *   [DOC] getId()添加警告：禁止用于BuffManager.removeBuff()
 *
 * v1.1 (2026-01) - Bugfix Review
 *   [P2-1] _id改为private，防止外部修改导致ID映射损坏
 */
class org.flashNight.arki.component.Buff.BaseBuff implements IBuff {

    private static var nextID:Number = 0;
    private var _type:String = "BaseBuff";
    // [P2-1 修复] 改为 private，防止外部修改导致ID映射损坏
    private var _id:String;

    // [Phase D] 基本激活状态控制
    private var _active:Boolean = true;

    /**
     * BaseBuff构造函数，负责初始化所有Buff共有的属性。
     */
    public function BaseBuff() {
        this._id = String(nextID++);
        this._active = true;
    }

    /**
     * IBuff接口实现：获取Buff内部唯一标识。
     * 这是所有子类共享的功能。
     *
     * 【重要警告】此ID是系统内部自增ID，仅用于内部追踪。
     * **禁止**将此ID传递给 BuffManager.removeBuff()！
     * 正确做法是保存 BuffManager.addBuff() 的返回值用于后续移除。
     *
     * @return String 内部自增ID（如 "42"）
     */
    public function getId():String {
        return this._id;
    }

    // --- 以下是需要或建议子类重写的方法 ---

    /**
     * IBuff接口实现：应用效果。
     * 基类提供一个空实现，具体逻辑必须由子类提供。
     *
     * 【警告】直接实例化BaseBuff并添加到BuffManager是无效的！
     * BaseBuff.applyEffect是空实现，不会产生任何数值效果。
     * 必须使用PodBuff（数值Buff）或MetaBuff（状态Buff）。
     *
     * @param calculator Buff计算器，用于添加数值修改
     * @param context Buff上下文，包含属性名、目标对象等信息
     */
    public function applyEffect(calculator:IBuffCalculator, context:BuffContext):Void {
        // 空实现 - 子类必须重写此方法以产生实际效果
    }

    /**
     * IBuff接口实现：获取类型。
     */
    public function getType():String {
        return _type;
    }

    /**
     * IBuff接口实现：检查激活状态。
     * [Phase D] 修改为返回_active字段，支持deactivate()停用。
     * 如果Buff有复杂的激活条件，子类应重写。
     */
    public function isActive():Boolean {
        return this._active;
    }

    /**
     * [Phase D] 停用Buff，使isActive()返回false。
     * BuffManager.update()会自动清理inactive的独立PodBuff。
     */
    public function deactivate():Void {
        this._active = false;
    }

    /**
     * IBuff接口实现：是否是简单数值类型。
     * 默认实现为true。数值计算交给podbuff实现。
     * 对于非PodBuff，数值计算通过传递PodBuff实现
     * 对于生命周期由容器管理的模型，这个默认实现是合适的。
     */
    public function isPod():Boolean {
        return true;
    }

    /**
     * IBuff接口实现：销毁。
     * 基类提供一个空实现，如果子类需要清理资源（如数据容器），则应重写。
     */
    public function destroy():Void {
        // 子类可重写此方法以释放资源
    }

    /**
     * 返回Buff的字符串表示形式，包含类型与ID信息。
     */
    public function toString():String {
        return "[Buff type: " + this._type + ", id: " + this._id + "]";
    }

}