import org.flashNight.arki.ui.GymPreviewProjection;

/** 健身训练的 AS2 权威会话。未完成时只保留内存状态；完成时一次性扣费、发奖并严格保存。 */
class org.flashNight.arki.ui.GymTrainingPanelService {
    private static var _installed:Boolean = false;
    private static var _sequence:Number = 0;
    private static var _open:Object = null;
    private static var _session:Object = null;
    private static var _last:Object = null;
    private static var _json:LiteJSON;
    private static var _testNow:Number = -1;
    private static var MAX_SAFE_INTEGER:Number = 9007199254740991;

    public static function install():Void {
        if (_installed) return;
        _installed = true;
        if (_root.gameCommands == undefined) _root.gameCommands = {};
        _root.gameCommands["gymStart"] = function(params) { org.flashNight.arki.ui.GymTrainingPanelService.handle("start", params); };
        _root.gameCommands["gymCancel"] = function(params) { org.flashNight.arki.ui.GymTrainingPanelService.handle("cancel", params); };
        _root.gameCommands["gymFinish"] = function(params) { org.flashNight.arki.ui.GymTrainingPanelService.handle("finish", params); };
        _root.gameCommands["gymQuery"] = function(params) { org.flashNight.arki.ui.GymTrainingPanelService.handle("query", params); };
        _root.gameCommands["gymRetrySave"] = function(params) { org.flashNight.arki.ui.GymTrainingPanelService.handle("retrySave", params); };
    }

    public static function prepareOpen(stationId:String):Object {
        var pending:Boolean = _session != null && _session.phase == "save_pending";
        if (pending && !sameSaveContext()) return fail("open", "context_changed", null);
        // 完成后的待保存结果属于原器材；别的器材入口也回到该结果，避免玩家失去重试入口。
        var effectiveStation:String = pending ? _session.stationId : stationId;
        var preview:Object = GymPreviewProjection.buildPreview(effectiveStation);
        if (preview == null || preview.error != undefined) return preview;
        if (_session != null && _session.phase == "running") retireRunning();
        var token:String = "gym.open." + now() + "." + (++_sequence);
        _open = {
            token:token, stationId:effectiveStation, world:_root.gameworld,
            actor:_root.gameworld[_root.控制目标], actorKey:String(_root.控制目标),
            saveOwner:_root.存档系统, slotKey:String(_root.savePath),
            sceneEpoch:org.flashNight.arki.map.MapDomainBridge.getSceneEpoch(),
            sceneStamp:sceneStamp()
        };
        preview.v = 2;
        preview.openToken = token;
        preview.pendingSession = pending ? {
            sessionToken:_session.token, stationId:_session.stationId,
            projectId:_session.projectId, phase:"save_pending"
        } : null;
        for (var i:Number = 0; i < preview.projects.length; i++) {
            var project:Object = preview.projects[i];
            project.baseExperience = project.cap == null ? 0 : 10000;
            project.capExperience = project.cap == null ? 0 : 50000;
        }
        return preview;
    }

    public static function retireOpen(token:String):Void {
        if (_open != null && _open.token === token) _open = null;
    }

    public static function handle(operation:String, params:Object):Void {
        var result:Object = execute(operation, params);
        result.task = "gym_training_response";
        var callId:Number = params == null ? NaN : Number(params.callId);
        result.callId = !isNaN(callId) && isFinite(callId) ? callId : 0;
        if (_json == undefined) _json = new LiteJSON();
        if (_root.server != undefined && typeof _root.server.sendSocketMessage == "function") {
            _root.server.sendSocketMessage(_json.stringifySafe(result));
        }
    }

    public static function execute(operation:String, params:Object):Object {
        if (operation != "start" && operation != "cancel" && operation != "finish"
                && operation != "query" && operation != "retrySave") return fail(operation, "unsupported_cmd", params);
        if (params == null || params.v !== 1) return fail(operation, "unsupported_version", params);
        if (operation == "start") return start(params);
        if (typeof params.sessionToken != "string" || params.sessionToken == "") {
            return fail(operation, "invalid_payload", params);
        }
        if (_last != null && params.sessionToken === _last.sessionToken) {
            return copyResult(_last, operation);
        }
        if (_session == null || params.sessionToken !== _session.token) {
            return fail(operation, "stale_token", params);
        }
        if (operation == "query") return query();
        if (operation == "cancel") return cancel();
        if (operation == "retrySave") return retrySave();
        return finish();
    }

