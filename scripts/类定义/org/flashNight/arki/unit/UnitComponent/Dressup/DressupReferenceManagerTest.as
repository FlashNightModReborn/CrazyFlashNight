import org.flashNight.arki.unit.UnitComponent.Dressup.DressupReferenceManager;
import org.flashNight.arki.unit.UnitComponent.Dressup.SkinReadyClass;

/**
 * DressupReferenceManager Test Suite
 *
 * 通过 mock 验证 attach/refreshAll/doConfig 的纯逻辑路径，覆盖：
 * - 巨拳模式排除
 * - refNameAliases 数字后缀解析
 * - 女性 fallback 路径
 * - 同步 publish 条件触发
 * - deferred 路径 initObject 注入（含 fallback 路径）
 * - attach 数字后缀 regKey/actualRefName 生成
 * - attach 失效 MC regKey 复用
 * - refreshAll 标记设置/清除 + 组级事件
 * - refreshAll 边遍历边删除 dead entry 同时执行 live entry
 *
 * Usage: DressupReferenceManagerTest.runAll();
 */
class org.flashNight.arki.unit.UnitComponent.Dressup.DressupReferenceManagerTest {

    private static var testCount:Number = 0;
    private static var passedTests:Number = 0;
    private static var failedTests:Number = 0;

    // ====================================================================
    // 断言 helpers
    // ====================================================================

    private static function assertTrue(name:String, cond:Boolean):Void {
        testCount++;
        if (cond) {
            passedTests++;
            trace("  [PASS] " + name);
        } else {
            failedTests++;
            trace("  [FAIL] " + name);
        }
    }

    private static function assertEquals(name:String, expected, actual):Void {
        testCount++;
        if (expected === actual) {
            passedTests++;
            trace("  [PASS] " + name + " (= " + actual + ")");
        } else {
            failedTests++;
            trace("  [FAIL] " + name + " expected=" + expected + " actual=" + actual);
        }
    }

    private static function assertNull(name:String, value):Void {
        testCount++;
        if (value === null || value === undefined) {
            passedTests++;
            trace("  [PASS] " + name + " (null)");
        } else {
            failedTests++;
            trace("  [FAIL] " + name + " expected null actual=" + value);
        }
    }

    private static function assertNotNull(name:String, value):Void {
        testCount++;
        if (value !== null && value !== undefined) {
            passedTests++;
            trace("  [PASS] " + name);
        } else {
            failedTests++;
            trace("  [FAIL] " + name + " value is null/undefined");
        }
    }

    // ====================================================================
    // Mock builders
    // ====================================================================

    private static function makeMockUnit(空手动作类型:String, 性别:String) {
        var unit = {};
        unit.空手动作类型 = (空手动作类型 != null) ? 空手动作类型 : "正常";
        unit.性别 = (性别 != null) ? 性别 : "男";
        unit.syncRefs = {};
        unit.publishLog = [];
        unit.dispatcher = {};
        unit.dispatcher.publish = function(key, u) {
            u.publishLog.push({key: key, unit: u});
        };
        return unit;
    }

    private static function makeMockMC() {
        var mc = {};
        mc.基本款 = { _name: "基本款" };
        mc.attachLog = [];
        mc.failLinkages = {};
        mc.attachMovie = function(linkage, instanceName, depth, initObject) {
            this.attachLog.push({
                linkage: linkage,
                instanceName: instanceName,
                depth: depth,
                initObject: initObject
            });
            if (this.failLinkages[linkage]) return undefined;
            var skin = { _parent: this, _name: instanceName };
            if (initObject) {
                for (var k:String in initObject) skin[k] = initObject[k];
            }
            this[instanceName] = skin;
            return skin;
        };
        return mc;
    }

    // 让 attach() 内 movieClip._parent._parent._parent 能拿到 unit
    private static function wireParentChain(mc, unit):Void {
        mc._parent = { _parent: { _parent: unit } };
    }

    // ====================================================================
    // Tests
    // ====================================================================

