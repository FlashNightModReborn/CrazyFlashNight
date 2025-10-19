import org.flashNight.arki.item.itemIcon.*;
import org.flashNight.arki.task.*;

_root.任务栏UI函数 = new Object();

//文本相关函数
_root.任务栏UI函数.打印物品列表 = function(itemList):String{
	var list = [];
	for(var i=0; i<itemList.length; i++){
		var itemArr = itemList[i].split("#");
		var itemData = _root.getItemData(itemArr[0]);
		var str = itemData.displayname;
		if(itemData.type == "武器" || itemData.type == "防具"){
			if(itemArr[1] > 1) str += "[+" + itemArr[1] + "]";
		}else{
			str += "*" + itemArr[1];
		}
		list.push(str);
	}
	return list.join("  ") + "\n";
}

_root.任务栏UI函数.打印限制词条明细 = function(entryArray,limitLevel):String{
	var str = "";
	for (var i = 0; i < entryArray.length; i++){
		str += "- " ;
		if(limitLevel){
			str += "[" + _root.获取难度等级(limitLevel) + "难度]";
		}
		str +=  _root.限制系统.getDiscription(entryArray[i]);
		str += "\n";
	}
	return str;
}

_root.任务栏UI函数.打印任务明细 = function(id):String{
	var taskData = TaskUtil.getTaskData(id);
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
	if(taskData.finish_submit_items.length > 0){
		str += "- 提交物品 -\n";
		str += _root.任务栏UI函数.打印物品列表(taskData.finish_submit_items);
	}else if(taskData.finish_contain_items.length > 0){
		str += "- 持有物品 -\n";
		str += _root.任务栏UI函数.打印物品列表(taskData.finish_contain_items);
	}
	str += "提交NPC：" + taskData.finish_npc + "\n";
	//奖励
	str += "- 奖励 -\n";
	str += _root.任务栏UI函数.打印物品列表(taskData.rewards);
	return str;
}

_root.任务栏UI函数.打印任务挑战明细 = function(id){
	var challenge = TaskUtil.getTaskData(id).challenge;
	str = "挑战模式【难度：" + _root.getDifficultyString(challenge.difficulty) + "】\n";
	if(challenge.limitations) str += _root.任务栏UI函数.打印限制词条明细(challenge.limitations);
	if(challenge.description) str += "* " + challenge.description + "\n";
	str += "额外奖励："
	if(challenge.rewards) str +=_root.任务栏UI函数.打印物品列表(challenge.rewards);
	if(challenge.rewards_text) str +=  challenge.rewards_text + '\n';
	if(challenge.recommended_level){
		str += "推荐等级：" + challenge.recommended_level;
	} 
	return str;
}

_root.任务栏UI函数.打印任务对话 = function(taskText){
	var str = "";
	for(var i=0; i<taskText.length; i++){
		str += _root.getDialogueSpecialString(taskText[i].name) + "：" + taskText[i].text + "\n";
	}
	return str;
}



