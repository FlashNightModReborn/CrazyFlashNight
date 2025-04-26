// 文件路径：org/flashNight/arki/bullet/BulletComponent/Movement/Util/TrackTargetCallbacks.as

/**
 * 目标追踪回调生成器
 * 提供一个静态方法 create()
 * 返回一个函数用于导弹实例的目标追踪（onTrackTarget）。
 */
class org.flashNight.arki.bullet.BulletComponent.Movement.Util.TrackTargetCallbacks {
    /**
     * 构造目标追踪回调函数。
     * @return Function 追踪目标并调整速度和方向的回调，无返回值。
     */
    public static function create():Function {
        return function():Void {
            if (!this.target || this.target.hp <= 0) {
                this.changeState("SearchTarget");
                this.target = null;
                this.hasTarget = false;
                return;
            }

            var targetObject = this.targetObject;
            var target:MovieClip = this.target;
            var dx:Number = target._x - targetObject._x;

            var coefficient:Number = target.身高 / 175;
            var yOffset:Number = target.中心高度 ? target.中心高度 * coefficient :
                                 target.状态 == "倒地" ? 35 : 75;
            var dy:Number = target._y - targetObject._y - yOffset;

            var targetAngleRadians:Number = Math.atan2(dy, dx);
            var targetAngleDegrees:Number = targetAngleRadians * 180 / Math.PI;
            var angleDifference:Number = targetAngleDegrees - this.rotationAngle;
            if (angleDifference > 180) {
                angleDifference -= 360;
            } else if (angleDifference < -180) {
                angleDifference += 360;
            }

            var rotationStep:Number = Math.min(Math.max(angleDifference, -this._rotationSpeed), this._rotationSpeed);
            this.rotationAngle += rotationStep;
            targetObject.yOffset = yOffset;

            if (this.speed < this.maxSpeed) {
                this.speed += this.acceleration;
            }
        };
    }
}