    private static function test_doConfig_巨拳模式排除右下臂():Void {
        trace("--- doConfig: 巨拳模式排除右下臂 ---");
        var unit = makeMockUnit("巨拳", "男");
        var mc = makeMockMC();
        var result = DressupReferenceManager.doConfig(mc, "右下臂_装扮素材", "装扮", "右下臂_引用", unit);
        assertNull("巨拳模式右下臂_引用 doConfig 返回 null", result);
        assertEquals("attachMovie 未被调用", 0, mc.attachLog.length);
        assertEquals("publish 未触发", 0, unit.publishLog.length);
    }

    private static function test_doConfig_单臂巨拳不排除左下臂():Void {
        trace("--- doConfig: 单臂巨拳不排除左下臂 ---");
        var unit = makeMockUnit("单臂巨拳", "男");
        var mc = makeMockMC();
        var result = DressupReferenceManager.doConfig(mc, "左下臂_装扮素材", "装扮", "左下臂_引用", unit);
        assertNotNull("单臂巨拳左下臂_引用 doConfig 返回非 null", result);
        assertEquals("attachMovie 被调用 1 次", 1, mc.attachLog.length);
    }

    private static function test_doConfig_refNameAliases_小腿1解析为小腿():Void {
        trace("--- doConfig: refNameAliases 小腿1_引用 → 小腿_引用 base ---");
        // 巨拳排除规则只对 baseRefName 检查；小腿1_引用 不应被巨拳排除
        // 同时 femaleFallbacks 用 base 名（小腿_引用 → 女变装-裸体小腿）
        var unit = makeMockUnit("正常", "女");
        var mc = makeMockMC();
        mc.failLinkages["primary_skin"] = true;  // 让主 attach 失败，触发女性 fallback
        var result = DressupReferenceManager.doConfig(mc, "primary_skin", "装扮", "小腿1_引用", unit);
        assertNotNull("fallback 路径返回非 null", result);
        // 检查第二次 attachMovie 用的是 baseRefName(小腿_引用) 对应的 fallback
        assertEquals("第二次 attach 用 base 名映射的 fallback", "女变装-裸体小腿", mc.attachLog[1].linkage);
    }

    private static function test_doConfig_女性fallback触发():Void {
        trace("--- doConfig: 女性 fallback 路径 ---");
        var unit = makeMockUnit("正常", "女");
        var mc = makeMockMC();
        mc.failLinkages["primary_skin"] = true;
        var result = DressupReferenceManager.doConfig(mc, "primary_skin", "装扮", "身体_引用", unit);
        assertEquals("attachMovie 被调用 2 次（主 + fallback）", 2, mc.attachLog.length);
        assertEquals("第一次 attach 是 primary_skin", "primary_skin", mc.attachLog[0].linkage);
        assertEquals("第二次 attach 是女变装-裸体身体", "女变装-裸体身体", mc.attachLog[1].linkage);
        assertEquals("unit.身体_引用 指向 fallback skin", "装扮", unit.身体_引用._name);
    }

    private static function test_doConfig_男性无fallback():Void {
        trace("--- doConfig: 男性无 fallback，引用降级到基本款 ---");
        var unit = makeMockUnit("正常", "男");
        var mc = makeMockMC();
        mc.failLinkages["primary_skin"] = true;
        var result = DressupReferenceManager.doConfig(mc, "primary_skin", "装扮", "身体_引用", unit);
        assertEquals("attachMovie 仅调用 1 次（无 fallback）", 1, mc.attachLog.length);
        assertEquals("unit.身体_引用 降级到基本款", "基本款", unit.身体_引用._name);
    }

    private static function test_doConfig_同步publish条件触发():Void {
        trace("--- doConfig: 同步 publish 仅在 syncRefs 设置时触发 ---");
        var unit1 = makeMockUnit("正常", "男");
        var mc1 = makeMockMC();
        DressupReferenceManager.doConfig(mc1, "skin", "装扮", "身体_引用", unit1);
        assertEquals("syncRefs 未设置时 publish 不触发", 0, unit1.publishLog.length);

        var unit2 = makeMockUnit("正常", "男");
        var mc2 = makeMockMC();
        unit2.syncRefs["身体_引用"] = true;
        DressupReferenceManager.doConfig(mc2, "skin", "装扮", "身体_引用", unit2);
        assertEquals("syncRefs 设置时 publish 触发 1 次", 1, unit2.publishLog.length);
        assertEquals("publish key 正确", "身体_引用", unit2.publishLog[0].key);
    }

