import org.flashNight.arki.component.Damage.*;
import org.flashNight.arki.component.StatHandler.*;

/**
 * UniversalDamageHandle 测试套件
 *
 * 覆盖四种伤害类型（物理/真伤/魔法/破击）的正确性、边界条件和性能基准。
 * 用于保护优化重构的语义不变性。
 *
 * 启动：
 *   import org.flashNight.arki.component.Damage.*;
 *   UniversalDamageHandleTest.runTests();
 */
class org.flashNight.arki.component.Damage.UniversalDamageHandleTest {

    // ========== 统计 ==========
    private static var _total:Number = 0;
    private static var _pass:Number = 0;
    private static var _fail:Number = 0;

    // ========== 被测对象 ==========
    private static var handler:UniversalDamageHandle;

    // ========== 断言工具 ==========

    private static function assertEq(expected, actual, msg:String):Void {
        _total++;
        if (expected != actual) {
            _fail++;
            trace("[FAIL] " + msg);
            trace("  expected: " + expected);
            trace("  actual  : " + actual);
        } else {
            _pass++;
            trace("[PASS] " + msg);
        }
    }

    private static function assertFloatEq(expected:Number, actual:Number, delta:Number, msg:String):Void {
        _total++;
        var diff:Number = expected - actual;
        if (diff < 0) diff = -diff;
        if (diff > delta) {
            _fail++;
            trace("[FAIL] " + msg);
            trace("  expected: " + expected + " +/-" + delta);
            trace("  actual  : " + actual + " (diff=" + diff + ")");
        } else {
            _pass++;
            trace("[PASS] " + msg);
        }
    }

    private static function assertTrue(cond:Boolean, msg:String):Void {
        _total++;
        if (!cond) {
            _fail++;
            trace("[FAIL] " + msg);
        } else {
            _pass++;
            trace("[PASS] " + msg);
        }
    }

    // ========== Mock 工厂 ==========

    /**
     * 构造子弹 mock
     * @param type 伤害类型字符串（"物理"/"魔法"/"真伤"/"破击"/undefined 等）
     * @param power 破坏力
     * @param enemy 是否为敌人
     * @param magicAttr 魔法伤害属性（可为 null/undefined）
     */
    private static function makeBullet(type:String, power:Number, enemy:Boolean, magicAttr:String):Object {
        return {
            伤害类型: type,
            破坏力: power,
            是否为敌人: enemy,
            魔法伤害属性: magicAttr
        };
    }

    /**
     * 构造目标 mock
     * @param defense 防御力
     * @param level 等级
     * @param resistTbl 魔法抗性字典（可为 null）
     */
    private static function makeTarget(defense:Number, level:Number, resistTbl:Object):Object {
        return {
            防御力: defense,
            等级: level,
            魔法抗性: resistTbl,
            损伤值: 0
        };
    }

    /** 构造并重置 DamageResult */
    private static function freshResult():DamageResult {
        var r:DamageResult = new DamageResult();
        r.reset();
        return r;
    }

    // ========== 测试入口 ==========

    public static function runTests():Void {
        trace("===== UniversalDamageHandle 测试套件 =====");
        _total = 0;
        _pass = 0;
        _fail = 0;
        handler = UniversalDamageHandle.getInstance();

        // --- 物理伤害 ---
        test_物理_基础计算();
        test_物理_未定义类型fallback();
        test_物理_空字符串fallback();
        test_物理_颜色_敌方();
        test_物理_颜色_友方();

        // --- 真伤 ---
        test_真伤_无视防御和抗性();
        test_真伤_颜色和标志_敌方();
        test_真伤_颜色和标志_友方();

        // --- 魔法伤害 ---
        test_魔法_专属抗性();
        test_魔法_回退基础抗性();
        test_魔法_默认抗性();
        test_魔法_零抗性不被误判();
        test_魔法_NaN抗性fallback();
        test_魔法_负抗性增伤();
        test_魔法_抗性95不触发软上限();
        test_魔法_抗性96软上限生效();
        test_魔法_抗性150恰好100减免();
        test_魔法_抗性200截断到100();
        test_魔法_抗性负2000夹取下限();
        test_魔法_颜色和标志();
        test_魔法_null属性默认能();

        // --- 破击伤害 ---
        test_破击_魔法属性有抗性();
        test_破击_非魔法属性有抗性();
        test_破击_无匹配抗性退化物理();
        test_破击_标志和emoji_魔法属性();
        test_破击_标志和emoji_非魔法属性();
        test_破击_零抗性值不被误判();
        test_破击_null属性默认能();

        // --- 边界 ---
        test_边界_防御力为零();
        test_边界_破坏力为零();
        test_边界_resistTbl为null();

        // --- 性能基准 ---
        runBenchmark();

        trace("===== 汇总: run=" + _total + " pass=" + _pass + " fail=" + _fail + " =====");
    }

