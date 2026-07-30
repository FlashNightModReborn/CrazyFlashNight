import JSON;
import org.flashNight.arki.skill.SkillLoadoutService;
import org.flashNight.arki.skill.SkillPanelService;

/** SkillPanelService session / preview / commit / wire 回归。 */
class org.flashNight.arki.skill.SkillPanelServiceTest {
    private static var passed:Number = 0;
    private static var failed:Number = 0;

    public static function runAllTests():Void {
        passed = failed = 0;
        testInstallRegistersCommandsAndBridges();
        testManageOpenUsesStrictJson();
        testGameCommandOpenEchoesRequestId();
        testGameCommandOpenRejectsMissingRequestId();
        testGameCommandOpenRejectsInvalidRequestId();
        testOrdinaryOpenersDoNotCarryRequestId();
        testManageOpenNotReadySendsNothing();
        testManageOpenSendFalseFailsClosed();
        testSparseTrainerObjectNormalization();
        testDuplicateTrainerEntryKeepsFirst();
        testInvalidTrainerEntriesDiagnosed();
        testManageSnapshotShape();
        testTrainerSnapshotHasFullEntries();
        testMalformedTrainerMetadataProjectsBoundedAndBlocked();
        testTrainerDiagnosticsReachSnapshot();
        testSameTrainerReusesSession();
        testSuccessfulReadRenewsTrainerLease();
        testIdleTrainerLeaseExpires();
        testDifferentTrainerReplacesSession();
        testManageIntentPreservesActiveSession();
        testLastTrainerIntentWinsWithoutRevokingActive();
        testTrainerSendFailureDropsOnlyCandidate();
        testCandidateCleanupPreservesActiveSession();
        testCloseInvalidatesSession();
        testLateOldSessionCloseDoesNotKillNewSession();
        testCleanupWireAckUsesExactMinimalShape();
        testInitialPreviewIssuesToken();
        testInitialPreviewRejectsLevelSkip();
        testUpgradePreviewUsesDeltaCost();
        testUpgradeCostBoundaryAndOverflow();
        testInsufficientSpIsBusinessPreview();
        testLevelLockIsBusinessPreview();
        testForbiddenSkillIsProtocolFailure();
        testCommitIsAtomicAndReplaySafe();
        testManageWriteIgnoresResidualTrainerSession();
        testMoveSlotDispatchesPhysicalAtomicWrite();
        testTrainerWriteContextIsRejected();
        testExplicitRendererFailureDoesNotRollbackOrStickBusy();
        testMissingRenderersSkipWithoutRollback();
        testExternalDriftInvalidatesToken();
        testCatalogMutationExpiresSession();
        testRemovedNpcExpiresSession();
        testReplacedNpcExpiresSession();
        testDescriptionStrictJsonRoundTrip();
        testResponseWireEchoesReconcileBinding();
        testQuickHudUnequipUsesCurrentAuthority();
        testServiceNotReadyFailsClosed();
        testCloseIsIdempotent();
        SkillPanelService.closeSession();
        SkillLoadoutService.testOnlyReset();
        trace("SkillPanelServiceTest Tests Passed: " + passed);
        trace("SkillPanelServiceTest Tests Failed: " + failed);
    }

    private static function testInstallRegistersCommandsAndBridges():Void {
        fixture(); SkillPanelService.install();
        check(typeof _root.gameCommands.skillSnapshot == "function" && typeof _root.gameCommands.skillLearnCommit == "function"
            && typeof _root.gameCommands.skillMoveSlot == "function"
            && typeof _root.quickSkillUnequip == "function"
            && typeof _root.openSkillTrainer == "function"
            && typeof _root.openSkillPanel == "undefined"
            && typeof _root.legacySkillLearnCommit == "undefined"
            && typeof _root.legacySkillEquip == "undefined"
            && typeof _root.legacySkillUnequip == "undefined"
            && typeof _root.legacySkillSetPassive == "undefined"
            && typeof _root.legacySkillReorder == "undefined",
            "install registers Web commands, trainer opener and narrow quick-HUD unequip only");
    }

    private static function testManageOpenUsesStrictJson():Void {
        var f:Object = fixture();
        var requestId:String = "skill.open.direct-test";
        var result:Object = SkillPanelService.openManage("nativehud", requestId);
        var parsed:Object = (new JSON(false)).parse(f.root.server.sent[0]);
        check(result.success && parsed.task == "panel_request"
            && parsed.panel == "skills" && parsed.initData.view == "manage"
            && parsed.source == "nativehud"
            && parsed.openRequestId == requestId,
            "manage opener emits strict nonce-bound panel_request JSON");
    }

