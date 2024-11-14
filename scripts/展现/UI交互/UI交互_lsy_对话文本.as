_root.对话赋值到对话框 = function(内容数组)
{
	var _loc3_ = 0;
	while (_loc3_ < 内容数组.length)
	{
		_root.对话框界面.本轮对话内容.push(内容数组[_loc3_]);
		_loc3_ += 1;
	}
	_root.对话框界面.对话进度 = 0;
	_root.对话框界面.对话条数 += 内容数组.length;
	_root.对话框界面.gotoAndStop(1);
}

_root.对话覆盖赋值到对话框 = function(内容数组)
{
	_root.对话框界面.本轮对话内容 = [];
	var _loc3_ = 0;
	while (_loc3_ < 内容数组.length)
	{
		_root.对话框界面.本轮对话内容.push(内容数组[_loc3_]);
		_loc3_ += 1;
	}
	_root.对话框界面.对话进度 = 0;
	_root.对话框界面.对话条数 = 内容数组.length;
	_root.对话框界面.gotoAndStop(1);
}

_root.getDialogueSpecialString = function(str)
{
	if (str == "$PC")
	{
		return _root.角色名;
	}
	// 
	if (str == "$PC_TITLE")
	{
		return _root.玩家称号;
	}
	if (str == "$PC_CHAR")
	{
		return "玩家";
	}
	return str;
};

_root.getDifficultyString = function(str)
{
	switch (str)
	{
		case "简单" :
			return '<font color="#0099cc">简单</font>';
		case "冒险" :
			return '<font color="#22bb00">冒险</font>';
		case "修罗" :
			return '<font color="#ddaa00">修罗</font>';
		case "地狱" :
			return '<font color="#cc0000">地狱</font>';
	}
	return str;
};

_root.组装单次对话 = function(arr:Array){
	var 输出对话 = new Array(arr.length);
	for (var i = 0; i < arr.length; i++)
	{
		var char = arr[i].char.split("#");
		char[0] = getDialogueSpecialString(char[0]);
		var 对话 = new Array(6);
		对话[0] = getDialogueSpecialString(arr[i].name);
		对话[1] = getDialogueSpecialString(arr[i].title);
		对话[2] = getDialogueSpecialString(char[0]);
		对话[3] = arr[i].text;
		对话[4] = char[1] ? char[1] : "普通";
		对话[5] = arr[i].target;
		对话[6] = arr[i].imageurl;
		输出对话[i] = 对话;
	}
	return 输出对话;
}

_root.SetDialogue = function(arr, 是否覆盖已有对话)
{
	if (arr.__proto__ == String.prototype)
	{
		SetDialogue(getTaskText(arr));
		return;
	}
	var 输出对话 = _root.组装单次对话(arr);
	if (是否覆盖已有对话)
	{
		_root.对话覆盖赋值到对话框(输出对话);
	}
	else
	{
		_root.对话赋值到对话框(输出对话);
	}
}

_root.组装多语版任务对话 = function(任务属性, 任务名, 任务前后, 原装对话)
{
	var _loc6_ = [];
	var _loc7_ = 0;
	while (_loc7_ < 原装对话.length)
	{
		_loc6_.push([原装对话[_loc7_][0], 原装对话[_loc7_][1], 原装对话[_loc7_][2], _root.json多语言任务对话数据[任务属性 + "【" + 任务名 + "】任务" + 任务前后 + "对话" + _loc7_], 原装对话[_loc7_][4]]);
		_loc7_ += 1;
	}
	return _loc6_;
}
_root.组装多语版NPC随机对话 = function(NPC名字, 原装对话, 随机数)
{
	var _loc5_ = [];
	var _loc6_ = 0;
	while (_loc6_ < 原装对话[随机数].length)
	{
		_loc5_.push([原装对话[随机数][_loc6_][0], 原装对话[随机数][_loc6_][1], 原装对话[随机数][_loc6_][2], _root.json多语言任务对话数据[NPC名字 + "默认对话" + 随机数 + "_" + _loc6_], 原装对话[随机数][_loc6_][4]]);
		_loc6_ += 1;
	}
	return _loc5_;
}
_root.组装多语版佣兵随机对话 = function(索引文字, 原装对话)
{
	var _loc4_ = [];
	var _loc5_ = 0;
	while (_loc5_ < 原装对话.length)
	{
		_loc4_.push([原装对话[_loc5_][0], 原装对话[_loc5_][1], 原装对话[_loc5_][2], _root.json多语言任务对话数据[索引文字], "普通"]);
		_loc5_ += 1;
	}
	return _loc4_;
}


_root.获取游戏提示文本 = function (){
	var 提示文本列表 = _root.提示文本列表;
	var 权重表 = new Array();
	for(var i = 0; i < 提示文本列表.length; i++){
		var 文本组 = 提示文本列表[i];
		if(文本组.Unlock <= 0 || 文本组.Unlock < _root.主线任务进度){
			权重表.push({对象:文本组.Text,权重:文本组.Text.length});
		}
	}
	var 选中文本组 = _root.根据权重获取随机对象(权重表).对象;
	return _root.随机选择数组元素(选中文本组);
}
