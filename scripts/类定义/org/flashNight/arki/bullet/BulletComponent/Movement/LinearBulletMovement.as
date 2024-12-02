import org.flashNight.arki.bullet.BulletComponent.Movement.*;

class org.flashNight.arki.bullet.BulletComponent.Movement.LinearBulletMovement implements IMovement {
    private var 速度X:Number;
    private var 速度Y:Number;
    private var ZY比例:Number;
    private var 射程阈值:Number;

    /**
     * 构造函数
     * @param 速度X:Number 子弹的 X 轴速度。
     * @param 速度Y:Number 子弹的 Y 轴速度。
     * @param ZY比例:Number ZY 比例，用于计算 Z 轴坐标。
     * @param 射程阈值:Number 子弹超出射程的距离阈值。
     */
    public function LinearBulletMovement(速度X:Number, 速度Y:Number, ZY比例:Number, 射程阈值:Number) {
        this.速度X = 速度X;
        this.速度Y = 速度Y;
        this.ZY比例 = ZY比例;
        this.射程阈值 = 射程阈值;
    }

    /**
     * 更新运动逻辑。
     * @param target:MovieClip 要移动的目标对象。
     */
    public function updateMovement(target:MovieClip):Void {
        // 更新子弹位置
        if (this.速度X != undefined && this.速度Y != undefined && this.ZY比例 != undefined) {
            target._x += this.速度X;
            target._y += this.速度Y;
            target.Z轴坐标 = target._y * this.ZY比例; // 更新 Z 轴坐标
        } else {
            target._x += target.xmov; // 兼容性逻辑，处理旧变量
            target._y += target.ymov;
        }
    }

    /**
     * 检查对象是否需要被销毁或移除。
     * @param target:MovieClip 要检查的目标对象。
     * @return Boolean 是否需要销毁。
     */
    public function shouldDestroy(target:MovieClip):Boolean {
        // 判断子弹是否超出射程范围
        var 发射者:MovieClip = _root.gameworld[target.发射者名];
        if (发射者 == undefined || this.射程阈值 == undefined) {
            return false;
        }

        return !target.远距离不消失 &&
               (Math.abs(target._x - 发射者._x) > this.射程阈值 ||
                Math.abs(target._y - 发射者._y) > this.射程阈值);
    }

    /**
     * 静态方法构建实例。
     * @param 速度X:Number 子弹的 X 轴速度。
     * @param 速度Y:Number 子弹的 Y 轴速度。
     * @param ZY比例:Number ZY 比例，用于计算 Z 轴坐标。
     * @param 射程阈值:Number 子弹超出射程的距离阈值。
     * @return LinearBulletMovement 实例。
     */
    public static function create(速度X:Number, 速度Y:Number, ZY比例:Number, 射程阈值:Number):LinearBulletMovement {
        return new LinearBulletMovement(速度X, 速度Y, ZY比例, 射程阈值);
    }
}
