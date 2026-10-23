/**
 * 经脉系统 AS2 权威服务。
 *
 * 数据真源：data/meridians/meridians_config.json（经 MeridianDataLoader 非阻塞加载）。
 * 点亮状态：_root._saveExt.meridians = {v:1, nodes:{nodeId:true}}，走 ext 透传，不扩存档主体。
 * 收益预算：内力只转移了健身房原上限的一半（100→50），另一侧 HP/MP 上限与防御各让出一半
 *       （2000→1000、2000→1000、1000→500）改由穴位发放，故预算分四类，各自独立封顶，
 *       根级 bonusCaps = {innerPower, hp, mp, defense}（缺省 DEFAULT_CAPS）。
 *       每穴按 bonusType 记账：累加原始值用于门槛判定，截断值经 _root 的四个 getter
 *       （经脉内力加成/经脉HP加成/经脉MP加成/经脉防御加成）汇入 DressupInitializer.updateProperties；
 *       该类型预算已满时后续同类型穴位直接拒绝贯注（bonus_cap_reached），改数据文件后重启（或 reload）即重算生效。
 *       与旧档健身内力的取大口径在 DressupInitializer，不在本服务。
 * 解锁顺序：脉内按序——同脉前一穴未点亮则本穴拒绝（order_locked）；八脉之间无先后。
 * 情报门槛：脉络级 requiredInfo 沿用（info_missing）；穴位级 node.requiredInfo 为接口位，
 *       当前配置不给值，命中时报 node_info_missing，日后按穴分情报只改数据文件。
 * 技能强化：本期只提供接口（node.skillMod 聚合 + getSkillModifier 查询），无现役消费方。
 * 持久写：点亮为内存原子事务（扣 K 点与写点亮集之间无中断窗口），随后单次 flush；
 *         未确认落盘时按 save_pending 语义上报，不盲目重放，重试由幂等结果缓存兜底。
 */
class org.flashNight.arki.ui.MeridianPanelService {
    /** 四类收益的判定顺序；同时用作配置缺字段时的兜底预算键表。 */
    public static var BONUS_TYPES:Array = ["innerPower", "hp", "mp", "defense"];
    private static var DEFAULT_CAPS:Object = {innerPower:50, hp:1000, mp:1000, defense:500};
    private static var _installed:Boolean = false;
    private static var _json:LiteJSON;
    private static var _config:Array = null;
    private static var _nodeIndex:Object = null;
    // 静态字段初始化只写字面量：AVM1 里在初始化表达式中调用静态方法的时序不可靠。
    private static var _caps:Object = {innerPower:50, hp:1000, mp:1000, defense:500};
    private static var _loading:Boolean = false;
    private static var _pendingStateWaiters:Array = [];
    private static var _lightResults:Object = {};
    private static var _cache:Object = {innerPower:0, hp:0, mp:0, defense:0};
    private static var _raw:Object = {innerPower:0, hp:0, mp:0, defense:0};
    private static var _dirty:Boolean = true;
    private static var _skillMods:Object = {};
    private static var _contextOwner:Object;
    private static var _contextSlot:String;
    private static var _contextExt:Object;
    private static var _contextToken:Object;
    private static var _contextStatToken:Object;

    /** 只在角色权威替换时调用；普通保存不清配置，也不清其他领域回执。 */
    public static function resetContext():Void {
        _contextOwner = undefined;
        _contextSlot = undefined;
        _contextExt = undefined;
        _contextToken = {};
        _contextStatToken = undefined;
        clearContextCache();
    }

    private static function clearContextCache():Void {
        _lightResults = {};
        _cache = {innerPower:0, hp:0, mp:0, defense:0};
        _raw = {innerPower:0, hp:0, mp:0, defense:0};
        _skillMods = {};
        _dirty = true;
    }

