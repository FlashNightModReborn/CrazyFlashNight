if(_root.基建系统 == null) _root.基建系统 = new Object();
_root.基建系统.infrastructure = new Object();

_root.基建系统.初始化基建元件 = function(target:MovieClip, key:String, args:Array):Void{
	target.stop();
	if(_root.基建系统.dict[key] == null) return;
	// 对目标基建等级进行排序
	args = org.flashNight.naki.Sort.QuickSort.adaptiveSort(args, function(a, b) {
        return a[0] - b[0]; // Numeric comparison
    });
	target.基建项目 = key;
	target.基建等级列表 = args;
	if(this.infrastructure[target.基建项目] == null){
		this.infrastructure[target.基建项目] = 0;
		// 弹出提示
		_root.发布消息("发现新的基建项目：" + key);
	}
	_root.基建系统.更新基建元件(target);
}

_root.基建系统.更新基建元件 = function(target:MovieClip):Void{
	var currentLevel = isNaN(this.infrastructure[target.基建项目]) ? 0 : this.infrastructure[target.基建项目];
	// 逐个检索基建等级是否高于目标等级
	var i = 0;
	for(i = 0; i < target.基建等级列表.length; i++){
		if(currentLevel < target.基建等级列表[i][0]) break;
	}
	if(i == 0){
		target._visible = false; // 若不满足最低等级则直接隐藏
	}else{
		target.gotoAndStop(target.基建等级列表[i-1][1]); // 否则，跳转到指定的帧
	}
}

_root.基建系统.检查基建等级 = function(key:String, level:Number):Boolean{
	return (_root.基建系统.infrastructure[key] > 0 && _root.基建系统.infrastructure[key] >= level);
}

/*
初始化基建元件示例：
_root.基建系统.初始化基建元件(this, "厨房", [
	[1,"锅"],
	[2,"大锅"],
	[3,"超大锅"]
]);
*/


