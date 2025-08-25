import org.flashNight.neur.Event.*;
import org.flashNight.naki.Interpolation.*;
import org.flashNight.gesh.xml.LoadXml.WeatherSystemConfigLoader;
import org.flashNight.arki.component.Effect.*;

_root.天气系统 = {};
//_root.开启昼夜系统 = true;

_root.天气系统.初始化 = function(onComplete:Function, onError:Function):Void {
    // 获取 XML 加载器实例
    var configLoader:WeatherSystemConfigLoader = WeatherSystemConfigLoader.getInstance();

    // 保存当前实例引用
    var self = this;

    // 加载配置文件
    configLoader.load(
        // 成功加载配置文件
        function(data:Object):Void {
            // 解析 GeneralParameters
            var params:Object = data.GeneralParameters;

            // 设置基础参数
            self.昼夜长度 = params.DayLength;
            self.小时帧数 = params.HourFrames;
            self.光照等级更新阈值 = params.LightUpdateThreshold;
            self.使用滤镜渲染 = params.UseFilterRendering;
            self.开启昼夜系统 = params.EnableDayNightCycle;
            self.暂停昼夜系统 = params.PauseDayNightCycle;
            self.时间倍率启动等级 = params.TimeMultiplierStartLevel;
            self.金币时间倍率 = params.CoinTimeMultiplier;
            self.金币时间最大倍率 = params.CoinTimeMaxMultiplier;
            self.经验时间倍率 = params.ExpTimeMultiplier;
            self.经验时间最大倍率 = params.ExpTimeMaxMultiplier;
            self.人物信息透明度 = params.CharacterInfoOpacity;
            self.天气情况 = params.WeatherCondition;
            self.空间情况 = params.SpaceCondition;
            self.视觉情况 = params.VisualCondition;
            self.当前时间 = params.CurrentTime;
            self.当前帧数 = params.CurrentFrame;
            self.光照等级最大值 = params.MaxLight;
            self.光照等级最小值 = params.MinLight;
            self.最大光照 = self.光照等级最大值;
            self.最小光照 = self.光照等级最小值;
            self.无限过图环境信息 = params.InfiniteMapEnvironmentInfo == "null" ? null : params.InfiniteMapEnvironmentInfo;

            // 解析光照等级
            var lightLevels:Array = data.LightLevels.Hour;
            self.昼夜光照 = [];
            for (var i:Number = 0; i < 24; i++) {
                self.昼夜光照[i] = lightLevels[i];
            }

            // 设置当前光照等级
            self.当前光照等级 = self.昼夜光照[self.当前时间];

            trace("天气系统配置已加载成功！");
            // 执行完成回调
            if (onComplete != undefined) {
                onComplete();
            }
        },

        // 加载配置失败
        function():Void {
            trace("天气系统配置加载失败，使用默认配置！");

            // 使用默认值初始化（兼容旧逻辑）
            self.昼夜长度 = 15 * 60 * 30;// 一天15分钟
            self.小时帧数 = self.昼夜长度 / 24;
            self.光照等级更新阈值 = 0.1;
            self.使用滤镜渲染 = false;
            self.开启昼夜系统 = true;
            self.暂停昼夜系统 = false;
            self.时间倍率启动等级 = 2.5;
            self.金币时间倍率 = 1;
            self.金币时间最大倍率 = 2;
            self.经验时间倍率 = 1;
            self.经验时间最大倍率 = 2;
            self.人物信息透明度 = 100;
            self.天气情况 = "正常";
            self.空间情况 = "室外";
            self.视觉情况 = "光照";
            self.当前时间 = 6;
            self.当前帧数 = 0;
            self.昼夜光照 = [0, 0, 1, 4, 7, 7, 7, 7, 7, 7, 7, 7, 9, 7, 7, 7, 7, 7, 7, 4, 1, 0, 0, 0];
            self.当前光照等级 = self.昼夜光照[self.当前时间];
            self.光照等级最大值 = 9;
            self.光照等级最小值 = 0;
            self.最大光照 = self.光照等级最大值;
            self.最小光照 = self.光照等级最小值;
            self.无限过图环境信息 = null;

            trace("默认配置已应用！");
            // 执行失败回调
            if (onError != undefined) {
                onError();
            }
        }
    );
};
_root.天气系统.初始化();
_root.天气系统.获得当前时间 = function()
{
    if(!this.开启昼夜系统) return 7;
    if(this.暂停昼夜系统) return this.当前时间;
    var 帧数 = _root.帧计时器.当前帧数;
    this.当前时间 = (this.当前时间 + (帧数 - this.当前帧数) / this.小时帧数) % 24;
    this.当前帧数 = 帧数;
    return this.当前时间;
};

//默认配置
_root.天气系统.默认环境配置 = {
    地址: "gk20_2_BG.swf",//背景swf的地址
    //地图尺寸
    对齐原点: false,
    Xmin: 50,
    Xmax: 1750,
    Ymin: 330,
    Ymax: 600,
    背景长: 1750,
    背景高: 600,
    //后景信息
    地平线高度: 200,
    后景: null,
    禁用天空: false,
    //天气信息
    天气情况: "正常",//后续或许可以随机天气，或者指定下雨沙尘暴
    空间情况: "室外",//决定是否启用天空盒
    视觉情况: "光照",//决定使用的色彩引擎方案
    最大光照: 8,
    最小光照: 4,
    //背景元素
    背景元素: null,
    //无限过图参数
    门: null,
    地图碰撞箱: null,
    左侧出生线: null,
    右侧出生线: null,
    //基地场景额外数据
    佣兵刷新数据: null,
    BGM: null
};

