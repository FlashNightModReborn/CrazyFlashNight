


 //从磁盘重新读取 data/task 与 data/task/text，并写回 TaskUtil。可选 onSuccess / onError。若正在执行中会忽略新的请求（避免重复点击叠加载）。
_root.重新加载任务数据 = function(onSuccess:Function, onError:Function):Void {
    if (_root._taskReloadBusy == true) {
        _root.发布消息("重新加载任务数据：已在执行中，跳过");
        return;
    }
    _root._taskReloadBusy = true;

    var taskDone:Boolean = false;
    var textDone:Boolean = false;
    var taskData:Object = null;
    var textData:Object = null;
    var failed:Boolean = false;

    function doneBusy():Void {
        _root._taskReloadBusy = false;
    }

    function tryFinish():Void {
        if (failed) {
            return;
        }
        if (!taskDone || !textDone) {
            return;
        }
        TaskUtil.ParseTaskData(taskData, textData);
        _root.检查任务数据完整性();
        _root.发布消息("任务数据已重新加载");
        doneBusy();
        if (onSuccess != undefined) {
            onSuccess();
        }
    }

    function fail():Void {
        if (failed) {
            return;
        }
        failed = true;
        trace("重新加载任务数据失败");
        _root.发布消息("任务数据重新加载失败");
        doneBusy();
        if (onError != undefined) {
            onError();
        }
    }

    TaskDataLoader.getInstance().reload(
        function(data:Object):Void {
            taskData = data;
            taskDone = true;
            tryFinish();
        },
        fail
    );

    TaskTextLoader.getInstance().reload(
        function(data:Object):Void {
            textData = data;
            textDone = true;
            tryFinish();
        },
        fail
    );
};

// ExternalInterface：若宿主（浏览器/部分壳）对 SWF 暴露了 JS 桥，外部可 call("reloadTaskData") 触发重新加载；独立播放器常不可用。
if (flash.external.ExternalInterface.available) {
    flash.external.ExternalInterface.addCallback("reloadTaskData", _root, _root.重新加载任务数据);
}

// LoadPCTasks / SavePCTasks 空壳定义在 通信_lsy_原版存档系统.as 的 shim 层

// 修复历史「引用错位」存档损坏。
// 正常存档中 task_chains_progress 的键应为任务链名(主线/大学/委托…);
// 此前启动器 SOL 解析器的引用错位 bug 会把旧 tasks_finished 的内容(任务ID键)
// 整体挤进 task_chains_progress,而 tasks_finished 自身被换成残片 —— 表现为
// 做过的支线任务在 NPC 处全部重新可接。此函数把错位的已完成记录抢救回
// tasks_finished,并按任务链定义重建 task_chains_progress 的链名进度。
// 健康存档不含任务ID键 → 探测阶段即返回,不改动任何数据(对健康存档零影响)。
_root.修复错位的任务存档 = function():Void {
    var tcp = _root.task_chains_progress;
    if (tcp == null || _root.tasks_finished == null)
        return;

    // 1. 探测错位指纹:task_chains_progress 中出现「合法任务ID」键
    var 错位键:Array = [];
    for (var k in tcp) {
        var raw = TaskUtil.getRawTaskData(k);
        if (raw != undefined && String(raw.id) == String(k)) {
            错位键.push(k);
        }
    }
    if (错位键.length == 0)
        return; // 健康存档,直接返回,零改动

    // 2. 把错位键的已完成记录抢救回 tasks_finished,并从 task_chains_progress 清除
    var 抢救数:Number = 0;
    for (var i = 0; i < 错位键.length; i++) {
        var key = 错位键[i];
        var v:Number = Number(tcp[key]);
        if (isNaN(v) || v < 1)
            v = 1;
        if (isNaN(_root.tasks_finished[key]) || _root.tasks_finished[key] < v) {
            _root.tasks_finished[key] = v;
            抢救数++;
        }
        delete tcp[key];
    }

    // 3. 从 tasks_finished 反向重建各任务链的链名进度(只升不降;无序号链如「委托」
    //    不在 task_chains 中,自然跳过,与正常存档一致)
    for (var chainName in TaskUtil.task_chains) {
        var chainObj = TaskUtil.task_chains[chainName];
        var seqArr:Array = TaskUtil.task_in_chains_by_sequence[chainName];
        var maxDone:Number = 0;
        for (var j = 0; j < seqArr.length; j++) {
            var seq = seqArr[j];
            if (_root.tasks_finished[chainObj[seq]] > 0 && seq > maxDone) {
                maxDone = seq;
            }
        }
        if (isNaN(tcp[chainName]) || tcp[chainName] < maxDone) {
            tcp[chainName] = maxDone;
        }
    }

    // 4. 标脏,确保修复结果会在下次存盘时落地
    if (_root.存档系统 != undefined)
        _root.存档系统.dirtyMark = true;
    if (_root.服务器 != undefined)
        _root.服务器.发布服务器消息("[任务存档修复] 引用错位:抢救已完成任务 " + 抢救数 + " 项,清理错位键 " + 错位键.length + " 个");
    trace("[任务存档修复] 抢救 " + 抢救数 + " / 清理 " + 错位键.length);
};

