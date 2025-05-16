/**
 * 单位组件监视器 - 卡死状态检测
 * 
 * 监视目标对象的硬直状态，如果连续多次处于硬直且位置不变，则判定为卡死状态并触发恢复操作。
 * 优化点：仅在必要时访问对象的坐标属性，减少getter调用次数。
 * 
 */
class org.flashNight.arki.unit.UnitComponent.Updater.WatchDogUpdater {
    
    /** 连续硬直检测的阈值，达到此值开始进行位置监控 */
    private static var STUN_THRESHOLD:Number = 6;
    
    /** 连续位置不变的阈值，达到此值判定为卡死 */
    private static var STUCK_THRESHOLD:Number = 6;
    
    /**
     * 初始化目标的监视数据
     * @param target:MovieClip 需要监视的目标对象
     */
    public static function init(target:MovieClip):Void {
        var data:Object = target.watchDogData = {};
        data.stunCount  = 0;     // 连续"硬直中"检测次数
        data.stuckCount = 0;     // 连续坐标不变的检测次数
        data.lastXSet = false;   // 是否已设置上次坐标
    }
    
    /**
     * 更新监视状态，每帧调用
     * @param target:MovieClip 需要监视的目标对象
     */
    public static function update(target:MovieClip):Void {
        var data:Object = target.watchDogData;
        
        if (target.硬直中) {
            data.stunCount++;
            
            // 第三次"硬直"时，第一次记录基线坐标
            if (data.stunCount === STUN_THRESHOLD) {
                data.lastX = target._x;
                data.lastY = target._y;
                data.lastXSet = true;
            }
            
            // 只有当连续硬直次数达到阈值后才开始检查坐标变化
            if (data.stunCount >= STUN_THRESHOLD) {
                // 仅在真正需要比较时读取一次 _x/_y，减少getter访问
                var curX:Number = target._x;
                var curY:Number = target._y;
                
                if (curX == data.lastX && curY == data.lastY) {
                    data.stuckCount++;
                    
                    // 达到卡死阈值时触发恢复
                    if (data.stuckCount >= STUCK_THRESHOLD) {
                        // 进入卡死状态处理
                        _handleStuckState(target, data);
                    }
                } else {
                    // 位置发生变化，重置卡住计数
                    data.stuckCount = 0;
                }
                
                // 更新基线坐标供下次比较
                data.lastX = curX;
                data.lastY = curY;
            }
        } else {
            // 退出"硬直"时，若之前记录过坐标，则更新一次
            if (data.lastXSet) {
                data.lastX = target._x;
                data.lastY = target._y;
            }
            // 重置计数器
            _resetCounters(data);
        }
    }
    
    /**
     * 处理卡死状态
     * @param target:MovieClip 卡死的目标对象
     * @param data:Object 目标的监视数据
     * @private
     */
    private static function _handleStuckState(target:MovieClip, data:Object):Void {
        // 调用全局卡死处理方法
        onWatchDogStuck(target);
        
        // 重置计数，避免重复触发
        _resetCounters(data);
    }
    
    /**
     * 重置监视计数器
     * @param data:Object 目标的监视数据
     * @private
     */
    private static function _resetCounters(data:Object):Void {
        data.stunCount  = 0;
        data.stuckCount = 0;
    }
    
    /**
     * 全局卡死状态处理方法（可在外部重写）
     * 默认行为：解除目标硬直状态并发布消息
     * @param target:MovieClip 卡死的目标对象
     */
    public static function onWatchDogStuck(target:MovieClip):Void {
        // 解除硬直状态
        target.硬直中 = false;
        _root.发布消息("[WatchDog] 检测到对象卡死，已自动恢复: " + target);
    }
}