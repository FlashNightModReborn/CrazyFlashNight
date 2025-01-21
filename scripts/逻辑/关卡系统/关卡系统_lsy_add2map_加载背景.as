import org.flashNight.arki.bullet.BulletComponent.Shell.*;

_root.add2map = function(tg, ln){
	tg.暴走标志.removeMovieClip();
	tg.远古标志.removeMovieClip();
	tg.亚种标志.removeMovieClip();
	tg.人物文字信息.removeMovieClip();
	tg.新版人物文字信息.removeMovieClip();
	if(!_root.帧计时器.是否死亡特效) return;

	var pos = new Object({x:0, y:0});
	var 游戏世界 = _root.gameworld;
	tg.localToGlobal(pos);
	if (_root.血腥开关){
		游戏世界.deadbody.globalToLocal(pos);
		var matrix = new flash.geom.Matrix(1 * tg._xscale * 0.01, 0, 0, 1 * tg._yscale * 0.01, pos.x, pos.y);
		var 颜色调整 = tg.transform.colorTransform;
		var 暗化调整 = new flash.geom.ColorTransform(颜色调整.redMultiplier - 0.3, 颜色调整.greenMultiplier - 0.3, 颜色调整.blueMultiplier - 0.3, 颜色调整.alphaMultiplier, 颜色调整.redOffset - 0, 颜色调整.greenOffset, 颜色调整.blueOffset, 颜色调整.alphaOffset);
		游戏世界.deadbody.layers[ln].draw(tg,matrix,暗化调整,"normal",undefined,true);
	}else{
		游戏世界.效果.globalToLocal(pos);
		_root.效果("尸体消失",pos.x,pos.y,100);
	}
};
_root.add2map2 = function(tg, ln){
	tg.人物文字信息.removeMovieClip();
	tg.新版人物文字信息.removeMovieClip();
	var 游戏世界 = _root.gameworld;

	if (_root.血腥开关 and _root.帧计时器.是否死亡特效){
		var 尸体层 = 游戏世界.deadbody;
		pos = new Object({x:0, y:0});
		tg.localToGlobal(pos);
		尸体层.globalToLocal(pos);
		if (tg._xscale < 0){
			matrix = new flash.geom.Matrix(-1, 0, 0, 1, pos.x, pos.y);
		}else{
			matrix = new flash.geom.Matrix(1, 0, 0, 1, pos.x, pos.y);
		}
		var _loc4_ = tg.transform.colorTransform;
		var _loc5_ = new flash.geom.ColorTransform(_loc4_.redMultiplier - 0.3, _loc4_.greenMultiplier - 0.3, _loc4_.blueMultiplier - 0.3, _loc4_.alphaMultiplier, _loc4_.redOffset - 0, _loc4_.greenOffset, _loc4_.blueOffset, _loc4_.alphaOffset);
		尸体层.layers[ln].draw(tg,matrix,_loc5_,"normal",undefined,true);
	}else{
		pos = new Object({x:0, y:0});
		tg.localToGlobal(pos);
		游戏世界.效果.globalToLocal(pos);
		_root.效果("尸体消失",pos.x,pos.y,100);
	}
};
_root.add2map3 = function(tg, ln){
	var 游戏世界 = _root.gameworld;

	if (_root.帧计时器.是否死亡特效){
		var 尸体层 = 游戏世界.deadbody;
		pos = new Object({x:0, y:0});
		tg.localToGlobal(pos);
		尸体层.globalToLocal(pos);
	
        var rotationRadians = tg._rotation * Math.PI / 180;// 获取影片剪辑的旋转角度并转换为弧度
        var scaleX = tg._xscale * 0.01;
        var scaleY = tg._yscale * 0.01;
		scaleX /= Math.abs(scaleX);
		scaleX = Math.abs(scaleX) > 0.5 ? scaleX : 0.5;
		scaleY = Math.abs(scaleY) > 0.5 ? scaleY : 0.5;
		var r_cos = Math.cos(rotationRadians) * scaleX;
		var r_sin = Math.sin(rotationRadians) * scaleY;
		//_root.服务器.发布服务器消息(tg._xscale + "_" + tg._yscale + " " +  scaleX + " : " + scaleY);
        // 创建带有旋转的矩阵
        matrix = new flash.geom.Matrix(r_cos, r_sin, -r_sin, r_cos, pos.x, pos.y);
		var 颜色调整 = tg.transform.colorTransform;
		var 暗化调整 = new flash.geom.ColorTransform(颜色调整.redMultiplier - 0.3, 颜色调整.greenMultiplier - 0.3, 颜色调整.blueMultiplier - 0.3, 颜色调整.alphaMultiplier, 颜色调整.redOffset - 0, 颜色调整.greenOffset, 颜色调整.blueOffset, 颜色调整.alphaOffset);
		尸体层.layers[ln].draw(tg,matrix,暗化调整,"normal",undefined,true);
	}
};



