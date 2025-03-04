// 文件路径：org.flashNight.arki.bullet.BulletComponent.Movement.LinearBulletMovement.as

import org.flashNight.arki.bullet.BulletComponent.Movement.IMovement;

class org.flashNight.arki.bullet.BulletComponent.Movement.LinearBulletMovement implements IMovement {
    private var _speedX:Number;
    private var _speedY:Number;
    private var _zyRatio:Number;

    // 动态绑定的方法
    private var updateMovementDelegate:Function;

    /**
     * 构造函数，后续需要考虑是否应该设置成私有避免外部构造
     * @param _speedX:Number 子弹的 X 轴速度。
     * @param _speedY:Number 子弹的 Y 轴速度。
     * @param _zyRatio:Number ZY 比例，用于计算 Z 轴坐标。
     */
    public function LinearBulletMovement(_speedX:Number, _speedY:Number, _zyRatio:Number) {
        this._speedX = _speedX;
        this._speedY = _speedY;
        this._zyRatio = _zyRatio;

        // 初始化代理函数
        this.initializeDelegates();
    }

    /**
     * 初始化更新逻辑代理。
     */
    private function initializeDelegates():Void {
        this.updateMovementDelegate = this.getUpdateMovementFunction();
    }

    /**
     * 根据参数选择更新逻辑。
     * @return Function 更新逻辑函数。
     */
    private function getUpdateMovementFunction():Function {
        if (this._speedX == undefined && this._speedY == undefined) {
            return this.updateWithDefaultMovement;
        } else if (this._zyRatio == undefined) {
            return this.updateWithoutZCoordinate;
        } else {
            return this.updateWithFullMovement;
        }
    }

    /**
     * 更新运动逻辑 - 默认使用 xmov 和 ymov。
     * @param target:MovieClip 目标对象。
     */
    private function updateWithDefaultMovement(target:MovieClip):Void {
        var xmov:Number = target.xmov;
        var ymov:Number = target.ymov;
        target._x += xmov;
        target._y += ymov;
    }

    /**
     * 更新运动逻辑 - 无需 Z 坐标。
     * @param target:MovieClip 目标对象。
     */
    private function updateWithoutZCoordinate(target:MovieClip):Void {
        target._x += this._speedX;
        target._y += this._speedY;
    }

    /**
     * 更新运动逻辑 - 完整更新包括 Z 坐标。
     * @param target:MovieClip 目标对象。
     */
    private function updateWithFullMovement(target:MovieClip):Void {
        target._x += this._speedX;
        target._y += this._speedY;
        target.Z轴坐标 = target._y * this._zyRatio;
    }

    /**
     * 更新运动逻辑。
     * @param target:MovieClip 要移动的目标对象。
     */
    public function updateMovement(target:MovieClip):Void {
        this.updateMovementDelegate(target);
    }

    /**
     * 静态方法构建实例。
     * @param _speedX:Number 子弹的 X 轴速度。
     * @param _speedY:Number 子弹的 Y 轴速度。
     * @param _zyRatio:Number ZY 比例，用于计算 Z 轴坐标。
     * @return LinearBulletMovement 实例。
     */
    public static function create(_speedX:Number, _speedY:Number, _zyRatio:Number):LinearBulletMovement {
        return new LinearBulletMovement(_speedX, _speedY, _zyRatio);
    }
}
