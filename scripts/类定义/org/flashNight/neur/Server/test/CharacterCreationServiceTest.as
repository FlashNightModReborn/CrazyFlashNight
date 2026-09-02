import org.flashNight.neur.Server.BootstrapWait;

import org.flashNight.neur.Server.CharacterCreationService;
import org.flashNight.arki.ui.HairdresserPanelService;
import org.flashNight.arki.item.ItemUtil;
import JSON;

/** 启动前门建角 focused 契约。 */
class org.flashNight.neur.Server.test.CharacterCreationServiceTest {

    private static var testCount:Number = 0;
    private static var passedCount:Number = 0;
    private static var failedCount:Number = 0;
    private static var sent:Array;
    private static var events:Array;
    private static var flushResults:Array;
    private static var prepareCalls:Number;
    private static var flushCalls:Number;
    private static var startCalls:Number;
    private static var reserveCalls:Number;
    private static var notifyCalls:Number;
    private static var gotoCalls:Number;
    private static var capturedAccepted:Function;
    private static var capturedFailed:Function;
    private static var capturedInitialState:Object;
    private static var capturedSynthetic:Boolean;

    public static function runAllTests():Void {
        trace("========== CharacterCreationServiceTest START ==========");
        testCount = 0; passedCount = 0; failedCount = 0;
        var itemCatalogReceipt:Object = beginAppearanceItemCatalogFixture();
        try {
            test_snapshot_contract_and_real_catalog_projection();
            test_catalog_fail_closed();
            test_invalid_requests_have_zero_transaction_side_effects();
            test_durable_retry_idempotence_and_stage_only_retry();
            test_create_scene_ready_requires_exact_live_actor();
            test_resolved_save_waits_for_real_scene_ready();
        } finally {
            endAppearanceItemCatalogFixture(itemCatalogReceipt);
            CharacterCreationService._resetForTests();
            trace("CharacterCreationServiceTest Tests Passed: " + passedCount);
            trace("CharacterCreationServiceTest Tests Failed: " + failedCount);
        }
    }

    private static function assert(cond:Boolean, msg:String):Void {
        testCount++;
        if (cond) { passedCount++; trace("[PASS] " + msg); }
        else { failedCount++; trace("[FAIL] " + msg); }
    }

    private static function setUp():Void {
        CharacterCreationService._resetForTests();
        sent = [];
        events = [];
        flushResults = [];
        prepareCalls = 0;
        flushCalls = 0;
        startCalls = 0;
        reserveCalls = 0;
        notifyCalls = 0;
        gotoCalls = 0;
        capturedAccepted = null;
        capturedFailed = null;
        capturedInitialState = null;
        capturedSynthetic = true;

        _root._bootstrapAttemptId = "attempt-A";
        _root.savePath = "slot-A";
        _root.当前关卡名 = "";
        _root.控制目标 = "主角";
        _root.gameworld = {};
        _root.notifyGameEntered = function():Void {
            org.flashNight.neur.Server.test.CharacterCreationServiceTest.recordNotify();
        };
        _root.gotoAndStop = function(frameName:String):Void {
            org.flashNight.neur.Server.test.CharacterCreationServiceTest.recordGoto(frameName);
        };
        _root.server = {
            sendSocketMessage:function(message:String):Boolean {
                return org.flashNight.neur.Server.test.CharacterCreationServiceTest.recordSend(
                    message);
            }
        };

        installHairCatalog();
        CharacterCreationService.install();
        CharacterCreationService._setHooksForTests(
            function(initialState:Object):Object {
                return org.flashNight.neur.Server.test.CharacterCreationServiceTest.recordPrepare(
                    initialState);
            },
            function():Boolean {
                return org.flashNight.neur.Server.test.CharacterCreationServiceTest.recordFlush();
            },
            function(token:String, synthetic:Boolean,
                    accepted:Function, failed:Function):Boolean {
                return org.flashNight.neur.Server.test.CharacterCreationServiceTest.recordStart(
                    token, synthetic, accepted, failed);
            },
            function():Object {
                return org.flashNight.neur.Server.test.CharacterCreationServiceTest.recordReserve();
            }
        );
    }

