import org.flashNight.arki.key.KeyManager;
import org.flashNight.neur.Server.SaveManager;
import org.flashNight.arki.unit.UnitComponent.Targetcache.TargetCacheManager;

/**
 * 游戏设置 Web Panel 的 AS2 权威服务。
 *
 * Web 只持有草稿与展示状态；设置、36 键、作弊码和强制流程均在此重新校验。
 * 音量试听只改变本次运行态，并由 cancel/panelClosed 恢复；apply 是唯一设置写入口。
 */
class org.flashNight.arki.ui.GameSettingsPanelService {
    private static var _installed:Boolean = false;
    private static var _json:LiteJSON;
    private static var _revision:Number = 0;
    private static var _lastFingerprint:String;
    private static var _previewBaseline:Object;
    private static var _previewRestoreTimer:Number;
    private static var _keyRefreshPending:Boolean = false;

    public static function install():Void {
        if (_installed) return;
        _installed = true;
        if (_root.gameCommands == undefined) _root.gameCommands = {};
        _root.gameCommands["settingsSnapshot"] = function(params):Void {
            org.flashNight.arki.ui.GameSettingsPanelService.handle("snapshot", params);
        };
        _root.gameCommands["settingsPreviewAudio"] = function(params):Void {
            org.flashNight.arki.ui.GameSettingsPanelService.handle("preview", params);
        };
        _root.gameCommands["settingsApply"] = function(params):Void {
            org.flashNight.arki.ui.GameSettingsPanelService.handle("apply", params);
        };
        _root.gameCommands["settingsCancel"] = function(params):Void {
            org.flashNight.arki.ui.GameSettingsPanelService.handle("cancel", params);
        };
        _root.gameCommands["settingsSave"] = function(params):Void {
            org.flashNight.arki.ui.GameSettingsPanelService.handle("save", params);
        };
        _root.gameCommands["settingsCheat"] = function(params):Void {
            org.flashNight.arki.ui.GameSettingsPanelService.handle("cheat", params);
        };
        _root.gameCommands["settingsReturnBase"] = function(params):Void {
            org.flashNight.arki.ui.GameSettingsPanelService.handle("return_base", params);
        };
        _root.gameCommands["settingsTryRevive"] = function(params):Void {
            org.flashNight.arki.ui.GameSettingsPanelService.handle("try_revive", params);
        };
        _root.gameCommands["settingsPanelClosed"] = function(params):Void {
            org.flashNight.arki.ui.GameSettingsPanelService.execute("panel_closed", {v:1});
        };
        _root.gameCommands["openSettings"] = function():Boolean {
            return org.flashNight.arki.ui.GameSettingsPanelService.openPanel();
        };
    }

    public static function openPanel():Boolean {
        if (_root.server == undefined || _root.server.sendSocketMessage == undefined) return false;
        var payload:String = org.flashNight.arki.ui.PanelRequestEnvelope.build(
            "settings", "as2_settings_request", [], []
        );
        return _root.server.sendSocketMessage(payload);
    }

    public static function handle(commandName:String, params:Object):Void {
        var request:Object = params == undefined ? {} : params;
        var callId:Number = Number(request.callId);
        if (isNaN(callId)) callId = 0;
        var response:Object = execute(commandName, request);
        response.task = "settings_response";
        response.callId = callId;
        sendResponse(response);
    }

    public static function execute(commandName:String, params:Object):Object {
        if (params == undefined || params.v !== 1) return fail("unsupported_version");
        switch (commandName) {
            case "snapshot": return executeSnapshot();
            case "preview": return executePreview(params);
            case "apply": return executeApply(params);
            case "cancel": return executeCancel();
            case "save": return executeSave();
            case "cheat": return executeCheat(params);
            case "return_base": return executeReturnBase(params);
            case "try_revive": return executeTryRevive(params);
            case "panel_closed": return executeCancel();
        }
        return fail("unsupported_cmd");
    }

