import flash.geom.ColorTransform;
import flash.filters.*;
import org.flashNight.naki.DataStructures.*;
import org.flashNight.arki.render.*;
import org.flashNight.sara.util.*;


_root.设置色彩 = function(对象, 红色乘数, 绿色乘数, 蓝色乘数, 红色偏移, 绿色偏移, 蓝色偏移, 透明乘数, 透明偏移)
{
	var 色彩 = 对象.transform.colorTransform;


	色彩.redMultiplier = isNaN(红色乘数) ? 色彩.redMultiplier : 红色乘数;
	色彩.greenMultiplier = isNaN(绿色乘数) ? 色彩.greenMultiplier : 绿色乘数;
	色彩.blueMultiplier = isNaN(蓝色乘数) ? 色彩.blueMultiplier : 蓝色乘数;

	色彩.redOffset = isNaN(红色偏移) ? 色彩.redOffset : 红色偏移;
	色彩.greenOffset = isNaN(绿色偏移) ? 色彩.greenOffset : 绿色偏移;
	色彩.blueOffset = isNaN(蓝色偏移) ? 色彩.blueOffset : 蓝色偏移;
	色彩.alphaMultiplier = isNaN(透明乘数) ? 色彩.alphaMultiplier : 透明乘数;
	色彩.alphaOffset = isNaN(透明偏移) ? 色彩.alphaOffset : 透明偏移;

	对象.transform.colorTransform = 色彩;

};

_root.重置色彩 = function(对象)
{
	_root.设置色彩(对象,1,1,1,0,0,0,1,0);
};
_root.重置透明 = function(对象)
{
	_root.设置色彩(对象,NaN,NaN,NaN,NaN,NaN,NaN,1,0);
};
_root.红化色彩 = function(对象, 红化强度)
{
	红化强度 = isNaN(红化强度) ? 75 : 红化强度;
	_root.设置色彩(对象,NaN,NaN,NaN,NaN,-红化强度,-红化强度,NaN,NaN);
};
_root.受击色彩 = function(对象)
{

	_root.设置色彩(对象,NaN,NaN,NaN,-10,-40,-40,NaN,NaN);
};
_root.亮化色彩 = function(对象, 亮化强度)
{
	亮化强度 = isNaN(亮化强度) ? 75 : 亮化强度;
	_root.设置色彩(对象,NaN,NaN,NaN,亮化强度,亮化强度,亮化强度,NaN,NaN);
};
_root.暗化色彩 = function(对象, 暗化强度)
{
	暗化强度 = isNaN(暗化强度) ? 75 : 暗化强度;
	_root.设置色彩(对象,NaN,NaN,NaN,-暗化强度,-暗化强度,-暗化强度,NaN,NaN);
};
_root.透明色彩 = function(对象, 透明强度)
{
	透明强度 = isNaN(透明强度) ? 75 : 透明强度;
	_root.设置色彩(对象,NaN,NaN,NaN,NaN,NaN,NaN,NaN,-透明强度);
};

_root.受击变红 = function(间隔时间, 对象) 
{  
	if(!对象.受击变红)
	{
		_root.受击色彩(对象);  // 设置对象受击时的色彩
		对象.受击变红 = true;  
	}
 
    _root.帧计时器.添加或更新任务(对象, "_受击变红", function() {
         _root.设置色彩(对象, NaN, NaN, NaN, 0, 0, 0, NaN, NaN);  // 恢复对象的原始色彩   
		 对象.受击变红 = false;
    }, 间隔时间);
};
_root.镜闪变亮 = function(间隔时间, 对象)
{
	var _this:Object = 对象;// 在外部保存对当前对象的引用
	var executed:Boolean = false;
	var 当前时间:Number = getTimer();


	function pause2()
	{
		var 探针时间:Number = getTimer();

		if (探针时间 >= _this.恢复时间)
		{
			_root.重置色彩(_this);
		}
	}


	_root.亮化色彩(_this);
	_root.透明色彩(_this);
	_this.恢复时间 = 当前时间 + 间隔时间;
	clearInterval(_this.镜闪变亮判定);
	_this.镜闪变亮判定 = setTimeout(pause2, 间隔时间);
};

