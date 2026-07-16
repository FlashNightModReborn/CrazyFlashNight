import org.flashNight.arki.skill.SkillLoadoutService;

/** SkillLoadoutService 领域与坏档门回归。 */
class org.flashNight.arki.skill.SkillLoadoutServiceTest {
    private static var passed:Number = 0;
    private static var failed:Number = 0;

    public static function runAllTests():Void {
        passed = failed = 0;
        testServiceNotReady();
        testSnapshotShortTableIsReadOnly();
        testExternalDriftAdvancesRevision();
        testDescriptorDoesNotNeedHud();
        testDuplicateProjectionIsUnique();
        testDuplicateReleaseFailsClosed();
        testInvalidBooleanDiagnostic();
        testCorruptNumericProjectionStaysWireBounded();
        testPurePassiveShadowIgnoredBySignature();
        testTailDataBlocksWrites();
        testEquipAndDirty();
        testEquipNoop();
        testNormalModeRejectsDuplicateSlot();
        testEasyModeAllowsDuplicateSlot();
        testAtomicReplacement();
        testMoveSlotToEmpty();
        testMoveSlotSwapsOccupied();
        testMoveSlotNoop();
        testMoveSlotRejectsEmptyOrCorruptSource();
        testMutationDoesNotNormalizeUnrelatedRows();
        testUnequipKeepsEasyDuplicateEnabled();
        testUnknownSlotSafeUnequip();
        testDuplicateSlotUnequipBlocked();
        testBadSlotOccupantMatrix();
        testPurePassiveCannotEquip();
        testIllegalPurePassiveSlotIsSafeToClear();
        testSetPassive();
        testPassiveShadowRoundTrip();
        testPurePassiveShadowRepresentationsAreIgnored();
        testMixedPassiveFollowsSlots();
        testReorderAndStableLoadout();
        testReorderNoop();
        testReorderRejectsMalformedTarget();
        testReorderRejectsUnknownTarget();
        testNormalReorderRejectsEquippedTarget();
        testEasyReorderRejectsEquippedTarget();
        testStaleRevisionZeroWrite();
        testInitialLearnMaterializesShortRow();
        testInitialLearnUsesCanonicalPurePassive();
        testInitialLearnMustBeLevelOne();
        testUpgradeKeepsRowIdentity();
        testFullTableRejectsLearn();
        testDomainFailureRollsBack();
        testLearnDomainFailureRollsBackSkillPoints();
        testCooldownEffectsAreIndependent();
        testMoveShotZeroAndTenBoundary();
        testQuickHudRendererRebuildsReplaceAndClear();
        testAllOptionalRenderersMissing();
        SkillLoadoutService.testOnlyReset();
        trace("SkillLoadoutServiceTest Tests Passed: " + passed);
        trace("SkillLoadoutServiceTest Tests Failed: " + failed);
    }

    private static function testServiceNotReady():Void {
        SkillLoadoutService.testOnlyUseRoot({});
        var before:Number = SkillLoadoutService.getRevision();
        var result:Object = SkillLoadoutService.synchronize();
        check(!result.success && result.error == "service_not_ready" && before == 0, "service_not_ready creates no revision");
    }

    private static function testSnapshotShortTableIsReadOnly():Void {
        var r:Object = fixture(2);
        var ref:Array = r.主角技能表;
        var length:Number = ref.length;
        var snap:Object = SkillLoadoutService.buildSnapshot("manage", null);
        check(snap.success && r.主角技能表 === ref && ref.length == length, "short snapshot preserves outer reference and length");
    }

    private static function testExternalDriftAdvancesRevision():Void {
        var r:Object = fixture(80);
        var rev:Number = SkillLoadoutService.getRevision();
        r.主角技能表[0][1] = 2;
        check(SkillLoadoutService.getRevision() == rev + 1, "legacy root drift advances revision once");
    }

    private static function testDescriptorDoesNotNeedHud():Void {
        var r:Object = fixture(80); learn(r, 0, "闪现", 3); r.快捷技能栏1 = "闪现";
        r.玩家信息界面 = null;
        var d:Object = SkillLoadoutService.getSlotDescriptor(1);
        check(d.equipped && d.skillKey == "闪现" && d.level == 3 && d.mp == 10 && d.cooldownMs == 2000, "descriptor reads root and metadata without HUD");
    }

    private static function testDuplicateProjectionIsUnique():Void {
        var r:Object = fixture(80); learn(r, 0, "闪现", 1); learn(r, 4, "闪现", 2);
        var snap:Object = SkillLoadoutService.buildSnapshot("manage", null);
        var count:Number = countLearned(snap.learned, "闪现");
        check(count == 1 && findLearned(snap.learned, "闪现").stateHealth == "duplicate", "duplicate rows project one blocked learned entry");
    }