    private static function installHairCatalog():Void {
        _root.发型库 = [];
        _root.发型名称库 = [];
        _root.发型价格 = [];
        for (var i:Number = 0; i < 77; i++) {
            _root.发型库.push("目录发型-" + i);
            _root.发型名称库.push("目录名称-" + i);
            _root.发型价格.push(0);
        }
        _root.发型库[0] = "光头";
        _root.发型名称库[0] = "光头";
        _root.发型库[7] = "发型-男式-黑暴走头";
        _root.发型名称库[7] = "黑暴走头";
        _root.发型库[8] = "发型-女式-咖啡色中长马尾";
        _root.发型名称库[8] = "咖啡色中长马尾";
        _root.发型库[20] = "发型-男式-平头";
        _root.发型名称库[20] = "平头";
        _root.发型库[32] = "发型-男式-平头";
        _root.发型名称库[32] = "平头";
    }

    /** TestLoader 不加载生产 items XML；只安装本服务所需的最小只读目录。 */
    private static function beginAppearanceItemCatalogFixture():Object {
        var receipt:Object = {
            itemDataDict:ItemUtil.itemDataDict,
            equipmentDict:ItemUtil.equipmentDict,
            materialDict:ItemUtil.materialDict,
            informationMaxValueDict:ItemUtil.informationMaxValueDict,
            balanceDataDict:ItemUtil.balanceDataDict
        };
        ItemUtil.itemDataDict = {};
        // focused fixture 不测试 EquipmentCalculator；这里让 BaseItem 保持一级只读实例，
        // 生产启动序列仍会从真实 equipmentDict 把这些条目识别为防具。
        ItemUtil.equipmentDict = {};
        ItemUtil.materialDict = {};
        ItemUtil.informationMaxValueDict = {};
        ItemUtil.balanceDataDict = {};

        addAppearanceItem("浅灰背心", "上装装备", "浅灰背心");
        addAppearanceItem("绿色马甲", "上装装备", "绿色马甲");
        addAppearanceItem("黑色功夫装", "上装装备", "黑色功夫装");
        addAppearanceItem("廉价西服", "上装装备", "廉价西服");
        addAppearanceItem("米色高腰背心", "上装装备", "米色高腰背心");
        addAppearanceItem("黑灰色连帽马甲", "上装装备", "黑灰色连帽马甲");
        addAppearanceItem("咖啡色多包裤", "下装装备", "咖啡色多包裤");
        addAppearanceItem("咖啡色多包短裤", "下装装备", "咖啡色多包裤");
        addAppearanceItem("破牛仔裤", "下装装备", "破牛仔裤");
        addAppearanceItem("黑灰色毛边短裤", "下装装备", "黑灰色毛边短裤");
        addAppearanceItem("棕色带腿包短裤", "下装装备", "棕色带腿包短裤");
        addAppearanceItem("棕色皮鞋", "脚部装备", "棕色皮鞋");
        addAppearanceItem("白色板鞋", "脚部装备", "白色板鞋");
        addAppearanceItem("深灰色皮鞋", "脚部装备", "深灰色皮鞋");
        addAppearanceItem("棕色圆头皮鞋", "脚部装备", "棕色圆头皮鞋");
        return receipt;
    }

    private static function addAppearanceItem(name:String, use:String,
            iconName:String):Void {
        ItemUtil.itemDataDict[name] = {
            name:name,
            displayname:name,
            icon:iconName,
            type:"防具",
            use:use,
            price:900,
            description:"<FONT COLOR=\"#B22222\">focused 目录说明：</FONT>" + name,
            data:{level:1, weight:1, damage:0, defence:5}
        };
    }

    private static function endAppearanceItemCatalogFixture(receipt:Object):Void {
        ItemUtil.itemDataDict = receipt.itemDataDict;
        ItemUtil.equipmentDict = receipt.equipmentDict;
        ItemUtil.materialDict = receipt.materialDict;
        ItemUtil.informationMaxValueDict = receipt.informationMaxValueDict;
        ItemUtil.balanceDataDict = receipt.balanceDataDict;
    }

    public static function recordSend(message:String):Boolean {
        sent.push(message);
        var parsed:Object = new JSON(false).parse(message);
        events.push("send:" + parsed.phase + ":" + parsed.success);
        return true;
    }