    private static function executeSnapshot():Object {
        var readiness:Object = ensureAuthorityReady();
        if (!readiness.success) return readiness;
        syncRevision();
        var snapshot:Object = buildSnapshot();
        snapshot.success = true;
        snapshot.v = 1;
        snapshot.operation = "snapshot";
        snapshot.migrationPending = readiness.migrationPending == true;
        return snapshot;
    }

    private static function executePreview(params:Object):Object {
        if (!hasOnly(params, ["task", "action", "callId", "v", "globalVolume", "bgmVolume", "sample"])) {
            return fail("invalid_payload");
        }
        var globalVolume:Number = Number(params.globalVolume);
        var bgmVolume:Number = Number(params.bgmVolume);
        var sample:String = String(params.sample);
        if (!isIntegerInRange(globalVolume, 0, 100)
                || !isIntegerInRange(bgmVolume, 0, 100)
                || (sample != "none" && sample != "sfx")) {
            return fail("invalid_payload");
        }
        if (_root.soundEffectManager == undefined) return fail("audio_unavailable");
        if (_previewBaseline == undefined) {
            try {
                _previewBaseline = {
                    globalVolume:Number(_root.soundEffectManager.getGlobalVolume()),
                    bgmVolume:Number(_root.soundEffectManager.getBGMVolume())
                };
            } catch (baselineError) {
                _previewBaseline = undefined;
                return fail("audio_unavailable");
            }
        }
        var played:Boolean = false;
        try {
            // 先建立恢复租约，再执行任一可能留下部分副作用的 setter。
            armPreviewRestoreTimer();
            _root.soundEffectManager.setGlobalVolume(globalVolume);
            _root.soundEffectManager.setBGMVolume(bgmVolume);
            if (sample == "sfx" && typeof _root.soundEffectManager.playSound == "function") {
                _root.soundEffectManager.playSound("Button9.wav");
                played = true;
            }
        } catch (previewError) {
            var restored:Boolean = restoreAudioPreview();
            return {
                success:false,
                v:1,
                operation:"preview",
                error:"audio_preview_failed",
                previewRestored:restored,
                previewActive:_previewBaseline != undefined
            };
        }
        return {
            success:true,
            v:1,
            operation:"preview",
            previewActive:true,
            globalVolume:globalVolume,
            bgmVolume:bgmVolume,
            samplePlayed:played
        };
    }

    private static function executeCancel():Object {
        var restored:Boolean = restoreAudioPreview();
        return {
            success:true,
            v:1,
            operation:"cancel",
            previewRestored:restored,
            previewActive:_previewBaseline != undefined
        };
    }

