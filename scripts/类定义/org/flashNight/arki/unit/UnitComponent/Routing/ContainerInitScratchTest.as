import org.flashNight.arki.unit.UnitComponent.Routing.*;

/**
 * ContainerInitScratch Test Suite
 *
 * 覆盖：
 * - assembleFromMap 纯函数：对每个 fieldMap 验证 dst 字段全装配 + 指向预期 _root.X.Y 源
 * - getPublic / getUnarmed / getWeapon trampoline：连续调用返回同一 scratch + transform 刷新
 *
 * 注意 trampoline 状态：testloader 在 boot 后跑，若生产代码已先调用过 getXxx，
 * trampoline 已被替换为 fast-path closure；此时测试退化为只验证 "fast-path 返回同一 scratch"
 * 与 "transform 字段被刷新"。装配契约由 assembleFromMap 测试独立保证。
 *
 * Fake container：plain object 模拟 MovieClip 的 _x/_y/_xscale/_yscale。
 */
class org.flashNight.arki.unit.UnitComponent.Routing.ContainerInitScratchTest {

    private static var testCount:Number = 0;
    private static var passedTests:Number = 0;
    private static var failedTests:Number = 0;

    private static function assertEquals(name:String, expected, actual):Void {
        testCount++;
        if (expected === actual) {
            passedTests++;
            trace("  [PASS] " + name);
        } else {
            failedTests++;
            trace("  [FAIL] " + name + " (exp=" + expected + " act=" + actual + ")");
        }
    }

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

    private static function assertSame(name:String, expected, actual):Void {
        testCount++;
        if (expected === actual) {
            passedTests++;
            trace("  [PASS] " + name);
        } else {
            failedTests++;
            trace("  [FAIL] " + name + " (not same ref)");
        }
    }

    private static function makeContainer(x:Number, y:Number, xs:Number, ys:Number) {
        return {
            _x: x, _y: y, _xscale: xs, _yscale: ys
        };
    }

    public static function runAll():Boolean {
        trace("================================================================");
        trace("ContainerInitScratch Test Suite");
        trace("================================================================");

        var t0:Number = getTimer();
        testCount = 0;
        passedTests = 0;
        failedTests = 0;

        // assembleFromMap 装配契约（纯函数路径）
        testAssembleFromMap_TransformWritten();
        testAssembleFromMap_DynamicManFlag();
        testAssembleFromMap_PUBLIC_FieldsAndSources();
        testAssembleFromMap_UNARMED_FieldsAndSources();
        testAssembleFromMap_WEAPON_FieldsAndSources();
        testFieldMap_NoEmptyDstKeys();

        // sources 注入 + 反向 sentinel 断言（与 fieldMap 互证，独立于 _root）
        testAssembleFromMap_SourcesInjection();
        testAssembleFromMap_DefaultSourcesFallbackToRoot();
        testFieldMap_CriticalSourceContracts();

        // trampoline 行为（同一 scratch + transform 刷新）
        testGetPublic_SameScratchOnRepeatedCall();
        testGetUnarmed_SameScratchOnRepeatedCall();
        testGetWeapon_SameScratchOnRepeatedCall();

        var elapsed:Number = getTimer() - t0;
        trace("================================================================");
        trace("Results: " + passedTests + "/" + testCount + " passed, "
              + failedTests + " failed (" + elapsed + "ms)");
        trace("================================================================");
        return failedTests == 0;
    }

    // ====================================================================
    // assembleFromMap：纯函数装配
    // ====================================================================

    private static function testAssembleFromMap_TransformWritten():Void {
        trace("\n--- testAssembleFromMap_TransformWritten ---");
        var c = makeContainer(7, 13, 80, -80);
        var s = ContainerInitScratch.assembleFromMap(c, RoutingFieldMap.PUBLIC_FIELDS);

        assertEquals("_x", 7, s._x);
        assertEquals("_y", 13, s._y);
        assertEquals("_xscale", 80, s._xscale);
        assertEquals("_yscale", -80, s._yscale);
    }