    public static function recordPrepare(initialState:Object):Object {
        prepareCalls++;
        capturedInitialState = initialState;
        events.push("prepare");
        return {success:true, startToken:"token-1"};
    }

    public static function recordFlush():Boolean {
        flushCalls++;
        events.push("flush");
        if (flushResults.length > 0) return flushResults.shift() === true;
        return true;
    }

    public static function recordStart(token:String, synthetic:Boolean,
            accepted:Function, failed:Function):Boolean {
        startCalls++;
        capturedSynthetic = synthetic;
        capturedAccepted = accepted;
        capturedFailed = failed;
        events.push("start:" + token);
        return true;
    }

    public static function recordReserve():Object {
        reserveCalls++;
        events.push("reserve");
        return {success:true, startToken:"retry-token-" + reserveCalls};
    }

    public static function recordNotify():Void {
        notifyCalls++;
        events.push("notify");
    }

    public static function recordGoto(frameName:String):Void {
        gotoCalls++;
        events.push("goto:" + frameName);
    }

    private static function parseSent(index:Number):Object {
        return new JSON(false).parse(String(sent[index]));
    }

    private static function lastResponse():Object {
        return parseSent(sent.length - 1);
    }

    private static function snapshotRequest(callId:Number):Object {
        return {
            task:"cmd",
            action:"characterCreationSnapshot",
            v:1,
            attemptId:"attempt-A",
            slotKey:"slot-A",
            callId:"call-" + callId
        };
    }

    private static function createRequest(callId:Number, draft:Object):Object {
        return {
            task:"cmd",
            action:"characterCreate",
            v:1,
            attemptId:"attempt-A",
            slotKey:"slot-A",
            callId:"call-" + callId,
            draft:draft
        };
    }

    private static function resolvedRequest(callId:Number):Object {
        return {
            task:"cmd",
            action:"frontdoorEnterResolvedSave",
            v:1,
            attemptId:"attempt-A",
            slotKey:"slot-A",
            callId:"call-" + callId
        };
    }

    private static function maleDraft(characterName:String):Object {
        return {
            characterName:characterName,
            gender:"male",
            height:175,
            faceIdentifier:"男变装-基本脸型",
            hairIdentifier:"发型-男式-黑暴走头",
            upperIdentifier:"黑色功夫装",
            lowerIdentifier:"咖啡色多包裤",
            footwearIdentifier:"棕色皮鞋",
            difficulty:"balanced"
        };
    }

    private static function stringArrayContains(values:Array, value:String):Boolean {
        for (var i:Number = 0; i < values.length; i++) {
            if (values[i] == value) return true;
        }
        return false;
    }

    private static function hasExactRichItemKeys(row:Object):Boolean {
        var expected:Array = [
            "identifier", "name", "iconName", "itemType", "introHTML", "descHTML"
        ];
        if (row == null || typeof row != "object" || row instanceof Array) return false;
        var count:Number = 0;
        for (var key:String in row) {
            if (!Object.prototype.hasOwnProperty.call(row, key)) continue;
            if (!stringArrayContains(expected, key)) return false;
            count++;
        }
        if (count != expected.length) return false;
        for (var i:Number = 0; i < expected.length; i++) {
            var value = row[expected[i]];
            if (typeof value != "string" || value == "") return false;
        }
        return true;
    }

    private static function richCatalogMatches(rows:Array, expectedIdentifiers:Array):Boolean {
        if (!(rows instanceof Array) || rows.length != expectedIdentifiers.length) return false;
        for (var i:Number = 0; i < rows.length; i++) {
            if (!hasExactRichItemKeys(rows[i])
                    || rows[i].identifier != expectedIdentifiers[i]
                    || rows[i].itemType != "防具") return false;
        }
        return true;
    }

