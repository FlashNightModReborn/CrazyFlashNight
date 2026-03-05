// 文件路径：org.flashNight.arki.bullet.BulletComponent.Lifecycle.UnitBulletLifecycle.as

import org.flashNight.neur.Event.*;
import org.flashNight.arki.component.Collider.*;
import org.flashNight.arki.component.Damage.*;
import org.flashNight.arki.bullet.BulletComponent.Lifecycle.*;
import org.flashNight.arki.bullet.BulletComponent.Queue.*;
import org.flashNight.arki.bullet.BulletComponent.Collider.*;
import org.flashNight.arki.unit.UnitComponent.Initializer.*;
import org.flashNight.arki.unit.UnitComponent.Initializer.ElementComponent.*;
import org.flashNight.arki.unit.UnitComponent.Targetcache.*;

/**
 * UnitBulletLifecycle - 可拦截单位子弹生命周期管理器
 *
 * 继承自 NormalBulletLifecycle，使子弹同时具备单位属性，
 * 可被其他子弹命中并击毁（弹幕拦截玩法）。
 *
 * 初始化流程：
 * 1. super.bindLifecycle -> 子弹管线完全就绪（collider + damageManager + onEnterFrame + safeRemove）
 * 2. 设置 element 自引用 -> 使 HitEventComponent / KillEventComponent 走地图元件分支
 * 3. BasicAttributeInitializer.initializeWithoutPosition -> hp/防御力/击中效果等，Z轴坐标不被覆写
 * 3.5. 恢复发射者阵营 -> 跟随发射者而非 HOSTILE_NEUTRAL，自碰撞自然消除
 * 3.6. 设置 NPC=true -> DamageCalculator 短路（不做完整伤害计算），hit 事件仍正常触发
 * 3.7. 补 unitAIType -> initializeWithoutPosition 跳过了 initializePositionAndAI
 * 4. 覆盖 hitPoint / zTolerance -> 使用 XML 配置值
 * 5. StaticInitializer.initializeUnit -> 注册到单位管线（TargetCache + EventInitializer）
 * 5.5. 撤销 UpdateWheel 注册 -> EventInitializer 的 UpdateEventComponent 会做 swapDepths，对子弹无意义
 * 6. subscribeSingle 覆盖事件 -> 定制 hit/kill/death/UpdateEventComponent 处理器
 * 7. 恢复子弹帧状态 -> 撤销 BasicAttributeInitializer 的 gotoAndStop("正常")
 */
