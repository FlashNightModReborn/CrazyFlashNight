import org.flashNight.arki.component.Buff.*;
import org.flashNight.arki.component.Buff.Effect.GrayGooShotgunEtch;
import org.flashNight.arki.bullet.BulletComponent.Queue.BulletHitEffectRegistry;
import org.flashNight.arki.bullet.Factory.BulletFactory;
import org.flashNight.arki.component.Damage.DamageManagerFactory;
import org.flashNight.arki.component.Damage.DamageResult;
import org.flashNight.arki.component.Shield.BaseShield;
import org.flashNight.neur.Event.EventDispatcher;

/**
 * 灰蛊蚀刻霰弹（grayGooEtch）端到端行为契约单测：
 * - 单弹片擦边命中 → 54帧延迟 → 零距离满弹片结算 + 1%血量上限击溃
 * - 倒计时窗口内不叠加、不刷新、不覆盖快照；引爆不自我重挂；引爆后下一发可重新植入
 * - 非联弹多发霰弹（初始霰弹值>1 且单发霰弹值=1）引爆满发弹片
 * - 切枪/属性变化下保持植入瞬间的射手快照（STATE_LOCK_SHOOTER + 伤害加成快照）
 * - 目标提前阵亡静默清理、MISS 不植入、高强度护盾阻断击溃门控
 */
class org.flashNight.arki.component.Buff.Effect.GrayGooShotgunEtchTest {
    private static var passed:Number = 0;
    private static var failed:Number = 0;

    public static function runAllTests():Void {
        passed = 0;
        failed = 0;
        if (DamageManagerFactory.Basic == null) {
            DamageManagerFactory.init();
        }
        if (_root.gameworld == undefined) {
            _root.gameworld = {};
        }
        trace("=== GrayGooShotgunEtchTest start ===");
        testFarGrazeDetonatesFullPelletAndCrumble();
        testNoStackNoRefreshNoSelfLoopAndRearm();
        testNonChainMultiProjectileInitialScatter();
        testShooterSnapshotLockAcrossWeaponSwap();
        testTargetDeathBeforeExpiryCancelsSilently();
        testMissAndShieldStrengthGates();
        trace("=== GrayGooShotgunEtchTest result: passed=" + passed + " failed=" + failed + " ===");
        if (failed > 0) trace("[TEST_FAIL] GrayGooShotgunEtchTest");
    }

    private static function check(ok:Boolean, label:String):Void {
        if (ok) {
            passed++;
        } else {
            failed++;
            trace("[FAIL] GrayGooShotgunEtchTest: " + label);
        }
    }

    private static function etchBehavior():Object {
        return {
            type: "grayGooEtch",
            stackGroup: "grayGooShotgunEtch",
            profileId: "shotgunBase",
            delayFrames: 54,
            detonationCrumble: 1
        };
    }

    private static function makeTarget(hp:Number):Object {
        var t:Object = {
            _name: "etchTarget",
            _x: 200,
            _y: 300,
            Z轴坐标: 0,
            hp: hp,
            hp满血值: hp,
            防御力: 1,
            等级: 1,
            重量: 100,
            躲闪率: 0,
            damageTakenMultiplier: 1,
            shield: new BaseShield(0, 0, 0, 0, "无"),
            dispatcher: new EventDispatcher()
        };
        t.buffManager = new BuffManager(t, null);
        return t;
    }

    private static function makeShooter():Object {
        return {
            _name: "etchHero",
            _x: 100,
            _y: 300,
            _xscale: 100,
            等级: 50,
            命中率: 100000,
            伤害加成: 20,
            是否为敌人: false,
            dispatcher: new EventDispatcher()
        };
    }

    private static function validHitResult():DamageResult {
        var r:DamageResult = new DamageResult();
        r.dodgeStatus = "未躲闪";
        r.actualScatterUsed = 1;
        return r;
    }

    private static function cleanup(t:Object):Void {
        if (!t) return;
        if (t.buffManager) {
            t.buffManager.clearAllBuffs();
            t.buffManager.destroy();
        }
        if (t.dispatcher) t.dispatcher.destroy();
    }

