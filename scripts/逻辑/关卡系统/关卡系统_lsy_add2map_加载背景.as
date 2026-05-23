import org.flashNight.arki.bullet.BulletComponent.Shell.*;
import org.flashNight.arki.corpse.*;
import org.flashNight.arki.spatial.transform.*;
import org.flashNight.sara.util.*;
import org.flashNight.neur.Event.*;
import flash.geom.Matrix;
import flash.display.BitmapData;
import org.flashNight.gesh.object.*;
import org.flashNight.arki.unit.UnitComponent.Targetcache.*;
import org.flashNight.arki.camera.*;
import org.flashNight.arki.scene.*;
import org.flashNight.arki.collision.CollisionLayerRenderer;
import org.flashNight.arki.weather.*;
import org.flashNight.gesh.depth.*;


_root.add2map = _root.add2map2 = DeathEffectRenderer.renderCorpse;
_root.add2map3 = DeathEffectRenderer.renderRotatedCorpse;

_root.createEmptyMovieClip("collisionLayer", _root.getNextHighestDepth());

_root.绘制地图碰撞箱 = function () {
	var 地图 = _root.gameworld.地图;
	if(地图.初始化完毕 !== true){
		var point:Vector = SceneCoordinateManager.calculateOffset();

		// 定义边界坐标
		var xmin:Number = _root.Xmin - point.x;
		var xmax:Number = _root.Xmax - point.x;
		var ymin:Number = _root.Ymin - point.y;
		var ymax:Number = _root.Ymax - point.y;

		// 调用统一渲染器绘制边界碰撞箱
		CollisionLayerRenderer.drawBoundary(
			_root.collisionLayer,
			xmin, xmax, ymin, ymax,
			300,  // margin
			_root.调试模式
		);

		// 调试模式下显示地图层
		if(_root.调试模式) {
			地图._visible = true;
			地图._alpha = 66;
		} else {
			地图._visible = false;
		}

		地图.初始化完毕 = true;
	}
}


_root.通过数组绘制地图碰撞箱 = function(arr:Array) {
	// 调用统一渲染器绘制多边形碰撞箱
	CollisionLayerRenderer.drawPolygons(_root.collisionLayer, arr);
}

_root.通过影片剪辑外框绘制地图碰撞箱 = function(mc:MovieClip) {
	// 获取影片剪辑的边界矩形
	var rect:Object = mc.area.getRect(_root.gameworld);
	// 调用统一渲染器绘制矩形碰撞箱
	CollisionLayerRenderer.drawRect(_root.collisionLayer, rect);
}

