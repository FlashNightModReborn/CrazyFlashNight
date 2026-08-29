

import org.flashNight.neur.Event.EventBus;
import org.flashNight.arki.ui.HairdresserPanelService;
import org.flashNight.arki.item.BaseItem;
import org.flashNight.arki.item.InventoryPanelService;
import org.flashNight.neur.Server.SaveManager;
import LiteJSON;

/** 启动前门角色创建的 AS2 权威服务。 */
class org.flashNight.neur.Server.CharacterCreationService {
    private static var _installed:Boolean = false;
    private static var _json:LiteJSON;

    private static var _attemptId:String = "";
    private static var _slotKey:String = "";
    private static var _kind:String = "";
    private static var _phase:String = "idle";
    private static var _draftSignature:String = "";
    private static var _characterName:String = "";
    private static var _startToken:String = "";
    private static var _callId:String = "";
    private static var _sceneNotified:Boolean = false;

    // focused TestLoader hooks；生产代码保持 null。
    private static var _prepareHookForTests:Function = null;
    private static var _flushHookForTests:Function = null;
    private static var _startHookForTests:Function = null;
    private static var _reserveHookForTests:Function = null;

    private static var SNAPSHOT_KEYS:Array = [
        "task", "action", "v", "attemptId", "slotKey", "callId"
    ];
    private static var CREATE_KEYS:Array = [
        "task", "action", "v", "attemptId", "slotKey", "callId", "draft"
    ];
    private static var DRAFT_KEYS:Array = [
        "characterName", "gender", "height", "faceIdentifier", "hairIdentifier",
        "upperIdentifier", "lowerIdentifier", "footwearIdentifier", "difficulty"
    ];

    public static function install():Void {
        if (_installed) return;
        _installed = true;
        if (_root.gameCommands == undefined) _root.gameCommands = {};
        _root.gameCommands["characterCreationSnapshot"] = function(params):Void {
            org.flashNight.neur.Server.CharacterCreationService.handle("snapshot", params);
        };
        _root.gameCommands["characterCreate"] = function(params):Void {
            org.flashNight.neur.Server.CharacterCreationService.handle("create", params);
        };
        _root.gameCommands["frontdoorEnterResolvedSave"] = function(params):Void {
            org.flashNight.neur.Server.CharacterCreationService.handle("resolved_save", params);
        };
        EventBus.getInstance().subscribe(
            "SceneReady",
            org.flashNight.neur.Server.CharacterCreationService.onSceneReady,
            null
        );
    }

    public static function handle(commandName:String, params:Object):Void {
        var request:Object = params == undefined ? {} : params;
        if (commandName == "snapshot") {
            handleSnapshot(request);
        } else if (commandName == "create") {
            handleCreate(request);
        } else if (commandName == "resolved_save") {
            handleResolvedSave(request);
        } else {
            sendRejected("create", request, "unsupported_cmd", false);
        }
    }

    private static function handleSnapshot(request:Object):Void {
        var validation:Object = validateEnvelope(
            request, "characterCreationSnapshot", SNAPSHOT_KEYS);
        if (!validation.success) {
            sendRejected("snapshot", request, validation.error, false);
            return;
        }
        var hair:Object = resolveHairCatalog();
        if (!hair.success) {
            sendRejected("snapshot", request, hair.error,
                hair.error == "catalog_not_ready");
            return;
        }
        var appearance:Object = buildAppearanceCatalog();
        if (!appearance.success) {
            sendRejected("snapshot", request, appearance.error, true);
            return;
        }

        var response:Object = baseResponse("snapshot", "snapshot", true, request);
        response.constraints = {
            displayNameMin:1,
            displayNameMax:32,
            characterNameMin:1,
            characterNameMax:15,
            heightMin:150,
            heightMax:200
        };
        response.defaults = buildDefaults();
        response.appearanceCatalog = appearance.catalog;
        response.hairCatalog = hair.catalog;
        response.difficulties = buildDifficulties();
        sendResponse(response);
    }