    /** 1. 远距离仅1颗弹丸擦边（影子编码 S0=12）→ 54帧后零距离12弹丸全额引爆 + 1%击溃 */
    private static function testFarGrazeDetonatesFullPelletAndCrumble():Void {
        var target:Object = makeTarget(10000);
        var shooter:Object = makeShooter();
        var lastPellets:Number = 0;
        var lastSegments:Number = 0;
        var lastCrumble:Number = -1;
        target.dispatcher.subscribe("GrayGooEtchDetonated", function(u:Object, s:Object, dr:Object, pellets:Number, crumble:Number):Void {
            lastPellets = pellets;
            lastSegments = dr ? Number(dr.actualScatterUsed) : 0;
            lastCrumble = crumble;
        }, target);

        // 模拟联弹影子记账态：出生 S0=12，远距离仅命中1颗后剩余11颗
        var shadowScatter:Number = -((12 << 16) | 11);
        var grazeBullet:Object = {
            hitBehavior: etchBehavior(),
            发射者: shooter._name,
            子弹威力: 50,
            固伤: 0,
            百分比伤害: 0,
            伤害类型: "物理",
            命中率: 100000,
            霰弹值: shadowScatter,
            初始霰弹值: 12,
            击溃: 0.1,
            击倒率: 15,
            水平击退速度: 12,
            垂直击退速度: 0,
            Z轴攻击范围: 40
        };

        // prepare 对 grayGooEtch 不篡改当发子弹的静态 0.1% 击溃
        BulletHitEffectRegistry.prepare(grazeBullet, shooter, target);
        check(Math.abs(grazeBullet.击溃 - 0.1) < 0.0001, "prepare preserves static 0.1% rout on normal shot");

        var implanted:Boolean = BulletHitEffectRegistry.apply(grazeBullet, shooter, target, validHitResult());
        check(implanted === true && target.grayGooEtchPending === true, "1-pellet graze implants pending etch");

        // 53帧时尚未到期
        target.buffManager.update(53);
        check(target.hp == 10000 && target.hp满血值 == 10000 && target.grayGooEtchPending === true,
            "etch does not detonate at frame 53");

        // 第54帧精确到期引爆：12颗弹丸打满 + 1%血量上限击溃（100点）
        target.buffManager.update(1);
        check(target.grayGooEtchPending === false && target.grayGooEtchDetonationCount == 1,
            "etch detonates at frame 54 and clears pending state");
        check(lastPellets == 12 && lastSegments == 12,
            "detonation resolves all 12 birth pellets at 0-distance");
        check(target.hp满血值 == 9900 && lastCrumble == 100,
            "detonation permanently crumbles 1% max HP (100 of 10000)");
        // 12颗弹丸伤害（每颗约 (50+20)*[0.85..1.15] ≈ 59..80，12颗至少700）+ 100击溃伤血 => 损失远超单弹丸并小于全血
        var totalHpLost:Number = 10000 - target.hp;
        check(totalHpLost >= 750 && totalHpLost <= 1200,
            "detonation deals full 12-pellet 0-distance damage plus 100 crumble HP loss");

        cleanup(target);
        shooter.dispatcher.destroy();
    }