    private static function testDuplicateReleaseFailsClosed():Void {
        var r:Object = fixture(80); learn(r, 0, "闪现", 1); learn(r, 2, "闪现", 1);
        check(!SkillLoadoutService.isReleaseAllowed("闪现"), "duplicate learned skill cannot pass release guard");
    }

    private static function testInvalidBooleanDiagnostic():Void {
        var r:Object = fixture(80); learn(r, 0, "闪现", 1); r.主角技能表[0][4] = "ture";
        var item:Object = findLearned(SkillLoadoutService.buildSnapshot("manage", null).learned, "闪现");
        check(item.stateHealth == "invalid" && item.writeBlocked, "unknown legacy boolean is diagnosed without coercion");
    }

    private static function testCorruptNumericProjectionStaysWireBounded():Void {
        var r:Object = fixture(80); learn(r, 0, "闪现", 999999999); r.快捷技能栏1 = "闪现";
        r.技能表对象.闪现.MP = Number.POSITIVE_INFINITY; r.技能表对象.闪现.CD = 999999999;
        r.技能表对象.闪现.Type = "武术" + String.fromCharCode(1); r.技能表对象.闪现.Description = "描述" + String.fromCharCode(127);
        var snap:Object = SkillLoadoutService.buildSnapshot("manage", null); var item:Object = findLearned(snap.learned, "闪现");
        check(snap.success && item.level == 9999 && item.mp == 0 && item.cooldownMs == 86400000 && item.type == "武术"
            && item.description == "描述" && item.stateHealth == "invalid" && snap.loadout[0].level == 9999
            && snap.loadout[0].stateHealth == "invalid" && snap.loadout[0].writeBlocked,
            "corrupt learned numbers and control text remain diagnosable while every wire field stays Host-bounded");
    }

    private static function testPurePassiveShadowIgnoredBySignature():Void {
        var r:Object = fixture(80); learn(r, 0, "内力爆发", 1); r.主角技能表[0][2] = true;
        var rev:Number = SkillLoadoutService.getRevision();
        r.主角技能表[0][2] = "false";
        check(SkillLoadoutService.getRevision() == rev, "pure-passive [2] shadow does not churn revision");
    }

    private static function testTailDataBlocksWrites():Void {
        var r:Object = fixture(81); learn(r, 0, "闪现", 1); r.主角技能表[80] = ["尾部技能", 1, false, "武术", false];
        var result:Object = SkillLoadoutService.equip("闪现", 1, SkillLoadoutService.getRevision());
        check(!result.success && result.error == "corrupt_skill_state" && r.快捷技能栏1 == "", "nonempty tail blocks every loadout write");
    }

    private static function testEquipAndDirty():Void {
        var r:Object = fixture(80); learn(r, 0, "闪现", 1);
        var result:Object = SkillLoadoutService.equip("闪现", 1, SkillLoadoutService.getRevision());
        check(result.success && result.changed && r.快捷技能栏1 == "闪现" && r.主角技能表[0][2] === true && r.存档系统.dirtyMark, "equip commits slot flags and dirty atomically");
    }

    private static function testEquipNoop():Void {
        var r:Object = fixture(80); learn(r, 0, "闪现", 1); r.快捷技能栏1 = "闪现"; r.主角技能表[0][2] = true; r.主角技能表[0][4] = true;
        var rev:Number = SkillLoadoutService.getRevision(); r.存档系统.dirtyMark = false;
        var result:Object = SkillLoadoutService.equip("闪现", 1, rev);
        check(result.success && !result.changed && result.revision == rev && !r.存档系统.dirtyMark && r.domainCalls == 0, "same-slot equip is a side-effect-free no-op");
    }

    private static function testNormalModeRejectsDuplicateSlot():Void {
        var r:Object = fixture(80); learn(r, 0, "闪现", 1); r.快捷技能栏1 = "闪现";
        var result:Object = SkillLoadoutService.equip("闪现", 2, SkillLoadoutService.getRevision());
        check(!result.success && result.error == "already_equipped" && r.快捷技能栏2 == "", "normal mode rejects a second slot copy");
    }

    private static function testEasyModeAllowsDuplicateSlot():Void {
        var r:Object = fixture(80); r.easy = true; learn(r, 0, "闪现", 1); r.快捷技能栏1 = "闪现";
        var result:Object = SkillLoadoutService.equip("闪现", 2, SkillLoadoutService.getRevision());
        check(result.success && r.快捷技能栏1 == "闪现" && r.快捷技能栏2 == "闪现", "easy mode retains multi-slot skill behavior");
    }