_root.贴背景图 = function(){
	// if(_root.无限过图模式) _root.配置无限过图背景参数(); //弃用
	var 游戏世界 = _root.gameworld;
	var 背景层 = 游戏世界.背景;
	var 天气系统:WeatherSystem = WeatherSystem.getInstance();

	// 排查：背景元件未命名为"背景"（如散放在"背景"图层）时 gameworld.背景 为 undefined，该图背景无法转位图
	if (背景层 == undefined) {
		var logMsg:String = "[贴背景图] 未找到 gameworld.背景 实例 — 地图:" + _root.关卡地图帧值 + " 关卡标志:" + _root.关卡标志 + " — 背景不会转位图（需把背景打包成实例名为'背景'的元件）";
		_root.发布消息(logMsg);
		_root.服务器.发布服务器消息(logMsg);
	}

	if(背景层 != null && !背景层.已更新环境配置){
		if(_root.天空盒){
			天气系统.spaceCondition = "室外";
			天气系统.visualCondition = "光照";
			天气系统.maxLight = 9;
			天气系统.minLight = 0;
		}else{
			天气系统.spaceCondition = "室内";
			天气系统.visualCondition = "灯光";
			天气系统.maxLight = 8;
			天气系统.minLight = 5;
		}
	}

	游戏世界.已更新天气 = false;
	_global.ASSetPropFlags(游戏世界, ["已更新天气"], 1, false);

	//
	_root.绘制地图碰撞箱();

	if (背景层._width <= 1300) return;

	// ── Bake：把 背景 烤进 deadbody.layers[0] ──
	// 兼容作者随手摆：_x/_y/_xscale/_yscale 任意值都正确还原视觉位置和尺寸，
	// 不再要求作者把 背景 放在 (0,0) + 100% 缩放。两条关键修复：
	//   (1) 用 transform.matrix.clone() 继承 背景 自身缩放/旋转，老的写死单位阵会把
	//       _xscale!=100 的 背景 烤成原始尺寸（=放大 1/scale 倍）。
	//   (2) 用 getBounds(deadbody) 拿到实际可视盒子，按 bounds 重建 BitmapData，
	//       并把 wrapper MC 反向位移到 bounds.topLeft，让位图视觉位置 = background 原位置。
	var deadbody:MovieClip = 游戏世界.deadbody;
	var b:Object = 背景层.getBounds(deadbody);
	var needW:Number = Math.ceil(b.xMax - b.xMin);
	var needH:Number = Math.ceil(b.yMax - b.yMin);
	if (needW < 1) needW = 1;
	if (needW > 8192) needW = 8192;
	if (needH < 1) needH = 1;
	if (needH > 4096) needH = 4096;

	var bd:flash.display.BitmapData = deadbody.layers[0];
	var bgWrap:MovieClip = deadbody.__bgBakeLayer;
	if (bd.width != needW || bd.height != needH) {
		bd.dispose();
		bd = new flash.display.BitmapData(needW, needH, true, 13421772);
		deadbody.layers[0] = bd;
		bgWrap.attachBitmap(bd, 1);
	}

	var bgMat:flash.geom.Matrix = 背景层.transform.matrix.clone();
	var dbMat:flash.geom.Matrix = deadbody.transform.matrix.clone();
	dbMat.invert();
	bgMat.concat(dbMat);                    // 背景 局部 → deadbody 局部
	bgMat.translate(-b.xMin, -b.yMin);      // bounds.topLeft → bitmap (0,0)

	背景层._visible = true;
	bd.draw(背景层, bgMat, new flash.geom.ColorTransform(), "normal", undefined, true);
	背景层._visible = false;

	bgWrap._x = b.xMin;                     // wrapper 反向位移：位图回到 background 原视觉位置
	bgWrap._y = b.yMin;

	// 背景已烤进 deadbody 位图，unloadMovie 清空原背景夹、释放全部矢量子级内存
	// （对时间轴负深度实例同样有效；外部图则连 外部动画加载壳mc 一并清；留空壳故 gameworld.背景 不会变 undefined）
	背景层.unloadMovie();
};

_root.配置场景环境信息 = function(){
	var 游戏世界 = _root.gameworld;
	var 环境信息 = WeatherSystem.getInstance().getEnvConfig().getSceneEnv(_root.关卡标志);
	//寻找出生点，但似乎由于异步原因没有生效
	// var 出生点列表 = [];
	// for (var 单位 in 游戏世界){
	// 	var 出生点 = 游戏世界[单位];
	// 	if (出生点.是否从门加载主角 && 单位 != "出生地"){
	// 		出生点列表.push(出生点);
	// 	}
	// }

	// 游戏世界.出生点列表 = 出生点列表;
	if(环境信息){
		//配置地图尺寸
		_root.Xmax = 环境信息.Xmax;
		_root.Xmin = 环境信息.Xmin;
		_root.Ymax = 环境信息.Ymax;
		_root.Ymin = 环境信息.Ymin;
		// 用精确场景边界标定深度管理器
		DepthManager.instance.calibrate(_root.Ymin, _root.Ymax);
		游戏世界.背景长 = 环境信息.背景长;
		游戏世界.背景高 = 环境信息.背景高;

		// 添加动态尺寸的位图层
		SceneManager.getInstance().addBodyLayers(游戏世界.背景长, 游戏世界.背景高);

		//配置天气和后景
		WeatherSystem.getInstance().configureEnvironment(环境信息);
		_root.加载后景(环境信息);
		// 配置碰撞箱
		var collision = 环境信息.Collision || 环境信息.地图碰撞箱 || null
		if(collision) _root.通过数组绘制地图碰撞箱(collision);
		//加载随机佣兵
		游戏世界.面积系数 = isNaN(环境信息.佣兵刷新数据.AreaMultiplier) ? 1 : 环境信息.佣兵刷新数据.AreaMultiplier;
		if(!isNaN(环境信息.佣兵刷新数据.Initial)){
			_root.场景刷可雇用玩家(环境信息.佣兵刷新数据.Initial);
		}
		if(_root.门口佣兵刷新器 && !isNaN(环境信息.佣兵刷新数据.Entrance)){
			_root.门口佣兵刷新器.几率 = 环境信息.佣兵刷新数据.Entrance;
		}
		// 一次性场景加载快照，给标定看 area/mult/target
		org.flashNight.arki.merc.MercBudget.emitLoad();
		//播放场景bgm（支持单曲/专辑两种模式）
		if(typeof 环境信息.BGM == "object" && 环境信息.BGM.album != undefined){
			// 专辑模式: <BGM album="TFR"/> 或 <BGM album="TFR" default="Dialtone"/>
			_root.soundEffectManager.playAlbumBGM(环境信息.BGM.album, "scene", true, 环境信息.BGM["default"]);
		} else if(环境信息.BGM != null){
			if(环境信息.BGM == "stop") _root.soundEffectManager.stopBGM();
			else _root.soundEffectManager.playBGMWithSource(环境信息.BGM, "scene", true, null);
		}
		// 兜底: 如果场景无 BGM 配置但 jukebox 激活，确保 jukebox 恢复
		_root.soundEffectManager.resumeJukeboxIfNeeded();
	}else{
		天气系统.spaceCondition = "室外";
		天气系统.visualCondition = "光照";
		天气系统.maxLight = 9;
		天气系统.minLight = 0;
		SceneManager.getInstance().addBodyLayers(2880, 1000);
		// 无环境信息时用 EnvironmentConfig 默认值标定
		DepthManager.instance.calibrate(330, 600);
	}
	_global.ASSetPropFlags(游戏世界, ["面积系数","出生点列表"], 1, false);

	//完成并贴背景图
	游戏世界.背景.已更新环境配置 = true;
	_root.贴背景图();
}