    /** 2. 倒计时窗口内不叠加/不刷新/不覆盖快照；引爆自身不重挂；引爆后下一发正常重装 */
    private static function testNoStackNoRefreshNoSelfLoopAndRearm():Void {
        var target:Object = makeTarget(20000);
        var shooter:Object = makeShooter();
        var observedPellets:Array = [];
        target.dispatcher.subscribe("GrayGooEtchDetonated", function(u:Object, s:Object, dr:Object, pellets:Number, crumble:Number):Void {
            observedPellets.push(pellets);
        }, target);

        var shot1:Object = {
            hitBehavior: etchBehavior(),
            发射者: shooter._name,
            子弹威力: 40,
            伤害类型: "物理",
            命中率: 100000,
            霰弹值: 8,
            初始霰弹值: 8,
            击溃: 0.1
        };
        var shot2Stronger:Object = {
            hitBehavior: etchBehavior(),
            发射者: shooter._name,
            子弹威力: 999,
            伤害类型: "真伤",
            命中率: 100000,
            霰弹值: 12,
            初始霰弹值: 12,
            击溃: 0.1
        };

        check(BulletHitEffectRegistry.apply(shot1, shooter, target, validHitResult()) === true,
            "shot1 implants etch");
        target.buffManager.update(30);
        check(BulletHitEffectRegistry.apply(shot2Stronger, shooter, target, validHitResult()) === false,
            "shot2 during countdown returns false without stacking or refreshing");

        // 再过24帧（总计54帧，而非 30+54=84帧）即按 shot1 的 8 弹丸快照引爆
        target.buffManager.update(24);
        check(target.grayGooEtchDetonationCount == 1 && observedPellets.length == 1 && observedPellets[0] == 8,
            "countdown is not extended and keeps shot1 8-pellet snapshot");

        // 引爆用的结算弹不带 hitBehavior，继续推进100帧绝不自我递归引爆
        target.buffManager.update(100);
        check(target.grayGooEtchDetonationCount == 1 && target.grayGooEtchPending === false,
            "detonation settlement bullet never self-retriggers another etch");

        // 引爆结束后，下一发真实命中可以立即重新挂上新蚀刻
        check(BulletHitEffectRegistry.apply(shot2Stronger, shooter, target, validHitResult()) === true,
            "next shot after detonation re-arms a fresh etch");
        target.buffManager.update(54);
        check(target.grayGooEtchDetonationCount == 2 && observedPellets[1] == 12,
            "re-armed etch detonates cleanly with new 12-pellet snapshot");

        cleanup(target);
        shooter.dispatcher.destroy();
    }

    /** 3. 非联弹多发霰弹（如夜莺/众神之力：单实例霰弹值=1，但出生初始霰弹值=5）引爆5段满伤 */
    private static function testNonChainMultiProjectileInitialScatter():Void {
        var target:Object = makeTarget(10000);
        var shooter:Object = makeShooter();
        var segmentsUsed:Number = 0;
        target.dispatcher.subscribe("GrayGooEtchDetonated", function(u:Object, s:Object, dr:Object, pellets:Number, crumble:Number):Void {
            segmentsUsed = dr ? Number(dr.actualScatterUsed) : 0;
        }, target);

        // 验证 BulletFactory.prepareBulletData 后单发模板记录初始霰弹值
        var rawObj:Object = {
            子弹种类: "巨型穿刺能量子弹",
            发射者: shooter._name,
            霰弹值: 5,
            子弹威力: 60,
            伤害类型: "破击",
            魔法伤害属性: "能量",
            命中率: 100000,
            hitBehavior: etchBehavior()
        };
        BulletFactory.prepareBulletData(rawObj, shooter);
        // 模拟 createBullet 非联弹多发路径：Obj.初始霰弹值=5，而单颗飞行实例 霰弹值=1
        rawObj.初始霰弹值 = 5;
        rawObj.霰弹值 = 1;

        check(BulletHitEffectRegistry.apply(rawObj, shooter, target, validHitResult()) === true,
            "non-chain multi-projectile single hit implants etch");
        target.buffManager.update(54);
        check(segmentsUsed == 5,
            "non-chain multi-projectile detonation settles full 5 birth projectiles");

        cleanup(target);
        shooter.dispatcher.destroy();
    }

    /** 4. 植入后切枪或射手属性变化，引爆仍严格使用植入瞬间快照 */
    private static function testShooterSnapshotLockAcrossWeaponSwap():Void {
        var target:Object = makeTarget(10000);
        target.防御力 = 99999; // 极高物理防御，只有真伤快照才能打出全额伤害
        var shooter:Object = makeShooter();
        shooter.伤害加成 = 300;

        var shot:Object = {
            hitBehavior: etchBehavior(),
            发射者: shooter._name,
            子弹威力: 200,
            固伤: 0,
            伤害类型: "真伤",
            命中率: 100000,
            霰弹值: 4,
            初始霰弹值: 4,
            击溃: 0.1
        };
        BulletHitEffectRegistry.apply(shot, shooter, target, validHitResult());

        // 模拟 1.8s 期间玩家切枪：射手当前伤害加成清零、伤害类型变物理、额外挂上 50% 击溃
        shooter.伤害加成 = 0;
        shooter.伤害类型 = "物理";
        shooter.击溃 = 50;

        target.buffManager.update(54);
        // 若错误重读了 shooter：击溃会变成 50%（上限剩 5000），且伤害加成丢失；正确锁快照则上限为 9900，且4段真伤每段约 (200+300)*[0.85..1.15]=425..575
        var hpLost:Number = 10000 - target.hp;
        check(target.hp满血值 == 9900,
            "STATE_LOCK_SHOOTER prevents inheriting post-swap shooter.击溃=50%");
        check(hpLost >= 1700 && hpLost <= 2500,
            "detonation uses snapshotted 真伤 + 300 damage bonus despite weapon swap");

        cleanup(target);
        shooter.dispatcher.destroy();
    }

