import JSON;
import org.flashNight.arki.skill.SkillLoadoutService;

/** Web 技能面板协议、教师 capability 与学习事务 facade。 */
class org.flashNight.arki.skill.SkillPanelService {
    private static var _installed:Boolean = false;
    private static var _json:JSON = null;
    private static var _busy:Boolean = false;
    private static var _session:Object = null;
    private static var _candidateSession:Object = null;
    private static var _learnToken:Object = null;
    private static var _sessionSeq:Number = 0;
    private static var _tokenSeq:Number = 0;
    private static var SESSION_TTL_MS:Number = 120000;
    private static var TOKEN_TTL_MS:Number = 30000;

    public static function install():Void {
        if (_installed) return;
        _installed = true;
        _json = new JSON(false);
        if (_root.gameCommands == undefined) _root.gameCommands = {};
        _root.gameCommands["skillSnapshot"] = function(params:Object):Void { SkillPanelService.handle("snapshot", params); };
        _root.gameCommands["skillPanelOpen"] = function(params:Object):Void {
            SkillPanelService.openManage("nativehud");
        };
        _root.gameCommands["skillLearnPreview"] = function(params:Object):Void { SkillPanelService.handle("learnPreview", params); };
        _root.gameCommands["skillLearnCommit"] = function(params:Object):Void { SkillPanelService.handle("learnCommit", params); };
        _root.gameCommands["skillEquip"] = function(params:Object):Void { SkillPanelService.handle("equip", params); };
        _root.gameCommands["skillUnequip"] = function(params:Object):Void { SkillPanelService.handle("unequip", params); };
        _root.gameCommands["skillSetPassive"] = function(params:Object):Void { SkillPanelService.handle("setPassive", params); };
        _root.gameCommands["skillReorder"] = function(params:Object):Void { SkillPanelService.handle("reorder", params); };
        _root.gameCommands["skillPanelClose"] = function(params:Object):Void { SkillPanelService.handle("close", params); };

        _root.openSkillPanel = function(source:String):Object { return SkillPanelService.openManage(source); };
        _root.openSkillTrainer = function(npcRef:Object, source:String):Object { return SkillPanelService.openTrainer(npcRef, source); };
        _root.legacySkillLearnCommit = function(skillKey:String, desiredLevel:Number, npcRef:Object):Object {
            return SkillPanelService.legacyLearnCommit(skillKey, desiredLevel, npcRef);
        };
        _root.legacySkillEquip = function(skillKey:String, slot:Number):Object { return SkillPanelService.legacyEquip(skillKey, slot); };
        _root.legacySkillUnequip = function(slot:Number):Object { return SkillPanelService.legacyUnequip(slot); };
        _root.legacySkillSetPassive = function(skillKey:String, enabled:Boolean):Object { return SkillPanelService.legacySetPassive(skillKey, enabled); };
        _root.legacySkillReorder = function(skillKey:String, targetIndex:Number):Object { return SkillPanelService.legacyReorder(skillKey, targetIndex); };
    }

    public static function handle(commandName:String, params:Object):Void {
        var response:Object = execute(commandName, params);
        response.task = "skill_response";
        response.callId = params == null ? 0 : Number(params.callId);
        // reconcile 绑定与盖章由 Host 持有；AS2 routed snapshot 保持冻结 exact schema。
        sendResponse(response);
    }