    private static function appearanceCatalogIsStrict(catalog:Object):Boolean {
        return richCatalogMatches(catalog.upper.male,
                ["浅灰背心", "绿色马甲", "黑色功夫装", "廉价西服"])
            && richCatalogMatches(catalog.upper.female,
                ["浅灰背心", "米色高腰背心", "黑灰色连帽马甲", "廉价西服"])
            && richCatalogMatches(catalog.lower.male,
                ["咖啡色多包裤", "咖啡色多包短裤", "破牛仔裤"])
            && richCatalogMatches(catalog.lower.female,
                ["黑灰色毛边短裤", "棕色带腿包短裤", "破牛仔裤"])
            && richCatalogMatches(catalog.footwear.male,
                ["棕色皮鞋", "白色板鞋"])
            && richCatalogMatches(catalog.footwear.female,
                ["深灰色皮鞋", "棕色圆头皮鞋", "白色板鞋"]);
    }

    private static function test_snapshot_contract_and_real_catalog_projection():Void {
        setUp();
        CharacterCreationService.handle("snapshot", snapshotRequest(11));
        var response:Object = lastResponse();
        assert(response.task == "character_create_response"
                && response.callId == "call-11" && response.v == 1
                && response.operation == "snapshot" && response.phase == "snapshot"
                && response.success && response.attemptId == "attempt-A"
                && response.slotKey == "slot-A",
            "snapshot emits the frozen flat envelope");
        assert(response.constraints.displayNameMin == 1
                && response.constraints.displayNameMax == 32
                && response.constraints.characterNameMin == 1
                && response.constraints.characterNameMax == 15
                && response.constraints.heightMin == 150
                && response.constraints.heightMax == 200,
            "snapshot publishes exact display/character/height constraints");
        assert(response.defaults.male.height == 175
                && response.defaults.male.hairIdentifier == "发型-男式-黑暴走头"
                && response.defaults.male.difficulty == "balanced"
                && response.defaults.female.height == 165
                && response.defaults.female.hairIdentifier == "发型-女式-咖啡色中长马尾",
            "snapshot projects the two legacy defaults");
        assert(!(response.appearanceCatalog.faces.male instanceof Array)
                && response.appearanceCatalog.faces.male.identifier == "男变装-基本脸型"
                && response.appearanceCatalog.faces.female.identifier == "女变装-基本脸型",
            "faces remain one frozen object per gender");
        var upper:Object = response.appearanceCatalog.upper.male[2];
        var aliasedIcon:Object = response.appearanceCatalog.lower.male[1];
        assert(appearanceCatalogIsStrict(response.appearanceCatalog)
                && upper.identifier == "黑色功夫装"
                && upper.name == "黑色功夫装"
                && upper.iconName == "黑色功夫装"
                && upper.itemType == "防具"
                && upper.introHTML.length > 0 && upper.descHTML.length > 0
                && aliasedIcon.identifier == "咖啡色多包短裤"
                && aliasedIcon.iconName == "咖啡色多包裤",
            "snapshot keeps strict rich rows, source order and the real item-data icon alias");
        assert(response.hairCatalog.length == 77
                && response.hairCatalog[0].identifier == "光头"
                && response.hairCatalog[76].identifier == "目录发型-76",
            "snapshot forwards all current Hairdresser rows in source order");
        assert(response.hairCatalog[20].identifier == "发型-男式-平头"
                && response.hairCatalog[32].identifier == "发型-男式-平头",
            "snapshot preserves duplicate Hairdresser rows");
        _root.发型库.push("目录未来扩充发型");
        _root.发型名称库.push("未来扩充发型");
        _root.发型价格.push(0);
        CharacterCreationService.handle("snapshot", snapshotRequest(12));
        var expanded:Object = lastResponse();
        assert(expanded.success && expanded.hairCatalog.length == 78
                && expanded.hairCatalog[77].identifier == "目录未来扩充发型",
            "production catalog accepts valid real Hairdresser expansion beyond current 77 rows");
        assert(response.difficulties.length == 3
                && response.difficulties[0].identifier == "balanced"
                && response.difficulties[0].recommended === true
                && response.difficulties[1].recommended === false
                && response.difficulties[2].description.indexOf("自我限制玩法") >= 0,
            "snapshot carries the three authored difficulty explanations");
    }

