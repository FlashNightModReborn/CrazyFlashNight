// 文件路径：org/flashNight/arki/bullet/BulletComponent/Movement/Util/PreLaunchMoveCallbacks.as

/**
 * 预发射移动回调生成器
 * ==================
 * 使用配置对象中的参数创建蓄力抛物线动画
 * 
 * 职责：
 *   - 创建预发射阶段的抛物线运动
 *   - 添加随机化的运动参数
 *   - 处理旋转抖动效果
 */
class org.flashNight.arki.bullet.BulletComponent.Movement.Util.PreLaunchMoveCallbacks {
    /**
     * 构造预发射移动回调函数
     * @param config 导弹配置对象
     * @param angleDegrees 导弹初始的旋转角度（度数）
     * @return Function 带随机化参数的抛物线/振荡动画函数
     */
    public static function create(config:Object, angleDegrees:Number):Function {
        return function(flag:String):Boolean {
            if (this._preFrame == undefined) {
                this._preFrame = 0;
                // 设置初始角度
                this.rotationAngle = angleDegrees;

                // 使用配置中的帧数范围
                this._preTotal = config.preLaunchFrames.min + 
                               Math.floor(Math.random() * (config.preLaunchFrames.max - config.preLaunchFrames.min + 1));
                this._launchX = this.targetObject._x;
                this._launchY = this.targetObject._y;
                // 使用配置中的高度范围
                this._peakHeight = config.preLaunchPeakHeight.min + 
                                 Math.random() * (config.preLaunchPeakHeight.max - config.preLaunchPeakHeight.min);
                // 使用配置中的水平振幅范围（添加安全检查）
                if (config.preLaunchHorizAmp != undefined &&
                    config.preLaunchHorizAmp.min != undefined &&
                    config.preLaunchHorizAmp.max != undefined) {
                    this._horizAmp = Number(config.preLaunchHorizAmp.min) +
                                   Math.random() * (Number(config.preLaunchHorizAmp.max) - Number(config.preLaunchHorizAmp.min));
                } else {
                    this._horizAmp = 5; // 默认值
                }

                // 使用配置中的振荡周期范围（添加安全检查）
                if (config.preLaunchCycles != undefined &&
                    config.preLaunchCycles.min != undefined &&
                    config.preLaunchCycles.max != undefined) {
                    this._horizCycles = Number(config.preLaunchCycles.min) +
                                      Math.random() * (Number(config.preLaunchCycles.max) - Number(config.preLaunchCycles.min));
                } else {
                    this._horizCycles = 2; // 默认值
                }
            }
            
            if (flag == "isComplete") {
                return this._preFrame >= this._preTotal;
            }
            
            this._preFrame++;
            var t:Number = this._preFrame / this._preTotal;
            var y:Number;
            
            // 分段抛物线运动
            if (t < 0.4) {
                var t1:Number = t / 0.4;
                y = -this._peakHeight * (1 - Math.pow(1 - t1, 3));
            } else {
                var t2:Number = (t - 0.4) / 0.6;
                y = -this._peakHeight * (1 - Math.pow(t2, 3));
            }
            
            // 水平振荡运动
            var decay:Number = 1 - t;
            var radians:Number = angleDegrees * Math.PI / 180;
            var direction:Number = (Math.cos(radians) > 0) ? 1 : -1;
            var sinValue:Number = Math.sin(2 * Math.PI * this._horizCycles * t);
            var x:Number = direction * this._horizAmp * decay * sinValue;

            // 调试信息
            // _root.服务器.发布服务器消息(this._launchX + " " + "方向:" + direction + ", _horizAmp:" + this._horizAmp + ", decay:" + decay + ", cycles:" + this._horizCycles + ", x:" + x);
            // 使用配置中的旋转抖动参数
            if (t > config.rotationShakeTime.start && t < config.rotationShakeTime.end) {
                this.rotationAngle = angleDegrees + (Math.random() - 0.5) * config.rotationShakeAmplitude;
            } else {
                this.rotationAngle = angleDegrees;
            }
            
            this.targetObject._x = this._launchX + x;
            this.targetObject._y = this._launchY + y;
            // 更新导弹旋转以匹配当前角度
            this.targetObject._rotation = this.rotationAngle;
            this.lockRotation = true;
            return false;
        };
    }
}