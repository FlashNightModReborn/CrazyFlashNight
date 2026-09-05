import org.flashNight.arki.scene.WarlordActionEncounterService;

import org.flashNight.arki.unit.UnitComponent.Initializer.RuntimeEquipmentProjection;

/**
 * PREFER_B focused regression：只验证 v2 战斗事实和纯投影。
 * 场景创建、跳帧、回收与重试时钟均由 StageManager 单独持有，
 * 本套件不再模拟第二生命周期 owner 或物理场景回收协议。
 */
class org.flashNight.arki.scene.ActionEncounterRunnerTest {
    private static var passed:Number = 0;
    private static var failed:Number = 0;
    private static var cases:Number = 0;

    /** 消费同轮 C# transport 实际导出的命令；不创建场景、不运行战斗。 */
    public static function validateHostCommands(wireText:String):Void {
        var parser:LiteJSON = new LiteJSON();
        var commands:Array = parser.parse(wireText);
        if (commands.length != 8) throw new Error("Host wire matrix must contain 8 cases");
        for (var i:Number = 0; i < commands.length; i++) {
            var command:Object = commands[i];
            if (!WarlordActionEncounterService.testOnlyValidateStart(command)) {
                throw new Error("Host wire rejected at case " + i);
            }
            var originalSide:String = String(command.encounter.playerControlledSide);
            command.encounter.playerControlledSide = originalSide == "none" ? "red" : "none";
            if (WarlordActionEncounterService.testOnlyValidateStart(command)) {
                throw new Error("Host wire control drift accepted at case " + i);
            }
            command.encounter.playerControlledSide = originalSide;
        }
        trace("ActionEncounterRunnerTest Host Wire Passed: 16/16");
    }

    public static function runAllTests():Void {
        passed = 0;
        failed = 0;
        cases = 0;
        trace("=== ActionEncounterRunnerTest start ===");

        testExactV2Contract(); cases++;
        testDeploymentProjection(); cases++;
        testPlayerAvatarProjection(); cases++;
        testAdmissionHandshake(); cases++;

        trace("ActionEncounterRunnerTest Tests Passed: " + passed);
        trace("ActionEncounterRunnerTest Tests Failed: " + failed);
        if (failed > 0 || passed != 97 || cases != 4) {
            throw new Error("ActionEncounterRunnerTest failed: " + failed
                + " failures, " + passed + "/97 assertions, "
                + cases + "/4 cases");
        }
        trace("ActionEncounterRunnerTest Cases Passed: 4/4");
        trace("=== ActionEncounterRunnerTest end ===");
    }

    private static function testExactV2Contract():Void {
        check(WarlordActionEncounterService.testOnlyGetActivePhase() == "idle",
            "C01 fresh service begins without a second lifecycle owner");

        var valid:Object = productStart();
        check(WarlordActionEncounterService.testOnlyValidateStart(valid),
            "C01 product socket accepts the exact canonical v2 envelope");
        check(countOwnKeys(valid.binding) == 5
                && valid.binding.schema
                    == "warlord.action-encounter-binding.v2",
            "C01 binding is the exact five-key v2 identity");
        check(valid.binding.outerRunId == "run.product"
                && valid.binding.encounterId == "enc.product"
                && valid.binding.requestId == "request.product",
            "C01 v2 identity carries the frozen outer, encounter and request ids");
        check(typeof valid.binding.outerRunId == "string"
                && typeof valid.binding.encounterId == "string"
                && typeof valid.binding.requestId == "string"
                && typeof valid.binding.inputDigest == "string",
            "C01 v2 identity contains only opaque ids and the canonical digest");
        check(valid.encounter.schema == "warlord.action-encounter-control.v2"
                && valid.encounter.playerControlledSide == "none",
            "C01 product control keeps the v2 player-control boundary");
        check(String(valid.binding.inputDigest).indexOf("sha256:") == 0
                && String(valid.binding.inputDigest).length == 71,
            "C01 canonical sha256 digest crosses the AS2 identity gate");

        var changed:Object = productStart();
        changed.extra = true;
        check(!WarlordActionEncounterService.testOnlyValidateStart(changed),
            "C01 extra command field fails closed");
        changed = productStart();
        changed.binding.extra = true;
        check(!WarlordActionEncounterService.testOnlyValidateStart(changed),
            "C01 every extra binding field fails the exact five-key identity");
        changed = productStart();
        changed.binding.schema = "warlord.action-encounter-binding.v1";
        check(!WarlordActionEncounterService.testOnlyValidateStart(changed),
            "C01 retired v1 binding fails closed");
        changed = productStart();
        delete changed.binding.requestId;
        check(!WarlordActionEncounterService.testOnlyValidateStart(changed),
            "C01 missing request identity fails closed");
        changed = productStart();
        changed.binding.outerRunId = "bad id";
        check(!WarlordActionEncounterService.testOnlyValidateStart(changed),
            "C01 non-opaque outer run identity fails closed");
        changed = productStart();
        changed.binding.inputDigest =
            "sha256:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA";
        check(!WarlordActionEncounterService.testOnlyValidateStart(changed),
            "C01 non-canonical digest casing fails closed");
        changed = productStart();
        changed.encounter.extra = true;
        check(!WarlordActionEncounterService.testOnlyValidateStart(changed),
            "C01 extra encounter control field fails closed");
        changed = productStart();
        changed.encounter.blueRoster[0].extra = true;
        check(!WarlordActionEncounterService.testOnlyValidateStart(changed),
            "C01 extra roster field fails closed");
        changed = productStart();
        changed.encounter.blueRoster.push(
            changed.encounter.blueRoster[0]);
        check(!WarlordActionEncounterService.testOnlyValidateStart(changed),
            "C01 duplicate strategic source identity fails closed");
        changed = productStart();
        changed.encounter.spawnDistance = 361;
        check(!WarlordActionEncounterService.testOnlyValidateStart(changed),
            "C01 only frozen encounter distances enter product combat");

        var blueAvatar:Object = playerAvatarStart("blue");
        check(WarlordActionEncounterService.testOnlyValidateStart(blueAvatar),
            "C01 one trusted blue player avatar enters the exact union");
        var redAvatar:Object = playerAvatarStart("red");
        check(WarlordActionEncounterService.testOnlyValidateStart(redAvatar),
            "C01 one trusted red player avatar enters the exact union");
        changed = playerAvatarStart("blue");
        changed.encounter.playerControlledSide = "red";
        check(!WarlordActionEncounterService.testOnlyValidateStart(changed),
            "C01 playerControlledSide cannot drift from the avatar roster");
        changed = playerAvatarStart("blue");
        changed.encounter.playerControlledSide = "none";
        check(!WarlordActionEncounterService.testOnlyValidateStart(changed),
            "C01 none cannot conceal a player avatar");
        changed = playerAvatarStart("blue");
        changed.encounter.blueRoster.push(changed.encounter.blueRoster[0]);
        check(!WarlordActionEncounterService.testOnlyValidateStart(changed),
            "C01 duplicate player avatars fail closed");
        changed = playerAvatarStart("blue");
        changed.encounter.blueRoster[0].commanderId = "commander.spoof";
        check(!WarlordActionEncounterService.testOnlyValidateStart(changed),
            "C01 AS2 accepts only the fixed trusted player commander identity");
        changed = playerAvatarStart("blue");
        changed.encounter.blueRoster[0].level = 83;
        check(!WarlordActionEncounterService.testOnlyValidateStart(changed),
            "C01 player avatar rejects proxy-card level authority");
    }

