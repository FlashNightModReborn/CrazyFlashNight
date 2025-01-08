import org.flashNight.neur.Event.*;
import org.flashNight.naki.Interpolation.*;
import org.flashNight.gesh.xml.LoadXml.WeatherSystemConfigLoader;

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

_root.天气系统.配置环境 = function (环境信息) 
{
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

_root.天气系统.获得当前光照等级 = function() {
    var 时间 = this.获得当前时间();
    var 光照等级 = 7; // 默认光照等级

    // 检查是否在需要插值的时间范围内
    if ((时间 > 1 && 时间 < 4) || (时间 > 11 && 时间 < 13) || (时间 > 18 && 时间 < 21)) {
        var baseLevel = Math.floor(时间);
        var nextLevel = Math.ceil(时间);
        光照等级 = Interpolatior.linear(时间, baseLevel, nextLevel, this.昼夜光照[baseLevel], this.昼夜光照[nextLevel]);
    }

    // 限制光照等级在最小值和最大值之间
    光照等级 = Math.max(this.最小光照, Math.min(光照等级, this.最大光照));

    // 更新当前光照等级如果变化超过阈值或当前光照等级未定义
    if (Math.abs(光照等级 - this.当前光照等级) > this.光照等级更新阈值 || this.当前光照等级 == undefined) {
        this.当前光照等级 = 光照等级;
    }

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
            夜视仪 = {};
        }
    }

    //_root.服务器.发布服务器消息(_root.常用工具函数.对象转JSON(夜视仪));
    if(光照等级 <= this.时间倍率启动等级 && !夜视仪.视觉情况)
    {
        bus.publish("WeatherTimeRateUpdated", 光照等级);
    }
    else
    {
        this.金币时间倍率 = 1;
        this.经验时间倍率 = 1;
        this.人物信息透明度 = 100;
    }

    _root.色彩引擎.根据光照调整颜色(_root.gameworld, 光照等级, 视觉情况, this.使用滤镜渲染);
    //_root.服务器.发布服务器消息(光照等级 + " : " + this.最大光照 + " : " + this.最小光照 + " " + 视觉情况);
    //_root.服务器.发布服务器消息(this.金币时间倍率);
    switch(this.空间情况)
    {
        case "室外":_root.色彩引擎.根据光照调整颜色(_root.天空盒, 光照等级, 视觉情况, false);break;
        case "室内":
        default: break;
    }
};


EventBus.getInstance().subscribe("WeatherUpdated", function() {
    this.设置当前天气();
}, _root.天气系统);

EventBus.getInstance().subscribe("WeatherTimeRateUpdated", function(光照等级) {
    this.金币时间倍率 = Interpolatior.linear(光照等级, 0, this.时间倍率启动等级, this.金币时间最大倍率, 1);
    this.经验时间倍率 = Interpolatior.linear(光照等级, 0, this.时间倍率启动等级, this.经验时间最大倍率, 1);
    this.人物信息透明度 = Interpolatior.linear(光照等级, 0, this.时间倍率启动等级, 0, 100);
}, _root.天气系统);