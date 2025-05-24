// 文件路径：org.flashNight.arki.bullet.BulletComponent.Movement.LinearBulletMovement.as

import org.flashNight.arki.bullet.BulletComponent.Movement.IMovement;

class org.flashNight.arki.bullet.BulletComponent.Movement.LinearBulletMovement implements IMovement {
    private var _speedX:Number;
    private var _speedY:Number;
    private var _zyRatio:Number;

    private static var BASIC:LinearBulletMovement = new LinearBulletMovement(null, null, null);

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
        this.updateMovement = this.getUpdateMovementFunction();
    }

    /**
     * 根据参数选择更新逻辑。
     * @return Function 更新逻辑函数。
     */
    private function getUpdateMovementFunction():Function {
        var _speedX:Number = this._speedX;
        var _speedY:Number = this._speedY;

        var isBasicCase:Boolean = 
            !isFinite(_speedX + _speedY) &&  // 捕获 NaN/undefined/null 等非有效数值
            (_speedX == null) &&             // 显式排除 0 值
            (_speedY == null);               // 显式排除 0 值
        if (isBasicCase) {
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
        target._x += target.xmov;
        target._y += target.ymov;
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
     * 运行时会被动态替换
     * @param target:MovieClip 要移动的目标对象。
     */
    public function updateMovement(target:MovieClip):Void {
        
    }

    /**
     * 静态方法构建实例。
     * @param _speedX:Number 子弹的 X 轴速度。
     * @param _speedY:Number 子弹的 Y 轴速度。
     * @param _zyRatio:Number ZY 比例，用于计算 Z 轴坐标。
     * @return LinearBulletMovement 实例。
     */
    public static function create(_speedX:Number, _speedY:Number, _zyRatio:Number):LinearBulletMovement {
        // 利用类型转换特性进行智能判断
        /*
        var isBasicCase:Boolean = 
            !isFinite(_speedX + _speedY) &&  // 捕获 NaN/undefined/null 等非有效数值
            (_speedX == null) &&             // 显式排除 0 值
            (_speedY == null);               // 显式排除 0 值

        _root.发布消息(isBasicCase)
        
        return isBasicCase ? LinearBulletMovement.BASIC : new LinearBulletMovement(
            _speedX, _speedY, _zyRatio
        );
        */

        return new LinearBulletMovement(
            _speedX, _speedY, _zyRatio
        );
    }
}
