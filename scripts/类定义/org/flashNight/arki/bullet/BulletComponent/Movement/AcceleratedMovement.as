import org.flashNight.arki.bullet.BulletComponent.Movement.IMovement;
import org.flashNight.arki.bullet.BulletComponent.Movement.LinearBulletMovement;
import org.flashNight.arki.bullet.BulletComponent.Movement.TrajectoryRotationComponent;

/**
 * AcceleratedMovement - 复合加速移动组件 (已重构)
 * 
 * 组合了三种行为：
 * 1. 一个基础的、恒定的线性速度 (通过 LinearBulletMovement)。
 * 2. 一个基于自身朝向的持续加速 (核心逻辑)。
 * 3. 一个可选的、使自身朝向实际运动轨迹的视觉旋转 (通过 TrajectoryRotationComponent)。
 */
class org.flashNight.arki.bullet.BulletComponent.Movement.AcceleratedMovement implements IMovement {

    // --- 组合的组件 ---
    private var _linearMovement:LinearBulletMovement;
    private var _rotationComponent:TrajectoryRotationComponent;
    
    // --- 加速逻辑的内部状态 ---
    private var _acceleration:Number;         // 加速度大小
    private var _maxSpeed:Number;             // 加速部分的速度上限
    private var _acceleratedSpeedX:Number;    // 由加速产生的X轴速度
    private var _acceleratedSpeedY:Number;    // 由加速产生的Y轴速度

    /**
     * 构造函数
     * @param initialSpeedX         初始线性速度X (用于LinearBulletMovement)
     * @param initialSpeedY         初始线性速度Y (用于LinearBulletMovement)
     * @param acceleration          每一帧的加速度大小
     * @param maxSpeed              由加速产生的速度的上限 (不影响初始速度)
     * @param enableAutoRotation    是否启用自动轨迹旋转
     * @param rotationOffset        轨迹旋转的偏移角度
     */
    public function AcceleratedMovement(initialSpeedX:Number, initialSpeedY:Number, acceleration:Number, maxSpeed:Number, enableAutoRotation:Boolean, rotationOffset:Number) {
        // 1. 创建并配置线性移动组件
        this._linearMovement = LinearBulletMovement.create(initialSpeedX, initialSpeedY, null);
        
        // 2. 创建并配置旋转组件
        this._rotationComponent = new TrajectoryRotationComponent(enableAutoRotation, rotationOffset);

        // 3. 初始化加速参数
        this._acceleration = (acceleration != undefined) ? acceleration : 1;
        this._maxSpeed = (maxSpeed != undefined) ? maxSpeed : Number.POSITIVE_INFINITY;

        // 4. 初始化加速产生的速度
        this._acceleratedSpeedX = 0;
        this._acceleratedSpeedY = 0;

        // 设置入口函数
        this.updateMovement = this.updateWithInitialization;
    }

    /**
     * 第一次调用的初始化更新函数
     */
    private function updateWithInitialization(target:MovieClip):Void {
        // 初始化旋转组件，记录初始位置
        this._rotationComponent.initialize(target);
        
        // 切换到正常运行的更新函数
        this.updateMovement = this.updateWithActiveMovement;
        
        // 执行第一次正常更新
        this.updateWithActiveMovement(target);
    }

    /**
     * 正常运行时的更新函数
     */
    private function updateWithActiveMovement(target:MovieClip):Void {
        // 步骤 1: 应用基础的、恒定的线性移动
        this._linearMovement.updateMovement(target);
        
        // 步骤 2: 计算并应用加速产生的移动
        // 将目标的旋转角度从度转换为弧度
        var angleRad:Number = target._rotation * (Math.PI / 180);
        
        // 根据加速度和方向，更新“加速速度”
        this._acceleratedSpeedX += this._acceleration * Math.cos(angleRad);
        this._acceleratedSpeedY += this._acceleration * Math.sin(angleRad);

        // 步骤 3: 限制“加速速度”的大小，防止无限加速
        var currentAcceleratedSpeed:Number = Math.sqrt(
            this._acceleratedSpeedX * this._acceleratedSpeedX + 
            this._acceleratedSpeedY * this._acceleratedSpeedY
        );

        if (currentAcceleratedSpeed > this._maxSpeed) {
            var scale:Number = this._maxSpeed / currentAcceleratedSpeed;
            this._acceleratedSpeedX *= scale;
            this._acceleratedSpeedY *= scale;
        }

        // 应用“加速速度”产生的位移
        target._x += this._acceleratedSpeedX;
        target._y += this._acceleratedSpeedY;

        // 步骤 4: 更新视觉旋转
        // TrajectoryRotationComponent 会根据物体的【最终】位置变化来计算朝向
        this._rotationComponent.updateMovement(target);
    }

    /**
     * 更新运动逻辑 (入口)
     */
    public function updateMovement(target:MovieClip):Void {
        // 运行时会被动态替换
    }

    /**
     * 静态创建方法，提供更简洁的API。
     */
    public static function create(initialSpeedX:Number, initialSpeedY:Number, acceleration:Number, maxSpeed:Number, enableAutoRotation:Boolean, rotationOffset:Number):AcceleratedMovement {
        return new AcceleratedMovement(initialSpeedX, initialSpeedY, acceleration, maxSpeed, enableAutoRotation, rotationOffset);
    }
}