    // ==================== 物理伤害测试 ====================

    private static function test_物理_基础计算():Void {
        var b:Object = makeBullet("物理", 100, true, null);
        var t:Object = makeTarget(300, 10, null);
        var r:DamageResult = freshResult();
        handler.handleBulletDamage(b, null, t, null, r);
        // 300/(300+300)=0.5, 100*0.5=50
        assertFloatEq(50, t.损伤值, 0.01, "物理: 100*(300/600)=50");
    }

    private static function test_物理_未定义类型fallback():Void {
        // bullet.伤害类型 为 undefined 应走物理路径
        var b:Object = {破坏力: 200, 是否为敌人: false, 魔法伤害属性: null};
        var t:Object = makeTarget(0, 1, null);
        var r:DamageResult = freshResult();
        handler.handleBulletDamage(b, null, t, null, r);
        // def=0: 300/300=1, 200*1=200
        assertFloatEq(200, t.损伤值, 0.01, "undefined类型fallback物理: 200*1=200");
        assertEq(2, r._dmgColorId, "undefined类型: 友方颜色=2");
    }

    private static function test_物理_空字符串fallback():Void {
        var b:Object = makeBullet("", 100, true, null);
        var t:Object = makeTarget(300, 1, null);
        var r:DamageResult = freshResult();
        handler.handleBulletDamage(b, null, t, null, r);
        assertFloatEq(50, t.损伤值, 0.01, "空字符串fallback物理: 100*0.5=50");
    }

    private static function test_物理_颜色_敌方():Void {
        var b:Object = makeBullet("物理", 100, true, null);
        var t:Object = makeTarget(0, 1, null);
        var r:DamageResult = freshResult();
        handler.handleBulletDamage(b, null, t, null, r);
        assertEq(1, r._dmgColorId, "物理敌方: 颜色=1");
    }

    private static function test_物理_颜色_友方():Void {
        var b:Object = makeBullet("物理", 100, false, null);
        var t:Object = makeTarget(0, 1, null);
        var r:DamageResult = freshResult();
        handler.handleBulletDamage(b, null, t, null, r);
        assertEq(2, r._dmgColorId, "物理友方: 颜色=2");
    }

    // ==================== 真伤测试 ====================

    private static function test_真伤_无视防御和抗性():Void {
        var b:Object = makeBullet("真伤", 150, true, null);
        var t:Object = makeTarget(999, 50, {基础: 80});
        var r:DamageResult = freshResult();
        handler.handleBulletDamage(b, null, t, null, r);
        assertFloatEq(150, t.损伤值, 0.01, "真伤: 无视防御(999)和抗性(80), 损伤=150");
    }

    private static function test_真伤_颜色和标志_敌方():Void {
        var b:Object = makeBullet("真伤", 100, true, null);
        var t:Object = makeTarget(0, 1, null);
        var r:DamageResult = freshResult();
        handler.handleBulletDamage(b, null, t, null, r);
        assertEq(3, r._dmgColorId, "真伤敌方: 颜色=3");
        assertTrue((r._efFlags & 8) != 0, "真伤: EF_DMG_TYPE_LABEL(bit3)已设置");
        assertTrue((r._efFlags & 128) != 0, "真伤敌方: isEnemy(bit7)已设置");
        assertEq("真", r._efText, "真伤: efText='真'");
    }

    private static function test_真伤_颜色和标志_友方():Void {
        var b:Object = makeBullet("真伤", 100, false, null);
        var t:Object = makeTarget(0, 1, null);
        var r:DamageResult = freshResult();
        handler.handleBulletDamage(b, null, t, null, r);
        assertEq(4, r._dmgColorId, "真伤友方: 颜色=4");
        assertTrue((r._efFlags & 128) == 0, "真伤友方: isEnemy位未设置");
    }

    // ==================== 魔法伤害测试 ====================