    private static function start(params:Object):Object {
        if (typeof params.openToken != "string" || typeof params.stationId != "string"
                || typeof params.projectId != "string") return fail("start", "invalid_payload", params);
        if (_open == null || params.openToken !== _open.token
                || params.stationId !== _open.stationId) return fail("start", "stale_open", params);
        if (_session != null && _session.phase == "save_pending") return fail("start", "save_pending", params);
        if (_session != null && _session.phase == "running") {
            if (_session.openToken === params.openToken && _session.projectId === params.projectId) {
                return resultFor(_session, "start");
            }
            return fail("start", "already_running", params);
        }
        if (!sameOpenContext()) return fail("start", "context_changed", params);
        if (!saveAvailable()) return fail("start", "save_unavailable", params);
        var project:Object = currentProject(params.stationId, params.projectId);
        if (project == null) return fail("start", "project_unavailable", params);
        var balance:Number = project.currency == "money" ? Number(_root.金钱) : Number(_root.虚拟币);
        if (balance < project.cost) return fail("start", "insufficient_funds", params);
        if (project.cap != null && project.current >= project.cap && project.capExperience <= 0) {
            return fail("start", "at_cap", params);
        }
        var award:Object = makeAward(project);
        if (award == null) return fail("start", "invalid_award", params);
        _session = {
            token:"gym.session." + now() + "." + (++_sequence),
            openToken:_open.token, stationId:_open.stationId, projectId:project.id,
            world:_open.world, actor:_open.actor, actorKey:_open.actorKey,
            saveOwner:_open.saveOwner, slotKey:_open.slotKey,
            sceneEpoch:_open.sceneEpoch, sceneStamp:_open.sceneStamp,
            project:copyProject(project), phase:"running", startMs:now(),
            durationMs:project.durationMs, award:award
        };
        return resultFor(_session, "start");
    }

    private static function query():Object {
        if (_session.phase == "running" && !sameSessionContext()) retireRunning();
        return resultFor(_session, "query");
    }

    private static function cancel():Object {
        if (_session.phase == "save_pending") return fail("cancel", "save_pending", {sessionToken:_session.token});
        if (_session.phase == "running") retireRunning();
        return resultFor(_session, "cancel");
    }

    private static function finish():Object {
        if (_session.phase == "save_pending") return resultFor(_session, "finish");
        if (_session.phase != "running") return resultFor(_session, "finish");
        if (!sameSessionContext()) { retireRunning(); return resultFor(_session, "finish"); }
        var elapsed:Number = now() - _session.startMs;
        if (elapsed < 0 || elapsed < _session.durationMs) {
            return fail("finish", "not_ready", {sessionToken:_session.token});
        }
        if (!saveAvailable()) {
            retireRunning();
            return fail("finish", "save_unavailable", {sessionToken:_session.token});
        }
        var current:Object = currentProject(_session.stationId, _session.projectId);
        if (current == null || !sameProjectTerms(current, _session.project)) {
            retireRunning();
            return fail("finish", "stale_project", {sessionToken:_session.token});
        }
        var award:Object = makeAward(current);
        if (award == null) {
            retireRunning();
            return fail("finish", "invalid_award", {sessionToken:_session.token});
        }
        var balance:Number = current.currency == "money" ? Number(_root.金钱) : Number(_root.虚拟币);
        if (balance < current.cost) {
            retireRunning();
            return fail("finish", "insufficient_funds", {sessionToken:_session.token});
        }
        var experienceBefore:Number = Number(_root.经验值);
        var skillBefore:Number = Number(_root.技能点数);
        if (!nonnegativeInteger(experienceBefore) || !nonnegativeInteger(skillBefore)
                || experienceBefore + award.baseExperience + award.capExperience > MAX_SAFE_INTEGER
                || skillBefore + (award.kind == "skillPoints" ? award.amount : 0) > MAX_SAFE_INTEGER) {
            retireRunning();
            return fail("finish", "state_unavailable", {sessionToken:_session.token});
        }
        var growth:Object = {level:Number(_root.等级), skillPoints:0};
        if (award.baseExperience + award.capExperience > 0) {
            growth = planLevelGrowth(experienceBefore + award.baseExperience + award.capExperience);
        }
        if (growth == null || skillBefore + growth.skillPoints
                + (award.kind == "skillPoints" ? award.amount : 0) > MAX_SAFE_INTEGER
                || !nonnegativeInteger(growth.level) || growth.level < 1
                || (growth.level > Number(_root.等级) && (!nonnegativeInteger(_root.基础身价值)
                    || Number(_root.基础身价值) * growth.level > MAX_SAFE_INTEGER))) {
            retireRunning();
            return fail("finish", "state_unavailable", {sessionToken:_session.token});
        }
        try { _root.存档系统.markDirty(); }
        catch (dirtyError) {
            retireRunning();
            return fail("finish", "save_unavailable", {sessionToken:_session.token});
        }

        _session.phase = "save_pending";
        _session.award = award;
        _session.levelBefore = Number(_root.等级);
        if (current.currency == "money") _root.金钱 = balance - current.cost;
        else _root.虚拟币 = balance - current.cost;
        if (award.kind == "stat") _root[current.attributeName] = current.current + award.amount;
        if (award.kind == "skillPoints") _root.技能点数 = skillBefore + award.amount;
        _root.经验值 = experienceBefore + award.baseExperience + award.capExperience;
        _root.等级 = growth.level;
        _root.技能点数 = Number(_root.技能点数) + growth.skillPoints;
        if (growth.level > _session.levelBefore) {
            _root.身价 = Number(_root.基础身价值) * growth.level;
        }
        _session.applied = {
            balances:{money:Number(_root.金钱), kpoint:Number(_root.虚拟币)},
            current:award.kind == "stat" ? Number(_root[current.attributeName]) : Number(_root.技能点数),
            cap:current.cap, experience:Number(_root.经验值), skillPoints:Number(_root.技能点数),
            level:Number(_root.等级), award:copyAward(award)
        };
        try {
            _root.记录玩家货币变化(current.currency == "money" ? -current.cost : 0,
                current.currency == "kpoint" ? -current.cost : 0,
                {source:"gym_training", reason:"training_complete", mergeScope:"operation", operationId:_session.token});
        } catch (feedError) { trace("[GymTraining] currency feed failed after authority write"); }
        try {
            if (current.currency == "kpoint" && typeof _root.获取虚拟币值 == "function") _root.获取虚拟币值();
        } catch (balanceUiError) { trace("[GymTraining] K-point display refresh failed"); }
        return savePrepared("finish");
    }

