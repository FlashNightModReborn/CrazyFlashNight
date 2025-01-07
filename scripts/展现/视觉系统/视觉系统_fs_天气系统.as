import org.flashNight.neur.Event.*;
import org.flashNight.naki.Interpolation.*;

_root.天气系统 = {};
//_root.开启昼夜系统 = true;

_root.天气系统.初始化 = function()
{
    this.昼夜长度 = 15 * 60 * 30;//一天15分钟
    this.小时帧数 = this.昼夜长度 / 24;
    this.光照等级更新阈值 = 0.1;
    this.使用滤镜渲染 = false;
    //this.开启昼夜系统 = false;
    this.开启昼夜系统 = true;
    this.暂停昼夜系统 = false;
    this.夜视仪情况 = {};
    this.时间倍率启动等级 = 2.5;
    this.金币时间倍率 = 1;
    this.金币时间最大倍率 = 2;
    this.经验时间倍率 = 1;
    this.经验时间最大倍率 = 2;
    this.人物信息透明度 = 100;
    this.天气情况 = "正常";
    this.空间情况 = "室外";
    this.视觉情况 = "光照";
    //this.当前时间 = 6 + 12;
    this.当前时间 = 6;
    this.当前帧数 = 0;
    this.昼夜光照 = [];
    this.昼夜光照[0] = 0;
    this.昼夜光照[1] = 0;
    this.昼夜光照[2] = 1;
    this.昼夜光照[3] = 4;
    this.昼夜光照[4] = 7
    this.昼夜光照[5] = 7;
    this.昼夜光照[6] = 7;
    this.昼夜光照[7] = 7;
    this.昼夜光照[8] = 7;
    this.昼夜光照[9] = 7;
    this.昼夜光照[10] = 7;
    this.昼夜光照[11] = 7;
    this.昼夜光照[12] = 9;
    this.昼夜光照[13] = 7;
    this.昼夜光照[14] = 7;
    this.昼夜光照[15] = 7;
    this.昼夜光照[16] = 7;
    this.昼夜光照[17] = 7;
    this.昼夜光照[18] = 7;
    this.昼夜光照[19] = 4;
    this.昼夜光照[20] = 1;
    this.昼夜光照[21] = 0;
    this.昼夜光照[22] = 0;
    this.昼夜光照[23] = 0;
    this.当前光照等级 = this.昼夜光照[this.当前时间];
    this.光照等级最大值 = 9;
    this.光照等级最小值 = 0;
    this.最大光照 = this.光照等级最大值;
    this.最小光照 = this.光照等级最小值;
    this.无限过图环境信息 = null;
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

_root.天气系统.获得当前光照等级 = function()
{
    var 时间 = this.获得当前时间();
    var 光照等级 = 0;
    if((时间 < 4 and 时间 > 1) or (时间 < 13 and 时间 > 11) or (时间 < 21 and 时间 > 18))
    {
        var baseLevel = Math.floor(时间);
        var nextLevel = Math.ceil(时间);
        光照等级 = Interpolation.linear(时间, baseLevel, nextLevel, this.昼夜光照[baseLevel], this.昼夜光照[nextLevel]);
    }
    else if((时间 <= 11 and 时间 >= 4) or (时间 <= 18 and 时间 >= 13))
    {
        光照等级 = 7;
    }
    
    if(光照等级 > this.最大光照)
    {
        光照等级 = this.最大光照;
    }
    else if(光照等级 < this.最小光照)
    {
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
            夜视仪 = {};
        }
    }

    //_root.服务器.发布服务器消息(_root.常用工具函数.对象转JSON(夜视仪));
    if(光照等级 <= this.时间倍率启动等级 && !夜视仪.视觉情况)
    {
        bus.publish("WeatherTimeRateUpdated");
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
    this.经验时间倍率 = Interpolation.linear(光照等级, 0, this.时间倍率启动等级, this.经验时间最大倍率, 1);
    this.人物信息透明度 = Interpolation.linear(光照等级, 0, this.时间倍率启动等级, 0, 100);
}, _root.天气系统);