//UI逻辑相关函数
_root.任务栏UI函数.显示任务明细 = function(index){
	// 检查任务是否存在
	if(!_root.tasks_to_do[index]){
		// 获取当前主线进度，显示对应的引导信息
		var 主线进度 = _root.task_chains_progress.主线 || 0;
		var guide = TaskUtil.getProgressGuide(主线进度);

		if(guide){
			// 显示引导信息
			this.任务标题 = guide.title;
			this.任务信息.clearDescription();
			this.任务信息.typeDescription(guide.description);
		}else{
			// 没有引导数据时的默认处理
			this.任务标题 = "";
			this.任务信息.clearDescription();
		}

		// 清空关卡需求显示
		var 关卡需求图标 = this.关卡需求.关卡需求图标;
		关卡需求图标.stageName.htmlText = "";
		关卡需求图标.关卡难度标志._visible = false;
		关卡需求图标.完成标志._visible = false;
		// 清空物品需求显示
		var 物品需求图标 = this.物品需求.物品需求图标;
		物品需求图标.itemType.text = "";
		物品需求图标.物品展示框.itemInfo = "";
		物品需求图标.完成标志._visible = false;
		// 清空奖励显示
		this.任务奖励.rewards = [];
		this.任务奖励.refresh();
		// 清空提交NPC
		this.提交NPC界面.finish_npc = "";
		return;
	}
	var taskData = TaskUtil.getTaskData(_root.tasks_to_do[index].id);
	this.任务标题 = _root.getTaskText(taskData.title);
	this.任务详情.refresh();
	this.任务信息.typeDescription(_root.getTaskText(taskData.description));
	//关卡需求
	var 关卡需求图标 = this.关卡需求.关卡需求图标;
	if(taskData.finish_requirements.length <= 0){
		关卡需求图标.stageName.htmlText = "无需通过关卡";
		关卡需求图标.关卡难度标志._visible = false;
	}else{
		var itemArr = taskData.finish_requirements[0].split("#");
		关卡需求图标.stageName.htmlText = itemArr[0]; //  + "[" + _root.getDifficultyString(itemArr[1]) + "]"
		关卡需求图标.关卡难度标志._visible = true;
		关卡需求图标.关卡难度标志.gotoAndStop(itemArr[1]);
	}
	if(_root.tasks_to_do[index].requirements.stages.length <= 0){
		关卡需求图标.完成标志._visible = true;
		关卡需求图标.完成标志.gotoAndPlay(1);
	}else{
		关卡需求图标.完成标志._visible = false;
		关卡需求图标.完成标志.stop();
	}
	
	//提交物品
	var 物品需求图标 = this.物品需求.物品需求图标;
	for(var i = 0; i < 物品需求图标.iconList.length; i++){
		物品需求图标.iconList[i].removeMovieClip();
	}
	var items = null;
	if(taskData.finish_submit_items.length > 0){
		物品需求图标.itemType.text = "提交物品";
		items = taskData.finish_submit_items;
	}else if(taskData.finish_contain_items.length > 0){
		物品需求图标.itemType.text = "持有物品";
		items = taskData.finish_contain_items;
	}
	if(items.length > 0){
		var 物品展示框 = 物品需求图标.物品展示框;
		物品需求图标.iconList = new Array();
		for (var i = 0; i < items.length; i++){
			var itemArr = items[i].split("#");

			_root.帧计时器.添加单次任务(function(count) {
				var 物品图标 = 物品展示框.attachMovie("物品图标","物品图标" + count, count);
				物品图标._x = 10 + count * 20;
				物品图标._y = 10;
				物品图标._xscale = 物品图标._yscale = 75;
				物品图标.itemIcon = new ItemIcon(物品图标, itemArr[0], Number(itemArr[1]));
				物品需求图标.iconList.push(物品图标);
			},(i + 1) * 500, i);
		}
		if(items.length == 1){
			var itemArr = items[0].split("#");
			var itemData = _root.getItemData(itemArr[0]);
			var str = itemData.displayname;
			if(itemData.type == "武器" || itemData.type == "防具"){
				if(itemArr[1] > 1) str += "[+" + itemArr[1] + "]";
			}else{
				str += "*" + itemArr[1];
			}
			物品展示框.itemInfo = str;
		}else{
			物品展示框.itemInfo = "";
		}
		if(TaskUtil.containTaskItems(items)){
			物品需求图标.完成标志._visible = true;
			物品需求图标.完成标志.gotoAndPlay(1);
		}else{
			物品需求图标.完成标志._visible = false;
			物品需求图标.完成标志.stop();
		}
	}else{
		物品需求图标.itemType.text = "提交物品";
		物品需求图标.物品展示框.itemInfo = "无需提交物品";
		物品需求图标.完成标志._visible = true;
		物品需求图标.完成标志.gotoAndPlay(1);
	}
	//奖励
	this.任务奖励.rewards = taskData.rewards;
	this.任务奖励.refresh();
	// this.任务奖励.taskFinishNPC.htmlText = "提交NPC：" + taskData.finish_npc;
	this.提交NPC界面.finish_npc = taskData.finish_npc;

	var NPC头像框:MovieClip = this.提交NPC界面.提交NPC.NPC头像框;
	NPC头像框._visible = false;
	_root.帧计时器.添加单次任务(function() {
		NPC头像框._visible = true;
		_root.对话框UI.刷新NPC头像(NPC头像框, taskData.finish_npc);
	}, 33)
	
}

_root.任务栏UI函数.隐藏任务明细 = function(){
	this.taskName.htmlText = "";
	this.taskDesc.htmlText = "";
	this.关卡需求._visible = false;
	this.提交物品._visible = false;
	this.持有物品._visible = false;
	this.任务奖励._visible = false;
}

_root.任务栏UI函数.创建任务奖励图标 = function(){
	for (var i = 0; i < this.rewards.length; i++){
		var itemArr = this.rewards[i].split("#");
		var 物品图标 = this["奖励图标" + i].底框.底框图形.attachMovie("物品图标","物品图标", 0);
		物品图标._x = 15;
		物品图标._y = 15;
		物品图标.itemIcon = new ItemIcon(物品图标, itemArr[0], Number(itemArr[1]));
		this.任务奖励.iconList.push(物品图标);
	}
}