    public static function execute(commandName:String, params:Object):Object {
        if (params == null || Number(params.v) != 1) return fail("invalid_payload");
        if (_busy && commandName != "snapshot" && commandName != "close") return fail("busy");
        if (commandName == "snapshot") return executeSnapshot(params);
        if (commandName == "learnPreview") return executeLearnPreview(params);
        if (commandName == "learnCommit") return executeLearnCommit(params);
        if (commandName == "equip") return executeWrite("equip", params);
        if (commandName == "unequip") return executeWrite("unequip", params);
        if (commandName == "setPassive") return executeWrite("setPassive", params);
        if (commandName == "reorder") return executeWrite("reorder", params);
        if (commandName == "close") {
            if (params.trainerSession != undefined && !safeOpaque(params.trainerSession, 160)) return fail("invalid_payload");
            // 带 session 的 tracked cleanup 只能撤销同一 capability；迟到的旧 cleanup 对新 session 幂等 no-op。
            if (params.trainerSession == undefined) closeSession();
            else {
                var cleanupNonce:String = String(params.trainerSession);
                if (_candidateSession != null && _candidateSession.nonce == cleanupNonce) _candidateSession = null;
                else if (_session != null && _session.nonce == cleanupNonce) closeActiveSession();
            }
            return {success:true, v:1, changed:false, revision:SkillLoadoutService.getRevision()};
        }
        return fail("unknown_command");
    }

    public static function openManage(source:String):Object {
        if (!SkillLoadoutService.isReady()) {
            var r:Object = SkillLoadoutService.root();
            if (r != null && typeof r.发布调试消息 == "function") r.发布调试消息("[SkillPanelService] service_not_ready");
            return {success:false, v:1, error:"service_not_ready", opened:false};
        }
        return sendPanelRequest("manage", null, source == null ? "native_hud" : source);
    }

    public static function openTrainer(npcRef:Object, source:String):Object {
        if (!SkillLoadoutService.isReady()) return {success:false, v:1, error:"service_not_ready"};
        var created:Object = createOrReuseSession(npcRef);
        if (!created.success) return created;
        var sent:Object = sendPanelRequest("trainer", created.session.nonce, source == null ? "world_skill_trainer" : source);
        if (!sent.success) {
            if (created.candidate && _candidateSession === created.session) _candidateSession = null;
        } else sent.trainerSession = created.session.nonce;
        return sent;
    }

    public static function legacyLearnCommit(skillKey:String, desiredLevel:Number, npcRef:Object):Object {
        if (npcRef == null) npcRef = resolveCurrentNpc();
        var made:Object = createOrReuseSession(npcRef);
        if (!made.success) return made;
        var revision:Number = SkillLoadoutService.getRevision();
        var preview:Object = calculatePreview(skillKey, desiredLevel, made.session.nonce, revision, false);
        if (!preview.success) return preview;
        if (!preview.canCommit) return fail(preview.blockingError);
        return finalizeLegacyWrite(SkillLoadoutService.commitLearn(skillKey, desiredLevel, preview.cost, revision));
    }

    public static function legacyEquip(skillKey:String, slot:Number):Object {
        return finalizeLegacyWrite(SkillLoadoutService.equip(skillKey, slot, SkillLoadoutService.getRevision()));
    }
    public static function legacyUnequip(slot:Number):Object {
        return finalizeLegacyWrite(SkillLoadoutService.unequip(slot, SkillLoadoutService.getRevision()));
    }
    public static function legacySetPassive(skillKey:String, enabled:Boolean):Object {
        return finalizeLegacyWrite(SkillLoadoutService.setPassive(skillKey, enabled, SkillLoadoutService.getRevision()));
    }
    public static function legacyReorder(skillKey:String, targetIndex:Number):Object {
        return finalizeLegacyWrite(SkillLoadoutService.reorder(skillKey, targetIndex, SkillLoadoutService.getRevision()));
    }

    private static function finalizeLegacyWrite(result:Object):Object {
        if (result.success && result.changed) SkillLoadoutService.runOptionalRenderers();
        if (result.success) result.snapshot = SkillLoadoutService.buildSnapshot("manage", null);
        return result;
    }

