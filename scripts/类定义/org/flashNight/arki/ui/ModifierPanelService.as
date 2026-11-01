import org.flashNight.arki.item.ItemUtil;
import org.flashNight.arki.ui.PanelRequestEnvelope;

/**
 * 修改器 Web Panel 的 AS2 权威服务。
 *
 * Web 只持有目录投影、筛选和草稿；会话、写资格、目标校验、dirty 与
 * 一次性操作收据均由本服务裁决。旧 Flash 修改工具保留为回退，不在这里
 * 绑定任何 XFL 元件。
 */
class org.flashNight.arki.ui.ModifierPanelService {
    private static var _installed:Boolean = false;
    private static var _json:LiteJSON;
    private static var _sequence:Number = 0;
    private static var _spawnCounter:Number = 0;
    private static var _mercCounter:Number = 0;
    private static var _active:Object;
    private static var _sessions:Object = {};
    private static var _order:Array = [];
    private static var _maxSafe:Number = 9007199254740991;
    private static var _itemPageSize:Number = 64;
    private static var _unitPageSize:Number = 8;
    private static var _maxSessions:Number = 128;

    public static function install():Void {
        if (_installed) return;
        _installed = true;
        if (_root.gameCommands == undefined) _root.gameCommands = {};
        _root.gameCommands["modifierSnapshot"] = function(params):Void {
            org.flashNight.arki.ui.ModifierPanelService.handle("snapshot", params);
        };
        _root.gameCommands["modifierItems"] = function(params):Void {
            org.flashNight.arki.ui.ModifierPanelService.handle("items", params);
        };
        _root.gameCommands["modifierUnits"] = function(params):Void {
            org.flashNight.arki.ui.ModifierPanelService.handle("units", params);
        };
        _root.gameCommands["modifierQuery"] = function(params):Void {
            org.flashNight.arki.ui.ModifierPanelService.handle("query", params);
        };
        _root.gameCommands["modifierGrantMoney"] = function(params):Void {
            org.flashNight.arki.ui.ModifierPanelService.handle("grantMoney", params);
        };
        _root.gameCommands["modifierGrantKCoin"] = function(params):Void {
            org.flashNight.arki.ui.ModifierPanelService.handle("grantKCoin", params);
        };
        _root.gameCommands["modifierSpawnItem"] = function(params):Void {
            org.flashNight.arki.ui.ModifierPanelService.handle("spawnItem", params);
        };
        _root.gameCommands["modifierLevelAction"] = function(params):Void {
            org.flashNight.arki.ui.ModifierPanelService.handle("levelAction", params);
        };
        _root.gameCommands["modifierGrantTask"] = function(params):Void {
            org.flashNight.arki.ui.ModifierPanelService.handle("grantTask", params);
        };
        _root.gameCommands["modifierSpawnUnit"] = function(params):Void {
            org.flashNight.arki.ui.ModifierPanelService.handle("spawnUnit", params);
        };
        _root.gameCommands["modifierSpawnMerc"] = function(params):Void {
            org.flashNight.arki.ui.ModifierPanelService.handle("spawnMerc", params);
        };
        _root.gameCommands["openModifier"] = function():Boolean {
            return org.flashNight.arki.ui.ModifierPanelService.openPanel();
        };
        _root.gameCommands["modifierPanelClosed"] = function():Void {
            org.flashNight.arki.ui.ModifierPanelService.onPanelClosed();
        };
    }

    public static function openPanel():Boolean {
        if (typeof _root.server.sendSocketMessage != "function") return false;
        if (_root.gameworld == undefined || _root.gameworld[_root.控制目标] == undefined) {
            _root.最上层发布文字提示("修改器需要在角色场景中打开。");
            return false;
        }
        if (isChallengeMode()) {
            _root.最上层发布文字提示("挑战模式中修改器不可用。");
            return false;
        }
        if (_root.修改工具界面 != undefined) _root.修改工具界面._visible = false;
        retireActive();
        var token:String = "modifier." + getTimer() + "." + (++_sequence);
        var session:Object = {
            token: token,
            phase: "editing",
            revision: 0,
            saveOwner: _root.存档系统,
            slot: String(_root.savePath),
            scene: String(_root.关卡标志),
            lastOperation: null,
            pendingAction: null
        };
        _active = session;
        _sessions[token] = session;
        _order.push(token);
        if (_order.length > _maxSessions) delete _sessions[_order.shift()];
        var payload:String = org.flashNight.arki.ui.PanelRequestEnvelope.build(
            "modifier", "nativehud_modifier", [], [{name:"token", value:token}]
        );
        if (_root.server.sendSocketMessage(payload) === false) {
            session.phase = "expired";
            _active = undefined;
            return false;
        }
        return true;
    }

    public static function handle(command:String, params:Object):Void {
        var request:Object = params == undefined ? {} : params;
        var callId:Number = Number(request.callId);
        if (isNaN(callId)) callId = 0;
        var response:Object = execute(command, request);
        response.task = "modifier_response";
        response.callId = callId;
        if (_json == undefined) _json = new LiteJSON();
        if (typeof _root.server.sendSocketMessage == "function") {
            _root.server.sendSocketMessage(_json.stringifySafe(response));
        }
    }

