_root.加载后景 = function(环境信息){
	if(环境信息.空间情况 == "室内"){
		_root.启用后景 = false;
		_root.天空盒.默认天空._visible = false;
		return;
	}
	_root.启用后景 = true;
	_root.天空盒.默认天空._visible = true;
	_root.天空盒.地平线高度 = 环境信息.地平线高度;
	if(!环境信息.后景){
		_root.卸载后景();
		return;
	}
	if(!_root.天空盒.后景列表) {
		_root.天空盒.后景列表 = [];
		_root.天空盒.后景移动速度列表 = [];
	}
	var url = "flashswf/skybox/" + 环境信息.后景[0].url;
	var 后景mc = _root.天空盒.createEmptyMovieClip("后景0",0);
	后景mc.loadMovie(url);
	
	_root.天空盒._y = _root.gameworld._y + 环境信息.地平线高度;
	_root.天空盒.后景列表.push(后景mc);
	_root.天空盒.后景移动速度列表.push(环境信息.后景[0].SpeedRate);
}

_root.卸载后景 = function(){
	for(var i=0; i<_root.天空盒.后景列表.length; i++){
		_root.天空盒.后景列表[i].removeMovieClip();
	}
	_root.天空盒.后景列表 = null;
	_root.天空盒.后景移动速度列表 = null;
}