_root.检查任务数据完整性 = function() {
    //先检查任务数据是否加载完毕
    if (TaskUtil.tasks == null)
        return;
    //修复历史引用错位损坏(健康存档零影响)
    _root.修复错位的任务存档();
    //检查并删除undefined任务
    for (var index in _root.tasks_to_do) {
        if (TaskUtil.getTaskData(_root.tasks_to_do[index].id).title == null) {
            _root.DeleteTask(index);
        }
    }
    //检查主线任务链是否完整
    var 主线进度 = _root.task_chains_progress.主线;
    var chainArr = TaskUtil.task_in_chains_by_sequence.主线;
    var chainObj = TaskUtil.task_chains.主线;
    if (主线进度 > chainArr.length)
        主线进度 = chainArr.length;
    for (var i = 0; i < 主线进度; i++) {
        var taskID = chainObj[chainArr[i]];
        if (_root.tasks_finished[taskID] <= 0) {
            _root.tasks_finished[taskID] = 1;
        }
    }
    for (var i = 主线进度; i < chainArr.length; i++) {
        var taskID = chainObj[chainArr[i]];
        if (_root.tasks_finished[taskID] > 0) {
            _root.tasks_finished[taskID] = undefined;
        }
    }
}

_root.NPCTaskCheck = function(npcname) {
    var npcHotspot:String = org.flashNight.arki.map.MapHotspotResolver.resolveCurrent();
    for (var index in _root.tasks_to_do) {
        var activeTaskData:Object = TaskUtil.getTaskData(_root.tasks_to_do[index].id);
        if (TaskUtil.taskNpcMatches(activeTaskData, "finish", npcname, npcHotspot) && _root.taskCompleteCheck(index)) {
            return {result: "完成任务", id: index};
        }
    }
    var npcTaskIds:Array = TaskUtil.getTasksForNpc(npcname, npcHotspot);
    for (var i = 0; i < npcTaskIds.length; i++) {
        if (_root.taskAvailable(npcTaskIds[i])) {
            for (var j = 0; j < _root.tasks_to_do.length; j++) {
                if (_root.tasks_to_do[j].id == npcTaskIds[i]) {
                    return {result: "路过"};
                }
            }
            return {result: "接受任务", id: npcTaskIds[i]};
        }
    }
    return {result: "路过"};
}

_root.GetTask = function(id) {
    for (var i = 0; i < _root.tasks_to_do.length; i++) {
        if (_root.tasks_to_do[i].id == id) {
            _root.发布消息("无法重复接受任务！");
            return false;
        }
    }
    var taskData = TaskUtil.getTaskData(id);
    _root.AddTask(id);
    _root.SetDialogue(TaskUtil.getTaskText(taskData.get_conversation));
    // 任务通知 → Launcher 刘海屏
    var taskTitle = TaskUtil.getTaskText(taskData.title);
    _root.server.sendSocketMessage("Utask|" + taskTitle);
    if (taskData.announcement.length > 0) {
        //#$#;用于分割多条公告
        var announcement_Arr = taskData.announcement.split("#$#;");
        // 在2秒后逐条发布公告到刘海屏
        _root.帧计时器.添加单次任务(function() {
            for (var i = 0; i < announcement_Arr.length; i++) {
                _root.server.sendSocketMessage("Uannounce|" + announcement_Arr[i]);
            }
        }, 2000);
    }
}