    public static function execute(command:String, params:Object):Object {
        if (command == "snapshot") return readSnapshot(params);
        if (command == "items") return readItems(params);
        if (command == "units") return readUnits(params);
        if (command == "query") return readQuery(params);
        if (command == "grantMoney" || command == "grantKCoin" || command == "spawnItem"
                || command == "levelAction" || command == "grantTask"
                || command == "spawnUnit" || command == "spawnMerc") {
            return write(command, params);
        }
        return fail(command, tokenOf(params), "unsupported_cmd");
    }

    private static function readSnapshot(params:Object):Object {
        if (params == undefined || params.v !== 1) return fail("snapshot", tokenOf(params), "unsupported_version");
        if (!hasOnly(params, ["v", "token", "task", "action", "callId"])) return fail("snapshot", tokenOf(params), "invalid_payload");
        var token:String = tokenOf(params);
        if (!validToken(token)) return fail("snapshot", token, "invalid_payload");
        var session:Object = _sessions[token];
        if (session == undefined) return fail("snapshot", token, "stale_token");
        if (session.phase == "closed") return fail("snapshot", token, "stale_token");
        if (!sameContext(session)) {
            session.phase = "expired";
            return fail("snapshot", token, "context_changed");
        }
        var hero:Object = _root.gameworld[_root.控制目标];
        return {
            v: 1,
            operation: "snapshot",
            token: token,
            success: true,
            revision: Number(session.revision),
            phase: String(session.phase),
            state: {
                money: numberOrZero(_root.金钱),
                kcoin: numberOrZero(_root.虚拟币),
                maxLevel: numberOrZero(_root.最大等级),
                inWorld: hero != undefined,
                stageActive: stageState(),
                challengeMode: isChallengeMode(),
                saveAvailable: saveAvailable()
            },
            itemCount: countItems(),
            unitCount: countUnits(),
            itemPageSize: _itemPageSize,
            unitPageSize: _unitPageSize
        };
    }

    private static function readItems(params:Object):Object {
        if (params == undefined || params.v !== 1) return fail("items", tokenOf(params), "unsupported_version");
        if (!hasOnly(params, ["v", "token", "query", "page", "task", "action", "callId"])) return fail("items", tokenOf(params), "invalid_payload");
        var token:String = tokenOf(params);
        if (!validToken(token)) return fail("items", token, "invalid_payload");
        var session:Object = _sessions[token];
        if (session == undefined) return fail("items", token, "stale_token");
        if (session.phase == "expired") return fail("items", token, "context_changed");
        var query:String = typeof params.query == "string" ? String(params.query) : "";
        if (query.length > 64) return fail("items", token, "invalid_payload");
        var page:Number = integerParam(params.page, 1, 9999);
        if (page < 1) return fail("items", token, "invalid_payload");
        var catalog:Array = itemCatalog();
        var matches:Array = [];
        var needle:String = query.toLowerCase();
        var i:Number;
        var total:Number = 0;
        if (needle == "") {
            for (i = 0; i < catalog.length; i++) {
                if (catalog[i] != null) total++;
            }
            var start:Number = (page - 1) * _itemPageSize;
            for (i = start; i < catalog.length && matches.length < _itemPageSize; i++) {
                if (catalog[i] != null) matches.push(copyItem(catalog[i]));
            }
        } else {
            for (i = 0; i < catalog.length; i++) {
                if (catalog[i] != null && itemMatches(catalog[i], needle)) {
                    total++;
                    if (total > (page - 1) * _itemPageSize && matches.length < _itemPageSize) {
                        matches.push(copyItem(catalog[i]));
                    }
                }
            }
        }
        return {
            v: 1, operation: "items", token: token, success: true,
            revision: Number(session.revision), query: query, page: page,
            pageSize: _itemPageSize, total: total, items: matches
        };
    }

    private static function readUnits(params:Object):Object {
        if (params == undefined || params.v !== 1) return fail("units", tokenOf(params), "unsupported_version");
        if (!hasOnly(params, ["v", "token", "query", "page", "task", "action", "callId"])) return fail("units", tokenOf(params), "invalid_payload");
        var token:String = tokenOf(params);
        if (!validToken(token)) return fail("units", token, "invalid_payload");
        var session:Object = _sessions[token];
        if (session == undefined) return fail("units", token, "stale_token");
        if (session.phase == "expired") return fail("units", token, "context_changed");
        var query:String = typeof params.query == "string" ? String(params.query) : "";
        if (query.length > 64) return fail("units", token, "invalid_payload");
        var page:Number = integerParam(params.page, 1, 9999);
        if (page < 1) return fail("units", token, "invalid_payload");
        var catalog:Array = unitCatalog();
        var matches:Array = [];
        var needle:String = query.toLowerCase();
        var total:Number = 0;
        var i:Number;
        if (needle == "") {
            total = catalog.length;
            var start:Number = (page - 1) * _unitPageSize;
            for (i = start; i < catalog.length && matches.length < _unitPageSize; i++) {
                matches.push(copyUnit(catalog[i]));
            }
        } else {
            for (i = 0; i < catalog.length; i++) {
                if (unitMatches(catalog[i], needle)) {
                    total++;
                    if (total > (page - 1) * _unitPageSize && matches.length < _unitPageSize) {
                        matches.push(copyUnit(catalog[i]));
                    }
                }
            }
        }
        return {
            v: 1, operation: "units", token: token, success: true,
            revision: Number(session.revision), query: query, page: page,
            pageSize: _unitPageSize, total: total, units: matches
        };
    }

