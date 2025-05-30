import org.flashNight.arki.spatial.animation.FragmentConfig;
import org.flashNight.arki.spatial.animation.FragmentAnimationInstance;

/**
 * 地图元件破碎动画管理器
 * 
 * 这是一个静态管理类，负责创建、控制和销毁碎片动画实例。
 * 支持同时运行多个动画实例，每个实例都有独立的物理计算和碰撞检测。
 * 
 * 功能特性：
 * - 多实例动画支持：可同时运行多个不同的破碎动画
 * - 实例生命周期管理：自动或手动控制动画的开始和结束
 * - 内存优化：动画结束后自动清理资源，防止内存泄漏
 * - 调试支持：提供详细的运行状态信息
 * 
 * 物理模拟特性：
 * - 基于质量的物理计算：不同尺寸的碎片具有不同的物理行为
 * - 重力系统：模拟真实的重力加速度
 * - 碰撞检测：碎片间的弹性碰撞计算
 * - 摩擦力模拟：地面摩擦和空气阻力
 * - 能量损耗：碰撞和摩擦导致的能量衰减
 * 
 */
class org.flashNight.arki.spatial.animation.FragmentAnimator {
    
    /**
     * 全局动画实例存储容器
     * 使用Object模拟Dictionary功能，键为动画ID，值为动画实例
     */
    private static var _animationInstances:Object = {};
    
    /**
     * 下一个可用的动画实例ID
     * 每创建一个新动画实例时自增，确保ID的唯一性
     */
    private static var _nextAnimationId:Number = 1;
    
    /**
     * 启动地图元件破碎动画
     * 
     * 此方法创建一个新的动画实例，并立即开始播放。动画会自动处理：
     * 1. 碎片的初始化和质量计算
     * 2. 初始速度的随机分配
     * 3. 物理模拟的逐帧更新
     * 4. 碰撞检测和响应
     * 5. 动画结束时的自动清理
     * 
     * @param scope:MovieClip 动画的作用域容器，碎片MovieClip应该是此容器的子对象
     * @param fragmentPrefix:String 碎片MovieClip的名称前缀，实际碎片名称为前缀+数字(1,2,3...)
     * @param config:FragmentConfig 可选的配置参数，如果为null则使用默认配置
     * @return Number 返回动画实例的唯一ID，可用于后续的控制操作（如停止动画）
     * 
     * @throws Error 当scope或fragmentPrefix参数无效时抛出异常
     * 
     * @example
     * // 基础用法：使用默认配置
     * var animId:Number = FragmentAnimator.startAnimation(container, "碎片");
     * 
     * @example
     * // 高级用法：使用自定义配置
     * var config:FragmentConfig = new FragmentConfig();
     * config.gravity = 2.0;
     * config.fragmentCount = 15;
     * config.enableDebug = true;
     * var animId:Number = FragmentAnimator.startAnimation(container, "资源箱碎片", config);
     */
    public static function startAnimation(scope:MovieClip, fragmentPrefix:String, config:FragmentConfig):Number {
        // 严格的参数验证，确保传入参数的有效性
        if (!scope) {
            trace("[FragmentAnimator] 错误：scope参数不能为空");
            return -1;
        }
        if (!fragmentPrefix || fragmentPrefix.length == 0) {
            trace("[FragmentAnimator] 错误：fragmentPrefix参数不能为空");
            return -1;
        }
        
        // 如果没有提供配置，则使用默认配置
        // 如果提供了配置，则克隆一份以避免外部修改影响动画
        var cfg:FragmentConfig = config ? config.clone() : new FragmentConfig();
        
        // 生成唯一的动画实例ID
        var animationId:Number = _nextAnimationId++;
        
        // 创建动画实例对象
        // 此实例将独立管理自己的碎片、物理计算和生命周期
        var instance:FragmentAnimationInstance = new FragmentAnimationInstance(
            animationId, scope, fragmentPrefix, cfg
        );
        
        // 将实例存储到全局容器中，便于后续管理
        _animationInstances[animationId] = instance;
        
        // 启动动画实例
        instance.start();
        
        // 输出调试信息（如果启用了调试模式）
        if (cfg.enableDebug) {
            trace("[FragmentAnimator] 动画已启动: " + fragmentPrefix + ", ID: " + animationId + 
                  ", 碎片数量: " + cfg.fragmentCount);
        }
        
        return animationId;
    }
    