_root.贴背景图 = function(){
	// if(_root.无限过图模式) _root.配置无限过图背景参数(); //弃用
	var 游戏世界 = _root.gameworld;
	var 背景层 = 游戏世界.背景;
	var 天气系统 = _root.天气系统;

	if(背景层 != null && !背景层.已更新环境配置){
		if(_root.天空盒){
			天气系统.空间情况 = "室外";
			天气系统.视觉情况 = "光照";
			天气系统.最大光照 = 9;
			天气系统.最小光照 = 0;
		}else{
			天气系统.空间情况 = "室内";
			天气系统.视觉情况 = "灯光";
			天气系统.最大光照 = 8;
			天气系统.最小光照 = 5;		
		}
	}

	// if(天气系统.空间情况 !== "室外") _root.天空盒.removeMovieClip();

	游戏世界.已更新天气 = false;
	_global.ASSetPropFlags(游戏世界, ["效果", "子弹区域"], 1, true);

	if (背景层._width <= 1300) return;

	背景层._visible = true;
	var pos = new Object({x:0, y:0});
	背景层.localToGlobal(pos);
	游戏世界.deadbody.globalToLocal(pos);
	var matrix = new flash.geom.Matrix(1, 0, 0, 1, pos.x, pos.y);
	游戏世界.deadbody.layers[0].draw(背景层,matrix,new flash.geom.ColorTransform(),"normal",undefined,true);
	背景层._visible = false;
	背景层.外部动画加载壳mc.unloadMovie(); //尝试直接卸载原背景
};

_root.配置基地场景环境信息 = function(){
	var 环境信息 = _root.天气系统.环境设置[_root.关卡标志];
	if(环境信息){
		_root.Xmax = 环境信息.Xmax;
		_root.Xmin = 环境信息.Xmin;
		_root.Ymax = 环境信息.Ymax;
		_root.Ymin = 环境信息.Ymin;
		_root.gameworld.背景长 = 环境信息.背景长;
		_root.gameworld.背景高 = 环境信息.背景高;
		//
		_root.天气系统.配置环境(环境信息);
		_root.加载后景(环境信息);
	}else{
		天气系统.空间情况 = "室外";
		天气系统.视觉情况 = "光照";
		天气系统.最大光照 = 9;
		天气系统.最小光照 = 0;
	}
	_root.gameworld.背景.已更新环境配置 = true;
	_root.贴背景图();
}

_root.配置场景环境信息 = _root.配置基地场景环境信息;//想了想基地和外部地图好像可以用一套函数

_root.加载场景背景 = function (动画名){
	var 游戏世界 = _root.gameworld;
	var 背景层 = 游戏世界.背景;
	背景层.attachMovie("外部动画加载壳mc","外部动画加载壳mc",背景层.getNextHighestDepth());
	var list = 动画名.split("/")
	var url = list[list.length-1];
	var 环境配置 = _root.天气系统.环境设置[url];	
	_root.服务器.发布服务器消息("加载场景背景 " + url + " " + _root.格式化对象为字符串(环境配置));
	if(环境配置) {
		_root.天气系统.配置环境(环境配置);
		背景层.已更新环境配置 = true;
	}
	游戏世界.场景背景url = "flashswf/backgrounds/" + url;
	loadMovie(游戏世界.场景背景url, 背景层.外部动画加载壳mc);
	if(环境配置.背景元素){
		for(var i = 0; i < 环境配置.背景元素.length; i++){
			_root.加载背景元素(环境配置.背景元素[i].url, 环境配置.背景元素[i].name, 环境配置.背景元素[i].x, 环境配置.背景元素[i].y, 环境配置.背景元素[i].depth);
		}
	}
}

