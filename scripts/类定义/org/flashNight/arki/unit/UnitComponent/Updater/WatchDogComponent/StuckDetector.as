import org.flashNight.neur.Event.EventDispatcher;

/**
 * 硬直卡死检测组件
 * 
 * 专门负责检测角色是否因持续处于受击硬直状态且位置不变而进入卡死状态。
 * 监控目标的硬直状态和位置变化，在满足卡死条件时自动恢复。
 * 设计重点：
 * 1. 仅在必要时访问坐标属性，减少getter调用
 * 2. 模块化设计，独立于其他监视逻辑
 * 3. 可配置的检测阈值
 * 
 * @version 1.0
 * @update 2025-05-16
 */
class org.flashNight.arki.unit.UnitComponent.Updater.WatchDogComponent.StuckDetector {
    
    /** 组件数据在watchDogData中的命名空间 */
    private static var NAMESPACE:String = "stuckDetector";
    
    /** 连续受击硬直检测的阈值，达到此值开始进行位置监控 */
    private static var STUN_THRESHOLD:Number = 6;
    
    /** 连续位置不变的阈值，达到此值判定为卡死 */
    private static var STUCK_THRESHOLD:Number = 6;
    
    /**
     * 初始化硬直卡死检测组件
     * @param target:MovieClip 需要监视的目标对象
     * @param watchDogData:Object 监视器数据容器
     */
    public static function init(target:MovieClip, watchDogData:Object):Void {
        // 创建组件专用数据命名空间
        var data:Object = watchDogData[NAMESPACE] = {};
        
        // 初始化检测数据
        data.stunCount = 0;      // 连续"硬直中"检测次数
        data.stuckCount = 0;     // 连续坐标不变的检测次数
        data.lastXSet = false;   // 是否已设置上次坐标
        data.enabled = true;     // 组件启用状态
    }
    
    /**
     * 更新硬直卡死检测状态
     * @param target:MovieClip 需要监视的目标对象
     * @param watchDogData:Object 监视器数据容器
     */
    public static function update(target:MovieClip, watchDogData:Object):Void {
        // 获取组件数据
        var data:Object = watchDogData[NAMESPACE];
        if (data == null || !data.enabled) return;
        
        // 执行硬直卡死检测
        if (target.硬直中 || target.浮空 || target.knockStiffID != null) {
            _handleStunState(target, data);
        } else {
            _handleNormalState(target, data);
        }
    }
    
    /**
     * 处理目标处于硬直状态的情况
     * @param target:MovieClip 目标对象
     * @param data:Object 组件数据
     * @private
     */
    private static function _handleStunState(target:MovieClip, data:Object):Void {
        // 增加硬直计数
        data.stunCount++;
        
        // 达到硬直阈值时，开始记录位置
        if (data.stunCount === STUN_THRESHOLD) {
            _recordPosition(target, data);
        }
        
        // 已达到监控阈值，开始检测位置变化
        if (data.stunCount >= STUN_THRESHOLD) {
            _checkPositionChange(target, data);
        }
    }
    
    /**
     * 处理目标处于正常状态（非硬直）的情况
     * @param target:MovieClip 目标对象
     * @param data:Object 组件数据
     * @private
     */
    private static function _handleNormalState(target:MovieClip, data:Object):Void {
        // 若之前记录过位置，则更新最后位置
        if (data.lastXSet) {
            data.lastX = target._x;
            data.lastY = target._y;
        }
        
        // 重置计数器
        data.stunCount = 0;
        data.stuckCount = 0;
    }
    
    /**
     * 记录目标当前位置
     * @param target:MovieClip 目标对象
     * @param data:Object 组件数据
     * @private
     */
    private static function _recordPosition(target:MovieClip, data:Object):Void {
        data.lastX = target._x;
        data.lastY = target._y;
        data.lastXSet = true;
    }
    