    private static function testAtomicReplacement():Void {
        var r:Object = fixture(80); learn(r, 0, "闪现", 1); learn(r, 1, "刀技", 1); r.快捷技能栏3 = "刀技";
        var result:Object = SkillLoadoutService.equip("闪现", 3, SkillLoadoutService.getRevision());
        check(result.success && r.快捷技能栏3 == "闪现" && r.主角技能表[0][2] === true && r.主角技能表[1][2] === false, "replacement updates new and displaced row in one write");
    }

    private static function testMoveSlotToEmpty():Void {
        var r:Object = fixture(80); learn(r, 0, "闪现", 1); r.快捷技能栏2 = "闪现"; r.主角技能表[0][2] = true;
        var revision:Number = SkillLoadoutService.getRevision(); r.存档系统.dirtyMark = false;
        var result:Object = SkillLoadoutService.moveSlot(2, 8, revision);
        check(result.success && result.changed && result.revision == revision + 1
            && r.快捷技能栏2 == "" && r.快捷技能栏8 == "闪现"
            && r.主角技能表[0][2] === true && r.主角技能表[0][4] === true
            && r.domainCalls == 0 && r.存档系统.dirtyMark,
            "moving to an empty quick slot is one atomic revision and keeps the skill enabled");
    }

    private static function testMoveSlotSwapsOccupied():Void {
        var r:Object = fixture(80); learn(r, 0, "闪现", 1); learn(r, 1, "刀技", 2);
        r.快捷技能栏3 = "闪现"; r.快捷技能栏7 = "刀技";
        r.主角技能表[0][2] = r.主角技能表[0][4] = true;
        r.主角技能表[1][2] = r.主角技能表[1][4] = true;
        var revision:Number = SkillLoadoutService.getRevision();
        var result:Object = SkillLoadoutService.moveSlot(3, 7, revision);
        check(result.success && result.revision == revision + 1
            && r.快捷技能栏3 == "刀技" && r.快捷技能栏7 == "闪现"
            && r.主角技能表[0][2] === true && r.主角技能表[1][2] === true
            && result.changed && r.domainCalls == 0,
            "occupied quick slots swap atomically without transient unequip or duplicate checks");
    }

    private static function testMoveSlotNoop():Void {
        var r:Object = fixture(80); learn(r, 0, "闪现", 1); r.快捷技能栏4 = "闪现"; r.主角技能表[0][2] = true;
        var revision:Number = SkillLoadoutService.getRevision(); r.存档系统.dirtyMark = false;
        var same:Object = SkillLoadoutService.moveSlot(4, 4, revision);
        r.easy = true; r.快捷技能栏5 = "闪现"; SkillLoadoutService.getRevision(); revision = SkillLoadoutService.getRevision();
        var duplicate:Object = SkillLoadoutService.moveSlot(4, 5, revision);
        check(same.success && !same.changed && duplicate.success && !duplicate.changed
            && r.快捷技能栏4 == "闪现" && r.快捷技能栏5 == "闪现"
            && SkillLoadoutService.getRevision() == revision && r.domainCalls == 0 && !r.存档系统.dirtyMark,
            "same-slot and same-skill easy-mode moves are side-effect-free no-ops");
    }

    private static function testMoveSlotRejectsEmptyOrCorruptSource():Void {
        var r:Object = fixture(80); learn(r, 0, "闪现", 1);
        var empty:Object = SkillLoadoutService.moveSlot(1, 2, SkillLoadoutService.getRevision());
        r.快捷技能栏1 = "坏技能";
        var corrupt:Object = SkillLoadoutService.moveSlot(1, 2, SkillLoadoutService.getRevision());
        check(!empty.success && empty.error == "slot_empty" && !corrupt.success && corrupt.error == "corrupt_skill_state"
            && r.快捷技能栏1 == "坏技能" && r.快捷技能栏2 == "" && !r.存档系统.dirtyMark,
            "empty or corrupt quick-slot sources fail without overwriting either physical slot");
    }

    private static function testMutationDoesNotNormalizeUnrelatedRows():Void {
        var r:Object = fixture(80); learn(r, 0, "闪现", 1); learn(r, 1, "刀技", 1);
        r.主角技能表[1][2] = "true"; r.主角技能表[1][3] = "旧类型"; r.主角技能表[1][4] = "false";
        var result:Object = SkillLoadoutService.equip("闪现", 1, SkillLoadoutService.getRevision());
        check(result.success && r.主角技能表[1][2] === "true" && r.主角技能表[1][3] === "旧类型"
            && r.主角技能表[1][4] === "false", "mutation derives flags and metadata only for physical rows genuinely affected by that write");
    }

