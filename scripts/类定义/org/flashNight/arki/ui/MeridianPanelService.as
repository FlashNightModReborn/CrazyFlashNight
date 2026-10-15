/**
 * 经脉系统 AS2 权威服务。
 *
 * 数据真源：data/meridians/meridians_config.json（经 MeridianDataLoader 非阻塞加载）。
 * 点亮状态：_root._saveExt.meridians = {v:1, nodes:{nodeId:true}}，走 ext 透传，不扩存档主体。
 * 收益预算：内力总预算取配置根级 innerPowerCap（缺省 DEFAULT_CAP），已点亮穴位的 innerPower
 *       累加后按预算截断，再经 _root.经脉内力加成 getter 汇入 DressupInitializer.updateProperties；
 *       预算不足时后续穴位直接拒绝贯注（bonus_cap_reached），改数据文件后重启（或 reload）即重算生效。
 *       与旧档健身内力的取大口径在 DressupInitializer，不在本服务。
 * 解锁顺序：脉内按序——同脉前一穴未点亮则本穴拒绝（order_locked）；八脉之间无先后。
 * 情报门槛：脉络级 requiredInfo 沿用（info_missing）；穴位级 node.requiredInfo 为接口位，
 *       当前配置不给值，命中时报 node_info_missing，日后按穴分情报只改数据文件。
 * 技能强化：本期只提供接口（node.skillMod 聚合 + getSkillModifier 查询），无现役消费方。
 * 持久写：点亮为内存原子事务（扣 K 点与写点亮集之间无中断窗口），随后单次 flush；
 *         未确认落盘时按 save_pending 语义上报，不盲目重放，重试由幂等结果缓存兜底。
 */
class org.flashNight.arki.ui.MeridianPanelService {
    /** 配置缺 innerPowerCap（或值非法）时的兜底预算：与 115 穴 × 1 点的现行数值一致。 */
    private static var DEFAULT_CAP:Number = 115;
    private static var _installed:Boolean = false;
    private static var _json:LiteJSON;
    private static var _config:Array = null;
    private static var _nodeIndex:Object = null;
    private static var _cap:Number = DEFAULT_CAP;
    private static var _loading:Boolean = false;
    private static var _pendingStateWaiters:Array = [];
    private static var _lightResults:Object = {};
    private static var _innerCache:Number = 0;
    private static var _innerRaw:Number = 0;
    private static var _innerDirty:Boolean = true;
    private static var _skillMods:Object = {};

    public static function install():Void {
        if (_installed) return;
        _installed = true;
        if (_root.gameCommands == undefined) _root.gameCommands = {};
        _root.gameCommands["meridiansState"] = function(params) {
            org.flashNight.arki.ui.MeridianPanelService.handleState(params);
        };
        _root.gameCommands["meridianLight"] = function(params) {
            org.flashNight.arki.ui.MeridianPanelService.handleLight(params);
        };
        // 内力 getter：任何写入路径都会拿到当前配置重算值；本服务之外不得对该属性赋值。
        _root.addProperty("经脉内力加成", function() {
            return org.flashNight.arki.ui.MeridianPanelService.getTotalInnerPower();
        });
        startConfigLoad();
    }

    // ========== 配置加载 ==========

    private static function startConfigLoad():Void {
        if (_loading || _config != null) return;
        _loading = true;
        org.flashNight.gesh.json.LoadJson.MeridianDataLoader.getInstance().load(
            org.flashNight.arki.ui.MeridianPanelService.onConfigLoaded,
            org.flashNight.arki.ui.MeridianPanelService.onConfigLoadFailed
        );
    }

    private static function onConfigLoaded(raw:Object):Void {
        _loading = false;
        _cap = readCap(raw == null ? null : raw.innerPowerCap);
        _config = sanitizeConfig(raw == null ? null : raw.meridians);
        _innerDirty = true;
        flushStateWaiters();
    }

    /** 预算非法（缺失、NaN、负数）时退回 DEFAULT_CAP，绝不当成 0 把已点亮的内力抹掉。 */
    private static function readCap(value:Object):Number {
        var cap:Number = Number(value);
        if (!isFinite(cap) || cap < 0) return DEFAULT_CAP;
        return cap;
    }

    private static function onConfigLoadFailed():Void {
        _loading = false;
        flushStateWaiters();
    }

    private static function flushStateWaiters():Void {
        var waiting:Array = _pendingStateWaiters;
        _pendingStateWaiters = [];
        for (var i:Number = 0; i < waiting.length; i++) {
            sendStateResult(waiting[i].callId, buildStateResult());
        }
    }

