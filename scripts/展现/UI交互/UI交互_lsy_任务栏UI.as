_root.任务栏UI函数 = new Object();

_root.任务栏UI函数.打印任务明细 = function(id){
	var taskData = _root.getTaskData(id);
	var str = _root.getTaskText(taskData.title) + "\n";
	//任务描述
	str += "\t";
	str += _root.getTaskText(taskData.description);
	str += "\n";
	//任务需求
	if(taskData.finish_requirements.length > 0){
		str += "- 需要通过关卡 -\n";
		for (var i = 0; i < taskData.finish_requirements.length; i++){
			var requirementArr = taskData.finish_requirements[i].split("#");
			str += requirementArr[0] + "(" + _root.getDifficultyString(requirementArr[1]) + ")" + "  ";
		}
		str += "\n";
	}
	if(taskData.finish_submit_items.length > 0){
		str += "- 需要提交物品 -\n";
		for (var i = 0; i < taskData.finish_submit_items.length; i++){
			var requirementArr = taskData.finish_submit_items[i].split("#");
			str += requirementArr[0] + "*" + requirementArr[1] + "  ";
		}
		str += "\n";
	}
	str += "提交NPC：" + taskData.finish_npc + "\n";
	//奖励
	str += "- 奖励 -\n";
	for (var i = 0; i < taskData.rewards.length; i++){
		rewardArr = taskData.rewards[i].split("#");
		str += _root.getItemData(rewardArr[0]).displayname + "*" + rewardArr[1] + ", ";
	}
	return str;
}

_root.任务栏UI函数.打印任务挑战明细 = function(id){
}