    private static function testAssembleFromMap_DynamicManFlag():Void {
        trace("\n--- testAssembleFromMap_DynamicManFlag ---");
        var c = makeContainer(0, 0, 100, 100);
        var s1 = ContainerInitScratch.assembleFromMap(c, RoutingFieldMap.PUBLIC_FIELDS);
        var s2 = ContainerInitScratch.assembleFromMap(c, RoutingFieldMap.UNARMED_FIELDS);
        var s3 = ContainerInitScratch.assembleFromMap(c, RoutingFieldMap.WEAPON_FIELDS);

        assertEquals("PUBLIC __isDynamicMan", true, s1.__isDynamicMan);
        assertEquals("UNARMED __isDynamicMan", true, s2.__isDynamicMan);
        assertEquals("WEAPON __isDynamicMan", true, s3.__isDynamicMan);
    }

    private static function testAssembleFromMap_PUBLIC_FieldsAndSources():Void {
        trace("\n--- testAssembleFromMap_PUBLIC_FieldsAndSources ---");
        var c = makeContainer(0, 0, 100, 100);
        var s = ContainerInitScratch.assembleFromMap(c, RoutingFieldMap.PUBLIC_FIELDS);
        var fields = RoutingFieldMap.PUBLIC_FIELDS;

        for (var i:Number = 0; i < fields.length; i++) {
            var entry = fields[i];
            var dst = entry[0];
            var src = _root[entry[1]][entry[2]];
            assertSame("PUBLIC[" + dst + "] === _root." + entry[1] + "." + entry[2], src, s[dst]);
        }
    }

    private static function testAssembleFromMap_UNARMED_FieldsAndSources():Void {
        trace("\n--- testAssembleFromMap_UNARMED_FieldsAndSources ---");
        var c = makeContainer(0, 0, 100, 100);
        var s = ContainerInitScratch.assembleFromMap(c, RoutingFieldMap.UNARMED_FIELDS);
        var fields = RoutingFieldMap.UNARMED_FIELDS;

        for (var i:Number = 0; i < fields.length; i++) {
            var entry = fields[i];
            var dst = entry[0];
            var src = _root[entry[1]][entry[2]];
            assertSame("UNARMED[" + dst + "] === _root." + entry[1] + "." + entry[2], src, s[dst]);
        }
    }

    private static function testAssembleFromMap_WEAPON_FieldsAndSources():Void {
        trace("\n--- testAssembleFromMap_WEAPON_FieldsAndSources ---");
        var c = makeContainer(0, 0, 100, 100);
        var s = ContainerInitScratch.assembleFromMap(c, RoutingFieldMap.WEAPON_FIELDS);
        var fields = RoutingFieldMap.WEAPON_FIELDS;

        for (var i:Number = 0; i < fields.length; i++) {
            var entry = fields[i];
            var dst = entry[0];
            var src = _root[entry[1]][entry[2]];
            assertSame("WEAPON[" + dst + "] === _root." + entry[1] + "." + entry[2], src, s[dst]);
        }
    }

    private static function testFieldMap_NoEmptyDstKeys():Void {
        trace("\n--- testFieldMap_NoEmptyDstKeys ---");
        var maps = [
            ["PUBLIC", RoutingFieldMap.PUBLIC_FIELDS],
            ["UNARMED", RoutingFieldMap.UNARMED_FIELDS],
            ["WEAPON", RoutingFieldMap.WEAPON_FIELDS]
        ];
        for (var i:Number = 0; i < maps.length; i++) {
            var label:String = maps[i][0];
            var fields = maps[i][1];
            assertTrue(label + " 非空", fields.length > 0);
            for (var j:Number = 0; j < fields.length; j++) {
                var entry = fields[j];
                assertTrue(label + "[" + j + "].dst 非空字符串", typeof entry[0] === "string" && entry[0].length > 0);
                assertTrue(label + "[" + j + "].srcRoot 非空字符串", typeof entry[1] === "string" && entry[1].length > 0);
                assertTrue(label + "[" + j + "].srcKey 非空字符串", typeof entry[2] === "string" && entry[2].length > 0);
            }
        }
    }

    // ====================================================================
    // sources 注入 + 反向 sentinel 断言
    // ====================================================================

