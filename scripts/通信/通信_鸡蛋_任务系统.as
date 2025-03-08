import org.flashNight.arki.task.*;

_root.LoadPCTasks = function()
{
	var _loc2_ = SharedObject.getLocal("crazyflasher7_saves");
	_root.tasks_to_do = _loc2_.data.tasks_to_do;
	_root.tasks_finished = _loc2_.data.tasks_finished;
	_root.task_chains_progress = _loc2_.data.task_chains_progress;
	_root.task_history = _loc2_.data.task_history;
	UpdateTaskProgress();
	//检查任务数据完整性，若完整则检查并删除undefined任务
	// if(_root.tasks.length > 0){
	// 	for (var index in tasks_to_do){
	// 		if(TaskUtil.getTaskData(tasks_to_do[index].id).title == undefined){
	// 			_root.DeleteTask(index);
	// 		}
	// 	}
	// }
}

_root.SavePCTasks = function()
{
	var _loc2_ = SharedObject.getLocal("crazyflasher7_saves");
	_loc2_.data.tasks_to_do = _root.tasks_to_do;
	_loc2_.data.tasks_finished = _root.tasks_finished;
	_loc2_.data.task_chains_progress = _root.task_chains_progress;
	_loc2_.data.task_history = _root.task_history;
	_loc2_.flush();
	UpdateTaskProgress();
}

_root.NPCTaskCheck = function(npcname)
{
	for (var index in tasks_to_do){
		var finish_npc = TaskUtil.getTaskData(tasks_to_do[index].id).finish_npc;
		if (finish_npc == npcname && _root.taskFinished(index)){
			return {result:"完成任务", id:index};
		}
	}
	for (var i = 0; i < TaskUtil.tasks_of_npc[npcname].length; i++){
		if (_root.taskAvailable(TaskUtil.tasks_of_npc[npcname][i])){
			for (var j = 0; j < tasks_to_do.length; j++){
				if (tasks_to_do[j].id == TaskUtil.tasks_of_npc[npcname][i]){
					return {result:"路过"};
				}
			}
			return {result:"接受任务", id:TaskUtil.tasks_of_npc[npcname][i]};
		}
	}
	return {result:"路过"};
}

_root.GetTask = function(id){
	
	for (var i = 0; i < tasks_to_do.length; i++){
		if (tasks_to_do[i].id == id){
			_root.发布消息("无法重复接受任务！");
			return false;
		}
	}
	_root.AddTask(id);
	_root.SetDialogue(TaskUtil.getTaskText(TaskUtil.getTaskData(id).get_conversation));
	_root.任务栏界面.排列任务图标();
	_root.弹出公告界面.弹出新任务(id);
}

_root.taskFinished = function(index){
	var taskData = TaskUtil.getTaskData(tasks_to_do[index].id);
	var requirements = tasks_to_do[index].requirements;
	if (requirements.stages.length != 0){
		_root.任务完成提示._visible = false;
		return false;
	}

	if(!TaskUtil.containTaskItems(taskData.finish_contain_items)){
		_root.任务完成提示._visible = false;
		return false;
	}
	if(!TaskUtil.containTaskItems(taskData.finish_submit_items)){
		_root.任务完成提示._visible = false;
		return false;
	}
	_root.任务完成提示._visible = true;
	return true;
}

_root.taskAvailable = function(index){
	if (tasks_finished[String(index)] > 0 && tasks_finished[String(index)] != null){
		return false;
	}
	for (var i = 0; i < tasks_to_do.length; i++){
		if (tasks_to_do[i].id == index)
		{
			return false;
		}
	}
	var _loc4_ = 0;
	var 前置任务 = TaskUtil.getTaskData(index).get_requirements;
	while (_loc4_ < 前置任务.length){
		if (前置任务[_loc4_].__proto__ == Number.prototype){
			if (tasks_finished[String(前置任务[_loc4_])] < 1 || tasks_finished[String(前置任务[_loc4_])] == null){
				return false;
			}
		}else{
			var _loc6_ = 前置任务[_loc4_].split("#");
			// var itemArray = org.flashNight.arki.item.ItemUtil.getRequirement(requirements.items);
			// if(!org.flashNight.arki.item.ItemUtil.contain(itemArray))
			return false;
		}
		_loc4_ += 1;
	}
	return true;
}