    private static function readQuery(params:Object):Object {
        if (params == undefined || params.v !== 1) return fail("query", tokenOf(params), "unsupported_version");
        if (!hasOnly(params, ["v", "token", "operationId", "task", "action", "callId"])) return fail("query", tokenOf(params), "invalid_payload");
        var token:String = tokenOf(params);
        var operationId:String = typeof params.operationId == "string" ? String(params.operationId) : "";
        if (!validToken(token) || !validOperationId(operationId)) return fail("query", token, "invalid_payload");
        var session:Object = _sessions[token];
        if (session == undefined) return fail("query", token, "stale_token");
        if (session.lastOperation == null || session.lastOperation.id != operationId) {
            return {v:1, operation:"query", token:token, success:false, revision:Number(session.revision),
                operationId:operationId, queriedOperation:operationId, error:"not_applied", requiresReconcile:false};
        }
        var result:Object = copyResult(session.lastOperation.result);
        result.operation = "query";
        result.queriedOperation = operationId;
        result.token = token;
        result.revision = Number(session.revision);
        result.operationId = operationId;
        if (result.error == "applying") {
            result.success = false;
            result.error = "apply_ambiguous";
            result.requiresReconcile = true;
        }
        return result;
    }

    private static function write(command:String, params:Object):Object {
        var token:String = tokenOf(params);
        var operationId:String = params != undefined && typeof params.operationId == "string" ? String(params.operationId) : "";
        if (params == undefined || params.v !== 1) return writeFail(command, token, operationId, "unsupported_version");
        if (!validToken(token) || !validOperationId(operationId)) return writeFail(command, token, operationId, "invalid_payload");
        if (!validWriteFields(command, params)) return writeFail(command, token, operationId, "invalid_payload");
        var session:Object = _sessions[token];
        if (session == undefined) return writeFail(command, token, operationId, "stale_token");
        if (session.phase == "closed") return writeFail(command, token, operationId, "stale_token");
        if (session.phase == "expired") return writeFail(command, token, operationId, "context_changed");
        if (session.phase == "reconcile") return writeFail(command, token, operationId, "reconcile_required");
        if (session.lastOperation != null && session.lastOperation.id == operationId) {
            var cached:Object = copyResult(session.lastOperation.result);
            cached.operation = command;
            cached.token = token;
            cached.operationId = operationId;
            cached.revision = Number(session.revision);
            return cached;
        }
        var expected:Number = integerParam(params.expectedRevision, 0, 9007199254740991);
        if (expected < 0) return writeFail(command, token, operationId, "invalid_payload");
        if (expected != Number(session.revision)) return writeFail(command, token, operationId, "stale_revision");
        if (!sameContext(session)) {
            session.phase = "expired";
            return writeFail(command, token, operationId, "context_changed");
        }
        if (isChallengeMode()) return writeFail(command, token, operationId, "challenge_mode");
        if (!saveAvailable()) return writeFail(command, token, operationId, "save_unavailable");
        // 新写会取消上一笔尚未消费的关闭后动作，避免失败关闭后误执行旧场景跳转。
        session.pendingAction = null;
        // 先写入 applying 收据；即使后续抛错，同一 operationId 的 query 也不会被
        // 误判成“未执行”，更不会让 Web 换一个 operationId 重放。
        session.lastOperation = {id:operationId, result:{v:1, operation:command, token:token,
            success:false, revision:Number(session.revision), operationId:operationId,
            error:"applying", requiresReconcile:true}};
        var result:Object;
        try {
            switch (command) {
                case "grantMoney": result = applyGrantMoney(session, operationId); break;
                case "grantKCoin": result = applyGrantKCoin(session, operationId); break;
                case "spawnItem": result = applySpawnItem(session, operationId, params); break;
                case "levelAction": result = applyLevelAction(session, operationId, params); break;
                case "grantTask": result = applyGrantTask(session, operationId, params); break;
                case "spawnUnit": result = applySpawnUnit(session, operationId, params); break;
                case "spawnMerc": result = applySpawnMerc(session, operationId, params); break;
                default: result = fail(command, token, "unsupported_cmd");
            }
        } catch (applyError) {
            result = {v:1, operation:command, token:token, success:false,
                revision:Number(session.revision), operationId:operationId,
                error:"apply_ambiguous", requiresReconcile:true};
        }
        if (result == null) result = fail(command, token, "apply_failed");
        result.v = 1;
        result.operation = command;
        result.token = token;
        result.operationId = operationId;
        if (result.success === true) session.revision = Number(session.revision) + 1;
        result.revision = Number(session.revision);
        if (result.requiresReconcile === true) session.phase = "reconcile";
        session.lastOperation.result = copyResult(result);
        return result;
    }

    private static function writeFail(operation:String, token:String, operationId:String, error:String):Object {
        var result:Object = fail(operation, token, error);
        result.operationId = operationId;
        result.requiresReconcile = false;
        return result;
    }