    private static function executeApply(params:Object):Object {
        if (!hasOnly(params, ["task", "action", "callId", "v", "keySchemaVersion",
                "expectedRevision", "settings", "keys"])
                || typeof params.keySchemaVersion != "number"
                || params.keySchemaVersion !== 2) {
            return fail("invalid_payload");
        }
        var readiness:Object = ensureAuthorityReady();
        if (!readiness.success) return readiness;
        syncRevision();
        var expectedRevision:Number = Number(params.expectedRevision);
        if (!isIntegerInRange(expectedRevision, 0, 2147483647)) return fail("invalid_payload");
        if (expectedRevision != _revision) {
            var stale:Object = buildSnapshot();
            stale.success = false;
            stale.v = 1;
            stale.error = "stale_state";
            stale.operation = "apply";
            stale.migrationPending = hasPendingMigration();
            return stale;
        }

        var normalizedSettings:Object = validateSettings(params.settings);
        if (normalizedSettings == null) return fail("invalid_settings");
        var normalizedKeys:Object = validateKeyBindings(params.keys);
        if (!normalizedKeys.success) return normalizedKeys;
        if (_root.存档系统 == undefined || typeof _root.存档系统 != "object"
                || typeof _root.刷新键值设定 != "function"
                || _root.允许存档 !== true) {
            return fail("save_unavailable");
        }

        try {
            SaveManager.getInstance().applySettings(normalizedSettings);
            _root.键值设定 = normalizedKeys.keys;
            _keyRefreshPending = true;
            _root.刷新键值设定();
            _keyRefreshPending = false;
        } catch (applyError) {
            clearPreviewRestoreTimer();
            _previewBaseline = undefined;
            markDirty();
            try { syncRevision(); } catch (reconcileError) {}
            return {
                success:false,
                v:1,
                operation:"apply",
                error:"apply_ambiguous",
                requiresReconcile:true,
                revision:_revision
            };
        }
        clearPreviewRestoreTimer();
        _previewBaseline = undefined;
        markDirty();
        _revision++;
        _lastFingerprint = buildFingerprint();

        var durable:Boolean = false;
        try {
            durable = SaveManager.getInstance().flushNow() === true;
        } catch (saveError) {
            durable = false;
        }
        if (durable) {
            KeyManager.clearPendingKeySettingsMigration();
            SaveManager.getInstance().clearPendingSettingsMigration();
        }
        var response:Object = buildSnapshot();
        response.success = durable;
        response.applied = true;
        response.durable = durable;
        response.v = 1;
        response.operation = "apply";
        response.migrationPending = hasPendingMigration();
        if (!durable) {
            response.error = "save_failed";
            response.needsSaveRetry = true;
        }
        return response;
    }

    private static function executeSave():Object {
        if (_root.存档系统 == undefined || _root.允许存档 !== true) return fail("save_unavailable");
        var durable:Boolean = false;
        try {
            durable = SaveManager.getInstance().flushNow() === true;
        } catch (saveError) {
            durable = false;
        }
        if (durable) {
            KeyManager.clearPendingKeySettingsMigration();
            SaveManager.getInstance().clearPendingSettingsMigration();
        }
        var response:Object = {
            success:durable,
            v:1,
            operation:"save",
            durable:durable,
            needsSaveRetry:!durable,
            revision:_revision,
            migrationPending:hasPendingMigration()
        };
        if (!durable) response.error = "save_failed";
        return response;
    }

    private static function executeCheat(params:Object):Object {
        if (!hasOnly(params, ["task", "action", "callId", "v", "command", "confirmed"])
                || params.confirmed !== true || typeof params.command != "string") {
            return fail("invalid_payload");
        }
        var command:String = trim(String(params.command));
        if (command.length == 0 || command.length > 240
                || command.indexOf("\n") >= 0 || command.indexOf("\r") >= 0) {
            return fail("invalid_payload");
        }
        if (typeof _root.cheatCode != "function") return fail("cheat_unavailable");
        var classification:Object = classifyCheat(command);
        if (classification == null) return fail("unknown_command");
        var mayWriteSave:Boolean = classification.effectScope == "save";
        // 作弊后端里有多条“先改权威字段、后刷新 UI/发布事件”的路径。
        // 后段一旦抛错，调用方无法证明前段没有生效；必须在进入后端前先置脏，
        // 并把异常报告为需对账的未知写，不能把部分写伪装成确定未执行。
        if (mayWriteSave) markDirty();
        try {
            _root.cheatCode(command);
        } catch (cheatError) {
            if (mayWriteSave) {
                return {
                    success:false,
                    v:1,
                    operation:"cheat",
                    error:"command_ambiguous",
                    command:command,
                    effectScope:"save",
                    dirty:_root.存档系统 != undefined && _root.存档系统.dirtyMark === true,
                    requiresReconcile:true
                };
            }
            return fail("command_failed");
        }
        return {
            success:true,
            v:1,
            operation:"cheat",
            accepted:true,
            command:command,
            effectScope:classification.effectScope,
            dirty:_root.存档系统 != undefined && _root.存档系统.dirtyMark === true,
            challengeMode:isChallengeMode(),
            modeLabel:modeLabel(),
            cheatHelp:buildCheatHelp(),
            message:"命令已由游戏端执行；具体结果请查看游戏内提示。"
        };
    }

