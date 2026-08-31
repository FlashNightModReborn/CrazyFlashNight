import org.flashNight.arki.key.KeyManager;
import org.flashNight.arki.ui.GameSettingsPanelService;
import org.flashNight.arki.item.ItemUtil;
import org.flashNight.arki.item.LootContainerService;
import org.flashNight.arki.item.itemCollection.ArrayInventory;
import org.flashNight.arki.item.itemCollection.DictCollection;
import org.flashNight.arki.item.itemCollection.InformationCollection;
import org.flashNight.arki.scene.StageRunSession;
import org.flashNight.arki.weather.WeatherSystem;
import org.flashNight.neur.Server.SaveManager;

/** 设置 Web Panel 的键位、试听、作弊与强制控制回归测试。 */
class org.flashNight.arki.ui.GameSettingsPanelServiceTest {
    private static var passed:Number = 0;
    private static var failed:Number = 0;

    public static function runAllTests():Void {
        passed = 0;
        failed = 0;
        setup();
        testKeyTableMigration();
        testSnapshotMigrationLatch();
        testUnchangedLegacyReservedKeyDoesNotBlockSettingsApply();
        testSubscriptionFollowsRebind();
        testVersionAndAudioPreview();
        testCheatHelpBoundary();
        testRawCheatsConservativelyMarkDirty();
        testPartiallyAppliedSaveCheatRequiresReconcile();
        testForceControls();
        testOpenPanelEnvelope();
        testResponseEnvelope();
        testReturnBaseWireEnvelope();
        trace("GameSettingsPanelServiceTest Tests Passed: " + passed);
        trace("GameSettingsPanelServiceTest Tests Failed: " + failed);
    }

    private static function setup():Void {
        if (_root.gameCommands == undefined) _root.gameCommands = {};
        GameSettingsPanelService.install();
        resetState();
    }

    private static function resetState():Void {
        LootContainerService.testOnlyReset();
        StageRunSession.testOnlyReset();
        KeyManager.clearPendingKeySettingsMigration();
        SaveManager.getInstance().clearPendingSettingsMigration();
        _root.存档系统 = {dirtyMark:false};
        _root.difficultyMode = 0;
        _root.isChallengeMode = function():Boolean {
            return Number(_root.difficultyMode) == 2;
        };
        _root.cheatFunction = {
            status:function():Void {},
            challengemode:function():Void {}
        };
        _root.lastCheat = "";
        _root.cheatCode = function(command:String):Void {
            _root.lastCheat = command;
            if (command == "challengemode") _root.difficultyMode = 2;
        };
        _root.returnBaseCalls = 0;
        _root.返回基地 = function():Void { _root.returnBaseCalls++; };
        _root.关卡结束界面 = undefined;
        _root.soundEffectManager = createSoundManager(60, 40);
    }

    private static function createSoundManager(globalVolume:Number, bgmVolume:Number):Object {
        return {
            globalVolume:globalVolume,
            bgmVolume:bgmVolume,
            lastSound:"",
            getGlobalVolume:function():Number { return Number(this.globalVolume); },
            getBGMVolume:function():Number { return Number(this.bgmVolume); },
            setGlobalVolume:function(value:Number):Void { this.globalVolume = value; },
            setBGMVolume:function(value:Number):Void { this.bgmVolume = value; },
            playSound:function(name:String):Void { this.lastSound = name; },
            jukeboxOverride:false,
            trueRandom:false,
            playMode:"albumLoop",
            getJukeboxOverride:function():Boolean { return this.jukeboxOverride; },
            getTrueRandom:function():Boolean { return this.trueRandom; },
            getPlayMode:function():String { return this.playMode; },
            setJukeboxOverride:function(value:Boolean):Void { this.jukeboxOverride = value; },
            setTrueRandom:function(value:Boolean):Void { this.trueRandom = value; },
            setPlayMode:function(value:String):Void { this.playMode = value; }
        };
    }

