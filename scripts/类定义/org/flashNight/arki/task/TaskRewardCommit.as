import org.flashNight.arki.item.ItemUtil;
import org.flashNight.arki.item.BaseItem;
import org.flashNight.arki.item.RewardStashService;
import org.flashNight.arki.item.RewardStashStore;
import org.flashNight.arki.item.PlayerAssetTransaction;
import org.flashNight.arki.task.TaskUtil;

/** 交付消费、奖励、完成态和必然成长在同一候选；对话/音效晚于本地提交。 */
class org.flashNight.arki.task.TaskRewardCommit {
    private static var _instances:Object = {};

    public static function instanceToken(entry:Object):String {
        if (entry == null) return "";
        var key:String = "$" + entry.id;
        var cached:Object = _instances[key];
        if (cached == null || cached.entry !== entry) {
            cached = {entry:entry, token:RewardStashService.nextOperationId("quest")};
            _instances[key] = cached;
        }
        return String(cached.token);
    }

    private static function fail(error:String):Boolean {
        _root._lastTaskFinishError = error;
        return false;
    }

    public static function finish(index:Number, expectedInstance:String):Boolean {
        _root._lastTaskFinishError = "";
        if (!RewardStashStore.whole(index) || !(_root.tasks_to_do instanceof Array)
                || index >= _root.tasks_to_do.length) return fail("task_not_found");
        var instance:Object = _root.tasks_to_do[index];
        var token:String = instanceToken(instance);
        if (expectedInstance != null && expectedInstance !== token) return fail("stale_task_instance");
        if (RewardStashService.pendingOperationId() != "") return fail("commit_pending");
        if (typeof _root.taskCompleteCheck == "function" && _root.taskCompleteCheck(index) !== true) return fail("not_satisfied");
        var taskId:String = String(instance.id);
        var taskData:Object = TaskUtil.getTaskData(taskId);
        if (taskData == null) return fail("task_not_found");
        var rewards:Array = taskData.rewards;
        var challenge:Boolean = taskData.challenge.rewards.length > 0
            && instance.requirements.challenge.finished === true;
        if (challenge) rewards = rewards.concat(taskData.challenge.rewards);
        var definitions:Array = ItemUtil.getRequirementFromTask(rewards);
        for (var i:Number = 0; i < definitions.length; i++) {
            if (_root.isChallengeMode()) {
                if (definitions[i].name == "K点") definitions[i].value = Math.floor(definitions[i].value * 0.1);
                if (definitions[i].name == "金币") definitions[i].value = Math.floor(definitions[i].value * 0.5);
            }
        }
        var submit:Array = taskData.finish_submit_items
            ? ItemUtil.getRequirementFromTask(taskData.finish_submit_items) : null;
        if (submit != null && ItemUtil.contain(submit) == null) return fail("insufficient_items");
        var operationId:String = RewardStashService.nextOperationId("quest_finish");
        var context:Object = {source:"quest_reward", reason:"quest_complete", operationId:operationId, mergeScope:"operation"};
        var domain:Object = {taskId:taskId, taskData:taskData, beforeLevel:Number(_root.等级), challenge:challenge,
            overflowMoney:0, hasOverflow:false};
        if (!RewardStashService.begin(operationId, context, resolved, domain)) return fail(RewardStashService.lastError);
        try {
            if (submit != null && submit.length > 0 && !ItemUtil.submit(submit,
                    {source:"quest_turn_in", reason:"quest_complete"})) {
                var cancelled:Object = RewardStashService.cancel("insufficient_items"); return fail(String(cancelled.error));
            }
            // 消耗之后规划，所以释放出的格子、药剂 affinity 和情报余量都已正确。
            var positive:Array = [];
            for (var d:Number = 0; d < definitions.length; d++) {
                if (definitions[d].value === 0 && (definitions[d].name == "金币" || definitions[d].name == "K点")) continue;
                positive.push(definitions[d]);
            }
            var planned:Object = ItemUtil.planRewardAcquire(positive);
            if (planned == null) throw new Error("invalid_reward");
            domain.overflowMoney = planned.overflowMoney;
            domain.hasOverflow = planned.hasOverflow;
            for (var r:Number = 0; r < planned.items.length; r++) {
                var reward:Object = planned.items[r];
                var name:String = String(reward.name);
                if (name == "经验值" || name == "技能点") {
                    var growth:Object = ItemUtil.require([reward]);
                    if (growth == null) throw new Error("invalid_progress_reward");
                    _root.经验值 += Number(growth.经验值);
                    _root.技能点数 += Number(growth.技能点);
                    PlayerAssetTransaction.recordEffect("gain", name == "经验值" ? "experience" : "skillpoint", name, Number(reward.value), context);
                } else if (name == "金币" || name == "K点") {
                    if (!ItemUtil.acquire([reward], context)) throw new Error("invalid_currency_reward");
                } else {
                    var item:BaseItem = BaseItem.create(name, Number(reward.value));
                    if (item == null) throw new Error("invalid_reward");
                    if (typeof item.value == "object" && reward.tier != undefined) item.value.tier = reward.tier;
                    // 情报已由同批计划处理过上限/折算，admit 仍按当前数量核对，不重复获得。
                    if (!RewardStashService.admit([item.toObject()], true, true, context)) throw new Error("invalid_reward");
                }
            }
            if (!applyGrowth()) throw new Error("invalid_progress_reward");
            if (_root.tasks_to_do[index] !== instance || instanceToken(instance) !== token) throw new Error("stale_task_instance");
            _root.提交任务完成状态(taskId, taskData.chain);
            _root.tasks_to_do.splice(index, 1);
            var result:Object = RewardStashService.end("quest.v2|" + token,
                {success:true, kind:"quest", taskId:taskId, instanceToken:token}, "reward.quest_finish");
            return result.success === true ? true : fail(String(result.error));
        } catch (error) {
            var failure:Object = RewardStashService.cancel("task_reward_failed");
            trace("[TaskRewardCommit] candidate failed: " + error);
            return fail(String(failure.error));
        }
    }