    private static function testGameCommandOpenEchoesRequestId():Void {
        var f:Object = fixture();
        var requestId:String = "skill.open.Request_7~A-B";
        _root.gameCommands.skillPanelOpen({task:"cmd", action:"skillPanelOpen", openRequestId:requestId});
        var parsed:Object = (new JSON(false)).parse(f.root.server.sent[0]);
        check(parsed.task == "panel_request" && parsed.initData.view == "manage" && parsed.source == "nativehud"
            && parsed.openRequestId === requestId,
            "skillPanelOpen echoes the exact Host openRequestId on the nativehud manage request");
    }

    private static function testGameCommandOpenRejectsMissingRequestId():Void {
        var f:Object = fixture();
        _root.gameCommands.skillPanelOpen({task:"cmd", action:"skillPanelOpen"});
        check(f.root.server.sent.length == 0,
            "skillPanelOpen rejects missing Host openRequestId without sending");
    }

    private static function testGameCommandOpenRejectsInvalidRequestId():Void {
        var f:Object = fixture();
        var tooLong:String = "";
        for (var i:Number = 0; i < 161; i++) tooLong += "a";
        _root.gameCommands.skillPanelOpen({openRequestId:"bad token"});
        _root.gameCommands.skillPanelOpen({openRequestId:"bad/token"});
        _root.gameCommands.skillPanelOpen({openRequestId:7});
        _root.gameCommands.skillPanelOpen({openRequestId:null});
        _root.gameCommands.skillPanelOpen({openRequestId:tooLong});
        check(f.root.server.sent.length == 0,
            "skillPanelOpen rejects non-opaque, non-string, or overlength openRequestId without sending");
    }

    private static function testOrdinaryOpenersDoNotCarryRequestId():Void {
        var f:Object = fixture();
        var trainer:Object = _root.openSkillTrainer(f.npc, "world_skill_trainer");
        var trainerWire:Object = (new JSON(false)).parse(f.root.server.sent[0]);
        check(trainer.success && trainerWire.openRequestId == undefined
            && typeof _root.openSkillPanel == "undefined",
            "trainer opener carries no manage nonce and no direct root manage opener exists");
    }

    private static function testManageOpenNotReadySendsNothing():Void {
        SkillPanelService.testOnlyReset(); var server:Object = makeServer();
        SkillLoadoutService.testOnlyUseRoot({server:server}); SkillPanelService.install();
        var result:Object = SkillPanelService.openManage(
            "nativehud", "skill.open.not-ready");
        check(!result.success && result.error == "service_not_ready" && server.sent.length == 0,
            "unready AS2 domain fails closed before any panel_request");
    }

    private static function testManageOpenSendFalseFailsClosed():Void {
        var f:Object = fixture(); f.root.server.sendSocketMessage = function(m:String):Boolean{this.sent.push(m);return false;};
        var result:Object = SkillPanelService.openManage(
            "nativehud", "skill.open.send-false");
        check(!result.success && result.error == "launcher_unavailable" && !result.opened,
            "failed panel_request transport reports launcher_unavailable without claiming open");
    }

    private static function testSparseTrainerObjectNormalization():Void {
        fixture(); var raw:Object = {}; raw["4"] = "刀技"; raw["0"] = "闪现";
        var normalized:Object = SkillPanelService.normalizeTrainerCatalog(raw);
        check(normalized.success && normalized.entries.length == 2 && normalized.entries[0].skillKey == "闪现" && normalized.entries[1].skillKey == "刀技", "sparse numeric Object is normalized in ascending index order");
    }

    private static function testDuplicateTrainerEntryKeepsFirst():Void {
        fixture(); var raw:Object = {}; raw[0] = "闪现"; raw[3] = "闪现";
        var n:Object = SkillPanelService.normalizeTrainerCatalog(raw);
        check(n.entries.length == 1 && n.entries[0].index == 0 && hasDiagnostic(n.diagnostics, "duplicate_trainer_entry"), "duplicate trainer skill keeps first physical catalog entry");
    }

    private static function testInvalidTrainerEntriesDiagnosed():Void {
        fixture(); var raw:Object = {}; raw[0] = 9; raw.bad = "闪现"; raw[2] = "不存在";
        var n:Object = SkillPanelService.normalizeTrainerCatalog(raw);
        check(n.entries.length == 0 && hasDiagnostic(n.diagnostics, "invalid_trainer_entry") && hasDiagnostic(n.diagnostics, "unknown_skill"), "invalid key value and unknown skill are diagnosed and skipped");
    }

    private static function testManageSnapshotShape():Void {
        fixture();
        var snap:Object = SkillPanelService.execute("snapshot", {v:1, view:"manage"});
        check(snap.success && snap.view == "manage" && snap.loadout.length == 12 && snap.trainer == null
            && snap.player.skillPoints == 100 && snap.loadout[0].equipped == undefined
            && snap.loadout[0].mp == undefined && snap.loadout[0].cooldownMs == undefined,
            "manage snapshot is trainer-free and loadout uses the exact lean wire shape");
    }