    private static function buildDefaults():Array {
        var codes:Array = [87,83,65,68,74,75,82,49,50,51,52,53,54,55,56,57,48,
            32,85,73,79,80,76,72,71,67,66,78,77,47,69,70,18,81,16,17];
        var rows:Array = [];
        for (var i:Number = 0; i < 36; i++) {
            rows.push(["键位" + i, "测试键" + i, codes[i]]);
        }
        rows[12] = ["药剂组切换", "药剂组切换键", 54];
        rows[34] = ["奔跑", "奔跑键", 16];
        rows[35] = ["组合", "组合键", 17];
        return rows;
    }

    private static function testKeyTableMigration():Void {
        var defaults:Array = buildDefaults();
        var historic:Array = KeyManager.copyKeySettings(defaults);
        historic.splice(34, 2);
        historic.splice(12, 1);
        historic[0][2] = 90;
        historic.push(["未知", "未注册键", 88]);

        var copied:Array = KeyManager.copyKeySettings(historic);
        check(copied.length == 34 && copied[0][1] == "测试键0" && copied[0][2] == 90,
            "copyKeySettings copies valid triples");
        copied[0][2] = 65;
        check(historic[0][2] == 90,
            "copyKeySettings returns a deep row copy");

        var normalized:Array = KeyManager.normalizeKeySettings(historic, defaults);
        check(normalized.length == 36,
            "historic 33-key table is expanded to the 36-key authority shape");
        check(normalized[0][2] == 90 && normalized[12][1] == "药剂组切换键"
            && normalized[12][2] == 54 && normalized[34][1] == "奔跑键"
            && normalized[35][1] == "组合键",
            "migration preserves custom bindings and appends switch, run and combination keys");
        check(normalized[33][1] == "测试键33" && normalized[35][1] != "未注册键",
            "migration discards unknown logical ids");

        historic[1][2] = 999;
        normalized = KeyManager.normalizeKeySettings(historic, defaults);
        check(normalized[1][2] == defaults[1][2],
            "invalid historical keycodes fall back to the authority default");
    }

    private static function testSnapshotMigrationLatch():Void {
        var defaults:Array = buildDefaults();
        var historic:Array = KeyManager.copyKeySettings(defaults);
        historic.splice(12, 1);
        historic[0][2] = 54;
        _root.默认键值设定 = defaults;
        _root.键值设定 = historic;
        _root.按键设定表 = [[0, 0, 0, 0]];
        _root.刷新键值设定 = function():Void {
            KeyManager.refreshKeySettings(_root.键值设定, null, _root.按键设定表[0]);
        };
        _root.帧计时器 = {性能等级上限:3};
        _root.是否阴影 = true;
        _root.是否视觉元素 = true;
        _root.cameraZoomToggle = true;
        _root.basicZoomScale = 1;
        _root.立绘类型 = 1;
        var weather:WeatherSystem = WeatherSystem.getInstance();
        weather.enableDayNightCycle = true;
        weather.pauseDayNightCycle = false;
        weather.useFilterRendering = true;

        // 模拟真实 load 顺序：键位与性能在设置面板第一次 snapshot 前已经被读档路径归一。
        _root.刷新键值设定();
        SaveManager.getInstance().applySettings({性能等级上限:3});
        var keyMigrationLatched:Boolean = KeyManager.hasPendingKeySettingsMigration();
        var settingsMigrationLatched:Boolean = SaveManager.getInstance().hasPendingSettingsMigration();
        _root.键值设定[0][0] = undefined;

        var first:Object = GameSettingsPanelService.execute("snapshot", {v:1});
        check(first.success && first.keySchemaVersion == 2 && first.keys.length == 36
            && first.defaultKeys.length == 36
            && first.settings.性能等级上限 == 1 && _root.帧计时器.性能等级上限 == 1
            && keyMigrationLatched && settingsMigrationLatched
            && first.keys[0].label == first.keys[0].id,
            "snapshot normalizes legacy performance and projects the explicit 36-key schema");
        check(first.keys[0].keyCode == 54 && first.keys[12].id == "药剂组切换键"
            && first.keys[12].keyCode == 84 && first.keys[34].id == "奔跑键"
            && first.keys[35].id == "组合键" && first.migrationPending
            && typeof first.keyMigrationNotice == "string"
            && first.keyMigrationNotice.length > 0 && first.keyMigrationNotice.length <= 160
            && first.keyMigrationNotice.indexOf("保留原有数字 6 绑定") >= 0,
            "conflicting historic 6 remains bound while the switch fallback is disclosed once");

        var second:Object = GameSettingsPanelService.execute("snapshot", {v:1});
        check(second.success && second.migrationPending,
            "migration save latch survives a second snapshot until a durable save");

        var applyKeys:Array = [];
        for (var i:Number = 0; i < second.keys.length; i++) {
            applyKeys.push({id:second.keys[i].id, keyCode:second.keys[i].keyCode});
        }
        var refresh:Function = _root.刷新键值设定;
        _root.允许存档 = true;
        _root.刷新键值设定 = function():Void { throw new Error("settings apply test"); };
        var ambiguous:Object = GameSettingsPanelService.execute("apply", {
            v:1,
            keySchemaVersion:2,
            expectedRevision:second.revision,
            settings:second.settings,
            keys:applyKeys
        });
        _root.刷新键值设定 = refresh;
        check(!ambiguous.success && ambiguous.error == "apply_ambiguous"
            && ambiguous.requiresReconcile,
            "an exception after apply begins reports an ambiguous result instead of inviting replay");
        var reconciled:Object = GameSettingsPanelService.execute("snapshot", {v:1});
        check(reconciled.success && reconciled.keySchemaVersion == 2
            && reconciled.keys.length == 36,
            "the next authority snapshot retries a pending key-cache refresh before adoption");

        KeyManager.clearPendingKeySettingsMigration();
        SaveManager.getInstance().clearPendingSettingsMigration();
        var cleared:Object = GameSettingsPanelService.execute("snapshot", {v:1});
        check(cleared.success && !cleared.migrationPending
            && cleared.keyMigrationNotice == "",
            "clearing the per-save migration latches cannot leak pending state into another slot");

        var noConflictHistoric:Array = KeyManager.copyKeySettings(defaults);
        noConflictHistoric.splice(12, 1);
        _root.键值设定 = noConflictHistoric;
        _root.刷新键值设定();
        var defaultMigration:Object = GameSettingsPanelService.execute("snapshot", {v:1});
        check(defaultMigration.success && defaultMigration.keys[12].keyCode == 54
            && defaultMigration.keyMigrationNotice == "",
            "an unoccupied default 6 migrates silently while the notice field remains present");
        KeyManager.clearPendingKeySettingsMigration();
    }