    private static function executeReturnBase(params:Object):Object {
        if (!hasOnly(params, ["task", "action", "callId", "v"])) return fail("invalid_payload");
        if (typeof _root.返回基地 != "function") return fail("return_base_unavailable");
        try {
            var accepted = _root.返回基地();
            if (accepted === false) return fail("settlement_prepare_failed");
        } catch (returnError) {
            return fail("return_base_failed");
        }
        return {success:true, v:1, operation:"return_base", closePanel:true};
    }

    private static function executeTryRevive(params:Object):Object {
        if (!hasOnly(params, ["task", "action", "callId", "v"])) return fail("invalid_payload");
        var result:Object = org.flashNight.arki.scene.StageRunSession.requestReviveLocal(
            "settings_recovery");
        if (result == null || result.success !== true) {
            return fail(result == null || result.error == undefined
                ? "revive_failed" : String(result.error));
        }
        return {
            success:true,
            v:1,
            operation:"try_revive",
            revived:true,
            reviveCoins:Number(result.reviveCoins),
            closePanel:true
        };
    }

    private static function ensureAuthorityReady():Object {
        if (_root.默认键值设定 == undefined || !(_root.默认键值设定 instanceof Array)
                || _root.默认键值设定.length != 36 || _root.键值设定 == undefined
                || typeof _root.刷新键值设定 != "function"
                || _root.soundEffectManager == undefined || _root.帧计时器 == undefined) {
            return fail("settings_unavailable");
        }
        if (_keyRefreshPending) {
            try {
                _root.刷新键值设定();
                _keyRefreshPending = false;
            } catch (pendingRefreshError) {
                return fail("key_refresh_failed");
            }
        }
        var migrationPending:Boolean = KeyManager.hasPendingKeySettingsMigration()
            || SaveManager.getInstance().hasPendingSettingsMigration();
        var normalized:Array = KeyManager.normalizeKeySettings(
            _root.键值设定, _root.默认键值设定
        );
        if (!sameKeySettings(_root.键值设定, normalized)) {
            _root.键值设定 = normalized;
            _keyRefreshPending = true;
            try {
                _root.刷新键值设定();
                _keyRefreshPending = false;
            } catch (migrationRefreshError) {
                SaveManager.getInstance().markSettingsMigrationPending();
                markDirty();
                return fail("key_refresh_failed");
            }
            migrationPending = true;
            SaveManager.getInstance().markSettingsMigrationPending();
        }
        var performance:Number = Number(_root.帧计时器.性能等级上限);
        var normalizedPerformance:Number = (isNaN(performance) || performance <= 0) ? 0 : 1;
        if (performance != normalizedPerformance) {
            _root.帧计时器.性能等级上限 = normalizedPerformance;
            migrationPending = true;
            SaveManager.getInstance().markSettingsMigrationPending();
        }
        if (migrationPending) {
            markDirty();
        }
        return {success:true, migrationPending:migrationPending};
    }

    private static function hasPendingMigration():Boolean {
        return KeyManager.hasPendingKeySettingsMigration()
            || SaveManager.getInstance().hasPendingSettingsMigration();
    }

    private static function buildSnapshot():Object {
        var settings:Object = readAuthoritySettings();
        return {
            keySchemaVersion:2,
            revision:_revision,
            settings:settings,
            keys:projectKeyBindings(),
            defaultKeys:projectDefaultBindings(),
            allowedKeyCodes:projectAllowedKeyCodes(),
            challengeMode:isChallengeMode(),
            modeLabel:modeLabel(),
            cheatHelp:buildCheatHelp(),
            forceControls:buildForceControls(),
            previewActive:_previewBaseline != undefined,
            keyMigrationNotice:buildKeyMigrationNotice()
        };
    }

