import org.flashNight.arki.bullet.BulletComponent.Movement.*;

class org.flashNight.arki.bullet.BulletComponent.Movement.LinearBulletMovement implements IMovement {
    private var 速度X:Number;
    private var 速度Y:Number;
    private var ZY比例:Number;
    private var 射程阈值:Number;

    // 动态绑定的方法
    private var updateMovementDelegate:Function;
    private var shouldDestroyDelegate:Function;

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

        // 根据参数设置最优的更新和销毁逻辑
        this.initializeDelegates();
    }

    /**
     * 初始化具体的逻辑函数。
     */
    private function initializeDelegates():Void {
        // 优化 updateMovement
        if (this.速度X == undefined && this.速度Y == undefined) {
            this.updateMovementDelegate = function(target:MovieClip):Void {
                target._x += target.xmov;
                target._y += target.ymov;
            };
        } else if (this.ZY比例 == undefined) {
            this.updateMovementDelegate = function(target:MovieClip):Void {
                target._x += this.速度X;
                target._y += this.速度Y;
            };
        } else {
            this.updateMovementDelegate = function(target:MovieClip):Void {
                target._x += this.速度X;
                target._y += this.速度Y;
                target.Z轴坐标 = target._y * this.ZY比例;
            };
        }

        // 优化 shouldDestroy
        if (this.射程阈值 == undefined) {
            this.shouldDestroyDelegate = function(target:MovieClip):Boolean {
                return false; // 永不销毁
            };
        } else {
            this.shouldDestroyDelegate = function(target:MovieClip):Boolean {
                var 发射者:MovieClip = _root.gameworld[target.发射者名];
                if (发射者 == undefined) return false;

                var isOutOfRange:Boolean = !target.远距离不消失 &&
                                           (Math.abs(target._x - 发射者._x) > this.射程阈值 ||
                                            Math.abs(target._y - 发射者._y) > this.射程阈值);

                // 地图碰撞检测
                var isCollidedWithMap:Boolean = false;
                var 游戏世界 = _root.gameworld;
                var Z轴坐标 = target.Z轴坐标;
                var 近战检测 = target.近战检测;

                if(target._x < _root.Xmin || target._x > _root.Xmax || Z轴坐标 < _root.Ymin || Z轴坐标 > _root.Ymax){
                    isCollidedWithMap = true;
                } else if(target._y > Z轴坐标 && !近战检测){
                    isCollidedWithMap = true;
                } else {
                    var 子弹地面坐标:Object = {x: target._x, y: Z轴坐标};
                    游戏世界.localToGlobal(子弹地面坐标);
                    if(游戏世界.地图.hitTest(子弹地面坐标.x, 子弹地面坐标.y, true)){
                        isCollidedWithMap = true;
                    }
                }

                if(isCollidedWithMap){
                    target.击中地图 = true;
                }

                return isOutOfRange || isCollidedWithMap;
            };
        }
    }

    /**
     * 更新运动逻辑。
     * @param target:MovieClip 要移动的目标对象。
     */
    public function updateMovement(target:MovieClip):Void {
        this.updateMovementDelegate(target);
    }

    /**
     * 检查对象是否需要被销毁或移除。
     * @param target:MovieClip 要检查的目标对象。
     * @return Boolean 是否需要销毁。
     */
    public function shouldDestroy(target:MovieClip):Boolean {
        return this.shouldDestroyDelegate(target);
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