    private static function testUnequipKeepsEasyDuplicateEnabled():Void {
        var r:Object = fixture(80); r.easy = true; learn(r, 0, "混合技", 1); r.快捷技能栏1 = "混合技"; r.快捷技能栏2 = "混合技";
        var result:Object = SkillLoadoutService.unequip(1, SkillLoadoutService.getRevision());
        check(result.success && r.快捷技能栏2 == "混合技" && r.主角技能表[0][2] === true && r.主角技能表[0][4] === true, "unequipping one easy duplicate keeps remaining mixed passive active");
    }

    private static function testUnknownSlotSafeUnequip():Void {
        var r:Object = fixture(80); r.快捷技能栏4 = "坏技能";
        var result:Object = SkillLoadoutService.unequip(4, SkillLoadoutService.getRevision());
        check(result.success && result.changed && r.快捷技能栏4 == "", "unknown slot can be safely cleared without inventing a row");
    }

    private static function testDuplicateSlotUnequipBlocked():Void {
        var r:Object = fixture(80); learn(r, 0, "闪现", 1); learn(r, 1, "闪现", 1); r.快捷技能栏5 = "闪现";
        var result:Object = SkillLoadoutService.unequip(5, SkillLoadoutService.getRevision());
        check(!result.success && r.快捷技能栏5 == "闪现", "duplicate-key slot cannot be modified through safe unequip");
    }

    private static function testBadSlotOccupantMatrix():Void {
        var all:Boolean = true;
        var r:Object = fixture(80); learn(r, 0, "闪现", 1); r.快捷技能栏4 = "未学技能";
        var d:Object = SkillLoadoutService.getSlotDescriptor(4);
        var replace:Object = SkillLoadoutService.equip("闪现", 4, SkillLoadoutService.getRevision());
        var clear:Object = SkillLoadoutService.unequip(4, SkillLoadoutService.getRevision());
        all = all && d.stateHealth == "unknown" && !d.writeBlocked && !replace.success && clear.success;

        r = fixture(80); learn(r, 0, "闪现", 999999); learn(r, 1, "刀技", 1); r.快捷技能栏4 = "闪现";
        d = SkillLoadoutService.getSlotDescriptor(4); replace = SkillLoadoutService.equip("刀技", 4, SkillLoadoutService.getRevision());
        clear = SkillLoadoutService.unequip(4, SkillLoadoutService.getRevision());
        all = all && d.stateHealth == "invalid" && d.writeBlocked && !replace.success && !clear.success;

        r = fixture(80); learn(r, 0, "闪现", 1); learn(r, 1, "刀技", 1); r.主角技能表[0][4] = "ture"; r.快捷技能栏4 = "闪现";
        d = SkillLoadoutService.getSlotDescriptor(4); replace = SkillLoadoutService.equip("刀技", 4, SkillLoadoutService.getRevision());
        clear = SkillLoadoutService.unequip(4, SkillLoadoutService.getRevision());
        all = all && d.stateHealth == "invalid" && d.writeBlocked && !replace.success && !clear.success;

        r = fixture(80); learn(r, 0, "内力爆发", 1); learn(r, 1, "刀技", 1); r.快捷技能栏4 = "内力爆发";
        d = SkillLoadoutService.getSlotDescriptor(4); replace = SkillLoadoutService.equip("刀技", 4, SkillLoadoutService.getRevision());
        clear = SkillLoadoutService.unequip(4, SkillLoadoutService.getRevision());
        all = all && d.stateHealth == "invalid" && !d.writeBlocked && !replace.success && clear.success;

        r = fixture(80); learn(r, 0, "闪现", 1); learn(r, 2, "闪现", 1); learn(r, 1, "刀技", 1); r.快捷技能栏4 = "闪现";
        d = SkillLoadoutService.getSlotDescriptor(4); replace = SkillLoadoutService.equip("刀技", 4, SkillLoadoutService.getRevision());
        clear = SkillLoadoutService.unequip(4, SkillLoadoutService.getRevision());
        all = all && d.stateHealth == "duplicate" && d.writeBlocked && !replace.success && !clear.success;
        check(all, "unknown invalid-level invalid-boolean pure-passive and duplicate slot occupants obey snapshot/equip/unequip matrix");
    }

    private static function testPurePassiveCannotEquip():Void {
        var r:Object = fixture(80); learn(r, 0, "内力爆发", 1);
        var result:Object = SkillLoadoutService.equip("内力爆发", 1, SkillLoadoutService.getRevision());
        check(!result.success && result.error == "not_equippable", "pure passive is never quick-slot equippable");
    }

    private static function testIllegalPurePassiveSlotIsSafeToClear():Void {
        var r:Object = fixture(80); learn(r, 0, "内力爆发", 1); r.快捷技能栏11 = "内力爆发";
        var descriptor:Object = SkillLoadoutService.getSlotDescriptor(11);
        var result:Object = SkillLoadoutService.unequip(11, SkillLoadoutService.getRevision());
        check(!descriptor.equipped && descriptor.stateHealth == "invalid" && !SkillLoadoutService.isReleaseAllowed("内力爆发")
            && result.success && r.快捷技能栏11 == "", "illegal legacy pure-passive slot fails release closed but remains safely clearable");
    }

