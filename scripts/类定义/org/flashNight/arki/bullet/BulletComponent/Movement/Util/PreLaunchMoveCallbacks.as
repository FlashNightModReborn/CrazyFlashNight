// 文件路径：org/flashNight/arki/bullet/BulletComponent/Movement/Util/PreLaunchMoveCallbacks.as

/**
 * 预发射移动回调生成器
 * 提供一个静态方法 create()
 * 返回一个函数用于导弹实例的蓄力抛物线动画（onPreLaunchMove）。
 */
class org.flashNight.arki.bullet.BulletComponent.Movement.Util.PreLaunchMoveCallbacks {
    /**
     * 构造预发射移动回调函数。
     * @return Function 带随机化参数的抛物线/振荡动画函数，返回 Boolean（"isComplete" 时返回是否完成）。
     */
    public static function create():Function {
        return function(flag:String):Boolean {
            if (this._preFrame == undefined) {
                this._preFrame   = 0;
                this._preTotal   = 10 + Math.floor(Math.random() * 6);
                this._launchX    = this.targetObject._x;
                this._launchY    = this.targetObject._y;
                this._peakHeight = 20 + Math.random() * 40;
                this._horizAmp   = Math.random() * 8;
                this._horizCycles= 1 + Math.random() * 2;
            }
            if (flag == "isComplete") {
                return this._preFrame >= this._preTotal;
            }
            this._preFrame++;
            var t:Number = this._preFrame / this._preTotal;
            var y:Number;
            if (t < 0.4) {
                var t1:Number = t / 0.4;
                y = -this._peakHeight * (1 - Math.pow(1 - t1, 3));
            } else {
                var t2:Number = (t - 0.4) / 0.6;
                y = -this._peakHeight * (1 - Math.pow(t2, 3));
            }
            var decay:Number = 1 - t;
            var x:Number = this._horizAmp * decay * Math.sin(2 * Math.PI * this._horizCycles * t);
            if (t > 0.35 && t < 0.45) {
                this.rotationAngle += (Math.random() - 0.5) * 0.4;
            }
            this.targetObject._x = this._launchX + x;
            this.targetObject._y = this._launchY + y;
            return false;
        };
    }
}
