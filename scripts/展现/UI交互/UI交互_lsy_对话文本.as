import org.flashNight.arki.unit.*;

_root.对话赋值到对话框 = function(内容数组){
	var i = 0;
	while (i < 内容数组.length){
		_root.对话框界面.本轮对话内容.push(内容数组[i]);
		i++;
	}
	_root.对话框界面.对话进度 = 0;
	_root.对话框界面.对话条数 += 内容数组.length;
	_root.对话框界面.gotoAndStop("open");
}

_root.对话覆盖赋值到对话框 = function(内容数组){
	_root.对话框界面.本轮对话内容 = [];
	var i = 0;
	while (i < 内容数组.length){
		_root.对话框界面.本轮对话内容.push(内容数组[i]);
		i++;
	}
	_root.对话框界面.对话进度 = 0;
	_root.对话框界面.对话条数 = 内容数组.length;
	_root.对话框界面.gotoAndStop("open");
}

_root.getDialogueSpecialString = function(str){
	if (str == "$PC") return _root.角色名;
	if (str == "$PC_TITLE") return HeroUtil.getHeroTitle();
	if (str == "$PC_CHAR") return "玩家";
	return str;
};

_root.getDifficultyString = function(str){
	switch (str){
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
	for (var i = 0; i < arr.length; i++){
		var char = arr[i].char.split("#");
		char[0] = getDialogueSpecialString(char[0]);
		var 对话 = new Array(7);
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

_root.SetDialogue = function(arr, 是否覆盖已有对话){
	if (arr.__proto__ == String.prototype){
		SetDialogue(getTaskText(arr));
		return;
	}
	var 输出对话 = _root.组装单次对话(arr);
	if (是否覆盖已有对话 == true){
		_root.对话覆盖赋值到对话框(输出对话);
	}else{
		_root.对话赋值到对话框(输出对话);
	}
}

/*
_root.组装多语版任务对话 = function(任务属性, 任务名, 任务前后, 原装对话){
	var arr = [];
	var i = 0;
	while (i < 原装对话.length){
		arr.push([原装对话[i][0], 原装对话[i][1], 原装对话[i][2], _root.json多语言任务对话数据[任务属性 + "【" + 任务名 + "】任务" + 任务前后 + "对话" + i], 原装对话[i][4]]);
		i += 1;
	}
	return arr;
}
_root.组装多语版NPC随机对话 = function(NPC名字, 原装对话, 随机数){
	var arr = [];
	var i = 0;
	while (i < 原装对话[随机数].length){
		arr.push([原装对话[随机数][i][0], 原装对话[随机数][i][1], 原装对话[随机数][i][2], _root.json多语言任务对话数据[NPC名字 + "默认对话" + 随机数 + "_" + i], 原装对话[随机数][i][4]]);
		i += 1;
	}
	return arr;
}
_root.组装多语版佣兵随机对话 = function(索引文字, 原装对话){
	var arr = [];
	var i = 0;
	while (i < 原装对话.length){
		arr.push([原装对话[i][0], 原装对话[i][1], 原装对话[i][2], _root.json多语言任务对话数据[索引文字], "普通"]);
		i += 1;
	}
	return arr;
}
*/

_root.获取游戏提示文本 = function(){
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

_root.处理html剧情文本 = function(str:String){
	//消除空格换两行的问题
	str = str.split("\r\n").join("<BR>");
	//将"$PC_NAME"替换为玩家名称
	if(_root.角色名) str = str.split("${PC_NAME}").join(_root.角色名);
	return str;
}

_root.加密html剧情文本 = function(str:String, encryptReplace, encryptCut){
	//替换文本
	if(encryptReplace != null){
		var replaceArr = [];
		for(var key in encryptReplace){
			replaceArr.push(key);
		}
		// 使用稳定排序TimSort，确保相同长度的key保持原始顺序
		replaceArr = org.flashNight.naki.Sort.TimSort.sort(replaceArr, function(a, b) {
			return b.length - a.length; //按字符串长度倒序排列
		});
		for(var i=0; i<replaceArr.length; i++){
			var replaceStr = encryptReplace[replaceArr[i]];
			if(replaceStr == null) replaceStr = "";
			str = str.split(replaceArr[i]).join(replaceStr);
		}
	}
	//截断文本
	if(encryptCut != null){
		var cutArr = [];
		for(var key in encryptCut){
			cutArr.push(key);
		}
		// 使用稳定排序TimSort，确保相同长度的key保持原始顺序
		cutArr = org.flashNight.naki.Sort.TimSort.sort(cutArr, function(a, b) {
			return b.length - a.length; //按字符串长度倒序排列
		});
		for(var i=0; i<cutArr.length; i++){
			var cutStr = encryptCut[cutArr[i]];
			if(cutStr == null) cutStr = "";
			var strSplit = str.split(cutArr[i]);
			if(strSplit.length > 1) str = strSplit[0] + cutStr;
		}
	}
	return str;
}