    private static function buildKeyMigrationNotice():String {
        var info:Object = null;
        try {
            info = KeyManager.getPendingKeySettingsMigrationInfo();
        } catch (migrationInfoError) {
            info = null;
        }
        if (info == null || String(info.id) != "药剂组切换键"
                || Number(info.defaultCode) != 54
                || !isIntegerInRange(Number(info.assignedCode), 0, 255)
                || Number(info.assignedCode) == Number(info.defaultCode)) {
            return "";
        }
        var assignedName:String = KeyManager.getKeyName(
            Number(info.assignedCode));
        if (assignedName == undefined || assignedName == null
                || String(assignedName) == "") {
            assignedName = String(info.assignedCode);
        }
        var notice:String = "已保留原有数字 6 绑定；药剂组切换已分配为 "
            + String(assignedName) + "。";
        return notice.length > 160 ? notice.substring(0, 160) : notice;
    }

    private static function readAuthoritySettings():Object {
        var settings:Object = SaveManager.getInstance().packSettings();
        settings.性能等级上限 = Number(settings.性能等级上限) <= 0 ? 0 : 1;
        if (_previewBaseline != undefined) {
            settings.setGlobalVolume = _previewBaseline.globalVolume;
            settings.setBGMVolume = _previewBaseline.bgmVolume;
        }
        return settings;
    }

    private static function projectKeyBindings():Array {
        var projected:Array = [];
        for (var i:Number = 0; i < _root.键值设定.length; i++) {
            var row:Array = _root.键值设定[i];
            var id:String = String(row[1]);
            var label:String = (row[0] == undefined || row[0] == null)
                ? id : trim(String(row[0]));
            if (label.length == 0 || label == "undefined" || label == "null") label = id;
            projected.push({
                index:i,
                label:label,
                id:id,
                keyCode:Number(row[2]),
                keyName:KeyManager.getKeyName(Number(row[2]))
            });
        }
        return projected;
    }

    private static function projectDefaultBindings():Array {
        var projected:Array = [];
        for (var i:Number = 0; i < _root.默认键值设定.length; i++) {
            var row:Array = _root.默认键值设定[i];
            projected.push({id:String(row[1]), keyCode:Number(row[2])});
        }
        return projected;
    }

    private static function projectAllowedKeyCodes():Array {
        var codes:Array = KeyManager.getAllKeycodes();
        codes.sort(Array.NUMERIC);
        var projected:Array = [];
        for (var i:Number = 0; i < codes.length; i++) {
            var code:Number = Number(codes[i]);
            if (!isReservedKey(code)) projected.push({code:code, name:KeyManager.getKeyName(code)});
        }
        return projected;
    }

    private static function validateSettings(value:Object):Object {
        if (value == undefined || typeof value != "object" || !hasOnly(value, [
            "setGlobalVolume", "setBGMVolume", "性能等级上限", "是否阴影",
            "是否视觉元素", "cameraZoomToggle", "basicZoomScale",
            "开启昼夜系统", "暂停昼夜系统", "使用滤镜渲染", "立绘类型",
            "jukeboxOverride", "jukeboxTrueRandom", "jukeboxPlayMode"
        ])) return null;
        if (!isIntegerInRange(Number(value.setGlobalVolume), 0, 100)
                || !isIntegerInRange(Number(value.setBGMVolume), 0, 100)
                || !isIntegerInRange(Number(value.性能等级上限), 0, 1)
                || !isNumberInRange(Number(value.basicZoomScale), 0.5, 3)
                || !isIntegerInRange(Number(value.立绘类型), 1, 2)
                || !isBoolean(value.是否阴影) || !isBoolean(value.是否视觉元素)
                || !isBoolean(value.cameraZoomToggle)
                || !isBoolean(value.开启昼夜系统) || !isBoolean(value.暂停昼夜系统)
                || !isBoolean(value.使用滤镜渲染) || !isBoolean(value.jukeboxOverride)
                || !isBoolean(value.jukeboxTrueRandom)
                || (value.jukeboxPlayMode != "singleLoop"
                    && value.jukeboxPlayMode != "albumLoop"
                    && value.jukeboxPlayMode != "playOnce")) return null;
        return {
            setGlobalVolume:Number(value.setGlobalVolume),
            setBGMVolume:Number(value.setBGMVolume),
            性能等级上限:Number(value.性能等级上限),
            是否阴影:value.是否阴影,
            是否视觉元素:value.是否视觉元素,
            cameraZoomToggle:value.cameraZoomToggle,
            basicZoomScale:Math.round(Number(value.basicZoomScale) * 10) / 10,
            开启昼夜系统:value.开启昼夜系统,
            暂停昼夜系统:value.暂停昼夜系统,
            使用滤镜渲染:value.使用滤镜渲染,
            立绘类型:Number(value.立绘类型),
            jukeboxOverride:value.jukeboxOverride,
            jukeboxTrueRandom:value.jukeboxTrueRandom,
            jukeboxPlayMode:String(value.jukeboxPlayMode)
        };
    }