    private static function handleCreate(request:Object):Void {
        var validation:Object = validateEnvelope(request, "characterCreate", CREATE_KEYS);
        if (!validation.success) {
            sendRejected("create", request, validation.error, false);
            return;
        }
        if (!hasExactOwnKeys(request.draft, DRAFT_KEYS)) {
            sendRejected("create", request, "invalid_draft", false);
            return;
        }
        var hair:Object = resolveHairCatalog();
        if (!hair.success) {
            sendRejected("create", request, hair.error,
                hair.error == "catalog_not_ready");
            return;
        }
        var draftValidation:Object = validateDraft(request.draft, hair.catalog);
        if (!draftValidation.success) {
            sendRejected("create", request, draftValidation.error, false);
            return;
        }

        var attemptId:String = String(request.attemptId);
        var signature:String = buildDraftSignature(request.draft);
        resetIfRootAttemptChanged();
        if (_attemptId == attemptId && _kind != "") {
            if (_kind != "create" || _draftSignature != signature) {
                sendRejected("create", request, "attempt_conflict", false);
                return;
            }
            _callId = String(request.callId);
            replayCreate(request);
            return;
        }

        resetState();
        _attemptId = attemptId;
        _slotKey = String(request.slotKey);
        _kind = "create";
        _phase = "preparing";
        _draftSignature = signature;
        _characterName = String(request.draft.characterName);
        _callId = String(request.callId);

        var prepared:Object = prepareCharacter(buildInitialState(request.draft));
        if (!prepared.success) {
            var prepareError:String = prepared.error == undefined
                ? "initialization_failed" : String(prepared.error);
            if (prepareError == "initialization_failed") {
                _phase = "failed_initialization";
            } else {
                resetState();
            }
            sendRejected("create", request, prepareError,
                prepareError == "stage_busy" || prepareError == "transition_unavailable");
            return;
        }

        _startToken = String(prepared.startToken);
        _phase = "prepared";
        flushPreparedCreate(request);
    }

    private static function replayCreate(request:Object):Void {
        if (_phase == "prepared") {
            flushPreparedCreate(request);
        } else if (_phase == "durable") {
            if (sendDurable(request)) startTutorialTransition();
        } else if (_phase == "transitioning") {
            sendDurable(request);
        } else if (_phase == "scene_ready") {
            sendSceneReady(request);
        } else if (_phase == "failed_initialization") {
            sendRejected("create", request, "initialization_failed", false);
        } else {
            sendRejected("create", request, "attempt_conflict", false);
        }
    }

    private static function flushPreparedCreate(request:Object):Void {
        if (!flushCharacter()) {
            var failed:Object = baseResponse("create", "rejected", false, request);
            failed.durable = false;
            failed.localFlush = false;
            failed.error = "save_failed";
            failed.retryable = true;
            sendResponse(failed);
            return;
        }
        _phase = "durable";
        if (sendDurable(request)) startTutorialTransition();
    }

    private static function sendDurable(request:Object):Boolean {
        var response:Object = baseResponse("create", "durable", true, request);
        response.durable = true;
        // Host 只在 SharedObject.flush() 本轮严格返回 true 后采信此位。
        response.localFlush = true;
        response.characterName = _characterName;
        return sendResponse(response);
    }

    private static function startTutorialTransition():Void {
        if (_phase != "durable") return;
        if (_startToken == "") {
            var reservation:Object = reserveTutorial();
            if (!reservation.success) {
                var request:Object = currentRequest();
                var response:Object = baseResponse("create", "rejected", false, request);
                response.durable = true;
                response.error = reservation.error == undefined
                    ? "stage_busy" : String(reservation.error);
                response.retryable = true;
                sendResponse(response);
                return;
            }
            _startToken = String(reservation.startToken);
        }
        _phase = "transitioning";
        var boundAttemptId:String = _attemptId;
        var boundToken:String = _startToken;
        var accepted:Function = function():Void {
            org.flashNight.neur.Server.CharacterCreationService.onTutorialTransitionAccepted(
                boundAttemptId, boundToken);
        };
        var failed:Function = function(errorCode:String):Void {
            org.flashNight.neur.Server.CharacterCreationService.onTutorialTransitionFailed(
                boundAttemptId, boundToken, errorCode);
        };
        var started:Boolean = startTutorial(_startToken, accepted, failed);
        if (!started && _phase == "transitioning") {
            onTutorialTransitionFailed(
                boundAttemptId, boundToken, "stage_load_failed");
        }
    }

