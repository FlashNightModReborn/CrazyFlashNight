// File: org/flashNight/arki/component/Shield/ShieldIdAllocator.as

/**
 * ShieldIdAllocator - 护盾系统统一 ID 分配器
 *
 * 【设计目的】
 * 为所有护盾类型（BaseShield、AdaptiveShield、ShieldSnapshot 等）提供全局唯一 ID。
 * 避免各类各自维护 _idCounter 导致的 ID 冲突问题。
 *
 * 【ID 语义】
 * - 每个护盾实例在创建时获得一个唯一 ID
 * - ID 用于：精确查询、移除、日志追踪、回调识别
 * - ID 在整个运行时保持唯一（不考虑 Number 溢出，约 9e15 次分配）
 *
 * 【使用方式】
 * var id:Number = ShieldIdAllocator.nextId();
 */
class org.flashNight.arki.component.Shield.ShieldIdAllocator {

    /** 全局 ID 计数器 */
    private static var _counter:Number = 0;

    /**
     * 分配下一个唯一 ID。
     *
     * @return Number 全局唯一的护盾 ID
     */
    public static function nextId():Number {
        return ++_counter;
    }

    /**
     * 获取当前已分配的最大 ID（用于调试）。
     *
     * @return Number 当前计数器值
     */
    public static function getCurrentCounter():Number {
        return _counter;
    }

    /**
     * 重置计数器（仅用于测试）。
     *
     * 【警告】
     * 生产环境禁止调用，会导致 ID 冲突。
     */
    public static function resetForTesting():Void {
        _counter = 0;
    }
}