    /**
     * sources 注入功能本身：自构 fields + fakeSources，sentinel 字符串作为期望值。
     * 这一组不依赖 _root，也不依赖 RoutingFieldMap 的具体内容，纯验证 assembleFromMap
     * 的"按 fields 表把 sources[srcRoot][srcKey] 拷到 out[dst]"契约。
     */
    private static function testAssembleFromMap_SourcesInjection():Void {
        trace("\n--- testAssembleFromMap_SourcesInjection ---");
        var c = makeContainer(0, 0, 100, 100);
        var fields:Array = [
            ["alpha", "rootA", "k1"],
            ["beta",  "rootA", "k2"],
            ["gamma", "rootB", "k1"]
        ];
        var sources:Object = {
            rootA: { k1: "SENTINEL_A_k1", k2: "SENTINEL_A_k2" },
            rootB: { k1: "SENTINEL_B_k1" }
        };
        var s = ContainerInitScratch.assembleFromMap(c, fields, sources);

        assertEquals("alpha → sources.rootA.k1", "SENTINEL_A_k1", s.alpha);
        assertEquals("beta → sources.rootA.k2",  "SENTINEL_A_k2", s.beta);
        assertEquals("gamma → sources.rootB.k1", "SENTINEL_B_k1", s.gamma);
        // sources 注入不影响 transform / __isDynamicMan
        assertEquals("__isDynamicMan 仍为 true", true, s.__isDynamicMan);
        assertEquals("_x 来自 container", 0, s._x);
    }

    /**
     * 不传 sources（或传 undefined）时退化到 _root：与原 _root 路径行为一致。
     */
    private static function testAssembleFromMap_DefaultSourcesFallbackToRoot():Void {
        trace("\n--- testAssembleFromMap_DefaultSourcesFallbackToRoot ---");
        var c = makeContainer(0, 0, 100, 100);
        var fields:Array = [["dst1", "技能函数", "攻击时移动"]];

        var sNoArg = ContainerInitScratch.assembleFromMap(c, fields, undefined);
        assertSame("不传 sources → fallback _root", _root.技能函数.攻击时移动, sNoArg.dst1);
    }

    /**
     * 关键映射人工 audit 表（与 RoutingFieldMap 互证）。
     *
     * 这些是字段语义文档里明确定义的"独立来源"：如果 RoutingFieldMap 里 srcRoot/srcKey
     * 写错（typo / 改错 dict 名 / 漏掉 weapon 覆盖），下列断言会立刻 FAIL。原 PUBLIC/
     * UNARMED/WEAPON_FieldsAndSources 测试是"测试与被测代码同读 fieldMap"，对 typo
     * 不敏感；这组用 sentinel 注入做反向断言，弥补盲点。
     *
     * 维护原则：
     *   - 仅断言 _关键_ 易错点，不复制整个 fieldMap
     *   - 修改 RoutingFieldMap 时，仅在变更这些"独立来源"语义时才需同步本测试
     */
    private static function testFieldMap_CriticalSourceContracts():Void {
        trace("\n--- testFieldMap_CriticalSourceContracts ---");
        var c = makeContainer(0, 0, 100, 100);

        // 构造 sentinel sources：每个 (srcRoot, srcKey) 一个独有字符串
        var sources:Object = {};
        sources["技能函数"] = {
            攻击时移动:    "SKILL_移动",
            兵器攻击时移动:"SKILL_兵器移动",
            获取移动方向:  "SKILL_方向",
            回旋踢可派生搓招:"SKILL_回旋踢派生"
        };
        sources["空手攻击路由"] = {
            攻击时移动:    "UNARMED_移动",
            获取移动方向:  "UNARMED_方向"  // 故意填值，但 fieldMap 不会读它
        };

        var sPublic  = ContainerInitScratch.assembleFromMap(c, RoutingFieldMap.PUBLIC_FIELDS,  sources);
        var sUnarmed = ContainerInitScratch.assembleFromMap(c, RoutingFieldMap.UNARMED_FIELDS, sources);
        var sWeapon  = ContainerInitScratch.assembleFromMap(c, RoutingFieldMap.WEAPON_FIELDS,  sources);

        // PUBLIC：所有 src 都来自 技能函数
        assertEquals("PUBLIC.攻击时移动 ← 技能函数.攻击时移动",
            "SKILL_移动", sPublic["攻击时移动"]);
        assertEquals("PUBLIC.攻击时后退移动 ← 技能函数.攻击时移动（同源）",
            "SKILL_移动", sPublic["攻击时后退移动"]);
        assertEquals("PUBLIC.获取移动方向 ← 技能函数.获取移动方向",
            "SKILL_方向", sPublic["获取移动方向"]);

        // UNARMED：攻击时移动 必须走 空手攻击路由（不是 技能函数）
        assertEquals("UNARMED.攻击时移动 ← 空手攻击路由.攻击时移动",
            "UNARMED_移动", sUnarmed["攻击时移动"]);
        assertEquals("UNARMED.攻击时后退移动 ← 空手攻击路由.攻击时移动（同源）",
            "UNARMED_移动", sUnarmed["攻击时后退移动"]);
        // UNARMED.获取移动方向 是关键易错点：来自 技能函数 而非 空手攻击路由
        assertEquals("UNARMED.获取移动方向 ← 技能函数（而非 空手攻击路由）",
            "SKILL_方向", sUnarmed["获取移动方向"]);
        assertEquals("UNARMED.回旋踢可派生搓招 ← 技能函数.回旋踢可派生搓招",
            "SKILL_回旋踢派生", sUnarmed["回旋踢可派生搓招"]);

        // WEAPON：攻击时移动 用 兵器攻击时移动 覆盖；攻击时后退移动 沿用 base
        assertEquals("WEAPON.攻击时移动 ← 技能函数.兵器攻击时移动（兵器覆盖）",
            "SKILL_兵器移动", sWeapon["攻击时移动"]);
        assertEquals("WEAPON.攻击时后退移动 ← 技能函数.攻击时移动（沿用 base 而非兵器版）",
            "SKILL_移动", sWeapon["攻击时后退移动"]);
        assertEquals("WEAPON.获取移动方向 ← 技能函数.获取移动方向",
            "SKILL_方向", sWeapon["获取移动方向"]);
    }