    private static function executeSnapshot(params:Object):Object {
        var view:String = String(params.view);
        if (view != "manage" && view != "trainer") return fail("invalid_payload");
        var trainer:Object = null;
        if (view == "trainer") {
            var sessionCheck:Object = validateSession(String(params.trainerSession));
            if (!sessionCheck.success) return sessionCheck;
            trainer = buildTrainerProjection(sessionCheck.session);
        } else if (params.trainerSession != undefined) {
            return fail("invalid_payload");
        }
        return SkillLoadoutService.buildSnapshot(view, trainer);
    }

    private static function executeLearnPreview(params:Object):Object {
        return calculatePreview(String(params.skillKey), Number(params.desiredLevel), String(params.trainerSession), Number(params.expectedRevision), true);
    }

    private static function executeLearnCommit(params:Object):Object {
        if (!safeOpaque(params.expectedLearnToken, 160)) return fail("invalid_payload");
        var token:Object = _learnToken;
        _learnToken = null;
        if (token == null || token.nonce != String(params.expectedLearnToken) || elapsed(token.createdAt) > TOKEN_TTL_MS) return fail("stale_state");
        if (String(params.view) != "trainer" || String(params.trainerSession) != token.trainerSession) return fail("invalid_payload");
        var sessionCheck:Object = validateSession(token.trainerSession);
        if (!sessionCheck.success) return sessionCheck;
        var preview:Object = calculatePreview(token.skillKey, token.desiredLevel, token.trainerSession, token.revision, false);
        _learnToken = null;
        if (!preview.success) return preview;
        var currentMetadata:Object = SkillLoadoutService.root().技能表对象[token.skillKey];
        if (!preview.canCommit || preview.cost != token.cost || metadataSignature(currentMetadata) != token.metadataSignature
            || safeWhole(SkillLoadoutService.root().技能点数, -1) != token.skillPoints
            || safeWhole(SkillLoadoutService.root().等级, -1) != token.playerLevel
            || sessionCheck.session.catalogSignature != token.catalogSignature) return fail("stale_state");
        _busy = true;
        var result:Object = SkillLoadoutService.commitLearn(token.skillKey, token.desiredLevel, token.cost, token.revision);
        _busy = false;
        if (result.success) {
            if (result.changed) SkillLoadoutService.runOptionalRenderers();
            var after:Object = validateSession(token.trainerSession);
            if (after.success) result.snapshot = SkillLoadoutService.buildSnapshot("trainer", buildTrainerProjection(after.session));
            else delete result.snapshot; // 主写已成功但 capability 失效：交由 Host 进入 unknown + reconcile。
        }
        return result;
    }

    private static function executeWrite(kind:String, params:Object):Object {
        var context:Object = resolveWriteContext(params);
        if (!context.success) return context;
        _busy = true;
        var result:Object;
        if (kind == "equip") result = SkillLoadoutService.equip(String(params.skillKey), Number(params.slot), Number(params.expectedRevision));
        else if (kind == "unequip") result = SkillLoadoutService.unequip(Number(params.slot), Number(params.expectedRevision));
        else if (kind == "setPassive") result = SkillLoadoutService.setPassive(String(params.skillKey), params.enabled, Number(params.expectedRevision));
        else result = SkillLoadoutService.reorder(String(params.skillKey), Number(params.targetIndex), Number(params.expectedRevision));
        _busy = false;
        if (result.success && result.changed) SkillLoadoutService.runOptionalRenderers();
        if (result.success) result.snapshot = SkillLoadoutService.buildSnapshot("manage", null);
        return result;
    }

    private static function resolveWriteContext(params:Object):Object {
        var view:String = String(params.view);
        if (view != "manage" || params.trainerSession != undefined) return fail("invalid_payload");
        return {success:true, view:"manage"};
    }