_root.FinishTask = function(index){
	var taskID = tasks_to_do[index].id;
	var taskData = TaskUtil.getTaskData(taskID);
	var rewards = taskData.rewards;
	//检测挑战是否完成
	if(taskData.challenge.rewards.length > 0 && tasks_to_do[index].requirements.challenge.finished == true){
		rewards = rewards.concat(taskData.challenge.rewards);
	}
	var itemArray = org.flashNight.arki.item.ItemUtil.getRequirementFromTask(rewards);
	var rewardList = [];
	//处理任务奖励的金币和K点减少
	for(var i = 0; i < itemArray.length; i++){
		var itemName = itemArray[i].name;
		var itemValue = itemArray[i].value;
		if(itemName == "K点" && _root.isChallengeMode()) itemArray[i].value = Math.floor(itemValue * 0.1);
		if(itemName == "金币" && _root.isChallengeMode()) itemArray[i].value = Math.floor(itemValue * 0.5);
		// if(_root.isEasyMode()) itemArray[i].value = Math.floor(itemValue * 1.5);
		rewardList.push([itemName, itemArray[i].value]);
	}
	//获得奖励
	var result = org.flashNight.arki.item.ItemUtil.acquire(itemArray);
	if(!result){
		_root.发布消息("背包无法装下奖励，无法交付任务！请清理背包后重试！");
		return false;
	}
	_root.任务奖励提示界面.奖励品 = rewardList;
	_root.任务奖励提示界面.刷新();
	//消耗任务物品
	var submitItems = taskData.finish_submit_items;
	if(submitItems){
		var itemArray = org.flashNight.arki.item.ItemUtil.getRequirementFromTask(submitItems);
		var result = org.flashNight.arki.item.ItemUtil.submit(itemArray);
		if(!result){
			_root.发布消息("交付任务物品异常！");
		}
	}
	_root.SetDialogue(TaskUtil.getTaskText(taskData.finish_conversation));
	//移除已完成的任务
	UpdateTaskProgress(taskID);
	tasks_to_do.splice(index,1);
	//
	var _loc7_ = -1;
	var i = 0;
	while (i < TaskUtil.task_in_chains_by_sequence[taskData.chain[0]].length)
	{
		if (TaskUtil.task_chains[taskData.chain[0]][String(TaskUtil.task_in_chains_by_sequence[taskData.chain[0]][i])] == taskData.id)
		{
			_loc7_ = i;
			break;
		}
		i += 1;
	}
	var _loc9_ = TaskUtil.task_in_chains_by_sequence[taskData.chain[0]][i + 1] != undefined && _loc7_ != -1;
	var _loc10_ = taskAvailable(TaskUtil.task_chains[taskData.chain[0]][String(TaskUtil.task_in_chains_by_sequence[taskData.chain[0]][i + 1])]);
	if (_loc9_ && _loc10_)
	{
		_root.GetTask(TaskUtil.task_chains[taskData.chain[0]][String(TaskUtil.task_in_chains_by_sequence[taskData.chain[0]][i + 1])]);
	}
	return true;
}

_root.FinishStage = function(name, difficulty){
	for (var i in tasks_to_do){
		var task = tasks_to_do[i];
		var stageArr = task.requirements.stages;
		var len = stageArr.length;
		if(task.requirements.challenge && len == 1 && stageArr[0].name == name){
			if(task.requirements.challenge.difficulty == difficulty){
				task.requirements.challenge.finished = true;
				task.requirements.stages = [];
			}else if(stageArr[0].difficulty == difficulty){
				task.requirements.stages = [];
			}
		}else{
			for (var j = len-1 ; j > -1; j--){
				if (stageArr[j].name == name && stageArr[j].difficulty == difficulty){
					task.requirements.stages.splice(j,1);
				}
			}
		}
	}
	UpdateTaskProgress();
	//检测更低难度的任务完成
	switch (difficulty){
		case "地狱" :
			FinishStage(name,"修罗");
			break;
		case "修罗" :
			FinishStage(name,"冒险");
			break;
		case "冒险" :
			FinishStage(name,"简单");
			break;
		case "简单" :
			break;
	}
}

_root.AddTask = function(id){
	for (var i = 0; i < tasks_to_do.length; i++){
		if (tasks_to_do[i].id == id){
			_root.发布消息("无法重复接受任务！");
			return false;
		}
	}
	var taskData = TaskUtil.getTaskData(id);
	var finish_requirements = TaskUtil.getTaskData(id).finish_requirements;
	var 关卡要求 = {};
	// var _loc5_ = [];
	var stageArr = [];
	var i = 0;
	for (i in finish_requirements){
		var _loc9_ = finish_requirements[i].split("#");
		
		var stage = {};
		stage.name = _loc9_[0];
		stage.difficulty = _loc9_[1];
		stageArr.push(stage);
		// else
		// {
		// 	_loc7_ = {};
		// 	_loc7_.name = _loc9_[0];
		// 	_loc7_.count = _loc9_[1];
		// 	_loc5_.push(_loc7_);
		// }
	}
	// 关卡要求.items = _loc5_;
	关卡要求.stages = stageArr;
	//记录挑战难度
	if(taskData.challenge.difficulty){
		关卡要求.challenge = {};
		关卡要求.challenge.difficulty = taskData.challenge.difficulty;
		关卡要求.challenge.finished = false;
	}
	var task = {};
	task.id = id;
	task.requirements = 关卡要求;
	tasks_to_do.push(task);
}

