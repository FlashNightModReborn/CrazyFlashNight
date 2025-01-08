_root.任务栏UI函数 = new Object();


_root.任务栏UI函数.打印物品列表 = function(itemList):String{
	var str = "";
	for (var i = 0; i < itemList.length; i++){
		var requirementArr = itemList[i].split("#");
		str += requirementArr[0] + "*" + requirementArr[1] + "  ";
	}
	str += "\n";
	return str;
}

_root.任务栏UI函数.打印任务明细 = function(id):String{
	var taskData = _root.getTaskData(id);
	var str = _root.getTaskText(taskData.title) + "\n";
	//任务描述
	str += "\t";
	str += _root.getTaskText(taskData.description);
	str += "\n";
	//任务需求
	if(taskData.finish_requirements.length > 0){
		str += "- 关卡需求 -\n";
		for (var i = 0; i < taskData.finish_requirements.length; i++){
			var requirementArr = taskData.finish_requirements[i].split("#");
			str += requirementArr[0] + "(" + _root.getDifficultyString(requirementArr[1]) + ")" + "  ";
		}
		str += "\n";
	}
	if(taskData.finish_submit_items.length > 0 || taskData.finish_contain_items.length > 0){
		str += "- 物品需求 -\n";
	}
	if(taskData.finish_submit_items.length > 0){
		str += "需提交："
		str += _root.任务栏UI函数.打印物品列表(taskData.finish_submit_items);
	}
	if(taskData.finish_contain_items.length > 0){
		str += "需持有："
		str += _root.任务栏UI函数.打印物品列表(taskData.finish_contain_items);
	}
	str += "提交NPC：" + taskData.finish_npc + "\n";
	//奖励
	str += "- 奖励 -\n";
	str += _root.任务栏UI函数.打印物品列表(taskData.rewards);
	return str;
}

_root.任务栏UI函数.打印任务挑战明细 = function(id){
	var challenge = _root.getTaskData(id).challenge;
	str = "挑战模式【难度：" + _root.getDifficultyString(challenge.difficulty) + "】\n";
	if(challenge.description) str += "* " + challenge.description + "\n";
	str += "额外奖励："
	str +=_root.任务栏UI函数.打印物品列表(challenge.rewards);
	return str;
}