    private static function calculatePreview(skillKey:String, desiredLevel:Number, trainerSession:String, expectedRevision:Number, issueToken:Boolean):Object {
        if (!safeSkillKey(skillKey) || !whole(desiredLevel, 1, 100) || !whole(expectedRevision, 0, 2147483647)) return fail("invalid_payload");
        var sessionCheck:Object = validateSession(trainerSession);
        if (!sessionCheck.success) return sessionCheck;
        var sync:Object = SkillLoadoutService.synchronize();
        if (!sync.success) return sync;
        if (sync.revision != expectedRevision) return fail("stale_state");
        if (!catalogContains(sessionCheck.session.catalog, skillKey)) return fail("trainer_skill_forbidden");
        var state:Object = SkillLoadoutService.inspectSkill(skillKey);
        var metadata:Object = SkillLoadoutService.root().技能表对象[skillKey];
        if (metadata == null) return fail("unknown_skill");
        if (!validTrainerMetadata(metadata)) return fail("corrupt_skill_state");
        if (state.learned && state.stateHealth != "ok") return fail("corrupt_skill_state");
        var currentLevel:Number = state.learned ? state.level : 0;
        var maxLevel:Number = Number(metadata.MaxLevel);
        var cost:Number = 0;
        var blocking:String = null;
        if (currentLevel == 0 && desiredLevel != 1) blocking = "initial_level_must_be_one";
        else if (currentLevel > 0 && desiredLevel <= currentLevel) blocking = currentLevel >= maxLevel ? "max_level" : "invalid_level";
        else if (desiredLevel > maxLevel) blocking = "invalid_level";
        if (currentLevel == 0) {
            cost = Number(metadata.UnlockSP);
        } else if (desiredLevel > currentLevel) {
            var delta:Number = desiredLevel - currentLevel;
            var upgradeSP:Number = Number(metadata.UpgradeSP);
            if (upgradeSP > Math.floor(2147483647 / delta)) return fail("invalid_level");
            cost = delta * upgradeSP;
        }
        if (blocking == null && safeWhole(SkillLoadoutService.root().等级, 0) < Number(metadata.UnlockLevel)) blocking = "level_locked";
        if (blocking == null && currentLevel == 0 && SkillLoadoutService.findLearnTargetIndex() < 0) blocking = "skill_table_full";
        if (blocking == null && safeWhole(SkillLoadoutService.root().技能点数, 0) < cost) blocking = "insufficient_sp";

        var response:Object = {success:true, v:1, trainerSession:trainerSession, skillKey:skillKey,
            currentLevel:currentLevel, desiredLevel:desiredLevel, cost:cost, revision:sync.revision,
            canCommit:blocking == null, blockingError:blocking, learnToken:null, metadata:metadata};
        _learnToken = null;
        if (blocking == null && issueToken) {
            var nonce:String = "lt." + now() + "." + (++_tokenSeq);
            _learnToken = {nonce:nonce, trainerSession:trainerSession, skillKey:skillKey,
                desiredLevel:desiredLevel, cost:cost, revision:sync.revision, createdAt:now(),
                metadataSignature:metadataSignature(metadata),
                skillPoints:safeWhole(SkillLoadoutService.root().技能点数, 0),
                playerLevel:safeWhole(SkillLoadoutService.root().等级, 0),
                catalogSignature:sessionCheck.session.catalogSignature};
            response.learnToken = nonce;
        }
        delete response.metadata;
        return response;
    }

    private static function createOrReuseSession(npcRef:Object):Object {
        if (npcRef == null) return fail("trainer_session_expired");
        var normalized:Object = normalizeTrainerCatalog(catalogSource(npcRef));
        if (!normalized.success) return normalized;
        var scene:String = sceneSignature();
        var npcKey:String = npcIdentity(npcRef);
        var lifecycleMode:String = trainerLifecycleMode(npcRef, npcKey);
        if (lifecycleMode == null) return fail("trainer_session_expired");
        if (sessionMatches(_session, npcRef, npcKey, lifecycleMode, scene, normalized.signature)) {
            _candidateSession = null;
            return {success:true, v:1, session:_session, reused:true, candidate:false};
        }
        if (sessionMatches(_candidateSession, npcRef, npcKey, lifecycleMode, scene, normalized.signature)) {
            return {success:true, v:1, session:_candidateSession, reused:true, candidate:true};
        }
        _candidateSession = {nonce:"ts." + now() + "." + (++_sessionSeq), npcRef:npcRef, npcKey:npcKey,
            lifecycleMode:lifecycleMode, scene:scene, catalog:normalized.entries, catalogDiagnostics:normalized.diagnostics,
            catalogSignature:normalized.signature, createdAt:now()};
        return {success:true, v:1, session:_candidateSession, reused:false, candidate:true};
    }