    private static function testSetPassive():Void {
        var r:Object = fixture(80); learn(r, 0, "内力爆发", 1); r.主角技能表[0][4] = false;
        var result:Object = SkillLoadoutService.setPassive("内力爆发", true, SkillLoadoutService.getRevision());
        check(result.success && r.主角技能表[0][4] === true && r.主角被动技能.内力爆发.启用 === true, "pure-passive toggle rebuilds domain cache");
    }

    private static function testPassiveShadowRoundTrip():Void {
        var r:Object = fixture(80); learn(r, 0, "内力爆发", 1); r.主角技能表[0][2] = "false"; r.主角技能表[0][4] = false;
        SkillLoadoutService.setPassive("内力爆发", true, SkillLoadoutService.getRevision());
        var item:Object = findLearned(SkillLoadoutService.buildSnapshot("manage", null).learned, "内力爆发");
        check(r.主角技能表[0][2] === "false" && item.equippedSlots.length == 0 && item.enabled, "pure-passive shadow round-trips while [4] is authoritative");
    }

    private static function testPurePassiveShadowRepresentationsAreIgnored():Void {
        var shadows:Array = [true, false, "true", "false", "ture"];
        var all:Boolean = true;
        for (var i:Number = 0; i < shadows.length; i++) {
            var r:Object = fixture(80); learn(r, 0, "内力爆发", 1);
            r.主角技能表[0][2] = shadows[i]; r.主角技能表[0][4] = false;
            var result:Object = SkillLoadoutService.setPassive("内力爆发", true, SkillLoadoutService.getRevision());
            all = all && result.success && r.主角技能表[0][2] === shadows[i] && r.主角技能表[0][4] === true;
        }
        check(all, "pure-passive [2] accepts and round-trips historical booleans strings and malformed shadow text");
    }

    private static function testMixedPassiveFollowsSlots():Void {
        var r:Object = fixture(80); learn(r, 0, "混合技", 1);
        SkillLoadoutService.equip("混合技", 6, SkillLoadoutService.getRevision());
        var enabled:Boolean = r.主角技能表[0][4] === true;
        SkillLoadoutService.unequip(6, SkillLoadoutService.getRevision());
        check(enabled && r.主角技能表[0][4] === false, "mixed passive enables on first equip and disables on last unequip");
    }

    private static function testReorderAndStableLoadout():Void {
        var r:Object = fixture(80); learn(r, 0, "闪现", 1); learn(r, 2, "刀技", 1); r.快捷技能栏7 = "刀技"; r.easy = true;
        var result:Object = SkillLoadoutService.reorder("刀技", 1, SkillLoadoutService.getRevision());
        check(result.success && r.主角技能表[1][0] == "刀技" && r.快捷技能栏7 == "刀技", "reorder swaps rows without drifting skill-key loadout");
    }

    private static function testReorderNoop():Void {
        var r:Object = fixture(80); learn(r, 2, "刀技", 1); var rev:Number = SkillLoadoutService.getRevision();
        var result:Object = SkillLoadoutService.reorder("刀技", 2, rev);
        check(result.success && !result.changed && result.revision == rev, "same-position reorder is a no-op");
    }

    private static function testReorderRejectsMalformedTarget():Void {
        var r:Object = fixture(80); learn(r, 0, "闪现", 1); r.主角技能表[1] = {bad:true};
        var source = r.主角技能表[0]; var target = r.主角技能表[1];
        var result:Object = SkillLoadoutService.reorder("闪现", 1, SkillLoadoutService.getRevision());
        check(!result.success && result.error == "corrupt_skill_state" && r.主角技能表[0] === source && r.主角技能表[1] === target,
            "reorder rejects malformed target with zero physical-row writes");
    }

    private static function testReorderRejectsUnknownTarget():Void {
        var r:Object = fixture(80); learn(r, 0, "闪现", 1); r.主角技能表[1] = ["不存在", 1, false, "武术", false];
        var source = r.主角技能表[0]; var target = r.主角技能表[1];
        var result:Object = SkillLoadoutService.reorder("闪现", 1, SkillLoadoutService.getRevision());
        check(!result.success && result.error == "corrupt_skill_state" && r.主角技能表[0] === source && r.主角技能表[1] === target,
            "reorder rejects unknown-skill target with zero physical-row writes");
    }