    private static function test_doConfig_deferred路径initObject注入():Void {
        trace("--- doConfig: deferred 路径正确注入 initObject ---");
        var unit = makeMockUnit("正常", "男");
        var mc = makeMockMC();
        unit.syncRefs["刀_引用:ready"] = true;
        DressupReferenceManager.doConfig(mc, "_test_dressup_skin_001", "装扮", "刀_引用", unit);

        assertEquals("attachMovie 被调用 1 次", 1, mc.attachLog.length);
        var initObj = mc.attachLog[0].initObject;
        assertNotNull("initObject 已注入", initObj);
        assertEquals("initObject.__publishKey 正确", "刀_引用:ready", initObj.__publishKey);
        assertTrue("initObject.__unit === unit", initObj.__unit === unit);
        // 清理（doConfig 内已 unregister，再保险一次）
        Object.registerClass("_test_dressup_skin_001", null);
    }

    private static function test_doConfig_deferred_fallback路径同样注入initObject():Void {
        trace("--- doConfig: deferred 路径下 fallback 也注入 initObject ---");
        var unit = makeMockUnit("正常", "女");
        var mc = makeMockMC();
        mc.failLinkages["_test_dressup_skin_002"] = true;  // 主路径失败
        unit.syncRefs["身体_引用:ready"] = true;
        DressupReferenceManager.doConfig(mc, "_test_dressup_skin_002", "装扮", "身体_引用", unit);

        assertEquals("attachMovie 被调用 2 次", 2, mc.attachLog.length);
        // 主路径 attach 也带 initObject（会被女性 fallback 覆盖）
        assertNotNull("主路径 initObject 已注入", mc.attachLog[0].initObject);
        // fallback 路径必须也带 initObject（这是 Plan B 易漏点）
        var fbInit = mc.attachLog[1].initObject;
        assertNotNull("fallback 路径 initObject 已注入", fbInit);
        assertEquals("fallback initObject.__publishKey 正确", "身体_引用:ready", fbInit.__publishKey);
        Object.registerClass("_test_dressup_skin_002", null);
        Object.registerClass("女变装-裸体身体", null);
    }

    private static function test_doConfig_未订阅deferred时不传initObject():Void {
        trace("--- doConfig: 未订阅 :ready 时 attachMovie 不带 initObject ---");
        var unit = makeMockUnit("正常", "男");
        var mc = makeMockMC();
        // 不设置 syncRefs[:ready]
        DressupReferenceManager.doConfig(mc, "skin", "装扮", "刀_引用", unit);
        assertEquals("attachMovie 被调用 1 次", 1, mc.attachLog.length);
        assertNull("initObject 未注入", mc.attachLog[0].initObject);
    }

    private static function test_attach_数字后缀regKey生成():Void {
        trace("--- attach: 同 base key 第二次注册生成数字后缀 ---");
        var unit = makeMockUnit("正常", "男");
        var mc1 = makeMockMC();
        wireParentChain(mc1, unit);
        DressupReferenceManager.attach(mc1, "skin", "装扮", "小腿_引用");

        var mc2 = makeMockMC();
        wireParentChain(mc2, unit);
        DressupReferenceManager.attach(mc2, "skin", "装扮", "小腿_引用");

        // 第一次：regKey = "小腿_引用@装扮"，actualRefName = "小腿_引用"
        // 第二次：regKey = "小腿1_引用@装扮"，actualRefName = "小腿1_引用"
        // 命名风格已统一：regKey 即 actualRefName + "@" + instanceName
        var entry1 = unit.dressupRegistry["小腿_引用@装扮"];
        var entry2 = unit.dressupRegistry["小腿1_引用@装扮"];
        assertNotNull("第一次 entry 存在", entry1);
        assertNotNull("第二次 entry 存在（数字后缀 regKey）", entry2);
        assertEquals("第一次 actualRefName = 小腿_引用", "小腿_引用", entry1.referenceName);
        assertEquals("第二次 actualRefName = 小腿1_引用", "小腿1_引用", entry2.referenceName);
        // baseReferenceName 始终是原始名
        assertEquals("第二次 baseReferenceName = 小腿_引用", "小腿_引用", entry2.baseReferenceName);
    }