    public static function onTutorialTransitionAccepted(
            attemptId:String, startToken:String):Void {
        if (_kind != "create" || _phase != "transitioning"
                || _attemptId != attemptId || _startToken != startToken) return;
        // SceneReady 才是可见完成点；fade 接受后继续保持 transitioning。
    }

    public static function onTutorialTransitionFailed(
            attemptId:String, startToken:String, errorCode:String):Void {
        if (_kind != "create" || _phase != "transitioning"
                || _attemptId != attemptId || _startToken != startToken) return;
        _phase = "durable";
        _startToken = "";
        var request:Object = currentRequest();
        var response:Object = baseResponse("create", "rejected", false, request);
        response.durable = true;
        response.characterName = _characterName;
        response.error = errorCode == null || errorCode == ""
            ? "stage_load_failed" : errorCode;
        response.retryable = true;
        sendResponse(response);
    }

    private static function handleResolvedSave(request:Object):Void {
        var validation:Object = validateEnvelope(
            request, "frontdoorEnterResolvedSave", SNAPSHOT_KEYS);
        if (!validation.success) {
            sendRejected("create", request, validation.error, false);
            return;
        }
        if (typeof _root.notifyGameEntered != "function"
                || typeof _root.gotoAndStop != "function") {
            sendRejected("create", request, "entry_unavailable", true);
            return;
        }

        resetIfRootAttemptChanged();
        if (_attemptId == String(request.attemptId) && _kind != "") {
            if (_kind != "resolved_save") {
                sendRejected("create", request, "attempt_conflict", false);
                return;
            }
            _callId = String(request.callId);
            if (_phase == "resolved_pending") enterResolvedSaveFrame();
            return;
        }

        resetState();
        _attemptId = String(request.attemptId);
        _slotKey = String(request.slotKey);
        _kind = "resolved_save";
        _phase = "resolved_pending";
        _callId = String(request.callId);
        // Host 已经解析并选定普通存档。本命令只负责 one-way 进入读盘帧，
        // 不伪造本轮建角 durable/localFlush receipt；最终入场仍只由
        // notifyGameEntered() 的 exact s:1|ga 信号确认。
        enterResolvedSaveFrame();
    }

    private static function enterResolvedSaveFrame():Void {
        if (_kind != "resolved_save" || _phase != "resolved_pending") return;
        _phase = "transitioning";
        _root.gotoAndStop("读盘");
    }

    /** 只接受当前 attempt 的真实 actor-ready SceneReady。 */
    public static function onSceneReady():Void {
        if (_phase != "transitioning" || _sceneNotified) return;
        if (_attemptId == "" || _attemptId != String(_root._bootstrapAttemptId)) return;
        if (_slotKey == "" || _slotKey != String(_root.savePath)) return;
        if (_kind == "create" && String(_root.当前关卡名) != "教学关卡") return;
        if (!hasLiveControlledHero()) return;
        if (typeof _root.notifyGameEntered != "function") return;

        _sceneNotified = true;
        _phase = "scene_ready";
        _startToken = "";
        _root.notifyGameEntered();
        if (_kind == "create") sendSceneReady(currentRequest());
    }

    private static function hasLiveControlledHero():Boolean {
        if (_root.gameworld == undefined || _root.控制目标 == undefined
                || String(_root.控制目标) == "") return false;
        var hero:Object = _root.gameworld[_root.控制目标];
        return hero != undefined && hero != null && hero.是否为敌人 === false;
    }