// 原名为taskFinished
_root.taskCompleteCheck = function(index) {
    var taskData = TaskUtil.getTaskData(_root.tasks_to_do[index].id);
    var requirements = _root.tasks_to_do[index].requirements;
    if (requirements.stages.length != 0) {
        return false;
    }

    //目前逻辑为提交物品与持有物品不可兼容，优先判定提交物品
    if (!TaskUtil.checkItemRequirements(taskData)) {
        return false;
    }
    //检查特殊需求
    if (!TaskUtil.checkSpecialRequirements(taskData)) {
        return false;
    }
    //检查共享判定条件（conditions 可选字段，与成就共用 ObjectiveEvaluator；无该字段零成本直过）
    if (!TaskUtil.checkConditions(taskData, _root.tasks_to_do[index])) {
        return false;
    }
    return true;
}

_root.taskAvailable = function(index) {
    if (_root.tasks_finished[String(index)] > 0) {
        return false;
    }
    for (var i = 0; i < _root.tasks_to_do.length; i++) {
        if (_root.tasks_to_do[i].id == index) {
            return false;
        }
    }
    var get_requirements = TaskUtil.getTaskData(index).get_requirements;
    for (var i = 0; i < get_requirements.length; i++) {
        if (isNaN(_root.tasks_finished[get_requirements[i]]) || _root.tasks_finished[get_requirements[i]] < 1) {
            return false;
        }
    }
    return true;
}