    private static function testNormalReorderRejectsEquippedTarget():Void {
        var r:Object = fixture(80); learn(r, 0, "闪现", 1); learn(r, 1, "刀技", 1); r.快捷技能栏4 = "刀技";
        var source:Array = r.主角技能表[0]; var target:Array = r.主角技能表[1];
        var result:Object = SkillLoadoutService.reorder("闪现", 1, SkillLoadoutService.getRevision());
        check(!result.success && result.error == "equipped_skill_locked"
            && r.主角技能表[0] === source && r.主角技能表[1] === target,
            "normal-mode reorder rejects an equipped target row without swapping physical rows");
    }

    private static function testEasyReorderRejectsEquippedTarget():Void {
        var r:Object = fixture(80); learn(r, 0, "闪现", 1); learn(r, 1, "刀技", 1); r.快捷技能栏4 = "刀技"; r.easy = true;
        var source:Array = r.主角技能表[0]; var target:Array = r.主角技能表[1];
        var result:Object = SkillLoadoutService.reorder("闪现", 1, SkillLoadoutService.getRevision());
        check(!result.success && result.error == "equipped_skill_locked"
            && r.主角技能表[0] === source && r.主角技能表[1] === target,
            "easy-mode reorder still rejects an equipped target row without swapping physical rows");
    }

    private static function testStaleRevisionZeroWrite():Void {
        var r:Object = fixture(80); learn(r, 0, "闪现", 1); var rev:Number = SkillLoadoutService.getRevision(); r.主角技能表[0][1] = 2;
        var result:Object = SkillLoadoutService.equip("闪现", 8, rev);
        check(!result.success && result.error == "stale_state" && r.快捷技能栏8 == "", "stale expectedRevision performs zero writes");
    }

    private static function testInitialLearnMaterializesShortRow():Void {
        var r:Object = fixture(2); r.主角技能表[0] = emptyRow(); r.主角技能表[1] = emptyRow();
        var ref:Array = r.主角技能表; var result:Object = SkillLoadoutService.commitLearn("闪现", 1, 20, SkillLoadoutService.getRevision());
        check(result.success && r.主角技能表 === ref && r.主角技能表[0][0] == "闪现" && r.技能点数 == 80, "initial learn materializes one row in place after validation");
    }

    private static function testInitialLearnUsesCanonicalPurePassive():Void {
        var r:Object = fixture(80);
        var result:Object = SkillLoadoutService.commitLearn("异型被动", 1, 20, SkillLoadoutService.getRevision());
        var item:Object = findLearned(result.snapshot.learned, "异型被动");
        check(result.success && r.主角技能表[0][2] === true && r.主角技能表[0][4] === true
            && item.equippedSlots.length == 0, "Equippable=false canonical pure passive initializes [2]/[4] true without quick-slot projection");
    }

    private static function testInitialLearnMustBeLevelOne():Void {
        var r:Object = fixture(80); var result:Object = SkillLoadoutService.commitLearn("闪现", 2, 20, SkillLoadoutService.getRevision());
        check(!result.success && result.error == "initial_level_must_be_one" && r.技能点数 == 100, "unlearned skill cannot skip directly to a higher level");
    }

    private static function testUpgradeKeepsRowIdentity():Void {
        var r:Object = fixture(80); learn(r, 0, "闪现", 1); var row:Array = r.主角技能表[0];
        var result:Object = SkillLoadoutService.commitLearn("闪现", 3, 10, SkillLoadoutService.getRevision());
        check(result.success && r.主角技能表[0] === row && row[1] == 3 && r.技能点数 == 90, "upgrade mutates the existing physical row and deducts exact supplied cost");
    }

    private static function testFullTableRejectsLearn():Void {
        var r:Object = fixture(80); for(var i:Number = 0; i < 80; i++) r.主角技能表[i] = ["占位" + i, 1, false, "武术", false];
        r.技能表对象 = {}; for(i = 0; i < 80; i++) r.技能表对象["占位" + i] = meta("占位" + i, "武术", false, true);
        r.技能表对象.闪现 = meta("闪现", "武术", false, true); SkillLoadoutService.testOnlyUseRoot(r);
        var result:Object = SkillLoadoutService.commitLearn("闪现", 1, 20, SkillLoadoutService.getRevision());
        check(!result.success && result.error == "skill_table_full" && r.技能点数 == 100, "full 80-row table rejects learn without SP loss");
    }