    private static function testSubscriptionFollowsRebind():Void {
        var callback:Function = function():Void {};
        var defaults:Array = [["动作一", "动作一键", 65], ["动作二", "动作二键", 66]];
        _root.默认键值设定 = defaults;
        var controls:Array = [0, 0, 0, 0];
        KeyManager.refreshKeySettings(KeyManager.copyKeySettings(defaults), null, controls);
        KeyManager.onKeyDown("动作一键", callback, _root);
        check(KeyManager.getKeySetting("动作一键") == 65
            && KeyManager.resolvesWatchedBinding("动作一键", 65),
            "logical subscription initially resolves to its physical key");

        var rebound:Array = [["动作一", "动作一键", 67], ["动作二", "动作二键", 66]];
        KeyManager.refreshKeySettings(rebound, null, controls);
        check(KeyManager.getKeySetting("动作一键") == 67
            && KeyManager.resolvesWatchedBinding("动作一键", 67),
            "existing subscription follows the new physical key after refresh");
        check(!KeyManager.resolvesWatchedBinding("动作一键", 65),
            "old physical key no longer publishes the rebound logical event");

        var shared:Array = [["动作一", "动作一键", 68], ["动作二", "动作二键", 68]];
        KeyManager.onKeyDown("动作二键", callback, _root);
        KeyManager.refreshKeySettings(shared, null, controls);
        check(KeyManager.resolvesWatchedBinding("动作一键", 68)
            && KeyManager.resolvesWatchedBinding("动作二键", 68),
            "duplicate legacy bindings retain both logical event routes");
        KeyManager.offKeyDown("动作一键", callback);
        KeyManager.offKeyDown("动作二键", callback);
    }

