// 文件路径：org.flashNight.arki.bullet.BulletComponent.Lifecycle.ChainObjectLifecycle.as

import org.flashNight.neur.Event.*;
import org.flashNight.arki.component.Collider.*;
import org.flashNight.arki.component.Damage.*;
import org.flashNight.arki.bullet.BulletComponent.Lifecycle.*;
import org.flashNight.arki.bullet.BulletComponent.Collider.*;
import org.flashNight.arki.bullet.BulletComponent.Chain.*;
import org.flashNight.arki.unit.UnitComponent.Targetcache.*;

/**
 * 对象化联弹生命周期管理器（P3 去影片剪辑化）
 *
 * 继承 NormalBulletLifecycle（射程判定 / 地图碰撞检测对纯对象字段直接可用），
 * 仅替换三处 MC 依赖：
 * • bindCollider：无 area 子剪辑，经工厂扩展方法 createFromChainObject
 *   从联弹组本地碰撞盒 + 子弹仿射矩阵推导（工厂仍由 ChainDetector 按旋转角选择）
 * • bindFrameHandler：纯对象无帧事件，由 ChainUnitManager.tick 统一泵入碰撞队列
 * • bindSafeRemove：对象式销毁（回收碰撞器 + 回收单元体组 + 死亡标记），
 *   并安装 gotoAndPlay/gotoAndStop/stop 垫片复刻 MC 消失帧语义
 *   （BulletQueueProcessor 单出口的 gotoAndPlay("消失") 对两种形态统一生效）
 */
class org.flashNight.arki.bullet.BulletComponent.Lifecycle.ChainObjectLifecycle extends NormalBulletLifecycle implements ILifecycle {

    /** 静态实例 - 默认射程900像素的对象化联弹生命周期管理器 */
    public static var BASIC:ChainObjectLifecycle = new ChainObjectLifecycle(900);

    /**
     * 构造函数
     * @param rangeThreshold:Number 子弹的最大有效射程（像素）
     */
    public function ChainObjectLifecycle(rangeThreshold:Number) {
        super(rangeThreshold);
    }

    /**
     * 绑定碰撞检测器（对象化联弹专用）
     * factory 为 ChainDetector 选择的 AABB / CoverageAABB 工厂，
     * 两者均已提供 createFromChainObject 扩展方法（不在 IColliderFactory 接口内，经无类型调用分发）。
     *
     * @param target:MovieClip 对象化联弹（运行时为纯 Object）
     * @param factory:IColliderFactory 碰撞检测器工厂
     */
    public function bindCollider(target:MovieClip, factory:IColliderFactory):Void {
        var f = factory;
        target.aabbCollider = f.createFromChainObject(target);
    }

    /**
     * 帧处理器绑定：故意空实现。
     * 对象化联弹的边界标记 / AABB 更新 / 入队由 ChainUnitManager.tick 统一驱动。
     *
     * @param target:MovieClip 对象化联弹
     */
    public function bindFrameHandler(target:MovieClip):Void {
        // 纯对象无 onEnterFrame，统一泵见 ChainUnitManager.tick
    }

    /**
     * 安全销毁 + 帧标签垫片
     *
     * @param target 对象化联弹
     */
    public function bindSafeRemove(target):Void {
        // === 对象式销毁：回收碰撞器 → 回收单元体组 → 置死亡标记 ===
        target.removeMovieClip = function():Void {
            var aabb:AABBCollider = this.aabbCollider;
            if (aabb) {
                aabb.getFactory().releaseCollider(aabb);
                this.aabbCollider = null;
            }
            var poly = this.polygonCollider;
            if (poly) {
                poly.getFactory().releaseCollider(poly);
                this.polygonCollider = null;
            }
            ChainUnitManager.removeGroupByBullet(this);
            this.__chainDead = true;
        };

        // === 帧标签垫片：复刻 MC 消失帧语义 ===
        // 队列单出口（VANISH/击中地图）调用 gotoAndPlay("消失") → 分发到对象联弹消失
        target.gotoAndPlay = function(label):Void {
            _root.联弹系统.对象联弹消失(this);
        };
        target.gotoAndStop = target.gotoAndPlay;
        target.stop = function():Void {
        };
    }
}