import org.flashNight.arki.bullet.BulletComponent.Loader.*;
import org.flashNight.arki.bullet.BulletComponent.Movement.*;
import org.flashNight.arki.bullet.BulletComponent.Movement.Util.*;
import org.flashNight.neur.Server.*;

/**
 * MovementSystem
 * 
 * 管理子弹的移动行为，根据配置数据选择合适的移动类型
 * 接收和处理 MovementLoader 加载的数据
 */
class org.flashNight.arki.bullet.BulletComponent.Movement.MovementSystem {
    // 移动数据映射（由InfoLoader加载）
    private static var movementMap:Object = {};
    // 初始化标志
    private static var initialized:Boolean = false;

    /**
     * 初始化方法：注册InfoLoader回调，加载移动数据
     */
    public static function initialize():Void {
        InfoLoader.getInstance().onLoad(function(data:Object):Void {
            MovementSystem.onMovementDataLoad(data);
        });
    }

    /**
     * 当加载完成 InfoLoader 数据后调用此方法
     * 设置 movementMap 数据
     */
    private static function onMovementDataLoad(data:Object):Void {
        movementMap = data.movementData;
        initialized = true;
        
        // 调试信息
        var server = ServerManager.getInstance();
        server.sendServerMessage("MovementSystem: 移动数据加载成功");
    }

    /**
     * 根据子弹类型创建适当的移动组件
     * 
     * @param bulletType:String - 子弹类型名称
     * @param shooter:Object - 发射者
     * @param bulletInstance:Object - 子弹实例
     * @param speedX:Number - X轴速度
     * @param speedY:Number - Y轴速度
     * @param zyRatio:Number - ZY比例参数
     * @param velocity:Number - 子弹速度
     * @param rotation:Number - 子弹旋转角度
     * @return IMovement - 子弹移动接口实现
     */
    public static function createMovementForBullet(
        bulletType:String, 
        shooter:MovieClip, 
        speedX:Number, 
        speedY:Number, 
        zyRatio:Number,
        velocity:Number,
        rotation:Number
    ):IMovement {
        // 如果系统未初始化或无此子弹类型的移动数据，使用默认线性移动
        if (!initialized || !movementMap || !movementMap[bulletType]) {
            return LinearBulletMovement.create(speedX, speedY, zyRatio);
        }
        
        // 获取此子弹类型的移动信息
        var movementInfo:Object = movementMap[bulletType];
        var movementFunc:String = movementInfo.func;
        
        // 根据func类型创建移动组件
        switch (movementFunc) {
            case "DefaultMissile":
                // 获取导弹配置名称和参数
                var configName:String = "predatorPlasma"; // 默认配置
                var usePreLaunch:Boolean = true; // 默认值
                
                if (movementInfo.param) {
                    if (movementInfo.param.missileConfig) {
                        configName = movementInfo.param.missileConfig;
                    }
                    
                    if (movementInfo.param.usePreLaunch !== undefined) {
                        usePreLaunch = movementInfo.param.usePreLaunch;
                    }
                }
                
                // 构建参数并创建导弹移动
                var missileParams:Object = DefaultMissileCallbacks.build(
                    shooter, 
                    velocity, 
                    rotation,
                    MissileConfig.getInstance().getConfig(configName)
                );
                
                missileParams.usePreLaunch = usePreLaunch;
                return MissileMovement.create(missileParams);
            
            // 可在此处添加其他移动类型
            // case "homing":  // 追踪型
            // case "spiral":  // 螺旋型
            // 等等
                
            case "linear":
            default:
                // 默认使用线性移动
                return LinearBulletMovement.create(speedX, speedY, zyRatio);
        }
    }
    
    /**
     * 检查是否已初始化
     */
    public static function isInitialized():Boolean {
        return initialized;
    }
    
    /**
     * 获取加载的移动数据
     */
    public static function getMovementData():Object {
        return movementMap;
    }
}