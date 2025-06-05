import org.flashNight.arki.bullet.BulletComponent.Shell.*;
import org.flashNight.arki.corpse.*;
import org.flashNight.arki.spatial.transform.*;
import org.flashNight.sara.util.*;
import org.flashNight.neur.Event.*;
import flash.geom.Matrix;
import flash.display.BitmapData;
import org.flashNight.gesh.object.*;
import org.flashNight.arki.unit.UnitComponent.Targetcache.*;

// 原 add2map 的重构
_root.add2map = function(tg, ln) {
    DeathEffectRenderer.renderCorpse(tg, ln);
};

// 原 add2map2 的重构
_root.add2map2 = function(tg, ln) {
    // 注：原 add2map2 的清除逻辑与 renderCorpse 不同，但通过安全检查后可直接复用
    DeathEffectRenderer.renderCorpse(tg, ln);
};

// 原 add2map3 的重构（处理旋转）
_root.add2map3 = function(tg, ln) {
    DeathEffectRenderer.renderRotatedCorpse(tg, ln);
};

_root.add2map = _root.add2map2 = DeathEffectRenderer.renderCorpse;
_root.add2map3 = DeathEffectRenderer.renderRotatedCorpse;

_root.createEmptyMovieClip("collisionLayer", _root.getNextHighestDepth());

_root.绘制地图碰撞箱 = function () {
	var 地图 = _root.gameworld.地图;
	var collisionLayer = _root.collisionLayer;
	if(地图.初始化完毕 !== true){
		var point:Vector = SceneCoordinateManager.calculateOffset();

		// 定义边界及安全边距
		var margin = 300;  
		var xmin = _root.Xmin - point.x;
		var xmax = _root.Xmax - point.x;
		var ymin = _root.Ymin - point.y;
		var ymax = _root.Ymax - point.y;

		// 计算“外框”坐标
		var outerLeft   = xmin - margin;
		var outerRight  = xmax + margin;
		var outerTop    = ymin - margin;
		var outerBottom = ymax + margin;

		// 为了可视化调试，设置较明显的线条和半透明填充
		collisionLayer.lineStyle(2, 0xFF0000, 100);   // 红色边线，不透明
		collisionLayer.beginFill(0x66CC66, 100);      // 半透明绿色填充

		// ------ 先绘制外框 (顺时针) ------
		// 例如：从左上 -> 右上 -> 右下 -> 左下 -> 回到左上
		collisionLayer.moveTo(outerLeft,  outerTop);
		collisionLayer.lineTo(outerRight, outerTop);
		collisionLayer.lineTo(outerRight, outerBottom);
		collisionLayer.lineTo(outerLeft,  outerBottom);
		collisionLayer.lineTo(outerLeft,  outerTop);

		// ------ 再绘制内框 (逆时针)，产生“中空”效果 ------
		// 如果外框是顺时针，这里反向绘制才能在非零环绕规则下形成洞
		collisionLayer.moveTo(xmin, ymin);
		collisionLayer.lineTo(xmax, ymin);
		collisionLayer.lineTo(xmax, ymax);
		collisionLayer.lineTo(xmin, ymax);
		collisionLayer.lineTo(xmin, ymin);

		// 结束填充
		collisionLayer.endFill();

        // 设置碰撞层可见性
        if(_root.调试模式) {
			_root.collisionLayer._visible = true;
			_root.collisionLayer._alpha = 50; // 调试时显示为半透明
            // 地图本身也可以显示
            地图._visible = true;
            地图._alpha = 66;
        } else {
            _root.collisionLayer._visible = false;
            地图._visible = false;
        }

		地图.初始化完毕 = true;
	}
}


