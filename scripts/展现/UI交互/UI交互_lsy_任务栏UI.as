import org.flashNight.arki.item.itemIcon.*;
import org.flashNight.arki.task.*;

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

_root.任务栏UI函数.打印限制词条明细 = function(entryArray):String{
	var str = "";
	for (var i = 0; i < entryArray.length; i++){
		str += "- " + _root.限制系统.getDiscription(entryArray[i]);
		str += "\n";
	}
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
	if(challenge.limitations) str += _root.任务栏UI函数.打印限制词条明细(challenge.limitations);
	if(challenge.description) str += "* " + challenge.description + "\n";
	str += "额外奖励："
	str +=_root.任务栏UI函数.打印物品列表(challenge.rewards);
	return str;
}

_root.任务栏UI函数.显示任务明细 = function(index){
	var taskData = _root.getTaskData(_root.tasks_to_do[index].id);
	this.taskName.htmlText = _root.getTaskText(taskData.title);
	this.taskDesc.htmlText = _root.getTaskText(taskData.description);
	//关卡需求
	this.关卡需求._visible = true;
	if(taskData.finish_requirements == null){
		this.关卡需求.taskStage.htmlText = "无";
	}else{
		var stageText = "";
		for (var i = 0; i < taskData.finish_requirements.length; i++){
			var itemArr = taskData.finish_requirements[i].split("#");
			stageText += itemArr[0] + "(" + _root.getDifficultyString(itemArr[1]) + ")" + "  ";
			this.关卡需求.taskStage.htmlText = stageText;
		}
	}
	this.关卡需求.完成标志._visible = _root.tasks_to_do[index].requirements.stages.length <= 0;
	//记录关卡需求容器的位置，以决定接下来面板的位置
	var 容器位置 = this.关卡需求._y;
	//提交物品
	if(taskData.finish_submit_items == null){
		this.提交物品._visible = false;
	}else{
		容器位置 += 40;
		this.提交物品._visible = true;
		this.提交物品._y = 容器位置;
		for(var i = 0; i < this.提交物品.iconList.length; i++){
			this.提交物品.iconList[i].removeMovieClip();
		}
		this.提交物品.iconList = new Array();
		for (var i = 0; i < taskData.finish_submit_items.length; i++){
			var itemArr = taskData.finish_submit_items[i].split("#");
			var 物品图标 = this.提交物品.attachMovie("物品图标","物品图标" + i, i);
			物品图标._x = 140 + i * 36;
			物品图标._y = 16;
			物品图标.itemIcon = new ItemIcon(物品图标, itemArr[0], Number(itemArr[1]));
			this.提交物品.iconList.push(物品图标);
		}
		this.提交物品.完成标志._visible = TaskUtil.containTaskItems(taskData.finish_submit_items);
	}
	//持有物品
	if(taskData.finish_contain_items == null){
		this.持有物品._visible = false;
	}else{
		容器位置 += 40;
		this.持有物品._visible = true;
		this.持有物品._y = 容器位置;
		for(var i = 0; i < this.持有物品.iconList.length; i++){
			this.持有物品.iconList[i].removeMovieClip();
		}
		this.持有物品.iconList = new Array();
		for (var i = 0; i < taskData.finish_contain_items.length; i++){
			var itemArr = taskData.finish_contain_items[i].split("#");
			var 物品图标 = this.持有物品.attachMovie("物品图标","物品图标" + i, i);
			物品图标._x = 140 + i * 36;
			物品图标._y = 16;
			物品图标.itemIcon = new ItemIcon(物品图标, itemArr[0], Number(itemArr[1]));
			this.持有物品.iconList.push(物品图标);
		}
		this.持有物品.完成标志._visible = TaskUtil.containTaskItems(taskData.finish_contain_items);
	}
	//奖励
	容器位置 += 60;
	this.任务奖励._visible = true;
	this.任务奖励._y = 容器位置;
	this.任务奖励.taskFinishNPC.htmlText = "提交NPC：" + taskData.finish_npc;
	for(var i = 0; i < this.任务奖励.iconList.length; i++){
		this.任务奖励.iconList[i].removeMovieClip();
	}
	this.任务奖励.iconList = new Array();
	for (var i = 0; i < taskData.rewards.length; i++){
		var itemArr = taskData.rewards[i].split("#");
		var 物品图标 = this.任务奖励.attachMovie("物品图标","物品图标" + i, i);
		物品图标._x = 20 + i * 36;
		物品图标._y = 60;
		物品图标.itemIcon = new ItemIcon(物品图标, itemArr[0], Number(itemArr[1]));
		this.任务奖励.iconList.push(物品图标);
	}
}

_root.任务栏UI函数.隐藏任务明细 = function(){
	this.taskName.htmlText = "";
	this.taskDesc.htmlText = "";
	this.关卡需求._visible = false;
	this.提交物品._visible = false;
	this.持有物品._visible = false;
	this.任务奖励._visible = false;
}

_root.任务栏UI函数.创建任务树 = function(){
}