    private static function validateSession(nonce:String):Object {
        if (_session != null && nonce == _session.nonce) return validateSessionRecord(_session, false);
        if (_candidateSession != null && nonce == _candidateSession.nonce) {
            var candidateCheck:Object = validateSessionRecord(_candidateSession, true);
            if (!candidateCheck.success) return candidateCheck;
            _session = _candidateSession;
            _candidateSession = null;
            _learnToken = null;
            return {success:true, v:1, session:_session, promoted:true};
        }
        return fail("trainer_session_expired");
    }

    private static function validateSessionRecord(session:Object, candidate:Boolean):Object {
        if (session == null || elapsed(session.createdAt) > SESSION_TTL_MS || session.scene != sceneSignature() || !npcStillValid(session)) {
            if (candidate) _candidateSession = null; else closeActiveSession();
            return fail("trainer_session_expired");
        }
        var normalized:Object = normalizeTrainerCatalog(catalogSource(session.npcRef));
        if (!normalized.success || normalized.signature != session.catalogSignature) {
            if (candidate) _candidateSession = null; else closeActiveSession();
            return fail("trainer_session_expired");
        }
        session.catalog = normalized.entries;
        session.catalogDiagnostics = normalized.diagnostics;
        return {success:true, v:1, session:session};
    }

    private static function sessionMatches(session:Object, npcRef:Object, npcKey:String, lifecycleMode:String, scene:String, signature:String):Boolean {
        return session != null && elapsed(session.createdAt) <= SESSION_TTL_MS && session.npcRef === npcRef
            && session.npcKey == npcKey && session.lifecycleMode == lifecycleMode
            && session.scene == scene && session.catalogSignature == signature;
    }

    public static function normalizeTrainerCatalog(raw):Object {
        if (raw == null || typeof raw != "object") return fail("trainer_session_expired");
        var diagnostics:Array = [];
        var byIndex:Object = {};
        var invalidKeys:Array = [];
        var signature:Array = [];
        for (var key:String in raw) {
            if (raw.hasOwnProperty != undefined && !raw.hasOwnProperty(key)) continue;
            var index:Number = parseCatalogIndex(key);
            if (index < 0) { invalidKeys.push(key); continue; }
            byIndex[index] = raw[key];
        }
        invalidKeys.sort();
        for (var bad:Number = 0; bad < invalidKeys.length; bad++) {
            var badKey:String = String(invalidKeys[bad]);
            addDiagnostic(diagnostics, {code:"invalid_trainer_entry", index:sanitizePlain(badKey, 64, "invalid")});
            signature.push("x:" + valueToken(badKey) + ":" + valueToken(raw[badKey]));
        }
        var entries:Array = [];
        var seen:Object = {};
        for (var i:Number = 0; i < 80; i++) {
            if (byIndex[i] == undefined && !(raw instanceof Array && raw.hasOwnProperty(String(i)))) continue;
            var value = byIndex[i] == undefined ? raw[i] : byIndex[i];
            signature.push(i + ":" + valueToken(value));
            if (typeof value != "string" || String(value).length == 0 || String(value).length > 64) {
                addDiagnostic(diagnostics, {code:"invalid_trainer_entry", index:i});
                continue;
            }
            var skillKey:String = String(value);
            if (!safeSkillKey(skillKey)) {
                addDiagnostic(diagnostics, {code:"invalid_trainer_entry", index:i});
                continue;
            }
            if (SkillLoadoutService.root().技能表对象[skillKey] == null) {
                addDiagnostic(diagnostics, {code:"unknown_skill", skillKey:skillKey});
                continue;
            }
            var seenKey:String = "$" + skillKey;
            if (seen[seenKey] === true) {
                addDiagnostic(diagnostics, {code:"duplicate_trainer_entry", skillKey:skillKey});
                continue;
            }
            seen[seenKey] = true;
            entries.push({index:i, skillKey:skillKey});
            if (!validTrainerMetadata(SkillLoadoutService.root().技能表对象[skillKey])) {
                addDiagnostic(diagnostics, {code:"metadata_mismatch", skillKey:skillKey});
            }
        }
        return {success:true, v:1, entries:entries, diagnostics:diagnostics, signature:signature.join("|")};
    }