_root.加载背景元素 = function(url, 实例名, x, y, 层级){
    if(!url) return;
	if(!实例名) 实例名 = "instance" + random(99);
	var 游戏世界 = _root.gameworld;
    var instance = 游戏世界.createEmptyMovieClip(实例名, 游戏世界.getNextHighestDepth());
    instance._x = x;
    instance._y = y;
    instance.loadMovie(url);
    var depth = y;
    if(!isNaN(层级)) depth = 层级;
    else if(层级 === "前景") depth += 1000;
    else if(层级 === "后景") depth -= 1000;
    instance.swapDepths(depth);
}


_root.横版卷屏 = function(scrollTarget, bgWidth, bgHeight, easeFactor) {

	var frameTimer = _root.帧计时器;
	var frame:Number = frameTimer.当前帧数;

	if(frame % frameTimer.scrollDelay !== 0) return;

    var stageWidth = Stage.width;
    var stageHeight = Stage.height - 64;
    if (stageWidth >= bgWidth && stageHeight >= bgHeight) return;

    var gameWorld = _root.gameworld;
    var scrollObj = gameWorld[scrollTarget];
    if (!scrollObj._x) return;

    // 卷屏边界计算
    var minScrollX = stageWidth - bgWidth;
    var minScrollY = stageHeight - bgHeight;
    var maxScrollX = 0;
    var maxScrollY = 0;
    
    // 卷屏中心点常量（AS2用变量模拟）
    var LEFT_SCROLL_CENTER = stageWidth * 0.5 + 100;
    var RIGHT_SCROLL_CENTER = stageWidth * 0.5 - 100;
    var VERTICAL_SCROLL_CENTER = stageHeight - 100;

    // 坐标转换
    var pt = { x: 0, y: 0 };
    scrollObj.localToGlobal(pt);
    
    // 根据方向计算偏移量
    var isRightDirection = scrollObj._xscale > 0;
    var targetX = isRightDirection ? RIGHT_SCROLL_CENTER : LEFT_SCROLL_CENTER;
    var deltaX = (targetX - pt.x) / easeFactor;
    var deltaY = (VERTICAL_SCROLL_CENTER - pt.y) / easeFactor;

    if (Math.abs(deltaX) > 1 || Math.abs(deltaY) > 1) {
        var newX = gameWorld._x + deltaX;
        var newY = gameWorld._y + deltaY;

        // X轴边界处理
        if (stageWidth < bgWidth) {
            newX = Math.max(minScrollX, Math.min(newX, maxScrollX));
        }
        
        // Y轴边界处理
        if (stageHeight < bgHeight) {
            newY = Math.max(minScrollY, Math.min(newY, maxScrollY));
        }

        // 应用新坐标
        gameWorld._x = (stageWidth < bgWidth) ? newX : gameWorld._x;
        gameWorld._y = (stageHeight < bgHeight) ? newY : gameWorld._y;
    }

    // 后景处理
    if (_root.启用后景) {
        var bgLayer = _root.天空盒;
        bgLayer._y = gameWorld._y + bgLayer.地平线高度;
        
        var backgroundList = bgLayer.后景移动速度列表;
        var currentFrame = _root.帧计时器.当前帧数;
        var worldX = gameWorld._x;

        for (var i = 0; i < backgroundList.length; i++) {
            var bgInfo = backgroundList[i];
            if (currentFrame % bgInfo.delay === 0) {
                bgInfo.mc._x = worldX / bgInfo.speedrate;
            }
        }
    }
};

_root.缩放画面 = function(放大倍数){
	var 游戏世界 = _root.gameworld;
	游戏世界.背景长 *= 放大倍数;
	游戏世界.背景高 *= 放大倍数;
	游戏世界._width *= 放大倍数;
	游戏世界._height *= 放大倍数;
	_root.横版卷屏(_root.控制目标,游戏世界.背景长,游戏世界.背景高,1);
}

//Stage.align = "TL";