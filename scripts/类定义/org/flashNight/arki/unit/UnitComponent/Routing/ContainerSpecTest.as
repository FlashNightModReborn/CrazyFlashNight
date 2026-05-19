import org.flashNight.arki.unit.UnitComponent.Routing.*;

/**
 * ContainerSpec Test Suite
 *
 * 覆盖：
 *   - buildLinkageName 4 kind × 多个 actionName
 *   - getLinkagePrefix 4 kind + 未知 kind → undefined
 *   - getMissingFallback 4 kind 现状（unarmed/weapon → ABORT，skill/battleSkill → SILENT_CONTINUE）
 *   - allKinds() 完整性：4 kind 都能 lookup 到非空 prefix + 非空 fallback
 *
 * 后两组（fallback / 完整性遍历）是反向断言："以后加新 kind 必须扩 ContainerSpec
 * 的注册表，否则 fallback/prefix 返回 undefined → 测试立刻 FAIL"。
 */
class org.flashNight.arki.unit.UnitComponent.Routing.ContainerSpecTest {

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

    public static function runAll():Boolean {
        trace("================================================================");
        trace("ContainerSpec Test Suite");
        trace("================================================================");

        var t0:Number = getTimer();
        testCount = 0;
        passedTests = 0;
        failedTests = 0;

        testBuildLinkageName_Unarmed();
        testBuildLinkageName_Weapon();
        testBuildLinkageName_Skill();
        testBuildLinkageName_BattleSkill();
        testGetLinkagePrefix_AllKinds();
        testGetLinkagePrefix_UnknownKind();
        testGetMissingFallback_Current();
        testGetMissingFallback_UnknownKind();
        testAllKinds_AreLookupable();
        testKindsExhaustive_BothLookups();

        var elapsed:Number = getTimer() - t0;
        trace("================================================================");
        trace("Results: " + passedTests + "/" + testCount + " passed, "
              + failedTests + " failed (" + elapsed + "ms)");
        trace("================================================================");
        return failedTests == 0;
    }

    // ====================================================================
    // buildLinkageName
    // ====================================================================

    private static function testBuildLinkageName_Unarmed():Void {
        trace("\n--- testBuildLinkageName_Unarmed ---");
        assertEquals("unarmed + 普通拳",
            "空手攻击容器-普通拳",
            ContainerSpec.buildLinkageName(ContainerSpec.KIND_UNARMED, "普通拳"));
    }

    private static function testBuildLinkageName_Weapon():Void {
        trace("\n--- testBuildLinkageName_Weapon ---");
        assertEquals("weapon + 通用兵器攻击",
            "兵器攻击容器-通用兵器攻击",
            ContainerSpec.buildLinkageName(ContainerSpec.KIND_WEAPON, "通用兵器攻击"));
    }

    private static function testBuildLinkageName_Skill():Void {
        trace("\n--- testBuildLinkageName_Skill ---");
        assertEquals("skill + 升龙拳",
            "技能容器-升龙拳",
            ContainerSpec.buildLinkageName(ContainerSpec.KIND_SKILL, "升龙拳"));
    }

    private static function testBuildLinkageName_BattleSkill():Void {
        trace("\n--- testBuildLinkageName_BattleSkill ---");
        assertEquals("battleSkill + 双刀变长柄",
            "战技容器-双刀变长柄",
            ContainerSpec.buildLinkageName(ContainerSpec.KIND_BATTLE_SKILL, "双刀变长柄"));
    }

    // ====================================================================
    // getLinkagePrefix
    // ====================================================================

    private static function testGetLinkagePrefix_AllKinds():Void {
        trace("\n--- testGetLinkagePrefix_AllKinds ---");
        assertEquals("unarmed",     "空手攻击容器", ContainerSpec.getLinkagePrefix(ContainerSpec.KIND_UNARMED));
        assertEquals("weapon",      "兵器攻击容器", ContainerSpec.getLinkagePrefix(ContainerSpec.KIND_WEAPON));
        assertEquals("skill",       "技能容器",     ContainerSpec.getLinkagePrefix(ContainerSpec.KIND_SKILL));
        assertEquals("battleSkill", "战技容器",     ContainerSpec.getLinkagePrefix(ContainerSpec.KIND_BATTLE_SKILL));
    }

    private static function testGetLinkagePrefix_UnknownKind():Void {
        trace("\n--- testGetLinkagePrefix_UnknownKind ---");
        assertEquals("未知 kind → undefined",
            undefined,
            ContainerSpec.getLinkagePrefix("bogus"));
    }

    // ====================================================================
    // getMissingFallback
    // ====================================================================

    private static function testGetMissingFallback_Current():Void {
        trace("\n--- testGetMissingFallback_Current ---");
        // 当前现状（documented in ContainerSpec）：
        // unarmed/weapon → ABORT；skill/battleSkill → SILENT_CONTINUE
        assertEquals("unarmed → ABORT",
            ContainerSpec.FALLBACK_ABORT,
            ContainerSpec.getMissingFallback(ContainerSpec.KIND_UNARMED));
        assertEquals("weapon → ABORT",
            ContainerSpec.FALLBACK_ABORT,
            ContainerSpec.getMissingFallback(ContainerSpec.KIND_WEAPON));
        assertEquals("skill → SILENT_CONTINUE",
            ContainerSpec.FALLBACK_SILENT_CONTINUE,
            ContainerSpec.getMissingFallback(ContainerSpec.KIND_SKILL));
        assertEquals("battleSkill → SILENT_CONTINUE",
            ContainerSpec.FALLBACK_SILENT_CONTINUE,
            ContainerSpec.getMissingFallback(ContainerSpec.KIND_BATTLE_SKILL));
    }

    private static function testGetMissingFallback_UnknownKind():Void {
        trace("\n--- testGetMissingFallback_UnknownKind ---");
        assertEquals("未知 kind → undefined",
            undefined,
            ContainerSpec.getMissingFallback("bogus"));
    }

    // ====================================================================
    // allKinds — 完整性反向断言
    // ====================================================================

    private static function testAllKinds_AreLookupable():Void {
        trace("\n--- testAllKinds_AreLookupable ---");
        var kinds:Array = ContainerSpec.allKinds();
        assertEquals("allKinds 长度 = 4", 4, kinds.length);
    }

    /**
     * 反向断言：allKinds 里的每个 kind 都必须能 lookup 到非空 prefix + 非空 fallback。
     * 任意新增 kind 必须同步注册到 getLinkagePrefix / getMissingFallback / allKinds，
     * 否则本测试 FAIL — 防止"加了 KIND 常量但忘了在 switch 里加分支"。
     */
    private static function testKindsExhaustive_BothLookups():Void {
        trace("\n--- testKindsExhaustive_BothLookups ---");
        var kinds:Array = ContainerSpec.allKinds();
        for (var i:Number = 0; i < kinds.length; i++) {
            var k:String = kinds[i];
            var prefix:String = ContainerSpec.getLinkagePrefix(k);
            var fallback:String = ContainerSpec.getMissingFallback(k);
            assertTrue("kind=" + k + " 有 linkagePrefix",
                prefix != undefined && prefix.length > 0);
            assertTrue("kind=" + k + " 有 missingFallback",
                fallback != undefined && fallback.length > 0);
        }
    }
}