_root.任务栏UI函数.创建任务树 = function(){
	this.任务树.initX = this.任务树._x;
	this.任务树.initY = this.任务树._y;
	this.任务树.setMask(this.遮罩);
	var 任务节点图标 = this.任务树.任务节点图标;
	this.创建主线任务树();
	var x = 1;
	for(var key in _root.task_chains_progress){
		if(key != "主线" && key != "委托"){
			this.创建支线任务树(key, x);
			x = -x;
			if(x > 0) x++;
		}
	}
	//
	任务节点图标._visible = false;
	this.任务对话按钮._visible = false;
	this.任务完成对话按钮._visible = false;
}

_root.任务栏UI函数.创建主线任务树 = function(){
	var 任务节点图标 = this.任务树.任务节点图标;
	var 任务进度 = _root.task_chains_progress.主线;
	if(!任务进度) return;
	var chainArr = TaskUtil.task_in_chains_by_sequence.主线;
	var chainObj = TaskUtil.task_chains.主线;
	if(任务进度 > chainArr.length) 任务进度 = chainArr.length;
	for(var i = 0; i < 任务进度; i++){
		var taskID = chainObj[chainArr[i]];
		var taskData = TaskUtil.getTaskData(taskID);
		this.创建任务节点("主线", taskID, 0, taskID);
	}
}

_root.任务栏UI函数.创建支线任务树 = function(chainName, x){
	var 任务节点图标 = this.任务树.任务节点图标;
	var 任务进度 = _root.task_chains_progress[chainName];
	if(!任务进度) return;
	var chainArr = TaskUtil.task_in_chains_by_sequence[chainName];
	var chainObj = TaskUtil.task_chains[chainName];
	if(任务进度 > chainArr.length) 任务进度 = chainArr.length;
	var y = 0; //基准y位置
	for(var i = 0; i < 任务进度; i++){
		y++; //基准y位置至少加1
		var taskID = chainObj[chainArr[i]];
		var taskData = TaskUtil.getTaskData(taskID);
		for(var j=0; j<taskData.get_requirements.length; j++){
			var requirementID = taskData.get_requirements[j];
			if(TaskUtil.getTaskData(requirementID).chain[0] == "主线" && requirementID > y){
				y = requirementID;
				break;
			}
		}
		this.创建任务节点(chainName, taskID, x, y);
	}
}

_root.任务栏UI函数.创建任务节点 = function(chainName, taskID, x, y){
	var 任务节点图标 = this.任务树.任务节点图标;
	var taskData = TaskUtil.getTaskData(taskID);
	var 新节点 = 任务节点图标.duplicateMovieClip(chainName + "任务节点图标" + i,this.任务树.getNextHighestDepth());
	新节点.taskChain.text = taskData.chain.join("#");
	新节点._x = x * 100;
	新节点._y = y * 30;
	新节点.taskID = taskID;
}

_root.任务栏UI函数.显示事件日志任务明细 = function(taskID){
	this.taskDetail.htmlText = _root.任务栏UI函数.打印任务明细(taskID);
	var get_conversation = TaskUtil.getTaskText(TaskUtil.getTaskData(taskID).get_conversation);
	if(get_conversation.length > 0){
		this.任务对话按钮._visible = true;
		this.任务对话按钮.taskText = get_conversation;
	}else{
		this.任务对话按钮._visible = false;
		this.任务对话按钮.taskText = null;
	}
	var finish_conversation = TaskUtil.getTaskText(TaskUtil.getTaskData(taskID).finish_conversation);
	if(finish_conversation.length > 0){
		this.任务完成对话按钮._visible = true;
		this.任务完成对话按钮.taskText = finish_conversation;
	}else{
		this.任务完成对话按钮._visible = false;
		this.任务完成对话按钮.taskText = null;
	}
}

_root.任务栏UI函数.拖拽任务树 = function(){
	//定义窗体基础大小与padding以计算拖拽范围
	var x = this.任务树.initX;
	var y = this.任务树.initY;
	var baseWidth = 560;
	var halfWidth = baseWidth / 2;
	var baseHeight = 480;
	var paddingX = 0;
	var paddingY = 20;
	var rect = this.任务树.getRect(this.任务树);
	var left = rect.xMax > halfWidth ? halfWidth - rect.xMax : 0;
	var right = -rect.xMin > halfWidth ? halfWidth + rect.xMin : 0;
	var top = rect.yMax > baseHeight ? baseHeight - rect.yMax: 0;
	var bottom = 0;
	this.任务树.startDrag(false, x + left, y + top, x + right, y + bottom);
}

_root.任务栏UI函数.停止拖拽任务树 = function(){
	this.任务树.stopDrag();
}