    private static function testTrainerSnapshotHasFullEntries():Void {
        var f:Object = fixture(); var opened:Object = SkillPanelService.openTrainer(f.npc, "world_skill_trainer");
        var snap:Object = SkillPanelService.execute("snapshot", {v:1, view:"trainer", trainerSession:opened.trainerSession});
        var e:Object = snap.trainer.entries[0];
        check(snap.success && e.skillKey == "闪现" && e.currentLevel == 0 && e.maxLevel == 10 && e.description.indexOf("\n") >= 0 && e.iconKey == "闪现", "trainer entry independently projects unlearned metadata");
    }

    private static function testMalformedTrainerMetadataProjectsBoundedAndBlocked():Void {
        var f:Object = fixture(); var m:Object = f.root.技能表对象.闪现;
        m.MaxLevel = 999; m.MP = 999999999; m.CD = 999999999.5; m.Type = "武术" + String.fromCharCode(1);
        var opened:Object = SkillPanelService.openTrainer(f.npc, "world_skill_trainer");
        var snap:Object = SkillPanelService.execute("snapshot", {v:1, view:"trainer", trainerSession:opened.trainerSession});
        var e:Object = snap.trainer.entries[0];
        check(snap.success && e.maxLevel == 1 && e.mp == 1000000 && e.cooldownMs == 86400000 && e.type == "武术"
            && e.stateHealth == "invalid" && e.writeBlocked && hasDiagnostic(snap.diagnostics, "metadata_mismatch"),
            "malformed trainer metadata stays wire-bounded, visible, diagnosed, and write-blocked");
    }

    private static function testTrainerDiagnosticsReachSnapshot():Void {
        var f:Object = fixture();
        f.npc.可学的技能 = {};
        f.npc.可学的技能[0] = "闪现"; f.npc.可学的技能[2] = "闪现";
        f.npc.可学的技能[4] = "不存在"; f.npc.可学的技能.bad = "刀技";
        var opened:Object = SkillPanelService.openTrainer(f.npc, "world_skill_trainer");
        var snap:Object = SkillPanelService.execute("snapshot", {v:1, view:"trainer", trainerSession:opened.trainerSession});
        check(snap.success && hasDiagnostic(snap.diagnostics, "duplicate_trainer_entry")
            && hasDiagnostic(snap.diagnostics, "unknown_skill") && hasDiagnostic(snap.diagnostics, "invalid_trainer_entry")
            && snap.trainer.diagnostics == undefined && snap.diagnostics.length <= 32,
            "trainer catalog diagnostics merge into the exact top-level snapshot diagnostics");
    }

    private static function testSameTrainerReusesSession():Void {
        var f:Object = fixture(); var a:Object = SkillPanelService.openTrainer(f.npc, "world_skill_trainer"); var b:Object = SkillPanelService.openTrainer(f.npc, "world_skill_trainer");
        check(a.success && b.success && a.trainerSession == b.trainerSession, "same npc scene and catalog reuse one trainer capability");
    }

    private static function testSuccessfulReadRenewsTrainerLease():Void {
        var f:Object = fixture(); SkillPanelService.testOnlySetNow(1000);
        var opened:Object = SkillPanelService.openTrainer(f.npc, "world_skill_trainer");
        SkillPanelService.testOnlySetNow(120000);
        var snap:Object = SkillPanelService.execute("snapshot", {v:1, view:"trainer", trainerSession:opened.trainerSession});
        SkillPanelService.testOnlySetNow(239000);
        var preview:Object = SkillPanelService.execute("learnPreview", {v:1, skillKey:"闪现", desiredLevel:1,
            trainerSession:opened.trainerSession, expectedRevision:SkillLoadoutService.getRevision()});
        check(snap.success && preview.success, "successful trainer traffic renews the 120 second idle lease beyond absolute session age");
    }

    private static function testIdleTrainerLeaseExpires():Void {
        var f:Object = fixture(); SkillPanelService.testOnlySetNow(1000);
        var opened:Object = SkillPanelService.openTrainer(f.npc, "world_skill_trainer");
        SkillPanelService.testOnlySetNow(121001);
        var snap:Object = SkillPanelService.execute("snapshot", {v:1, view:"trainer", trainerSession:opened.trainerSession});
        check(!snap.success && snap.error == "trainer_session_expired", "trainer capability still expires after 120 seconds without valid traffic");
    }

    private static function testDifferentTrainerReplacesSession():Void {
        var f:Object = fixture(); var a:Object = SkillPanelService.openTrainer(f.npc, "world_skill_trainer");
        SkillPanelService.execute("snapshot", {v:1, view:"trainer", trainerSession:a.trainerSession});
        var catalog2:Object = {}; catalog2[0] = "刀技";
        var npc2:Object = {_name:"教师B", 可学的技能:catalog2}; f.root.gameworld[npc2._name] = npc2;
        var b:Object = SkillPanelService.openTrainer(npc2, "world_skill_trainer");
        var beforePromote:Object = SkillPanelService.execute("snapshot", {v:1, view:"trainer", trainerSession:a.trainerSession});
        var promoted:Object = SkillPanelService.execute("snapshot", {v:1, view:"trainer", trainerSession:b.trainerSession});
        var old:Object = SkillPanelService.execute("snapshot", {v:1, view:"trainer", trainerSession:a.trainerSession});
        check(b.success && beforePromote.success && promoted.success && !old.success && old.error == "trainer_session_expired",
            "different trainer remains a candidate until first bound command then atomically revokes the old capability");
    }