    private static function applyGrantMoney(session:Object, operationId:String):Object {
        var current:Number = Number(_root.金钱);
        if (isNaN(current)) current = 0;
        if (!isFinite(current) || current < 0 || Math.floor(current) != current
                || current > _maxSafe) return fail("grantMoney", session.token, "invalid_balance");
        var next:Number = current + 100000;
        if (next > _maxSafe) next = _maxSafe;
        _root.金钱 = next;
        markDirty();
        var delta:Number = next - current;
        try {
            if (typeof _root.记录玩家货币变化 == "function") _root.记录玩家货币变化(
                delta, 0, {source:"cheat", reason:"modifier_grant", mergeScope:"operation", operationId:operationId});
        } catch (feedError) {
            trace("[Modifier] currency feed failed after authority write");
        }
        return {v:1, operation:"grantMoney", token:session.token, success:true,
            revision:Number(session.revision), operationId:operationId,
            message:"已增加 " + delta + " 金币", money:next};
    }

    private static function applyGrantKCoin(session:Object, operationId:String):Object {
        var current:Number = Number(_root.虚拟币);
        if (isNaN(current)) current = 0;
        if (!isFinite(current) || current < 0 || Math.floor(current) != current
                || current > _maxSafe) return fail("grantKCoin", session.token, "invalid_balance");
        var next:Number = current + 100000;
        if (next > _maxSafe) next = _maxSafe;
        _root.虚拟币 = next;
        markDirty();
        var delta:Number = next - current;
        try {
            if (typeof _root.记录玩家货币变化 == "function") _root.记录玩家货币变化(
                0, delta, {source:"cheat", reason:"modifier_grant", mergeScope:"operation", operationId:operationId});
        } catch (feedError) {
            trace("[Modifier] currency feed failed after authority write");
        }
        return {v:1, operation:"grantKCoin", token:session.token, success:true,
            revision:Number(session.revision), operationId:operationId,
            message:"已增加 " + delta + " K点", kcoin:next};
    }

    private static function applySpawnItem(session:Object, operationId:String, params:Object):Object {
        var itemName:String = typeof params.itemName == "string" ? String(params.itemName) : "";
        var quantity:Number = integerParam(params.quantity, 1, 999999999);
        if (itemName == "" || quantity < 1) return fail("spawnItem", session.token, "invalid_payload");
        if (!ItemUtil.isItem(itemName)) return fail("spawnItem", session.token, "item_unavailable");
        var hero:Object = currentHero();
        if (hero == undefined) return fail("spawnItem", session.token, "actor_unavailable");
        if (ItemUtil.isMaterial(itemName) && _root.收集品栏 != undefined
                && _root.收集品栏.材料 != undefined
                && typeof _root.收集品栏.材料.getValue == "function") {
            var owned:Number = Number(_root.收集品栏.材料.getValue(itemName));
            if (isNaN(owned) || owned < 0) owned = 0;
            var remaining:Number = _maxSafe - owned;
            if (quantity > remaining) quantity = remaining;
            if (quantity < 1) return fail("spawnItem", session.token, "quantity_overflow");
        }
        if (typeof _root.创建可拾取物 != "function") return fail("spawnItem", session.token, "pickup_unavailable");
        _root.创建可拾取物(itemName, quantity, hero._x, hero._y, true);
        return {v:1, operation:"spawnItem", token:session.token, success:true,
            revision:Number(session.revision), operationId:operationId, quantity:quantity,
            message:"已投放 " + itemName + " ×" + quantity};
    }

    private static function applyLevelAction(session:Object, operationId:String, params:Object):Object {
        var action:String = typeof params.levelAction == "string" ? String(params.levelAction) : "";
        if (action == "unlock_stages") return applyUnlockStages(session, operationId);
        if (action == "kill_all") return applyKillAll(session, operationId);
        if (action == "finish_wave") return applyFinishWave(session, operationId);
        if (action == "finish_map") return applyFinishMap(session, operationId);
        if (action == "finish_stage" || action == "test_space") {
            if (action == "finish_stage") {
                if (stageState() != "Active" || typeof _root.关卡结束 != "function")
                    return fail("levelAction", session.token, "stage_unavailable");
                session.pendingAction = {type:"finish_stage"};
                return {v:1, operation:"levelAction", token:session.token, success:true,
                    revision:Number(session.revision), operationId:operationId, closeAfter:true,
                    message:"关闭面板后将结算当前关卡。"};
            }
            if (_root.淡出动画 == undefined || typeof _root.淡出动画.淡出跳转帧 != "function")
                return fail("levelAction", session.token, "navigation_unavailable");
            session.pendingAction = {type:"test_space"};
            return {v:1, operation:"levelAction", token:session.token, success:true,
                revision:Number(session.revision), operationId:operationId, closeAfter:true,
                message:"关闭面板后将前往测试空间。"};
        }
        return fail("levelAction", session.token, "invalid_payload");
    }