_root.敌方打击伤害数字色彩 = function(对象)
{
	_root.设置色彩(对象,1,0.2,0.2,0,0,0,1,0);
};



// 通用的设置滤镜函数
_root.色彩引擎.设置滤镜 = function(影片剪辑, 滤镜实例, 滤镜种类) 
{
    if (影片剪辑 == null) return; // 如果影片剪辑是null，直接返回
    var filters = 影片剪辑.filters;
    var found = false;
    for (var i = 0; i < filters.length; i++) {
        if (filters[i] instanceof 滤镜种类) {
            filters[i] = 滤镜实例;
            found = true;
            break;
        }
    }
    if (!found) {
        filters.push(滤镜实例);
    }
    影片剪辑.filters = filters;
};

_root.色彩引擎.检查并删除滤镜 = function(影片剪辑, 滤镜种类) 
{
    if (影片剪辑 == null) return; // 如果影片剪辑是null，直接返回
    var filters = 影片剪辑.filters;
    for (var i = filters.length - 1; i >= 0; i--) {
        if (filters[i] instanceof 滤镜种类) {
            filters.splice(i, 1); // 删除指定索引的滤镜
        }
    }
    影片剪辑.filters = filters;
};

// 升级后的设置投影滤镜函数
_root.色彩引擎.设置投影滤镜 = function(影片剪辑, 距离, 角度, 颜色, 透明度, X模糊, Y模糊, 强度, 质量, 内部, 挖空, 隐藏对象) {
    if (arguments.length == 1) {
        this.检查并删除滤镜(影片剪辑, flash.filters.DropShadowFilter);
        return;
    }
    距离 = isNaN(距离) ? 4 : 距离;
    角度 = isNaN(角度) ? 45 : 角度;
    颜色 = 颜色 == undefined ? 0x000000 : 颜色;
    透明度 = isNaN(透明度) ? 0.8 : 透明度;
    X模糊 = isNaN(X模糊) ? 8 : X模糊;
    Y模糊 = isNaN(Y模糊) ? 8 : Y模糊;
    强度 = isNaN(强度) ? 1 : 强度;
    质量 = isNaN(质量) ? 1 : 质量;
    内部 = 内部 == undefined ? false : 内部;
    挖空 = 挖空 == undefined ? false : 挖空;
    隐藏对象 = 隐藏对象 == undefined ? false : 隐藏对象;
    var shadow = new flash.filters.DropShadowFilter(距离, 角度, 颜色, 透明度, X模糊, Y模糊, 强度, 质量, 内部, 挖空, 隐藏对象);
    this.设置滤镜(影片剪辑, shadow, flash.filters.DropShadowFilter);
};

// 设置模糊滤镜
_root.色彩引擎.设置模糊滤镜 = function(影片剪辑, X模糊, Y模糊, 质量) 
{
    if (arguments.length == 1) {
        this.检查并删除滤镜(影片剪辑, flash.filters.BlurFilter);
        return;
    }
    X模糊 = isNaN(X模糊) ? 10 : X模糊;
    Y模糊 = isNaN(Y模糊) ? 10 : Y模糊;
    质量 = isNaN(质量) ? 1 : 质量;
    var blur = new flash.filters.BlurFilter(X模糊, Y模糊, 质量);
    this.设置滤镜(影片剪辑, blur, flash.filters.BlurFilter);
};


// 设置发光滤镜
_root.色彩引擎.设置发光滤镜 = function(影片剪辑, 颜色, 透明度, X模糊, Y模糊, 强度, 质量, 内部, 挖空) {
    if (arguments.length == 1) {
        this.检查并删除滤镜(影片剪辑, flash.filters.GlowFilter);
        return;
    }
    颜色 = 颜色 == undefined ? 0xFF0000 : 颜色;
    透明度 = isNaN(透明度) ? 1 : 透明度;
    X模糊 = isNaN(X模糊) ? 10 : X模糊;
    Y模糊 = isNaN(Y模糊) ? 10 : Y模糊;
    强度 = isNaN(强度) ? 2 : 强度;
    质量 = isNaN(质量) ? 1 : 质量;
    内部 = 内部 == undefined ? false : 内部;
    挖空 = 挖空 == undefined ? false : 挖空;
    var glow = new flash.filters.GlowFilter(颜色, 透明度, X模糊, Y模糊, 强度, 质量, 内部, 挖空);
    this.设置滤镜(影片剪辑, glow, flash.filters.GlowFilter);
};