    private static function test_catalog_fail_closed():Void {
        setUp();
        _root.发型库 = [];
        _root.发型名称库 = [];
        _root.发型价格 = [];
        CharacterCreationService.handle("snapshot", snapshotRequest(21));
        var unavailable:Object = lastResponse();
        assert(!unavailable.success && unavailable.phase == "rejected"
                && unavailable.error == "catalog_not_ready" && unavailable.retryable,
            "unready Hairdresser catalog fails closed and remains retryable");

        installHairCatalog();
        _root.发型价格[40] = 1;
        CharacterCreationService.handle("snapshot", snapshotRequest(22));
        var pricing:Object = lastResponse();
        assert(!pricing.success && pricing.error == "pricing_unsupported",
            "non-free Hairdresser data blocks character creation projection");
        assert(prepareCalls == 0 && flushCalls == 0 && startCalls == 0,
            "catalog failures never touch the creation transaction");
    }

    private static function test_invalid_requests_have_zero_transaction_side_effects():Void {
        setUp();
        _root.角色名 = "旧角色";
        var extraEnvelope:Object = snapshotRequest(31);
        extraEnvelope.extra = true;
        CharacterCreationService.handle("snapshot", extraEnvelope);
        assert(lastResponse().error == "invalid_envelope",
            "snapshot rejects every extra envelope key");

        var stale:Object = createRequest(32, maleDraft("新角色"));
        stale.attemptId = "attempt-old";
        CharacterCreationService.handle("create", stale);
        assert(lastResponse().error == "stale_attempt",
            "create rejects a non-current bootstrap attempt");

        var wrongSlot:Object = createRequest(33, maleDraft("新角色"));
        wrongSlot.slotKey = "slot-other";
        CharacterCreationService.handle("create", wrongSlot);
        assert(lastResponse().error == "slot_mismatch",
            "create rejects any slot rewrite");

        var extraDraft:Object = maleDraft("新角色");
        extraDraft.randomAppearance = true;
        CharacterCreationService.handle("create", createRequest(34, extraDraft));
        assert(lastResponse().error == "invalid_draft",
            "draft exact-key validation rejects random appearance extensions");

        CharacterCreationService.handle(
            "create", createRequest(35, maleDraft("坏\n名字")));
        assert(lastResponse().error == "invalid_character_name",
            "character name rejects control characters");

        var crossGender:Object = maleDraft("新角色");
        crossGender.upperIdentifier = "米色高腰背心";
        CharacterCreationService.handle("create", createRequest(36, crossGender));
        assert(lastResponse().error == "invalid_upper",
            "gender clothing allowlists are enforced authoritatively");

        var state:Object = CharacterCreationService._stateForTests();
        assert(prepareCalls == 0 && flushCalls == 0 && startCalls == 0
                && reserveCalls == 0 && state.phase == "idle"
                && _root.角色名 == "旧角色",
            "invalid requests leave root, reservation, initialization and save untouched");
    }

    private static function test_durable_retry_idempotence_and_stage_only_retry():Void {
        setUp();
        flushResults = [false, true];
        var quotedName:String = "阿\"七";
        var draft:Object = maleDraft(quotedName);
        CharacterCreationService.handle("create", createRequest(41, draft));
        var first:Object = lastResponse();
        assert(!first.success && first.phase == "rejected" && !first.durable
                && first.localFlush === false
                && first.error == "save_failed" && first.retryable,
            "flush false emits no durable success and leaves a retryable save failure");
        assert(prepareCalls == 1 && flushCalls == 1 && startCalls == 0
                && CharacterCreationService._stateForTests().phase == "prepared",
            "first failed flush initializes exactly once and starts no XML");
        assert(capturedInitialState.characterName == quotedName
                && capturedInitialState.genderText == "男"
                && capturedInitialState.height == 175
                && capturedInitialState.difficultyText == "平衡模式（困难）",
            "validated draft maps to the current Chinese root fields");

        CharacterCreationService.handle("create", createRequest(42, draft));
        var second:Object = parseSent(1);
        assert(prepareCalls == 1 && flushCalls == 2 && startCalls == 1,
            "same attempt and draft retries flush without duplicate initialization");
        assert(events.join("|")
                == "prepare|flush|send:rejected:false|flush|send:durable:true|start:token-1",
            "transaction order is reserve-initialize then flush true then durable response then XML start");
        assert(second.success && second.durable && second.localFlush === true
                && second.callId == "call-42"
                && second.characterName == quotedName
                && String(sent[1]).indexOf("\\\"") >= 0,
            "LiteJSON stringifySafe preserves a quoted Unicode character name");
        assert(capturedSynthetic === false,
            "Web creation explicitly disables the legacy synthetic SceneReady");

        CharacterCreationService.handle("create", createRequest(43, draft));
        assert(prepareCalls == 1 && flushCalls == 2 && startCalls == 1
                && lastResponse().phase == "durable",
            "duplicate create while transitioning only replays durable state");

        CharacterCreationService.handle("create", createRequest(44, maleDraft("另一个角色")));
        assert(lastResponse().error == "attempt_conflict"
                && prepareCalls == 1 && flushCalls == 2 && startCalls == 1,
            "same attempt with a different draft is a zero-write conflict");

        capturedFailed("stage_load_failed");
        var stageFailure:Object = lastResponse();
        assert(stageFailure.phase == "rejected" && !stageFailure.success
                && stageFailure.durable && stageFailure.error == "stage_load_failed"
                && CharacterCreationService._stateForTests().phase == "durable",
            "stage load failure preserves the already durable character");

        CharacterCreationService.handle("create", createRequest(45, draft));
        assert(prepareCalls == 1 && flushCalls == 2 && reserveCalls == 1
                && startCalls == 2
                && CharacterCreationService._stateForTests().phase == "transitioning",
            "durable stage retry only re-reserves and restarts the tutorial");
    }