    private static function testManageIntentPreservesActiveSession():Void {
        var f:Object = fixture(); var a:Object = SkillPanelService.openTrainer(f.npc, "world_skill_trainer");
        SkillPanelService.execute("snapshot", {v:1, view:"trainer", trainerSession:a.trainerSession});
        var opened:Object = SkillPanelService.openManage(
            "nativehud", "skill.open.preserve-session");
        var stillActive:Object = SkillPanelService.execute("snapshot", {v:1, view:"trainer", trainerSession:a.trainerSession});
        check(opened.success && stillActive.success, "manage panel intent does not revoke the active trainer before Host rebind cleanup");
    }

    private static function testLastTrainerIntentWinsWithoutRevokingActive():Void {
        var f:Object = fixture(); var a:Object = SkillPanelService.openTrainer(f.npc, "world_skill_trainer");
        SkillPanelService.execute("snapshot", {v:1, view:"trainer", trainerSession:a.trainerSession});
        var catalogB:Object = {}; catalogB[0] = "刀技";
        var catalogC:Object = {}; catalogC[0] = "闪现";
        var npcB:Object = {_name:"教师B", 可学的技能:catalogB}; f.root.gameworld[npcB._name] = npcB;
        var npcC:Object = {_name:"教师C", 可学的技能:catalogC}; f.root.gameworld[npcC._name] = npcC;
        var b:Object = SkillPanelService.openTrainer(npcB, "world_skill_trainer");
        var c:Object = SkillPanelService.openTrainer(npcC, "world_skill_trainer");
        var staleB:Object = SkillPanelService.execute("snapshot", {v:1, view:"trainer", trainerSession:b.trainerSession});
        var activeA:Object = SkillPanelService.execute("snapshot", {v:1, view:"trainer", trainerSession:a.trainerSession});
        var promoteC:Object = SkillPanelService.execute("snapshot", {v:1, view:"trainer", trainerSession:c.trainerSession});
        var expiredA:Object = SkillPanelService.execute("snapshot", {v:1, view:"trainer", trainerSession:a.trainerSession});
        check(!staleB.success && activeA.success && promoteC.success && !expiredA.success
            && SkillPanelService.testOnlyCandidateSession() == null, "single candidate capacity keeps active A, drops B, and promotes only last intent C");
    }

    private static function testTrainerSendFailureDropsOnlyCandidate():Void {
        var f:Object = fixture(); var a:Object = SkillPanelService.openTrainer(f.npc, "world_skill_trainer");
        SkillPanelService.execute("snapshot", {v:1, view:"trainer", trainerSession:a.trainerSession});
        var catalogB:Object = {}; catalogB[0] = "刀技";
        var npcB:Object = {_name:"教师B", 可学的技能:catalogB}; f.root.gameworld[npcB._name] = npcB;
        f.root.server.sendSocketMessage = function(m:String):Boolean{this.sent.push(m);return false;};
        var failed:Object = SkillPanelService.openTrainer(npcB, "world_skill_trainer");
        var activeA:Object = SkillPanelService.execute("snapshot", {v:1, view:"trainer", trainerSession:a.trainerSession});
        check(!failed.success && activeA.success && SkillPanelService.testOnlyCandidateSession() == null,
            "trainer panel_request send failure drops only candidate B and preserves active A");
    }

    private static function testCandidateCleanupPreservesActiveSession():Void {
        var f:Object = fixture(); var a:Object = SkillPanelService.openTrainer(f.npc, "world_skill_trainer");
        SkillPanelService.execute("snapshot", {v:1, view:"trainer", trainerSession:a.trainerSession});
        var catalogB:Object = {}; catalogB[0] = "刀技";
        var npcB:Object = {_name:"教师B", 可学的技能:catalogB}; f.root.gameworld[npcB._name] = npcB;
        var b:Object = SkillPanelService.openTrainer(npcB, "world_skill_trainer");
        SkillPanelService.execute("close", {v:1, trainerSession:b.trainerSession});
        var activeA:Object = SkillPanelService.execute("snapshot", {v:1, view:"trainer", trainerSession:a.trainerSession});
        var candidateB:Object = SkillPanelService.execute("snapshot", {v:1, view:"trainer", trainerSession:b.trainerSession});
        check(activeA.success && !candidateB.success, "scoped candidate cleanup removes B without touching active trainer A");
    }

