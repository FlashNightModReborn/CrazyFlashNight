import org.flashNight.arki.unit.UnitComponent.Updater.WatchDogComponent.*;

/**
 * 监视器更新管理器
 * 
 * 负责管理和协调所有WatchDog监视组件的运行。
 * 作为组件系统的主入口点，处理组件的初始化和更新调度。
 * 
 * @version 1.0
 * @update 2025-05-16
 */
class org.flashNight.arki.unit.UnitComponent.Updater.WatchDogUpdater {
    
    /**
     * 初始化目标对象的所有监视组件
     * @param target:MovieClip 需要监视的目标对象
     */
    public static function init(target:MovieClip):Void {
        // 创建监视数据主容器
        var watchDogData:Object = target.watchDogData = {};
        
        // 初始化各监视组件
        // 1. 硬直卡死检测组件
        // StiffDetector.init(target, watchDogData); // 暂时禁用，测试中未触发
        StuckDetector.init(target, watchDogData);

        // 2. 0血不死检测组件
        ZeroHPDetector.init(target, watchDogData);
        
        // [预留] 其他监视组件的初始化
        // Component2.init(target, watchDogData);
        // Component3.init(target, watchDogData);
        
        // 记录已初始化标记
        watchDogData.initialized = true;
    }
    
    /**
     * 更新所有监视组件，每帧调用
     * @param target:MovieClip 需要监视的目标对象
     */
    public static function update(target:MovieClip):Void {
        // 安全检查：确保已初始化
        var watchDogData:Object = target.watchDogData;
        /*
        if (watchDogData == null || watchDogData.initialized !== true) {
            init(target);
            return;
        }
        */

        if(_root.控制目标 === target._name) {
            var state:Object = {
                                    长枪:true,
                                    手枪:true,
                                    手枪2:true,
                                    双枪:true,
                                    手雷:true
            };

            if(!state[target.攻击模式]) {
                target.射击最大后摇中 = false;
                // _root.发布消息(target.射击最大后摇中, target.攻击模式)
            }
        }

        
        
        // 依次更新各监视组件
        // 1. 更新硬直卡死检测
        // StiffDetector.update(target, watchDogData); // 暂时禁用，测试中未触发
        StuckDetector.update(target, watchDogData);

        // 2. 更新0血不死检测
        ZeroHPDetector.update(target, watchDogData);
        
        // [预留] 其他监视组件的更新
        // Component2.update(target, watchDogData);
        // Component3.update(target, watchDogData);
    }
    
    /**
     * 重置所有监视组件状态
     * 在角色状态发生重大变化时调用（如：复活、传送等）
     * @param target:MovieClip 需要重置的目标对象
     */
    public static function reset(target:MovieClip):Void {
        var watchDogData:Object = target.watchDogData;
        if (watchDogData == null) return;
        
        // 重置各组件
        // StiffDetector.reset(target, watchDogData); // 暂时禁用，测试中未触发
        StuckDetector.reset(target, watchDogData);
        ZeroHPDetector.reset(target, watchDogData);
        
        // [预留] 其他组件重置
    }
    
    /**
     * 销毁监视器及其数据
     * 在角色被删除前调用，防止内存泄漏
     * @param target:MovieClip 需要清理的目标对象
     */
    public static function destroy(target:MovieClip):Void {
        delete target.watchDogData;
    }
}