    /** 形参保持 Object：CS6 不把 Object 属性值隐式当 Array 传，下面用 instanceof 把关。 */
    private static function sanitizeConfig(raw:Object):Array {
        var result:Array = [];
        var index:Object = {};
        if (!(raw instanceof Array)) return result;
        for (var m:Number = 0; m < raw.length; m++) {
            var meridian:Object = raw[m];
            if (meridian == null || typeof meridian.id != "string" || meridian.id == "") continue;
            var cleanInfo:Array = cleanInfoList(meridian.requiredInfo);
            var cleanNodes:Array = [];
            var nodes:Array = meridian.nodes instanceof Array ? meridian.nodes : [];
            for (var n:Number = 0; n < nodes.length; n++) {
                var node:Object = nodes[n];
                if (node == null || typeof node.id != "string" || node.id == "") continue;
                if (index[node.id] != undefined) continue;
                var cost:Number = Number(node.cost);
                var innerPower:Number = Number(node.innerPower);
                if (!isFinite(cost) || cost < 0 || !isFinite(innerPower) || innerPower < 0) continue;
                var clean:Object = {
                    id:node.id,
                    name:typeof node.name == "string" ? node.name : node.id,
                    cost:cost,
                    innerPower:innerPower,
                    requiredInfo:cleanInfoList(node.requiredInfo)
                };
                // 技能强化接口位：skillMod 原样透传，由 getSkillModifier 聚合，本期无消费方。
                if (node.skillMod != null && typeof node.skillMod == "object") clean.skillMod = node.skillMod;
                index[node.id] = {meridianId:meridian.id, node:clean, order:cleanNodes.length};
                cleanNodes.push(clean);
            }
            result.push({
                id:meridian.id,
                name:typeof meridian.name == "string" ? meridian.name : meridian.id,
                desc:typeof meridian.desc == "string" ? meridian.desc : "",
                requiredInfo:cleanInfo,
                nodes:cleanNodes
            });
        }
        _nodeIndex = index;
        return result;
    }

    /** 情报名列表归一化：只保留非空字符串；缺省（未配置）即空数组 = 无额外情报门槛。 */
    private static function cleanInfoList(value:Object):Array {
        var clean:Array = [];
        if (!(value instanceof Array)) return clean;
        for (var i:Number = 0; i < value.length; i++) {
            if (typeof value[i] == "string" && value[i] != "") clean.push(value[i]);
        }
        return clean;
    }

    // ========== 点亮状态（存档 ext 透传） ==========

    private static function getLitNodes():Object {
        if (_root._saveExt == undefined) _root._saveExt = {};
        var stored:Object = _root._saveExt.meridians;
        if (stored == null || typeof stored != "object"
                || stored.nodes == null || typeof stored.nodes != "object") {
            stored = {v:1, nodes:{}};
            _root._saveExt.meridians = stored;
        }
        return stored.nodes;
    }

    private static function isLit(nodeId:String):Boolean {
        var lit:Object = getLitNodes();
        return lit[nodeId] === true || lit[nodeId] == "true";
    }

    // ========== 收益重算 ==========

    private static function recomputeBonuses():Void {
        var total:Number = 0;
        var mods:Object = {};
        if (_config != null) {
            var lit:Object = getLitNodes();
            for (var i:Number = 0; i < _config.length; i++) {
                var nodes:Array = _config[i].nodes;
                for (var n:Number = 0; n < nodes.length; n++) {
                    var node:Object = nodes[n];
                    if (lit[node.id] !== true && lit[node.id] != "true") continue;
                    total += node.innerPower;
                    var mod:Object = node.skillMod;
                    if (mod != null && typeof mod.skillName == "string" && mod.skillName != "") {
                        var acc:Object = mods[mod.skillName];
                        if (acc == null) {
                            acc = {damageAdd:0, cooldownReduce:0, mpCostReduce:0};
                            mods[mod.skillName] = acc;
                        }
                        var damageAdd:Number = Number(mod.damageAdd);
                        var cooldownReduce:Number = Number(mod.cooldownReduce);
                        var mpCostReduce:Number = Number(mod.mpCostReduce);
                        if (isFinite(damageAdd)) acc.damageAdd += damageAdd;
                        if (isFinite(cooldownReduce)) acc.cooldownReduce += cooldownReduce;
                        if (isFinite(mpCostReduce)) acc.mpCostReduce += mpCostReduce;
                    }
                }
            }
        }
        _innerRaw = total;
        _innerCache = total > _cap ? _cap : total;
        _skillMods = mods;
        _innerDirty = false;
    }

    public static function getTotalInnerPower():Number {
        if (_innerDirty) recomputeBonuses();
        return _innerCache;
    }