    private static function validateKeyBindings(value:Object):Object {
        if (!(value instanceof Array) || value.length != _root.默认键值设定.length) {
            return fail("invalid_keys");
        }
        var seen:Object = {};
        var normalized:Array = [];
        for (var i:Number = 0; i < _root.默认键值设定.length; i++) {
            var binding:Object = value[i];
            var authority:Array = _root.默认键值设定[i];
            if (binding == undefined || typeof binding != "object"
                    || !hasOnly(binding, ["id", "keyCode"])
                    || typeof binding.id != "string" || String(binding.id) != String(authority[1])) {
                return fail("invalid_keys");
            }
            var code:Number = Number(binding.keyCode);
            if (!isIntegerInRange(code, 0, 255) || !KeyManager.hasKeyName(code)) {
                return fail("reserved_key");
            }
            if (isReservedKey(code)) {
                // 历史存档可能早于面板保留键规则，已经持有 F1-F12/Esc。
                // 完整 apply 必须允许原样携带该旧绑定，否则只改音量也会被卡死；
                // 但任何新分配到保留键的请求仍然拒绝。
                var current:Array = _root.键值设定[i];
                var unchangedLegacy:Boolean = current instanceof Array
                    && current.length >= 3
                    && String(current[1]) == String(binding.id)
                    && Number(current[2]) == code;
                if (!unchangedLegacy) return fail("reserved_key");
            }
            if (seen[code] === true) return fail("key_conflict");
            seen[code] = true;
            normalized.push([authority[0], String(authority[1]), code]);
        }
        return {success:true, keys:normalized};
    }

    private static function restoreAudioPreview():Boolean {
        if (_previewBaseline == undefined) {
            clearPreviewRestoreTimer();
            return false;
        }
        if (_root.soundEffectManager == undefined) {
            armPreviewRestoreTimer();
            return false;
        }
        var globalRestored:Boolean = false;
        var bgmRestored:Boolean = false;
        try {
            _root.soundEffectManager.setGlobalVolume(Number(_previewBaseline.globalVolume));
            globalRestored = true;
        } catch (globalRestoreError) {}
        try {
            _root.soundEffectManager.setBGMVolume(Number(_previewBaseline.bgmVolume));
            bgmRestored = true;
        } catch (bgmRestoreError) {}
        if (globalRestored && bgmRestored) {
            clearPreviewRestoreTimer();
            _previewBaseline = undefined;
            return true;
        }
        // 任一 setter 失败都保留原始基线并重新挂恢复租约；下一次 timer、cancel
        // 或 panel_closed 仍可继续恢复，不能把部分污染永久化。
        armPreviewRestoreTimer();
        return false;
    }

    private static function armPreviewRestoreTimer():Void {
        clearPreviewRestoreTimer();
        var timerId:Number;
        timerId = setInterval(function():Void {
            clearInterval(timerId);
            _previewRestoreTimer = undefined;
            org.flashNight.arki.ui.GameSettingsPanelService.execute("panel_closed", {v:1});
        }, 30000);
        _previewRestoreTimer = timerId;
    }

