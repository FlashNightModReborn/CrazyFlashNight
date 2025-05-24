/**
 * 硬直卡死检测组件
 * 
 * 专门负责检测角色是否因持续处于攻击硬直而进入卡死状态。
 * 监控目标的硬直状态和位置变化，在满足卡死条件时自动恢复。
 * 设计重点：
 * 1. 只通过stiffID是否存在判断任务丢失，不会错误检测时停等其他正常卡住敌人的手段
 * 2. 模块化设计，独立于其他监视逻辑
 * 3. 可配置的检测阈值
 * 
 * @version 1.0
 * @update 2025-05-18
 */
class org.flashNight.arki.unit.UnitComponent.Updater.WatchDogComponent.StiffDetector {
    
    /** 组件数据在watchDogData中的命名空间 */
    private static var NAMESPACE:String = "stiffDetector";
    
    /** 连续攻击硬直检测的阈值，达到此值判定为卡死 */
    private static var STIFF_THRESHOLD:Number = 5;
    
    /**
     * 初始化硬直卡死检测组件
     * @param target:MovieClip 需要监视的目标对象
     * @param watchDogData:Object 监视器数据容器
     */
    public static function init(target:MovieClip, watchDogData:Object):Void {
        // 创建组件专用数据命名空间
        var data:Object = watchDogData[NAMESPACE] = {};
        
        // 初始化检测数据
        data.stiffCount = 0;     // 连续"硬直中"检测次数
        data.lastStiffID = null; // 目标硬直任务ID
        // data.currentFrame = -1;  // 目标当前动画帧
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
        if (target.stiffID != null) {
            _handleStiffState(target, data);
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
    private static function _handleStiffState(target:MovieClip, data:Object):Void {
        // 增加硬直计数
        if(target.stiffID === data.lastStiffID){
            data.stiffCount++;
        }else{
            data.lastStiffID = target.stiffID;
            data.stiffCount = 0;
        }
        //  && data.state == target.状态 && target._currentframe == data.currentFrame
        
        // 已达到硬直阈值，开始检测位置变化
        if (data.stiffCount >= STIFF_THRESHOLD) {
            _recoverFromStiff(target, data);
        }
    }
    
    /**
     * 处理目标处于正常状态（非硬直）的情况
     * @param target:MovieClip 目标对象
     * @param data:Object 组件数据
     * @private
     */
    private static function _handleNormalState(target:MovieClip, data:Object):Void {
        // 重置计数器
        data.stiffCount = 0;
        data.lastStiffID = null;
    }


    
    /**
     * 从卡死状态恢复
     * @param target:MovieClip 目标对象
     * @param data:Object 组件数据
     * @private
     */
    private static function _recoverFromStiff(target:MovieClip, data:Object):Void {
        // 调用恢复处理方法
        onStiffDetected(target);
        
        // 重置计数器，防止重复触发
        data.stiffCount = 0;
        data.lastStiffID = null;
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
        data.stiffCount = 0;
        data.lastStiffID = null;
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
    public static function onStiffDetected(target:MovieClip):Void {
        // 发布消息通知系统
        //_root.发布消息("[WatchDog] 检测到对象攻击硬直卡死，已自动恢复: " + target + "[" + target.stiffID + "]");

        // printStiffTaskInfo(target.stiffID);

        // 解除硬直状态
        target.stiffID = null;
        target.man.play();
    }

    private static function printStiffTaskInfo(taskID):Void{
        var singleLevelTimeWheel = _root.帧计时器.ScheduleTimer.singleLevelTimeWheel;
        _root.服务器.发布服务器消息(singleLevelTimeWheel.printTimerInfoByID(taskID));
    }
    
    /**
     * 设置硬直检测阈值
     * @param threshold:Number 新的阈值值（默认为6）
     */
    public static function setStiffThreshold(threshold:Number):Void {
        STIFF_THRESHOLD = threshold;
    }

}