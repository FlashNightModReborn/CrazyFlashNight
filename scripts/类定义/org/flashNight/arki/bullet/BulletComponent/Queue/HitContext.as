import org.flashNight.arki.component.Damage.*;
import org.flashNight.arki.component.Collider.*;

/**
 * 命中上下文（零分配，固定字段集）
 * - 仅承载 handleHitCtx 所需数据；不做收尾/销毁/碰撞体回收
 * - 通过 reset()/fill(...) 循环复用，避免形状抖动与动态键
 * - 使用位标志优化：减少多个布尔值的读写开销
 */
class org.flashNight.arki.bullet.BulletComponent.Queue.HitContext {
    // 位标志定义（公开给BulletQueueProcessor使用）
    public static var FLAG_SHOULD_STUN:Number = 1 << 0;  // 应该硬直
    public static var FLAG_IS_PIERCE:Number = 1 << 1;    // 穿透
    public static var FLAG_NORMAL_KILL:Number = 1 << 2;  // 普通击杀（kill事件），否则为death
    // 核心对象引用
    public var bullet:MovieClip;
    public var shooter:MovieClip;
    public var target:MovieClip;

    // 碰撞结果（包含overlapRatio）
    public var collisionResult:CollisionResult;

    // 预计算标志位（由调用方传入，避免循环内重复判断）
    public var flags:Number;  // 位标志：包含shouldStun、isPierce、deathEvent等

    public function HitContext() {
        reset();
    }

    /** 清空为初始状态（供环形池借出时调用） */
    public function reset():Void {
        bullet = null;
        shooter = null;
        target = null;
        collisionResult = null;
        flags = 0;  // 清空所有标志位
    }

    /**
     * 填充上下文字段；返回 this 以便链式写法
     * 注意：flags已在外部预计算并组合，避免重复位运算
     */
    public function fill(
        b:MovieClip,
        s:MovieClip,
        t:MovieClip,
        cr:CollisionResult,
        f:Number  // 预计算的位标志
    ):HitContext {
        bullet = b;
        shooter = s;
        target = t;
        collisionResult = cr;
        flags = f;
        return this;
    }

    /** （可选）调试用 */
    public function toString():String {
        return "[HitContext bullet=" + (bullet ? bullet._name : "null") +
               " target=" + (target ? target._name : "null") +
               " overlap=" + (collisionResult ? collisionResult.overlapRatio : 0) + "]";
    }
}
