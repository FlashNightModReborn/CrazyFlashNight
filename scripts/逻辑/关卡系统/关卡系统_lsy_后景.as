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
			// ======================================================
			// 分帧延迟计算公式说明
			// ------------------------------------------------------
			// 设计目标：在保持视觉连续性的前提下，通过分帧渲染优化性能
			// 参数定义：
			//   speedrate - 后景与主世界的移动速度比值（N:1）
			//               示例：speedrate=4 表示后景移动速度是主世界的1/4
			// 延迟策略：
			//   speedrate ≤4 时：每帧渲染（delay=0）
			//   speedrate >4 时：按指数阶梯增加渲染间隔
			// ======================================================

			infoObj.delay = (speedrate <= 4) ? 
				0 : // 保持每帧渲染，确保快速移动元素的视觉流畅性
				Math.floor( 
					Math.log(speedrate / 2) / Math.LN2 // 核心计算公式说明：
					// 1. speedrate/2：将基准值调整为2的幂次增长起点
					//    （当speedrate=8时：8/2=4 → 2^2 → delay=2）
					// 2. log计算：获取达到当前速度比所需的2的幂次数
					// 3. floor：取整保证离散的阶梯变化
				);

			// ================= 数值映射示例 =================
			// speedrate | 计算过程             | delay | 实际渲染间隔（帧）
			// --------------------------------------------------
			// 4        | 条件判断              | 0     | 1
			// 5        | log₂(5/2)=1.32 →1    | 1     | 2
			// 8        | log₂(8/2)=2 →2       | 2     | 3
			// 12       | log₂(12/2)=2.58 →2   | 2     | 3
			// 16       | log₂(16/2)=3 →3      | 3     | 4
			// 32       | log₂(32/2)=4 →4      | 4     | 5

			// ============= 公式特性说明 =============
			// 视觉连续性保障：
			//   - 人眼对慢速运动（speedrate>16）的帧率下降不敏感
			//   - 人眼对信息变化的敏感度呈对数衰减
			// 注意事项：
			//   当speedrate从4提升到5，或者从7提升到8，15提升到16,31提升到32，渲染间隔都会增加
			//   可通过将除数调整为3来调节阈值：Math.log(speedrate/3)

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