    private static function retrySave():Object {
        if (_session.phase != "save_pending") return fail("retrySave", "not_pending", {sessionToken:_session.token});
        return savePrepared("retrySave");
    }

    private static function savePrepared(operation:String):Object {
        if (!sameSaveContext()) return fail(operation, "context_changed", {sessionToken:_session.token});
        var saved:Boolean = false;
        try { saved = _root.存档系统.flushDurableNow("ui.gym_training_paid") === true; }
        catch (saveError) { trace("[GymTraining] durable save pending"); }
        if (saved) {
            _session.phase = "applied";
            projectSavedState(_session);
        }
        var response:Object = resultFor(_session, operation);
        if (saved) {
            _last = copyResult(response, "finish");
            _session = null;
        }
        return response;
    }

    private static function projectSavedState(session:Object):Void {
        try {
            if (session.applied.level > session.levelBefore
                    && typeof _root.投影已提交任务成长 == "function") {
                _root.投影已提交任务成长(session.levelBefore);
            } else {
                // 完成保存后，同场景的普通属性训练立即重算当前角色；升级已走成长投影。
                if (session.award.kind == "stat" && sameSessionContext()) {
                    var actor:MovieClip = session.actor;
                    if (actor != null && actor.hasDressup === true
                            && typeof actor.根据模式重新读取武器加成 == "function") {
                        var oldHp:Number = Number(actor.hp);
                        var oldMaxHp:Number = Number(actor.hp满血值);
                        var oldMp:Number = Number(actor.mp);
                        org.flashNight.arki.unit.UnitComponent.Initializer.DressupInitializer.updateProperties(actor);
                        actor.hp = org.flashNight.arki.unit.Action.Regeneration.HealApplier.settleHpAfterMaxChange(
                            oldHp, oldMaxHp, Number(actor.hp满血值));
                        actor.mp = org.flashNight.arki.unit.Action.Regeneration.HealApplier.settleMpAfterMaxChange(
                            oldMp, Number(actor.mp满血值));
                        org.flashNight.arki.component.StatHandler.ImpactHandler.refreshImpactDerived(actor);
                        if (_root.玩家信息界面 != undefined) {
                            if (typeof _root.玩家信息界面.刷新hp显示 == "function")
                                _root.玩家信息界面.刷新hp显示();
                            if (typeof _root.玩家信息界面.刷新mp显示 == "function")
                                _root.玩家信息界面.刷新mp显示();
                        }
                    }
                }
                if (session.award.baseExperience + session.award.capExperience > 0
                        && _root.玩家信息界面 != undefined
                        && typeof _root.玩家信息界面.刷新经验值显示 == "function") {
                    _root.玩家信息界面.刷新经验值显示();
                }
            }
        } catch (displayError) { trace("[GymTraining] saved result display refresh failed"); }
    }