    private static function validateEnvelope(
            request:Object, expectedAction:String, expectedKeys:Array):Object {
        if (!hasExactOwnKeys(request, expectedKeys)) {
            return {success:false, error:"invalid_envelope"};
        }
        if (request.task !== "cmd" || request.action !== expectedAction) {
            return {success:false, error:"invalid_envelope"};
        }
        if (request.v !== 1) return {success:false, error:"unsupported_version"};
        if (typeof request.callId != "string" || request.callId == ""
                || request.callId.length > 128
                || containsControlCharacter(String(request.callId))) {
            return {success:false, error:"invalid_envelope"};
        }
        if (typeof request.attemptId != "string"
                || request.attemptId == ""
                || _root._bootstrapAttemptId == undefined
                || request.attemptId !== String(_root._bootstrapAttemptId)) {
            return {success:false, error:"stale_attempt"};
        }
        if (typeof request.slotKey != "string"
                || request.slotKey == ""
                || _root.savePath == undefined
                || request.slotKey !== String(_root.savePath)) {
            return {success:false, error:"slot_mismatch"};
        }
        return {success:true};
    }

    private static function validateDraft(draft:Object, hairCatalog:Array):Object {
        if (typeof draft.characterName != "string"
                || draft.characterName.length < 1 || draft.characterName.length > 15
                || containsControlCharacter(draft.characterName)) {
            return {success:false, error:"invalid_character_name"};
        }
        if (draft.gender !== "male" && draft.gender !== "female") {
            return {success:false, error:"invalid_gender"};
        }
        if (typeof draft.height != "number" || isNaN(draft.height)
                || Math.floor(draft.height) != draft.height
                || !(draft.height > 149) || !(draft.height < 201)) {
            return {success:false, error:"invalid_height"};
        }

        var gender:String = String(draft.gender);
        var face:String = gender == "male"
            ? "男变装-基本脸型" : "女变装-基本脸型";
        if (typeof draft.faceIdentifier != "string"
                || draft.faceIdentifier !== face) {
            return {success:false, error:"invalid_face"};
        }
        if (typeof draft.hairIdentifier != "string"
                || !catalogContains(hairCatalog, String(draft.hairIdentifier))) {
            return {success:false, error:"invalid_hair"};
        }
        if (typeof draft.upperIdentifier != "string"
                || !stringArrayContains(upperIdentifiers(gender), draft.upperIdentifier)) {
            return {success:false, error:"invalid_upper"};
        }
        if (typeof draft.lowerIdentifier != "string"
                || !stringArrayContains(lowerIdentifiers(gender), draft.lowerIdentifier)) {
            return {success:false, error:"invalid_lower"};
        }
        if (typeof draft.footwearIdentifier != "string"
                || !stringArrayContains(footwearIdentifiers(gender), draft.footwearIdentifier)) {
            return {success:false, error:"invalid_footwear"};
        }
        if (draft.difficulty !== "balanced" && draft.difficulty !== "easy"
                && draft.difficulty !== "challenge") {
            return {success:false, error:"invalid_difficulty"};
        }
        return {success:true};
    }

    private static function resolveHairCatalog():Object {
        var result:Object = HairdresserPanelService.execute("snapshot", {v:1});
        if (!result.success) {
            return {
                success:false,
                error:result.error == "catalog_invalid"
                    ? "catalog_not_ready" : String(result.error)
            };
        }
        if (!(result.catalog instanceof Array) || result.catalog.length < 1
                || !isValidHairCatalog(result.catalog)
                || !catalogContains(result.catalog, "发型-男式-黑暴走头")
                || !catalogContains(result.catalog, "发型-女式-咖啡色中长马尾")) {
            return {success:false, error:"catalog_not_ready"};
        }
        return {success:true, catalog:result.catalog};
    }

    private static function isValidHairCatalog(catalog:Array):Boolean {
        for (var i:Number = 0; i < catalog.length; i++) {
            var row:Object = catalog[i];
            if (row == null || typeof row != "object"
                    || typeof row.identifier != "string" || row.identifier == ""
                    || typeof row.name != "string") return false;
        }
        return true;
    }

