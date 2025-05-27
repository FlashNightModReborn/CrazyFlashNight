import org.flashNight.arki.task.*;

_root.LoadPCTasks = function(){
	var saveData = SharedObject.getLocal("crazyflasher7_saves");
	_root.tasks_to_do = saveData.data.tasks_to_do;
	_root.tasks_finished = saveData.data.tasks_finished;
	_root.task_chains_progress = saveData.data.task_chains_progress;
	// _root.task_history = saveData.data.task_history;
	_root.UpdateTaskProgress();
	_root.检查任务数据完整性();
}

_root.SavePCTasks = function(){
	var saveData = SharedObject.getLocal("crazyflasher7_saves");
	saveData.data.tasks_to_do = _root.tasks_to_do;
	saveData.data.tasks_finished = _root.tasks_finished;
	saveData.data.task_chains_progress = _root.task_chains_progress;
	saveData.data.task_history = undefined;
	saveData.flush();
	_root.UpdateTaskProgress();
}


_root.检查任务数据完整性 = function(){
	//先检查任务数据是否加载完毕
	if(TaskUtil.tasks == null) return;
	//检查并删除undefined任务
	for (var index in _root.tasks_to_do){
		if(TaskUtil.getTaskData(_root.tasks_to_do[index].id).title == null){
			_root.DeleteTask(index);
		}
	}
	//检查主线任务链是否完整
	var 主线进度 = _root.task_chains_progress.主线;
	var chainArr = TaskUtil.task_in_chains_by_sequence.主线;
	var chainObj = TaskUtil.task_chains.主线;
	if(主线进度 > chainArr.length) 主线进度 = chainArr.length;
	for(var i = 0; i < 主线进度; i++){
		var taskID = chainObj[chainArr[i]];
		if(_root.tasks_finished[taskID] <= 0) {
			_root.tasks_finished[taskID] = 1;
		}
	}
	for(var i = 主线进度; i < chainArr.length; i++){
		var taskID = chainObj[chainArr[i]];
		if(_root.tasks_finished[taskID] > 0) {
			_root.tasks_finished[taskID] = undefined;
		}
	}
}

_root.NPCTaskCheck = function(npcname){
	for (var index in _root.tasks_to_do){
		var finish_npc = TaskUtil.getTaskData(_root.tasks_to_do[index].id).finish_npc;
		if (finish_npc == npcname && _root.taskCompleteCheck(index)){
			return {result:"完成任务", id:index};
		}
	}
	for (var i = 0; i < TaskUtil.tasks_of_npc[npcname].length; i++){
		if (_root.taskAvailable(TaskUtil.tasks_of_npc[npcname][i])){
			for (var j = 0; j < _root.tasks_to_do.length; j++){
				if (_root.tasks_to_do[j].id == TaskUtil.tasks_of_npc[npcname][i]){
					return {result:"路过"};
				}
			}
			return {result:"接受任务", id:TaskUtil.tasks_of_npc[npcname][i]};
		}
	}
	return {result:"路过"};
}

_root.GetTask = function(id){
	for (var i = 0; i < _root.tasks_to_do.length; i++){
		if (_root.tasks_to_do[i].id == id){
			_root.发布消息("无法重复接受任务！");
			return false;
		}
	}
	_root.AddTask(id);
	_root.SetDialogue(TaskUtil.getTaskText(TaskUtil.getTaskData(id).get_conversation));
	_root.弹出公告界面.弹出新任务(id);
}

// 原名为taskFinished
_root.taskCompleteCheck = function(index){
	_root.任务完成提示._visible = false;
	var taskData = TaskUtil.getTaskData(_root.tasks_to_do[index].id);
	var requirements = _root.tasks_to_do[index].requirements;
	if (requirements.stages.length != 0){
		return false;
	}

	//目前逻辑为提交物品与持有物品不可兼容，优先判定提交物品
	if(!TaskUtil.checkItemRequirements(taskData)){
		return false;
	}
	//检查特殊需求
	if(!TaskUtil.checkSpecialRequirements(taskData)){
		return false;
	}
	_root.任务完成提示._visible = true;
	return true;
}

_root.taskAvailable = function(index){
	if (_root.tasks_finished[String(index)] > 0){
		return false;
	}
	for (var i = 0; i < _root.tasks_to_do.length; i++){
		if (_root.tasks_to_do[i].id == index){
			return false;
		}
	}
	var get_requirements = TaskUtil.getTaskData(index).get_requirements;
	for (var i = 0; i < get_requirements.length; i++){
		if (isNaN(_root.tasks_finished[get_requirements[i]]) || _root.tasks_finished[get_requirements[i]] < 1){
			return false;
		}
	}
	return true;
}