_root.FinishTask = function(index) {
    var taskID = _root.tasks_to_do[index].id;
    var taskData = TaskUtil.getTaskData(taskID);
    var rewards = taskData.rewards;
    //检测挑战是否完成
    var challengeCompleted:Boolean = taskData.challenge.rewards.length > 0 && _root.tasks_to_do[index].requirements.challenge.finished == true;
    if (challengeCompleted) {
        rewards = rewards.concat(taskData.challenge.rewards);
        // === 追加挑战奖励到物品来源缓存 ===
        var questTitle = TaskUtil.getTaskText(taskData.title);
        org.flashNight.arki.item.obtain.ItemObtainIndex.getInstance().appendQuestRewards(
            String(taskID), questTitle, taskData.challenge.rewards
        );
    }
    var itemArray = org.flashNight.arki.item.ItemUtil.getRequirementFromTask(rewards);
    //处理任务奖励的金币和K点减少
    for (var i = 0; i < itemArray.length; i++) {
        var itemName = itemArray[i].name;
        var itemValue = itemArray[i].value;
        if (itemName == "K点" && _root.isChallengeMode())
            itemArray[i].value = Math.floor(itemValue * 0.1);
        if (itemName == "金币" && _root.isChallengeMode())
            itemArray[i].value = Math.floor(itemValue * 0.5);
        // if(_root.isEasyMode()) itemArray[i].value = Math.floor(itemValue * 1.5);
    }
    // 交付物预检只是写前快速拒绝；事务内 submit 仍逐项核验实际扣除，
    // 防止同步监听器重入让后续交付物在 contain 后失效。
    var submitItems = taskData.finish_submit_items;
    var submitItemArray:Array = submitItems
        ? org.flashNight.arki.item.ItemUtil.getRequirementFromTask(submitItems) : null;
    if (submitItemArray != null
            && org.flashNight.arki.item.ItemUtil.contain(submitItemArray) == null) {
        _root.发布消息("任务交付物品不足，无法完成任务！");
        return false;
    }
    // 先冻结情报溢出折算后的实际奖励计划。经验/技能点拆成最后写入的标量，
    // 其余货币/容器奖励与任务交付物都受通用 exact snapshot 保护。
    var rewardPlan:Object =
        org.flashNight.arki.item.ItemUtil.planRewardAcquire(itemArray);
    if (rewardPlan == null) {
        _root.发布消息("奖励配置无效，无法交付任务！");
        return false;
    }
    var reversibleRewardItems:Array = [];
    var progressRewardItems:Array = [];
    for (var rewardIndex:Number = 0;
            rewardIndex < rewardPlan.items.length; rewardIndex++) {
        var plannedReward:Object = rewardPlan.items[rewardIndex];
        if (plannedReward.name == "经验值"
                || plannedReward.name == "技能点") {
            progressRewardItems.push(plannedReward);
        } else {
            reversibleRewardItems.push(plannedReward);
        }
    }
    // split 后仍复用 require 的标量聚合/finite/安全整数/当前值上限校验，
    // 禁止重复 XP/SP 奖励相加溢出后被静默少发。
    var progressRewardPlan:Object = progressRewardItems.length > 0
        ? org.flashNight.arki.item.ItemUtil.require(progressRewardItems)
        : {经验值:0, 技能点:0};
    if (progressRewardPlan == null) {
        _root.发布消息("奖励进度配置无效，无法交付任务！");
        return false;
    }
    var experienceReward:Number = Number(progressRewardPlan.经验值);
    var skillPointReward:Number = Number(progressRewardPlan.技能点);
    if (reversibleRewardItems.length > 0
            && org.flashNight.arki.item.ItemUtil.require(reversibleRewardItems) == null) {
        _root.发布消息("背包无法装下奖励，无法交付任务！请清理背包后重试！");
        return false;
    }
    var tasksFinishedExists:Boolean = _root.tasks_finished != undefined;
    var chainProgressExists:Boolean = _root.task_chains_progress != undefined;
    var taskStateBackup:Object = {
        tasksFinished:tasksFinishedExists
            ? org.flashNight.gesh.object.ObjectUtil.clone(_root.tasks_finished) : null,
        chainProgress:chainProgressExists
            ? org.flashNight.gesh.object.ObjectUtil.clone(_root.task_chains_progress) : null,
        tasksToDo:org.flashNight.gesh.object.ObjectUtil.clone(_root.tasks_to_do),
        assets:org.flashNight.arki.item.ItemUtil.capturePlayerAssetSnapshot(),
        experience:Number(_root.经验值),
        skillPoints:Number(_root.技能点数),
        dirty:_root.存档系统 == undefined
            ? undefined : _root.存档系统.dirtyMark
    };
    var restoreTaskClaimState:Function = function():Boolean {
        var fullyRestored:Boolean = true;
        try {
            _root.经验值 = Number(taskStateBackup.experience);
            _root.技能点数 = Number(taskStateBackup.skillPoints);
        } catch (taskProgressRestoreError) {
            fullyRestored = false;
            trace("[FinishTask] progress snapshot restore failed: "
                + taskProgressRestoreError);
        }
        try {
            if (tasksFinishedExists) {
                _root.tasks_finished = org.flashNight.gesh.object.ObjectUtil.clone(
                    taskStateBackup.tasksFinished);
            } else {
                delete _root.tasks_finished;
            }
            if (chainProgressExists) {
                _root.task_chains_progress = org.flashNight.gesh.object.ObjectUtil.clone(
                    taskStateBackup.chainProgress);
            } else {
                delete _root.task_chains_progress;
            }
            _root.tasks_to_do = org.flashNight.gesh.object.ObjectUtil.clone(
                taskStateBackup.tasksToDo);
        } catch (taskClaimRestoreError) {
            fullyRestored = false;
            trace("[FinishTask] task snapshot restore failed: "
                + taskClaimRestoreError);
        }
        // 任务/进度领域字段精确复原后才返还带 receipt 的通用资产；若领域
        // restore 已失败则保留资产事实，避免 settle(true) 发布幽灵 loss/gain。
        if (fullyRestored) {
            fullyRestored =
                org.flashNight.arki.item.ItemUtil.restorePlayerAssetSnapshot(
                    taskStateBackup.assets);
        }
        try {
            if (fullyRestored && _root.存档系统 != undefined) {
                _root.存档系统.dirtyMark = taskStateBackup.dirty;
            }
        } catch (taskDirtyRestoreError) {
            fullyRestored = false;
            trace("[FinishTask] dirty snapshot restore failed: "
                + taskDirtyRestoreError);
        }
        return fullyRestored;
    };
    // 奖励入账、任务物品交付与任务完成属于同一个玩家资产操作。外层事务
    // 延迟消费者回执，避免奖励刚入包、任务尚未完成时提前播报；失败预检不留卡片。
    var assetTransaction:Object =
        org.flashNight.arki.item.PlayerAssetTransaction.begin({
            source:"quest_reward", reason:"quest_complete", mergeScope:"operation"
        });
    var rewardSettlement:Object = rewardPlan;
    try {
        // 任务状态、奖励与交付物都是存档权威；缺少存档系统时首写失败，
        // catch 用同一快照恢复。先交付再发奖，避免奖励 listener 重入改变交付前提。
        org.flashNight.arki.item.PlayerAssetTransaction.markDirtyRequired(
            _root.存档系统);
        if (submitItemArray != null && submitItemArray.length > 0) {
            var result:Boolean = org.flashNight.arki.item.ItemUtil.submit(
                submitItemArray, {
                    source:"quest_turn_in", reason:"quest_complete"
                });
            if (!result) {
                var turnInRestored:Boolean = restoreTaskClaimState();
                org.flashNight.arki.item.PlayerAssetTransaction.settleAfterException(
                    assetTransaction, !turnInRestored);
                if (!turnInRestored) throw "quest_turn_in_restore_failed";
                try {
                    _root.发布消息("交付任务物品状态已变化，请重试任务完成！");
                } catch (turnInMessageError) {
                    trace("[FinishTask] turn-in warning failed: " + turnInMessageError);
                }
                return false;
            }
        }

        // 情报按计划截断，溢出已折算进 reversibleRewardItems 的金币。
        if (reversibleRewardItems.length > 0
                && !org.flashNight.arki.item.ItemUtil.acquire(
                    reversibleRewardItems, {
                        source:"quest_reward", reason:"quest_complete"
                    })) {
            var rewardRestored:Boolean = restoreTaskClaimState();
            org.flashNight.arki.item.PlayerAssetTransaction.settleAfterException(
                assetTransaction, !rewardRestored);
            if (!rewardRestored) throw "quest_reward_restore_failed";
            try {
                _root.发布消息("背包无法装下奖励，无法交付任务！请清理背包后重试！");
            } catch (rewardFailureMessageError) {
                trace("[FinishTask] reward warning failed: "
                    + rewardFailureMessageError);
            }
            return false;
        }

        // 无 EventBus 的进度标量最后写；升级联动移到 commit 后 guarded 投影，
        // 不允许旧回调把任务完成变成可重放的未知结果。
        if (experienceReward > 0) {
            _root.经验值 += experienceReward;
            org.flashNight.arki.item.PlayerAssetTransaction.markAuthorityWrite(
                assetTransaction);
        }
        if (skillPointReward > 0) {
            _root.技能点数 += skillPointReward;
            org.flashNight.arki.item.PlayerAssetTransaction.markAuthorityWrite(
                assetTransaction);
        }

        _root.提交任务完成状态(taskID, taskData.chain);
        _root.tasks_to_do.splice(index, 1);
        rewardSettlement.success = true;
    } catch (finishTaskAssetError) {
        var finishTaskRestored:Boolean = restoreTaskClaimState();
        org.flashNight.arki.item.PlayerAssetTransaction.settleAfterException(
            assetTransaction, !finishTaskRestored);
        trace("[FinishTask] asset boundary failed: " + finishTaskAssetError);
        throw finishTaskAssetError;
    }
    org.flashNight.arki.item.PlayerAssetTransaction.commit(assetTransaction);
    if (experienceReward > 0) {
        try {
            _root.主角是否升级(_root.等级, _root.经验值);
        } catch (levelProjectionError) {
            trace("[FinishTask] post-commit level reconciliation failed: "
                + levelProjectionError);
        }
    }
    // 奖励弹窗已退役：音效与提示都是可选投影，必须晚于权威状态和资产回执提交。
    try {
        if (rewardSettlement.items.length >= 1) {
            _root.播放音效("levelup-2.wav");
        }
    } catch (rewardSoundError) {
        trace("[FinishTask] post-commit reward sound failed: " + rewardSoundError);
    }
    try {
        if (rewardSettlement.hasOverflow) {
            _root.发布消息(rewardSettlement.overflowMoney > 0
                ? "超出情报持有上限的奖励已折算为金币" + rewardSettlement.overflowMoney + "。"
                : "已达持有上限的情报奖励不再重复计入。");
        }
    } catch (overflowMessageError) {
        trace("[FinishTask] post-commit overflow message failed: " + overflowMessageError);
    }
    try {
        _root.UpdateTaskProgress();
    } catch (taskProjectionError) {
        trace("[FinishTask] post-commit task projection failed: " + taskProjectionError);
    }
    try {
        _root.SetDialogue(TaskUtil.getTaskText(taskData.finish_conversation));
    } catch (dialogueProjectionError) {
        trace("[FinishTask] post-commit dialogue projection failed: "
            + dialogueProjectionError);
    }
    // 自动接链与完成检测都是提交后可选投影；任何旧回调异常都不得把已经完成
    // 的任务伪装成失败并阻断调用者 success finality。
    try {
        var isTaskInChain = false;
        var chainDict = TaskUtil.task_chains[taskData.chain[0]];
        var chainArray = TaskUtil.task_in_chains_by_sequence[taskData.chain[0]];
        var i = 0;
        while (i < chainArray.length) {
            if (chainDict[chainArray[i]] == taskData.id) {
                isTaskInChain = true;
                break;
            }
            i++;
        }
        if (isTaskInChain) {
            var nextTaskID = chainDict[chainArray[i + 1]];
            var nextTaskData:Object = TaskUtil.getTaskData(nextTaskID);
            // 检查上个任务的交付NPC与下个任务的接取NPC是否为同一地点的同一NPC
            if (TaskUtil.canAutoAcceptNextAtFinishNpc(taskData, nextTaskData)
                    && _root.taskAvailable(nextTaskID)) {
                _root.GetTask(nextTaskID);
            }
        }
    } catch (nextTaskProjectionError) {
        trace("[FinishTask] post-commit next-task projection failed: "
            + nextTaskProjectionError);
    }
    try {
        _root.是否达成任务检测();
    } catch (taskCompletionProjectionError) {
        trace("[FinishTask] post-commit completion projection failed: "
            + taskCompletionProjectionError);
    }
    return true;
}

