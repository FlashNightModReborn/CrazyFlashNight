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
     */
    public static function register(unit:MovieClip):Void {
        if (unit._btEnabled != true) {
            unit._btEnabled = true;
            _listenerCount++;
        }
    }

    /**
     * unregister — AI 单位禁用射弹预警
     * 由 ActionArbiter.destroy() 调用
     */
    public static function unregister(unit:MovieClip):Void {
        if (unit._btEnabled == true) {
            unit._btEnabled = false;
            _listenerCount--;
        }
    }

    /**
     * reset — 场景切换时重置
     */
    public static function reset():Void {
        _listenerCount = 0;
    }
}