    private static function testCloseInvalidatesSession():Void {
        var f:Object = fixture(); var opened:Object = SkillPanelService.openTrainer(f.npc, "world_skill_trainer");
        SkillPanelService.execute("close", {v:1});
        var result:Object = SkillPanelService.execute("snapshot", {v:1, view:"trainer", trainerSession:opened.trainerSession});
        check(!result.success && result.error == "trainer_session_expired", "skillPanelClose revokes trainer session and tokens");
    }

    private static function testLateOldSessionCloseDoesNotKillNewSession():Void {
        var f:Object = fixture(); var first:Object = SkillPanelService.openTrainer(f.npc, "world_skill_trainer");
        var catalog2:Object = {}; catalog2[0] = "刀技";
        var npc2:Object = {_name:"教师B", 可学的技能:catalog2}; f.root.gameworld[npc2._name] = npc2;
        var second:Object = SkillPanelService.openTrainer(npc2, "world_skill_trainer");
        var cleanup:Object = SkillPanelService.execute("close", {v:1, trainerSession:first.trainerSession});
        var snap:Object = SkillPanelService.execute("snapshot", {v:1, view:"trainer", trainerSession:second.trainerSession});
        check(cleanup.success && !cleanup.changed && snap.success && snap.trainer.session == second.trainerSession,
            "late tracked cleanup for an old trainer session is an idempotent no-op for the new capability");
    }

    private static function testCleanupWireAckUsesExactMinimalShape():Void {
        var f:Object = fixture(); var opened:Object = SkillPanelService.openTrainer(f.npc, "world_skill_trainer");
        SkillPanelService.handle("close", {v:1, callId:91, trainerSession:opened.trainerSession});
        var parsed:Object = (new JSON(false)).parse(f.root.server.sent[f.root.server.sent.length - 1]);
        check(parsed.task == "skill_response" && parsed.callId == 91 && parsed.success && parsed.v == 1
            && parsed.changed === false && parsed.revision == 0 && parsed.snapshot == undefined && parsed.error == undefined,
            "tracked cleanup wire ack uses exact minimal success shape without snapshot extras");
    }

    private static function testInitialPreviewIssuesToken():Void {
        var p:Object = freshPreview("闪现", 1);
        check(p.success && p.canCommit && p.currentLevel == 0 && p.cost == 20 && p.learnToken != null, "valid initial preview fixes level one and issues one token");
    }

    private static function testInitialPreviewRejectsLevelSkip():Void {
        var p:Object = freshPreview("闪现", 2);
        check(p.success && !p.canCommit && p.blockingError == "initial_level_must_be_one" && p.learnToken == null, "unlearned level skip is a deterministic business rejection");
    }

    private static function testUpgradePreviewUsesDeltaCost():Void {
        var f:Object = fixture(); learn(f.root, 0, "闪现", 2); var opened:Object = SkillPanelService.openTrainer(f.npc, "world_skill_trainer");
        var p:Object = SkillPanelService.execute("learnPreview", {v:1, skillKey:"闪现", desiredLevel:5,
            trainerSession:opened.trainerSession, expectedRevision:SkillLoadoutService.getRevision()});
        check(p.success && p.canCommit && p.cost == 15 && p.currentLevel == 2, "upgrade preview charges only level delta times UpgradeSP");
    }

    private static function testUpgradeCostBoundaryAndOverflow():Void {
        var f:Object = fixture(); learn(f.root, 0, "闪现", 1); f.root.技能点数 = 2147483647;
        f.root.技能表对象.闪现.MaxLevel = 100;
        f.root.技能表对象.闪现.UpgradeSP = Math.floor(2147483647 / 99);
        var opened:Object = SkillPanelService.openTrainer(f.npc, "world_skill_trainer");
        var edge:Object = SkillPanelService.execute("learnPreview", {v:1, skillKey:"闪现", desiredLevel:100,
            trainerSession:opened.trainerSession, expectedRevision:SkillLoadoutService.getRevision()});

        f = fixture(); learn(f.root, 0, "闪现", 1); f.root.技能点数 = 2147483647;
        f.root.技能表对象.闪现.MaxLevel = 100; f.root.技能表对象.闪现.UpgradeSP = 2147483647;
        opened = SkillPanelService.openTrainer(f.npc, "world_skill_trainer");
        var overflow:Object = SkillPanelService.execute("learnPreview", {v:1, skillKey:"闪现", desiredLevel:100,
            trainerSession:opened.trainerSession, expectedRevision:SkillLoadoutService.getRevision()});
        check(edge.success && edge.canCommit && edge.cost <= 2147483647 && !overflow.success && overflow.error == "invalid_level",
            "upgrade cost accepts the int boundary and rejects multiplication overflow before token issue");
    }

