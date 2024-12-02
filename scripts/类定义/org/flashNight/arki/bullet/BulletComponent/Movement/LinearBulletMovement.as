// 文件路径：org.flashNight.arki.bullet.BulletComponent.Movement.LinearBulletMovement.as

import org.flashNight.arki.bullet.BulletComponent.Movement.IMovement;

class org.flashNight.arki.bullet.BulletComponent.Movement.LinearBulletMovement implements IMovement {
    private var 速度X:Number;
    private var 速度Y:Number;
    private var ZY比例:Number;

    // 动态绑定的方法
    private var updateMovementDelegate:Function;

    /**
     * 构造函数
     * @param 速度X:Number 子弹的 X 轴速度。
     * @param 速度Y:Number 子弹的 Y 轴速度。
     * @param ZY比例:Number ZY 比例，用于计算 Z 轴坐标。
     */
    public function LinearBulletMovement(速度X:Number, 速度Y:Number, ZY比例:Number) {
        this.速度X = 速度X;
        this.速度Y = 速度Y;
        this.ZY比例 = ZY比例;

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
        if (this.速度X == undefined && this.速度Y == undefined) {
            return this.updateWithDefaultMovement;
        } else if (this.ZY比例 == undefined) {
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
        target._x += this.速度X;
        target._y += this.速度Y;
    }

    /**
     * 更新运动逻辑 - 完整更新包括 Z 坐标。
     * @param target:MovieClip 目标对象。
     */
    private function updateWithFullMovement(target:MovieClip):Void {
        target._x += this.速度X;
        target._y += this.速度Y;
        target.Z轴坐标 = target._y * this.ZY比例;
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
     * @param 速度X:Number 子弹的 X 轴速度。
     * @param 速度Y:Number 子弹的 Y 轴速度。
     * @param ZY比例:Number ZY 比例，用于计算 Z 轴坐标。
     * @return LinearBulletMovement 实例。
     */
    public static function create(速度X:Number, 速度Y:Number, ZY比例:Number):LinearBulletMovement {
        return new LinearBulletMovement(速度X, 速度Y, ZY比例);
    }
}