    private static function testDomainFailureRollsBack():Void {
        var r:Object = fixture(80); learn(r, 0, "闪现", 1); learn(r, 1, "内力爆发", 10); var row:Array = r.主角技能表[0];
        var table:Array = r.主角技能表; var cache:Object = r.主角被动技能; var rev:Number = SkillLoadoutService.getRevision();
        SkillLoadoutService.testOnlyRejectNextCommit();
        var result:Object = SkillLoadoutService.equip("闪现", 9, rev);
        var observed:Object = SkillLoadoutService.testOnlyRejectedState();
        check(!result.success && result.error == "commit_failed" && observed.slot9 == "闪现" && observed.firstEquipped === true
            && observed.flashCD == 1000 && observed.flashMP == 30
            && r.主角技能表 === table && r.主角技能表[0] === row && row[2] === false && r.快捷技能栏9 == ""
            && r.主角被动技能 === cache && SkillLoadoutService.getRevision() == rev && !r.存档系统.dirtyMark,
            "post-primary domain failure restores outer table row slot cache revision and dirty state");
        check(r._技能原始数值 == undefined && r.技能表对象.闪现.CD == 2000 && r.技能表对象.闪现.MP == 10,
            "domain rollback restores dynamic cooldown originals and CD/MP after a partial-write false result");
    }

    private static function testLearnDomainFailureRollsBackSkillPoints():Void {
        var r:Object = fixture(80); var row:Array = r.主角技能表[0]; var cache:Object = r.主角被动技能;
        var rev:Number = SkillLoadoutService.getRevision(); SkillLoadoutService.testOnlyRejectNextCommit();
        var result:Object = SkillLoadoutService.commitLearn("闪现", 1, 20, rev);
        var observed:Object = SkillLoadoutService.testOnlyRejectedState();
        check(!result.success && observed.firstSkill == "闪现" && observed.skillPoints == 80
            && r.主角技能表[0] === row && row[0] == "" && r.技能点数 == 100
            && r.主角被动技能 === cache && SkillLoadoutService.getRevision() == rev && !r.存档系统.dirtyMark,
            "post-primary learn failure restores original row identity skill points cache revision and dirty state");
    }

    private static function testCooldownEffectsAreIndependent():Void {
        var r:Object = fixture(80);
        r.主角被动技能 = {};
        r.主角被动技能["内力爆发"] = {等级:10, 启用:true};
        r.主角被动技能["移动射击"] = {等级:0, 启用:true};
        var burstResult:Boolean = SkillLoadoutService.recalculateDynamicCooldownDomain();
        check(burstResult && r.技能表对象.闪现.CD == 1000 && r.技能表对象.闪现.MP == 30
            && r.技能表对象.一瞬千击.CD == 1000 && r.技能表对象.一瞬千击.MP == 30
            && r.技能表对象.移动射击.CD == 2000,
            "level-10 inner-force burst changes flash/strike but never activates move-shot cooldown");
        r.主角被动技能 = {};
        r.主角被动技能["内力爆发"] = {等级:10, 启用:false};
        r.主角被动技能["移动射击"] = {等级:10, 启用:true};
        var moveResult:Boolean = SkillLoadoutService.recalculateDynamicCooldownDomain();
        check(moveResult && r.技能表对象.闪现.CD == 2000 && r.技能表对象.闪现.MP == 10
            && r.技能表对象.一瞬千击.CD == 2000 && r.技能表对象.一瞬千击.MP == 10
            && r.技能表对象.移动射击.CD == 1000,
            "move-shot level 10 independently activates 1s cooldown while burst values restore");
    }

    private static function testMoveShotZeroAndTenBoundary():Void {
        var r:Object = fixture(80);
        r.主角被动技能 = {};
        r.主角被动技能["移动射击"] = {等级:0, 启用:true};
        var zeroResult:Boolean = SkillLoadoutService.recalculateDynamicCooldownDomain();
        var zeroCD:Number = r.技能表对象.移动射击.CD;
        r.主角被动技能.移动射击.等级 = 10;
        var tenResult:Boolean = SkillLoadoutService.recalculateDynamicCooldownDomain();
        check(zeroResult && zeroCD == 2000 && tenResult && r.技能表对象.移动射击.CD == 1000,
            "move-shot level boundary keeps level 0 unchanged and activates exactly at level 10");
    }