    private static function testInsufficientSpIsBusinessPreview():Void {
        var f:Object = fixture(); f.root.技能点数 = 1; var opened:Object = SkillPanelService.openTrainer(f.npc, "world_skill_trainer");
        var p:Object = SkillPanelService.execute("learnPreview", {v:1, skillKey:"闪现", desiredLevel:1,
            trainerSession:opened.trainerSession, expectedRevision:SkillLoadoutService.getRevision()});
        check(p.success && !p.canCommit && p.blockingError == "insufficient_sp" && p.learnToken == null, "insufficient SP remains a parsed preview without token");
    }

    private static function testLevelLockIsBusinessPreview():Void {
        var f:Object = fixture(); f.root.等级 = 1; f.root.技能表对象.闪现.UnlockLevel = 15; var opened:Object = SkillPanelService.openTrainer(f.npc, "world_skill_trainer");
        var p:Object = SkillPanelService.execute("learnPreview", {v:1, skillKey:"闪现", desiredLevel:1,
            trainerSession:opened.trainerSession, expectedRevision:SkillLoadoutService.getRevision()});
        check(p.success && !p.canCommit && p.blockingError == "level_locked", "level gate is reported as a business preview blocker");
    }

    private static function testForbiddenSkillIsProtocolFailure():Void {
        var f:Object = fixture(); var opened:Object = SkillPanelService.openTrainer(f.npc, "world_skill_trainer");
        var p:Object = SkillPanelService.execute("learnPreview", {v:1, skillKey:"内力爆发", desiredLevel:1,
            trainerSession:opened.trainerSession, expectedRevision:SkillLoadoutService.getRevision()});
        check(!p.success && p.error == "trainer_skill_forbidden", "teacher catalog is an AS2 capability whitelist");
    }

    private static function testCommitIsAtomicAndReplaySafe():Void {
        var f:Object = fixture(); var opened:Object = SkillPanelService.openTrainer(f.npc, "world_skill_trainer");
        var p:Object = SkillPanelService.execute("learnPreview", {v:1, skillKey:"闪现", desiredLevel:1,
            trainerSession:opened.trainerSession, expectedRevision:SkillLoadoutService.getRevision()});
        var c:Object = SkillPanelService.execute("learnCommit", {v:1, expectedLearnToken:p.learnToken,
            view:"trainer", trainerSession:opened.trainerSession});
        var replay:Object = SkillPanelService.execute("learnCommit", {v:1, expectedLearnToken:p.learnToken,
            view:"trainer", trainerSession:opened.trainerSession});
        check(c.success && c.changed && f.root.技能点数 == 80 && f.root.主角技能表[0][0] == "闪现" && !replay.success && replay.error == "stale_state", "commit deducts once and consumes token before replay");
    }

    private static function testManageWriteIgnoresResidualTrainerSession():Void {
        var f:Object = fixture(); learn(f.root, 0, "闪现", 1);
        SkillPanelService.openTrainer(f.npc, "world_skill_trainer");
        var result:Object = SkillPanelService.execute("equip", {v:1, view:"manage", skillKey:"闪现", slot:1,
            expectedRevision:SkillLoadoutService.getRevision()});
        check(result.success && result.snapshot.view == "manage" && result.snapshot.trainer == null,
            "manage write uses explicit command context and ignores a residual trainer session");
    }

    private static function testMoveSlotDispatchesPhysicalAtomicWrite():Void {
        var f:Object = fixture(); learn(f.root, 0, "闪现", 1); learn(f.root, 1, "刀技", 2);
        f.root.快捷技能栏2 = "闪现"; f.root.快捷技能栏9 = "刀技";
        var result:Object = SkillPanelService.execute("moveSlot", {v:1, view:"manage", sourceSlot:2, targetSlot:9,
            expectedRevision:SkillLoadoutService.getRevision()});
        check(result.success && result.changed && f.root.快捷技能栏2 == "刀技" && f.root.快捷技能栏9 == "闪现"
            && result.snapshot.loadout[1].skillKey == "刀技" && result.snapshot.loadout[8].skillKey == "闪现",
            "moveSlot dispatcher returns one authoritative snapshot for the physical-slot swap");
    }

    private static function testTrainerWriteContextIsRejected():Void {
        var f:Object = fixture(); learn(f.root, 0, "闪现", 1);
        var opened:Object = SkillPanelService.openTrainer(f.npc, "world_skill_trainer");
        var result:Object = SkillPanelService.execute("equip", {v:1, view:"trainer", trainerSession:opened.trainerSession,
            skillKey:"闪现", slot:1, expectedRevision:SkillLoadoutService.getRevision()});
        check(!result.success && result.error == "invalid_payload" && f.root.快捷技能栏1 == "",
            "loadout writes are manage-only and reject trainer command context before mutation");
    }