    private static function testUnchangedLegacyReservedKeyDoesNotBlockSettingsApply():Void {
        resetState();
        _root.默认键值设定 = buildDefaults();
        _root.键值设定 = KeyManager.copyKeySettings(_root.默认键值设定);
        _root.键值设定[0][2] = 112; // 历史存档中的 F1；新面板已把它列为保留键。
        _root.按键设定表 = [[0, 0, 0, 0]];
        _root.刷新键值设定 = function():Void {
            KeyManager.refreshKeySettings(_root.键值设定, null, _root.按键设定表[0]);
        };
        _root.刷新键值设定();
        _root.帧计时器 = {性能等级上限:1};
        _root.是否阴影 = true;
        _root.是否视觉元素 = true;
        _root.cameraZoomToggle = true;
        _root.basicZoomScale = 1;
        _root.立绘类型 = 1;

        var snapshot:Object = GameSettingsPanelService.execute("snapshot", {v:1});
        var keys:Array = [];
        for (var i:Number = 0; i < snapshot.keys.length; i++) {
            keys.push({id:snapshot.keys[i].id, keyCode:snapshot.keys[i].keyCode});
        }

        var oldAllowSave = _root.允许存档;
        _root.允许存档 = false; // 停在 validator 之后，避免本测试真实落盘。
        var missingSchema:Object = GameSettingsPanelService.execute("apply", {
            v:1, expectedRevision:snapshot.revision, settings:snapshot.settings, keys:keys
        });
        var wrongSchema:Object = GameSettingsPanelService.execute("apply", {
            v:1, keySchemaVersion:1, expectedRevision:snapshot.revision,
            settings:snapshot.settings, keys:keys
        });
        check(!missingSchema.success && missingSchema.error == "invalid_payload"
            && !wrongSchema.success && wrongSchema.error == "invalid_payload",
            "apply requires explicit keySchemaVersion 2 and never infers it from 36 rows");
        var unchanged:Object = GameSettingsPanelService.execute("apply", {
            v:1, keySchemaVersion:2, expectedRevision:snapshot.revision,
            settings:snapshot.settings, keys:keys
        });
        check(!unchanged.success && unchanged.error == "save_unavailable",
            "unchanged legacy reserved binding no longer blocks an otherwise valid settings apply");

        keys[1].keyCode = 113; // 新把另一个动作分配到 F2，必须继续 fail-closed。
        var reassigned:Object = GameSettingsPanelService.execute("apply", {
            v:1, keySchemaVersion:2, expectedRevision:snapshot.revision,
            settings:snapshot.settings, keys:keys
        });
        check(!reassigned.success && reassigned.error == "reserved_key",
            "new assignments to reserved function keys remain rejected");
        _root.允许存档 = oldAllowSave;
    }

