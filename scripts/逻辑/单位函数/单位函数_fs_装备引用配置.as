_root.装备引用配置 = {};

_root.装备引用配置.配置装扮 = function(影片剪辑, 配置装扮, 实例名, 引用名)
{
    var 自机 = 影片剪辑._parent._parent._parent;
    var 装扮 = 影片剪辑.attachMovie(配置装扮,实例名,影片剪辑.getNextHighestDepth());

    自机[引用名] = 装扮 ? 装扮 : null;
    //_root.服务器.发布服务器消息(影片剪辑 + " " + 实例名 + " " + 引用名 + " " + 配置装扮 + " " + 配置装扮 + " " + 自机[引用名])
    return 自机[引用名];
}


/*
var 装扮 = _root.装备引用配置.配置装扮(this, _parent._parent._parent.左手, "装扮", "左手_引用");

onClipEvent(load){
	var 自机 = _parent._parent._parent;
	var 装扮 = _root.装备引用配置.配置装扮(this, 自机.屁股, "装扮", "屁股_引用");
	if (装扮)
	{
		this.基本款._visible = false;
	}
	else if (自机.性别 == "女")
	{
		_root.装备引用配置.配置装扮(this, "女变装-裸体屁股", "装扮", "屁股_引用");
		this.基本款._visible = false;
	}
}

onClipEvent (load) {
	this.基本款._visible = 0;
	var 长枪 = _parent._parent._parent.长枪_装扮;
	if (长枪 != undefined)
	{
		_root.装备引用配置.配置装扮(this,长枪,"装扮","长枪_引用");
	}

}

*/