class org.flashNight.arki.bullet.BulletComponent.Lifecycle.UnitBulletLifecycle
    extends NormalBulletLifecycle implements ILifecycle {

    /** 静态实例 - 默认可拦截子弹生命周期管理器 */
    public static var BASIC:UnitBulletLifecycle = new UnitBulletLifecycle(900);

    /**
     * 构造函数
     * @param rangeThreshold:Number 子弹的最大有效射程（像素）
     */
    public function UnitBulletLifecycle(rangeThreshold:Number) {
        super(rangeThreshold);
    }

    /**
     * 子弹销毁判定逻辑（重写）
     * 恢复 Z轴坐标 语义的地面碰撞判定，对齐 NormalBulletLifecycle.checkMapCollision。
     * 前提：Z轴坐标 由 BulletInitializer 设置为 shootZ，不再被 BasicAttributeInitializer 覆写。
     *
     * @param target:MovieClip 要检测的子弹对象
     * @return Boolean 是否需要销毁子弹
     */
    public function shouldDestroy(target:MovieClip):Boolean {
        #include "../macros/STATE_LONG_RANGE.as"
        #include "../macros/STATE_HIT_MAP.as"

        var shooter:MovieClip = _root.gameworld[target.发射者名];
        var sf:Number = target.stateFlags | 0;

        if (!shooter) {
            shooter = TargetCacheManager.findHero();
            if (!shooter) {
                // 无发射者也无主角：直接做地面碰撞检测
                var Z0:Number = target.Z轴坐标;
                var hitOnly:Boolean = (target._y > Z0)
                    ? true
                    : _root.collisionLayer.hitTest(target._x, Z0, true);
                if (hitOnly) target.stateFlags |= STATE_HIT_MAP;
                return hitOnly;
            }
        }

        var isLongRange:Boolean = (sf & STATE_LONG_RANGE) != 0;
        var dx:Number = target.shootX - target._x;
        var dy:Number = target.shootY - target._y;

        if (!isLongRange &&
            ((dx > rangeThreshold ^ dx < -rangeThreshold) |
            (dy > rangeThreshold ^ dy < -rangeThreshold))) {
            return true;
        }

        // 地面碰撞：用 Z轴坐标（即 shootZ，未被 BasicAttributeInitializer 覆写）
        // 语义与 NormalBulletLifecycle.checkMapCollision 一致
        var Z:Number = target.Z轴坐标;
        var isCollidedWithMap:Boolean = (target._y > Z)
            ? true
            : _root.collisionLayer.hitTest(target._x, Z, true);
        if (isCollidedWithMap) target.stateFlags |= STATE_HIT_MAP;
        return isCollidedWithMap;
    }

    /**
     * 绑定可拦截单位子弹的生命周期逻辑
     * 7步初始化流程，融合子弹管线和单位管线
     *
     * @param target:MovieClip 要绑定的子弹对象
     */
    public function bindLifecycle(target:MovieClip):Void {
        // === 步骤1：完成子弹管线初始化 ===
        // ChainDetector -> collider -> damageManager -> onEnterFrame -> safeRemove（将在步骤后重写）
        super.bindLifecycle(target);

        // === 步骤2：设置 element 自引用 ===
        // 使 HitEventComponent / KillEventComponent 走地图元件分支
        target.element = target;

        // === 步骤3：初始化地图元件基础属性（不覆写 Z轴坐标）===
        // 使用 initializeWithoutPosition 替代 initialize，保留 BulletInitializer 设置的 shootZ
        BasicAttributeInitializer.initializeWithoutPosition(target);

        // === 步骤3.5：恢复发射者阵营 ===
        // 跟随发射者的阵营：
        // 1. 阵营缓存路由正确（敌方 UnitBullet 在 ENEMY 桶，玩家子弹可命中）
        // 2. 自碰撞自然消除（同阵营子弹不检测同阵营单位）
        var shooter:MovieClip = _root.gameworld[target.发射者名];
        if (shooter) {
            target.是否为敌人 = shooter.是否为敌人;
        }

        // === 步骤3.6：设置 NPC=true ===
        // DamageCalculator:99 的 hitTarget.NPC 守卫短路，跳过完整伤害计算
        // 好处：hp=9999999 + 防御力=99999 的空转计算不再执行
        // hit 事件（BulletQueueProcessor:2255）仍正常 publish，onHit 的 hitPoint-- 照常触发
        target.NPC = true;

        // === 步骤3.7：补 unitAIType ===
        // initializeWithoutPosition 跳过了 initializePositionAndAI，需手动补充
        target.unitAIType = "None";

        // === 步骤4：覆盖 hitPoint 和 zTolerance 为 XML 配置值 ===
        var config:Object = target.unitBulletConfig;
        if (config) {
            target.hitPoint = config.hitPoint;
            target.hitPointMax = config.hitPoint;
            target.击中效果 = config.hitEffect;
            // zTolerance：额外 zOffset 容忍值，用于宽容拦截判定（BulletQueueProcessor 读取）
            target.unitBulletZTolerance = config.zTolerance || 0;
        }

        // === 步骤5：注册到单位管线 ===
        // ComponentInitializer 跳过 aabbCollider 创建（已存在）
        // EventInitializer 订阅 element 分支默认处理器
        // TargetCacheManager.addUnit 注册到目标缓存
        StaticInitializer.initializeUnit(target);

        // === 步骤5.5：撤销 UpdateWheel 注册 ===
        // EventInitializer 的 UpdateEventComponent 把 UnitBullet 注册到 unitUpdateWheel
        // 会触发 swapDepths（深度排序），干扰子弹渲染；UnitBullet 深度由 gameworld 层级自然管理
        _root.帧计时器.unitUpdateWheel.remove(target);

        // === 步骤6：用 subscribeSingle 覆盖需要定制的事件处理器 ===
        var d:EventDispatcher = target.dispatcher;
        d.subscribeSingle("hit", UnitBulletLifecycle.onHit, target);
        d.subscribeSingle("kill", UnitBulletLifecycle.onKill, target);
        d.subscribeSingle("death", UnitBulletLifecycle.onDeath, target);
        d.subscribeSingle("UpdateEventComponent", UnitBulletLifecycle.onUpdate, target);

        // === 步骤7：恢复子弹帧状态 ===
        // BasicAttributeInitializer.initializeDisplayState 调用了 gotoAndStop("正常")
        // 需要恢复到第1帧并播放飞行动画
        target.gotoAndStop(1);
        target.play();

        // === 诊断日志（调试完成后注释） ===
        // var aabb = target.aabbCollider;
        // _root.服务器.发布服务器消息("[UB Init] " + target._name
        //     + " area=" + (target.area != undefined)
        //     + " 是否为敌人=" + target.是否为敌人
        //     + " hp=" + target.hp
        //     + " hitPoint=" + target.hitPoint
        //     + " Z=" + target.Z轴坐标
        //     + " _y=" + target._y
        //     + " zTolerance=" + target.unitBulletZTolerance
        //     + " NPC=" + target.NPC
        //     + " AABB=[" + aabb.left + "," + aabb.right + "," + aabb.top + "," + aabb.bottom + "]"
        // );
    }

    /**
     * 重写安全销毁机制
     * 在父类碰撞器回收之外，追加单位侧清理
     *
     * @param target 要绑定的子弹对象
     */
    public function bindSafeRemove(target):Void {
        var originalRemove:Function = target.removeMovieClip;
        target.removeMovieClip = function():Void {
            // 1. 单位侧清理
            TargetCacheManager.removeUnit(this);
            if (this.dispatcher) {
                this.dispatcher.destroy();
            }
            this.element = null;          // 断开自引用
            this._deInitialized = true;   // 阻止 StaticDeinitializer 重复清理

            // 2. 碰撞器回收（与父类逻辑一致）
            var aabb = this.aabbCollider;
            if (aabb) {
                aabb.getFactory().releaseCollider(aabb);
                this.aabbCollider = null;
            }
            var poly = this.polygonCollider;
            if (poly) {
                poly.getFactory().releaseCollider(poly);
                this.polygonCollider = null;
            }

            // 3. 原始 MovieClip 销毁
            originalRemove.call(this);
        };
    }

    // ==================== 事件处理函数 ====================

    /**
     * 受击事件处理
     * DamageCalculator 因 NPC=true 已短路返回 NULL，hp 不变。
     * 只递减 hitPoint 做拦截判定。
     * hitPoint 归零时：设 hp=0 并 publish kill，让 BulletQueueProcessor 的死亡判定
     * 检测到 _killed=true（onKill 设置）后跳过重复 kill/death publish。
     */
    public static function onHit(target:MovieClip, shooter:MovieClip, bullet:MovieClip):Void {
        // _root.服务器.发布服务器消息("[UB Hit] " + target._name + " hitPoint=" + target.hitPoint + " by=" + bullet._name);
        target.hitPoint--;
        if (target.hitPoint <= 0) {
            target.hp = 0;  // 手动归零，使 BulletQueueProcessor line 2258 的死亡判定可见
            target.dispatcher.publish("kill", target);
        }
    }

    /**
     * 击杀事件处理
     * 跳到"消失"帧播放消失/爆炸动画
     * _killed=true 用作 BulletQueueProcessor 死亡判定的重复发布守卫
     */
    public static function onKill(target:MovieClip):Void {
        target.gotoAndPlay("消失");
        target._killed = true;
        if (target.垂直速度 < 0) target.垂直速度 = 0;
        target.dispatcher.publish("death", target);
    }

    /**
     * 死亡事件处理
     * 仅从 TargetCache 移除，不做经验值/死亡检测等单位逻辑
     */
    public static function onDeath(target:MovieClip):Void {
        TargetCacheManager.removeUnit(target);
    }

    /**
     * 帧更新事件处理
     * 空操作：不做 swapDepths（UpdateWheel 已撤销），不做渲染剔除
     * Z 轴由 Movement 维护，深度由 gameworld 层级自然管理
     */
    public static function onUpdate(target:MovieClip):Void {
        // 诊断（调试完成后注释）
        // if ((_root.帧计时器.当前帧数 % 30) == 0) {
        //     var aabb = target.aabbCollider;
        //     _root.服务器.发布服务器消息("[UB Update] " + target._name
        //         + " _x=" + Math.round(target._x)
        //         + " _y=" + Math.round(target._y)
        //         + " Z=" + Math.round(target.Z轴坐标)
        //         + " hp=" + target.hp
        //         + " hitPoint=" + target.hitPoint
        //         + " _cur=" + target._currentframe
        //     );
        // }
    }
}
