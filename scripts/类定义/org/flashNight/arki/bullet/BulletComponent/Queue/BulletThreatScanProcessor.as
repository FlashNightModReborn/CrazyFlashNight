/**
 * BulletThreatScanProcessor — 射弹预警门控
 *
 * 管理全局预警启用标志和单位级 _btEnabled 属性。
 * 实际预警扫描由 BulletQueueProcessor.processQueue() 的 Phase 2+ 尾循环完成。
 *
 * 零成本原则：当 _listenerCount == 0 时，尾循环整段不执行。
 */
class org.flashNight.arki.bullet.BulletComponent.Queue.BulletThreatScanProcessor {

    private static var _listenerCount:Number = 0;
    private static var _epoch:Number = 0;

    /**
     * hasListeners — 全局门控（O(1) 布尔检查）
     * BulletQueueProcessor 在 per-bullet 循环入口调用
     */
    public static function hasListeners():Boolean {
        return _listenerCount > 0;
    }

    /**
     * register — AI 单位启用射弹预警
     * 由 ActionArbiter 构造时调用
     *
     * epoch 机制：reset() 后新 epoch 覆盖旧标记，
     * 即使旧 _btEnabled=true 也会重新注册到当前 epoch。
     */
    public static function register(unit:MovieClip):Void {
        if (unit._btEnabled != true || unit._btEpoch != _epoch) {
            unit._btEnabled = true;
            unit._btEpoch = _epoch;
            _listenerCount++;
        }
    }

    /**
     * unregister — AI 单位禁用射弹预警
     * 由 ActionArbiter.destroy() 调用
     *
     * 仅当前 epoch 注册的单位才扣减计数，
     * 防止 reset() 后延迟 unregister 导致计数下溢。
     */
    public static function unregister(unit:MovieClip):Void {
        if (unit._btEnabled == true) {
            unit._btEnabled = false;
            if (unit._btEpoch == _epoch) {
                _listenerCount--;
            }
        }
    }

    /**
     * reset — 场景切换时重置
     *
     * 递增 epoch 使旧单位的 unregister 不再影响计数，
     * 解决 reset() 与延迟 destroy() 的竞态问题。
     */
    public static function reset():Void {
        _epoch++;
        _listenerCount = 0;
    }
}