    private static function test_魔法_专属抗性():Void {
        var b:Object = makeBullet("魔法", 100, true, "火");
        var t:Object = makeTarget(0, 1, {火: 20, 基础: 10});
        var r:DamageResult = freshResult();
        handler.handleBulletDamage(b, null, t, null, r);
        // rv=20, damage = 100*(100-20)/100 = 80
        assertFloatEq(80, t.损伤值, 0.01, "魔法专属抗性: 100*(100-20)/100=80");
    }

    private static function test_魔法_回退基础抗性():Void {
        // "冰"不在 resistTbl 中，应回退到 "基础"
        var b:Object = makeBullet("魔法", 100, true, "冰");
        var t:Object = makeTarget(0, 1, {火: 20, 基础: 30});
        var r:DamageResult = freshResult();
        handler.handleBulletDamage(b, null, t, null, r);
        // 专属miss -> 回退基础=30, damage = 100*(100-30)/100 = 70
        assertFloatEq(70, t.损伤值, 0.01, "魔法回退基础抗性: 100*(100-30)/100=70");
    }

    private static function test_魔法_默认抗性():Void {
        // "冰"不在 resistTbl 中，"基础"也不在，使用默认 10+lvl/2
        var b:Object = makeBullet("魔法", 100, true, "冰");
        var t:Object = makeTarget(0, 10, {火: 20});
        var r:DamageResult = freshResult();
        handler.handleBulletDamage(b, null, t, null, r);
        // 默认: 10 + 10/2 = 15, damage = 100*(100-15)/100 = 85
        assertFloatEq(85, t.损伤值, 0.01, "魔法默认抗性: 10+10/2=15, 100*85/100=85");
    }

    private static function test_魔法_零抗性不被误判():Void {
        // 抗性值为0不应被误判为 undefined/falsy
        var b:Object = makeBullet("魔法", 100, true, "火");
        var t:Object = makeTarget(0, 1, {火: 0});
        var r:DamageResult = freshResult();
        handler.handleBulletDamage(b, null, t, null, r);
        // rv=0, damage = 100*(100-0)/100 = 100
        assertFloatEq(100, t.损伤值, 0.01, "魔法零抗性: 0不被误判, 100*(100/100)=100");
    }

    private static function test_魔法_NaN抗性fallback():Void {
        // 抗性值为非数字字符串，isNaN应兜底到20
        var b:Object = makeBullet("魔法", 100, true, "火");
        var t:Object = makeTarget(0, 1, {火: "abc"});
        var r:DamageResult = freshResult();
        handler.handleBulletDamage(b, null, t, null, r);
        // isNaN("abc") -> rv=20, damage = 100*(100-20)/100 = 80
        assertFloatEq(80, t.损伤值, 0.01, "魔法NaN抗性: fallback到20, 100*80/100=80");
    }

    private static function test_魔法_负抗性增伤():Void {
        var b:Object = makeBullet("魔法", 100, true, "火");
        var t:Object = makeTarget(0, 1, {火: -50});
        var r:DamageResult = freshResult();
        handler.handleBulletDamage(b, null, t, null, r);
        // rv=-50, damage = 100*(100-(-50))/100 = 150
        assertFloatEq(150, t.损伤值, 0.01, "魔法负抗性: 增伤, 100*150/100=150");
    }

    private static function test_魔法_抗性95不触发软上限():Void {
        var b:Object = makeBullet("魔法", 1000, true, "火");
        var t:Object = makeTarget(0, 1, {火: 95});
        var r:DamageResult = freshResult();
        handler.handleBulletDamage(b, null, t, null, r);
        // rv=95 (恰好不触发 >95 分支), damage = 1000*(100-95)/100 = 50
        assertFloatEq(50, t.损伤值, 0.01, "魔法抗性95: 不触发软上限, 1000*5/100=50");
    }

    private static function test_魔法_抗性96软上限生效():Void {
        var b:Object = makeBullet("魔法", 1000, true, "火");
        var t:Object = makeTarget(0, 1, {火: 96});
        var r:DamageResult = freshResult();
        handler.handleBulletDamage(b, null, t, null, r);
        // rv>95: 95 + (96-95)/11 = 95 + 1/11 = 95.0909...
        // damage = 1000*(100 - 95.0909)/100 = 49.0909...
        var expectedRv:Number = 95 + (96 - 95) / 11;
        var expected:Number = 1000 * (100 - expectedRv) / 100;
        assertFloatEq(expected, t.损伤值, 0.01, "魔法抗性96: 软上限生效, rv=" + expectedRv);
    }

