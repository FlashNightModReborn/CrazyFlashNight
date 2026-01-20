/**
 * StateInfo.as - MetaBuff状态变化信息
 *
 * 设计目的：
 * - 提供编译期类型检查，避免字段拼写错误
 * - 作为静态单例复用，实现0GC
 * - 明确的字段定义，便于IDE自动补全
 *
 * 使用契约：
 * - MetaBuff.update() 返回此类的静态单例
 * - BuffManager 在同步调用栈内使用完毕，不跨帧持有引用
 * - 多个MetaBuff共享同一实例，调用方需在下一个update前完成读取
 *
 * 性能优化：
 * - 热路径直接访问 StateInfo.instance，零函数调用开销
 * - [v1.2] 静态初始化instance，确保实例始终存在
 *
 * 版本历史：
 * v1.2 (2026-01) - 初始化优化
 *   [FIX] 改用静态初始化，消除getInstance()首次调用的null检查
 *
 * @version 1.2 (2026-01)
 */
class org.flashNight.arki.component.Buff.StateInfo {

    /** MetaBuff是否仍然存活 */
    public var alive:Boolean;

    /** 状态是否发生变化（相比上一帧） */
    public var stateChanged:Boolean;

    /** 是否需要注入PodBuff（INACTIVE → ACTIVE） */
    public var needsInject:Boolean;

    /** 是否需要弹出PodBuff（ACTIVE → PENDING_DEACTIVATE） */
    public var needsEject:Boolean;

    // =====================================================
    // 静态单例 - 所有MetaBuff共享，实现0GC
    // =====================================================

    /**
     * 公开的静态单例实例
     * 热路径直接访问此变量，避免函数调用开销
     * [v1.2] 静态初始化，确保instance始终存在
     */
    public static var instance:StateInfo = new StateInfo();

    /**
     * 获取静态单例
     * [v1.2] 由于使用静态初始化，此方法直接返回instance
     * 保留此方法是为了兼容性，但热路径应直接访问 StateInfo.instance
     *
     * @return StateInfo 共享的单例实例
     */
    public static function getInstance():StateInfo {
        return instance;
    }

    /**
     * 构造函数
     * 初始化所有字段为默认值
     */
    public function StateInfo() {
        this.alive = false;
        this.stateChanged = false;
        this.needsInject = false;
        this.needsEject = false;
    }

    /**
     * 调试信息
     */
    public function toString():String {
        return "[StateInfo alive=" + this.alive +
               ", stateChanged=" + this.stateChanged +
               ", needsInject=" + this.needsInject +
               ", needsEject=" + this.needsEject + "]";
    }
}
