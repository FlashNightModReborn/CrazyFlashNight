import org.flashNight.arki.bullet.BulletComponent.Collider.*;
import org.flashNight.arki.component.Collider.*;
import org.flashNight.sara.util.*;

class org.flashNight.arki.bullet.BulletComponent.Collider.BulletColliderHandler {
    private var bullet:Object; // 当前子弹对象
    private var filterMethod:Function; // 前置过滤方法
    private var collisionMethod:Function; // 碰撞检测方法

    /**
     * 构造函数
     * @param bullet 当前子弹对象
     * @param filterMethod 前置过滤方法
     * @param collisionMethod 碰撞检测方法
     */
    public function BulletColliderHandler(bullet:Object, filterMethod:Function, collisionMethod:Function) {
        this.bullet = bullet;
        this.filterMethod = filterMethod;
        this.collisionMethod = collisionMethod;
    }

    /**
     * 执行前置过滤逻辑
     * @param target 当前目标对象
     * @return Boolean 是否通过过滤
     */
    public function applyFilter(target:Object):Boolean {
        return this.filterMethod(target, this.bullet);
    }

    /**
     * 执行碰撞检测逻辑
     * @param target 当前目标对象
     * @param zOffset Z轴偏移值
     * @return CollisionResult 碰撞检测结果
     */
    public function applyCollision(target:Object, zOffset:Number):CollisionResult {
        return this.collisionMethod(target, this.bullet, zOffset);
    }

    /**
     * 默认前置过滤逻辑
     * @param target 当前目标对象
     * @param bullet 当前子弹对象
     * @return Boolean 是否通过过滤
     */
    public static function defaultFilterMethod(target:Object, bullet:Object):Boolean {
        var zOffset:Number = target.Z轴坐标 - bullet.Z轴坐标;
        if (Math.abs(zOffset) >= bullet.Z轴攻击范围) {
            return false;
        }
        if (!(target.是否为敌人 == bullet.子弹敌我属性值)) {
            return false;
        }
        if ((target._name != bullet.发射者名 || bullet.友军伤害) && target.防止无限飞 != true || (target.hp <= 0 && !bullet.近战检测)) {
            return false;
        }
        return true;
    }

    /**
     * 默认碰撞检测逻辑
     * @param target 当前目标对象
     * @param bullet 当前子弹对象
     * @param zOffset Z轴偏移值
     * @return CollisionResult 碰撞检测结果
     */
    public static function defaultCollisionMethod(target:MovieClip, bullet:MovieClip, zOffset:Number):CollisionResult {
        var areaAABB:AABBCollider = bullet.aabbCollider;
        areaAABB.updateFromBullet(bullet, bullet.area);

        var unitArea:AABBCollider = target.aabbCollider;
        unitArea.updateFromUnitArea(target);

        var result:CollisionResult = areaAABB.checkCollision(unitArea, zOffset);

        if (!result.isColliding && bullet.联弹检测 && bullet._rotation != 0 && bullet._rotation != 180) {
            bullet.polygonCollider.updateFromBullet(bullet, bullet.area);
            result = bullet.polygonCollider.checkCollision(unitArea, zOffset);
        }

        return result;
    }
}