    // ====================================================================
    // trampoline：连续调用同一 scratch + transform 刷新
    // ====================================================================

    private static function testGetPublic_SameScratchOnRepeatedCall():Void {
        trace("\n--- testGetPublic_SameScratchOnRepeatedCall ---");
        var c1 = makeContainer(11, 22, 50, 50);
        var s1 = ContainerInitScratch.getPublic(c1);

        var c2 = makeContainer(33, 44, 200, -200);
        var s2 = ContainerInitScratch.getPublic(c2);

        assertSame("两次调用返回同一 scratch", s1, s2);
        assertEquals("_x 已刷新", 33, s2._x);
        assertEquals("_y 已刷新", 44, s2._y);
        assertEquals("_xscale 已刷新", 200, s2._xscale);
        assertEquals("_yscale 已刷新", -200, s2._yscale);
        assertEquals("__isDynamicMan 仍为 true", true, s2.__isDynamicMan);
        assertSame("攻击时移动 仍指向 _root.技能函数.攻击时移动",
            _root.技能函数.攻击时移动, s2.攻击时移动);
    }

    private static function testGetUnarmed_SameScratchOnRepeatedCall():Void {
        trace("\n--- testGetUnarmed_SameScratchOnRepeatedCall ---");
        var c1 = makeContainer(5, 6, 70, 70);
        var s1 = ContainerInitScratch.getUnarmed(c1);

        var c2 = makeContainer(99, 88, 25, 25);
        var s2 = ContainerInitScratch.getUnarmed(c2);

        assertSame("两次调用返回同一 scratch", s1, s2);
        assertEquals("_x 已刷新", 99, s2._x);
        assertEquals("_y 已刷新", 88, s2._y);
        assertSame("攻击时移动 仍指向 _root.空手攻击路由.攻击时移动",
            _root.空手攻击路由.攻击时移动, s2.攻击时移动);
        assertSame("获取移动方向 仍指向 _root.技能函数.获取移动方向",
            _root.技能函数.获取移动方向, s2.获取移动方向);
    }

    private static function testGetWeapon_SameScratchOnRepeatedCall():Void {
        trace("\n--- testGetWeapon_SameScratchOnRepeatedCall ---");
        var c1 = makeContainer(1, 2, 100, 100);
        var s1 = ContainerInitScratch.getWeapon(c1);

        var c2 = makeContainer(77, 66, 33, 33);
        var s2 = ContainerInitScratch.getWeapon(c2);

        assertSame("两次调用返回同一 scratch", s1, s2);
        assertEquals("_x 已刷新", 77, s2._x);
        assertEquals("_y 已刷新", 66, s2._y);
        assertSame("攻击时移动 兵器覆盖 = _root.技能函数.兵器攻击时移动",
            _root.技能函数.兵器攻击时移动, s2.攻击时移动);
        assertSame("攻击时后退移动 沿用 base = _root.技能函数.攻击时移动",
            _root.技能函数.攻击时移动, s2.攻击时后退移动);
    }
}
