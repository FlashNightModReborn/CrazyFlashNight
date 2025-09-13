import org.flashNight.arki.component.Damage.*; 
import org.flashNight.arki.component.Collider.*;

/**
 * 命中上下文（零分配，固定字段集）
 * - 仅承载 handleHitCtx 所需数据；不做收尾/销毁/碰撞体回收
 * - 通过 reset()/fill(...) 循环复用，避免形状抖动与动态键
 */
class org.flashNight.arki.bullet.BulletComponent.Queue.HitContext {
    // 核心对象引用
    public var bullet:MovieClip;
    public var shooter:MovieClip;
    public var target:MovieClip;

    // 碰撞结果与重叠比例
    public var collisionResult:CollisionResult;
    public var overlapRatio:Number;

    // 预计算标志（由调用方传入，避免循环内重复判断）
    public var isNormalBullet:Boolean;  // 非近战非爆炸
    public var shouldStun:Boolean;      // 应该触发硬直（近战且不免疫硬直）
    public var isPierce:Boolean;

    public function HitContext() {
        reset();
    }

    /** 清空为初始状态（供环形池借出时调用） */
    public function reset():Void {
        bullet = null;
        shooter = null;
        target = null;
        collisionResult = null;
        overlapRatio = 0;
        isNormalBullet = false;
        shouldStun = false;
        isPierce = false;
    }

    /**
     * 填充上下文字段；返回 this 以便链式写法
     * 注意：flags 相关布尔已在外部预计算后传入，避免重复位运算
     */
    public function fill(
        b:MovieClip,
        s:MovieClip,
        t:MovieClip,
        cr:CollisionResult,
        ov:Number,
        normal:Boolean,
        stun:Boolean,        // 应该硬直（近战且不免疫）
        pierce:Boolean
    ):HitContext {
        bullet = b;
        shooter = s;
        target = t;
        collisionResult = cr;
        overlapRatio = ov;
        isNormalBullet = normal;
        shouldStun = stun;
        isPierce = pierce;
        return this;
    }

    /** （可选）调试用 */
    public function toString():String {
        return "[HitContext bullet=" + (bullet ? bullet._name : "null") +
               " target=" + (target ? target._name : "null") +
               " overlap=" + overlapRatio + "]";
    }
}