    private static function test_魔法_抗性150恰好100减免():Void {
        var b:Object = makeBullet("魔法", 1000, true, "火");
        var t:Object = makeTarget(0, 1, {火: 150});
        var r:DamageResult = freshResult();
        handler.handleBulletDamage(b, null, t, null, r);
        // rv=150: 95+(150-95)/11 = 95+55/11 = 95+5 = 100
        // damage = 1000*(100-100)/100 = 0
        assertFloatEq(0, t.损伤值, 0.01, "魔法抗性150: 恰好100%减免");
    }

    private static function test_魔法_抗性200截断到100():Void {
        var b:Object = makeBullet("魔法", 1000, true, "火");
        var t:Object = makeTarget(0, 1, {火: 200});
        var r:DamageResult = freshResult();
        handler.handleBulletDamage(b, null, t, null, r);
        // 95+(200-95)/11 = 95+105/11 = 104.545 > 100 -> clamp到100
        // damage = 1000*0/100 = 0
        assertFloatEq(0, t.损伤值, 0.01, "魔法抗性200: 截断到100%, 零伤害");
    }

    private static function test_魔法_抗性负2000夹取下限():Void {
        var b:Object = makeBullet("魔法", 100, true, "火");
        var t:Object = makeTarget(0, 1, {火: -2000});
        var r:DamageResult = freshResult();
        handler.handleBulletDamage(b, null, t, null, r);
        // rv < -1000 -> clamp到-1000
        // damage = 100*(100-(-1000))/100 = 100*1100/100 = 1100
        assertFloatEq(1100, t.损伤值, 0.01, "魔法抗性-2000: 夹取到-1000, 11倍增伤");
    }

    private static function test_魔法_颜色和标志():Void {
        var b:Object = makeBullet("魔法", 100, true, "火");
        var t:Object = makeTarget(0, 1, {火: 20});
        var r:DamageResult = freshResult();
        handler.handleBulletDamage(b, null, t, null, r);
        assertEq(5, r._dmgColorId, "魔法敌方: 颜色=5");
        assertTrue((r._efFlags & 8) != 0, "魔法: EF_DMG_TYPE_LABEL(bit3)已设置");
        assertTrue((r._efFlags & 128) != 0, "魔法敌方: isEnemy(bit7)已设置");
        assertEq("火", r._efText, "魔法: efText='火'");
    }

    private static function test_魔法_null属性默认能():Void {
        // bullet.魔法伤害属性 为 null 时，efText 应显示 "能"
        var b:Object = makeBullet("魔法", 100, true, null);
        var t:Object = makeTarget(0, 10, null);
        var r:DamageResult = freshResult();
        handler.handleBulletDamage(b, null, t, null, r);
        assertEq("能", r._efText, "魔法null属性: efText默认='能'");
        // 默认抗性: 10+10/2=15, damage=100*85/100=85
        assertFloatEq(85, t.损伤值, 0.01, "魔法null属性: 走默认抗性=15");
    }

    // ==================== 破击伤害测试 ====================

    private static function test_破击_魔法属性有抗性():Void {
        // "电" 是 MagicDamageType -> rate=0.1
        var b:Object = makeBullet("破击", 100, true, "电");
        var t:Object = makeTarget(300, 1, {电: 50});
        var r:DamageResult = freshResult();
        handler.handleBulletDamage(b, null, t, null, r);
        // physPart = 100 * 300/(300+300) = 50
        // rate = 0.1 (magic tag)
        // rVal = 50
        // magicPart = 100 * 0.1 * (100-50)/100 = 5
        // total = 50 + 5 = 55
        assertFloatEq(55, t.损伤值, 0.01, "破击魔法属性: phys=50 + magic=5 = 55");
    }

    private static function test_破击_非魔法属性有抗性():Void {
        // "斩" 不是 MagicDamageType -> rate=0.5
        var b:Object = makeBullet("破击", 100, true, "斩");
        var t:Object = makeTarget(300, 1, {斩: 50});
        var r:DamageResult = freshResult();
        handler.handleBulletDamage(b, null, t, null, r);
        // physPart = 50
        // rate = 0.5 (non-magic tag)
        // magicPart = 100 * 0.5 * (100-50)/100 = 25
        // total = 50 + 25 = 75
        assertFloatEq(75, t.损伤值, 0.01, "破击非魔法属性: phys=50 + bonus=25 = 75");
    }

