_root.加载后景 = function(环境信息){
	var 禁用天空 = 环境信息.空间情况 == "室内" || 环境信息.禁用天空;
	_root.天空盒.默认天空._visible = !禁用天空;
	if(禁用天空 && !环境信息.后景){
		_root.启用后景 = false;
		return;
	}
	_root.启用后景 = true;
	_root.天空盒.地平线高度 = 环境信息.地平线高度;
	if(!环境信息.后景){
		_root.卸载后景();
		return;
	}
	if(!_root.天空盒.后景列表) {
		_root.天空盒.后景列表 = [];
		_root.天空盒.后景移动速度列表 = [];
	}
	//对后景进行排序
	var maxSpeedRate = 32;
	for(var i = 0; i<环境信息.后景.length; i++){
		var url = "flashswf/skybox/" + 环境信息.后景[i].url;
		var speedrate = 环境信息.后景[i].SpeedRate;
		if(speedrate > maxSpeedRate - 1) speedrate = maxSpeedRate - 1;
		var depth = speedrate <= 0 ? 0 : maxSpeedRate - speedrate;
		var 后景mc = _root.天空盒.createEmptyMovieClip("后景"+i, depth);
		后景mc.loadMovie(url);
		_root.天空盒.后景列表.push(后景mc);
		_root.天空盒.后景移动速度列表.push(speedrate);
	}
	
	_root.天空盒._y = _root.gameworld._y + 环境信息.地平线高度;
}

_root.卸载后景 = function(){
	for(var i=0; i<_root.天空盒.后景列表.length; i++){
		_root.天空盒.后景列表[i].removeMovieClip();
	}
	_root.天空盒.后景列表 = null;
	_root.天空盒.后景移动速度列表 = null;
}