    private static function testQuickHudRendererRebuildsReplaceAndClear():Void {
        var r:Object = fixture(80); learn(r, 0, "闪现", 3); learn(r, 1, "刀技", 2);
        var slotClip:Object = {frames:[]};
        slotClip.gotoAndStop = function(frame:String):Void { this.frames.push(frame); };
        var quickInterface:Object = {};
        quickInterface.快捷技能栏4 = slotClip;
        var playerInterface:Object = {快捷技能界面:quickInterface};

        r.快捷技能栏4 = "闪现";
        var equipped:Object = SkillLoadoutService.projectQuickSlotRenderer(playerInterface);
        var equippedOk:Boolean = equipped.success && equipped.renderedSlots == 1
            && slotClip.已装备名 == "闪现" && slotClip.对应数组号 == 0 && slotClip.数量 == 3
            && slotClip.冷却时间 == 2000 && slotClip.消耗mp == 10 && slotClip.图标 == "图标-闪现"
            && slotClip.frames.length == 2 && slotClip.frames[0] == "空" && slotClip.frames[1] == "默认图标";

        r.快捷技能栏4 = "刀技";
        var replaced:Object = SkillLoadoutService.projectQuickSlotRenderer(playerInterface);
        var replacedOk:Boolean = replaced.success && slotClip.已装备名 == "刀技"
            && slotClip.对应数组号 == 1 && slotClip.数量 == 2 && slotClip.图标 == "图标-刀技"
            && slotClip.frames.length == 4 && slotClip.frames[2] == "空" && slotClip.frames[3] == "默认图标";

        r.快捷技能栏4 = "";
        var cleared:Object = SkillLoadoutService.projectQuickSlotRenderer(playerInterface);
        var clearedOk:Boolean = cleared.success && slotClip.是否装备 == 0 && slotClip.已装备名 == ""
            && slotClip.对应数组号 == -1 && slotClip.数量 == 0 && slotClip.冷却时间 == 0
            && slotClip.消耗mp == 0 && slotClip.图标 == "" && slotClip.frames.length == 5 && slotClip.frames[4] == "空";
        check(equippedOk && replacedOk && clearedOk,
            "legacy quick HUD rebuilds icon shell on equip replacement and clears the stale icon on unequip");
    }

    private static function testAllOptionalRenderersMissing():Void {
        var r:Object = fixture(80); learn(r, 0, "闪现", 1); delete r.技能系统投影Hero; delete r.技能系统投影快捷栏; delete r.技能系统投影旧列表;
        var result:Object = SkillLoadoutService.equip("闪现", 10, SkillLoadoutService.getRevision());
        check(result.success && r.快捷技能栏10 == "闪现", "hero HUD and legacy list may all be absent on successful write");
    }

    private static function fixture(length:Number):Object {
        var r:Object = {技能表对象:{}, 主角技能表:new Array(length), 存档系统:{dirtyMark:false}, 等级:50, 技能点数:100,
            easy:false, domainCalls:0, heroCalls:0, hudCalls:0, listCalls:0, 主角被动技能:{}};
        r.技能表对象.闪现 = meta("闪现", "武术-内力", false, true);
        r.技能表对象.一瞬千击 = meta("一瞬千击", "武术-内力", false, true);
        r.技能表对象.移动射击 = meta("移动射击", "被动", true, false);
        r.技能表对象.刀技 = meta("刀技", "武术", false, true);
        r.技能表对象.内力爆发 = meta("内力爆发", "被动", true, false);
        r.技能表对象.异型被动 = meta("异型被动", "特殊被动", true, false);
        r.技能表对象.混合技 = meta("混合技", "被动-主动", true, true);
        for(var i:Number = 0; i < length; i++) r.主角技能表[i] = emptyRow();
        for(i = 1; i <= 12; i++) { r["快捷技能栏" + i] = ""; r["快捷技能栏键" + i] = 48 + i; }
        r.isEasyMode = function():Boolean { return this.easy; };
        r.keyshow = function(code:Number):String { return "K" + code; };
        r.动态更新技能冷却领域 = function():Boolean { this.domainCalls++; return true; };
        r.技能系统投影Hero = function():Void { this.heroCalls++; };
        r.技能系统投影快捷栏 = function():Void { this.hudCalls++; };
        r.技能系统投影旧列表 = function():Void { this.listCalls++; };
        SkillLoadoutService.testOnlyUseRoot(r);
        return r;
    }

    private static function meta(name:String, type:String, passive:Boolean, equippable:Boolean):Object {
        return {Name:name, Type:type, Description:"描述\n<font color=\"#fff\">x</font>\\tab", UnlockLevel:1,
            MaxLevel:10, UnlockSP:20, UpgradeSP:5, CD:2000, MP:10, Passive:passive, Equippable:equippable};
    }
    private static function emptyRow():Array { return ["", 0, false, "", true]; }
    private static function learn(r:Object, index:Number, key:String, level:Number):Void {
        var m:Object = r.技能表对象[key]; r.主角技能表[index] = [key, level, false, m.Type, m.Type == "被动"];
        SkillLoadoutService.testOnlyUseRoot(r);
    }
    private static function findLearned(items:Array, key:String):Object { for(var i:Number=0;i<items.length;i++) if(items[i].skillKey==key) return items[i]; return null; }
    private static function countLearned(items:Array, key:String):Number { var n:Number=0; for(var i:Number=0;i<items.length;i++) if(items[i].skillKey==key)n++; return n; }
    private static function check(condition:Boolean, message:String):Void {
        if(condition){passed++; trace("[PASS] " + message);} else {failed++; trace("[TEST_FAIL] " + message);}
    }
}