    private static function testDeploymentProjection():Void {
        var near:Object = WarlordActionEncounterService
            .testOnlyProjectDeployment(180, "line", 4, 54);
        var medium:Object = WarlordActionEncounterService
            .testOnlyProjectDeployment(360, "line", 4, 54);
        var far:Object = WarlordActionEncounterService
            .testOnlyProjectDeployment(650, "line", 4, 54);
        check(near.spawnDistance == 180
                && near.blueX == 805 && near.redX == 985,
            "C02 near deployment is exact 180");
        check(medium.spawnDistance == 360
                && medium.blueX == 715 && medium.redX == 1075,
            "C02 medium deployment is exact 360");
        check(far.spawnDistance == 650
                && far.blueX == 570 && far.redX == 1220,
            "C02 far deployment is exact 650");
        var clamped:Object = WarlordActionEncounterService
            .testOnlyProjectDeployment(180, "grid", 4, 12);
        check(clamped.formationSpacing == 36,
            "C02 pure projection clamps spacing to the runtime floor");
        check(near.blue.length == 4 && near.red.length == 4,
            "C02 product projection preserves every roster slot");
        check(deploymentBounded(near) && deploymentBounded(medium)
                && deploymentBounded(far),
            "C02 all distance bands stay inside the authored world bounds");

        var line:Object = WarlordActionEncounterService
            .testOnlyProjectDeployment(360, "line", 4, 54);
        var column:Object = WarlordActionEncounterService
            .testOnlyProjectDeployment(360, "column", 4, 54);
        var wedge:Object = WarlordActionEncounterService
            .testOnlyProjectDeployment(360, "wedge", 4, 54);
        var shield:Object = WarlordActionEncounterService
            .testOnlyProjectDeployment(360, "shield", 4, 54);
        var grid:Object = WarlordActionEncounterService
            .testOnlyProjectDeployment(360, "grid", 4, 54);
        var signatures:Array = [pointSignature(line.blue),
            pointSignature(column.blue), pointSignature(wedge.blue),
            pointSignature(shield.blue), pointSignature(grid.blue)];
        check(uniqueStringCount(signatures) == 5,
            "C02 all five formations produce distinct tactical geometry");
        check(!sidesOverlap(line) && !sidesOverlap(column)
                && !sidesOverlap(wedge) && !sidesOverlap(shield)
                && !sidesOverlap(grid),
            "C02 opposing deployments never share a spawn coordinate");
        var twoWedge:Object = WarlordActionEncounterService
            .testOnlyProjectDeployment(180, "wedge", 2, 54);
        check(twoWedge.blue[0].x != twoWedge.blue[1].x
                && twoWedge.blue[0].y != twoWedge.blue[1].y,
            "C02 two-unit wedge keeps a diagonal wing");
        var twoShield:Object = WarlordActionEncounterService
            .testOnlyProjectDeployment(180, "shield", 2, 54);
        check(twoShield.blue[0].x != twoShield.blue[1].x
                || twoShield.blue[0].y != twoShield.blue[1].y,
            "C02 two-unit shield keeps front and rear slots");
        check(line.spawnDistance == column.spawnDistance
                && column.spawnDistance == wedge.spawnDistance
                && wedge.spawnDistance == shield.spawnDistance
                && shield.spawnDistance == grid.spawnDistance,
            "C02 formation choice cannot mutate encounter distance");
        check(line.formationSpacing == 54
                && column.formationSpacing == 54
                && wedge.formationSpacing == 54
                && shield.formationSpacing == 54
                && grid.formationSpacing == 54,
            "C02 formation choice cannot mutate requested spacing");
    }