    private static function test_破击_无匹配抗性退化物理():Void {
        // 目标只有"冷"抗性，子弹属性"火"不匹配
        var b:Object = makeBullet("破击", 100, true, "火");
        var t:Object = makeTarget(300, 1, {冷: 50});
        var r:DamageResult = freshResult();
        handler.handleBulletDamage(b, null, t, null, r);
        // 无匹配 -> 纯物理: 100 * 300/600 = 50
        assertFloatEq(50, t.损伤值, 0.01, "破击无匹配抗性: 退化纯物理=50");
        // 不应设置 EF_CRUSH_LABEL
        assertTrue((r._efFlags & 16) == 0, "破击无匹配: EF_CRUSH_LABEL位未设置");
    }

    private static function test_破击_标志和emoji_魔法属性():Void {
        var b:Object = makeBullet("破击", 100, true, "电");
        var t:Object = makeTarget(0, 1, {电: 20});
        var r:DamageResult = freshResult();
        handler.handleBulletDamage(b, null, t, null, r);
        assertEq(1, r._dmgColorId, "破击敌方: 颜色=1(物理色)");
        assertTrue((r._efFlags & 16) != 0, "破击: EF_CRUSH_LABEL(bit4)已设置");
        assertEq("电", r._efText, "破击: efText='电'");
        assertEq("✨", r._efEmoji, "破击魔法属性: emoji=sparkle");
    }

    private static function test_破击_标志和emoji_非魔法属性():Void {
        var b:Object = makeBullet("破击", 100, true, "斩");
        var t:Object = makeTarget(0, 1, {斩: 20});
        var r:DamageResult = freshResult();
        handler.handleBulletDamage(b, null, t, null, r);
        assertEq("☠", r._efEmoji, "破击非魔法属性: emoji=skull");
    }

    private static function test_破击_零抗性值不被误判():Void {
        // 抗性值=0 不应被误判为 undefined（0 是 falsy）
        var b:Object = makeBullet("破击", 100, true, "电");
        var t:Object = makeTarget(0, 1, {电: 0});
        var r:DamageResult = freshResult();
        handler.handleBulletDamage(b, null, t, null, r);
        // rVal=0, rate=0.1, magicPart = 100*0.1*(100-0)/100 = 10
        // physPart = 100*1 = 100
        // total = 110
        assertFloatEq(110, t.损伤值, 0.01, "破击零抗性: phys=100 + magic=10 = 110");
        assertTrue((r._efFlags & 16) != 0, "破击零抗性: EF_CRUSH_LABEL仍设置");
    }

    private static function test_破击_null属性默认能():Void {
        // bullet.魔法伤害属性 为 null 时默认查 "能"
        var b:Object = makeBullet("破击", 100, true, null);
        var t:Object = makeTarget(0, 1, {能: 40});
        var r:DamageResult = freshResult();
        handler.handleBulletDamage(b, null, t, null, r);
        // attr默认"能", "能"不是MagicDamageType -> rate=0.5
        // physPart = 100, magicPart = 100*0.5*(100-40)/100 = 30
        // total = 130
        assertFloatEq(130, t.损伤值, 0.01, "破击null属性: 默认'能', phys=100+bonus=30=130");
    }

    // ==================== 边界条件 ====================

    private static function test_边界_防御力为零():Void {
        var b:Object = makeBullet("物理", 100, true, null);
        var t:Object = makeTarget(0, 1, null);
        var r:DamageResult = freshResult();
        handler.handleBulletDamage(b, null, t, null, r);
        // 300/300=1, 100*1=100
        assertFloatEq(100, t.损伤值, 0.01, "防御力0: 无减伤, 损伤=100");
    }

    private static function test_边界_破坏力为零():Void {
        var b:Object = makeBullet("物理", 0, true, null);
        var t:Object = makeTarget(300, 1, null);
        var r:DamageResult = freshResult();
        handler.handleBulletDamage(b, null, t, null, r);
        assertFloatEq(0, t.损伤值, 0.01, "破坏力0: 零伤害");
    }