    private static function resultFor(session:Object, operation:String):Object {
        if (session == null) return fail(operation, "stale_token", null);
        var applied:Object = session.applied;
        var project:Object = session.project;
        var current:Number = applied != null ? applied.current : Number(_root[project.attributeName]);
        if (project.attributeName == "技能点数" && applied == null) current = Number(_root.技能点数);
        var balances:Object = applied != null ? applied.balances
            : {money:Number(_root.金钱), kpoint:Number(_root.虚拟币)};
        var phase:String = session.phase;
        return {
            success:phase != "save_pending", v:1, operation:operation,
            error:phase == "save_pending" ? "save_pending" : null,
            openToken:session.openToken, sessionToken:session.token,
            stationId:session.stationId, projectId:session.projectId,
            phase:phase, saved:phase == "applied", durationMs:session.durationMs,
            award:copyAward(applied != null ? applied.award : session.award),
            balances:{money:Number(balances.money), kpoint:Number(balances.kpoint)},
            current:current, cap:project.cap,
            experience:applied != null ? applied.experience : Number(_root.经验值),
            skillPoints:applied != null ? applied.skillPoints : Number(_root.技能点数),
            level:applied != null ? applied.level : Number(_root.等级)
        };
    }

    private static function makeAward(project:Object):Object {
        if (project.cap == null) return {kind:"skillPoints", amount:project.rewardAmount,
            baseExperience:0, capExperience:0};
        if (project.current >= project.cap) return {kind:"experience", amount:50000,
            baseExperience:10000, capExperience:50000};
        return {kind:"stat", amount:Math.min(project.rewardAmount, project.cap - project.current),
            baseExperience:10000, capExperience:0};
    }

    private static function currentProject(stationId:String, projectId:String):Object {
        var preview:Object = GymPreviewProjection.buildPreview(stationId);
        if (preview == null || preview.error != undefined) return null;
        for (var i:Number = 0; i < preview.projects.length; i++) {
            var project:Object = preview.projects[i];
            if (project.id == projectId) {
                var index:Number = Number(project.index);
                var attributeName:String = sourceAttributeFor(stationId, index);
                if (attributeName == "") return null;
                project.attributeName = attributeName;
                project.baseExperience = project.cap == null ? 0 : 10000;
                project.capExperience = project.cap == null ? 0 : 50000;
                return project;
            }
        }
        return null;
    }

    private static function sourceAttributeFor(stationId:String, index:Number):String {
        if (!nonnegativeInteger(index) || index > 12) return "";
        var prior:Object = _root.健身房训练类型;
        var source:Object = null;
        try {
            if (stationId == "dummy") _root.获取木人桩训练项();
            else if (stationId == "dumbbell") _root.获取哑铃训练项();
            else if (stationId == "squat") _root.获取深蹲杠铃训练项();
            else return "";
            source = _root.健身房训练类型[index];
        } catch (catalogError) {
            return "";
        } finally {
            _root.健身房训练类型 = prior;
        }
        if (source == null) return "";
        var name:String = String(source.属性名);
        if (name == "技能点") return "技能点数";
        if (name == "全局健身HP加成" || name == "全局健身MP加成"
                || name == "全局健身空攻加成" || name == "全局健身防御加成"
                || name == "全局健身内力加成") return name;
        return "";
    }

    private static function planLevelGrowth(nextExperience:Number):Object {
        var oldLevel:Number = Number(_root.等级);
        var limit:Number = Number(_root.等级限制);
        if (!nonnegativeInteger(oldLevel) || oldLevel < 1 || !nonnegativeInteger(limit)) return null;
        if (oldLevel >= limit) return {level:oldLevel, skillPoints:0};
        if (typeof _root.根据等级得升级所需经验 != "function"
                || typeof _root.根据等级计算获得技能点 != "function") return null;
        var level:Number = oldLevel;
        var gained:Number = 0;
        while (level < limit) {
            var threshold:Number = Number(_root.根据等级得升级所需经验(level));
            if (!nonnegativeInteger(threshold) || threshold > nextExperience) break;
            level++;
            var points:Number = Number(_root.根据等级计算获得技能点(level));
            if (!nonnegativeInteger(points) || gained + points > MAX_SAFE_INTEGER) return null;
            gained += points;
        }
        return {level:level, skillPoints:gained};
    }