// 设置斜角滤镜
_root.色彩引擎.设置斜角滤镜 = function(影片剪辑, 距离, 角度, 高光颜色, 高光透明度, 阴影颜色, 阴影透明度, X模糊, Y模糊, 强度, 质量, 类型, 挖空) {
    if (arguments.length == 1) {
        this.检查并删除滤镜(影片剪辑, flash.filters.BevelFilter);
        return;
    }
    距离 = isNaN(距离) ? 4 : 距离;
    角度 = isNaN(角度) ? 45 : 角度;
    高光颜色 = 高光颜色 == undefined ? 0xFFFFFF : 高光颜色;
    高光透明度 = isNaN(高光透明度) ? 0.8 : 高光透明度;
    阴影颜色 = 阴影颜色 == undefined ? 0x000000 : 阴影颜色;
    阴影透明度 = isNaN(阴影透明度) ? 0.8 : 阴影透明度;
    X模糊 = isNaN(X模糊) ? 8 : X模糊;
    Y模糊 = isNaN(Y模糊) ? 8 : Y模糊;
    强度 = isNaN(强度) ? 1 : 强度;
    质量 = isNaN(质量) ? 1 : 质量;
    类型 = 类型 == undefined ? "inner" : 类型;
    挖空 = 挖空 == undefined ? false : 挖空;
    var bevel = new flash.filters.BevelFilter(距离, 角度, 高光颜色, 高光透明度, 阴影颜色, 阴影透明度, X模糊, Y模糊, 强度, 质量, 类型, 挖空);
    this.设置滤镜(影片剪辑, bevel, flash.filters.BevelFilter);
};


_root.色彩引擎.设置渐变发光滤镜 = function(影片剪辑, 距离, 角度, 颜色数组, 透明度数组, 比例数组, X模糊, Y模糊, 强度, 质量, 类型, 挖空) {
    if (arguments.length == 1) {
        this.检查并删除滤镜(影片剪辑, flash.filters.GradientGlowFilter);
        return;
    }
    距离 = isNaN(距离) ? 0 : 距离;
    角度 = isNaN(角度) ? 45 : 角度;
    颜色数组 = 颜色数组 || [0xFF0000, 0x000000];
    透明度数组 = 透明度数组 || [1, 1];
    比例数组 = 比例数组 || [0, 255];
    X模糊 = isNaN(X模糊) ? 8 : X模糊;
    Y模糊 = isNaN(Y模糊) ? 8 : Y模糊;
    强度 = isNaN(强度) ? 1 : 强度;
    质量 = isNaN(质量) ? 1 : 质量;
    类型 = 类型 || "outer";
    挖空 = 挖空 == undefined ? false : 挖空;
    var gradientGlow = new flash.filters.GradientGlowFilter(距离, 角度, 颜色数组, 透明度数组, 比例数组, X模糊, Y模糊, 强度, 质量, 类型, 挖空);
    this.设置滤镜(影片剪辑, gradientGlow, flash.filters.GradientGlowFilter);
};


_root.色彩引擎.设置渐变斜角滤镜 = function(影片剪辑, 距离, 角度, 颜色数组, 透明度数组, 比例数组, X模糊, Y模糊, 强度, 质量, 类型, 挖空) {
    if (arguments.length == 1) {
        this.检查并删除滤镜(影片剪辑, flash.filters.GradientBevelFilter);
        return;
    }
    距离 = isNaN(距离) ? 4 : 距离;
    角度 = isNaN(角度) ? 45 : 角度;
    颜色数组 = 颜色数组 || [0xFFFFFF, 0x000000];
    透明度数组 = 透明度数组 || [1, 1];
    比例数组 = 比例数组 || [0, 128, 255];
    X模糊 = isNaN(X模糊) ? 8 : X模糊;
    Y模糊 = isNaN(Y模糊) ? 8 : Y模糊;
    强度 = isNaN(强度) ? 1 : 强度;
    质量 = isNaN(质量) ? 1 : 质量;
    类型 = 类型 || "inner";
    挖空 = 挖空 == undefined ? false : 挖空;
    var gradientBevel = new flash.filters.GradientBevelFilter(距离, 角度, 颜色数组, 透明度数组, 比例数组, X模糊, Y模糊, 强度, 质量, 类型, 挖空);
    this.设置滤镜(影片剪辑, gradientBevel, flash.filters.GradientBevelFilter);
};



