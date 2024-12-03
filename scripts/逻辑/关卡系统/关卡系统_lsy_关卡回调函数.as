_root.关卡回调函数 = new Object();

_root.关卡回调函数.新手练习场_1 = function(){
	_root.新手引导界面.显示指引("拾取",800);
	_root.创建可拾取物("金钱",10,800,400,false);
}

_root.关卡回调函数.新手练习场_2 = function(){
	_root.新手引导界面.显示指引("奔跑");
}

_root.关卡回调函数.AVP_重设光照 = function(最大光照,最小光照){
	if(_root.难度等级 >= 2){
		_root.天气系统.无限过图环境信息.最大光照 = 最大光照;
		_root.天气系统.无限过图环境信息.最小光照 = 最小光照;
	}
}

_root.关卡回调函数.贫民窟_3 = function(){
	_root.创建可拾取物("资料",5,1438,400,false);
}

_root.关卡回调函数.贫民窟_6 = function(){
	var 事件mc = _root.gameworld.createEmptyMovieClip("事件_贫民窟_6",_root.gameworld.getNextHighestDepth());
	事件mc.onEnterFrame = function(){
		var 控制对象 = _root.gameworld[_root.控制目标];
		if(!控制对象) return;
		if(控制对象._x < 300){
			_root.生存模式OBJ.FinishRequirement = 99;
			delete this.onEnterFrame;
			this.removeMovieClip();
		}
	}
}