    private static function sameOpenContext():Boolean {
        return _open != null && _open.world === _root.gameworld
            && _open.actorKey === String(_root.控制目标)
            && _open.actor === _root.gameworld[_root.控制目标]
            && _open.saveOwner === _root.存档系统
            && _open.slotKey === String(_root.savePath)
            && _open.sceneEpoch === org.flashNight.arki.map.MapDomainBridge.getSceneEpoch()
            && _open.sceneStamp === sceneStamp();
    }

    private static function sameSessionContext():Boolean {
        return _session != null && _session.world === _root.gameworld
            && _session.actorKey === String(_root.控制目标)
            && _session.actor === _root.gameworld[_root.控制目标]
            && _session.sceneEpoch === org.flashNight.arki.map.MapDomainBridge.getSceneEpoch()
            && _session.sceneStamp === sceneStamp()
            && sameSaveContext();
    }

    private static function sameSaveContext():Boolean {
        return _session != null && _session.saveOwner === _root.存档系统
            && _session.slotKey === String(_root.savePath);
    }

    private static function saveAvailable():Boolean {
        return _root.允许存档 === true && _root.存档系统 != undefined
            && typeof _root.存档系统.markDirty == "function"
            && typeof _root.存档系统.flushDurableNow == "function"
            && typeof _root.记录玩家货币变化 == "function";
    }

    private static function sameProjectTerms(a:Object, b:Object):Boolean {
        return a.id === b.id && a.attributeName === b.attributeName
            && a.rewardAmount === b.rewardAmount && a.rewardLabel === b.rewardLabel
            && a.currency === b.currency && a.cost === b.cost
            && a.durationMs === b.durationMs && a.cap === b.cap;
    }

    private static function copyProject(p:Object):Object {
        return {id:p.id, attributeName:p.attributeName, rewardAmount:p.rewardAmount,
            rewardLabel:p.rewardLabel, currency:p.currency, cost:p.cost,
            durationMs:p.durationMs, cap:p.cap};
    }

    private static function copyAward(a:Object):Object {
        return {kind:a.kind, amount:a.amount, baseExperience:a.baseExperience,
            capExperience:a.capExperience};
    }

    private static function retireRunning():Void {
        if (_session != null && _session.phase == "running") _session.phase = "cancelled";
    }

    private static function now():Number { return _testNow >= 0 ? _testNow : getTimer(); }
    private static function sceneStamp():String {
        if (_json == undefined) _json = new LiteJSON();
        return _json.stringifySafe(org.flashNight.arki.map.MapFactsSampler.scene());
    }
    private static function nonnegativeInteger(value):Boolean {
        return typeof value == "number" && !isNaN(value) && isFinite(value)
            && value >= 0 && value <= MAX_SAFE_INTEGER && Math.floor(value) == value;
    }

    private static function fail(operation:String, error:String, params:Object):Object {
        if (params != null && _session != null && typeof params.sessionToken == "string"
                && params.sessionToken === _session.token) {
            var active:Object = resultFor(_session, operation);
            active.success = false;
            active.error = error;
            return active;
        }
        var result:Object = {success:false, v:1, operation:operation,
            phase:"preview", saved:false, error:error};
        if (params != null) {
            if (typeof params.openToken == "string") result.openToken = params.openToken;
            if (typeof params.sessionToken == "string") result.sessionToken = params.sessionToken;
            if (typeof params.stationId == "string") result.stationId = params.stationId;
            if (typeof params.projectId == "string") result.projectId = params.projectId;
        }
        return result;
    }

    private static function copyResult(source:Object, operation:String):Object {
        var result:Object = {};
        for (var key:String in source) if (key != "task" && key != "callId") result[key] = source[key];
        result.operation = operation;
        if (source.award != null) result.award = copyAward(source.award);
        if (source.balances != null) result.balances = {
            money:Number(source.balances.money), kpoint:Number(source.balances.kpoint)
        };
        return result;
    }

    public static function _setNowForTests(value:Number):Void { _testNow = value; }
    public static function _resetForTests():Void {
        _open = null; _session = null; _last = null; _testNow = -1;
    }
}