    /**
     * 检测目标位置变化并处理可能的卡死状态
     * @param target:MovieClip 目标对象
     * @param data:Object 组件数据
     * @private
     */
    private static function _checkPositionChange(target:MovieClip, data:Object):Void {
        // 获取当前位置（仅在此处访问一次坐标属性）
        var curX:Number = target._x;
        var curY:Number = target._y;
        
        // 检测位置是否变化
        if (curX == data.lastX && curY == data.lastY) {
            // 位置未变化，增加卡住计数
            data.stuckCount++;
            
            // 达到卡死阈值，触发恢复
            if (data.stuckCount >= STUCK_THRESHOLD) {
                _recoverFromStuck(target, data);
            }
        } else {
            // 位置已变化，重置卡住计数
            data.stuckCount = 0;
        }
        
        // 更新位置记录
        data.lastX = curX;
        data.lastY = curY;
    }
    
    /**
     * 从卡死状态恢复
     * @param target:MovieClip 目标对象
     * @param data:Object 组件数据
     * @private
     */
    private static function _recoverFromStuck(target:MovieClip, data:Object):Void {
        // 添加日志插桩
        // _root.服务器.发布服务器消息("[StuckDetector] 触发受击硬直卡死检测 - 目标: " + target + ", HP: " + target.hp + ", 状态: " + target.状态 + ", 硬直中: " + target.硬直中 + ", 浮空: " + target.浮空);
        
        // 调用恢复处理方法
        onStuckDetected(target);
        
        // 重置计数器，防止重复触发
        data.stunCount = 0;
        data.stuckCount = 0;
    }
    
    /**
     * 重置组件状态
     * 在角色状态发生重大变化时调用（如：复活、传送等）
     * @param target:MovieClip 目标对象
     * @param watchDogData:Object 监视器数据容器
     */
    public static function reset(target:MovieClip, watchDogData:Object):Void {
        var data:Object = watchDogData[NAMESPACE];
        if (data == null) return;
        
        // 重置所有计数和状态
        data.stunCount = 0;
        data.stuckCount = 0;
        data.lastXSet = false;
    }
    
    /**
     * 启用/禁用组件
     * @param target:MovieClip 目标对象
     * @param watchDogData:Object 监视器数据容器
     * @param enabled:Boolean 是否启用
     */
    public static function setEnabled(target:MovieClip, watchDogData:Object, enabled:Boolean):Void {
        var data:Object = watchDogData[NAMESPACE];
        if (data == null) return;
        
        data.enabled = enabled;
        
        // 禁用时重置状态
        if (!enabled) {
            reset(target, watchDogData);
        }
    }
    
    /**
     * 卡死状态检测回调方法（可在外部重写）
     * 默认行为：解除目标硬直状态并发布消息
     * @param target:MovieClip 卡死的目标对象
     */
    public static function onStuckDetected(target:MovieClip):Void {
        // 添加日志插桩 - 恢复操作
        // _root.服务器.发布服务器消息("[StuckDetector] 执行恢复操作 - 目标: " + target + ", knockStiffID: " + target.knockStiffID + ", flyID: " + target.flyID);
        
        // if(target.硬直中) printStuckTaskInfo(target.knockStiffID);
        // else if(target.浮空) printStuckTaskInfo(target.flyID);

        // 解除硬直状态
        target.硬直中 = false;
        target.浮空 = false;
        target.knockStiffID = null;

        if(target.hp > 0) {
            target.状态改变("空手站立");
        } else {
            var dispatcher:EventDispatcher = target.dispatcher;
            // _root.服务器.发布服务器消息("[StuckDetector] 发布击杀事件 - 目标: " + target);
            dispatcher.publish("kill", target);
        }
        
    }

    private static function printStuckTaskInfo(taskID):Void{
        var singleLevelTimeWheel = _root.帧计时器.ScheduleTimer.singleLevelTimeWheel;
        _root.服务器.发布服务器消息(singleLevelTimeWheel.printTimerInfoByID(taskID));
    }
    
    /**
     * 设置硬直检测阈值
     * @param threshold:Number 新的阈值值（默认为6）
     */
    public static function setStunThreshold(threshold:Number):Void {
        STUN_THRESHOLD = threshold;
    }
    
    /**
     * 设置卡死检测阈值
     * @param threshold:Number 新的阈值值（默认为6）
     */
    public static function setStuckThreshold(threshold:Number):Void {
        STUCK_THRESHOLD = threshold;
    }
}