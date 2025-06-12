import org.flashNight.neur.Event.*;
import org.flashNight.arki.component.Collider.*;
import org.flashNight.arki.component.Damage.*;
import org.flashNight.sara.util.*;
import org.flashNight.arki.bullet.BulletComponent.Lifecycle.*;

/**
 * 近战子弹生命周期管理器
 * 在 NormalBulletLifecycle 基础上扩展，专门处理近战检测逻辑
 */
class org.flashNight.arki.bullet.BulletComponent.Lifecycle.MeleeBulletLifecycle extends NormalBulletLifecycle implements ILifecycle {
    
    /** 静态实例 - 默认射程900像素的近战子弹生命周期管理器 */
    public static var BASIC:MeleeBulletLifecycle = new MeleeBulletLifecycle(900);
    
    /**
     * 构造函数
     * @param rangeThreshold:Number 子弹的最大有效射程（像素）
     */
    public function MeleeBulletLifecycle(rangeThreshold:Number) {
        super(rangeThreshold);
    }
    
    /**
     * 重写地图碰撞检测实现，加入近战检测逻辑
     * 检测流程：
     *   1. 地图边界检测
     *   2. 对非近战子弹进行额外的Y轴检测（target._y > target.Z轴坐标时判定为碰撞）
     *   3. 像素级精确碰撞检测
     * 
     * @param target:MovieClip 要检测的子弹对象
     * @return Boolean 是否发生地图碰撞
     */
    private function checkMapCollision(target:MovieClip):Boolean {
        var gameWorld:Object = _root.gameworld;
        var Z轴坐标:Number = target.Z轴坐标;
        var 近战检测:Boolean = target.近战检测;
        
        // 地图边界检测
        var Xmin:Number = _root.Xmin;
        var Xmax:Number = _root.Xmax;
        var Ymin:Number = _root.Ymin;
        var Ymax:Number = _root.Ymax;
        
        var targetX:Number = target._x;
        var targetY:Number = target._y;
        
        // 快速边界检测（优化性能）
        if (targetX < Xmin || targetX > Xmax || Z轴坐标 < Ymin || Z轴坐标 > Ymax) {
            return true;
        }
        // 近战检测逻辑：对于非近战子弹，若Y轴位置超过Z轴坐标则判定为碰撞
        else if (targetY > Z轴坐标 && !近战检测) {
            return true;
        }
        // 精确碰撞检测（像素级判断）
        else {
            return _root.collisionLayer.hitTest(targetX, Z轴坐标, true);
        }
    }
    
    /**
     * 重写子弹销毁判定逻辑，使用新实现的地图碰撞检测方法
     * 
     * @param target:MovieClip 要检测的子弹对象
     * @return Boolean 是否需要销毁子弹
     */
    public function shouldDestroy(target:MovieClip):Boolean {
        return super.shouldDestroy(target);
    }
    
    /**
     * 绑定子弹生命周期逻辑，与父类实现一致
     * 
     * @param target:MovieClip 要绑定的子弹对象
     */
    public function bindLifecycle(target:MovieClip):Void {
        super.bindLifecycle(target);
    }
}
