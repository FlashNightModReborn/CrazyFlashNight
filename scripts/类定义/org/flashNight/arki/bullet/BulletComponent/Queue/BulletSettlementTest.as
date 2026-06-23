import org.flashNight.arki.bullet.BulletComponent.Queue.BulletQueueProcessor;

/**
 * BulletSettlementTest —— settleHit / settleRayHit 结算路径的确定性 trace 套件
 * （子弹命中-伤害双管线拆分 Gate-a）。
 *
 * 用手工 mock 的 ctx + hitTarget 直接驱动 settleHit / settleRayHit，
 * 各 mock 把每步副作用 trace 成定长行，供改前/改后逐行 diff（tools/trace-diff）。
 * 零外部依赖（不需 _root.gameworld / TargetCacheManager / 真实 DamageCalculator）。
 *
 * 注：settleHit / settleRayHit 为 private static —— 经 Object 类型引用绕过编译期私有检查
 *     （AVM1 运行期不强制 private），故下方用 var BQP:Object = BulletQueueProcessor 调用。
 *
 * 用例 C/G（hp<=0 且 _killed=true）专门暴露 D1 _killed 守卫：
 *   - settleHit 有守卫 → 不重复 publish kill/enemyKilled；
 *   - 阶段2 前的 settleRayHit 无守卫 → 仍 publish（基线）；阶段2 后委托 settleHit → 被抑制。
 *   故 G 是改前/改后唯一应出现差异的行，其余用例必须逐行一致。
 */
class org.flashNight.arki.bullet.BulletComponent.Queue.BulletSettlementTest {

    public static function runTests():Void {
        trace("=== BulletSettlementTest start ===");
        // 共享核心 settleHit（caller 已算好 dodgeState；不内算闪避 / 不调触发 / 不做 FX）
        caseSettleHit("A settleHit survive",           100, false, 0,     1);
        caseSettleHit("B settleHit kill killed=false",  0,   false, 0,     1);
        caseSettleHit("C settleHit kill killed=true",   0,   true,  0,     1);
        caseSettleHit("D settleHit melee->death",       0,   false, 768,   2);
        // 射线适配器 settleRayHit（内部算 dodge + FX）
        caseSettleRay("E settleRayHit survive",           100, false, 0,   1);
        caseSettleRay("F settleRayHit kill killed=false", 0,   false, 0,   1);
        caseSettleRay("G settleRayHit kill killed=true",  0,   true,  0,   1);
        caseSettleRay("H settleRayHit melee->death",      0,   false, 768, 2);
        // injectHit 合法性兜底（拒绝路径，不进 settleHit；valid 路径用真 DamageCalculator，靠消费者真机验）
        caseInjectReject("I injectHit reject self",     true,  100, false);
        caseInjectReject("J injectHit reject dead",     false, 0,   false);
        caseInjectReject("K injectHit reject blockFly", false, 100, true);
        trace("=== BulletSettlementTest end ===");
    }

    private static function makeDispatcher(tag:String):Object {
        var d:Object = {};
        d.publish = function():Void {
            var t:String = (arguments[1] != undefined) ? arguments[1]._name : "-";
            trace("  [pub:" + tag + "] " + arguments[0] + " t=" + t);
        };
        return d;
    }

    private static function makeBullet():Object {
        var b:Object = {};
        b.hitCount = 0;
        b.伤害类型 = "物伤";
        b.命中率 = 100;
        b.shouldGeneratePostHitEffect = true;
        b.击中后子弹的效果 = "fx";
        return b;
    }

    private static function makeTarget(hp:Number, killed:Boolean):Object {
        var t:Object = {};
        t.hp = hp;
        t._x = 11; t._y = 22; t._name = "MockEnemy";
        t._killed = killed;
        t.Z轴坐标 = 0;
        t.dispatcher = makeDispatcher("tgt");
        return t;
    }

    private static function makeCtx(bullet:Object, flags:Number, scatter:Number):Object {
        var shooter:Object = {};
        shooter._x = 0; shooter._y = 0; shooter._xscale = 100;
        shooter.dispatcher = makeDispatcher("sht");

        var dodge:Object = {};
        dodge.calcDodgeResult = function(s, t, rate):Number { return 0; };
        dodge.calculateDodgeState = function(t, r, b):String {
            trace("  [dodge] (settleRayHit 内部算)");
            return "未躲闪";
        };

        var damage:Object = {};
        damage.calculateDamage = function(b, s, t, mult, ds):Object {
            trace("  [damage] mult=" + mult + " dodge=" + ds);
            var r:Object = {};
            r.actualScatterUsed = scatter;
            r.triggerDisplay = function(x, y, name):Void {
                trace("  [display] name=" + name + " x=" + x + " y=" + y);
            };
            return r;
        };

        var fx:Object = {};
        fx.Effect = function(eff, x, y, scale):Void {
            trace("  [fx] x=" + x + " y=" + y);
        };

        var result:Object = {};
        result.overlapCenter = {};
        result.overlapCenter.x = 0; result.overlapCenter.y = 0;
        result.overlapRatio = 0; result.tEntry = 0;

        var ctx:Object = {};
        ctx.bullet = bullet;
        ctx.shooter = shooter;
        ctx.result = result;
        ctx.flags = flags;
        ctx.meleeMask = 768; // FLAG_MELEE | FLAG_EXPLOSIVE
        ctx.Dodge = dodge;
        ctx.Damage = damage;
        ctx.FX = fx;
        return ctx;
    }

    private static function caseSettleHit(label:String, hp:Number, killed:Boolean, flags:Number, scatter:Number):Void {
        trace("-- " + label + " --");
        var bullet:Object = makeBullet();
        var ctx:Object = makeCtx(bullet, flags, scatter);
        var tgt:Object = makeTarget(hp, killed);
        var cr:Object = ctx.result;
        cr.overlapCenter.x = 11; cr.overlapCenter.y = 22;
        var BQP:Object = BulletQueueProcessor;
        BQP.settleHit(ctx, tgt, cr, 1, "未躲闪");
        trace("  => hitCount=" + bullet.hitCount);
    }

    private static function caseSettleRay(label:String, hp:Number, killed:Boolean, flags:Number, scatter:Number):Void {
        trace("-- " + label + " --");
        var bullet:Object = makeBullet();
        var ctx:Object = makeCtx(bullet, flags, scatter);
        var tgt:Object = makeTarget(hp, killed);
        var BQP:Object = BulletQueueProcessor;
        BQP.settleRayHit(ctx, tgt, 11, 22, 1, 50);
        trace("  => hitCount=" + bullet.hitCount);
    }

    private static function caseInjectReject(label:String, sameAsBullet:Boolean, hp:Number, blockFly:Boolean):Void {
        trace("-- " + label + " --");
        var bullet:Object = makeBullet();
        var shooter:Object = {};
        shooter.dispatcher = makeDispatcher("sht");
        var tgt:Object = sameAsBullet ? bullet : makeTarget(hp, false);
        if (blockFly) tgt.防止无限飞 = true;
        var BQP:Object = BulletQueueProcessor;
        var r:Object = BQP.injectHit(bullet, shooter, tgt, 11, 22, 1);
        trace("  => " + (r == null ? "null(rejected)" : "settled-UNEXPECTED"));
    }
}
