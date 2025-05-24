// 文件路径：org/flashNight/arki/bullet/BulletComponent/Movement/Util/TrackTargetCallbacks.as
import org.flashNight.arki.unit.UnitUtil;

/**
 * 目标追踪回调生成器（比例导引算法实现）
 * ===============================
 * 专注于实现比例导引算法，计算所需的转向参数
 * 
 * 职责：
 * - 实现比例导引算法
 * - 计算视线角速度
 * - 计算期望的转向角速度
 * - 处理目标失效情况
 * 
 * 导引模型：
 * - 使用比例导引算法
 * - 计算视线角速度
 * - 输出期望的转向角速度
 */
class org.flashNight.arki.bullet.BulletComponent.Movement.Util.TrackTargetCallbacks {
    
    /**
     * 构造目标追踪回调函数
     * @param config 导弹配置对象，包含以下属性：
     *               - navigationRatio: Number 比例导引系数
     *               - angleCorrection: Number 角度修正系数
     * @return Function 计算比例导引参数的回调函数
     */
    public static function create(config:Object):Function {
        return function():Void {
            // 目标失效时回退到搜索状态
            if (!this.target || this.target.hp <= 0) {
                this.changeState("SearchTarget");
                this.target = null;
                this.hasTarget = false;
                this.previousLOSAngle = undefined;
                this.setDesiredAngularVelocity(0);  // 清除导引指令
                return;
            }
            
            var targetObject:MovieClip = this.targetObject;
            var target:MovieClip = this.target;
            
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
                this.setDesiredAngularVelocity(0);
                return;
            }
            
            // 计算视线角速度（度/帧）
            var losAngularVelocity:Number = currentLOSAngle - this.previousLOSAngle;
            
            // 处理角度跨越问题
            if (losAngularVelocity > 180) {
                losAngularVelocity -= 360;
            } else if (losAngularVelocity < -180) {
                losAngularVelocity += 360;
            }
            
            // ========== 比例导引计算 ==========
            
            // 1. 计算所需的导引角速度（度/帧）
            var requiredAngularVelocity:Number = config.navigationRatio * losAngularVelocity;
            
            // 2. 计算角度差并应用修正
            var currentAngle:Number = this.rotationAngle;
            var angleDiff:Number = currentLOSAngle - currentAngle;
            
            // 归一化角度差
            while (angleDiff > 180) angleDiff -= 360;
            while (angleDiff < -180) angleDiff += 360;
            
            // 应用角度修正系数
            var correctedAngularVelocity:Number = angleDiff * config.angleCorrection;
            
            // 3. 合并导引指令和角度修正
            var finalAngularVelocity:Number = (requiredAngularVelocity + correctedAngularVelocity) / 2;
            
            // 4. 转换为弧度/帧并设置到导弹组件
            this.setDesiredAngularVelocity(finalAngularVelocity * Math.PI / 180);
            
            // 更新状态
            this.previousLOSAngle = currentLOSAngle;
            targetObject.yOffset = yOffset;
        };
    }
}