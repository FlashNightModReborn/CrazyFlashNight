import org.flashNight.neur.Event.EventDispatcher;

/**
 * 零血不死检测组件
 * 
 * 专门检测单位HP为0但未正常死亡的异常情况。
 * 当检测到单位血量为0但持续存活超过设定阈值时，
 * 将触发强制死亡机制，防止"幽灵单位"影响游戏平衡。
 * 
 * 设计重点：
 * 1. 低频检测HP值，减少性能开销
 * 2. 可配置的检测阈值和响应机制
 * 3. 支持不同类型单位的特殊情况处理
 * 4. 区分处理带复活标签和不带复活标签的单位
 * 
 * @version 1.1
 * @update 2025-05-16
 */
class org.flashNight.arki.unit.UnitComponent.Updater.WatchDogComponent.ZeroHPDetector {
    
    /** 组件数据在watchDogData中的命名空间 */
    private static var NAMESPACE:String = "zeroHPDetector";
    
    /** 零血状态持续的阈值，超过此值触发处理 */
    private static var ZERO_HP_THRESHOLD:Number = 50;
    
    /**
     * 初始化零血不死检测组件
     * @param target:MovieClip 需要监视的目标对象
     * @param watchDogData:Object 监视器数据容器
     */
    public static function init(target:MovieClip, watchDogData:Object):Void {
        // 创建组件专用数据命名空间
        var data:Object = watchDogData[NAMESPACE] = {};
        
        // 初始化检测数据
        data.zeroHPCounter = 0;        // 处于零血状态的持续次数
        data.lastHP = -1;              // 上次检测到的HP值
        data.enabled = true;           // 组件启用状态
        data.waitingForRespawn = false; // 是否正在等待复活
    }
    
    /**
     * 更新零血不死检测状态
     * @param target:MovieClip 需要监视的目标对象
     * @param watchDogData:Object 监视器数据容器
     */
    public static function update(target:MovieClip, watchDogData:Object):Void {
        // 获取组件数据
        var data:Object = watchDogData[NAMESPACE];
        if (data == null || !data.enabled) return;

        // _root.发布消息("update");
        
        // 如果正在等待复活，则处理复活等待逻辑
        if (data.waitingForRespawn) {
            _handleRespawnWaiting(target, data);
            return;
        }
        
        // 执行零血检测
        _checkZeroHPState(target, data);
    }
    
    /**
     * 检测单位是否处于零血但未死亡的状态
     * @param target:MovieClip 目标对象
     * @param data:Object 组件数据
     * @private
     */
    private static function _checkZeroHPState(target:MovieClip, data:Object):Void {
        // 获取当前HP
        var currentHP:Number = target.hp;
        
        // HP正常或目标已进入死亡动画，重置计数
        if (currentHP > 0 || target.状态 === "血腥死") {
            _resetZeroHPState(data);
            return;
        }
        
        // 检测到HP为0，增加零血计数
        data.zeroHPCounter++;
        // _root.发布消息("zeroHPCounter: " + data.zeroHPCounter);
        
        // 超过阈值，触发处理
        if (data.zeroHPCounter >= ZERO_HP_THRESHOLD) {
            _handleZeroHPStuck(target, data);
        }
        
        // 更新上次HP记录
        data.lastHP = currentHP;
    }
    
    /**
     * 处理等待复活的逻辑
     * @param target:MovieClip 目标对象
     * @param data:Object 组件数据
     * @private
     */
    private static function _handleRespawnWaiting(target:MovieClip, data:Object):Void {
        // 检查单位是否已经复活（HP已恢复）
        if (target.hp > 0) {
            // 添加日志插桩 - 复活成功
            _root.服务器.发布服务器消息("[ZeroHPDetector] 单位成功复活 - 目标: " + target + ", HP: " + target.hp);
            
            // 单位已复活，发布复活事件
            _publishRespawnEvent(target);
            
            // 重置等待状态
            data.waitingForRespawn = false;
            _resetZeroHPState(data);
            return;
        }
    }
    
    /**
     * 发布复活成功事件
     * @param target:MovieClip 目标对象
     * @private
     */
    private static function _publishRespawnEvent(target:MovieClip):Void {
        target.dispatcher.publish("respawn", target);
        _root.发布消息("[WatchDog] 单位已成功复活: ", target);
    }
    
    /**
     * 重置零血状态计数
     * @param data:Object 组件数据
     * @private
     */
    private static function _resetZeroHPState(data:Object):Void {
        data.zeroHPCounter = 0;
    }
    
    /**
     * 处理零血不死的卡死状态
     * @param target:MovieClip 目标对象
     * @param data:Object 组件数据
     * @private
     */
    private static function _handleZeroHPStuck(target:MovieClip, data:Object):Void {
        // 添加日志插桩
        _root.服务器.发布服务器消息("[ZeroHPDetector] 触发零血不死检测 - 目标: " + target + ", HP: " + target.hp + ", 状态: " + target.状态 + ", respawn: " + target.respawn + ", _killed: " + target._killed);
        
        // 调用回调处理方法
        onZeroHPStuckDetected(target, data);
    }
    
    /**
     * 重置组件状态
     * 在单位重生或状态重置时调用
     * @param target:MovieClip 目标对象
     * @param watchDogData:Object 监视器数据容器
     */
    public static function reset(target:MovieClip, watchDogData:Object):Void {
        var data:Object = watchDogData[NAMESPACE];
        if (data == null) return;
        
        // 重置所有计数和状态
        data.zeroHPCounter = 0;
        data.waitingForRespawn = false;
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
     * 零血不死状态检测回调方法
     * 根据单位是否有复活标签选择不同的处理方式：
     * - 有复活标签的单位：进入等待复活状态
     * - 无复活标签的单位：直接发布击杀事件
     * 
     * @param target:MovieClip 卡死的目标对象
     * @param data:Object 组件数据
     */
    public static function onZeroHPStuckDetected(target:MovieClip, data:Object):Void {
        var dispatcher:EventDispatcher = target.dispatcher;
        
        if (target.respawn) {
            // 添加日志插桩 - 等待复活
            _root.服务器.发布服务器消息("[ZeroHPDetector] 设置等待复活状态 - 目标: " + target);
            
            // 有复活标签的单位，进入等待复活状态
            data.waitingForRespawn = true;
        } else {
            // 无复活标签且未被击杀的单位，直接发布击杀事件
            if (!target._killed) {
                // 添加日志插桩 - 强制击杀
                _root.服务器.发布服务器消息("[ZeroHPDetector] 强制击杀幽灵单位 - 目标: " + target);
                
                dispatcher.publish("kill", target);
            }
        }
    }
    
    /**
     * 设置零血持续检测阈值
     * @param threshold:Number 新的阈值值（默认为10帧）
     */
    public static function setZeroHPThreshold(threshold:Number):Void {
        ZERO_HP_THRESHOLD = threshold;
    }
}