    /** 已点亮穴位的原始累加值（未截断）：预算门槛按它判定，避免截断值把后续穴位误放行。 */
    private static function getRawInnerPower():Number {
        if (_innerDirty) recomputeBonuses();
        return _innerRaw;
    }

    private static function getInnerPowerCap():Number {
        return _cap;
    }

    /**
     * 技能强化查询接口（预留）：返回某技能名经已点亮经脉聚合的修正量。
     * 本期配置不含 skillMod、战斗公式未接入；后续接线只改调用方。
     */
    public static function getSkillModifier(skillName:String):Object {
        if (skillName == undefined || skillName == "") return null;
        if (_innerDirty) recomputeBonuses();
        var mod:Object = _skillMods[skillName];
        return mod == null ? null : mod;
    }

    // ========== 命令处理 ==========

    public static function handleState(params:Object):Void {
        var callId:Number = readCallId(params);
        if (_config == null && !_loading) startConfigLoad();
        if (_config == null) {
            _pendingStateWaiters.push({callId:callId});
            return;
        }
        sendStateResult(callId, buildStateResult());
    }

    private static function sendStateResult(callId:Number, result:Object):Void {
        result.task = "meridians_response";
        result.callId = callId;
        result.operation = "state";
        send(result);
    }

    private static function buildStateResult():Object {
        if (_config == null) {
            return {success:false, v:1, error:"config_unavailable"};
        }
        var used:Number = getRawInnerPower();
        var remaining:Number = _cap - used;
        if (remaining < 0) remaining = 0;
        return {
            success:true, v:1,
            meridians:_config,
            lit:getLitNodes(),
            kpoint:Number(_root.虚拟币),
            infoValues:readInfoValues(),
            innerPowerCap:_cap,
            innerPowerUsed:used,
            innerPowerApplied:getTotalInnerPower(),
            innerPowerRemaining:remaining
        };
    }

    private static function readInfoValues():Object {
        var values:Object = {};
        if (_root.收集品栏 != undefined && _root.收集品栏.情报 != undefined
                && typeof _root.收集品栏.情报.toObject == "function") {
            var collected:Object = _root.收集品栏.情报.toObject();
            for (var name:String in collected) values[name] = Number(collected[name]);
        }
        return values;
    }

    public static function handleLight(params:Object):Void {
        var callId:Number = readCallId(params);
        var result:Object = executeLight(params == null ? null : String(params.nodeId));
        result.task = "meridians_response";
        result.callId = callId;
        result.operation = "light";
        send(result);
    }

    private static function executeLight(nodeId:String):Object {
        if (nodeId == undefined || nodeId == "") return failLight("invalid_payload");
        if (_config == null) {
            startConfigLoad();
            return failLight("config_unavailable");
        }
        var entry:Object = _nodeIndex != null ? _nodeIndex[nodeId] : null;
        if (entry == null) return failLight("node_unknown");
        var node:Object = entry.node;
        var cached:Object = _lightResults[nodeId];
        if (cached != null) return copyPending(cached, node);
        if (isLit(nodeId)) return failLight("already_lit");

        var missingInfo:Array = findMissingInfo(entry.meridianId);
        if (missingInfo.length > 0) {
            var blocked:Object = failLight("info_missing");
            blocked.missingInfo = missingInfo;
            return blocked;
        }

        // 脉内按序：前一穴未贯通则本穴不可贯注（八脉之间仍自由选择）。
        var blocker:Object = findOrderBlocker(entry.meridianId, entry.order);
        if (blocker != null) {
            var orderBlocked:Object = failLight("order_locked");
            orderBlocked.lockedBy = blocker.name;
            return orderBlocked;
        }

        // 穴位级情报门槛（接口位，现行配置不赋值）：与脉络级同样只拦不改数据。
        var nodeMissing:Array = findMissingValues(node.requiredInfo);
        if (nodeMissing.length > 0) {
            var nodeBlocked:Object = failLight("node_info_missing");
            nodeBlocked.missingInfo = nodeMissing;
            return nodeBlocked;
        }

        // 预算门槛：按原始累加值判定，超出上限的穴位不再可点。
        if (getRawInnerPower() + node.innerPower > _cap) return failLight("bonus_cap_reached");

        var balance:Number = Number(_root.虚拟币);
        if (!isFinite(balance)) return failLight("state_unavailable");
        if (balance < node.cost) return failLight("insufficient_funds");

        var saveOwner:Object = _root.存档系统;
        if (saveOwner == undefined || typeof saveOwner.markDirty != "function"
                || typeof saveOwner.flushDurableNow != "function") {
            return failLight("save_unavailable");
        }
        try { saveOwner.markDirty(); }
        catch (dirtyError) { return failLight("save_unavailable"); }

        // 内存原子事务：扣费与写点亮集之间没有可中断窗口。
        _root.虚拟币 = balance - node.cost;
        getLitNodes()[nodeId] = true;
        _innerDirty = true;
        var innerPower:Number = getTotalInnerPower();

        try {
            _root.记录玩家货币变化(0, -node.cost, {
                source:"meridian_light", reason:"node_lit",
                mergeScope:"operation", operationId:"meridian." + nodeId
            });
        } catch (feedError) { trace("[Meridian] currency feed failed after authority write"); }
        try {
            if (typeof _root.获取虚拟币值 == "function") _root.获取虚拟币值();
        } catch (balanceUiError) { trace("[Meridian] K-point display refresh failed"); }

        recomputeActor();

        var serial:Number = org.flashNight.neur.Server.SaveManager.getInstance().fullSaveSerial();
        var saved:Boolean = false;
        try {
            saved = saveOwner.flushDurableNow("ui.meridian_paid") === true;
        } catch (saveError) {
            saved = org.flashNight.neur.Server.SaveManager.getInstance()
                .fullSaveConfirmedAfter(serial, saveOwner, String(_root.savePath));
        }
        var used:Number = getRawInnerPower();
        var remaining:Number = _cap - used;
        if (remaining < 0) remaining = 0;
        var result:Object = {
            success:saved, v:1, applied:true, nodeId:nodeId,
            totalInnerPower:innerPower, kpoint:Number(_root.虚拟币),
            innerPowerCap:_cap, innerPowerUsed:used,
            innerPowerApplied:innerPower, innerPowerRemaining:remaining,
            savePending:!saved
        };
        if (!saved) result.error = "save_pending";
        _lightResults[nodeId] = result;
        return copyPending(result, node);
    }