_root.FinishTask = function(index){
	var taskID = _root.tasks_to_do[index].id;
	var taskData = TaskUtil.getTaskData(taskID);
	var rewards = taskData.rewards;
	//检测挑战是否完成
	if(taskData.challenge.rewards.length > 0 && _root.tasks_to_do[index].requirements.challenge.finished == true){
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
	_root.UpdateTaskProgress(taskID);
	_root.tasks_to_do.splice(index,1);
	//检索是否可以接取任务链的下一个任务
	var isTaskInChain = false;
	var chainDict = TaskUtil.task_chains[taskData.chain[0]];
	var chainArray = TaskUtil.task_in_chains_by_sequence[taskData.chain[0]];
	var i = 0;
	while (i < chainArray.length){
		if (chainDict[chainArray[i]] == taskData.id){
			isTaskInChain = true;
			break;
		}
		i++;
	}
	if(isTaskInChain){
		var nextTaskID = chainDict[chainArray[i + 1]];
		var nextTaskNPC = TaskUtil.getTaskData(nextTaskID).get_npc;
		// 检查上个任务的交付NPC与下个任务的接取NPC是否相同
		if(nextTaskNPC == taskData.finish_npc && _root.taskAvailable(nextTaskID)){
			_root.GetTask(nextTaskID);
		}
	}
	_root.是否达成任务检测();
	return true;
}

_root.FinishStage = function(name, difficulty){
	for (var i in _root.tasks_to_do){
		var task = _root.tasks_to_do[i];
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
	_root.UpdateTaskProgress();
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
	for (var i = 0; i < _root.tasks_to_do.length; i++){
		if (_root.tasks_to_do[i].id == id){
			_root.发布消息("无法重复接受任务！");
			return false;
		}
	}
	var taskData = TaskUtil.getTaskData(id);
	var finish_requirements = TaskUtil.getTaskData(id).finish_requirements;
	var 关卡要求 = {};
	var stageArr = [];
	var i = 0;
	for (i in finish_requirements){
		var itemArr = finish_requirements[i].split("#");
		
		var stage = {};
		stage.name = itemArr[0];
		stage.difficulty = itemArr[1];
		stageArr.push(stage);
	}
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
	_root.tasks_to_do.push(task);
}

_root.DeleteTask = function(index){
	if (TaskUtil.getTaskData(_root.tasks_to_do[index].id).chain[0] == "主线"){
		_root.发布消息("无法删除主线任务！");
		return false;
	}
	_root.tasks_to_do.splice(index,1);
	_root.发布消息("删除任务成功！");
	return true;
}

_root.UpdateTaskProgress = function(id){
	if (id != null){
		var chain = TaskUtil.getTaskData(id).chain;
		if (!isNaN(chain[1]) && (_root.task_chains_progress[chain[0]] < chain[1] || _root.task_chains_progress[chain[0]] == null)){
			_root.task_chains_progress[chain[0]] = chain[1];
			_root.tasks_finished[String(id)] = 1;
		}else{
			if (isNaN(_root.tasks_finished[String(id)])){
				_root.tasks_finished[String(id)] = 1;
			}else{
				_root.tasks_finished[String(id)] += 1;
			}
		}
	}
	if (isNaN(_root.task_chains_progress.主线)){
		_root.task_chains_progress.主线 = 0;
	}
	_root.主线任务进度 = _root.task_chains_progress.主线;
	if (_root.主线任务进度 > 13){
		_root.后勤战备箱按钮._visible = true;
	}
}


// 检测对应任务是否已完成
_root.isTaskFinished = function(index):Boolean{
	 return _root.tasks_finished[String(index)] > 0;
}



_root.计算难度等级 = function(等级描述){
	if (等级描述 === "简单") return 1;
	if (等级描述 === "冒险") return 1.5;
	if (等级描述 === "修罗") return 2;
	if (等级描述 === "地狱") return 2.5;
	return 1;
}
_root.获取难度等级 = function(等级){
	if (等级 == 1) return "简单";
	if (等级 == 1.5) return "冒险";
	if (等级 == 2) return "修罗";
	if (等级 == 2.5) return "地狱";
	return "";
}

_root.点击npc后检测任务 = function(npc名字){
	var ret = NPCTaskCheck(npc名字);
	switch (ret.result){
		case "完成任务" :
			_root.FinishTask(ret.id);
			break;
		case "接受任务" :
			_root.GetTask(ret.id);
			break;
		case "路过" :
			break;
	}
	return ret.result;
}

_root.是否达成任务检测 = function(){
	for (var i in _root.tasks_to_do){
		if (_root.taskCompleteCheck(i)) return true;
	}
	return false;
}

_root.完成任务提示检测 = function(){
	是否达成任务检测();
}


_root.检测并添加初始任务 = function(){
	//如果同时满足 任务栏全空 初始任务未完成 主线进度为0，则获取初始任务
	var 是否获取初始任务 = _root.tasks_to_do.length == 0 && _root.tasks_finished[0] <= 0 && _root.主线任务进度 <= 0;
	if(是否获取初始任务){
		_root.新手引导界面._visible = true;
		_root.新手引导界面.gotoAndStop("任务面板");
		_root.GetTask(0);
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
// _root.task_history = [];
_root.可同时接的任务数 = 10;
_root.主线任务进度 = 0;


//#func:_root.tesktest()



// 特殊任务需求
TaskUtil.specialRequirements = new Object();

TaskUtil.specialRequirements.task = {
	describe: function(args){
		return "完成任务【" + TaskUtil.getTaskText(TaskUtil.getTaskData(args[1]).title)+"】";
	},
	check:function(args){
		return _root.isTaskFinished(args[1]);
	}
}

TaskUtil.specialRequirements.skill = {
	describe: function(args){
		return "技能【" + args[1] + "】达到" + args[2] + "级";
	},
	check:function(args){
		return (_root.根据技能名查找主角技能等级(args[1]) > args[2] - 1);
	}
}

TaskUtil.specialRequirements.infrastructure = {
	describe: function(args){
		return "基建项目【" + args[1] + "】达到" + args[2] + "级";
	},
	check:function(args){
		return _root.基建系统.检查基建等级(args[1], args[2]);
	}
}