_root.加载场景背景 = function (动画名){
	var 游戏世界 = _root.gameworld;
	var 背景层 = 游戏世界.背景;
	背景层.attachMovie("外部动画加载壳mc","外部动画加载壳mc",背景层.getNextHighestDepth());
	var list = 动画名.split("/")
	var url = list[list.length-1];
	var 环境配置 = WeatherSystem.getInstance().getEnvConfig().getStageEnv(url);
	_root.服务器.发布服务器消息("加载场景背景 " + url + " " + _root.格式化对象为字符串(环境配置));
	if(环境配置) {
		WeatherSystem.getInstance().configureEnvironment(环境配置);
		背景层.已更新环境配置 = true;
	}
	游戏世界.场景背景url = "flashswf/backgrounds/" + url;
	_global.ASSetPropFlags(游戏世界, ["场景背景url"], 1, false);
	loadMovie(游戏世界.场景背景url, 背景层.外部动画加载壳mc);
	// if(环境配置.背景元素){
	// 	for(var i = 0; i < 环境配置.背景元素.length; i++){
	// 		_root.加载背景元素(环境配置.背景元素[i].url, 环境配置.背景元素[i].name, 环境配置.背景元素[i].x, 环境配置.背景元素[i].y, 环境配置.背景元素[i].depth);
	// 	}
	// }
}

// _root.加载背景元素 = function(url, 实例名, x, y, 层级){
//     if(!url) return;
// 	if(!实例名) 实例名 = "instance" + random(99);
// 	var 游戏世界 = _root.gameworld;
//     var instance = 游戏世界.createEmptyMovieClip(实例名, 游戏世界.getNextHighestDepth());
//     instance._x = x;
//     instance._y = y;
//     instance.loadMovie(url);
//     var depth = y;
//     if(!isNaN(层级)) depth = 层级;
//     else if(层级 === "前景") depth += 1000;
//     else if(层级 === "后景") depth -= 1000;
//     instance.swapDepths(depth);
// }

_root.横版卷屏 = function() {
    HorizontalScroller.update();
};

_root.cameraZoomToggle = false;
_root.basicZoomScale = 1;

EventBus.getInstance().subscribe("SceneReady", HorizontalScroller.onSceneChanged, HorizontalScroller); 
EventBus.getInstance().subscribe("FlashFullScreenChanged", HorizontalScroller.onFullScreenChanged, HorizontalScroller); 
EventBus.getInstance().subscribe("SceneReady", ZoomController.resetState, ZoomController); 