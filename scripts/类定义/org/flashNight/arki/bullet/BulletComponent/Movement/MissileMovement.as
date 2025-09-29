// 文件路径：org/flashNight/arki/bullet/BulletComponent/Movement/MissileMovement.as

import org.flashNight.arki.bullet.BulletComponent.Movement.BaseMissileMovement;
import org.flashNight.arki.bullet.BulletComponent.Movement.IMovement;

/**
 * MissileMovement
 * ===============
 * 面向"寻的追踪弹 / 导弹"专用运动组件。
 * 
 * • 继承自 BaseMissileMovement：获得 FSM、委托、速度/角度属性等通用能力。
 * • 实现 IMovement：保持与 BulletSystem 的 updateMovement(target) 统一接口。
 * • 集成完整的向量化物理模型：包括推力、阻力、法向力、诱导阻力等。
 * 
 * 典型绑定流程：
 * var movement:MissileMovement = MissileMovement.create(configObj);
 * movement.targetObject = missileClip;
 * missileClip.movement = movement;    // 供子弹管理器引用
 * 在 BulletLoop 中调用 movement.updateMovement(missileClip);
 *
 * @author flashNight
 */
class org.flashNight.arki.bullet.BulletComponent.Movement.MissileMovement 
    extends BaseMissileMovement implements IMovement 
{
    // --------------------------
    // 物理属性
    // --------------------------
    
    // 速度向量
    public var vx:Number = 0;
    public var vy:Number = 0;
    public var _rotationSpeed:Number = 0;
    
    // 期望的转向角速度（由导引算法计算得出）
    public var desiredAngularVelocity:Number = 0;
    
    // 物理配置参数
    public var config:Object;
    public var frame:Number = 0;
    
    // 配置默认值
    private static var DEFAULT_CONFIG:Object = {
        dragCoefficient: 0.001,
        navigationRatio: 3,
        angleCorrection: 2,
        rotationSpeed: 5  // 默认最大转向速度（度/帧）
    };
    
    // --------------------------
    // 构造 & 工厂
    // --------------------------
    
    /**
     * 构造函数（直接透传给父类；建议走 create() 工厂方法）
     * @param params:Object 参见 BaseMissileMovement 文档
     */
    public function MissileMovement(params:Object) 
    {
        super(params);   // BaseMissileMovement 会完成：委托绑定 + 状态机初始化
        
        // 初始化配置
        this.config = params.config || {};
        
        // 合并默认配置
        for (var key:String in DEFAULT_CONFIG) {
            if (this.config[key] == undefined) {
                this.config[key] = DEFAULT_CONFIG[key];
            }
        }
        
        // 设置转向速度
        this._rotationSpeed = this.config.rotationSpeed;
    }
    
    /**
     * 工厂方法 —— 与 LinearBulletMovement 的 create() 统一风格
     * @param params:Object 同构造函数
     */
    public static function create(params:Object):MissileMovement 
    {
        return new MissileMovement(params);
    }
    
    // --------------------------
    // IMovement 实现
    // --------------------------
    
    /**
     * 每帧由 BulletManager 驱动。
     * 统一处理所有物理计算，包括推力、阻力、法向力等。
     * 
     * @param target:MovieClip 当前导弹 Clip（外层系统负责传入）
     */
    public function updateMovement(target:MovieClip):Void 
    {
        // 确保 targetObject 引用正确
        this.targetObject = target;
        
        // 调用状态机更新逻辑（获取导引参数等）
        super.updateMovement(target);
        
        ++frame;
        

        if(frame === 1) {
            target.zOffset = target.Z轴坐标 - target._y;
        } else if(frame >= 150) {
            target.shouldDestroy = function() {
                return true;
            };
        }
        
        // ========== 向量化物理计算开始 ==========
        
        // 1. 当前状态
        var currentSpeed:Number = Math.sqrt(this.vx * this.vx + this.vy * this.vy);
        var currentAngle:Number = Math.atan2(this.vy, this.vx);
        
        // 2. 计算法向加速度（转向力）
        var maxTurnRateRad:Number = this._rotationSpeed * Math.PI / 180;
        var normalAccel:Number = maxTurnRateRad * currentSpeed; // 最大法向加速度
        
        // 使用期望的角速度计算转向力
        var turnForce:Number = this.desiredAngularVelocity * currentSpeed;
        turnForce = Math.max(Math.min(turnForce, normalAccel), -normalAccel);
        
        // 3. 计算法向力的方向
        var normalDirX:Number = -Math.sin(currentAngle);
        var normalDirY:Number = Math.cos(currentAngle);
        
        // 4. 计算推力（切向力）
        var thrustX:Number = 0;
        var thrustY:Number = 0;
        if (currentSpeed < this.maxSpeed) {
            var forwardDirX:Number = Math.cos(currentAngle);
            var forwardDirY:Number = Math.sin(currentAngle);
            thrustX = forwardDirX * this.acceleration;
            thrustY = forwardDirY * this.acceleration;
        }
        
        // 5. 计算阻力（与速度平方成正比）
        var dragCoefficient:Number = this.config.dragCoefficient;
        var speedSquared:Number = currentSpeed * currentSpeed;
        var dragX:Number = -this.vx * dragCoefficient * speedSquared;
        var dragY:Number = -this.vy * dragCoefficient * speedSquared;
        
        // 6. 转弯产生的额外阻力（模拟攻角影响）
        var turnAngle:Number = Math.abs(this.desiredAngularVelocity);
        var inducedDragFactor:Number = 1 + Math.sin(turnAngle) * 2; // 转弯时阻力增加
        dragX *= inducedDragFactor;
        dragY *= inducedDragFactor;
        
        // 7. 更新速度向量
        this.vx += thrustX + normalDirX * turnForce + dragX;
        this.vy += thrustY + normalDirY * turnForce + dragY;
        
        // 8. 限制最大速度
        var newSpeed:Number = Math.sqrt(this.vx * this.vx + this.vy * this.vy);
        if (newSpeed > this.maxSpeed) {
            var scale:Number = this.maxSpeed / newSpeed;
            this.vx *= scale;
            this.vy *= scale;
            newSpeed = this.maxSpeed;
        }
        
        // ========== 更新导弹状态 ==========
        
        // 更新速度和角度
        this.speed = newSpeed;
        if(this.lockRotation) {
            this.lockRotation = false;
        } else {
            this.rotationAngle += this.desiredAngularVelocity * 180 / Math.PI;
        }
        
        // 更新位置和显示
        target._x += this.vx;
        target._y += this.vy;
        target._rotation = this.rotationAngle;
        target.Z轴坐标 = target._y + (target.yOffset || target.zOffset);
    }

    /**
     * 自由飞行逻辑
     * 实现导弹的自由飞行逻辑，包括速度更新和位置更新。
     */
    public function freeFly():Void {
    }
    
    /**
     * 设置期望的角速度（由导引算法调用）
     * @param angularVelocity: Number 期望的角速度（弧度/帧）
     */
    public function setDesiredAngularVelocity(angularVelocity:Number):Void 
    {
        this.desiredAngularVelocity = angularVelocity;
    }
}