_root.色彩引擎.空调整颜色 = new flash.geom.ColorTransform();

_root.色彩引擎.初级调整颜色 = function(影片剪辑, 参数)
{
    if (参数 instanceof flash.geom.ColorTransform) 
    {
        影片剪辑.transform.colorTransform = 参数;
        return 参数;// 检查是否直接传入了ColorTransform对象
    }

    if (!参数) 
    {
        影片剪辑.transform.colorTransform = _root.色彩引擎.空调整颜色;
        return null;// 如果没有传入任何参数，移除当前的ColorTransform
    }

    var 色彩:ColorTransform = new flash.geom.ColorTransform();

    // 解析基础颜色乘数和偏移
    色彩.redMultiplier = 参数.hasOwnProperty('红色乘数') ? 参数['红色乘数'] : 1;
    色彩.greenMultiplier = 参数.hasOwnProperty('绿色乘数') ? 参数['绿色乘数'] : 1;
    色彩.blueMultiplier = 参数.hasOwnProperty('蓝色乘数') ? 参数['蓝色乘数'] : 1;
    色彩.alphaMultiplier = 参数.hasOwnProperty('透明乘数') ? 参数['透明乘数'] : 1;

    色彩.redOffset = 参数.hasOwnProperty('红色偏移') ? 参数['红色偏移'] : 0;
    色彩.greenOffset = 参数.hasOwnProperty('绿色偏移') ? 参数['绿色偏移'] : 0;
    色彩.blueOffset = 参数.hasOwnProperty('蓝色偏移') ? 参数['蓝色偏移'] : 0;
    色彩.alphaOffset = 参数.hasOwnProperty('透明偏移') ? 参数['透明偏移'] : 0;

    // 高级调整
    var 亮度 = 参数.hasOwnProperty('亮度') ? 参数['亮度'] : 0;
    var 对比度 = 参数.hasOwnProperty('对比度') ? 参数['对比度'] : 0;
    var 饱和度 = 参数.hasOwnProperty('饱和度') ? 参数['饱和度'] : 0;
    var 色相 = 参数.hasOwnProperty('色相') ? 参数['色相'] : 0;

    // 色相调整：冷暖（正值增加红色，负值增加蓝绿色）
    
    // 色相旋转，将色相值限制在0-360度范围内
    var 新色相 = (色彩.redOffset + 色相) % 360;
    if (新色相 < 0) 新色相 += 360; // 如果新色相为负值，转换为正值

    // 计算色相差值
    var 色相差值 = 新色相 - 色彩.redOffset;
    if (色相差值 > 180) 色相差值 -= 360; // 如果差值大于180度，则减去360度以找到最短路径
    if (色相差值 < -180) 色相差值 += 360; // 如果差值小于-180度，则加上360度以找到最短路径

    // 映射色相差值到RGB偏移
    // 假设整个色环可以映射到255的RGB值范围内
    var rgb差值 = 色相差值 / 360 * 255 / 3;
    //_root.服务器.发布服务器消息(色相 + ' ' + rgb差值);
    // 更新RGB偏移值以模拟色相旋转
    色彩.redOffset += rgb差值;
    色彩.greenOffset -= rgb差值 / 2;
    色彩.blueOffset -= rgb差值 / 2;

        // 对比度调整（简化计算，具体公式可根据需要调整）
    var 对比度乘数 = 1 + 对比度 / 100;
    var 对比度偏移 = 128 * (1 - 对比度乘数);

    // 应用对比度乘数和偏移
    色彩.redMultiplier *= 对比度乘数;
    色彩.greenMultiplier *= 对比度乘数;
    色彩.blueMultiplier *= 对比度乘数;

    色彩.redOffset += 对比度偏移 + 亮度;
    色彩.greenOffset += 对比度偏移 + 亮度;
    色彩.blueOffset += 对比度偏移 + 亮度;
    
    饱和度 += 色相差值 / 5;
    // 饱和度调整：尝试调整为灰色的相反方向增加饱和度
    if (饱和度 !== 0) {
        var 灰度平均乘数 = (色彩.redMultiplier + 色彩.greenMultiplier + 色彩.blueMultiplier) / 3;
        色彩.redMultiplier = 灰度平均乘数 + (色彩.redMultiplier - 灰度平均乘数) * (1 + 饱和度 / 100);
        色彩.greenMultiplier = 灰度平均乘数 + (色彩.greenMultiplier - 灰度平均乘数) * (1 + 饱和度 / 100);
        色彩.blueMultiplier = 灰度平均乘数 + (色彩.blueMultiplier - 灰度平均乘数) * (1 + 饱和度 / 100);
    }

    // 应用修改后的 ColorTransform
    if (影片剪辑 and 影片剪辑.transform) 影片剪辑.transform.colorTransform = 色彩;
    return 色彩;
};