_root.FinishStage = function(name, difficulty, deferProjection) {
    for (var i in _root.tasks_to_do) {
        var task = _root.tasks_to_do[i];
        var stageArr = task.requirements.stages;
        var len = stageArr.length;
        if (task.requirements.challenge && len == 1 && stageArr[0].name == name) {
            if (task.requirements.challenge.difficulty == difficulty) {
                task.requirements.challenge.finished = true;
                task.requirements.stages = [];
            } else if (stageArr[0].difficulty == difficulty) {
                task.requirements.stages = [];
            }
        } else {
            for (var j = len - 1; j > -1; j--) {
                if (stageArr[j].name == name && stageArr[j].difficulty == difficulty) {
                    task.requirements.stages.splice(j, 1);
                }
            }
        }
    }
    // Plan A audit: FinishStage 写 tasks_to_do[i].requirements，必须标脏
    _root.存档系统.dirtyMark = true;
    //检测更低难度的任务完成
    switch (difficulty) {
        case "地狱":
            FinishStage(name, "修罗", true);
            break;
        case "修罗":
            FinishStage(name, "冒险", true);
            break;
        case "冒险":
            FinishStage(name, "简单", true);
            break;
        case "简单":
            break;
    }
    // 一次关卡胜利会递归完成全部较低难度要求；只在最外层统一重算，
    // 避免逐层广播中间态，并让 Launcher 的“前往交付”无需等待后续心跳。
    if (deferProjection !== true) {
        _root.UpdateTaskProgress();
        try {
            _root.是否达成任务检测();
        } catch (stageTaskProjectionError) {
            trace("[FinishStage] post-commit completion projection failed: "
                + stageTaskProjectionError);
        }
    }
}