//目前关卡和基地场景的环境配置没有太大区别。后续可将该函数拆成两个分别对关卡和基地场景应用
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
	// 环境信息.门朝向 = 当前配置.DoorDirection ? 当前配置.DoorDirection : 默认配置.门朝向; //弃用
	环境信息.地图碰撞箱 = 当前配置.Collision ? _root.配置数据为数组(当前配置.Collision) : 默认配置.地图碰撞箱;
	环境信息.左侧出生线 = 当前配置.LeftSpawnLine ? 当前配置.LeftSpawnLine : 默认配置.左侧出生线;
	环境信息.右侧出生线 = 当前配置.RightSpawnLine ? 当前配置.RightSpawnLine : 默认配置.右侧出生线;
	//基地场景额外数据
	环境信息.佣兵刷新数据 = 当前配置.MercenaryRefresh ? 当前配置.MercenaryRefresh : 默认配置.佣兵刷新数据;
    环境信息.BGM = 当前配置.BGM ? 当前配置.BGM : 默认配置.BGM;

	return 环境信息;
}


_root.天气系统.配置环境 = function (环境信息) {
    if(this.无限过图环境信息){
        环境信息 = this.无限过图环境信息;
        this.无限过图环境信息 = null;
    }
    if (环境信息.天气情况) this.天气情况 = 环境信息.天气情况;
    if (环境信息.空间情况) this.空间情况 = 环境信息.空间情况;
    if (环境信息.视觉情况) this.视觉情况 = 环境信息.视觉情况;
    if (环境信息.最大光照 != undefined) this.最大光照 = 环境信息.最大光照;
    if (环境信息.最小光照 != undefined) this.最小光照 = 环境信息.最小光照;
}

_root.天气系统.获得当前光照等级 = function(){
    var 时间 = this.获得当前时间();
    var 光照等级 = 0;
    if((时间 < 4 && 时间 > 1) || (时间 < 13 && 时间 > 11) || (时间 < 21 && 时间 > 18)){
        var baseLevel = Math.floor(时间);
        var nextLevel = Math.ceil(时间);
        光照等级 = Interpolatior.linear(时间, baseLevel, nextLevel, this.昼夜光照[baseLevel], this.昼夜光照[nextLevel]);
    }else if((时间 <= 11 && 时间 >= 4) || (时间 <= 18 && 时间 >= 13)){
        光照等级 = 7;
    }
    
    if(光照等级 > this.最大光照){
        光照等级 = this.最大光照;
    }else if(光照等级 < this.最小光照){
        光照等级 = this.最小光照;
    }
    
    if(Math.abs(光照等级 - this.当前光照等级) > this.光照等级更新阈值 || !this.当前光照等级) this.当前光照等级 = 光照等级;
    return this.当前光照等级;
};

_root.天气系统.设置当前天气 = function()
{
    var 光照等级 = this.获得当前光照等级();
    var 视觉情况 = this.视觉情况;
    var 夜视仪 = this.夜视仪;
    var bus:EventBus = EventBus.getInstance();
    if(夜视仪.视觉情况)
    {
        if(光照等级 <= 夜视仪.最大启动亮度 && 光照等级 >= 夜视仪.最小启动亮度)
        {
            视觉情况 = 夜视仪.视觉情况;
            bus.publish("夜视仪启动", 光照等级);
        }

        else
        {
            夜视仪 = this.夜视仪 = {};
        }
    }

    //_root.服务器.发布服务器消息(_root.常用工具函数.对象转JSON(夜视仪));
    if(光照等级 <= this.时间倍率启动等级 && !夜视仪.视觉情况)
    {
        bus.publish("WeatherTimeRateUpdated", 光照等级);
    }
    else
    {
        if(this.金币时间倍率 !== 1) {
            this.金币时间倍率 = 1;
            this.经验时间倍率 = 1;
            this.人物信息透明度 = 100;

            // _root.发布消息("白天切换")
        }
    }

    LightingEngine.applyLighting(_root.gameworld, 光照等级, 视觉情况, this.使用滤镜渲染);
    //_root.服务器.发布服务器消息(光照等级 + " : " + this.最大光照 + " : " + this.最小光照 + " " + 视觉情况);
    //_root.服务器.发布服务器消息(this.金币时间倍率);
    //
    LightingEngine.applyLighting(_root.天空盒, 光照等级, 视觉情况, false);
    // switch(this.空间情况)
    // {
    //     case "室外":_root.色彩引擎.根据光照调整颜色(_root.天空盒, 光照等级, 视觉情况, false);break;
    //     case "室内":
    //     default: break;
    // }
};


EventBus.getInstance().subscribe("WeatherUpdated", _root.天气系统.设置当前天气, _root.天气系统);

EventBus.getInstance().subscribe("WeatherTimeRateUpdated", function(光照等级) {
    // _root.发布消息("WeatherTimeRateUpdated:" + 光照等级)
    this.金币时间倍率 = Interpolatior.linear(光照等级, 0, this.时间倍率启动等级, this.金币时间最大倍率, 1);
    this.经验时间倍率 = Interpolatior.linear(光照等级, 0, this.时间倍率启动等级, this.经验时间最大倍率, 1);
    this.人物信息透明度 = Interpolatior.linear(光照等级, 0, this.时间倍率启动等级, 0, 100);

    // _root.发布消息(this.金币时间倍率, this.经验时间倍率, this.人物信息透明度)
}, _root.天气系统);