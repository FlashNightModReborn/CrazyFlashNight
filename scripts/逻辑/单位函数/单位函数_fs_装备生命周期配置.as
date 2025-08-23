_root.主角函数.装载生命周期函数 = function(生命周期信息, 装备类型) 
{
    //_root.服务器.发布服务器消息(_root.格式化对象为字符串(生命周期信息));
    if(!生命周期信息) return;
    if(!this.生命周期函数列表) this.生命周期函数列表 = [];

    var 是否为主角 = this._name === _root.控制目标
    var 装备名称 = this[装备类型].name;
    var 装备种类 = this[装备类型 + "数据"].use;
    var 战技种类 = null;
    var 威力基数;

    switch(装备种类){
        case "刀": 
            战技种类 = "兵器"; 
            威力基数 = this.刀属性.power;
            break;

        case "长枪": 
            战技种类 = "长枪"; 
            威力基数 = this.长枪属性.power
            break;

        case "手部装备": 
            战技种类 = "空手"; 

        default:
            威力基数 = this.空手攻击力;
            break;
    }

    for(var each in 生命周期信息)
    {
        if(each.indexOf("attr") != -1)
        {
            var attributes = 生命周期信息[each];
            var init = attributes.init;      //初始化函数
            var cycle = attributes.cycle;    //周期函数
            var skill = attributes.skill;    //兼容主动战技
            var bullet = attributes.bullet;  //自动配置子弹 
            var data = attributes.data;      //自动配置备用武器数据

            var 标签名 = 装备名称 + "_" + 装备类型 +  "_" + cycle.cycleRoutines + each; // 构建标签名，用于周期性任务的唯一标识

            var 反射对象 = {标签名:标签名,
                           初始化函数:init.initRoutines,
                           初始化参数:init.initParam, 
                           生命周期函数:cycle.cycleRoutines, 
                           生命周期参数:cycle.cycleParam, 
                           装备类型:装备类型, 
                           装备名称:装备名称,
                           装备种类:装备种类, 
                           是否为主角:是否为主角,
                           生命周期函数列表:this.生命周期函数列表,
                           版本号:this.version,
                           自机:this}

            if(skill)
            {
                if(战技种类 && !this.主动战技[战技种类])
                {
                    this.装载主动战技(skill,战技种类);

                    if(是否为主角)
                    {
                        _root.玩家信息界面.玩家必要信息界面.战技栏.战技栏图标刷新();
                    }
                }
            }
            
            if(bullet)
            {       
                反射对象.子弹配置 = {};
                //_root.服务器.发布服务器消息("装载子弹配置 " + _root.常用工具函数.对象转JSON(bullet, true));

                for(var b in bullet)
                {
                    反射对象.子弹配置[b] = _root.子弹属性初始化(null, null, this);
                    var 子弹属性 = 反射对象.子弹配置[b];
                    var 子弹参数对象 = bullet[b];
                    var 子弹威力 = 子弹参数对象.power
                    var 威力百分比 = Number(子弹威力.split("%")[0]);

                    子弹属性.声音 = 子弹参数对象.sound ? 子弹参数对象.sound : "";
                    子弹属性.霰弹值 = 子弹参数对象.split ? 子弹参数对象.split : 1;
                    子弹属性.子弹散射度 = 子弹参数对象.diffusion ? 子弹参数对象.diffusion : 5;
                    子弹属性.子弹种类 = 子弹参数对象.bullet ? 子弹参数对象.bullet : "诛神雷电";
                    子弹属性.发射效果 = 子弹参数对象.muzzle ? 子弹参数对象.muzzle : "";
                    子弹属性.子弹速度 = 子弹参数对象.velocity ? 子弹参数对象.velocity : 6;
                    子弹属性.击中后子弹的效果 = 子弹参数对象.bullethit ? 子弹参数对象.bullethit : "";
                    子弹属性.Z轴攻击范围 = 子弹属性.range ? 子弹属性.range : 300;
                    子弹属性.击倒率 = 子弹参数对象.impact ? 子弹参数对象.impact : 1;
                    子弹属性.子弹威力 = (子弹威力.indexOf("%")  === 子弹威力.length - 1 && 威力百分比 > 0) ? (威力百分比 / 100 * 威力基数) : 子弹威力 ? 子弹威力 : 威力基数;
                }

                //_root.服务器.发布服务器消息("装载配置完成 " + _root.常用工具函数.对象转JSON(反射对象.子弹配置, true));
            }


            if(data)
            {       
                反射对象.data = data;
            }

            if(init)
            {
                var initFunc = _root.装备生命周期函数[init.initRoutines];
                if(initFunc)
                {
                    initFunc(反射对象, init.initParam || {});// 额外传入标签名，用于模拟反射
                }
            }
            
            if(cycle)
            {
                var cycleFunc = _root.装备生命周期函数[cycle.cycleRoutines];    
                if(cycleFunc)
                {
                    var 任务ID = _root.帧计时器.taskManager.addLifecycleTask(
                        this,
                        标签名,
                        cycleFunc,
                        0,
                        [反射对象, cycle.cycleParam || {}]
                    );
                    反射对象.生命周期任务ID = 任务ID;
                    var 卸载对象 = {动作:function(额外参数){
                                         _root.帧计时器.taskManager.removeTask(额外参数.任务ID);
                                         //_root.服务器.发布服务器消息("卸载 " + cycle.cycleRoutines);
                                   },
                                   额外参数:{任务ID:任务ID}};

                    this.生命周期函数列表.push(卸载对象);
                }

            }
        }
    }
};