_root.AddTask = function(id) {
    for (var i = 0; i < _root.tasks_to_do.length; i++) {
        if (_root.tasks_to_do[i].id == id) {
            _root.发布消息("无法重复接受任务！");
            return false;
        }
    }
    var taskData = TaskUtil.getTaskData(id);
    var finish_requirements = TaskUtil.getTaskData(id).finish_requirements;
    var 关卡要求 = {};
    var stageArr = [];
    var i = 0;
    for (i in finish_requirements) {
        var itemArr = finish_requirements[i].split("#");

        var stage = {};
        stage.name = itemArr[0];
        stage.difficulty = itemArr[1];
        stageArr.push(stage);
    }
    关卡要求.stages = stageArr;
    //记录挑战难度
    if (taskData.challenge.difficulty) {
        关卡要求.challenge = {};
        关卡要求.challenge.difficulty = taskData.challenge.difficulty;
        关卡要求.challenge.finished = false;
    }
    //conditions 基线快照（判定层共享设计 §4）：sinceAccept 条件记录接取时读数（窗口语义，
    //照成就 base.kt 模式）；非 sinceAccept 条目记 0 占位保持下标对齐。condBase 随
    //requirements 进 tasks_to_do 存档透传。
    if (taskData.conditions != undefined && taskData.conditions.length > 0) {
        var condBase = [];
        for (var ci = 0; ci < taskData.conditions.length; ci++) {
            var cond = taskData.conditions[ci];
            condBase.push(cond.sinceAccept == true
                ? org.flashNight.arki.achievement.ObjectiveEvaluator.rawOf(cond.type, cond.params)
                : 0);
        }
        关卡要求.condBase = condBase;
    }
    var task = {};
    task.id = id;
    task.requirements = 关卡要求;
    _root.tasks_to_do.push(task);
    // Plan A audit: AddTask 写 tasks_to_do，必须标脏
    _root.存档系统.dirtyMark = true;

    // === 更新任务奖励缓存（接取任务时记录基础奖励） ===
    if (taskData.rewards && taskData.rewards.length > 0) {
        var questTitle = TaskUtil.getTaskText(taskData.title);
        org.flashNight.arki.item.obtain.ItemObtainIndex.getInstance().updateQuestRewards(
            String(id), questTitle, taskData.rewards
        );
    }
}

