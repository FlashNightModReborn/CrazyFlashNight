/**
 * 视觉系统_fs_天气系统.as — 兼容垫片
 *
 * 核心逻辑已迁移至 org.flashNight.arki.weather.WeatherSystem（class 化单例）。
 * 本帧脚本负责：
 * 1. 创建单例并触发异步初始化
 * 2. 挂载 _root.天气系统 最低兼容引用
 * 3. 保留 _root.配置环境信息() 工具函数（依赖 _root 工具函数，暂不迁移）
 */
import org.flashNight.arki.weather.*;

// ==================== 创建单例 + 初始化 ====================

var ws:WeatherSystem = WeatherSystem.getInstance();
ws.setupLegacyBridge();
ws.initialize();
_root.天气系统 = ws;

// ==================== _root.配置环境信息() ====================
// 保留在帧脚本中：依赖 _root.配置数据为数组、_root.解析背景元素 等 _root 工具函数

_root.配置环境信息 = function(当前配置, 默认配置):Object{
	if(!当前配置) return null;
	var 环境信息:Object = {};
	环境信息.地址 = 当前配置.BackgroundURL;
	//地图尺寸
	环境信息.对齐原点 = 当前配置.Alignment ? true : 默认配置.对齐原点;
	环境信息.Xmin = !isNaN(当前配置.Xmin) ? Number(当前配置.Xmin) : 默认配置.Xmin;
	环境信息.Xmax = !isNaN(当前配置.Xmax) ? Number(当前配置.Xmax) : 默认配置.Xmax;
	环境信息.Ymin = !isNaN(当前配置.Ymin) ? Number(当前配置.Ymin) : 默认配置.Ymin;
	环境信息.Ymax = !isNaN(当前配置.Ymax) ? Number(当前配置.Ymax) : 默认配置.Ymax;
	环境信息.背景长 = !isNaN(当前配置.Width) ? Number(当前配置.Width) : 默认配置.背景长;
	环境信息.背景高 = !isNaN(当前配置.Height) ? Number(当前配置.Height) : 默认配置.背景高;
	//后景信息
	环境信息.地平线高度 = !isNaN(当前配置.Horizon) ? 当前配置.Horizon : 默认配置.地平线高度;
	环境信息.后景 = 当前配置.Skybox ? _root.配置数据为数组(当前配置.Skybox) : 默认配置.后景;
	环境信息.禁用天空 = 当前配置.DisableSky == true ? true : 默认配置.禁用天空;
	//天气信息
	环境信息.天气情况 = 当前配置.WeatherCondition != undefined ? 当前配置.WeatherCondition : 默认配置.天气情况;
	环境信息.空间情况 = 当前配置.SpaceCondition != undefined ? 当前配置.SpaceCondition : 默认配置.空间情况;
	环境信息.视觉情况 = 当前配置.VisualCondition != undefined ? 当前配置.VisualCondition : 默认配置.视觉情况;
	环境信息.最大光照 = 当前配置.MaxIllumination != undefined ? Number(当前配置.MaxIllumination) : 默认配置.最大光照;
	环境信息.最小光照 = 当前配置.MinIllumination != undefined ? Number(当前配置.MinIllumination) : 默认配置.最小光照;
	//背景元素
	环境信息.背景元素 = 当前配置.Instances ? _root.解析背景元素(_root.配置数据为数组(当前配置.Instances.Instance)) : 默认配置.背景元素;
	//无限过图参数
	if(当前配置.Door){
		var 门数据 = _root.配置数据为数组(当前配置.Door);
		环境信息.门 = new Object();
		for(var i=0; i<门数据.length; i++){
			var door = 门数据[i];
			环境信息.门[door.Index] = door;
		}
	}else{
		环境信息.门 = 默认配置.门;
	}
	环境信息.地图碰撞箱 = 当前配置.Collision ? _root.配置数据为数组(当前配置.Collision) : 默认配置.地图碰撞箱;
	环境信息.左侧出生线 = 当前配置.LeftSpawnLine ? 当前配置.LeftSpawnLine : 默认配置.左侧出生线;
	环境信息.右侧出生线 = 当前配置.RightSpawnLine ? 当前配置.RightSpawnLine : 默认配置.右侧出生线;
	//基地场景额外数据
	环境信息.佣兵刷新数据 = 当前配置.MercenaryRefresh ? 当前配置.MercenaryRefresh : 默认配置.佣兵刷新数据;
	环境信息.BGM = 当前配置.BGM ? 当前配置.BGM : 默认配置.BGM;

	return 环境信息;
}