    /** 5. 目标在倒计时结束前阵亡：静默清理，不触发引爆 */
    private static function testTargetDeathBeforeExpiryCancelsSilently():Void {
        var target:Object = makeTarget(5000);
        var shooter:Object = makeShooter();
        var detonated:Boolean = false;
        target.dispatcher.subscribe("GrayGooEtchDetonated", function():Void {
            detonated = true;
        }, target);

        var shot:Object = {
            hitBehavior: etchBehavior(),
            发射者: shooter._name,
            子弹威力: 100,
            伤害类型: "物理",
            命中率: 100000,
            霰弹值: 8,
            初始霰弹值: 8
        };
        BulletHitEffectRegistry.apply(shot, shooter, target, validHitResult());
        target.buffManager.update(20);
        target.hp = 0;
        target._killed = true;
        target.buffManager.update(40);

        check(!detonated && target.grayGooEtchPending === false && !(target.grayGooEtchDetonationCount > 0),
            "target dying before delayFrames cancels etch silently with zero detonation");

        cleanup(target);
        shooter.dispatcher.destroy();
    }

    /** 6. MISS 拒绝植入 & 高强度护盾按统一击溃门控阻断上限削减 */
    private static function testMissAndShieldStrengthGates():Void {
        var target:Object = makeTarget(10000);
        var shooter:Object = makeShooter();
        var shot:Object = {
            hitBehavior: etchBehavior(),
            发射者: shooter._name,
            子弹威力: 80,
            伤害类型: "物理",
            命中率: 100000,
            霰弹值: 6,
            初始霰弹值: 6
        };

        var missRes:DamageResult = new DamageResult();
        missRes.dodgeStatus = "躲闪";
        check(BulletHitEffectRegistry.apply(shot, shooter, target, missRes) === false && !target.grayGooEtchPending,
            "normal MISS does not implant etch");

        var scatterMissRes:DamageResult = new DamageResult();
        scatterMissRes.dodgeStatus = "未躲闪";
        scatterMissRes.scatterModelEnabled = true;
        scatterMissRes.actualScatterUsed = 3;
        scatterMissRes.scatterMissCount = 3;
        check(BulletHitEffectRegistry.apply(shot, shooter, target, scatterMissRes) === false && !target.grayGooEtchPending,
            "all-segment scatter MISS does not implant etch");

        // 挂载强度 500 (> 子弹威力 80) 的容量护盾：引爆仍正常结算，但 1% 击溃遵循统一护盾强度门控被阻断
        target.shield = new BaseShield(2000, 500, 0, 0, "测试强盾");
        var resolvedCrumble:Number = -1;
        target.dispatcher.subscribe("GrayGooEtchDetonated", function(u:Object, s:Object, dr:Object, pellets:Number, crumble:Number):Void {
            resolvedCrumble = crumble;
        }, target);

        check(BulletHitEffectRegistry.apply(shot, shooter, target, validHitResult()) === true,
            "valid hit against shielded target implants etch");
        target.buffManager.update(54);
        check(target.grayGooEtchDetonationCount == 1 && target.hp满血值 == 10000 && resolvedCrumble == 0,
            "shield strength > bullet power blocks detonation max-HP crumble per standard CrumbleDamageHandle rule");

        cleanup(target);
        shooter.dispatcher.destroy();
    }
}