    private static function copyPending(result:Object, node:Object):Object {
        return {
            success:result.success, v:1, applied:result.applied === true, nodeId:node.id,
            totalInnerPower:result.totalInnerPower, kpoint:result.kpoint,
            innerPowerCap:result.innerPowerCap, innerPowerUsed:result.innerPowerUsed,
            innerPowerApplied:result.innerPowerApplied, innerPowerRemaining:result.innerPowerRemaining,
            savePending:result.savePending === true,
            error:result.savePending === true ? "save_pending" : null
        };
    }

    /** 同脉前一穴是否已贯通；返回该穴（未贯通）或 null（可贯注）。首穴无前置。 */
    private static function findOrderBlocker(meridianId:String, order:Number):Object {
        if (!(order > 0)) return null;
        var meridian:Object = findMeridian(meridianId);
        if (meridian == null) return null;
        var previous:Object = meridian.nodes[order - 1];
        if (previous == null || isLit(previous.id)) return null;
        return previous;
    }

    private static function findMeridian(meridianId:String):Object {
        if (_config == null) return null;
        for (var i:Number = 0; i < _config.length; i++) {
            if (_config[i].id == meridianId) return _config[i];
        }
        return null;
    }

    private static function findMissingInfo(meridianId:String):Array {
        var meridian:Object = findMeridian(meridianId);
        if (meridian == null) return [];
        return findMissingValues(meridian.requiredInfo);
    }

    /** 情报清单里尚未持有的项（数量需 > 0）。 */
    private static function findMissingValues(required:Object):Array {
        var missing:Array = [];
        if (!(required instanceof Array)) return missing;
        var values:Object = readInfoValues();
        for (var r:Number = 0; r < required.length; r++) {
            var held:Number = Number(values[required[r]]);
            if (!(held > 0)) missing.push(required[r]);
        }
        return missing;
    }

    private static function recomputeActor():Void {
        try {
            var actor = _root.gameworld != undefined ? _root.gameworld[_root.控制目标] : undefined;
            if (actor != null && actor.hasDressup === true) {
                org.flashNight.arki.unit.UnitComponent.Initializer.DressupInitializer.updateProperties(actor);
            }
        } catch (refreshError) { trace("[Meridian] actor recompute failed"); }
    }

    private static function failLight(errorCode:String):Object {
        return {success:false, v:1, error:errorCode, savePending:false};
    }

    private static function readCallId(params:Object):Number {
        var callId:Number = params == null ? NaN : Number(params.callId);
        return !isNaN(callId) && isFinite(callId) ? callId : 0;
    }

    private static function send(result:Object):Void {
        if (_json == undefined) _json = new LiteJSON();
        if (_root.server != undefined && typeof _root.server.sendSocketMessage == "function") {
            _root.server.sendSocketMessage(_json.stringifySafe(result));
        }
    }
}