    private static function testPlayerAvatarProjection():Void {
        var originalInventory:Object = _root.物品栏;
        var equipmentRefs:Object = {};
        var slotKeys:Array = RuntimeEquipmentProjection.getSlotKeys();
        for (var slotIndex:Number = 0;
                slotIndex < slotKeys.length; slotIndex++) {
            var slotKey:String = String(slotKeys[slotIndex]);
            equipmentRefs[slotKey] = {
                name:"测试" + slotKey,
                value:{level:1, mods:[]}
            };
        }
        _root.物品栏 = {
            装备栏:{
                refs:equipmentRefs,
                getItem:function(key:String) {
                    return this.refs[key];
                }
            }
        };
        var avatarMc:Object = {_name:"avatar.unit", _parent:{}, hp:100,
            等级:37, 攻击目标:"无", 操控编号:0, hasDressup:true,
            version:8};
        for (slotIndex = 0; slotIndex < slotKeys.length; slotIndex++) {
            slotKey = String(slotKeys[slotIndex]);
            avatarMc[slotKey] = equipmentRefs[slotKey];
        }
        RuntimeEquipmentProjection.beginCanonical(avatarMc);
        RuntimeEquipmentProjection.completeCanonical(avatarMc);
        var allyMc:Object = {_name:"ally.unit", _parent:{}, hp:100,
            攻击目标:"无"};
        var enemyMc:Object = {_name:"enemy.unit", _parent:{}, hp:100,
            攻击目标:"无"};
        var avatar:Object = {mc:avatarMc,
            projectionKind:"player_avatar", sourceId:"piece:avatar",
            commanderId:"commander.player",
            characterId:"character.player-avatar", factionId:"player",
            runtimeLevel:37, hpPermille:1000, startMaxHp:100,
            side:"blue", isEnemy:false, controlReleased:false};
        var ally:Object = {mc:allyMc, projectionKind:"pet_projection",
            sourceId:"piece:ally", petId:0, identifier:"狙击兵",
            resolvedType:"狙击兵", rosterType:"pet", level:10,
            strategicPromotions:[], hpPermille:1000, startMaxHp:100,
            side:"blue", isEnemy:false};
        var enemy:Object = {mc:enemyMc, projectionKind:"pet_projection",
            sourceId:"piece:enemy", petId:1, identifier:"突击兵",
            resolvedType:"突击兵", rosterType:"pet", level:10,
            strategicPromotions:[], hpPermille:1000, startMaxHp:100,
            side:"red", isEnemy:true};
        var blue:Array = [avatar, ally];
        var red:Array = [enemy];

        check(!WarlordActionEncounterService
                .testOnlyIsAiPrimeCandidate(avatar)
                && WarlordActionEncounterService
                    .testOnlyIsAiPrimeCandidate(ally),
            "C03 player avatar never enters AI prime while allied pets do");
        WarlordActionEncounterService.testOnlyPrimeTargets(blue, red);
        check(avatarMc.攻击目标 == "无"
                && allyMc.攻击目标 == enemyMc._name,
            "C03 AI prime leaves player input authority untouched");
        check(enemyMc.攻击目标 == avatarMc._name,
            "C03 hostile AI may still target the controlled avatar");

        avatarMc.hp = 0;
        check(WarlordActionEncounterService.testOnlyCountAlive(blue) == 1,
            "C03 avatar down leaves a surviving ally in the same battle");
        var deathEffect:Object = {mc:{_parent:{},
                _warlordActionDeathCheckCalled:false},
            deathObserved:true, deadFinalized:false};
        var pendingBeforeHook:Boolean = WarlordActionEncounterService
            .testOnlyHasPendingDeathEffects([deathEffect]);
        deathEffect.mc._warlordActionDeathCheckCalled = true;
        check(pendingBeforeHook && !WarlordActionEncounterService
                .testOnlyHasPendingDeathEffects([deathEffect]),
            "C03 terminal waits until the projected death hook has run");
        var avatarResult:Object = WarlordActionEncounterService
            .testOnlySummarizeUnitResults([avatar])[0];
        check(avatarResult.projectionKind == "player_avatar"
                && avatarResult.sourceId == "piece:avatar"
                && avatarResult.commanderId == "commander.player"
                && avatarResult.characterId == "character.player-avatar"
                && avatarResult.factionId == "player",
            "C03 avatar result preserves the discriminated trusted identity");
        check(avatarResult.runtimeLevel == 37
                && avatarResult.hpPermille == 0
                && avatarResult.alive === false,
            "C03 avatar result reports runtime level and strategic HP projection");
        check(avatarResult.petId == undefined
                && avatarResult.identifier == undefined
                && avatarResult.level == undefined
                && avatarResult.strategicPromotions == undefined,
            "C03 avatar result never falls back to the pet-card contract");
        var petResult:Object = WarlordActionEncounterService
            .testOnlySummarizeUnitResults([ally])[0];
        check(petResult.projectionKind == "pet_projection"
                && petResult.petId == 0 && petResult.identifier == "狙击兵"
                && petResult.commanderId == undefined,
            "C03 ordinary units retain the exact pet projection result");

        var visualWorld:Object = {_name:"gameworld"};
        var visualActor:Object = {_parent:visualWorld, _visible:true,
            _width:72, _height:120, version:8,
            __unitInitializedVersion:8,
            dispatcher:{publish:function():Void {}},
            aabbCollider:{}, unitAI:{}, shield:{}};
        var visualRecord:Object = {mc:visualActor,
            projectionKind:"pet_projection", sourceId:"piece:visual"};
        check(WarlordActionEncounterService
                .testOnlyIsActorVisualReady(visualRecord, visualWorld),
            "C03 actor enters combat only after initialized visible bounds exist");
        var avatarVisual:Object = {_parent:visualWorld, _visible:true,
            _width:72, _height:120, version:8,
            __unitInitializedVersion:8,
            dispatcher:{publish:function():Void {}},
            aabbCollider:{}, shield:{}, 操控编号:0, hasDressup:true,
            攻击目标:"无"};
        for (slotIndex = 0; slotIndex < slotKeys.length; slotIndex++) {
            slotKey = String(slotKeys[slotIndex]);
            avatarVisual[slotKey] = equipmentRefs[slotKey];
        }
        RuntimeEquipmentProjection.beginCanonical(avatarVisual);
        RuntimeEquipmentProjection.completeCanonical(avatarVisual);
        var avatarVisualRecord:Object = {mc:avatarVisual,
            projectionKind:"player_avatar", sourceId:"piece:avatar-visual"};
        check(WarlordActionEncounterService
                .testOnlyIsActorVisualReady(avatarVisualRecord, visualWorld),
            "C03 fully dressed controlled avatar is ready without a unitAI");
        RuntimeEquipmentProjection.beginCanonical(avatarVisual);
        check(!WarlordActionEncounterService
                .testOnlyIsActorVisualReady(avatarVisualRecord, visualWorld),
            "C03 incomplete canonical equipment projection blocks combat arming");
        RuntimeEquipmentProjection.completeCanonical(avatarVisual);
        avatarVisual.操控编号 = -1;
        check(!WarlordActionEncounterService
                .testOnlyIsActorVisualReady(avatarVisualRecord, visualWorld),
            "C03 avatar misclassified as AI cannot enter combat");
        avatarVisual.操控编号 = 0;
        avatarVisual.hasDressup = false;
        check(!WarlordActionEncounterService
                .testOnlyIsActorVisualReady(avatarVisualRecord, visualWorld),
            "C03 undressed avatar cannot enter combat");
        avatarVisual.hasDressup = true;
        delete visualActor.unitAI;
        check(!WarlordActionEncounterService
                .testOnlyIsActorVisualReady(visualRecord, visualWorld),
            "C03 ordinary projected actor still requires its unitAI");
        visualActor.unitAI = {};
        visualActor.__unitInitializedVersion = null;
        check(!WarlordActionEncounterService
                .testOnlyIsActorVisualReady(visualRecord, visualWorld),
            "C03 incomplete StaticInitializer latch blocks combat arming");
        visualActor.__unitInitializedVersion = visualActor.version;
        visualActor._width = 0;
        check(!WarlordActionEncounterService
                .testOnlyIsActorVisualReady(visualRecord, visualWorld),
            "C03 zero-width paperdoll fails the visual readiness gate");
        visualActor._width = 72;
        visualActor._parent = {};
        check(!WarlordActionEncounterService
                .testOnlyIsActorVisualReady(visualRecord, visualWorld),
            "C03 detached actor cannot be armed by a later world");
        visualActor._parent = visualWorld;

        WarlordActionEncounterService.testOnlySetPreArmAiHold(
            visualRecord, true);
        check(visualActor._warlordActionAiHeld === true
                && visualRecord.aiHeld === true,
            "C03 pre-arm hold freezes only the projected AI unit");
        WarlordActionEncounterService.testOnlySetPreArmAiHold(
            visualRecord, false);
        check(visualActor._warlordActionAiHeld === false
                && visualRecord.aiHeld === false,
            "C03 arming releases the projected AI hold exactly once");
        WarlordActionEncounterService.testOnlySetPreArmAiHold(
            avatarVisualRecord, true);
        check(avatarVisual._warlordActionAiHeld === true
                && avatarVisualRecord.aiHeld === true,
            "C03 pre-arm safety hold also fences a misclassified avatar");

        var originalFade:Object = _root.淡出动画;
        _root.淡出动画 = {_currentframe:35};
        check(!WarlordActionEncounterService.testOnlyIsSceneRevealReady(),
            "C03 scene reveal waits before the standard idle frame");
        _root.淡出动画._currentframe = 36;
        check(WarlordActionEncounterService.testOnlyIsSceneRevealReady(),
            "C03 scene reveal accepts the main XFL empty idle frame");
        _root.淡出动画 = originalFade;

        var globalOriginal:Object = WarlordActionEncounterService
            .testOnlySnapshotGlobals();
        var drugCalls:Number = 0;
        _root.控制目标 = "outer.hero";
        _root.控制目标全自动 = true;
        _root.斗兽标定禁存档 = false;
        _root._agentCalibrationNoSave = false;
        var outerDrug:Object = function():Void { drugCalls++; };
        var outerPassive:Object = {probe:{count:1}};
        _root.使用药剂 = outerDrug;
        _root.主角被动技能 = outerPassive;
        var encounterSnapshot:Object = WarlordActionEncounterService
            .testOnlySnapshotGlobals();
        WarlordActionEncounterService.testOnlyApplyEncounterGlobals();
        var run:Object = {playerControlledSide:"blue", blueUnits:blue,
            redUnits:red, camera:{}, playerAvatar:null,
            playerControlReleased:false};
        check(WarlordActionEncounterService.testOnlyBindPlayerControl(run)
                && _root.控制目标 == avatarMc._name
                && _root.控制目标全自动 === false,
            "C03 exact avatar acquires keyboard control on either tactical side");
        _root.使用药剂("普通hp药剂");
        _root.主角被动技能.probe.count = 9;
        check(_root.斗兽标定禁存档 === true
                && _root._agentCalibrationNoSave === true
                && _root.主角被动技能 !== outerPassive
                && outerPassive.probe.count == 1 && drugCalls == 0,
            "C03 isolated encounter blocks saves and global drug consumption");
        WarlordActionEncounterService.testOnlyReleasePlayerControl(run, avatar);
        check(_root.控制目标 == "军阀动作镜头"
                && run.playerControlReleased === true
                && avatar.controlReleased === true,
            "C03 avatar down releases input to the encounter camera");
        WarlordActionEncounterService
            .testOnlyRestoreGlobals(encounterSnapshot);
        check(_root.控制目标 == "outer.hero"
                && _root.控制目标全自动 === true
                && _root.斗兽标定禁存档 === false
                && _root._agentCalibrationNoSave === false
                && _root.使用药剂 === outerDrug
                && _root.主角被动技能 === outerPassive
                && outerPassive.probe.count == 1 && drugCalls == 0,
            "C03 return restores the exact outer player globals");
        WarlordActionEncounterService.testOnlyRestoreGlobals(globalOriginal);
        _root.物品栏 = originalInventory;
    }

