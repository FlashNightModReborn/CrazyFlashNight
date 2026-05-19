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