_root.DeleteTask = function(index){
	if (TaskUtil.getTaskData(tasks_to_do[index].id).chain[0] == "主线"){
		_root.发布消息("无法删除主线任务！");
		return false;
	}
	tasks_to_do.splice(index,1);
	_root.发布消息("删除任务成功！");
	return true;
}

_root.UpdateTaskProgress = function(id){
	if (id != null){
		if (tasks_finished[String(id)] == undefined){
			tasks_finished[String(id)] = 0;
		}
		var chain = TaskUtil.getTaskData(id).chain;
		if (task_chains_progress[chain[0]] < Number(chain[1]) || task_chains_progress[chain[0]] == undefined){
			task_chains_progress[chain[0]] = Number(chain[1]);
		}
		tasks_finished[String(id)] += 1;
		task_history.push(id);
	}
	if (task_chains_progress.主线 == undefined){
		task_chains_progress.主线 = 0;
	}
	_root.主线任务进度 = task_chains_progress.主线;
	if (_root.主线任务进度 > 13){
		_root.后勤战备箱按钮._visible = true;
	}
	_root.任务栏界面.排列任务图标();
}

_root.计算难度等级 = function(等级描述){
	if (等级描述 === "简单") return 1;
	if (等级描述 === "冒险") return 1.5;
	if (等级描述 === "修罗") return 2;
	if (等级描述 === "地狱") return 2.5;
	return 1;
}

_root.点击npc后检测任务 = function(npc名字){
	var ret = NPCTaskCheck(npc名字);
	switch (ret.result){
		case "完成任务" :
			FinishTask(ret.id);
			break;
		case "接受任务" :
			GetTask(ret.id);
			break;
		case "路过" :
			break;
	}
	return ret.result;
}

_root.是否达成任务检测 = function(){
	for (var i in tasks_to_do){
		if (_root.taskFinished(i)) return true;
	}
	return false;
}

_root.完成任务提示检测 = function(){
	是否达成任务检测();
}

_root.打印任务进度 = function(页数){
	if (_root.任务栏界面.mc事件日志.mytext._x != undefined){
		_root.任务栏界面.mc事件日志.mytext.text = "";
		_root.任务栏界面.新任务text.text = "";
		var _loc3_ = (页数 - 1) * 事件日志每页条数;
		while (_loc3_ < task_history.length && _loc3_ < 页数 * 事件日志每页条数){
			// _root.任务栏界面.mc事件日志.mytext.text = _root.任务栏界面.mc事件日志.mytext.text + "\r" + TaskUtil.getTaskText(TaskUtil.getTaskData(task_history[_loc3_]).title) + _root.获得翻译(" 完成");
			_loc3_ += 1;
		}
	}
}

_root.检测并添加初始任务 = function(){
	//如果同时满足 任务栏全空 初始任务未完成 主线进度为0，则获取初始任务
	var 是否获取初始任务 = _root.tasks_to_do.length == 0 && _root.tasks_finished[0] <= 0 && _root.主线任务进度 <= 0;
	if(是否获取初始任务){
		_root.新手引导界面._visible = true;
		_root.新手引导界面.gotoAndStop("任务面板");
		_root.GetTask(TaskUtil.task_chains.主线[String(TaskUtil.task_in_chains_by_sequence.主线[0])]);
	}
}


//获取任务数据
_root.getTaskData = function(index){
	return TaskUtil.getTaskData(index);
}

//获取任务文本
_root.getTaskText = function(str){
	return TaskUtil.getTaskText(str);
}


//游戏难度检测
_root.isHardMode = function():Boolean{
	return _root.difficultyMode == 0;
}
_root.isEasyMode = function():Boolean{
	return _root.difficultyMode == 1;
}
_root.isChallengeMode = function():Boolean{
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
_root.task_history = [];
_root.可同时接的任务数 = 10;
_root.事件日志每页条数 = 10;
_root.主线任务进度 = 0;


//#func:_root.tesktest()