    private static function test_attach_失效MC复用regKey():Void {
        trace("--- attach: 旧 entry MC 失效时复用 regKey ---");
        var unit = makeMockUnit("正常", "男");
        var mc1 = makeMockMC();
        wireParentChain(mc1, unit);
        DressupReferenceManager.attach(mc1, "skin", "装扮", "刀_引用");
        // 模拟 mc1 被卸载：去掉 _parent
        unit.dressupRegistry["刀_引用@装扮"].mc._parent = null;

        var mc2 = makeMockMC();
        wireParentChain(mc2, unit);
        DressupReferenceManager.attach(mc2, "skin2", "装扮", "刀_引用");

        // 应当复用同一 regKey，没有数字后缀
        assertNotNull("regKey 复用，刀_引用@装扮 entry 仍存在", unit.dressupRegistry["刀_引用@装扮"]);
        assertNull("没有生成 刀1_引用@装扮", unit.dressupRegistry["刀1_引用@装扮"]);
        assertEquals("entry.mc 是新的 mc2", mc2, unit.dressupRegistry["刀_引用@装扮"].mc);
    }

    private static function test_attach_skinKeyOverrides武器走装扮后缀():Void {
        trace("--- attach: 武器 skinKeyName 走 _装扮 后缀，肢体走 split ---");
        var unit = makeMockUnit("正常", "男");
        var mc1 = makeMockMC();
        wireParentChain(mc1, unit);
        DressupReferenceManager.attach(mc1, "skin", "装扮", "刀_引用");
        assertEquals("刀_引用 → skinKeyName=刀_装扮", "刀_装扮",
            unit.dressupRegistry["刀_引用@装扮"].skinKeyName);

        var mc2 = makeMockMC();
        wireParentChain(mc2, unit);
        DressupReferenceManager.attach(mc2, "skin", "装扮", "身体_引用");
        assertEquals("身体_引用 → skinKeyName=身体（split fallback）", "身体",
            unit.dressupRegistry["身体_引用@装扮"].skinKeyName);
    }

    private static function test_refreshAll_标记与组级事件():Void {
        trace("--- refreshAll: dressupRefreshing 标记与组级事件 ---");
        var unit = makeMockUnit("正常", "男");
        var mc = makeMockMC();
        wireParentChain(mc, unit);
        DressupReferenceManager.attach(mc, "skin", "装扮", "身体_引用");
        unit["身体"] = "skin";  // skinConfig 来源（refresh 会读 unit[skinKeyName]）
        unit.publishLog = [];

        // case A: 不订阅组级事件
        DressupReferenceManager.refreshAll(unit);
        assertEquals("未订阅组级事件时 publish 0 次", 0, unit.publishLog.length);
        assertTrue("dressupRefreshing 在 refresh 后清零", unit.dressupRefreshing === false);

        // case B: 订阅组级事件
        unit.syncRefs["dressup:refreshed"] = true;
        unit.publishLog = [];
        DressupReferenceManager.refreshAll(unit);
        assertEquals("订阅后组级事件触发 1 次", 1, unit.publishLog.length);
        assertEquals("组级事件 key 正确", "dressup:refreshed", unit.publishLog[0].key);
    }