    private static function buildTrainerProjection(session:Object):Object {
        var entries:Array = [];
        for (var i:Number = 0; i < session.catalog.length; i++) {
            var key:String = session.catalog[i].skillKey;
            var m:Object = SkillLoadoutService.root().技能表对象[key];
            var state:Object = SkillLoadoutService.inspectSkill(key);
            var typeName:String = String(m.Type);
            if (typeName == "" || typeName == "undefined" || typeName == "null") typeName = "未知";
            var metadataHealthy:Boolean = validTrainerMetadata(m);
            var health:String = state.learned ? state.stateHealth : "ok";
            var blocked:Boolean = state.learned ? state.writeBlocked : false;
            if (!metadataHealthy) { health = "invalid"; blocked = true; }
            entries.push({skillKey:key, currentLevel:state.learned ? clampWhole(state.level, 0, 100) : 0,
                maxLevel:boundedMetadata(m, "MaxLevel", 1, 100, 1), type:sanitizePlain(typeName, 64, "未知"),
                passive:m.Passive === true || String(m.Type).indexOf("被动") >= 0,
                equippable:m.Equippable === true,
                unlockLevel:boundedMetadata(m, "UnlockLevel", 0, 9999, 0),
                unlockSP:boundedMetadata(m, "UnlockSP", 0, 2147483647, 0),
                upgradeSP:boundedMetadata(m, "UpgradeSP", 0, 2147483647, 0),
                mp:clampedMetadata(m, "MP", 1000000),
                cooldownMs:clampedIntegerMetadata(m, "CD", 86400000),
                iconKey:key, description:sanitizeLayout(String(m.Description == undefined ? "" : m.Description), 4096),
                stateHealth:health, writeBlocked:blocked});
        }
        return {session:session.nonce, entries:entries, diagnostics:session.catalogDiagnostics.concat()};
    }

    private static function sendPanelRequest(view:String, trainerSession:String, source:String):Object {
        var r:Object = SkillLoadoutService.root();
        if (r.server == null || typeof r.server.sendSocketMessage != "function") return {success:false, v:1, error:"launcher_unavailable", opened:false};
        if (_json == null) _json = new JSON(false);
        var initData:Object = {view:view};
        if (trainerSession != null) initData.trainerSession = trainerSession;
        var message:String = _json.stringify({task:"panel_request", panel:"skills", source:sanitizePlain(String(source), 64, "unknown"), initData:initData});
        var sent:Boolean = r.server.sendSocketMessage(message) === true;
        return sent ? {success:true, v:1, opened:true} : {success:false, v:1, error:"launcher_unavailable", opened:false};
    }

    private static function sendResponse(response:Object):Void {
        var r:Object = SkillLoadoutService.root();
        if (r.server == null || typeof r.server.sendSocketMessage != "function") return;
        if (_json == null) _json = new JSON(false);
        r.server.sendSocketMessage(_json.stringify(response));
    }