    private static function applyUnlockStages(session:Object, operationId:String):Object {
        var changed:Number = 0;
        if (_root.关卡地图MC != undefined && _root.关卡地图MC._x != undefined) {
            _root.关卡地图MC.强制解锁关卡 = true;
            for (var each:String in _root.关卡地图MC) {
                var stage:Object = _root.关卡地图MC[each];
                if (stage != undefined && stage._x != undefined && stage._currentframe != 1) {
                    stage.关卡开放条件 = 0;
                    stage._visible = 1;
                    stage.gotoAndStop(1);
                    changed++;
                }
            }
        } else if (_root.gameworld != undefined && _root.gameworld._x != undefined) {
            for (var eachNpc:String in _root.gameworld) {
                var npc:Object = _root.gameworld[eachNpc];
                if (npc != undefined && !npc._visible && npc.NPC任务_任务 != undefined) {
                    npc.NPC任务_任务_等级限制 = 1;
                    npc._visible = true;
                    changed++;
                }
            }
        } else {
            return fail("levelAction", session.token, "not_allowed");
        }
        return {v:1, operation:"levelAction", token:session.token, success:true,
            revision:Number(session.revision), operationId:operationId, changed:changed,
            message:"已解锁 " + changed + " 个关卡/任务入口"};
    }

    private static function applyKillAll(session:Object, operationId:String):Object {
        if (typeof _root.调试_敌人全死 != "function") return fail("levelAction", session.token, "stage_unavailable");
        _root.调试_敌人全死();
        return {v:1, operation:"levelAction", token:session.token, success:true,
            revision:Number(session.revision), operationId:operationId, message:"已对场上敌人执行清除。"};
    }

    private static function applyFinishWave(session:Object, operationId:String):Object {
        if (typeof _root.调试_完成当前波次 != "function") return fail("levelAction", session.token, "wave_unavailable");
        if (_root.调试_完成当前波次() !== true) return fail("levelAction", session.token, "wave_unavailable");
        return {v:1, operation:"levelAction", token:session.token, success:true,
            revision:Number(session.revision), operationId:operationId, message:"已强制完成当前波次。"};
    }

    private static function applyFinishMap(session:Object, operationId:String):Object {
        if (typeof _root.调试_完成当前地图 != "function") return fail("levelAction", session.token, "stage_unavailable");
        if (_root.调试_完成当前地图() !== true) return fail("levelAction", session.token, "stage_unavailable");
        return {v:1, operation:"levelAction", token:session.token, success:true,
            revision:Number(session.revision), operationId:operationId, message:"已开启当前地图出口。"};
    }

    private static function applyGrantTask(session:Object, operationId:String, params:Object):Object {
        var taskId:Number = integerParam(params.taskId, 1, 999);
        if (taskId < 1) return fail("grantTask", session.token, "invalid_payload");
        if (typeof _root.getTaskData != "function" || typeof _root.GetTask != "function"
                || typeof _root.UpdateTaskProgress != "function") return fail("grantTask", session.token, "task_unavailable");
        var data:Object = _root.getTaskData(taskId);
        if (data == undefined || data == null || !(data.chain instanceof Array) || data.chain.length < 1)
            return fail("grantTask", session.token, "task_unavailable");
        var tasks:Array = _root.tasks_to_do;
        if (!(tasks instanceof Array)) return fail("grantTask", session.token, "task_unavailable");
        var chainId = data.chain[0];
        var loop:Number = 0;
        while (loop < tasks.length) {
            var current:Object = tasks[loop];
            if (current != undefined && typeof _root.getTaskData == "function") {
                var currentData:Object = _root.getTaskData(current.id);
                if (currentData != undefined && currentData != null && currentData.chain instanceof Array
                        && currentData.chain.length > 0 && currentData.chain[0] == chainId) {
                    tasks.splice(loop, 1);
                    continue;
                }
            }
            loop++;
        }
        _root.GetTask(data.id);
        _root.UpdateTaskProgress();
        if (taskId >= 1 && _root.task_chains_progress != undefined) {
            _root.主线任务进度 = taskId;
            _root.task_chains_progress.主线 = taskId;
        }
        if (typeof _root.检查任务数据完整性 == "function") _root.检查任务数据完整性();
        markDirty();
        return {v:1, operation:"grantTask", token:session.token, success:true,
            revision:Number(session.revision), operationId:operationId, taskId:taskId,
            message:"已获得主线任务 " + taskId};
    }