    private static function test_refreshAll_dead_entry清理与live同处理():Void {
        trace("--- refreshAll: dead entry 删除 + live entry 仍处理 ---");
        var unit = makeMockUnit("正常", "男");

        // 注册两个 entry，一个稍后失效
        var deadMC = makeMockMC();
        wireParentChain(deadMC, unit);
        DressupReferenceManager.attach(deadMC, "skin", "装扮", "身体_引用");

        var liveMC = makeMockMC();
        wireParentChain(liveMC, unit);
        DressupReferenceManager.attach(liveMC, "skin", "装扮", "刀_引用");

        // dead MC 失效（_parent 置 null）
        unit.dressupRegistry["身体_引用@装扮"].mc._parent = null;
        unit["身体"] = "skin";
        unit["刀_装扮"] = "skin";

        // 清空 attach log（refresh 会再次调用）
        liveMC.attachLog = [];

        DressupReferenceManager.refreshAll(unit);

        assertNull("dead entry 已被清理", unit.dressupRegistry["身体_引用@装扮"]);
        assertNotNull("live entry 仍存在", unit.dressupRegistry["刀_引用@装扮"]);
        assertTrue("live entry 的 attachMovie 被再次调用", liveMC.attachLog.length > 0);
    }

    // ====================================================================
    // 多 unit 同帧 attach scope 隔离（验证 register-attach-unregister per-call）
    //
    // 注意：曾尝试 Object.registerClass 全局 spy 来验证 register/unregister
    // 调用对数与顺序，但 AS2/FP20 不允许覆写 Object 内置静态方法（赋值
    // Object.registerClass = function(){} 静默失败，调用方仍走原方法）。
    // 因此放弃 spy 思路，改为通过 mock attachMovie 抓取 initObject 来间接
    // 验证 deferred 路径的正确性。register-attach-unregister 是否真隔离，
    // 由 agentsDoc/as2-load-timing.md 第 2.3 节 trace 已实测确认。
    // ====================================================================

    private static function test_multi_unit_perAttach_scope_隔离_异步订阅():Void {
        trace("--- multi-unit: A 订阅 :ready / B 不订阅，initObject 不串扰 ---");
        var unitA = makeMockUnit("正常", "男");
        unitA.syncRefs["刀_引用:ready"] = true;
        var mcA = makeMockMC();

        var unitB = makeMockUnit("正常", "男");
        var mcB = makeMockMC();

        // 同一脚本块连续 attach 同名 linkage
        DressupReferenceManager.doConfig(mcA, "_shared_test_skin", "装扮", "刀_引用", unitA);
        DressupReferenceManager.doConfig(mcB, "_shared_test_skin", "装扮", "刀_引用", unitB);

        // 清理（doConfig 内已 unregister，再保险一次）
        Object.registerClass("_shared_test_skin", null);

        assertNotNull("unitA 的 attachMovie 收到 initObject", mcA.attachLog[0].initObject);
        assertNull("unitB 的 attachMovie 不带 initObject", mcB.attachLog[0].initObject);
        assertTrue("unitA initObject.__unit === unitA", mcA.attachLog[0].initObject.__unit === unitA);
    }

    private static function test_multi_unit_perAttach_scope_隔离_双订阅():Void {
        trace("--- multi-unit: A/B 都订阅，各自 initObject 指向自己的 unit ---");
        var unitA = makeMockUnit("正常", "男");
        unitA.syncRefs["刀_引用:ready"] = true;
        var mcA = makeMockMC();

        var unitB = makeMockUnit("正常", "男");
        unitB.syncRefs["刀_引用:ready"] = true;
        var mcB = makeMockMC();

        DressupReferenceManager.doConfig(mcA, "_shared_test_skin", "装扮", "刀_引用", unitA);
        DressupReferenceManager.doConfig(mcB, "_shared_test_skin", "装扮", "刀_引用", unitB);

        Object.registerClass("_shared_test_skin", null);

        // 关键：A 的 initObject.__unit === unitA, B 的 === unitB（非串扰）
        assertNotNull("unitA initObject 已注入", mcA.attachLog[0].initObject);
        assertNotNull("unitB initObject 已注入", mcB.attachLog[0].initObject);
        assertTrue("unitA initObject.__unit === unitA", mcA.attachLog[0].initObject.__unit === unitA);
        assertTrue("unitB initObject.__unit === unitB", mcB.attachLog[0].initObject.__unit === unitB);
        assertTrue("A/B initObject 是不同对象", mcA.attachLog[0].initObject !== mcB.attachLog[0].initObject);
    }