    private static function testAdmissionHandshake():Void {
        var originalServer:Object = _root.server;
        WarlordActionEncounterService.testOnlyResetStartAdmissionState();

        var pause:Object = makePauseAdapter(
            "lease9001", "webpanel", true);
        WarlordActionEncounterService.testOnlySetPanelPauseAdapter(pause);
        var released:Object = WarlordActionEncounterService
            .testOnlyReleasePanelPauseForStart();
        check(released.released === true && pause.releaseCalls == 1
                && pause.lease == undefined && pause.paused === false,
            "C04 fresh admission releases one exact webpanel lease");

        pause = makePauseAdapter("lease9002", "multiple_leases", true);
        WarlordActionEncounterService.testOnlySetPanelPauseAdapter(pause);
        var blocked:Object = WarlordActionEncounterService
            .testOnlyReleasePanelPauseForStart();
        check(blocked.released === false && pause.releaseCalls == 0
                && blocked.reasonCode
                    === "action.web-panel-lease-not-exclusive",
            "C04 non-exclusive pause authority is rejected without release");

        pause = makePauseAdapter("lease9003", "webpanel", true);
        pause.releaseLease = function(exact:String):Void {
            this.releaseCalls++;
            this.lease = "lease9004";
            this.owner = "webpanel";
            this.paused = true;
        };
        WarlordActionEncounterService.testOnlySetPanelPauseAdapter(pause);
        var replaced:Object = WarlordActionEncounterService
            .testOnlyReleasePanelPauseForStart();
        check(replaced.released === false && pause.lease === "lease9004"
                && replaced.reasonCode === "action.web-panel-unpause-blocked",
            "C04 a later panel lease is preserved and blocks fresh admission");

        pause = makePauseAdapter("lease9005", "webpanel", true);
        pause.releaseLease = function(exact:String):Void {
            this.releaseCalls++;
            this.owner = "unowned_pause";
            this.paused = true;
        };
        WarlordActionEncounterService.testOnlySetPanelPauseAdapter(pause);
        var stillPaused:Object = WarlordActionEncounterService
            .testOnlyReleasePanelPauseForStart();
        check(stillPaused.released === false && pause.lease == undefined
                && stillPaused.reasonCode === "action.web-panel-still-paused",
            "C04 clearing a lease is not accepted while gameplay remains paused");

        pause = makePauseAdapter(undefined, "none", false);
        WarlordActionEncounterService.testOnlySetPanelPauseAdapter(pause);
        var missing:Object = WarlordActionEncounterService
            .testOnlyReleasePanelPauseForStart();
        check(missing.released === false && pause.releaseCalls == 0
                && missing.reasonCode === "action.web-panel-lease-missing",
            "C04 fresh admission requires an exact generic panel lease");

        var start:Object = productStart();
        var accepted:Object = WarlordActionEncounterService
            .testOnlyBuildAdmission(start.binding,
                {accepted:true, disposition:"transition_pending"});
        check(WarlordActionEncounterService
                .testOnlyValidateAdmission(accepted),
            "C04 fresh admission satisfies the exact v1 receipt schema");
        check(countOwnKeys(accepted) == 4
                && countOwnKeys(accepted.binding) == 5,
            "C04 admission has four payload keys and a five-key v2 binding");
        check(accepted.binding !== start.binding
                && accepted.binding.requestId === start.binding.requestId,
            "C04 admission clones the exact request identity");
        check(accepted.disposition === "accepted"
                && accepted.phase === "entering",
            "C04 a fresh transition maps to accepted entering");

        var duplicate:Object = WarlordActionEncounterService
            .testOnlyBuildAdmission(start.binding,
                {accepted:true, disposition:"duplicate", phase:"active"});
        check(duplicate.disposition === "duplicate"
                && duplicate.phase === "active",
            "C04 exact duplicate reports its existing phase without rebuilding");
        check(WarlordActionEncounterService.testOnlyBuildAdmission(
                start.binding,
                {accepted:true, disposition:"accepted", phase:"entering"})
                    == null
                && WarlordActionEncounterService.testOnlyBuildAdmission(
                start.binding,
                {accepted:true, disposition:"duplicate", phase:"corrupt"})
                    == null,
            "C04 invalid outcome and phase fail closed instead of coercing admission");
        duplicate.extra = true;
        check(!WarlordActionEncounterService
                .testOnlyValidateAdmission(duplicate),
            "C04 extra admission payload fields fail closed");

        var sent:Array = [];
        _root.server = {sendTaskToNode:function(task:String,
                payload:Object, callback):Boolean {
            sent.push({task:task, payload:payload});
            return true;
        }};
        check(WarlordActionEncounterService
                .testOnlyTrySendAdmission(accepted),
            "C04 valid admission uses the existing AS2 task transport");
        check(sent[0].task === "warlord_action_encounter_admitted"
                && sent[0].payload !== accepted
                && WarlordActionEncounterService
                    .testOnlyValidateAdmission(sent[0].payload),
            "C04 transport sends a cloned exact admission payload");
        _root.server.sendTaskToNode = function():Boolean { return false; };
        check(!WarlordActionEncounterService
                .testOnlyTrySendAdmission(accepted),
            "C04 a false transport result is not misreported as an ACK");

        var notStarted:Object = WarlordActionEncounterService
            .testOnlyBuildFailureTerminal(start.binding, "not_started",
                "action.web-panel-unpause-blocked");
        check(notStarted.status === "not_started"
                && notStarted.result == null
                && notStarted.requestId === start.binding.requestId
                && countOwnKeys(notStarted) == 8,
            "C04 unpause failure produces one exact binding-matched terminal");

        // send=true 后 terminal 仍是 binding 级吸收态；同 binding start 必须在
        // inspector、pause 和 begin 之前重投。
        WarlordActionEncounterService.testOnlyResetStartAdmissionState();
        sent = [];
        _root.server = {sendTaskToNode:function(task:String,
                payload:Object, callback):Boolean {
            sent.push({task:task, payload:payload});
            return true;
        }};
        check(WarlordActionEncounterService.deliverTerminal(notStarted),
            "C04 a local terminal send succeeds without retiring absorption");
        var remembered:Object = WarlordActionEncounterService
            .testOnlyGetAbsorbingTerminal(start.binding);
        check(remembered != null && remembered.status === "not_started",
            "C04 sent terminal remains frozen for the exact binding");
        var inspectCalls:Number = 0;
        var beginCalls:Number = 0;
        var terminalManager:Object = {
            inspectWarlordActionEncounter:function(binding:Object):Object {
                inspectCalls++;
                return {accepted:true, disposition:"fresh", phase:"prepared"};
            },
            beginWarlordActionEncounter:function(binding:Object,
                    control:Object):Object {
                beginCalls++;
                return {accepted:true, disposition:"transition_pending"};
            }
        };
        pause = makePauseAdapter("lease9010", "webpanel", true);
        WarlordActionEncounterService.testOnlySetPanelPauseAdapter(pause);
        WarlordActionEncounterService.testOnlyHandleStartWithManager(
            start, terminalManager);
        check(sent.length == 2
                && sent[1].task === "warlord_action_encounter_terminal"
                && sent[1].payload.status === "not_started",
            "C04 same-binding retry replays the original terminal after send true");
        check(inspectCalls == 0 && beginCalls == 0
                && pause.releaseCalls == 0 && pause.lease === "lease9010",
            "C04 absorbing terminal prevents all retry side effects");

        // StageManager 自己冻结的 terminal 同样在 pause 前重投。
        WarlordActionEncounterService.testOnlyResetStartAdmissionState();
        sent = [];
        beginCalls = 0;
        var stageTerminalManager:Object = {
            inspectWarlordActionEncounter:function(binding:Object):Object {
                return {accepted:true, disposition:"duplicate",
                    terminal:notStarted};
            },
            beginWarlordActionEncounter:function(binding:Object,
                    control:Object):Object {
                beginCalls++;
                return null;
            }
        };
        pause = makePauseAdapter("lease90105", "webpanel", true);
        WarlordActionEncounterService.testOnlySetPanelPauseAdapter(pause);
        WarlordActionEncounterService.testOnlyHandleStartWithManager(
            start, stageTerminalManager);
        check(sent.length == 1
                && sent[0].task === "warlord_action_encounter_terminal"
                && beginCalls == 0 && pause.releaseCalls == 0,
            "C04 StageManager terminal replay precedes fresh pause release");

        // StageManager exact duplicate 也必须在 unpause 前 ACK，保留后来 lease。
        WarlordActionEncounterService.testOnlyResetStartAdmissionState();
        sent = [];
        inspectCalls = 0;
        beginCalls = 0;
        var duplicateManager:Object = {
            inspectWarlordActionEncounter:function(binding:Object):Object {
                inspectCalls++;
                return {accepted:true, disposition:"duplicate", phase:"active"};
            },
            beginWarlordActionEncounter:function(binding:Object,
                    control:Object):Object {
                beginCalls++;
                return null;
            }
        };
        pause = makePauseAdapter("lease9011", "webpanel", true);
        WarlordActionEncounterService.testOnlySetPanelPauseAdapter(pause);
        WarlordActionEncounterService.testOnlyHandleStartWithManager(
            start, duplicateManager);
        check(inspectCalls == 1 && beginCalls == 0
                && pause.releaseCalls == 0 && pause.lease === "lease9011",
            "C04 duplicate admission never releases a later panel lease");
        check(sent.length == 1
                && sent[0].task === "warlord_action_encounter_admitted"
                && sent[0].payload.disposition === "duplicate"
                && sent[0].payload.phase === "active",
            "C04 duplicate admission stops Host retry with the existing phase");

        // Host Timer callback 可能已越过 active 检查，随后才在同 generation
        // 写出旧 binding。新 B 已 active 时必须无副作用丢弃迟到 A，尤其不能让
        // A 的发送失败 terminal 占住 pending 并吞掉 B 的真实完成 terminal。
        WarlordActionEncounterService.testOnlyResetStartAdmissionState();
        sent = [];
        inspectCalls = 0;
        beginCalls = 0;
        var terminalSendAllowed:Boolean = false;
        _root.server = {sendTaskToNode:function(task:String,
                payload:Object, callback):Boolean {
            sent.push({task:task, payload:payload});
            return terminalSendAllowed;
        }};
        var oldStart:Object = productStart();
        var currentStart:Object = productStart();
        currentStart.binding.encounterId = "enc.current";
        currentStart.binding.requestId = "request.current";
        currentStart.binding.inputDigest =
            "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
        var activeManager:Object = {
            inspectWarlordActionEncounter:function(binding:Object):Object {
                inspectCalls++;
                return {accepted:false, disposition:"rejected",
                    reasonCode:"encounter_active"};
            },
            beginWarlordActionEncounter:function(binding:Object,
                    control:Object):Object {
                beginCalls++;
                return null;
            }
        };
        pause = makePauseAdapter("lease90115", "webpanel", true);
        WarlordActionEncounterService.testOnlySetPanelPauseAdapter(pause);
        WarlordActionEncounterService.testOnlyHandleStartWithManager(
            oldStart, activeManager);
        check(inspectCalls == 1 && beginCalls == 0
                && pause.releaseCalls == 0 && pause.lease === "lease90115",
            "C04 stale binding against an active encounter has no start side effects");
        check(sent.length == 0,
            "C04 encounter_active stale retry emits no synthetic terminal");
        check(WarlordActionEncounterService
                .testOnlyGetAbsorbingTerminal(oldStart.binding) == null,
            "C04 encounter_active stale retry creates no absorbing terminal");

        var currentTerminal:Object = WarlordActionEncounterService
            .testOnlyBuildFailureTerminal(currentStart.binding, "unknown",
                "action.current-terminal");
        check(!WarlordActionEncounterService.deliverTerminal(currentTerminal)
                && sent.length == 1
                && sent[0].task === "warlord_action_encounter_terminal"
                && sent[0].payload.requestId === "request.current",
            "C04 current terminal remains pending after its first send fails");
        terminalSendAllowed = true;
        WarlordActionEncounterService.retryPendingTerminal();
        WarlordActionEncounterService.retryPendingTerminal();
        check(sent.length == 2
                && sent[1].task === "warlord_action_encounter_terminal"
                && sent[1].payload.requestId === "request.current"
                && WarlordActionEncounterService.testOnlyGetAbsorbingTerminal(
                    currentStart.binding) != null,
            "C04 pending current terminal retries once and remains absorbing");

        // fresh start 只释放一次，随后才进入 manager 并发 accepted receipt。
        WarlordActionEncounterService.testOnlyResetStartAdmissionState();
        sent = [];
        inspectCalls = 0;
        beginCalls = 0;
        var freshManager:Object = {
            inspectWarlordActionEncounter:function(binding:Object):Object {
                inspectCalls++;
                return {accepted:true, disposition:"fresh", phase:"prepared"};
            },
            beginWarlordActionEncounter:function(binding:Object,
                    control:Object):Object {
                beginCalls++;
                return {accepted:true, disposition:"transition_pending",
                    reasonCode:"scene_transition_pending"};
            }
        };
        pause = makePauseAdapter("lease9012", "webpanel", true);
        WarlordActionEncounterService.testOnlySetPanelPauseAdapter(pause);
        WarlordActionEncounterService.testOnlyHandleStartWithManager(
            start, freshManager);
        check(inspectCalls == 1 && beginCalls == 1
                && pause.releaseCalls == 1 && pause.lease == undefined,
            "C04 fresh start releases exactly once before StageManager begin");
        check(sent.length == 1
                && sent[0].task === "warlord_action_encounter_admitted"
                && sent[0].payload.disposition === "accepted"
                && sent[0].payload.phase === "entering",
            "C04 fresh transition sends accepted entering admission");

        // begin 抛错后的二次 inspector 是提交事实裁判；active 必须 ACK，不能 terminal。
        WarlordActionEncounterService.testOnlyResetStartAdmissionState();
        sent = [];
        var committed:Boolean = false;
        var throwingManager:Object = {
            inspectWarlordActionEncounter:function(binding:Object):Object {
                return committed
                    ? {accepted:true, disposition:"duplicate", phase:"active"}
                    : {accepted:true, disposition:"fresh", phase:"prepared"};
            },
            beginWarlordActionEncounter:function(binding:Object,
                    control:Object):Object {
                committed = true;
                throw new Error("expected post-commit throw");
                return null;
            }
        };
        pause = makePauseAdapter("lease9013", "webpanel", true);
        WarlordActionEncounterService.testOnlySetPanelPauseAdapter(pause);
        WarlordActionEncounterService.testOnlyHandleStartWithManager(
            start, throwingManager);
        check(sent.length == 1
                && sent[0].task === "warlord_action_encounter_admitted"
                && sent[0].payload.disposition === "duplicate",
            "C04 post-commit throw recovers admission instead of false terminal");
        check(WarlordActionEncounterService
                .testOnlyGetAbsorbingTerminal(start.binding) == null,
            "C04 post-commit recovery does not poison the binding with terminal");

        // 未提交 throw 经 inspector 明确仍 fresh 后，冻结 unknown 且不可再开战。
        WarlordActionEncounterService.testOnlyResetStartAdmissionState();
        sent = [];
        var preCommitManager:Object = {
            inspectWarlordActionEncounter:function(binding:Object):Object {
                return {accepted:true, disposition:"fresh", phase:"prepared"};
            },
            beginWarlordActionEncounter:function(binding:Object,
                    control:Object):Object {
                throw new Error("expected pre-commit throw");
                return null;
            }
        };
        pause = makePauseAdapter("lease9014", "webpanel", true);
        WarlordActionEncounterService.testOnlySetPanelPauseAdapter(pause);
        WarlordActionEncounterService.testOnlyHandleStartWithManager(
            start, preCommitManager);
        remembered = WarlordActionEncounterService
            .testOnlyGetAbsorbingTerminal(start.binding);
        check(sent.length == 1
                && sent[0].task === "warlord_action_encounter_terminal"
                && sent[0].payload.status === "unknown",
            "C04 proven pre-commit throw emits one exact unknown terminal");
        check(remembered != null && remembered.status === "unknown",
            "C04 pre-commit unknown remains absorbing for later retries");

        WarlordActionEncounterService.testOnlyResetStartAdmissionState();
        _root.server = originalServer;
    }