    private static function applySpawnUnit(session:Object, operationId:String, params:Object):Object {
        var unitId:Number = integerParam(params.unitId, 0, 999999);
        var count:Number = integerParam(params.count, 1, 100);
        var maxLevel:Number = integerParam(_root.最大等级, 1, 9999);
        if (maxLevel < 1) maxLevel = 9999;
        var level:Number = integerParam(params.level, 1, maxLevel);
        if (unitId < 0 || count < 1 || level < 1 || typeof params.hostile != "boolean")
            return fail("spawnUnit", session.token, "invalid_payload");
        var unit:Object = _root.兵种库 == undefined ? undefined : _root.兵种库["兵种" + unitId];
        if (unit == undefined || unit == null || unit.兵种名 == undefined || unit.兵种名 == null || String(unit.兵种名) == "")
            return fail("spawnUnit", session.token, "unit_unavailable");
        var hero:Object = currentHero();
        if (hero == undefined) return fail("spawnUnit", session.token, "actor_unavailable");
        if (typeof _root.加载游戏世界人物 != "function") return fail("spawnUnit", session.token, "spawn_unavailable");
        var spawned:Number = 0;
        var failed:Number = 0;
        for (var i:Number = 0; i < count; i++) {
            _spawnCounter++;
            var name:String = "修改器" + String(unit.名字) + "-" + _spawnCounter;
            try {
                _root.加载游戏世界人物(String(unit.兵种名), name, _root.gameworld.getNextHighestDepth(), {
                    _x: hero._x, _y: hero._y, 等级: level, 名字: unit.名字,
                    是否为敌人: params.hostile, 身高: unit.身高, 长枪: unit.长枪,
                    手枪: unit.手枪, 手枪2: unit.手枪2, 刀: unit.刀, 手雷: unit.手雷,
                    脸型: unit.脸型, 发型: unit.发型, 头部装备: unit.头部装备,
                    上装装备: unit.上装装备, 下装装备: unit.下装装备, 手部装备: unit.手部装备,
                    脚部装备: unit.脚部装备, 颈部装备: unit.颈部装备, 性别: unit.性别,
                    宠物属性: unit.宠物属性, 产生源: "修改器"
                });
                if (_root.gameworld[name] == undefined) failed++;
                else spawned++;
            } catch (spawnError) {
                failed++;
            }
        }
        if (spawned == 0) return fail("spawnUnit", session.token, "spawn_failed");
        return {v:1, operation:"spawnUnit", token:session.token, success:true,
            revision:Number(session.revision), operationId:operationId, spawned:spawned, failed:failed,
            message:"已生成 " + spawned + " 个单位" + (failed > 0 ? "（" + failed + " 个失败）" : "")};
    }

    private static function applySpawnMerc(session:Object, operationId:String, params:Object):Object {
        var unitId:Number = integerParam(params.unitId, 0, 999999);
        var maxLevel:Number = integerParam(_root.最大等级, 1, 9999);
        if (maxLevel < 1) maxLevel = 9999;
        var level:Number = integerParam(params.level, 1, maxLevel);
        if (unitId < 0 || level < 1 || typeof params.hostile != "boolean")
            return fail("spawnMerc", session.token, "invalid_payload");
        var unit:Object = _root.兵种库 == undefined ? undefined : _root.兵种库["兵种" + unitId];
        if (unit == undefined || unit == null || unit.兵种名 == undefined || unit.兵种名 == null || String(unit.兵种名) == "")
            return fail("spawnMerc", session.token, "unit_unavailable");
        var hero:Object = currentHero();
        if (hero == undefined) return fail("spawnMerc", session.token, "actor_unavailable");
        var pool:Array = _root.可雇佣兵;
        if (!(pool instanceof Array) || pool.length < 1) return fail("spawnMerc", session.token, "merc_pool_empty");
        if (typeof _root.加载游戏世界人物 != "function") return fail("spawnMerc", session.token, "spawn_unavailable");
        var index:Number = random(pool.length);
        var attempts:Number = 0;
        var occupied:Object = _root.已上场佣兵编号;
        if (occupied == undefined) occupied = {};
        while (occupied[index] != undefined && attempts < pool.length * 2) {
            index++;
            if (index >= pool.length) index = 0;
            attempts++;
        }
        var record:Array = pool[index];
        if (!(record instanceof Array)) return fail("spawnMerc", session.token, "merc_pool_invalid");
        _mercCounter++;
        var name:String = "佣兵" + index + _mercCounter;
        var spawned:Object = _root.加载游戏世界人物("佣兵npc", name, _root.gameworld.getNextHighestDepth(), {
            _x: hero._x, _y: hero._y, 佣兵库编号: index, 是否为敌人: params.hostile,
            脸型: unit.脸型, 发型: unit.发型, 头部装备: unit.头部装备, 上装装备: unit.上装装备,
            手部装备: unit.手部装备, 下装装备: unit.下装装备, 脚部装备: unit.脚部装备,
            颈部装备: unit.颈部装备, 长枪: unit.长枪, 手枪: unit.手枪, 手枪2: unit.手枪2,
            刀: unit.刀, 手雷: unit.手雷, 名字: unit.名字, 身高: unit.身高, 性别: unit.性别,
            等级: level
        });
        if (_root.gameworld[name] == undefined)
            return fail("spawnMerc", session.token, "spawn_failed");
        record[4] = unit.脸型;
        record[5] = unit.发型;
        record[6] = unit.头部装备;
        record[7] = unit.上装装备;
        record[8] = unit.手部装备;
        record[9] = unit.下装装备;
        record[10] = unit.脚部装备;
        record[11] = unit.颈部装备;
        record[12] = unit.长枪;
        record[13] = unit.手枪;
        record[14] = unit.手枪;
        record[15] = unit.刀;
        record[16] = "压缩胶囊之兽王";
        record[1] = unit.名字;
        record[2] = random(10000);
        record[3] = unit.身高;
        record[17] = unit.兵种名;
        record[0] = level;
        _root.gameworld[name].佣兵数据 = record;
        markDirty();
        return {v:1, operation:"spawnMerc", token:session.token, success:true,
            revision:Number(session.revision), operationId:operationId,
            message:"已生成佣兵并写入雇佣池（需保存）"};
    }