    private static function testVersionAndAudioPreview():Void {
        resetState();
        var badVersion:Object = GameSettingsPanelService.execute("preview", {
            v:2, globalVolume:20, bgmVolume:30, sample:"none"
        });
        var badCommand:Object = GameSettingsPanelService.execute("missing", {v:1});
        check(!badVersion.success && badVersion.error == "unsupported_version"
            && !badCommand.success && badCommand.error == "unsupported_cmd",
            "protocol version and command gates fail closed");

        var invalid:Object = GameSettingsPanelService.execute("preview", {
            v:1, globalVolume:101, bgmVolume:30, sample:"none"
        });
        check(!invalid.success && invalid.error == "invalid_payload"
            && _root.soundEffectManager.globalVolume == 60,
            "invalid audio preview changes no runtime volume");

        var preview:Object = GameSettingsPanelService.execute("preview", {
            v:1, globalVolume:20, bgmVolume:30, sample:"sfx"
        });
        check(preview.success && preview.previewActive && preview.samplePlayed
            && _root.soundEffectManager.globalVolume == 20
            && _root.soundEffectManager.bgmVolume == 30
            && _root.soundEffectManager.lastSound == "Button9.wav",
            "audio preview applies live values and plays the existing sample cue");

        var cancel:Object = GameSettingsPanelService.execute("cancel", {v:1});
        check(cancel.success && cancel.previewRestored
            && _root.soundEffectManager.globalVolume == 60
            && _root.soundEffectManager.bgmVolume == 40,
            "cancel restores the original audio baseline");
        check(!GameSettingsPanelService.execute("cancel", {v:1}).previewRestored,
            "cancel is idempotent after the preview baseline is restored");

        GameSettingsPanelService.execute("preview", {
            v:1, globalVolume:10, bgmVolume:15, sample:"none"
        });
        var closed:Object = GameSettingsPanelService.execute("panel_closed", {v:1});
        check(closed.previewRestored && _root.soundEffectManager.globalVolume == 60
            && _root.soundEffectManager.bgmVolume == 40,
            "panel close restores uncommitted audio preview");

        var partial:Object = createSoundManager(60, 40);
        partial.throwPreviewBgm = true;
        partial.setBGMVolume = function(value:Number):Void {
            if (this.throwPreviewBgm && value == 30) throw new Error("preview bgm setter");
            this.bgmVolume = value;
        };
        _root.soundEffectManager = partial;
        var failedPreview:Object = GameSettingsPanelService.execute("preview", {
            v:1, globalVolume:20, bgmVolume:30, sample:"none"
        });
        check(!failedPreview.success && failedPreview.error == "audio_preview_failed"
            && failedPreview.previewRestored && !failedPreview.previewActive
            && partial.globalVolume == 60 && partial.bgmVolume == 40,
            "partial preview setter failure immediately restores both baseline volumes");

        var retryable:Object = createSoundManager(60, 40);
        retryable.throwRestoreBgm = false;
        retryable.setBGMVolume = function(value:Number):Void {
            if (this.throwRestoreBgm && value == 40) throw new Error("restore bgm setter");
            this.bgmVolume = value;
        };
        _root.soundEffectManager = retryable;
        GameSettingsPanelService.execute("preview", {
            v:1, globalVolume:20, bgmVolume:30, sample:"none"
        });
        retryable.throwRestoreBgm = true;
        var firstRestore:Object = GameSettingsPanelService.execute("cancel", {v:1});
        retryable.throwRestoreBgm = false;
        var secondRestore:Object = GameSettingsPanelService.execute("panel_closed", {v:1});
        check(!firstRestore.previewRestored && firstRestore.previewActive
            && retryable.globalVolume == 60
            && secondRestore.previewRestored && !secondRestore.previewActive
            && retryable.globalVolume == 60 && retryable.bgmVolume == 40,
            "failed restore keeps its baseline and remains retryable until both setters succeed");
    }

    private static function testCheatHelpBoundary():Void {
        resetState();
        var unconfirmed:Object = GameSettingsPanelService.execute("cheat", {
            v:1, command:"status", confirmed:false
        });
        check(!unconfirmed.success && unconfirmed.error == "invalid_payload"
            && _root.lastCheat == "",
            "cheat execution requires explicit confirmation");

        var normalParams:Object = {
            v:1, command:"status", confirmed:true
        };
        var normal:Object = GameSettingsPanelService.execute("cheat", normalParams);
        check(normal.success && normal.effectScope == "read" && normal.cheatHelp.length > 3
            && _root.lastCheat == "status" && !_root.存档系统.dirtyMark,
            "normal modes retain full cheat help and read-only diagnostics");

        var supply:Object = GameSettingsPanelService.execute("cheat", {
            v:1, command:"#supplytime:20", confirmed:true
        });
        var supplyHelpFound:Boolean = false;
        for (var i:Number = 0; i < supply.cheatHelp.length; i++) {
            if (String(supply.cheatHelp[i].command) == "#supplytime:10") {
                supplyHelpFound = supply.cheatHelp[i].effectScope == "session";
                break;
            }
        }
        check(supply.success && supply.effectScope == "session" && supplyHelpFound
                && _root.lastCheat == "#supplytime:20"
                && !_root.存档系统.dirtyMark,
            "online supply frame-time cheat is session-scoped and visible in normal help");

        var challenge:Object = GameSettingsPanelService.execute("cheat", {
            v:1, command:"challengemode", confirmed:true
        });
        check(challenge.success && challenge.challengeMode && challenge.cheatHelp.length == 3
            && challenge.effectScope == "save" && _root.存档系统.dirtyMark,
            "challenge mode exposes only the three mode-switch commands");

        var unknown:Object = GameSettingsPanelService.execute("cheat", {
            v:1, command:"definitely_unknown", confirmed:true
        });
        check(!unknown.success && unknown.error == "unknown_command",
            "unknown cheat commands never reach the backend");
    }