_root.DeleteTask = function(index) {
    if (TaskUtil.getTaskData(_root.tasks_to_do[index].id).chain[0] == "主线") {
        _root.发布消息("无法删除主线任务！");
        return false;
    }
    _root.tasks_to_do.splice(index, 1);
    // Plan A audit: DeleteTask 写 tasks_to_do，必须标脏
    _root.存档系统.dirtyMark = true;
    _root.发布消息("删除任务成功！");
    return true;
}

// 任务完成的权威状态写入与 UI 投影分离。资产事务只调用本函数，避免把
// 后勤按钮等可选 UI 回调放进“奖励 + 交付 + 完成任务”的 finality 边界。
_root.提交任务完成状态 = function(id, chain) {
    if (_root.task_chains_progress == undefined) _root.task_chains_progress = {};
    if (_root.tasks_finished == undefined) _root.tasks_finished = {};
    if (!isNaN(chain[1]) && (_root.task_chains_progress[chain[0]] < chain[1] || _root.task_chains_progress[chain[0]] == null)) {
        _root.task_chains_progress[chain[0]] = chain[1];
        _root.tasks_finished[String(id)] = 1;
    } else {
        if (isNaN(_root.tasks_finished[String(id)])) {
            _root.tasks_finished[String(id)] = 1;
        } else {
            _root.tasks_finished[String(id)] += 1;
        }
    }
    _root.存档系统.dirtyMark = true;
}

_root.UpdateTaskProgress = function(id) {
    if (id != null) {
        _root.提交任务完成状态(id, TaskUtil.getTaskData(id).chain);
    }
    if (isNaN(_root.task_chains_progress.主线)) {
        _root.task_chains_progress.主线 = 0;
    }
    _root.主线任务进度 = _root.task_chains_progress.主线;
    if (_root.主线任务进度 > 13) {
        _root.后勤战备箱按钮._visible = true;
    }
}


// 检测对应任务是否已完成
_root.isTaskFinished = function(index):Boolean {
    return _root.tasks_finished[String(index)] > 0;
}



_root.计算难度等级 = function(等级描述:String) {
    if (等级描述 === "简单")
        return 1;
    if (等级描述 === "冒险")
        return 1.5;
    if (等级描述 === "修罗")
        return 2;
    if (等级描述 === "地狱")
        return 2.5;
    return 1;
}
_root.获取难度等级 = function(等级:Number) {
    if (等级 == 1)
        return "简单";
    if (等级 == 1.5)
        return "冒险";
    if (等级 == 2)
        return "修罗";
    if (等级 == 2.5)
        return "地狱";
    return "";
}
_root.难度是否达到 = function(等级描述:String):Boolean{
    return _root.难度等级 >= _root.计算难度等级(等级描述);
}