_root.色彩引擎.亮度矩阵 = function(value:Number):Array
{
	return [1, 0, 0, 0, value,
			0, 1, 0, 0, value, 
			0, 0, 1, 0, value, 
			0, 0, 0, 1, 0];// 生成亮度调整矩阵
};

_root.色彩引擎.对比度矩阵 = function(value:Number):Array
{
	var scale:Number = value + 1;
	var offset:Number = 128 * (1 - scale);
	return [scale, 0, 0, 0, offset, 
			0, scale, 0, 0, offset, 
			0, 0, scale, 0, offset, 
			0, 0, 0, 1, 0];// 生成对比度调整矩阵
};

_root.色彩引擎.饱和度矩阵 = function(value:Number):Array
{
	var lumaR:Number = 0.2126;
	var lumaG:Number = 0.7152;
	var lumaB:Number = 0.0722;
	var invSat:Number = 1 - value;
	var invLumR:Number = invSat * lumaR;
	var invLumG:Number = invSat * lumaG;
	var invLumB:Number = invSat * lumaB;
	return [(invLumR + value), invLumG, invLumB, 0, 0, 
			invLumR, (invLumG + value), invLumB, 0, 0, 
			invLumR, invLumG, (invLumB + value), 0, 0, 
			0, 0, 0, 1, 0];// 生成饱和度调整矩阵
};

_root.色彩引擎.色相矩阵 = function(value:Number):Array
{
	var cosVal:Number = Math.cos(value);
	var sinVal:Number = Math.sin(value);
	return [((cosVal + (1.0 - cosVal) * 0.213)), ((1.0 - cosVal) * 0.715 - sinVal * 0.715), ((1.0 - cosVal) * 0.072 + sinVal * 0.928), 0, 0,
	        ((1.0 - cosVal) * 0.213 + sinVal * 0.143), ((cosVal + (1.0 - cosVal) * 0.715)), ((1.0 - cosVal) * 0.072 - sinVal * 0.283), 0, 0, 
			((1.0 - cosVal) * 0.213 - sinVal * 0.787), ((1.0 - cosVal) * 0.715 + sinVal * 0.715), ((cosVal + (1.0 - cosVal) * 0.072)), 0, 0, 
			0, 0, 0, 1, 0];// 生成色相调整矩阵
};


_root.色彩引擎.组合色彩矩阵 = function(base:Array, overlay:Array):Array 
{
	var result:Array = new Array(20);
	for (var i:Number = 0; i < 4; i++)
	{
		var ii = i * 5;
		for (var j:Number = 0; j < 4; j++)
		{
			result[ii + j] = base[ii + 0] * overlay[0 + j] + 
			   					base[ii + 1] * overlay[5 + j] + 
								base[ii + 2] * overlay[10 + j] + 
								base[ii + 3] * overlay[15 + j];
		}
		result[ii + 4] = base[ii + 0] * overlay[4] + 
                         base[ii + 1] * overlay[9] +
                         base[ii + 2] * overlay[14] + 
                         base[ii + 3] * overlay[19] + 
                         base[ii + 4]; // 加上原始偏移量
	}
	
	return result;// 矩阵组合函数
};