    private static function clearPreviewRestoreTimer():Void {
        if (_previewRestoreTimer != undefined) clearInterval(_previewRestoreTimer);
        _previewRestoreTimer = undefined;
    }

    private static function syncRevision():Void {
        var fingerprint:String = buildFingerprint();
        if (_lastFingerprint == undefined) {
            _lastFingerprint = fingerprint;
        } else if (_lastFingerprint != fingerprint) {
            _revision++;
            _lastFingerprint = fingerprint;
        }
    }

    private static function buildFingerprint():String {
        var settings:Object = readAuthoritySettings();
        var parts:Array = [
            settings.setGlobalVolume, settings.setBGMVolume, settings.性能等级上限,
            settings.是否阴影, settings.是否视觉元素,
            settings.cameraZoomToggle, settings.basicZoomScale, settings.开启昼夜系统,
            settings.暂停昼夜系统, settings.使用滤镜渲染, settings.立绘类型,
            settings.jukeboxOverride, settings.jukeboxTrueRandom, settings.jukeboxPlayMode
        ];
        for (var i:Number = 0; i < _root.键值设定.length; i++) {
            parts.push(String(_root.键值设定[i][1]) + ":" + Number(_root.键值设定[i][2]));
        }
        return parts.join("|");
    }

    private static function sameKeySettings(left:Array, right:Array):Boolean {
        if (!(left instanceof Array) || !(right instanceof Array) || left.length != right.length) return false;
        for (var i:Number = 0; i < left.length; i++) {
            if (!(left[i] instanceof Array) || String(left[i][1]) != String(right[i][1])
                    || Number(left[i][2]) != Number(right[i][2])) return false;
        }
        return true;
    }

    private static function buildForceControls():Object {
        var hero:MovieClip;
        try { hero = TargetCacheManager.findHero(); } catch (findError) { hero = undefined; }
        return {
            returnBaseAvailable:typeof _root.返回基地 == "function",
            tryReviveAvailable:org.flashNight.arki.scene.StageRunSession.canRequestRevive(),
            resurrectionRestricted:_root.限制系统 != undefined
                && _root.限制系统.DisableResurrection == true
        };
    }

    private static function isChallengeMode():Boolean {
        return typeof _root.isChallengeMode == "function"
            ? _root.isChallengeMode() == true : Number(_root.difficultyMode) == 2;
    }

    private static function modeLabel():String {
        var labels:Array = ["困难", "简单", "挑战"];
        var mode:Number = Number(_root.difficultyMode);
        return mode >= 0 && mode < labels.length ? String(labels[mode]) : "未知";
    }

    private static function buildCheatHelp():Array {
        var modeOnly:Array = [
            {command:"hardmode", description:"切换到困难模式", effectScope:"save"},
            {command:"easymode", description:"切换到简单模式", effectScope:"save"},
            {command:"challengemode", description:"切换到挑战模式", effectScope:"save"}
        ];
        if (isChallengeMode()) return modeOnly;
        return modeOnly.concat([
            {command:"status / scene", description:"查看玩家或场景状态", effectScope:"read"},
            {command:"heal / god", description:"回血或切换无敌（本次运行）", effectScope:"session"},
            {command:"#level:15 / #gold:99999 / #sp:99", description:"修改角色进度", effectScope:"save"},
            {command:"#give:物品名,数量", description:"给予物品", effectScope:"save"},
            {command:"#task:链名,进度", description:"修改任务链进度", effectScope:"save"},
            {command:"#spawn:兵种,等级 / #tp:x,y", description:"召唤或传送（当前场景）", effectScope:"session"},
            {command:"#get / #eval / #set / #_root / #func / #code", description:"高级表达式与原始控制，保守按存档写入处理", effectScope:"save"}
        ]);
    }