    /**
     * 停止指定的动画实例
     * 
     * 此方法会立即停止指定ID的动画实例，并清理相关资源。
     * 停止后的动画无法恢复，如需重新播放需要调用startAnimation创建新实例。
     * 
     * @param animationId:Number 要停止的动画实例ID（由startAnimation方法返回）
     * @return Boolean 返回true表示成功停止，false表示未找到对应的动画实例
     * 
     * @example
     * var animId:Number = FragmentAnimator.startAnimation(container, "碎片");
     * // ... 一段时间后
     * FragmentAnimator.stopAnimation(animId);
     */
    public static function stopAnimation(animationId:Number):Boolean {
        var instance:FragmentAnimationInstance = _animationInstances[animationId];
        if (instance) {
            // 停止动画实例的更新循环
            instance.stop();
            // 从全局容器中移除引用，帮助垃圾回收
            delete _animationInstances[animationId];
            return true;
        }
        return false;
    }
    
    /**
     * 停止所有当前运行的动画实例
     * 
     * 此方法会遍历所有活动的动画实例并逐一停止，然后清空存储容器。
     * 通常用于场景切换、游戏暂停或紧急清理等情况。
     * 
     * @return Number 返回被停止的动画实例数量
     * 
     * @example
     * // 游戏暂停时停止所有动画
     * var stoppedCount:Number = FragmentAnimator.stopAllAnimations();
     * trace("已停止 " + stoppedCount + " 个动画实例");
     */
    public static function stopAllAnimations():Number {
        var count:Number = 0;
        
        // 遍历所有存储的动画实例
        for (var id:String in _animationInstances) {
            var instance:FragmentAnimationInstance = _animationInstances[id];
            if (instance) {
                instance.stop();
                count++;
            }
        }
        
        // 清空存储容器
        _animationInstances = {};
        
        return count;
    }
    
    /**
     * 获取当前活动的动画实例数量
     * 
     * 此方法统计当前正在运行的动画实例总数，可用于：
     * - 性能监控：避免同时运行过多动画影响性能
     * - 资源管理：控制内存使用
     * - 调试信息：了解当前系统状态
     * 
     * @return Number 当前活动的动画实例数量
     * 
     * @example
     * if (FragmentAnimator.getActiveAnimationCount() < 5) {
     *     // 如果当前动画数量较少，可以启动新动画
     *     FragmentAnimator.startAnimation(container, "新碎片");
     * }
     */
    public static function getActiveAnimationCount():Number {
        var count:Number = 0;
        
        // 遍历统计有效的动画实例
        for (var id:String in _animationInstances) {
            if (_animationInstances[id]) {
                count++;
            }
        }
        
        return count;
    }
    
    /**
     * 检查指定ID的动画是否正在运行
     * 
     * @param animationId:Number 要检查的动画实例ID
     * @return Boolean 如果动画存在且正在运行返回true，否则返回false
     */
    public static function isAnimationRunning(animationId:Number):Boolean {
        var instance:FragmentAnimationInstance = _animationInstances[animationId];
        return (instance && instance.isRunning());
    }
    
    /**
     * 获取所有活动动画的ID列表
     * 
     * @return Array 包含所有活动动画ID的数组
     */
    public static function getActiveAnimationIds():Array {
        var ids:Array = [];
        
        for (var id:String in _animationInstances) {
            if (_animationInstances[id]) {
                ids.push(Number(id));
            }
        }
        
        return ids;
    }
    
    /**
     * 内部方法：由动画实例调用，用于自我清理
     * 当动画自然结束时，实例会调用此方法从全局容器中移除自己
     * 
     * @param animationId:Number 要清理的动画实例ID
     */
    public static function _removeAnimationInstance(animationId:Number):Void {
        delete _animationInstances[animationId];
    }
}