    private static function buildDefaults():Object {
        return {
            male:{
                height:175,
                faceIdentifier:"男变装-基本脸型",
                hairIdentifier:"发型-男式-黑暴走头",
                upperIdentifier:"黑色功夫装",
                lowerIdentifier:"咖啡色多包裤",
                footwearIdentifier:"棕色皮鞋",
                difficulty:"balanced"
            },
            female:{
                height:165,
                faceIdentifier:"女变装-基本脸型",
                hairIdentifier:"发型-女式-咖啡色中长马尾",
                upperIdentifier:"米色高腰背心",
                lowerIdentifier:"棕色带腿包短裤",
                footwearIdentifier:"棕色圆头皮鞋",
                difficulty:"balanced"
            }
        };
    }

    private static function buildAppearanceCatalog():Object {
        // 同一 snapshot 内按 identifier 复用 canonical 投影；不跨请求缓存，
        // 避免物品配置热更新后产生第二权威或 epoch 漂移。
        var cache:Object = {};
        var upperMale:Array = richItemCatalog(upperIdentifiers("male"), cache);
        var upperFemale:Array = richItemCatalog(upperIdentifiers("female"), cache);
        var lowerMale:Array = richItemCatalog(lowerIdentifiers("male"), cache);
        var lowerFemale:Array = richItemCatalog(lowerIdentifiers("female"), cache);
        var footwearMale:Array = richItemCatalog(footwearIdentifiers("male"), cache);
        var footwearFemale:Array = richItemCatalog(footwearIdentifiers("female"), cache);
        if (upperMale == null || upperFemale == null
                || lowerMale == null || lowerFemale == null
                || footwearMale == null || footwearFemale == null) {
            return {success:false, error:"catalog_not_ready"};
        }
        return {success:true, catalog:{
            faces:{
                male:{identifier:"男变装-基本脸型", name:"基本脸型"},
                female:{identifier:"女变装-基本脸型", name:"基本脸型"}
            },
            upper:{
                male:upperMale,
                female:upperFemale
            },
            lower:{
                male:lowerMale,
                female:lowerFemale
            },
            footwear:{
                male:footwearMale,
                female:footwearFemale
            }
        }};
    }

    private static function buildDifficulties():Array {
        return [
            {
                identifier:"balanced",
                name:"平衡模式（困难）",
                description:"该模式为推荐模式，游戏性与平衡的设计均以此模式为基准。主线到达一定进度后开始奖励k点，佣兵价格提升，战宠携带上限逐步开放。开放修改器。",
                recommended:true
            },
            {
                identifier:"easy",
                name:"逆天模式（简单）",
                description:"该模式更偏向于单机版原版。前期任务即可获得大量k点，且佣兵、战宠等无额外限制或更加接近原版。开放修改器。",
                recommended:false
            },
            {
                identifier:"challenge",
                name:"挑战模式（自限）",
                description:"该模式仅适合自我限制玩法的挑战型玩家。不适合未完整体验过重置版流程的新玩家。k点与金币奖励更少、佣兵价格大幅提升、战宠携带数量大幅减少、不开放修改器，主线关只可选择地狱难度。调整方案由该模式的玩家提出或推动，游戏体验不作为常规平衡考量标准。",
                recommended:false
            }
        ];
    }

    private static function upperIdentifiers(gender:String):Array {
        return gender == "male"
            ? ["浅灰背心", "绿色马甲", "黑色功夫装", "廉价西服"]
            : ["浅灰背心", "米色高腰背心", "黑灰色连帽马甲", "廉价西服"];
    }

    private static function lowerIdentifiers(gender:String):Array {
        return gender == "male"
            ? ["咖啡色多包裤", "咖啡色多包短裤", "破牛仔裤"]
            : ["黑灰色毛边短裤", "棕色带腿包短裤", "破牛仔裤"];
    }

    private static function footwearIdentifiers(gender:String):Array {
        return gender == "male"
            ? ["棕色皮鞋", "白色板鞋"]
            : ["深灰色皮鞋", "棕色圆头皮鞋", "白色板鞋"];
    }