_root.色彩引擎.调整颜色 = function(影片剪辑, 参数)
{
    if (参数 instanceof flash.filters.ColorMatrixFilter) 
    {
        this.设置滤镜(影片剪辑, 参数, flash.filters.ColorMatrixFilter);
        return;// 检查是否直接传入了ColorMatrixFilter对象
    }

    if (!参数) 
    {
        this.检查并删除滤镜(影片剪辑, flash.filters.ColorMatrixFilter);
        return;// 如果没有传入任何参数，移除当前的ColorMatrixFilter
    }

    // 默认矩阵为恒等矩阵
    var 矩阵:Array = [1, 0, 0, 0, 0, 
                      0, 1, 0, 0, 0, 
                      0, 0, 1, 0, 0, 
                      0, 0, 0, 1, 0];

    // 应用基本颜色乘数和偏移量
    var baseMatrix:Array = [
        参数.hasOwnProperty('红色乘数') ? 参数['红色乘数'] : 1, 0, 0, 0, 参数.hasOwnProperty('红色偏移') ? 参数['红色偏移'] : 0,
        0, 参数.hasOwnProperty('绿色乘数') ? 参数['绿色乘数'] : 1, 0, 0, 参数.hasOwnProperty('绿色偏移') ? 参数['绿色偏移'] : 0,
        0, 0, 参数.hasOwnProperty('蓝色乘数') ? 参数['蓝色乘数'] : 1, 0, 参数.hasOwnProperty('蓝色偏移') ? 参数['蓝色偏移'] : 0,
        0, 0, 0, 参数.hasOwnProperty('透明乘数') ? 参数['透明乘数'] : 1, 参数.hasOwnProperty('透明偏移') ? 参数['透明偏移'] : 0
    ];
    矩阵 = _root.色彩引擎.组合色彩矩阵(矩阵, baseMatrix);

    // 应用色彩调整
    if (参数.hasOwnProperty('亮度')) 矩阵 = _root.色彩引擎.组合色彩矩阵(矩阵, _root.色彩引擎.亮度矩阵(参数['亮度']));
    if (参数.hasOwnProperty('对比度')) 矩阵 = _root.色彩引擎.组合色彩矩阵(矩阵, _root.色彩引擎.对比度矩阵(参数['对比度'] * 0.01));
    if (参数.hasOwnProperty('饱和度')) 矩阵 = _root.色彩引擎.组合色彩矩阵(矩阵, _root.色彩引擎.饱和度矩阵(参数['饱和度'] * 0.01 + 1));
    if (参数.hasOwnProperty('色相')) 矩阵 = _root.色彩引擎.组合色彩矩阵(矩阵, _root.色彩引擎.色相矩阵(参数['色相'] * Math.PI / 180));

    // 设置新的滤镜
    var 调整颜色滤镜 = new flash.filters.ColorMatrixFilter(矩阵);
    this.设置滤镜(影片剪辑, 调整颜色滤镜, flash.filters.ColorMatrixFilter);
    return 调整颜色滤镜;
};




_root.RGBtoHSV = function(r, g, b) {  
    r /= 255, g /= 255, b /= 255;  
    var max = Math.max(r, g, b), min = Math.min(r, g, b);  
    var h, s, v = max;  
  
    var d = max - min;  
    s = max === 0 ? 0 : d / max;  
  
    if (max === min) {  
        h = 0; // achromatic  
    } else {  
        switch (max) {  
            case r: h = (g - b) / d + (g < b ? 6 : 0); break;  
            case g: h = (b - r) / d + 2; break;  
            case b: h = (r - g) / d + 4; break;  
        }  
        h /= 6;  
    }  
  
    return {h: h, s: s, v: v};  
};  

_root.HSVtoRGB = function(h, s, v)
{
	var r, g, b;
	var i = Math.floor(h * 6);
	var f = h * 6 - i;
	var p = v * (1 - s);
	var q = v * (1 - f * s);
	var t = v * (1 - (1 - f) * s);

	switch (i % 6)
	{
		case 0 :
			r = v, g = t, b = p;
			break;
		case 1 :
			r = q, g = v, b = p;
			break;
		case 2 :
			r = p, g = v, b = t;
			break;
		case 3 :
			r = p, g = q, b = v;
			break;
		case 4 :
			r = t, g = p, b = v;
			break;
		case 5 :
			r = v, g = p, b = q;
			break;
	}
	return (Math.round(r * 255) << 16) | (Math.round(g * 255) << 8) | Math.round(b * 255);
}