    private static function testRawCheatsConservativelyMarkDirty():Void {
        resetState();
        var commands:Array = [
            "#get:宠物信息.splice(0,1)",
            "#eval:_root.宠物信息.splice(0,1)",
            "#set:等级=50",
            "#_root.等级=50;int",
            "#func:_root.返回基地()",
            "#code:_root.等级=50"
        ];
        var allMarked:Boolean = true;
        for (var i:Number = 0; i < commands.length; i++) {
            _root.存档系统.dirtyMark = false;
            var response:Object = GameSettingsPanelService.execute("cheat", {
                v:1, command:commands[i], confirmed:true
            });
            if (!response.success || response.effectScope != "save"
                    || response.dirty !== true || _root.存档系统.dirtyMark !== true) {
                allMarked = false;
            }
        }
        check(allMarked,
            "all accepted expression and raw control prefixes conservatively mark save state dirty");
    }

    private static function testPartiallyAppliedSaveCheatRequiresReconcile():Void {
        resetState();
        _root.partialCheatWrite = 0;
        _root.cheatCode = function(command:String):Void {
            _root.partialCheatWrite = 50;
            throw new Error("post-write UI refresh failed");
        };
        var response:Object = GameSettingsPanelService.execute("cheat", {
            v:1, command:"#level:50", confirmed:true
        });
        check(!response.success && response.error == "command_ambiguous"
            && response.effectScope == "save" && response.requiresReconcile
            && response.dirty === true && _root.存档系统.dirtyMark === true
            && _root.partialCheatWrite == 50,
            "save cheat partial write is marked dirty and reported as requiring reconciliation");
    }

    private static function testForceControls():Void {
        resetState();
        var extraField:Object = GameSettingsPanelService.execute("return_base", {
            v:1, confirmed:true
        });
        check(!extraField.success && extraField.error == "invalid_payload"
            && _root.returnBaseCalls == 0,
            "return-to-base rejects stale confirmation payloads instead of widening the protocol");

        var returned:Object = GameSettingsPanelService.execute("return_base", {
            v:1
        });
        check(returned.success && returned.closePanel && _root.returnBaseCalls == 1,
            "return-to-base is a single-click delegation to the existing authoritative flow");

        var revive:Object = GameSettingsPanelService.execute("try_revive", {
            v:1
        });
        check(!revive.success && revive.error == "revive_unavailable",
            "try-revive fails closed when no authoritative stage run is awaiting revival");

        _root.gameworld = {};
        _root.控制目标 = "__settings_test_hero__";
        _root.限制系统 = {DisableResurrection:false};
        _root.物品栏 = {
            背包:new ArrayInventory(null, 50),
            仓库:new ArrayInventory(null, 1200),
            战备箱:new ArrayInventory(null, 400),
            药剂栏:new ArrayInventory(null, 8)
        };
        _root.收集品栏 = {
            材料:new DictCollection(null),
            情报:new InformationCollection(null)
        };
        var materialDict:Object = ItemUtil.materialDict;
        if (materialDict == undefined) {
            materialDict = {};
            ItemUtil.materialDict = materialDict;
        }
        var previousReviveCoin:Object = materialDict["复活币"];
        materialDict["复活币"] = true;
        _root.收集品栏.材料.add("复活币", 1);
        var hero:MovieClip = _root.createEmptyMovieClip(
            "__settingsTestHero", _root.getNextHighestDepth());
        hero.hp = 0;
        hero.hp满血值 = 100;
        hero.dispatcher = {};
        hero.dispatcher.publish = function(eventName:String):Void {
            if (eventName != "respawn") return;
            hero.hp = hero.hp满血值;
            StageRunSession.onHeroRespawn(hero);
        };
        _root.gameworld[_root.控制目标] = hero;
        StageRunSession.begin("设置页复活兜底", "测试");
        StageRunSession.onHeroDeath();
        _root.默认键值设定 = buildDefaults();
        _root.键值设定 = KeyManager.copyKeySettings(_root.默认键值设定);
        _root.按键设定表 = [[0, 0, 0, 0]];
        _root.刷新键值设定 = function():Void {
            KeyManager.refreshKeySettings(_root.键值设定, null, _root.按键设定表[0]);
        };
        _root.帧计时器 = {性能等级上限:1};
        var available:Object = GameSettingsPanelService.execute("snapshot", {v:1});
        var recovered:Object = GameSettingsPanelService.execute("try_revive", {
            v:1
        });
        check(available.success && available.forceControls.tryReviveAvailable,
            "try-revive is advertised only while the authoritative stage run is dead");
        check(recovered.success && recovered.revived && recovered.closePanel
            && recovered.reviveCoins == 0,
            "try-revive delegates to the shared idempotent revive path and closes on success");
        check(hero.hp == 100 && ItemUtil.getTotal("复活币") == 0
            && StageRunSession.testOnlySnapshot().life == "alive",
            "settings recovery restores the current hero and spends exactly one revive coin");
        hero.removeMovieClip();
        if (previousReviveCoin == undefined) delete materialDict["复活币"];
        else materialDict["复活币"] = previousReviveCoin;
    }