    private static function test_边界_resistTbl为null():Void {
        // target.魔法抗性 为 null/undefined，魔法伤害应走默认抗性
        var b:Object = makeBullet("魔法", 100, true, "火");
        var t:Object = makeTarget(0, 20, null);
        var r:DamageResult = freshResult();
        handler.handleBulletDamage(b, null, t, null, r);
        // resistTbl为null -> 默认: 10+20/2 = 20
        // damage = 100*(100-20)/100 = 80
        assertFloatEq(80, t.损伤值, 0.01, "resistTbl为null: 默认抗性=20, 损伤=80");
    }

    // ==================== 性能基准 ====================

    private static function runBenchmark():Void {
        trace("");
        trace("===== 性能基准 =====");

        var ITERS:Number = 50000;
        var h:UniversalDamageHandle = handler;
        var r:DamageResult = new DamageResult();

        // 预创建 mock 数据（避免循环内分配）
        var bPhys:Object = {破坏力: 100, 是否为敌人: true, 魔法伤害属性: null};
        var bMagic:Object = makeBullet("魔法", 100, true, "火");
        var bTrue:Object = makeBullet("真伤", 100, true, null);
        var bCrush:Object = makeBullet("破击", 100, true, "电");

        var tPhys:Object = makeTarget(300, 10, null);
        var tMagic:Object = makeTarget(0, 10, {火: 20, 基础: 10});
        var tCrush:Object = makeTarget(300, 10, {电: 30});

        var i:Number;
        var t0:Number;

        // --- 物理路径 ---
        t0 = getTimer();
        for (i = 0; i < ITERS; i++) {
            r._efFlags = 0;
            r._dmgColorId = 0;
            h.handleBulletDamage(bPhys, null, tPhys, null, r);
        }
        var msPhys:Number = getTimer() - t0;

        // --- 魔法路径 ---
        t0 = getTimer();
        for (i = 0; i < ITERS; i++) {
            r._efFlags = 0;
            r._dmgColorId = 0;
            h.handleBulletDamage(bMagic, null, tMagic, null, r);
        }
        var msMagic:Number = getTimer() - t0;

        // --- 真伤路径 ---
        t0 = getTimer();
        for (i = 0; i < ITERS; i++) {
            r._efFlags = 0;
            r._dmgColorId = 0;
            h.handleBulletDamage(bTrue, null, tMagic, null, r);
        }
        var msTrue:Number = getTimer() - t0;

        // --- 破击路径（有抗性） ---
        t0 = getTimer();
        for (i = 0; i < ITERS; i++) {
            r._efFlags = 0;
            r._dmgColorId = 0;
            h.handleBulletDamage(bCrush, null, tCrush, null, r);
        }
        var msCrush:Number = getTimer() - t0;

        // --- 混合分布 (50%物理, 20%魔法, 15%真伤, 15%破击) ---
        var bullets:Array = [];
        var targets:Array = [];
        for (i = 0; i < 20; i++) {
            if (i < 10) {
                bullets[i] = bPhys;
                targets[i] = tPhys;
            } else if (i < 14) {
                bullets[i] = bMagic;
                targets[i] = tMagic;
            } else if (i < 17) {
                bullets[i] = bTrue;
                targets[i] = tMagic;
            } else {
                bullets[i] = bCrush;
                targets[i] = tCrush;
            }
        }
        t0 = getTimer();
        for (i = 0; i < ITERS; i++) {
            r._efFlags = 0;
            r._dmgColorId = 0;
            var idx:Number = i % 20;
            h.handleBulletDamage(bullets[idx], null, targets[idx], null, r);
        }
        var msMix:Number = getTimer() - t0;

        trace("  物理路径: " + ITERS + "次 = " + msPhys + "ms (" + Math.round(msPhys * 1000000 / ITERS) + " ns/call)");
        trace("  魔法路径: " + ITERS + "次 = " + msMagic + "ms (" + Math.round(msMagic * 1000000 / ITERS) + " ns/call)");
        trace("  真伤路径: " + ITERS + "次 = " + msTrue + "ms (" + Math.round(msTrue * 1000000 / ITERS) + " ns/call)");
        trace("  破击路径: " + ITERS + "次 = " + msCrush + "ms (" + Math.round(msCrush * 1000000 / ITERS) + " ns/call)");
        trace("  混合分布: " + ITERS + "次 = " + msMix + "ms (" + Math.round(msMix * 1000000 / ITERS) + " ns/call)");
        trace("");
    }
}
