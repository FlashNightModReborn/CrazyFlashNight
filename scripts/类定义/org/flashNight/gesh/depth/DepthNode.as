import org.flashNight.naki.DataStructures.*;
import org.flashNight.aven.Coordinator.EventCoordinator;

/**
 * @class DepthNode
 * @description 深度管理器中用于表示影片剪辑及其深度信息的节点类
 * @package org.flashNight.gesh.depth
 */
class org.flashNight.gesh.depth.DepthNode {
    /** 关联的影片剪辑 */
    public var mc:MovieClip;
    
    /** 当前深度值 */
    public var depth:Number;
    
    /** 时间戳（用于相同深度值时确定优先级） */
    public var timestamp:Number;
    
    /** 是否已更新到实际深度 */
    public var isDirty:Boolean;
    
    /**
     * 构造函数
     * @param mc 影片剪辑实例
     * @param depth 初始深度值
     */
    public function DepthNode(mc:MovieClip, depth:Number) {
        this.mc = mc;
        this.depth = depth;
        this.timestamp = getTimer();
        this.isDirty = true; // 新节点默认需要更新
    }
    
    /**
     * 更新节点深度值
     * @param newDepth 新的深度值
     * @return 深度是否发生变化
     */
    public function updateDepth(newDepth:Number):Boolean {
        if (this.depth != newDepth) {
            this.depth = newDepth;
            this.timestamp = getTimer(); // 更新时间戳
            this.isDirty = true;
            return true;
        }
        return false;
    }
    
    /**
     * 设置时间戳（用于解决深度冲突）
     * @param timestamp 时间戳值
     */
    public function setTimestamp(timestamp:Number):Void {
        this.timestamp = timestamp;
    }
    
    /**
     * 重置脏标记（表示已完成实际深度更新）
     */
    public function resetDirty():Void {
        this.isDirty = false;
    }
    
    /**
     * 检查节点是否需要更新实际深度
     */
    public function needsUpdate():Boolean {
        return this.isDirty;
    }
}