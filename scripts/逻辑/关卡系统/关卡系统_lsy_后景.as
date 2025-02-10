import org.flashNight.neur.Event.*;

_root.加载后景 = function(环境信息){
	var 禁用天空 = 环境信息.空间情况 == "室内" || 环境信息.禁用天空;
	var gameWorld = _root.gameworld;
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
	var gwx:Number = gameWorld._x;
	var infoObj:Object;
	for(var i = 0; i<环境信息.后景.length; i++){
		var url = "flashswf/skybox/" + 环境信息.后景[i].url;
		var speedrate = 环境信息.后景[i].SpeedRate;
		if(speedrate > maxSpeedRate - 1) speedrate = maxSpeedRate - 1;
		var depth = speedrate <= 0 ? 0 : maxSpeedRate - speedrate;
		var bgMc = _root.天空盒.createEmptyMovieClip("后景"+i, depth);
		bgMc.loadMovie(url);
		bgMc._x = gwx / speedrate;
		_root.天空盒.后景列表.push(bgMc);

		if(speedrate > 0)
		{
			infoObj = {};
			infoObj.speedrate = speedrate;
			infoObj.mc = bgMc;
			infoObj.delay = Math.round(Math.log(speedrate - 4) / Math.LN2);
			_root.天空盒.后景移动速度列表.push(infoObj);
		}
		
	}
	
	_root.天空盒._y = _root.gameworld._y + 环境信息.地平线高度;
}

EventBus.getInstance().subscribe("SceneChanged", function()
{
	
	var bgLayer:MovieClip = _root.天空盒;
	var gameWorld = _root.gameworld;
	bgLayer._y = gameWorld._y + bgLayer.地平线高度;
	var backgroundList = bgLayer.后景移动速度列表;
	var currentFrame = _root.帧计时器.当前帧数;
	var worldX:Number = gameWorld._x;
	var len:Number = backgroundList.length;
	
	for (var i = 0; i < len; i++)
	{
		var bgInfo = backgroundList[i];
		if (currentFrame % bgInfo.delay === 0)
		{
			bgInfo.mc._x = worldX / bgInfo.speedrate;
		}
	}
}, _root); 

_root.卸载后景 = function(){
	for(var i=0; i<_root.天空盒.后景列表.length; i++){
		_root.天空盒.后景列表[i].removeMovieClip();
	}
	_root.天空盒.后景列表 = null;
	_root.天空盒.后景移动速度列表 = null;
}
