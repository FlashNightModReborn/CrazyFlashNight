import org.flashNight.arki.bullet.BulletComponent.Movement.IMovement;
import org.flashNight.arki.bullet.BulletComponent.Movement.LinearBulletMovement;
// 导入新的旋转组件
import org.flashNight.arki.bullet.BulletComponent.Movement.TrajectoryRotationComponent;

/**
 * FreeFallLinearMovement - 自由落体线性移动类 (已重构)
 * 
 * 组合了线性移动、自由落体和轨迹旋转功能。
 * 旋转逻辑已委托给 TrajectoryRotationComponent。
 */
class org.flashNight.arki.bullet.BulletComponent.Movement.FreeFallLinearMovement implements IMovement {
    // --- 核心组件 ---
    private var linearMovement:LinearBulletMovement;
    private var rotationComponent:TrajectoryRotationComponent; // 变化1: 引入旋转组件
    
    // --- 自由落体属性 ---
    private var verticalSpeed:Number;
    private var startY:Number;

    /**
     * 构造函数 (已更新)
     */
    public function FreeFallLinearMovement(speedX:Number, speedY:Number, zyRatio:Number, enableAutoRotation:Boolean, rotationOffset:Number) {
        // 创建线性移动组件
        this.linearMovement = LinearBulletMovement.create(speedX, speedY, zyRatio);
        
        // 变化2: 创建并配置旋转组件，而不是在自身存储旋转属性
        this.rotationComponent = new TrajectoryRotationComponent(enableAutoRotation, rotationOffset);
        
        // 初始化自由落体参数
        this.verticalSpeed = -5;
        
        // 初始化运动函数指针
        this.updateMovement = this.updateWithInitialization;
    }

    /**
     * 初始化更新函数 (已更新)
     */
    private function updateWithInitialization(target:MovieClip):Void {
        if (target.Z轴坐标 != undefined) {
            this.startY = target.Z轴坐标;
        } else {
            this.startY = target._y;
        }
        
        // 变化3: 调用旋转组件的初始化方法
        this.rotationComponent.initialize(target);
        
        // 切换到正常运行的更新函数
        this.updateMovement = this.updateWithActiveMovement;
        
        // 执行第一次正常更新
        this.updateWithActiveMovement(target);
    }

    /**
     * 正常运行时的更新函数 (已更新)
     */
    private function updateWithActiveMovement(target:MovieClip):Void {
        // 1. 执行线性移动
        this.linearMovement.updateMovement(target);
        
        // 2. 更新Y坐标（自由落体）
        target._y += this.verticalSpeed;
        
        // 3. 变化4: 将旋转逻辑委托给旋转组件
        this.rotationComponent.updateMovement(target);
        
        // 4. 应用重力加速度
        this.verticalSpeed += _root.重力加速度;
        
        // 5. 检查是否触地
        if (target._y >= this.startY) {
            this.onLanding(target);
        }
    }

    /**
     * 停止状态的更新函数
     */
    private function updateWithStoppedMovement(target:MovieClip):Void {
        // 不执行任何移动逻辑
    }

    /**
     * 触地处理
     */
    private function onLanding(target:MovieClip):Void {
        target._y = this.startY;
        this.updateMovement = this.updateWithStoppedMovement;
        target.gotoAndPlay("消失");
    }

    /**
     * 更新运动逻辑 (入口)
     */
    public function updateMovement(target:MovieClip):Void {
        // 运行时会被动态替换
    }

    // --- 变化5: 所有公共API现在都委托给相应的组件 ---

    public function getVerticalSpeed():Number {
        return this.verticalSpeed;
    }

    public function setVerticalSpeed(speed:Number):Void {
        this.verticalSpeed = speed;
    }

    public function setAutoRotation(enable:Boolean):Void {
        this.rotationComponent.setEnable(enable);
    }

    public function getAutoRotation():Boolean {
        return this.rotationComponent.getEnable();
    }

    public function setRotationOffset(offset:Number):Void {
        this.rotationComponent.setOffset(offset);
    }

    public function getRotationOffset():Number {
        return this.rotationComponent.getOffset();
    }
    
    public function resetFreeFall():Void {
        this.verticalSpeed = -5;
        this.updateMovement = this.updateWithInitialization;
    }

    // --- 静态创建方法保持不变，因为它们的接口没有变化 ---

    public static function create(speedX:Number, speedY:Number, zyRatio:Number, enableAutoRotation:Boolean, rotationOffset:Number):FreeFallLinearMovement {
        return new FreeFallLinearMovement(speedX, speedY, zyRatio, enableAutoRotation, rotationOffset);
    }

    public static function createWithRotation(speedX:Number, speedY:Number, zyRatio:Number, rotationOffset:Number):FreeFallLinearMovement {
        return new FreeFallLinearMovement(speedX, speedY, zyRatio, true, rotationOffset);
    }

    public static function createWithoutRotation(speedX:Number, speedY:Number, zyRatio:Number):FreeFallLinearMovement {
        return new FreeFallLinearMovement(speedX, speedY, zyRatio, false, 0);
    }
}