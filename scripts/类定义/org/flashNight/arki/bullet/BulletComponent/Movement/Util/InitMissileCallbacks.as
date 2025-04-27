// 文件路径：org/flashNight/arki/bullet/BulletComponent/Movement/Util/InitMissileCallbacks.as

/**
 * 初始化导弹回调生成器
 * ==================
 * 使用配置对象中的参数初始化导弹属性
 * 
 * 职责：
 *   - 设置导弹初始物理属性
 *   - 初始化导弹内部状态
 *   - 配置搜索相关参数
 */
class org.flashNight.arki.bullet.BulletComponent.Movement.Util.InitMissileCallbacks {
    /**
     * 构造导弹初始化回调函数
     * @param shooter 发射此导弹的 MovieClip 实例
     * @param velocity 导弹的最大速度
     * @param angleRadians 导弹初始的旋转角度（弧度）
     * @param config 导弹配置对象
     * @return Function 用于设置导弹初始属性的回调函数
     */
    public static function create(shooter:MovieClip,
                                velocity:Number,
                                angleRadians:Number,
                                config:Object):Function {
        return function():Void {
            // 根据配置设置初始速度
            this.speed = velocity * config.initialSpeedRatio;
            // 存储发射者的名字
            this.shooter = shooter._name;
            // 设置初始旋转角度
            this.rotationAngle = angleRadians;
            // 使用配置中的旋转速度
            this._rotationSpeed = config.rotationSpeed;
            // 设置最大速度
            this.maxSpeed = velocity;
            // 使用配置中的加速度
            this.acceleration = config.acceleration;

            // 初始化搜索相关的内部状态变量
            this._searchIndex = 0;          
            this._searchTargetCache = null; 
            this._bestTargetSoFar = null;   
            this._minDistanceSoFar = Infinity;
        };
    }
}