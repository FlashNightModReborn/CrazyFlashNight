/**
 * 插话「我接了」后的任务发布交接（Host 推送 task=agent_task_publish）。
 *
 * 时序：校验（槽位/战斗/已接/不可接/token）→ 读 sync_state 的 task_publish_version
 * → 复用 agent.同步任务热更新 → 热更完成后结束旧对白 → GetTask 接管。
 * 任一步失败只提示，不自动重试、不重复接取；环境能力全部由调用方注入，
 * 本类不直接读 _root / 不直接调对话服务，便于 focused 测试。
 */
class org.flashNight.arki.task.AgentTaskPublishHandoff {
    private static var RECENT_TOKEN_MAX:Number = 16;
    private static var TIP_TEXT:String = "委托已登记，去找 NPC 接取";
    private static var _recentTokens:Object = {};
    private static var _recentOrder:Array = [];
    private static var _pending:Object = null;

    /** 测试用：清空 token 表与在途交接。 */
    public static function reset():Void {
        _recentTokens = {};
        _recentOrder = [];
        _pending = null;
    }

    public static function pendingForTest():Object {
        return _pending;
    }

    /**
     * env 契约（全部由调用方提供）：
     *   currentSlot:String, inCombat:Boolean, lastTaskPublishVersion:Number,
     *   isTaskActive(taskId) / hasTaskData(taskId) / isTaskAvailable(taskId) /
     *   loadVersion(onReady) / reload(fileVer,onDone,onFailed) /
     *   closeSession() / openTask(taskId) / showTip(text)
     */
    public static function handle(payload:Object, env:Object):Void {
        if (env == null) return;
        var v:Object = validate(payload, env);
        if (v.ok !== true) {
            if (v.tip == true) tip(env);
            trace("[AgentPublish] rejected: " + v.reason);
            return;
        }
        if (v.alreadyActive == true) {
            // 已经接过：只关旧对白；再 GetTask 会触发“无法重复接受任务”
            consumeToken(v.token);
            closeSession(env);
            trace("[AgentPublish] already active task=" + v.taskId);
            return;
        }
        if (typeof env.loadVersion != "function") {
            tip(env);
            trace("[AgentPublish] rejected: no_version_loader");
            return;
        }
        _pending = v;
        // 回调可能被裸调用（this 不是类对象），静态成员一律显式限定。
        env.loadVersion(function(fileVer:Number):Void {
            if (AgentTaskPublishHandoff._pending !== v) return;
            var baseline:Number = Number(env.lastTaskPublishVersion);
            var dataReady:Boolean = AgentTaskPublishHandoff.hasTaskData(env, v.taskId);
            if (dataReady
                    && (!isFinite(fileVer) || fileVer <= 0
                        || (isFinite(baseline) && fileVer == baseline))) {
                AgentTaskPublishHandoff.accept(v, env);
                return;
            }
            if (typeof env.reload != "function") {
                AgentTaskPublishHandoff._pending = null;
                AgentTaskPublishHandoff.tip(env);
                trace("[AgentPublish] rejected: no_reloader");
                return;
            }
            env.reload(fileVer, function():Void {
                if (AgentTaskPublishHandoff._pending !== v) return;
                AgentTaskPublishHandoff.accept(v, env);
            }, function(reason:String):Void {
                if (AgentTaskPublishHandoff._pending !== v) return;
                AgentTaskPublishHandoff._pending = null;
                AgentTaskPublishHandoff.tip(env);
                trace("[AgentPublish] reload failed: " + String(reason));
            });
        });
    }

    /** 纯校验：不改状态（token 只查不写）。 */
    public static function validate(payload:Object, env:Object):Object {
        if (payload == null || env == null) {
            return {ok:false, reason:"missing_payload"};
        }
        var taskId:Number = Number(payload.taskId);
        if (!isFinite(taskId) || taskId <= 0) {
            return {ok:false, reason:"invalid_task"};
        }
        var token:String = textOf(payload.token);
        if (token != "" && _recentTokens[token] === true) {
            return {ok:false, reason:"duplicate_token"};
        }
        if (textOf(payload.npc) == "") {
            return {ok:false, reason:"missing_npc"};
        }
        var slot:String = textOf(payload.slot);
        var currentSlot:String = textOf(env.currentSlot);
        if (slot != "" && currentSlot != "" && slot != currentSlot) {
            return {ok:false, reason:"slot_mismatch", tip:true};
        }
        if (env.inCombat == true) {
            return {ok:false, reason:"combat", tip:true};
        }
        if (isTaskActive(env, taskId)) {
            return {ok:true, taskId:taskId, token:token, alreadyActive:true};
        }
        // 新发布的任务在热更落地前不在 TaskUtil.tasks：此时 taskAvailable 会读空定义，
        // 只能先放行去热更，是否能接由 accept 在热更后再判一次。
        if (hasTaskData(env, taskId) && !isTaskAvailable(env, taskId)) {
            return {ok:false, reason:"not_available", tip:true};
        }
        return {ok:true, taskId:taskId, token:token, alreadyActive:false};
    }

    private static function accept(v:Object, env:Object):Void {
        _pending = null;
        consumeToken(v.token);
        closeSession(env);
        if (isTaskActive(env, v.taskId)) return;   // 热更期间已被接取
        if (!hasTaskData(env, v.taskId)) {
            tip(env);
            trace("[AgentPublish] accept blocked: task data missing task=" + v.taskId);
            return;
        }
        if (!isTaskAvailable(env, v.taskId)) {
            tip(env);
            trace("[AgentPublish] accept blocked task=" + v.taskId);
            return;
        }
        if (typeof env.openTask == "function") {
            env.openTask(v.taskId);
            trace("[AgentPublish] accept task=" + v.taskId);
        }
    }

    private static function isTaskActive(env:Object, taskId:Number):Boolean {
        return typeof env.isTaskActive == "function" && env.isTaskActive(taskId) === true;
    }

    private static function isTaskAvailable(env:Object, taskId:Number):Boolean {
        return typeof env.isTaskAvailable == "function" && env.isTaskAvailable(taskId) === true;
    }

    /** 任务定义是否已加载；env 不提供该能力时按已加载处理。 */
    private static function hasTaskData(env:Object, taskId:Number):Boolean {
        return typeof env.hasTaskData != "function" || env.hasTaskData(taskId) === true;
    }

    private static function closeSession(env:Object):Void {
        if (typeof env.closeSession == "function") env.closeSession();
    }

    private static function tip(env:Object):Void {
        if (typeof env.showTip == "function") env.showTip(TIP_TEXT);
    }

    private static function consumeToken(token:String):Void {
        if (token == "" || _recentTokens[token] === true) return;
        _recentTokens[token] = true;
        _recentOrder.push(token);
        while (_recentOrder.length > RECENT_TOKEN_MAX) {
            var old:String = String(_recentOrder.shift());
            delete _recentTokens[old];
        }
    }

    private static function textOf(value):String {
        return (value == undefined || value == null) ? "" : String(value);
    }
}