    private static function test_create_scene_ready_requires_exact_live_actor():Void {
        setUp();
        CharacterCreationService.handle("create", createRequest(51, maleDraft("场景角色")));
        _root.当前关卡名 = "其他关卡";
        CharacterCreationService.onSceneReady();
        assert(notifyCalls == 0 && CharacterCreationService._stateForTests().phase == "transitioning",
            "wrong-stage SceneReady cannot complete character creation");

        _root.当前关卡名 = "教学关卡";
        CharacterCreationService.onSceneReady();
        assert(notifyCalls == 0,
            "SceneReady without the controlled hero cannot notify game entered");

        _root.gameworld.主角 = {};
        CharacterCreationService.onSceneReady();
        assert(notifyCalls == 0,
            "an object without the live friendly-hero marker cannot complete entry");

        _root.gameworld.主角 = {是否为敌人:false};
        _root._bootstrapAttemptId = "attempt-other";
        CharacterCreationService.onSceneReady();
        assert(notifyCalls == 0,
            "SceneReady is fenced to the exact current bootstrap attempt");
        _root._bootstrapAttemptId = "attempt-A";
        CharacterCreationService.onSceneReady();
        var scene:Object = lastResponse();
        assert(notifyCalls == 1 && scene.success && scene.phase == "scene_ready"
                && scene.durable && scene.callId == "call-51"
                && scene.characterName == "场景角色",
            "exact attempt tutorial SceneReady with a live hero notifies then responds");

        var sentBefore:Number = sent.length;
        CharacterCreationService.onSceneReady();
        assert(notifyCalls == 1 && sent.length == sentBefore,
            "duplicate SceneReady is one-shot");
    }

    private static function test_resolved_save_waits_for_real_scene_ready():Void {
        setUp();
        CharacterCreationService.handle("resolved_save", resolvedRequest(61));
        assert(events.join("|") == "goto:读盘"
                && gotoCalls == 1 && notifyCalls == 0 && sent.length == 0,
            "resolved-save valid command is one-way and enters load without a create receipt or early s:1");

        CharacterCreationService.onSceneReady();
        assert(notifyCalls == 0,
            "resolved-save synthetic or actorless SceneReady is ignored");

        _root.当前关卡名 = "基地";
        _root.gameworld.主角 = {是否为敌人:false};
        CharacterCreationService.onSceneReady();
        assert(notifyCalls == 1 && sent.length == 0
                && CharacterCreationService._stateForTests().phase == "scene_ready",
            "resolved save completes only through exact actor-ready s:1 without a create response");

        CharacterCreationService.handle("resolved_save", resolvedRequest(62));
        assert(notifyCalls == 1 && gotoCalls == 1 && sent.length == 0,
            "resolved-save retry after completion is a no-op without duplicate notify, goto or receipt");
    }
}
