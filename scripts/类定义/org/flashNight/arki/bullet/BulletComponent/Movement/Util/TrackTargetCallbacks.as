// 文件路径：org/flashNight/arki/bullet/BulletComponent/Movement/Util/TrackTargetCallbacks.as
/**
 * 目标追踪回调生成器
 * 使用比例导引法（Proportional Navigation）实现导弹追踪
 * 导弹角速度 = N × 视线角速度
 * 引入物理化转向损速：每帧速度损失 Δv = v * Δθ_rad
 * 
 */
class org.flashNight.arki.bullet.BulletComponent.Movement.Util.TrackTargetCallbacks {
    
    /** 默认导引比，通常取3-5之间 */
    private static var DEFAULT_NAVIGATION_RATIO:Number = 4;
    
    /**
     * 构造目标追踪回调函数
     * @param navigationRatio 导引比（可选，默认为4）
     * @return Function 使用比例导引法追踪目标的回调函数
     */
    public static function create(navigationRatio:Number):Function {
        if (navigationRatio == undefined) {
            navigationRatio = DEFAULT_NAVIGATION_RATIO;
        }
        
        return function():Void {
            // 目标失效时回退到搜索状态
            if (!this.target || this.target.hp <= 0) {
                this.changeState("SearchTarget");
                this.target = null;
                this.hasTarget = false;
                // 清除存储的视线角度
                this.previousLOSAngle = undefined;
                return;
            }
            
            var targetObject:MovieClip = this.targetObject;
            var target:MovieClip = this.target;
            
            // 计算水平和垂直偏移
            var dx:Number = target._x - targetObject._x;
            var coefficient:Number = target.身高 / 175;
            var yOffset:Number = target.中心高度
                               ? target.中心高度 * coefficient
                               : (target.状态 == "倒地" ? 35 : 75);
            var dy:Number = target._y - targetObject._y - yOffset;
            
            // 计算到目标的距离
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
            
            // 比例导引法：计算需要的角速度
            var requiredAngularVelocity:Number = navigationRatio * losAngularVelocity;
            
            // 计算当前航向角与目标视线的角度差
            var angleDifference:Number = currentLOSAngle - this.rotationAngle;
            if (angleDifference > 180) {
                angleDifference -= 360;
            } else if (angleDifference < -180) {
                angleDifference += 360;
            }
            
            // 计算最终旋转步长
            var rotationStep:Number = requiredAngularVelocity + angleDifference * 0.1;
            
            // 限制最大旋转步长
            rotationStep = Math.min(
                Math.max(rotationStep, -this._rotationSpeed),
                this._rotationSpeed
            );
            
            // 应用旋转
            this.rotationAngle += rotationStep;
            targetObject.yOffset = yOffset;
            
            // 物理化速度损失
            var deltaRad:Number = Math.abs(rotationStep) * Math.PI / 180;
            var speedLoss:Number = this.speed * deltaRad;
            this.speed = Math.max(this.speed - speedLoss, 0);
            
            // 加速（如果未达最大速度）
            if (this.speed < this.maxSpeed) {
                this.speed += this.acceleration;
            }
            
            // 更新视线角度记录，为下一帧做准备
            this.previousLOSAngle = currentLOSAngle;
        };
    }
}