    private static function testExplicitRendererFailureDoesNotRollbackOrStickBusy():Void {
        var f:Object = fixture(); learn(f.root, 0, "闪现", 1);
        f.root.技能系统投影Hero = function():Object{return {success:false,error:"fixture_failure"};};
        f.root.技能系统投影快捷栏 = function():Boolean{return false;};
        var first:Object = SkillPanelService.execute("equip", {v:1, view:"manage", skillKey:"闪现", slot:2,
            expectedRevision:SkillLoadoutService.getRevision()});
        var second:Object = SkillPanelService.execute("unequip", {v:1, view:"manage", slot:2, expectedRevision:first.revision});
        check(first.success && first.changed && hasDiagnostic(first.snapshot.diagnostics, "renderer_failed")
            && countDiagnostic(first.snapshot.diagnostics, "renderer_failed") == 1
            && second.success && f.root.快捷技能栏2 == "",
            "explicit renderer failure is diagnostic-only while false skips normally, busy releases, and the next write proceeds");
    }

    private static function testMissingRenderersSkipWithoutRollback():Void {
        var f:Object = fixture(); learn(f.root, 0, "闪现", 1);
        delete f.root.技能系统投影Hero; delete f.root.技能系统投影快捷栏;
        var result:Object = SkillPanelService.execute("equip", {v:1, view:"manage", skillKey:"闪现", slot:3,
            expectedRevision:SkillLoadoutService.getRevision()});
        check(result.success && f.root.快捷技能栏3 == "闪现" && !hasDiagnostic(result.snapshot.diagnostics, "renderer_failed"),
            "missing optional renderers are normal skips and do not roll back or emit false failures");
    }

    private static function testExternalDriftInvalidatesToken():Void {
        var f:Object = fixture(); var opened:Object = SkillPanelService.openTrainer(f.npc, "world_skill_trainer");
        var p:Object = SkillPanelService.execute("learnPreview", {v:1, skillKey:"闪现", desiredLevel:1,
            trainerSession:opened.trainerSession, expectedRevision:SkillLoadoutService.getRevision()});
        f.root.技能点数 = 99;
        var c:Object = SkillPanelService.execute("learnCommit", {v:1, expectedLearnToken:p.learnToken,
            view:"trainer", trainerSession:opened.trainerSession});
        check(!c.success && c.error == "stale_state" && f.root.技能点数 == 99 && f.root.主角技能表[0][0] == "", "external state drift invalidates token with zero skill write");
    }

    private static function testCatalogMutationExpiresSession():Void {
        var f:Object = fixture(); var opened:Object = SkillPanelService.openTrainer(f.npc, "world_skill_trainer"); f.npc.可学的技能[0] = "刀技";
        var snap:Object = SkillPanelService.execute("snapshot", {v:1, view:"trainer", trainerSession:opened.trainerSession});
        check(!snap.success && snap.error == "trainer_session_expired", "catalog signature mutation revokes existing trainer session");
    }

    private static function testRemovedNpcExpiresSession():Void {
        var f:Object = fixture(); var opened:Object = SkillPanelService.openTrainer(f.npc, "world_skill_trainer");
        delete f.root.gameworld[f.npc._name];
        var snap:Object = SkillPanelService.execute("snapshot", {v:1, view:"trainer", trainerSession:opened.trainerSession});
        check(!snap.success && snap.error == "trainer_session_expired", "removed gameworld NPC revokes trainer capability");
    }

    private static function testReplacedNpcExpiresSession():Void {
        var f:Object = fixture(); var opened:Object = SkillPanelService.openTrainer(f.npc, "world_skill_trainer");
        var replacementCatalog:Object = {}; replacementCatalog[0] = "闪现";
        f.root.gameworld[f.npc._name] = {_name:f.npc._name, 可学的技能:replacementCatalog};
        var snap:Object = SkillPanelService.execute("snapshot", {v:1, view:"trainer", trainerSession:opened.trainerSession});
        check(!snap.success && snap.error == "trainer_session_expired", "replaced gameworld NPC revokes trainer capability");
    }

    private static function testDescriptionStrictJsonRoundTrip():Void {
        var f:Object = fixture(); var opened:Object = SkillPanelService.openTrainer(f.npc, "world_skill_trainer");
        var snap:Object = SkillPanelService.execute("snapshot", {v:1, view:"trainer", trainerSession:opened.trainerSession});
        var wire:String = (new JSON(false)).stringify(snap); var parsed:Object = (new JSON(false)).parse(wire);
        var expected:String = "第一行\r\n<font color=\"#fff\">引号</font>\\路径\t";
        check(parsed.trainer.entries[0].description == expected, "wire text preserves quote slash CR LF and tab while removing forbidden C0/C1 controls");
    }