    private static function testOpenPanelEnvelope():Void {
        resetState();
        _root.server = undefined;
        check(!GameSettingsPanelService.openPanel(),
            "settings open fails closed when socket sender is unavailable");

        _root.server = {sent:"", result:true};
        _root.server.sendSocketMessage = function(message:String):Boolean {
            this.sent = message;
            return this.result;
        };
        check(GameSettingsPanelService.openPanel() && _root.server.sent
            == '{"task":"panel_request","panel":"settings","source":"as2_settings_request"}',
            "settings open emits the exact one-route panel_request envelope");

        _root.server.result = false;
        check(!GameSettingsPanelService.openPanel(),
            "settings open propagates transport failure without a Flash UI fallback");
    }

    private static function testResponseEnvelope():Void {
        resetState();
        _root.server = {sent:""};
        _root.server.sendSocketMessage = function(message:String):Boolean {
            this.sent = message;
            return true;
        };
        _root.gameCommands["settingsPreviewAudio"]({
            v:1, callId:71, globalVolume:25, bgmVolume:35, sample:"none"
        });
        var response:Object = new LiteJSON().parse(String(_root.server.sent));
        check(response.task == "settings_response" && response.callId == 71
            && response.success && response.operation == "preview"
            && response.globalVolume == 25 && response.bgmVolume == 35,
            "command handler emits a parseable settings_response with the exact callId");
        GameSettingsPanelService.execute("panel_closed", {v:1});
    }

    private static function testReturnBaseWireEnvelope():Void {
        resetState();
        var previousFade:Object = _root.淡出动画;
        _root.淡出动画 = {
            accepted:false,
            淡出跳转帧:function(frame:String):Void { this.accepted = true; }
        };
        _root.返回基地 = function():Boolean {
            _root.returnBaseCalls++;
            _root.淡出动画.淡出跳转帧("基地门口");
            return true;
        };
        _root.server = {sent:"", sentAfterTransition:false};
        _root.server.sendSocketMessage = function(message:String):Boolean {
            this.sent = message;
            this.sentAfterTransition = _root.淡出动画.accepted === true;
            return true;
        };

        _root.gameCommands["settingsReturnBase"]({v:2, callId:7300});
        var rejected:Object = new LiteJSON().parse(String(_root.server.sent));
        check(_root.returnBaseCalls == 0
            && rejected.task == "settings_response" && rejected.callId == 7300
            && !rejected.success && rejected.error == "unsupported_version",
            "return-to-base wire rejects non-v1 requests before transition authority");

        _root.gameCommands["settingsReturnBase"]({v:1, callId:7301});
        var response:Object = new LiteJSON().parse(String(_root.server.sent));
        check(_root.returnBaseCalls == 1 && _root.server.sentAfterTransition === true
            && response.task == "settings_response" && response.callId == 7301
            && response.success && response.operation == "return_base"
            && response.closePanel === true,
            "return-to-base wire responds after authority commit with the exact callId");
        _root.淡出动画 = previousFade;
    }

    private static function check(ok:Boolean, label:String):Void {
        if (ok) {
            passed++;
            trace("[PASS] " + label);
        } else {
            failed++;
            trace("[TEST_FAIL] " + label);
        }
    }
}