    private static function classifyCheat(command:String):Object {
        if (_root.cheatFunction != undefined && typeof _root.cheatFunction[command] == "function") {
            if (command == "status" || command == "scene" || command == "taskprogress"
                    || command == "taskstatus") return {effectScope:"read"};
            if (command == "easymode" || command == "hardmode" || command == "challengemode"
                    || command == "getallmods" || command == "getallintelligence"
                    || command == "unlockkills" || command == "unlockallenemies"
                    || command == "arenakills") return {effectScope:"save"};
            return {effectScope:"session"};
        }
        if (startsWith(command, "#get:") || startsWith(command, "#eval:")) {
            // 两种求值器都允许属性路径中的函数调用，读取语法并不等于无副作用；
            // 无法证明表达式纯读时必须按 save 处理，避免 splice 等调用静默改存档。
            return {effectScope:"save"};
        }
        if (startsWith(command, "#level:") || startsWith(command, "#gold:")
                || startsWith(command, "#sp:") || startsWith(command, "#give:")
                || startsWith(command, "#task:") || (startsWith(command, "..")
                    && !isNaN(Number(command.substring(2))))) return {effectScope:"save"};
        if (startsWith(command, "#spawn:") || startsWith(command, "#tp:")
                || startsWith(command, "#change:")) return {effectScope:"session"};
        if (startsWith(command, "#set:") || startsWith(command, "#_root.")
                || startsWith(command, "#func:_root.") || startsWith(command, "#code:")) {
            // raw 控制可直接写 _root 或调用任意根函数，无法可靠证明只影响会话态；
            // 一律按 save 分类，宁可多一次持久化，也不能让已接受的存档写静默丢失。
            return {effectScope:"save"};
        }
        return null;
    }

    private static function markDirty():Void {
        if (_root.存档系统 != undefined) _root.存档系统.dirtyMark = true;
        try { SaveManager.getInstance().markDirty(); } catch (dirtyError) {}
    }

    private static function isReservedKey(code:Number):Boolean {
        return code == 27 || (code >= 112 && code <= 123);
    }

    private static function hasOnly(value:Object, allowed:Array):Boolean {
        if (value == undefined || typeof value != "object") return false;
        for (var key:String in value) {
            var matched:Boolean = false;
            for (var i:Number = 0; i < allowed.length; i++) {
                if (String(key) == String(allowed[i])) {
                    matched = true;
                    break;
                }
            }
            // AS2 的 Object.prototype.hasOwnProperty.call 在部分 AVM1 路径上不稳定；
            // 直接拒绝任何未登记的可枚举字段，仍保持 fail-closed。
            if (!matched) return false;
        }
        return true;
    }

    private static function isBoolean(value:Object):Boolean {
        return value === true || value === false;
    }

    private static function isIntegerInRange(value:Number, minimum:Number, maximum:Number):Boolean {
        return !isNaN(value) && value != Infinity && value != -Infinity
            && Math.floor(value) == value && value >= minimum && value <= maximum;
    }

    private static function isNumberInRange(value:Number, minimum:Number, maximum:Number):Boolean {
        return !isNaN(value) && value != Infinity && value != -Infinity
            && value >= minimum && value <= maximum;
    }

    private static function startsWith(value:String, prefix:String):Boolean {
        return value.indexOf(prefix) == 0;
    }

    private static function trim(value:String):String {
        var start:Number = 0;
        var end:Number = value.length;
        while (start < end && value.charCodeAt(start) <= 32) start++;
        while (end > start && value.charCodeAt(end - 1) <= 32) end--;
        return value.substring(start, end);
    }

    private static function fail(errorCode:String):Object {
        return {success:false, v:1, error:errorCode};
    }

    private static function sendResponse(response:Object):Void {
        if (_root.server == undefined || _root.server.sendSocketMessage == undefined) return;
        if (_json == undefined) _json = new LiteJSON();
        _root.server.sendSocketMessage(_json.stringifySafe(response));
    }
}
