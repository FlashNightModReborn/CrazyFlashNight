// 文件路径：org.flashNight.arki.bullet.BulletComponent.Lifecycle.NormalBulletLifecycle.as
import org.flashNight.arki.bullet.BulletComponent.Lifecycle.TransparentBulletLifecycle;
import org.flashNight.arki.bullet.BulletComponent.Collider.*;
import org.flashNight.arki.component.Collider.*;

class org.flashNight.arki.bullet.BulletComponent.Lifecycle.NormalBulletLifecycle extends TransparentBulletLifecycle {
    private var 射程阈值:Number;
    
    public function NormalBulletLifecycle(射程阈值:Number) {
        super();
        this.射程阈值 = 射程阈值;
    }

    override public function shouldDestroy(target:MovieClip):Boolean {
        // 射程检测逻辑
        var 发射者:MovieClip = _root.gameworld[target.发射者名];
        if (发射者 == undefined) return false;

        var targetX:Number = target._x;
        var targetY:Number = target._y;
        var 发射者X:Number = 发射者._x;
        var 发射者Y:Number = 发射者._y;

        var isOutOfRange:Boolean = !target.远距离不消失 &&
                                  (Math.abs(targetX - 发射者X) > this.射程阈值 ||
                                   Math.abs(targetY - 发射者Y) > this.射程阈值);

        // 地面碰撞检测
        var isCollided:Boolean = checkMapCollision(target);
        if (isCollided) target.击中地图 = true;

        return isOutOfRange || isCollided;
    }

    override public function bindLifecycle(target:MovieClip):Void {
        // 先执行父类的基础绑定
        super.bindLifecycle(target);
        target.onEnterFrame = _root.子弹生命周期;
    }

    private function checkMapCollision(target:MovieClip):Boolean {
        // 复用BulletLifecycle的碰撞检测逻辑
        var 游戏世界:Object = _root.gameworld;
        var Z轴坐标:Number = target.Z轴坐标;
        var 近战检测:Boolean = target.近战检测;

        var Xmin:Number = _root.Xmin;
        var Xmax:Number = _root.Xmax;
        var Ymin:Number = _root.Ymin;
        var Ymax:Number = _root.Ymax;

        var targetX:Number = target._x;
        var targetY:Number = target._y;

        if (targetX < Xmin || targetX > Xmax || Z轴坐标 < Ymin || Z轴坐标 > Ymax) {
            return true;
        } else if (targetY > Z轴坐标 && !近战检测) {
            return true;
        } else {
            var 子弹地面坐标:Object = {x: targetX, y: Z轴坐标};
            游戏世界.localToGlobal(子弹地面坐标);
            return 游戏世界.地图.hitTest(子弹地面坐标.x, 子弹地面坐标.y, true);
        }
    }
}