_root.装备生命周期函数 = {};

_root.装备生命周期函数.移除周期函数 = function(反射对象)
{
    _root.帧计时器.添加单次任务(function()
    {
        _root.帧计时器.移除任务(反射对象.生命周期任务ID);
        delete 反射对象.自机.任务标识[反射对象.标签名];
    }, 0);//延迟一帧执行
    //_root.服务器.发布服务器消息(arguments.caller + " 卸载 " + 反射对象.生命周期任务ID + " " + 反射对象.标签名 + " " + 反射对象.自机.任务标识[反射对象.标签名]);
};

_root.装备生命周期函数.移除周期函数.toString = function(){return "_root.装备生命周期函数.移除周期函数";}

_root.装备生命周期函数.移除非主角周期函数 = function(反射对象)
{
    if(反射对象.是否为主角) return false;//主角不移除
    _root.装备生命周期函数.移除周期函数(反射对象);
    return true;//移除成功
};

_root.装备生命周期函数.移除非主角周期函数.toString = function(){return "_root.装备生命周期函数.移除非主角周期函数";}

_root.装备生命周期函数.移除异常周期函数 = function(反射对象)
{
    /*
    if((反射对象.是否为主角 ? _root[反射对象.装备类型] : 反射对象.自机[反射对象.装备类型]) !== 反射对象.装备名称)
    {
        _root.装备生命周期函数.移除周期函数(反射对象);
    }
    */

    //_root.发布消息(反射对象.是否为主角, 反射对象.版本号, 反射对象.自机.version);
    
    if(反射对象.是否为主角) {
        if(反射对象.版本号 !== 反射对象.自机.version) {
            // _root.发布消息("版本号不一致，卸载 " + 反射对象.生命周期任务ID + " " + 反射对象.标签名 + " " + 反射对象.自机.任务标识[反射对象.标签名]);
            // _root.发布消息("原版本号: " + 反射对象.版本号 + " 现版本号: " + 反射对象.自机.version);
            _root.装备生命周期函数.移除周期函数(反射对象);
        }
    }
    else
    {
        if(反射对象.自机[反射对象.装备类型].name !== 反射对象.装备名称) {
            _root.装备生命周期函数.移除周期函数(反射对象);
        }
    }
}; //判断是否存在异常的周期函数，如未在重初始化时移除

_root.装备生命周期函数.移除异常周期函数.toString = function(){return "_root.装备生命周期函数.移除异常周期函数";}

_root.装备生命周期函数.解析刀口 = function(反射对象, 参数对象)
{   
    if(参数对象.position)
    {
        if(isNaN(Number(参数对象.position)))
        {
            switch(参数对象.position)
            {
                case "自机":
                default:
                    反射对象.获得刀口 = function(反射对象)
                    {
                        return 反射对象.自机.man;
                    }
            }
        }
        else
        {
            反射对象.刀口位置 = "刀口位置" + 参数对象.position;
            反射对象.获得刀口 = function(反射对象)
            {
                return 反射对象.自机.刀_引用[反射对象.刀口位置];
            }
        }
    }
    else
    {
        反射对象.获得刀口 = function(反射对象)
        {
            return 反射对象.自机.man;
        }
    }
}//用于处理刀口位置参数，position为数字时使用刀口，非数字时使用自机，后续可扩展其他参数

_root.装备生命周期函数.解析刀口.toString = function(){return "_root.装备生命周期函数.解析刀口";}

_root.装备生命周期函数.获得身高修正比 = function(反射对象)
{
    var 身高修正比 = 反射对象.自机.身高 / 175;
    反射对象.身高修正比 = 身高修正比;
    return 身高修正比;
}

_root.装备生命周期函数.获得身高修正比.toString = function(){return "_root.装备生命周期函数.获得身高修正比";}

_root.装备生命周期函数.全局参数 = {}; //用于跨图传参

_root.主角函数.完成生命周期函数装载 = function()
{

}; //用于套装检测

_root.主角函数.完成生命周期函数装载.toString = function(){return "_root.主角函数.完成生命周期函数装载";}