    // ====================================================================
    // SkinReadyClass.onLoad 防御性检查
    // 直接通过 prototype.onLoad.apply 调用，避开 attachMovie/displayList 路径
    // ====================================================================

    private static function test_SkinReadyClass_onLoad_unit_为null时不crash():Void {
        trace("--- SkinReadyClass.onLoad: __unit 为 null ---");
        var fakeSkin = { __unit: null, __publishKey: "x_引用:ready" };
        SkinReadyClass.prototype.onLoad.apply(fakeSkin);
        assertTrue("调用未抛错", true);
    }

    private static function test_SkinReadyClass_onLoad_unit已卸载时不publish():Void {
        trace("--- SkinReadyClass.onLoad: unit._parent 为 null（已卸载） ---");
        var publishLog = [];
        var fakeUnit = {
            _parent: null,
            dispatcher: {
                publish: function(k, u) { publishLog.push({key: k, unit: u}); }
            }
        };
        var fakeSkin = { __unit: fakeUnit, __publishKey: "x_引用:ready" };
        SkinReadyClass.prototype.onLoad.apply(fakeSkin);
        assertEquals("publish 未被调用", 0, publishLog.length);
    }

    private static function test_SkinReadyClass_onLoad_publishKey缺失时不publish():Void {
        trace("--- SkinReadyClass.onLoad: __publishKey 缺失 ---");
        var publishLog = [];
        var fakeUnit = {
            _parent: {},
            dispatcher: { publish: function(k, u) { publishLog.push(k); } }
        };
        var fakeSkin = { __unit: fakeUnit };  // __publishKey 缺失
        SkinReadyClass.prototype.onLoad.apply(fakeSkin);
        assertEquals("publish 未被调用", 0, publishLog.length);
    }

    private static function test_SkinReadyClass_onLoad_alive时正常publish():Void {
        trace("--- SkinReadyClass.onLoad: 全条件满足，正常 publish ---");
        var publishLog = [];
        var fakeUnit = {
            _parent: {},
            dispatcher: {
                publish: function(k, u) { publishLog.push({key: k, unit: u}); }
            }
        };
        var fakeSkin = { __unit: fakeUnit, __publishKey: "x_引用:ready" };
        SkinReadyClass.prototype.onLoad.apply(fakeSkin);
        assertEquals("publish 被调用 1 次", 1, publishLog.length);
        assertEquals("publish key 正确", "x_引用:ready", publishLog[0].key);
        assertTrue("publish unit 是 fakeUnit", publishLog[0].unit === fakeUnit);
    }

    // ====================================================================
    // Benchmark
    // ====================================================================

    private static function bench(name:String, fn:Function, iterations:Number):Void {
        var t0:Number = getTimer();
        for (var i:Number = 0; i < iterations; i++) {
            fn();
        }
        var dt:Number = getTimer() - t0;
        var avgUs:Number = (dt * 1000) / iterations;
        // AS2 Number 无 toFixed，手动两位精度
        var avgUsStr:String = String(Math.round(avgUs * 100) / 100);
        trace("[BENCH] " + name + " : " + iterations + " iter,  total=" + dt + "ms,  avg=" + avgUsStr + "us");
    }

