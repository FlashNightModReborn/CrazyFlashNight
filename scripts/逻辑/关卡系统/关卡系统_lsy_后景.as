import org.flashNight.neur.Event.*;

_root.加载后景 = function(环境信息){
    // 根据环境信息判断是否禁用天空效果：
    // 当处于室内环境或明确设置禁用天空时，隐藏默认天空
    var 禁用天空 = 环境信息.空间情况 == "室内" || 环境信息.禁用天空;
    var gameWorld = _root.gameworld;
    _root.天空盒.默认天空._visible = !禁用天空;
    
    // 如果禁用天空且没有后景配置，则关闭后景功能并退出
    if(禁用天空 && !环境信息.后景){
        _root.启用后景 = false;
        return;
    }
    
    _root.启用后景 = true;
    // 根据游戏世界的 y 坐标和地平线高度，调整天空盒的垂直位置
    _root.天空盒.地平线高度 = 环境信息.地平线高度;
    _root.天空盒._y = _root.gameworld._y + 环境信息.地平线高度;
    
    // 如果没有后景配置，则卸载当前后景并退出
    if(!环境信息.后景){
        _root.卸载后景();
        return;
    }
    
    // 初始化后景列表和后景移动速度列表（若尚未初始化）
    if(!_root.天空盒.后景列表) {
        _root.天空盒.后景列表 = [];
        _root.天空盒.后景移动速度列表 = [];
    }
    
    // 设置后景的最大速度比阈值（有效 speedrate 最大为 maxSpeedRate - 1）
    var maxSpeedRate = 32;
    var gwx:Number = gameWorld._x;  // 获取游戏世界的 x 坐标，用于计算后景的初始水平位置
    
    // 遍历每个后景配置，根据 speedrate 设置其深度和初始位置，实现视差效果
    var infoObj:Object;
    for(var i = 0; i < 环境信息.后景.length; i++){
        // 构造后景 SWF 文件的 URL 路径
        var url = "flashswf/skybox/" + 环境信息.后景[i].url;
        var speedrate = 环境信息.后景[i].SpeedRate;
        
        // 限制 speedrate 的最大值，确保其不超过 (maxSpeedRate - 1)
        if(speedrate > maxSpeedRate - 1) {
            speedrate = maxSpeedRate - 1;
        }
        
        // 计算 MovieClip 的深度：
        //   - 当 speedrate ≤ 0 时，设定深度为 0（前景层）
        //   - 当 speedrate > 0 时，深度设为 maxSpeedRate - speedrate，
        //     使得 speedrate 越大（后景移动越慢）的图层越靠后
        var depth = speedrate <= 0 ? 0 : maxSpeedRate - speedrate;
        
        // 创建一个空 MovieClip 承载后景，并加载指定的 SWF 文件
        var bgMc = _root.天空盒.createEmptyMovieClip("后景" + i, depth);
        bgMc.loadMovie(url);
        
        // 根据游戏世界的 x 坐标和 speedrate 计算后景的初始水平位置，实现视差效果
        bgMc._x = gwx / speedrate;
        _root.天空盒.后景列表.push(bgMc);
        
        // 对于有效的 speedrate（大于 0），计算并记录渲染延迟信息，用于分帧渲染以优化性能
        if(speedrate > 0)
        {
            infoObj = {};
            infoObj.speedrate = speedrate;
            infoObj.mc = bgMc;
            
            // ======================================================
            // 分帧渲染延迟计算公式说明
            // ------------------------------------------------------
            // 设计目标：在保证视觉连续性的前提下，通过降低更新频率来优化性能
            //
            // 参数说明：
            //   speedrate - 后景与主世界的移动速度比例
            //               例如：speedrate = 4 表示后景移动速度为主世界的 1/4
            //
            // 延迟策略：
            //   当 speedrate ≤ 4 时，后景每帧渲染（delay = 1，表示无延迟）
            //   当 speedrate > 4 时，延迟值按以下公式计算：
            //     delay = Math.ceil( Math.log(speedrate / 2) / Math.LN2 )
            //
            // 计算示例：
            //   speedrate = 4  -> delay = 1  （每帧渲染）
            //   speedrate = 5  -> delay ≈ Math.ceil(Math.log(5/2)/Math.LN2) = 2
            //   speedrate = 8  -> delay = Math.ceil(Math.log(8/2)/Math.LN2) = 2
            //   speedrate = 12 -> delay ≈ 3
            //   speedrate = 16 -> delay = 3
            //   speedrate = 32 -> delay = 4
            //
            // 该策略确保高速后景保持流畅，而对于低速后景则通过增加渲染间隔来降低性能消耗
            // ======================================================
            
            infoObj.delay = (speedrate <= 4) ? 
                1 : // 当 speedrate ≤ 4 时，每帧渲染
                Math.ceil( Math.log(speedrate / 2) / Math.LN2 );
            
            _root.天空盒.后景移动速度列表.push(infoObj);
        }
    }
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
