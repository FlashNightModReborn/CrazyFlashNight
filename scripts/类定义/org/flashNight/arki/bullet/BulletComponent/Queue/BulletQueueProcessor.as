// ============================================================================
// 子弹队列处理器（轻量版）
// ----------------------------------------------------------------------------
// 功能：协调子弹的有序处理，在帧尾触发排序和执行
// ============================================================================

import org.flashNight.arki.bullet.BulletComponent.Queue.BulletQueue;

class org.flashNight.arki.bullet.BulletComponent.Queue.BulletQueueProcessor {
    
    private static var queue:BulletQueue = new BulletQueue();
    private static var enabled:Boolean = false;
    
    /**
     * 初始化处理器
     */
    public static function initialize():Void {
        enabled = true;
    }
    
    /**
     * 添加子弹到处理队列
     */
    public static function addBullet(bullet:MovieClip):Void {
        if (enabled) {
            queue.add(bullet);
        }
    }
    
    /**
     * 处理所有排队的子弹（帧尾调用）
     */
    public static function processBullets():Void {
        if (!enabled) return;
        
        // 移除已销毁的子弹
        queue.removeDestroyed();
        
        // 获取排序后的子弹并处理
        var sortedBullets:Array = queue.getSortedBullets();
        
        for (var i:Number = 0; i < sortedBullets.length; i++) {
            var bullet:MovieClip = sortedBullets[i];
            if (bullet && bullet._parent) {
                // 调用原有的生命周期处理
                _root.子弹生命周期.call(bullet);
            }
        }
        
        // 清空队列准备下一帧
        queue.clear();
    }
    
    /**
     * 启用有序处理
     */
    public static function enable():Void {
        enabled = true;
    }
    
    /**
     * 禁用有序处理
     */
    public static function disable():Void {
        enabled = false;
        queue.clear();
    }
    
    /**
     * 获取当前队列大小
     */
    public static function getQueueSize():Number {
        return queue.getCount();
    }
    
    /**
     * 检查是否启用
     */
    public static function isEnabled():Boolean {
        return enabled;
    }
}