_root.点击npc后检测任务 = function(npc名字, 目标) {
    var npcTaskName:String = String(npc名字);
    if (目标 != undefined && 目标 != null && 目标.任务名 != undefined && 目标.任务名 != null && String(目标.任务名).length > 0) {
        npcTaskName = String(目标.任务名);
    }
    var ret = NPCTaskCheck(npcTaskName);
    switch (ret.result) {
        case "完成任务":
            _root.FinishTask(ret.id);
            break;
        case "接受任务":
            _root.GetTask(ret.id);
            break;
        case "路过":
            break;
    }
    // if (目标) {
    //     if (_root.NPCTaskCheck(目标.名字).result == "接受任务") {
    //         //目标.文字信息.任务接取提示._visible = 1;
    //         if (目标.文字信息 && !目标.文字信息.任务接取提示) {
    //             目标.文字信息.任务接取提示 = 目标.文字信息.attachMovie("任务接取提示", "任务接取提示", 目标.文字信息.getNextHighestDepth());
    //             目标.文字信息.任务接取提示._x = 32.5;
    //             目标.文字信息.任务接取提示._y = 12.1;
    //         }
    //     } else {
    //         //目标.文字信息.任务接取提示._visible = 0;
    //         if (目标.文字信息 && 目标.文字信息.任务接取提示) {
    //             目标.文字信息.任务接取提示.removeMovieClip();
    //             delete 目标.文字信息.任务接取提示;
    //         }
    //     }
    // }
    return ret.result;
}

_root.是否达成任务检测 = function() {
    var found:Boolean = false;
    for (var i in _root.tasks_to_do) {
        if (_root.taskCompleteCheck(i)) {
            found = true;
            break;
        }
    }
    // 任务完成状态 + 最佳可交付 hotspot + 当前/返基地后是否可传送 → Launcher 刘海屏
    // tdn 服务普通点击，tdr 服务关卡胜利后的“结算后前往交付”；两者不能混用。
    var tdh:String = "";
    var tdn:String = "0";
    var tdr:String = "0";
    if (found) {
        var state:Object = org.flashNight.arki.map.MapPanelService.resolveDeliverableState();
        tdh = String(state.hotspotId);
        if (state.navigable) tdn = "1";
        if (state.returnNavigable) tdr = "1";
    }
    org.flashNight.arki.render.FrameBroadcaster.pushUiState(
        "td:" + (found ? "1" : "0") + "|tdh:" + tdh
            + "|tdn:" + tdn + "|tdr:" + tdr
    );
    return found;
}

_root.完成任务提示检测 = function() {
    是否达成任务检测();
}


_root.检测并添加初始任务 = function() {
    //如果同时满足 任务栏全空 初始任务未完成 主线进度为0，则获取初始任务
    var 是否获取初始任务 = _root.tasks_to_do.length == 0 && _root.tasks_finished[0] <= 0 && _root.主线任务进度 <= 0;
    if (是否获取初始任务) {
        _root.加载引导界面("引导-地图传送");
        _root.GetTask(0);
    }
}


//获取任务数据
_root.getTaskData = function(index) {
    return TaskUtil.getTaskData(index);
}

//获取任务文本
_root.getTaskText = function(str) {
    return TaskUtil.getTaskText(str);
}


//游戏难度检测
_root.isHardMode = function():Boolean {
    return _root.difficultyMode == 0;
}
_root.isEasyMode = function():Boolean {
    return _root.difficultyMode == 1;
}
_root.isChallengeMode = function():Boolean {
    return _root.difficultyMode == 2;
}
/*
   function ArrInclude(parentArr, arr){
   i = 0;
   while (i < parentArr.length){
   if (parentArr[i] == arr){
   return true;
   }
   i++;
   }
   return false;
   }
 */


_root.tasks_to_do = [];
_root.tasks_finished = {};
_root.task_chains_progress = {};
// _root.task_history = [];
_root.可同时接的任务数 = 10;
_root.主线任务进度 = 0;


//#func:_root.tesktest()



// 特殊任务需求
TaskUtil.specialRequirements = new Object();

TaskUtil.specialRequirements.task = {describe: function(args) {
    return "完成任务【" + TaskUtil.getTaskText(TaskUtil.getTaskData(args[1]).title) + "】";
},
        check: function(args) {
            return _root.isTaskFinished(args[1]);
        }}

TaskUtil.specialRequirements.skill = {describe: function(args) {
    return "技能【" + args[1] + "】达到" + args[2] + "级";
},
        check: function(args) {
            return (_root.根据技能名查找主角技能等级(args[1]) > args[2] - 1);
        }}

TaskUtil.specialRequirements.infrastructure = {describe: function(args) {
    return "基建项目【" + args[1] + "】达到" + args[2] + "级";
},
        check: function(args) {
            return _root.基建系统.检查基建等级(args[1], args[2]);
        }}