_root.通过数组绘制地图碰撞箱 = function(arr:Array) {
    // var 游戏世界地图 = _root.gameworld.地图;
	var collisionLayer = _root.collisionLayer;
    if (arr.length > 0) {
        for (var i = 0; i < arr.length; i++) {
            var 多边形 = arr[i].Point;
            if (多边形.length < 3) continue;
            collisionLayer.beginFill(0x000000);
            var pt = 多边形[0].split(",");
            var px = Number(pt[0]);
            var py = Number(pt[1]);
            collisionLayer.moveTo(px, py);
            for (var j = 多边形.length - 1; j >= 0; j--) {
                var pt = 多边形[j].split(",");
                var px = Number(pt[0]);
                var py = Number(pt[1]);
                collisionLayer.lineTo(px, py);
            }
            collisionLayer.endFill();
        }
    }
    collisionLayer._visible = false;
}

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

	游戏世界.已更新天气 = false;
	_global.ASSetPropFlags(游戏世界, ["效果", "子弹区域", "已更新天气"], 1, false);

	//
	_root.绘制地图碰撞箱();

	if (背景层._width <= 1300) return;

	// 若背景层存在且宽度大于1300则贴背景图
	背景层._visible = true;
	var pos = new Object({x:0, y:0});
	背景层.localToGlobal(pos);
	游戏世界.deadbody.globalToLocal(pos);
	var matrix = new flash.geom.Matrix(1, 0, 0, 1, pos.x, pos.y);
	游戏世界.deadbody.layers[0].draw(背景层,matrix,new flash.geom.ColorTransform(),"normal",undefined,true);
	背景层._visible = false;
	背景层.外部动画加载壳mc.unloadMovie(); //尝试直接卸载原背景

};