    private static function richItemCatalog(identifiers:Array, cache:Object):Array {
        var result:Array = [];
        for (var i:Number = 0; i < identifiers.length; i++) {
            var identifier:String = String(identifiers[i]);
            var row:Object = cache[identifier];
            if (row == undefined) {
                var item:BaseItem = BaseItem.create(identifier, 1);
                if (item == null) return null;
                var tooltip:Object = InventoryPanelService.buildTooltipProjection(item);
                if (tooltip == null || !tooltip.success
                        || typeof tooltip.itemName != "string"
                        || String(tooltip.itemName) != identifier
                        || typeof tooltip.displayname != "string"
                        || typeof tooltip.iconName != "string"
                        || typeof tooltip.itemType != "string"
                        || typeof tooltip.introHTML != "string"
                        || typeof tooltip.descHTML != "string"
                        || tooltip.displayname == "" || tooltip.iconName == ""
                        || tooltip.itemType == "" || tooltip.introHTML == ""
                        || tooltip.descHTML == "") return null;
                row = {
                    identifier:identifier,
                    name:String(tooltip.displayname),
                    iconName:String(tooltip.iconName),
                    itemType:String(tooltip.itemType),
                    introHTML:String(tooltip.introHTML),
                    descHTML:String(tooltip.descHTML)
                };
                cache[identifier] = row;
            }
            result.push(row);
        }
        return result;
    }

    private static function buildInitialState(draft:Object):Object {
        return {
            characterName:String(draft.characterName),
            genderText:draft.gender == "male" ? "男" : "女",
            height:Number(draft.height),
            faceIdentifier:String(draft.faceIdentifier),
            hairIdentifier:String(draft.hairIdentifier),
            upperIdentifier:String(draft.upperIdentifier),
            lowerIdentifier:String(draft.lowerIdentifier),
            footwearIdentifier:String(draft.footwearIdentifier),
            difficultyText:difficultyText(String(draft.difficulty))
        };
    }

    private static function difficultyText(identifier:String):String {
        if (identifier == "easy") return "逆天模式（简单）";
        if (identifier == "challenge") return "挑战模式（自限）";
        return "平衡模式（困难）";
    }

    private static function buildDraftSignature(draft:Object):String {
        return signaturePart(draft.characterName)
            + signaturePart(draft.gender)
            + signaturePart(draft.height)
            + signaturePart(draft.faceIdentifier)
            + signaturePart(draft.hairIdentifier)
            + signaturePart(draft.upperIdentifier)
            + signaturePart(draft.lowerIdentifier)
            + signaturePart(draft.footwearIdentifier)
            + signaturePart(draft.difficulty);
    }

    private static function signaturePart(value):String {
        var text:String = String(value);
        return String(text.length) + ":" + text;
    }

    private static function containsControlCharacter(value:String):Boolean {
        for (var i:Number = 0; i < value.length; i++) {
            var code:Number = value.charCodeAt(i);
            if (code < 32 || (code > 126 && code < 160)) return true;
        }
        return false;
    }

    private static function catalogContains(catalog:Array, identifier:String):Boolean {
        for (var i:Number = 0; i < catalog.length; i++) {
            if (String(catalog[i].identifier) == identifier) return true;
        }
        return false;
    }

    private static function stringArrayContains(values:Array, value:String):Boolean {
        for (var i:Number = 0; i < values.length; i++) {
            if (values[i] === value) return true;
        }
        return false;
    }

    private static function hasExactOwnKeys(value:Object, expected:Array):Boolean {
        if (value == null || typeof value != "object" || value instanceof Array) return false;
        var count:Number = 0;
        for (var key:String in value) {
            if (!owns(value, key)) continue;
            if (!stringArrayContains(expected, key)) return false;
            count++;
        }
        if (count != expected.length) return false;
        for (var i:Number = 0; i < expected.length; i++) {
            if (!owns(value, expected[i])) return false;
        }
        return true;
    }

    private static function owns(value:Object, key:String):Boolean {
        return value != null && Object.prototype.hasOwnProperty.call(value, key);
    }

    private static function baseResponse(operation:String, phase:String,
            success:Boolean, request:Object):Object {
        return {
            task:"character_create_response",
            callId:safeCallId(request),
            v:1,
            operation:operation,
            phase:phase,
            success:success,
            attemptId:safeAttemptId(request),
            slotKey:safeSlotKey(request)
        };
    }