    private static function onPanelClosed():Void {
        var session:Object = _active;
        if (session == undefined) return;
        var action:Object = session.pendingAction;
        session.pendingAction = null;
        session.phase = "closed";
        _active = undefined;
        if (action == null) return;
        try {
            if (action.type == "finish_stage" && typeof _root.关卡结束 == "function") {
                _root.关卡结束();
            } else if (action.type == "test_space") {
                if (_root.关卡结束界面 != undefined) _root.关卡结束界面._visible = 0;
                _root.场景进入位置名 = "出生地";
                if (_root.淡出动画 != undefined && typeof _root.淡出动画.淡出跳转帧 == "function") {
                    _root.淡出动画.淡出跳转帧("地图-测试空间");
                }
            }
        } catch (closeActionError) {
            trace("[Modifier] pending close action failed: " + closeActionError);
        }
    }

    private static function retireActive():Void {
        if (_active != undefined) {
            if (_active.phase == "editing") _active.phase = "expired";
            _active = undefined;
        }
    }

    private static function sameContext(session:Object):Boolean {
        return session != undefined && session.saveOwner === _root.存档系统
            && session.slot === String(_root.savePath)
            && session.scene === String(_root.关卡标志);
    }

    private static function currentHero():Object {
        if (_root.gameworld == undefined) return undefined;
        var hero:Object = _root.gameworld[_root.控制目标];
        return hero == undefined ? undefined : hero;
    }

    private static function stageState():String {
        if (typeof _root.获取关卡状态 != "function") return "none";
        var state = _root.获取关卡状态();
        return state == undefined || state == null ? "none" : String(state);
    }

    private static function isChallengeMode():Boolean {
        return typeof _root.isChallengeMode == "function" && _root.isChallengeMode() === true;
    }

    private static function saveAvailable():Boolean {
        return _root.存档系统 != undefined;
    }

    private static function markDirty():Void {
        if (_root.存档系统 == undefined) return;
        if (typeof _root.存档系统.markDirty == "function") {
            _root.存档系统.markDirty();
        } else {
            _root.存档系统.dirtyMark = true;
        }
    }

    private static function itemCatalog():Array {
        var source:Array = _root.物品属性数组;
        if (!(source instanceof Array)) return [];
        var out:Array = [];
        for (var i:Number = 0; i < source.length; i++) {
            var projection:Object = itemProjection(source[i]);
            out.push(projection);
        }
        return out;
    }

    private static function itemProjection(data:Object):Object {
        if (data == undefined || data == null || typeof data.name != "string" || data.name == "") return null;
        var name:String = String(data.name);
        var display:String = typeof data.displayname == "string" ? trimText(data.displayname) : "";
        if (display == "" || display.toLowerCase() == "undefined") display = name;
        var icon:String = typeof data.icon == "string" ? trimText(data.icon) : "";
        if (icon == "" || icon.toLowerCase() == "undefined") icon = name;
        var type:String = typeof data.type == "string" ? String(data.type) : "";
        var use:String = typeof data.use == "string" ? String(data.use) : "";
        var id:Number = Number(data.id);
        if (isNaN(id) || !isFinite(id) || id < 0 || Math.floor(id) != id) return null;
        return {id:id, name:name, displayName:display, icon:icon, type:type, use:use};
    }

    private static function copyItem(item:Object):Object {
        return {id:Number(item.id), name:String(item.name), displayName:String(item.displayName),
            icon:String(item.icon), type:String(item.type), use:String(item.use)};
    }

    private static function itemMatches(item:Object, needle:String):Boolean {
        if (item == null) return false;
        if (String(item.id) == needle) return true;
        if (String(item.name).toLowerCase().indexOf(needle) > -1) return true;
        if (String(item.displayName).toLowerCase().indexOf(needle) > -1) return true;
        if (String(item.type).toLowerCase().indexOf(needle) > -1) return true;
        if (String(item.use).toLowerCase().indexOf(needle) > -1) return true;
        var data:Object = _root.物品属性列表 == undefined ? undefined : _root.物品属性列表[item.name];
        if (data != undefined && data != null) {
            if (typeof data.actiontype == "string" && data.actiontype.toLowerCase().indexOf(needle) > -1) return true;
            if (data.data != undefined && data.data != null && typeof data.data.clipname == "string"
                    && data.data.clipname.toLowerCase().indexOf(needle) > -1) return true;
        }
        return false;
    }

    private static function countItems():Number {
        var catalog:Array = itemCatalog();
        var count:Number = 0;
        for (var i:Number = 0; i < catalog.length; i++) if (catalog[i] != null) count++;
        return count;
    }

