// 文件路径：org/flashNight/arki/bullet/BulletComponent/Movement/Util/InitMissileCallbacks.as

/**
 * 初始化导弹回调生成器
 * 提供一个静态方法 create(shooter, velocity, angleRadians)
 * 返回一个函数用于导弹实例的初始化（onInitializeMissile）。
 */
class org.flashNight.arki.bullet.BulletComponent.Movement.Util.InitMissileCallbacks {
    /**
     * 构造导弹初始化回调函数。
     * @param shooter     发射此导弹的 MovieClip 实例。
     * @param velocity    导弹的最大速度。
     * @param angleRadians 导弹初始的旋转角度（弧度）。
     * @return Function   用于设置导弹初始属性的回调函数。
     */
    public static function create(shooter:MovieClip,
                                  velocity:Number,
                                  angleRadians:Number):Function {
        return function():Void {
            // 设置初始速度（通常低于最大速度，以便后续加速）
            this.speed = velocity / 2;
            // 存储发射者的名字，以便后续在全局 gameworld 中查找
            this.shooter = shooter._name;
            // 设置初始旋转角度
            this.rotationAngle = angleRadians;
            // 设置追踪时的旋转速度（每帧最大旋转角度）
            this._rotationSpeed = 1;
            // 设置最大速度
            this.maxSpeed = velocity;
            // 设置追踪时的加速度
            this.acceleration = 10;

            // 初始化搜索相关的内部状态变量（用于限帧搜索）
            this._searchIndex = 0;          
            this._searchTargetCache = null; 
            this._bestTargetSoFar = null;   
            this._minDistanceSoFar = Infinity;
        };
    }
}