    private static function makePauseAdapter(
            lease, owner:String, paused:Boolean):Object {
        var adapter:Object = {
            lease:lease,
            owner:owner,
            paused:paused,
            releaseCalls:0,
            clearCalls:0
        };
        adapter.getLease = function() {
            return this.lease;
        };
        adapter.getOwner = function():String {
            return String(this.owner);
        };
        adapter.isPaused = function():Boolean {
            return this.paused === true;
        };
        adapter.releaseLease = function(exact:String):Void {
            this.releaseCalls++;
            if (this.lease !== exact) return;
            this.owner = "none";
            this.paused = false;
        };
        adapter.clearLeaseIfExact = function(exact):Void {
            this.clearCalls++;
            if (this.lease === exact) this.lease = undefined;
        };
        return adapter;
    }

    private static function productStart():Object {
        var blue:Object = {projectionKind:"pet_projection",
            sourceId:"piece:alpha", petId:0,
            identifier:"狙击兵", rosterType:"pet", level:10,
            hpPermille:1000, strategicPromotions:[]};
        var red:Object = {projectionKind:"pet_projection",
            sourceId:"piece:beta", petId:1,
            identifier:"突击兵", rosterType:"pet", level:10,
            hpPermille:1000, strategicPromotions:[]};
        return {task:"cmd", action:"warlord_action_encounter_start",
            binding:{schema:"warlord.action-encounter-binding.v2",
                outerRunId:"run.product", encounterId:"enc.product",
                requestId:"request.product",
                inputDigest:"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"},
            encounter:{schema:"warlord.action-encounter-control.v2",
                battleId:"warlord-product", blueRoster:[blue],
                redRoster:[red], timeoutFrames:3600, spawnDistance:360,
                blueFormation:"wedge", redFormation:"line",
                formationSpacing:54, authorityContext:{},
                playerControlledSide:"none"}};
    }