    private static function ensureContext():Void {
        if (_root._saveExt == undefined) _root._saveExt = {};
        var owner:Object = _root.存档系统;
        var slot:String = String(_root.savePath);
        var ext:Object = _root._saveExt;
        var statToken:Object = org.flashNight.arki.unit.PlayerStatRefreshCoordinator.production().contextToken();
        if (_contextToken != undefined && _contextOwner === owner
                && _contextSlot === slot && _contextStatToken === statToken) {
            // 同一角色的奖励事务会克隆整个 ext；重读收益，但不能丢失该角色的精确保存回执。
            if (_contextExt !== ext) {_contextExt=ext;_dirty=true;}
            return;
        }
        clearContextCache();
        _contextOwner = owner;
        _contextSlot = slot;
        _contextExt = ext;
        _contextToken = {};
        _contextStatToken = statToken;
    }

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
        // AVM1 addProperty 必须显式传 null setter，否则注册返回 false。只读收益始终按当前上下文重算。
        _root.addProperty("经脉内力加成", function() {
            return org.flashNight.arki.ui.MeridianPanelService.getBonus("innerPower");
        }, null);
        _root.addProperty("经脉HP加成", function() {
            return org.flashNight.arki.ui.MeridianPanelService.getBonus("hp");
        }, null);
        _root.addProperty("经脉MP加成", function() {
            return org.flashNight.arki.ui.MeridianPanelService.getBonus("mp");
        }, null);
        _root.addProperty("经脉防御加成", function() {
            return org.flashNight.arki.ui.MeridianPanelService.getBonus("defense");
        }, null);
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
        _caps = readCaps(raw == null ? null : raw.bonusCaps);
        _config = sanitizeConfig(raw == null ? null : raw.meridians);
        _dirty = true;
        // 配置是共享只读数据；只有已在等待的当前角色可声明自己的活体失效。
        if(_contextToken!=undefined && _contextOwner===_root.存档系统 && _contextSlot===String(_root.savePath)
                && _contextStatToken===org.flashNight.arki.unit.PlayerStatRefreshCoordinator.production().contextToken()) recomputeActor("config");
        flushStateWaiters();
    }

    /** 预算非法（缺失、NaN、负数）时逐项退回 DEFAULT_CAPS，绝不当成 0 把已点亮的加成抹掉。 */
    private static function readCaps(value:Object):Object {
        var caps:Object = copyCaps(DEFAULT_CAPS);
        if (value == null || typeof value != "object") return caps;
        for (var i:Number = 0; i < BONUS_TYPES.length; i++) {
            var key:String = BONUS_TYPES[i];
            var cap:Number = Number(value[key]);
            if (isFinite(cap) && cap >= 0) caps[key] = cap;
        }
        return caps;
    }

    private static function copyCaps(source:Object):Object {
        return {
            innerPower:source.innerPower, hp:source.hp,
            mp:source.mp, defense:source.defense
        };
    }

    private static function isBonusType(value:Object):Boolean {
        if (typeof value != "string") return false;
        for (var i:Number = 0; i < BONUS_TYPES.length; i++) {
            if (BONUS_TYPES[i] == value) return true;
        }
        return false;
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
                if (!isFinite(cost) || cost < 0) continue;
                // 收益类型：新配置走 bonusType/bonusAmount；旧配置的 innerPower 视作内力，
                // 这样只改数据文件也能平滑过渡，不会因为字段换代就静默丢掉整条脉的穴位。
                var bonusType:String = isBonusType(node.bonusType) ? String(node.bonusType) : "";
                var bonusAmount:Number = Number(node.bonusAmount);
                if (bonusType == "" && node.innerPower != undefined) {
                    bonusType = "innerPower";
                    bonusAmount = Number(node.innerPower);
                }
                if (bonusType == "" || !isFinite(bonusAmount) || bonusAmount < 0) continue;
                var clean:Object = {
                    id:node.id,
                    name:typeof node.name == "string" ? node.name : node.id,
                    cost:cost,
                    bonusType:bonusType,
                    bonusAmount:bonusAmount,
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
        ensureContext();
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
        var raw:Object = {innerPower:0, hp:0, mp:0, defense:0};
        var mods:Object = {};
        if (_config != null) {
            var lit:Object = getLitNodes();
            for (var i:Number = 0; i < _config.length; i++) {
                var nodes:Array = _config[i].nodes;
                for (var n:Number = 0; n < nodes.length; n++) {
                    var node:Object = nodes[n];
                    if (lit[node.id] !== true && lit[node.id] != "true") continue;
                    raw[node.bonusType] += node.bonusAmount;
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
        _raw = raw;
        _cache = {innerPower:0, hp:0, mp:0, defense:0};
        for (var t:Number = 0; t < BONUS_TYPES.length; t++) {
            var key:String = BONUS_TYPES[t];
            // 各类型独立截断：内力只搬来原上限的一半，HP/MP/防御搬来让出的那一半，互不挪用。
            _cache[key] = raw[key] > _caps[key] ? _caps[key] : raw[key];
        }
        _skillMods = mods;
        _dirty = false;
    }

    /** 实际发放值（已按该类型预算截断），供 _root 的四个经脉加成 getter 读取。 */
    public static function getBonus(bonusType:String):Number {
        ensureContext();
        if (_dirty) recomputeBonuses();
        if (!isBonusType(bonusType)) return 0;
        return _cache[bonusType];
    }

    /** 原始累加值（未截断）：预算门槛按它判定，避免截断值把后续穴位误放行。 */
    private static function getRawBonus(bonusType:String):Number {
        ensureContext();
        if (_dirty) recomputeBonuses();
        if (!isBonusType(bonusType)) return 0;
        return _raw[bonusType];
    }

    private static function getCap(bonusType:String):Number {
        if (!isBonusType(bonusType)) return 0;
        return _caps[bonusType];
    }

    /** 四类预算快照：state 与 light 结果都挂它，面板只需读一份口径。 */
    private static function buildBonusSnapshot():Object {
        ensureContext();
        if (_dirty) recomputeBonuses();
        var caps:Object = {};
        var used:Object = {};
        var applied:Object = {};
        var remaining:Object = {};
        for (var t:Number = 0; t < BONUS_TYPES.length; t++) {
            var key:String = BONUS_TYPES[t];
            caps[key] = _caps[key];
            used[key] = _raw[key];
            applied[key] = _cache[key];
            var left:Number = _caps[key] - _raw[key];
            remaining[key] = left < 0 ? 0 : left;
        }
        return {bonusCaps:caps, bonusUsed:used, bonusApplied:applied, bonusRemaining:remaining};
    }

    /**
     * 技能强化查询接口（预留）：返回某技能名经已点亮经脉聚合的修正量。
     * 本期配置不含 skillMod、战斗公式未接入；后续接线只改调用方。
     */
    public static function getSkillModifier(skillName:String):Object {
        ensureContext();
        if (skillName == undefined || skillName == "") return null;
        if (_dirty) recomputeBonuses();
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
        var result:Object = {
            success:true, v:1,
            meridians:_config,
            lit:getLitNodes(),
            kpoint:Number(_root.虚拟币),
            infoValues:readInfoValues()
        };
        return attachBonuses(result);
    }

    /** 四类预算快照逐字段挂到结果上（AS2 无展开语法）；面板只读这一份口径。 */
    private static function attachBonuses(result:Object):Object {
        var snapshot:Object = buildBonusSnapshot();
        result.bonusCaps = snapshot.bonusCaps;
        result.bonusUsed = snapshot.bonusUsed;
        result.bonusApplied = snapshot.bonusApplied;
        result.bonusRemaining = snapshot.bonusRemaining;
        // 节点事实、保存结果和现场投影分别上报；读取只续可重试的数值尾部。
        result.projection = projectionStatus();
        return result;
    }

    private static function projectionStatus():Object {
        try {
            var p:Object=org.flashNight.arki.unit.PlayerStatRefreshCoordinator.production().flush("meridian_read");
            return {status:String(p.status),reason:String(p.reason==undefined ? "" : p.reason).substr(0,160)};
        } catch(error) {return {status:"failed",reason:"projection_exception"};}
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
        ensureContext();
        var context:Object = _contextToken;
        if (nodeId == undefined || nodeId == "") return failLight("invalid_payload");
        if (_config == null) {
            startConfigLoad();
            return failLight("config_unavailable");
        }
        var entry:Object = _nodeIndex != null ? _nodeIndex[nodeId] : null;
        if (entry == null) return failLight("node_unknown");
        var node:Object = entry.node;
        var cached:Object = _lightResults[nodeId];
        if (cached != null) {
            retryPendingSave(cached);
            ensureContext();
            if (_contextToken !== context) return failLight("context_changed");
            return copyPending(cached, node);
        }
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

        // 预算门槛：按该穴自身收益类型的原始累加值判定，该类预算已满则不再可点。
        if (getRawBonus(node.bonusType) + node.bonusAmount > getCap(node.bonusType)) {
            var capped:Object = failLight("bonus_cap_reached");
            capped.bonusType = node.bonusType;
            return capped;
        }

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
        ensureContext();
        if (_contextToken !== context) return failLight("context_changed");

        // 内存原子事务：扣费与写点亮集之间没有可中断窗口。
        _root.虚拟币 = balance - node.cost;
        getLitNodes()[nodeId] = true;
        _dirty = true;

        try {
            _root.记录玩家货币变化(0, -node.cost, {
                source:"meridian_light", reason:"node_lit",
                mergeScope:"operation", operationId:"meridian." + nodeId
            });
        } catch (feedError) { trace("[Meridian] currency feed failed after authority write"); }
        try {
            if (typeof _root.获取虚拟币值 == "function") _root.获取虚拟币值();
        } catch (balanceUiError) { trace("[Meridian] K-point display refresh failed"); }

        ensureContext();
        if (_contextToken !== context) return failLight("context_changed");
        recomputeActor();

        var serial:Number = org.flashNight.neur.Server.SaveManager.getInstance().fullSaveSerial();
        var saved:Boolean = false;
        try {
            saved = saveOwner.flushDurableNow("ui.meridian_paid") === true;
        } catch (saveError) {
            saved = org.flashNight.neur.Server.SaveManager.getInstance()
                .fullSaveConfirmedAfter(serial, saveOwner, _contextSlot);
        }
        ensureContext();
        if (_contextToken !== context) return failLight("context_changed");
        var result:Object = attachBonuses({
            success:saved, v:1, applied:true, nodeId:nodeId,
            bonusType:node.bonusType, bonusAmount:node.bonusAmount,
            kpoint:Number(_root.虚拟币), savePending:!saved
        });
        if (!saved) result.error = "save_pending";
        _lightResults[nodeId] = result;
        return copyPending(result, node);
    }

    /** 同一操作的恢复仅重试保存；不重跑扣费、节点写入或数值投影。 */
    private static function retryPendingSave(result:Object):Void {
        if (result.savePending !== true) return;
        var context:Object = _contextToken;
        var owner:Object = _contextOwner;
        var slot:String = _contextSlot;
        var manager = org.flashNight.neur.Server.SaveManager.getInstance();
        if (!manager.settingsWriteAllowed() || typeof owner.flushDurableNow != "function") return;
        var serial:Number = manager.fullSaveSerial();
        var saved:Boolean = false;
        try { saved = owner.flushDurableNow("ui.meridian_paid") === true; }
        catch (saveError) { saved = manager.fullSaveConfirmedAfter(serial, owner, slot); }
        ensureContext();
        if (_contextToken !== context || !saved) return;
        result.success = true;
        result.savePending = false;
        result.error = null;
    }

    /** 幂等重放：只回传本穴身份与当前预算快照，不缓存过期的累加值。 */
    private static function copyPending(result:Object, node:Object):Object {
        return attachBonuses({
            success:result.success, v:1, applied:result.applied === true, nodeId:node.id,
            bonusType:node.bonusType, bonusAmount:node.bonusAmount,
            kpoint:Number(_root.虚拟币),
            savePending:result.savePending === true,
            error:result.savePending === true ? "save_pending" : null
        });
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

    private static function recomputeActor(reason:String):Void {
        try {
            var c:org.flashNight.arki.unit.PlayerStatRefreshCoordinator=org.flashNight.arki.unit.PlayerStatRefreshCoordinator.production();
            c.invalidate(1,reason=="config" ? "config" : "meridian",c.contextToken());
            c.flush("meridian");
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
