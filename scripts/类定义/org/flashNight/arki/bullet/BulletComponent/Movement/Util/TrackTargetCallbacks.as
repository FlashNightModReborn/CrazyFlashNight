// 文件路径：org/flashNight/arki/bullet/BulletComponent/Movement/Util/TrackTargetCallbacks.as
import org.flashNight.arki.unit.UnitUtil;

/**
 * 目标追踪回调生成器（向量化物理模型）
 * ===============================
 * 内部使用速度向量计算，同时保持与外部updateMovement的兼容性
 * 
 * 职责：
 *   - 实现比例导引算法
 *   - 处理导弹物理特性（加速度、阻力、转向）
 *   - 向量化计算以提高精度
 * 
 * 物理模型：
 *   - 推力、阻力、法向力的独立计算
 *   - 转弯产生的诱导阻力模拟
 *   - 速度矢量实时更新
 */
class org.flashNight.arki.bullet.BulletComponent.Movement.Util.TrackTargetCallbacks {
    
    /**
     * 构造目标追踪回调函数
     * @param config 导弹配置对象
     * @return Function 使用向量化物理模型的追踪回调函数
     */
    public static function create(config:Object):Function {
        return function():Void {
            // 目标失效时回退到搜索状态
            if (!this.target || this.target.hp <= 0) {
                this.changeState("SearchTarget");
                this.target = null;
                this.hasTarget = false;
                this.previousLOSAngle = undefined;
                this.vx = undefined;
                this.vy = undefined;
                return;
            }
            
            var targetObject:MovieClip = this.targetObject;
            var target:MovieClip = this.target;
            
            // 初始化速度向量（如果还没有）
            if (this.vx == undefined || this.vy == undefined) {
                var rad:Number = this.rotationAngle * Math.PI / 180;
                this.vx = this.speed * Math.cos(rad);
                this.vy = this.speed * Math.sin(rad);
            }
            
            // 使用 UnitUtil 计算目标偏移
            var yOffset:Number = UnitUtil.calculateCenterOffset(target);
            
            // 计算到目标的向量
            var dx:Number = target._x - targetObject._x;
            var dy:Number = target._y - targetObject._y - yOffset;
            var distance:Number = Math.sqrt(dx * dx + dy * dy);
            
            // 当前视线角度（度）
            var currentLOSAngle:Number = Math.atan2(dy, dx) * 180 / Math.PI;
            
            // 获取或初始化上一帧的视线角度
            if (this.previousLOSAngle == undefined) {
                this.previousLOSAngle = currentLOSAngle;
            }
            
            // 计算视线角速度（度/帧）
            var losAngularVelocity:Number = currentLOSAngle - this.previousLOSAngle;
            
            // 处理角度跨越问题
            if (losAngularVelocity > 180) {
                losAngularVelocity -= 360;
            } else if (losAngularVelocity < -180) {
                losAngularVelocity += 360;
            }
            
            // ========== 向量化物理计算开始 ==========
            
            // 1. 计算所需的导引力方向（比例导引）
            var requiredAngularVelocity:Number = config.navigationRatio * losAngularVelocity;
            
            // 2. 将角速度转换为加速度向量
            var currentSpeed:Number = Math.sqrt(this.vx * this.vx + this.vy * this.vy);
            var currentAngle:Number = Math.atan2(this.vy, this.vx);
            
            // 目标角度
            var targetAngleRad:Number = (currentLOSAngle * Math.PI / 180);
            var angleDiffRad:Number = targetAngleRad - currentAngle;
            
            // 归一化角度差
            while (angleDiffRad > Math.PI) angleDiffRad -= 2 * Math.PI;
            while (angleDiffRad < -Math.PI) angleDiffRad += 2 * Math.PI;
            
            // 3. 计算法向加速度（转向力）
            var maxTurnRateRad:Number = this._rotationSpeed * Math.PI / 180;
            var normalAccel:Number = maxTurnRateRad * currentSpeed; // 最大法向加速度
            
            // 限制转向力
            var turnForce:Number = angleDiffRad * config.angleCorrection * currentSpeed;
            turnForce = Math.max(Math.min(turnForce, normalAccel), -normalAccel);
            
            // 4. 计算法向力的方向
            var normalDirX:Number = -Math.sin(currentAngle);
            var normalDirY:Number = Math.cos(currentAngle);
            
            // 5. 计算推力（切向力）
            var thrustX:Number = 0;
            var thrustY:Number = 0;
            if (currentSpeed < this.maxSpeed) {
                var forwardDirX:Number = Math.cos(currentAngle);
                var forwardDirY:Number = Math.sin(currentAngle);
                thrustX = forwardDirX * this.acceleration;
                thrustY = forwardDirY * this.acceleration;
            }
            
            // 6. 计算阻力（与速度平方成正比）
            var dragCoefficient:Number = config.dragCoefficient || 0.001;
            var speedSquared:Number = currentSpeed * currentSpeed;
            var dragX:Number = -this.vx * dragCoefficient * speedSquared;
            var dragY:Number = -this.vy * dragCoefficient * speedSquared;
            
            // 7. 转弯产生的额外阻力（模拟攻角影响）
            var turnAngle:Number = Math.abs(angleDiffRad);
            var inducedDragFactor:Number = 1 + Math.sin(turnAngle) * 2; // 转弯时阻力增加
            dragX *= inducedDragFactor;
            dragY *= inducedDragFactor;
            
            // 8. 更新速度向量
            this.vx += thrustX + normalDirX * turnForce + dragX;
            this.vy += thrustY + normalDirY * turnForce + dragY;
            
            // 9. 限制最大速度
            var newSpeed:Number = Math.sqrt(this.vx * this.vx + this.vy * this.vy);
            if (newSpeed > this.maxSpeed) {
                var scale:Number = this.maxSpeed / newSpeed;
                this.vx *= scale;
                this.vy *= scale;
                newSpeed = this.maxSpeed;
            }
            
            // ========== 转换回标量形式（为了兼容 updateMovement）==========
            this.speed = newSpeed;
            this.rotationAngle = Math.atan2(this.vy, this.vx) * 180 / Math.PI;
            
            // 更新其他状态
            targetObject.yOffset = yOffset;
            this.previousLOSAngle = currentLOSAngle;
        };
    }
}