    private static function unitCatalog():Array {
        var source:Array = _root.units;
        if (!(source instanceof Array) || _root.兵种库 == undefined) return [];
        var out:Array = [];
        for (var i:Number = 0; i < source.length; i++) {
            var unit:Object = source[i];
            if (unit == undefined || unit == null) continue;
            var id:Number = Number(unit.id);
            if (isNaN(id) || !isFinite(id) || id < 0 || Math.floor(id) != id) continue;
            var attr:Object = _root.兵种库["兵种" + id];
            if (attr == undefined || attr == null || attr.兵种名 == undefined || attr.兵种名 == null || String(attr.兵种名) == "") continue;
            var name:String = typeof attr.名字 == "string" && trimText(attr.名字) != ""
                ? String(attr.名字) : (typeof unit.name == "string" ? String(unit.name) : "");
            var spriteName:String = String(attr.兵种名);
            var key:String = typeof unit.key == "string" ? String(unit.key) : "";
            var level:Number = Number(unit.level);
            if (isNaN(level) || level < 0) level = 0;
            out.push({id:id, name:name, spriteName:spriteName, key:key, level:Math.floor(level),
                hostile:attr.是否为敌人 === true || unit.is_hostile === true});
        }
        // 旧界面按兵种 id 分页；保持稳定顺序，同时不依赖 for...in 的枚举顺序。
        var sorted:Array = [];
        while (out.length > 0) {
            var smallest:Number = 0;
            for (var j:Number = 1; j < out.length; j++) {
                if (Number(out[j].id) < Number(out[smallest].id)) smallest = j;
            }
            sorted.push(out.splice(smallest, 1)[0]);
        }
        return sorted;
    }

    private static function copyUnit(unit:Object):Object {
        return {id:Number(unit.id), name:String(unit.name), spriteName:String(unit.spriteName),
            key:String(unit.key), level:Number(unit.level), hostile:unit.hostile === true};
    }

    private static function unitMatches(unit:Object, needle:String):Boolean {
        if (String(unit.id) == needle) return true;
        if (String(unit.name).toLowerCase().indexOf(needle) > -1) return true;
        if (String(unit.spriteName).toLowerCase().indexOf(needle) > -1) return true;
        if (String(unit.key).toLowerCase().indexOf(needle) > -1) return true;
        if (needle == "敌人" && unit.hostile) return true;
        if (needle == "友军" && !unit.hostile) return true;
        return false;
    }

    private static function countUnits():Number {
        return unitCatalog().length;
    }

    private static function validWriteFields(command:String, params:Object):Boolean {
        var allowed:Array = ["v", "token", "operationId", "expectedRevision", "task", "action", "callId"];
        if (command == "spawnItem") {
            allowed.push("itemName"); allowed.push("quantity");
        } else if (command == "levelAction") {
            allowed.push("levelAction");
        } else if (command == "grantTask") {
            allowed.push("taskId");
        } else if (command == "spawnUnit") {
            allowed.push("unitId"); allowed.push("count"); allowed.push("level"); allowed.push("hostile");
        } else if (command == "spawnMerc") {
            allowed.push("unitId"); allowed.push("level"); allowed.push("hostile");
        }
        return hasOnly(params, allowed);
    }

    private static function hasOnly(value:Object, allowed:Array):Boolean {
        for (var key:String in value) {
            var found:Boolean = false;
            for (var i:Number = 0; i < allowed.length; i++) {
                if (allowed[i] == key) found = true;
            }
            if (!found) return false;
        }
        return true;
    }

    private static function tokenOf(params:Object):String {
        return params != undefined && typeof params.token == "string" ? String(params.token) : "";
    }

    private static function validToken(value:String):Boolean {
        return value != undefined && value.length >= 12 && value.length <= 96
            && value.substring(0, 9) == "modifier." && safeId(value);
    }

    private static function validOperationId(value:String):Boolean {
        return value != undefined && value.length >= 4 && value.length <= 96 && safeId(value)
            && value.substring(0, 4) == "mod.";
    }

    private static function safeId(value:String):Boolean {
        if (value == undefined || value.length < 1 || value.length > 128) return false;
        for (var i:Number = 0; i < value.length; i++) {
            var code:Number = value.charCodeAt(i);
            if (code >= 48 && code <= 57) continue;
            if (code >= 65 && code <= 90) continue;
            if (code >= 97 && code <= 122) continue;
            if (code == 46 || code == 95 || code == 126 || code == 45) continue;
            return false;
        }
        return true;
    }

    private static function integerParam(value, min:Number, max:Number):Number {
        var number:Number = Number(value);
        if (isNaN(number) || !isFinite(number) || Math.floor(number) != number
                || number < min || number > max) return -1;
        return number;
    }

    private static function numberOrZero(value):Number {
        var number:Number = Number(value);
        if (isNaN(number) || !isFinite(number) || number < 0 || number > _maxSafe) return 0;
        return number;
    }

    private static function trimText(value):String {
        if (typeof value != "string") return "";
        var start:Number = 0;
        var end:Number = value.length - 1;
        while (start <= end && value.charCodeAt(start) <= 32) start++;
        while (end >= start && value.charCodeAt(end) <= 32) end--;
        return start > end ? "" : value.substring(start, end + 1);
    }

    private static function copyResult(source:Object):Object {
        var result:Object = {};
        for (var key:String in source) result[key] = source[key];
        return result;
    }

    private static function fail(operation:String, token:String, error:String):Object {
        return {v:1, operation:operation, token:token, success:false, error:error,
            revision:0, requiresReconcile:error == "apply_ambiguous"};
    }

    public static function _resetForTests():Void {
        _active = undefined;
        _sessions = {};
        _order = [];
        _spawnCounter = 0;
        _mercCounter = 0;
    }
}