    private static function testResponseWireEchoesReconcileBinding():Void {
        var f:Object = fixture(); SkillPanelService.handle("snapshot", {v:1, callId:17, view:"manage", reconcileId:"rec.17", reconcileAfterCallId:"skill.write.16"});
        var parsed:Object = (new JSON(false)).parse(f.root.server.sent[f.root.server.sent.length - 1]);
        check(parsed.task == "skill_response" && parsed.callId == 17 && parsed.reconcileId == undefined
            && parsed.reconcileAfterCallId == undefined && parsed.loadout.length == 12,
            "wire response keeps exact snapshot schema while Host owns reconcile binding");
    }

    private static function testQuickHudUnequipUsesCurrentAuthority():Void {
        var f:Object = fixture();
        learn(f.root, 0, "闪现", 1);
        var equipped:Object = SkillLoadoutService.equip(
            "闪现", 1, SkillLoadoutService.getRevision());
        var unequipped:Object = _root.quickSkillUnequip(1);
        check(equipped.success && unequipped.success
            && unequipped.changed && f.root.快捷技能栏1 == "",
            "quick HUD unequip uses current loadout authority without legacy UI bridges");
    }

    private static function testServiceNotReadyFailsClosed():Void {
        SkillPanelService.testOnlyReset(); SkillLoadoutService.testOnlyUseRoot({server:makeServer()});
        var result:Object = SkillPanelService.execute("snapshot", {v:1, view:"manage"});
        check(!result.success && result.error == "service_not_ready", "panel read fails service_not_ready before creating diagnostics or capability");
    }

    private static function testCloseIsIdempotent():Void {
        fixture(); var a:Object = SkillPanelService.execute("close", {v:1}); var b:Object = SkillPanelService.execute("close", {v:1});
        check(a.success && b.success && !a.changed && !b.changed, "close is idempotent");
    }

    private static function freshPreview(skillKey:String, desiredLevel:Number):Object {
        var f:Object = fixture(); var opened:Object = SkillPanelService.openTrainer(f.npc, "world_skill_trainer");
        return SkillPanelService.execute("learnPreview", {v:1, skillKey:skillKey, desiredLevel:desiredLevel,
            trainerSession:opened.trainerSession, expectedRevision:SkillLoadoutService.getRevision()});
    }

    private static function fixture():Object {
        SkillPanelService.testOnlyReset();
        var r:Object = {技能表对象:{}, 主角技能表:new Array(80), 存档系统:{dirtyMark:false}, 等级:50, 技能点数:100,
            当前场景:"base", 主角被动技能:{}, server:makeServer(), gameworld:{}};
        r.技能表对象.闪现 = meta("闪现", "武术-内力", false, true, 15);
        r.技能表对象.刀技 = meta("刀技", "武术", false, true, 1);
        r.技能表对象.内力爆发 = meta("内力爆发", "被动", true, false, 1);
        for(var i:Number=0;i<80;i++) r.主角技能表[i] = ["",0,false,"",true];
        for(i=1;i<=12;i++){r["快捷技能栏"+i]="";r["快捷技能栏键"+i]=48+i;}
        r.isEasyMode=function():Boolean{return false;}; r.keyshow=function(n:Number):String{return "K"+n;};
        r.动态更新技能冷却领域=function():Void{}; r.技能系统投影Hero=function():Void{};
        r.技能系统投影快捷栏=function():Void{};
        var trainerCatalog:Object = {}; trainerCatalog[0] = "闪现"; trainerCatalog[3] = "刀技";
        var npc:Object = {_name:"技能教师", 可学的技能:trainerCatalog};
        r.gameworld[npc._name] = npc;
        SkillLoadoutService.testOnlyUseRoot(r);
        SkillPanelService.install();
        return {root:r, npc:npc};
    }

    private static function meta(name:String,type:String,passive:Boolean,equippable:Boolean,unlockLevel:Number):Object {
        return {Name:name,Type:type,Description:"第一行\r\n<font color=\"#fff\">引号</font>\\路径\t" + String.fromCharCode(1) + String.fromCharCode(127),UnlockLevel:unlockLevel,
            MaxLevel:10,UnlockSP:20,UpgradeSP:5,CD:2000,MP:10,Passive:passive,Equippable:equippable};
    }
    private static function makeServer():Object { var s:Object={sent:[]}; s.sendSocketMessage=function(m:String):Boolean{this.sent.push(m);return true;}; return s; }
    private static function learn(r:Object,index:Number,key:String,level:Number):Void { var m:Object=r.技能表对象[key];r.主角技能表[index]=[key,level,false,m.Type,m.Type=="被动"];SkillLoadoutService.testOnlyUseRoot(r); }
    private static function hasDiagnostic(items:Array,code:String):Boolean { for(var i:Number=0;i<items.length;i++)if(items[i].code==code)return true;return false; }
    private static function countDiagnostic(items:Array,code:String):Number { var count:Number=0;for(var i:Number=0;i<items.length;i++)if(items[i].code==code)count++;return count; }
    private static function check(condition:Boolean,message:String):Void { if(condition){passed++;trace("[PASS] "+message);}else{failed++;trace("[TEST_FAIL] "+message);} }
}