    private static function sendRejected(operation:String, request:Object,
            errorCode:String, retryable:Boolean):Boolean {
        var response:Object = baseResponse(operation, "rejected", false, request);
        response.error = errorCode;
        response.retryable = retryable;
        if (operation == "create") response.durable = isDurablePhase();
        return sendResponse(response);
    }

    private static function sendSceneReady(request:Object):Boolean {
        var response:Object = baseResponse("create", "scene_ready", true, request);
        response.durable = true;
        if (_characterName != "") response.characterName = _characterName;
        return sendResponse(response);
    }

    private static function safeCallId(request:Object):String {
        return typeof request.callId == "string" ? String(request.callId) : "";
    }

    private static function safeAttemptId(request:Object):String {
        if (typeof request.attemptId == "string") return String(request.attemptId);
        return _root._bootstrapAttemptId == undefined
            ? "" : String(_root._bootstrapAttemptId);
    }

    private static function safeSlotKey(request:Object):String {
        if (typeof request.slotKey == "string") return String(request.slotKey);
        return _root.savePath == undefined ? "" : String(_root.savePath);
    }

    private static function currentRequest():Object {
        return {callId:_callId, attemptId:_attemptId, slotKey:_slotKey};
    }

    private static function isDurablePhase():Boolean {
        return _phase == "durable" || _phase == "transitioning"
            || (_phase == "scene_ready" && _kind == "create");
    }

    private static function resetIfRootAttemptChanged():Void {
        if (_attemptId != "" && _attemptId != String(_root._bootstrapAttemptId)) {
            resetState();
        }
    }

    private static function resetState():Void {
        _attemptId = "";
        _slotKey = "";
        _kind = "";
        _phase = "idle";
        _draftSignature = "";
        _characterName = "";
        _startToken = "";
        _callId = "";
        _sceneNotified = false;
    }

    private static function prepareCharacter(initialState:Object):Object {
        if (_prepareHookForTests != null) return _prepareHookForTests(initialState);
        return SaveManager.getInstance().prepareNewCharacter(
            initialState, "character_creation");
    }

    private static function flushCharacter():Boolean {
        if (_flushHookForTests != null) return _flushHookForTests() === true;
        return SaveManager.getInstance().flushNow() === true;
    }

    private static function startTutorial(startToken:String,
            accepted:Function, failed:Function):Boolean {
        if (_startHookForTests != null) {
            return _startHookForTests(
                startToken, false, accepted, failed) === true;
        }
        return SaveManager.getInstance().startNewCharacterTutorial(
            startToken, false, accepted, failed);
    }

    private static function reserveTutorial():Object {
        if (_reserveHookForTests != null) return _reserveHookForTests();
        return SaveManager.getInstance().reserveNewCharacterTutorial(
            "character_creation_retry");
    }

    private static function sendResponse(response:Object):Boolean {
        if (_root.server == undefined
                || typeof _root.server.sendSocketMessage != "function") return false;
        if (_json == undefined) _json = new LiteJSON();
        return _root.server.sendSocketMessage(_json.stringifySafe(response)) === true;
    }

    /** focused TestLoader 专用，生产代码不得调用。 */
    public static function _setHooksForTests(
            prepareHook:Function, flushHook:Function, startHook:Function,
            reserveHook:Function):Void {
        _prepareHookForTests = prepareHook;
        _flushHookForTests = flushHook;
        _startHookForTests = startHook;
        _reserveHookForTests = reserveHook;
    }

    /** focused TestLoader 专用，生产代码不得调用。 */
    public static function _resetForTests():Void {
        resetState();
        _prepareHookForTests = null;
        _flushHookForTests = null;
        _startHookForTests = null;
        _reserveHookForTests = null;
    }

    /** focused TestLoader 专用只读状态。 */
    public static function _stateForTests():Object {
        return {
            attemptId:_attemptId,
            slotKey:_slotKey,
            kind:_kind,
            phase:_phase,
            draftSignature:_draftSignature,
            characterName:_characterName,
            startToken:_startToken,
            callId:_callId,
            sceneNotified:_sceneNotified
        };
    }
}