    private static function playerAvatarStart(side:String):Object {
        var value:Object = productStart();
        var avatar:Object = {projectionKind:"player_avatar",
            sourceId:"piece:avatar", commanderId:"commander.player",
            characterId:"character.player-avatar", factionId:"player",
            hpPermille:1000};
        value.encounter.playerControlledSide = side;
        if (side == "red") value.encounter.redRoster.unshift(avatar);
        else value.encounter.blueRoster.unshift(avatar);
        return value;
    }

    private static function deploymentBounded(value:Object):Boolean {
        var sides:Array = [value.blue, value.red];
        for (var s:Number = 0; s < sides.length; s++) {
            for (var i:Number = 0; i < sides[s].length; i++) {
                var point:Object = sides[s][i];
                if (point.x < 230 || point.x > 1560
                        || point.y < 242 || point.y > 620) return false;
            }
        }
        return true;
    }

    private static function pointSignature(points:Array):String {
        var out:String = "";
        for (var i:Number = 0; i < points.length; i++) {
            out += String(points[i].x) + "," + String(points[i].y) + ";";
        }
        return out;
    }

    private static function uniqueStringCount(values:Array):Number {
        var seen:Object = {};
        var count:Number = 0;
        for (var i:Number = 0; i < values.length; i++) {
            if (seen[String(values[i])] !== true) {
                seen[String(values[i])] = true;
                count++;
            }
        }
        return count;
    }

    private static function sidesOverlap(value:Object):Boolean {
        for (var i:Number = 0; i < value.blue.length; i++) {
            for (var j:Number = 0; j < value.red.length; j++) {
                if (value.blue[i].x == value.red[j].x
                        && value.blue[i].y == value.red[j].y) return true;
            }
        }
        return false;
    }

    private static function countOwnKeys(value:Object):Number {
        var count:Number = 0;
        for (var key:String in value) {
            if (Object.prototype.hasOwnProperty.call(value, key)) count++;
        }
        return count;
    }

    private static function check(condition:Boolean, message:String):Void {
        if (condition) {
            passed++;
            trace("[PASS] " + message);
        } else {
            failed++;
            trace("[FAIL] " + message);
        }
    }
}
