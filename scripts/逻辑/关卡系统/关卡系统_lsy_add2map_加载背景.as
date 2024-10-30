_root.add2map = function(tg, ln)
{
	tg.暴走标志.removeMovieClip();
	tg.远古标志.removeMovieClip();
	tg.亚种标志.removeMovieClip();
	tg.人物文字信息.removeMovieClip();
	tg.新版人物文字信息.removeMovieClip();
	if(!_root.帧计时器.是否死亡特效) return;

	var pos = new Object({x:0, y:0});
	var 游戏世界 = _root.gameworld;
	tg.localToGlobal(pos);
	if (_root.血腥开关)
	{
		游戏世界.deadbody.globalToLocal(pos);
		var matrix = new flash.geom.Matrix(1 * tg._xscale * 0.01, 0, 0, 1 * tg._yscale * 0.01, pos.x, pos.y);
		var 颜色调整 = tg.transform.colorTransform;
		var 暗化调整 = new flash.geom.ColorTransform(颜色调整.redMultiplier - 0.3, 颜色调整.greenMultiplier - 0.3, 颜色调整.blueMultiplier - 0.3, 颜色调整.alphaMultiplier, 颜色调整.redOffset - 0, 颜色调整.greenOffset, 颜色调整.blueOffset, 颜色调整.alphaOffset);
		游戏世界.deadbody.layers[ln].draw(tg,matrix,暗化调整,"normal",undefined,true);
	}
	else
	{
		游戏世界.效果.globalToLocal(pos);
		_root.效果("尸体消失",pos.x,pos.y,100);
	}
};
_root.add2map2 = function(tg, ln)
{
	tg.人物文字信息.removeMovieClip();
	tg.新版人物文字信息.removeMovieClip();
	var 游戏世界 = _root.gameworld;

	if (_root.血腥开关 and _root.帧计时器.是否死亡特效)
	{
		var 尸体层 = 游戏世界.deadbody;
		pos = new Object({x:0, y:0});
		tg.localToGlobal(pos);
		尸体层.globalToLocal(pos);
		if (tg._xscale < 0)
		{
			matrix = new flash.geom.Matrix(-1, 0, 0, 1, pos.x, pos.y);
		}
		else
		{
			matrix = new flash.geom.Matrix(1, 0, 0, 1, pos.x, pos.y);
		}
		var _loc4_ = tg.transform.colorTransform;
		var _loc5_ = new flash.geom.ColorTransform(_loc4_.redMultiplier - 0.3, _loc4_.greenMultiplier - 0.3, _loc4_.blueMultiplier - 0.3, _loc4_.alphaMultiplier, _loc4_.redOffset - 0, _loc4_.greenOffset, _loc4_.blueOffset, _loc4_.alphaOffset);
		尸体层.layers[ln].draw(tg,matrix,_loc5_,"normal",undefined,true);
	}
	else
	{
		pos = new Object({x:0, y:0});
		tg.localToGlobal(pos);
		游戏世界.效果.globalToLocal(pos);
		_root.效果("尸体消失",pos.x,pos.y,100);
	}
};
_root.add2map3 = function(tg, ln)
{
	var 游戏世界 = _root.gameworld;

	if (_root.帧计时器.是否死亡特效)
	{
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


_root.贴背景图 = function()
{
	if(_root.无限过图模式) _root.配置无限过图背景参数();
	var 游戏世界 = _root.gameworld;
	var 背景层 = 游戏世界.背景;
	var 天气系统 = _root.天气系统;
	if(!背景层.已更新环境配置)
	{
		if(_root.天空盒)
		{
			天气系统.空间情况 = "室外";
			天气系统.视觉情况 = "光照";
			天气系统.最大光照 = 9;
			天气系统.最小光照 = 0;
		}
		else
		{
			天气系统.空间情况 = "室内";
			天气系统.视觉情况 = "灯光";
			天气系统.最大光照 = 8;
			天气系统.最小光照 = 5;		
		}
	}

	if(天气系统.空间情况 !== "室外") _root.天空盒.removeMovieClip();

	游戏世界.已更新天气 = false;

	if (背景层._width < 1300) return;

	背景层._visible = true;
	var pos = new Object({x:0, y:0});
	背景层.localToGlobal(pos);
	游戏世界.deadbody.globalToLocal(pos);
	var matrix = new flash.geom.Matrix(1, 0, 0, 1, pos.x, pos.y);
	游戏世界.deadbody.layers[0].draw(背景层,matrix,new flash.geom.ColorTransform(),"normal",undefined,true);
	//尝试直接卸载原背景
	背景层.外部动画加载壳mc.unloadMovie();
	背景层._visible = false;
};

_root.加载场景背景 = function (动画名)
{
	var 背景层 = _root.gameworld.背景;
	背景层.attachMovie("外部动画加载壳mc","外部动画加载壳mc",背景层.getNextHighestDepth());
	var list = 动画名.split("/")
	var url = list[list.length-1];
	var 环境配置 = _root.天气系统.环境设置[url];	
	_root.服务器.发布服务器消息("加载场景背景 " + url + " " + _root.格式化对象为字符串(环境配置));
	if(环境配置) 
	{
		_root.天气系统.配置环境(环境配置);
		背景层.已更新环境配置 = true;
	}
	loadMovie("flashswf/backgrounds/" + url,背景层.外部动画加载壳mc);
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


_root.配置无限过图背景参数 = function()
{
	//可以参考军阀秘密基地_1_BG和军阀秘密基地_2_BG这两张背景作为教程
	if (!_root.无限过图模式){
		return;
	}
	var 游戏世界 = _root.gameworld;
	var 世界地图 = 游戏世界.地图;
	var 对象 = 游戏世界.背景.外部动画加载壳mc;
	var 环境信息 = _root.天气系统.无限过图环境信息;
	
	//注意：最小的能占满屏幕的背景长和背景高分别为1024和512，再小就会出黑边
	
	var 游戏世界门1 = 游戏世界.门1;
	var 对象门 = 对象.门;
	if(对象门){	
		游戏世界门1._x = 对象门._x;
		游戏世界门1._y = 对象门._y;
		游戏世界门1._width = 对象门._width;
		游戏世界门1._height = 对象门._height;
	}else if(游戏世界.门朝向 === "左"){
		//如果没有在背景文件里检测到门，则默认过图位置为地图左边缘或右边缘
		游戏世界门1._x = _root.Xmin;
		游戏世界门1._y = _root.Ymin;
		游戏世界门1._width = 50;
		游戏世界门1._height = _root.Ymax - _root.Ymin;
	}else{
		游戏世界门1._x = _root.Xmax - 50;
		游戏世界门1._y = _root.Ymin;
		游戏世界门1._width = 50;
		游戏世界门1._height = _root.Ymax - _root.Ymin;
		游戏世界.门朝向 = "右";
	}
	//地图碰撞箱的绘制已移到无限过图文件
};

_root.横版卷屏 = function(卷屏目标, 背景长, 背景高, 缓动系数)
{
	var 游戏世界 = _root.gameworld;
	var 卷屏对象 = 游戏世界[卷屏目标];
	if (卷屏对象._x)
	{
		var 舞台长 = Stage.width;
		var 舞台高 = Stage.height - 64;
		var 卷屏x最小坐标值 = 舞台长 - 背景长;
		var 卷屏y最小坐标值 = 舞台高 - 背景高;
		var 卷屏x最大坐标值 = 0;
		var 卷屏y最大坐标值 = 0;
		var 左横向卷屏中心坐标 = 舞台长 * 0.5 + 100;
		var 右横向卷屏中心坐标 = 舞台长 * 0.5 - 100;
		var 纵向卷屏中心坐标 = 舞台高 - 100;
		//目前的逻辑是若地图尺寸小于屏幕尺寸则不调整坐标
		if (舞台长 < 背景长 or 舞台高 < 背景高)
		{
			var pt = {x:0, y:0};
			卷屏对象.localToGlobal(pt);
			if (卷屏对象._xscale > 0)
			{
				var aa = (右横向卷屏中心坐标 - pt.x) / 缓动系数;
				var bb = (纵向卷屏中心坐标 - pt.y) / 缓动系数;
			}
			else
			{
				var aa = (左横向卷屏中心坐标 - pt.x) / 缓动系数;
				var bb = (纵向卷屏中心坐标 - pt.y) / 缓动系数;
			}
			if (Math.abs(aa) > 1 or Math.abs(bb) > 1)
			{
				var xxx = 游戏世界._x + aa;
				var yyy = 游戏世界._y + bb;
				if (舞台长 < 背景长)
				{
					if (xxx > 卷屏x最小坐标值 and xxx < 卷屏x最大坐标值)
					{
						游戏世界._x = xxx;
					}
					else if (xxx < 卷屏x最小坐标值)
					{
						游戏世界._x = 卷屏x最小坐标值;
					}
					else if (xxx > 卷屏x最大坐标值)
					{
						游戏世界._x = 卷屏x最大坐标值;
					}
				}
				/*else
				{
					游戏世界._x = (舞台长 - 背景长) / 2;;
				}*/
				if (舞台高 < 背景高)
				{
					if (yyy > 卷屏y最小坐标值 and yyy < 卷屏y最大坐标值)
					{
						游戏世界._y = yyy;
					}
					else if (yyy < 卷屏y最小坐标值)
					{
						游戏世界._y = 卷屏y最小坐标值;
					}
					else if (yyy > 卷屏y最大坐标值)
					{
						游戏世界._y = 卷屏y最大坐标值;
					}
				}
				/*else
				{
					游戏世界._y = (舞台高 - 背景高) / 2;
				}*/
			}
		}
		/*else
		{
			游戏世界._x = (舞台长 - 背景长) / 2;
			游戏世界._y = (舞台高 - 背景高) / 2;
		}*/
	}
}
_root.缩放画面 = function(放大倍数)
{
	var 游戏世界 = _root.gameworld;
	游戏世界.背景长 *= 放大倍数;
	游戏世界.背景高 *= 放大倍数;
	游戏世界._width *= 放大倍数;
	游戏世界._height *= 放大倍数;
	_root.横版卷屏(_root.控制目标,游戏世界.背景长,游戏世界.背景高,1);
}

//Stage.align = "TL";