    public static function runBench():Void {
        trace("================================================================");
        trace("DressupReferenceManager Benchmarks");
        trace("================================================================");

        // baseline: empty wrapper（衡量 fn() 调用本身的开销，对照基线）
        bench("(baseline empty wrapper)", function() {}, 100000);

        // bench 1: doConfig，未订阅 deferred，纯逻辑路径
        var u1 = makeMockUnit("正常", "男");
        var m1 = makeMockMC();
        bench("doConfig (no deferred, no fallback)", function() {
            DressupReferenceManager.doConfig(m1, "skin", "装扮", "身体_引用", u1);
        }, 50000);

        // bench 2: doConfig，订阅 deferred，包含真实 Object.registerClass 双调用
        var u2 = makeMockUnit("正常", "男");
        u2.syncRefs["刀_引用:ready"] = true;
        var m2 = makeMockMC();
        bench("doConfig (deferred, real registerClass x2)", function() {
            DressupReferenceManager.doConfig(m2, "_bench_skin_a", "装扮", "刀_引用", u2);
        }, 20000);

        // bench 3: doConfig，女性 fallback 路径（attachMovie 双调用）
        var u3 = makeMockUnit("正常", "女");
        var m3 = makeMockMC();
        m3.failLinkages["primary_skin"] = true;
        bench("doConfig (female fallback, no deferred)", function() {
            DressupReferenceManager.doConfig(m3, "primary_skin", "装扮", "身体_引用", u3);
        }, 20000);

        // bench 4: attach（含 registry 写入 + doConfig）
        // 每次 attach 都会增加 registry entry，counter 不断递增 → 单测无意义
        // 改用：每次 fresh unit + 单次 attach，代价 = setup + attach
        bench("attach (fresh unit, 1 attach)", function() {
            var u = makeMockUnit("正常", "男");
            var mm = makeMockMC();
            wireParentChain(mm, u);
            DressupReferenceManager.attach(mm, "skin", "装扮", "身体_引用");
        }, 10000);

        // bench 5: refreshAll，11 entries（模拟主角真实装备数）
        var u5 = makeMockUnit("正常", "男");
        var refs = ["头部_引用", "身体_引用", "上臂_引用", "右下臂_引用", "左下臂_引用",
                    "屁股_引用", "右大腿_引用", "左大腿_引用", "小腿_引用", "脚_引用", "刀_引用"];
        for (var i:Number = 0; i < refs.length; i++) {
            var mm = makeMockMC();
            wireParentChain(mm, u5);
            DressupReferenceManager.attach(mm, "skin", "装扮", refs[i]);
            u5[refs[i].split("_引用")[0]] = "skin";  // skinConfig 来源
        }
        u5["刀_装扮"] = "skin";
        bench("refreshAll (11 entries, no deferred)", function() {
            DressupReferenceManager.refreshAll(u5);
        }, 5000);

        trace("================================================================");
    }

    // ====================================================================
    // Runner
    // ====================================================================

    public static function runAll():Void {
        trace("================================================================");
        trace("DressupReferenceManager Test Suite");
        trace("================================================================");

        var t0:Number = getTimer();
        testCount = 0;
        passedTests = 0;
        failedTests = 0;

        test_doConfig_巨拳模式排除右下臂();
        test_doConfig_单臂巨拳不排除左下臂();
        test_doConfig_refNameAliases_小腿1解析为小腿();
        test_doConfig_女性fallback触发();
        test_doConfig_男性无fallback();
        test_doConfig_同步publish条件触发();
        test_doConfig_deferred路径initObject注入();
        test_doConfig_deferred_fallback路径同样注入initObject();
        test_doConfig_未订阅deferred时不传initObject();
        test_attach_数字后缀regKey生成();
        test_attach_失效MC复用regKey();
        test_attach_skinKeyOverrides武器走装扮后缀();
        test_refreshAll_标记与组级事件();
        test_refreshAll_dead_entry清理与live同处理();
        test_multi_unit_perAttach_scope_隔离_异步订阅();
        test_multi_unit_perAttach_scope_隔离_双订阅();
        test_SkinReadyClass_onLoad_unit_为null时不crash();
        test_SkinReadyClass_onLoad_unit已卸载时不publish();
        test_SkinReadyClass_onLoad_publishKey缺失时不publish();
        test_SkinReadyClass_onLoad_alive时正常publish();

        var dt:Number = getTimer() - t0;
        trace("================================================================");
        trace("Result: " + passedTests + "/" + testCount + " passed, " + failedTests + " failed  (" + dt + " ms)");
        trace("================================================================");
    }
}