    private static function closeActiveSession():Void { _session = null; _learnToken = null; }
    public static function closeSession():Void { closeActiveSession(); _candidateSession = null; }

    private static function resolveCurrentNpc():Object {
        var r:Object = SkillLoadoutService.root();
        return r.gameworld == null ? null : r.gameworld[r.当前NPC];
    }
    private static function catalogSource(npcRef:Object) {
        if (npcRef == null) return null;
        if (npcRef.可学的技能 != undefined) return npcRef.可学的技能;
        var r:Object = SkillLoadoutService.root();
        var key:String = npcIdentity(npcRef);
        return r.NPC技能表 == null ? null : r.NPC技能表[key];
    }
    private static function npcIdentity(npcRef:Object):String {
        if (npcRef == null) return "";
        if (typeof npcRef == "string") return String(npcRef);
        if (npcRef._name != undefined) return String(npcRef._name);
        if (npcRef.名字 != undefined) return String(npcRef.名字);
        if (npcRef.name != undefined) return String(npcRef.name);
        return "npc";
    }
    private static function npcStillValid(session:Object):Boolean {
        var r:Object = SkillLoadoutService.root();
        if (session.lifecycleMode == "detached") return session.npcRef != null && session.npcRef.__skillTrainerDetached === true;
        if (session.lifecycleMode != "gameworld" || r.gameworld == null) return false;
        return r.gameworld[session.npcKey] === session.npcRef;
    }
    private static function trainerLifecycleMode(npcRef:Object, npcKey:String):String {
        var r:Object = SkillLoadoutService.root();
        if (r.gameworld != null && npcKey != "npc" && r.gameworld[npcKey] === npcRef) return "gameworld";
        // 非 gameworld 教师必须显式声明不可验证生命周期；禁止把具名 missing 当存活。
        if (npcRef != null && npcRef.__skillTrainerDetached === true) return "detached";
        return null;
    }
    private static function sceneSignature():String {
        var r:Object = SkillLoadoutService.root();
        return String(r.当前场景 != undefined ? r.当前场景 : (r.关卡名 != undefined ? r.关卡名 : r._currentframe));
    }
    private static function catalogContains(catalog:Array, skillKey:String):Boolean {
        for (var i:Number = 0; i < catalog.length; i++) if (catalog[i].skillKey == skillKey) return true;
        return false;
    }
    private static function parseCatalogIndex(key:String):Number {
        if (key == "") return -1;
        var n:Number = Number(key);
        if (!whole(n, 0, 79) || String(n) != key) return -1;
        return n;
    }
    private static function metadataSignature(m:Object):String {
        if (m == null) return "";
        return [valueToken(m.Name), valueToken(m.Type), valueToken(m.MaxLevel), valueToken(m.UnlockLevel),
            valueToken(m.UnlockSP), valueToken(m.UpgradeSP), valueToken(m.CD), valueToken(m.MP),
            valueToken(m.Passive), valueToken(m.Equippable)].join("|");
    }
    private static function boundedMetadata(m:Object, key:String, min:Number, max:Number, fallback:Number):Number {
        if (m == null) return fallback;
        var n:Number = Number(m[key]);
        return whole(n, min, max) ? n : fallback;
    }
    private static function clampedMetadata(m:Object, key:String, max:Number):Number {
        if (m == null) return 0;
        var n:Number = Number(m[key]);
        if (isNaN(n) || !isFinite(n) || n < 0) return 0;
        return n > max ? max : n;
    }
    private static function clampedIntegerMetadata(m:Object, key:String, max:Number):Number {
        return Math.floor(clampedMetadata(m, key, max));
    }
    private static function validLearnMetadata(m:Object):Boolean {
        return m != null && whole(m.MaxLevel, 1, 100) && whole(m.UnlockLevel, 0, 9999)
            && whole(m.UnlockSP, 0, 2147483647) && whole(m.UpgradeSP, 0, 2147483647);
    }
    private static function validTrainerMetadata(m:Object):Boolean {
        if (!validLearnMetadata(m) || typeof m.Type != "string" || !safeText(String(m.Type), 1, 64)
            || typeof m.Passive != "boolean" || typeof m.Equippable != "boolean") return false;
        var mp:Number = Number(m.MP);
        return !isNaN(mp) && isFinite(mp) && mp >= 0 && mp <= 1000000 && whole(m.CD, 0, 86400000);
    }
    private static function now():Number { return getTimer(); }
    private static function elapsed(start:Number):Number { var d:Number = now() - start; return d < 0 ? d + 4294967296 : d; }
    private static function safeSkillKey(value):Boolean {
        if (typeof value != "string") return false;
        var s:String = String(value);
        return s.length > 0 && s.length <= 64 && isSafePlain(s) && !isBoundaryWhitespace(s.charCodeAt(0))
            && !isBoundaryWhitespace(s.charCodeAt(s.length - 1));
    }
    private static function safeOpaque(value, max:Number):Boolean { return typeof value == "string" && String(value).length > 0 && String(value).length <= max; }
    private static function whole(value, min:Number, max:Number):Boolean { var n:Number = Number(value); return !isNaN(n) && isFinite(n) && Math.floor(n) == n && n >= min && n <= max; }
    private static function safeWhole(value, fallback:Number):Number { var n:Number = Number(value); return isNaN(n) || !isFinite(n) ? fallback : Math.floor(n); }
    private static function clampWhole(value, min:Number, max:Number):Number { var n:Number = safeWhole(value, min); if(n < min)return min; return n > max ? max : n; }
    private static function clip(value:String, max:Number):String { return value.length <= max ? value : value.substr(0, max); }
    private static function sanitizePlain(value:String, max:Number, fallback:String):String {
        var out:String = "";
        for (var i:Number = 0; i < value.length && out.length < max; i++) {
            var c:Number = value.charCodeAt(i);
            if (c >= 32 && !(c >= 127 && c <= 159)) out += value.charAt(i);
        }
        return out.length == 0 ? fallback : out;
    }
    private static function sanitizeLayout(value:String, max:Number):String {
        var out:String = "";
        for (var i:Number = 0; i < value.length && out.length < max; i++) {
            var c:Number = value.charCodeAt(i);
            if ((c >= 32 && !(c >= 127 && c <= 159)) || c == 9 || c == 10 || c == 13) out += value.charAt(i);
        }
        return out;
    }
    private static function isSafePlain(value:String):Boolean {
        for (var i:Number = 0; i < value.length; i++) {
            var c:Number = value.charCodeAt(i);
            if (c < 32 || (c >= 127 && c <= 159)) return false;
        }
        return true;
    }
    private static function safeText(value:String, min:Number, max:Number):Boolean {
        return value.length >= min && value.length <= max && isSafePlain(value);
    }
    private static function isBoundaryWhitespace(code:Number):Boolean {
        return code <= 32 || code == 160 || code == 5760 || (code >= 8192 && code <= 8202)
            || code == 8232 || code == 8233 || code == 8239 || code == 8287 || code == 12288;
    }
    private static function valueToken(value):String {
        if (value == null) return "null";
        var s:String = String(value);
        return typeof value + ":" + s.length + ":" + s;
    }
    private static function addDiagnostic(target:Array, item:Object):Void { if (target.length < 32) target.push(item); }
    private static function fail(errorCode:String):Object { return {success:false, v:1, error:errorCode, revision:SkillLoadoutService.getRevision()}; }

    public static function testOnlyReset():Void {
        _installed = false; _busy = false; _session = null; _candidateSession = null; _learnToken = null; _sessionSeq = 0; _tokenSeq = 0; _json = new JSON(false);
    }
    public static function testOnlySession():Object { return _session; }
    public static function testOnlyCandidateSession():Object { return _candidateSession; }
}