    private static function applyGrowth():Boolean {
        if (!RewardStashStore.whole(Number(_root.等级)) || !RewardStashStore.whole(Number(_root.经验值))
                || !RewardStashStore.whole(Number(_root.技能点数))) return false;
        var limit:Number = Number(_root.等级限制);
        if (isNaN(limit)) return true;
        while (_root.等级 < limit) {
            var required:Number = Number(_root.根据等级得升级所需经验(_root.等级));
            if (!RewardStashStore.whole(required) || required < 1) return false;
            if (_root.经验值 < required) break;
            var next:Number = Number(_root.等级) + 1;
            var points:Number = Number(_root.根据等级计算获得技能点(next));
            if (!RewardStashStore.whole(points) || !RewardStashStore.whole(Number(_root.技能点数) + points)) return false;
            _root.等级 = next;
            _root.技能点数 += points;
        }
        _root.身价 = _root.基础身价值 * _root.等级;
        return true;
    }

    private static function resolved(committed:Boolean, domain:Object):Boolean {
        if (!committed) return true;
        // 每个可选消费者独立保护，任何失败不能重开已经完成的任务。
        try { _root.投影已提交任务成长(domain.beforeLevel); } catch (growthError) { trace("[TaskRewardCommit] growth projection: " + growthError); }
        try { _root.播放音效("levelup-2.wav"); } catch (audioError) { }
        try {
            if (domain.hasOverflow) _root.发布消息(domain.overflowMoney > 0
                ? "超出情报持有上限的奖励已折算为金币" + domain.overflowMoney + "。"
                : "已达持有上限的情报奖励不再重复计入。");
        } catch (noticeError) { }
        try {
            if (domain.challenge) org.flashNight.arki.item.obtain.ItemObtainIndex.getInstance().updateQuestRewards(
                domain.taskId, String(domain.taskData.title || domain.taskId), domain.taskData.rewards.concat(domain.taskData.challenge.rewards));
        } catch (discoveryError) { }
        try { _root.UpdateTaskProgress(); } catch (listError) { }
        try { _root.SetDialogue(TaskUtil.getTaskText(domain.taskData.finish_conversation)); } catch (dialogueError) { }
        try { TaskUtil.requestAutoAcceptAfterFinish(domain.taskId); } catch (nextTaskError) { }
        try { _root.是否达成任务检测(); } catch (completionError) { }
        return true;
    }
}