_root.配置场景环境信息 = function(){
	var 游戏世界 = _root.gameworld;
	var 环境信息 = _root.天气系统.场景环境设置[_root.关卡标志];
	//显示场景名称
	_root.场景名称文本.text = _root.关卡标志.split("地图-").join("");
	//寻找出生点，但似乎由于异步原因没有生效
	var 出生点列表 = [];
	for (var 单位 in 游戏世界){
		var 出生点 = 游戏世界[单位];
		if (出生点.是否从门加载主角 && 单位 != "出生地"){
			出生点列表.push(出生点);
		}
	}

	游戏世界.出生点列表 = 出生点列表;
	if(环境信息){
		//配置地图尺寸
		_root.Xmax = 环境信息.Xmax;
		_root.Xmin = 环境信息.Xmin;
		_root.Ymax = 环境信息.Ymax;
		_root.Ymin = 环境信息.Ymin;
		游戏世界.背景长 = 环境信息.背景长;
		游戏世界.背景高 = 环境信息.背景高;
		//配置天气和后景
		_root.天气系统.配置环境(环境信息);
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
		//播放场景bgm
		if(环境信息.BGM != null){
			if(环境信息.BGM == "stop") _root.soundEffectManager.stopBGM();
			else _root.soundEffectManager.playBGM(环境信息.BGM, true, null);
		}
	}else{
		天气系统.空间情况 = "室外";
		天气系统.视觉情况 = "光照";
		天气系统.最大光照 = 9;
		天气系统.最小光照 = 0;
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
	var 环境配置 = _root.天气系统.关卡环境设置[url];	
	_root.服务器.发布服务器消息("加载场景背景 " + url + " " + _root.格式化对象为字符串(环境配置));
	if(环境配置) {
		_root.天气系统.配置环境(环境配置);
		背景层.已更新环境配置 = true;
	}
	游戏世界.场景背景url = "flashswf/backgrounds/" + url;
	_global.ASSetPropFlags(游戏世界, ["场景背景url"], 1, false);
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

_root.横版卷屏 = function(scrollTarget, bgWidth, bgHeight, easeFactor, zoomScale)
{
    // 1) 处理缩放参数默认值
    var gameWorld = _root.gameworld;
    var scrollObj = gameWorld[scrollTarget];

    var farthestEnemy = TargetCacheManager.findFarthestEnemy(scrollObj, 5);
    var distance = (Math.abs(scrollObj._x - farthestEnemy._x) + Math.abs(scrollObj._y - farthestEnemy._y)) || 99999;
    var normalizedDistance = Math.max(1, distance / 100); // 归一化距离
    var logScale = Math.log(normalizedDistance) / Math.log(10); // 以10为底的对数
    var targetZoomScale = Math.min(2, Math.max(1, 2 - logScale * 1.11)); // 800像素时缩放为1

    if(!gameWorld.lastScale) gameWorld.lastScale = targetZoomScale;
    
    // 记录缩放前的状态
    var oldScale = gameWorld.lastScale;
	var deltaSscale = (gameWorld.lastScale - targetZoomScale) / easeFactor;
	var deltaMax = 0.1;
	if(deltaSscale > deltaMax) deltaSscale = deltaMax;
	else if(deltaSscale < -deltaMax) deltaSscale = -deltaMax;
	
	
    var newScale:Number = gameWorld.lastScale + (targetZoomScale - gameWorld.lastScale) / easeFactor;
    var frameTimer = _root.帧计时器;
    var frame:Number = frameTimer.当前帧数;
    
    // 2) 舞台显示区域（假设顶部有UI占64像素）
    var stageWidth:Number  = Stage.width;
    var stageHeight:Number = Stage.height - 64;
    
    // 如果目标还没准备好，就不进行处理
    if (!scrollObj || scrollObj._x == undefined) {
        return;
    }
    
    // 2.5) 提前计算边界范围 - 用于缩放补偿的边界检查
    var effBgW:Number = bgWidth * newScale;
    var effBgH:Number = bgHeight * newScale;
    var minScrollX:Number = stageWidth  - effBgW;
    var minScrollY:Number = stageHeight - effBgH;
    var maxScrollX:Number = 0;
    var maxScrollY:Number = 0;
    
    // 3) 缩放中心点补偿处理
    var scaleChanged = Math.abs(newScale - oldScale) > 0.001;
    var worldOffsetX = 0;
    var worldOffsetY = 0;
    
	if (scaleChanged) {
		// 1) 记录缩放前屏幕坐标
		var preScalePt:Object = { x:0, y:0 };
		scrollObj.localToGlobal(preScalePt);

		// 2) 应用新的缩放
		var newScalePercent:Number = newScale * 100;
		gameWorld._xscale = gameWorld._yscale = newScalePercent;
		bgLayer._xscale   = bgLayer._yscale   = newScalePercent;   // ★ 同步缩放

		// 3) 记录缩放后屏幕坐标
		var postScalePt:Object = { x:0, y:0 };
		scrollObj.localToGlobal(postScalePt);

		// 4) 计算补偿
		worldOffsetX = preScalePt.x - postScalePt.x;
		worldOffsetY = preScalePt.y - postScalePt.y;

		// 5) ★ 新增：计算补偿后的坐标并应用边界检查
		var compensatedX:Number = gameWorld._x + worldOffsetX;
		var compensatedY:Number = gameWorld._y + worldOffsetY;
		
		// 边界检查 - X方向
		if (stageWidth < effBgW) {
			if (compensatedX < minScrollX) {
				compensatedX = minScrollX;
			} else if (compensatedX > maxScrollX) {
				compensatedX = maxScrollX;
			}
		}
		
		// 边界检查 - Y方向  
		if (stageHeight < effBgH) {
			if (compensatedY < minScrollY) {
				compensatedY = minScrollY;
			} else if (compensatedY > maxScrollY) {
				compensatedY = maxScrollY;
			}
		}

		// 6) 应用边界约束后的坐标到 gameWorld
		gameWorld._x = compensatedX;
		gameWorld._y = compensatedY;

		// 7) ★ 同步到天空盒根节点
		bgLayer._x = compensatedX;                // 与世界保持相对位置
		bgLayer._y = compensatedY + bgLayer.地平线高度;

		// 8) ★ 立即刷新视差子层 (和 onScrollX 共用一段逻辑)
		var bgList = bgLayer.后景移动速度列表;
		var len    = bgList.length;
		for (var i = 0; i < len; i++) {
			var info = bgList[i];
			info.mc._x = compensatedX / info.speedrate;
		}

		// 9) 更新 lastScale
		gameWorld.lastScale = newScale;
	}

    // 若背景尺寸比可用舞台更小或正好匹配，则无需卷屏
    if (stageWidth >= effBgW && stageHeight >= effBgH) {
        return;
    }
    
    // 6) 容差
    var offsetTolerance:Number = frameTimer.offsetTolerance; 
    
    // 7) 设定卷屏的「中心点」
    var LEFT_SCROLL_CENTER:Number   = stageWidth  * 0.5 + 100;
    var RIGHT_SCROLL_CENTER:Number  = stageWidth  * 0.5 - 100;
    var VERTICAL_SCROLL_CENTER:Number = stageHeight - 100;
    
    // 8) 获取玩家(或目标) 在全局坐标下的位置
    var pt:Object = { x: 0, y: 0 };
    scrollObj.localToGlobal(pt);
    
    // 9) 根据角色朝向决定"目标中心"在哪侧
    var isRightDirection = (scrollObj._xscale > 0);
    var targetX = isRightDirection ? RIGHT_SCROLL_CENTER : LEFT_SCROLL_CENTER;
    
    // 10) 计算与目标中心点的差值 (deltaX/deltaY)
    var deltaX:Number = targetX - pt.x;
    var deltaY:Number = VERTICAL_SCROLL_CENTER - pt.y;
    var adx:Number = Math.abs(deltaX);
    var ady:Number = Math.abs(deltaY);
    
    // 11) 分别判断 X / Y 是否需要移动
    var needMoveX:Boolean = (adx > offsetTolerance);
    var needMoveY:Boolean = (ady > offsetTolerance);
    if (!needMoveX && !needMoveY) {
        // X/Y 都不需要移动
        return;
    }

    // 取当前的世界坐标（后面要对比有没有变化）
    var oldX:Number = gameWorld._x;
    var oldY:Number = gameWorld._y;
    // 先默认 0 表示不移动
    var dx:Number = 0;
    var dy:Number = 0;
    
    // ---- X方向移动逻辑 ----
    if (needMoveX) {
        // 当 adx 较大时，为了平滑移动，做 easeFactor 处理
        if (adx > 1) {
            dx = deltaX / easeFactor; 
        } else {
            // 如果介于 offsetTolerance 和 1 之间，考虑可以直接小幅修正，
            dx = deltaX; 
        }
    }
    // ---- Y方向移动逻辑 ----
    if (needMoveY) {
        if (ady > 1) {
            dy = deltaY / easeFactor;
        } else {
            // 同上，ady在 (offsetTolerance, 1] 的范围可以直接一次性修正
            dy = deltaY;
        }
    }

    // 如果 dx 和 dy 全是 0，说明其实不需要移动
    if (dx == 0 && dy == 0) {
        return;
    }
    
    // 12) 计算新的世界坐标（尚未约束到边界）
    var newX:Number = oldX + dx;
    var newY:Number = oldY + dy;
    
    // ---- X 方向边界限定 ----
    if (stageWidth < effBgW) {
        // 如果背景比舞台宽，要在 [minScrollX, maxScrollX] 区间内移动
        if (newX < minScrollX) {
            newX = minScrollX;
        } else if (newX > maxScrollX) {
            newX = maxScrollX;
        }
    } else {
        // 如果背景比舞台还窄，则不滚动 X
        newX = oldX;
    }
    
    // ---- Y 方向边界限定 ----
    if (stageHeight < effBgH) {
        if (newY < minScrollY) {
            newY = minScrollY;
        } else if (newY > maxScrollY) {
            newY = maxScrollY;
        }
    } else {
        // 如果背景比舞台还短，则不滚动 Y
        newY = oldY;
    }

    var onScrollX:Boolean = (newX != oldX);
    var onScrollY:Boolean = (newY != oldY);
    
    // 13) 如果实际计算后 newX/newY 与当前 gameWorld 的坐标并无变化，
    //     说明已经在边界，或者移动微乎其微，跳过后续操作。
    if (newX == oldX && newY == oldY) {
        return;
    }

    var bgLayer:MovieClip = _root.天空盒;
    
    if (bgLayer._xscale != newScale * 100) {
       	bgLayer._xscale = bgLayer._yscale = newScale * 100;
    }

    if(onScrollX)
    {
        gameWorld._x = newX;
        if(onScrollY)
        {
            gameWorld._y = newY;
            bgLayer._y = gameWorld._y + bgLayer.地平线高度;
        }
    }
    else
    {
        if(onScrollY)
        {
            gameWorld._y = newY;
            bgLayer._y = gameWorld._y + bgLayer.地平线高度;
        }
        else
        {
            return;
        }
    }
    
    // 14) （可选）发布消息以便 Debug 或查看实际移动量
    /*
    if (scaleChanged) {
        _root.发布消息("缩放补偿 - offsetX: " + worldOffsetX 
                        + ", offsetY: " + worldOffsetY
                        + ", 新缩放: " + newScale.toFixed(3));
    }
    */
    
    // 15) 后景(天空盒/视差背景)处理
    if (_root.启用后景)
    {
        // 让后景的 Y 跟随世界移动
        if(onScrollX)
        {
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
        }
    }
};