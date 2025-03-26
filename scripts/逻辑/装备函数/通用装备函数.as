_root.装备生命周期函数.初期特效初始化 = function(反射对象, 参数对象) 
{
   反射对象.子弹属性 = 反射对象.子弹配置.bullet_0;//通过反射对象传参通讯
   反射对象.成功率 = 参数对象.probability ? 参数对象.probability : 3;
   反射对象.xOffset = 参数对象.xOffset ? 参数对象.xOffset : 0;
   反射对象.yOffset = 参数对象.yOffset ? 参数对象.yOffset :0;

   _root.装备生命周期函数.获得身高修正比(反射对象);
   _root.装备生命周期函数.解析刀口(反射对象, 参数对象);
};

_root.装备生命周期函数.初期特效周期 = function(反射对象, 参数对象) 
{
    _root.装备生命周期函数.移除异常周期函数(反射对象);
    
    var 自机 = 反射对象.自机;
    if (_root.兵器攻击检测(自机)) 
    {
        if (_root.成功率(反射对象.成功率)) 
        {
            var 刀口 = 反射对象.获得刀口(反射对象);
            var 坐标 = {x:刀口._x,y:刀口._y};
            刀口._parent.localToGlobal(坐标);
            _root.gameworld.globalToLocal(坐标);
            
            坐标.x += (自机.方向 === "左" ? -1 : 1) * 反射对象.xOffset * 反射对象.身高修正比;
            坐标.y += 反射对象.yOffset * 反射对象.身高修正比;

            反射对象.子弹属性.shootX = 坐标.x;
            反射对象.子弹属性.shootY = 坐标.y;
            反射对象.子弹属性.shootZ = 自机.Z轴坐标;

            _root.子弹区域shoot传递(反射对象.子弹属性);
        }
    }
    //_root.服务器.发布服务器消息("初期特效周期");
};

_root.装备生命周期函数.耗蓝特效初始化 = function(反射对象, 参数对象)
{
    var 自机 = 反射对象.自机;

    反射对象.成功率 = 参数对象.probability ? 参数对象.probability : 5;
    反射对象.特效间隔 = 参数对象.interval ? 参数对象.interval : 500;
    反射对象.攻击时转向 = 参数对象.turn ? 参数对象.turn : true;
    反射对象.刀口位置 = "刀口位置" + (参数对象.position ? 参数对象.position : "3");
    反射对象.是否缓存威力 = 参数对象.cache ? 参数对象.cache : true;

    反射对象.子弹属性 = 反射对象.子弹配置.bullet_0;

    var 耗蓝量 = 参数对象.mp ? 参数对象.mp : 25;
    var 耗蓝百分比 = Number(耗蓝量.split("%")[0]);
    
    反射对象.伤害转化系数 = 参数对象.conversion ? 参数对象.conversion : 1;

    if(参数对象.cache)
    {
        反射对象.耗蓝量 = (耗蓝量.indexOf("%") === 耗蓝量.length - 1 && 耗蓝百分比 > 0) ? (自机.mp满血值 / 100 * 耗蓝百分比) : 耗蓝量;
        反射对象.子弹属性.子弹威力 = 反射对象.耗蓝量 * 反射对象.伤害转化系数;

        反射对象.设置子弹属性 = function(反射对象)
        {
            var 自机 = 反射对象.自机;
            var 刀口 = 自机.刀_引用[反射对象.刀口位置];
            var 坐标 = {x:刀口._x,y:刀口._y};
            var 子弹属性 = 反射对象.子弹属性;

            刀口._parent.localToGlobal(坐标);
            _root.gameworld.globalToLocal(坐标);
            子弹属性.shootX = 坐标.x;
            子弹属性.shootY = 坐标.y;
            子弹属性.shootZ = 自机.Z轴坐标;
        };
    }
    else
    {
        if(耗蓝量.indexOf("%") === 耗蓝量.length - 1 && 耗蓝百分比 > 0)
        {
            反射对象.耗蓝百分比 = 耗蓝百分比;
            反射对象.获得子弹威力 = function(反射对象)
            {
                反射对象.耗蓝量 = 反射对象.自机.mp满血值 / 100 * 反射对象.耗蓝百分比;
                
                return  反射对象.耗蓝量 * 反射对象.伤害转化系数;
            };
        }
        else
        {
            反射对象.耗蓝量 = 耗蓝量;
            
            反射对象.获得子弹威力 = function(反射对象)
            {
                return 反射对象.耗蓝量 * 反射对象.伤害转化系数;
            };
        }
        
        反射对象.设置子弹属性 = function(反射对象)
        {
            var 自机 = 反射对象.自机;
            var 刀口 = 自机.刀_引用[反射对象.刀口位置];
            var 坐标 = {x:刀口._x,y:刀口._y};
            var 子弹属性 = 反射对象.子弹属性;

            刀口._parent.localToGlobal(坐标);
            _root.gameworld.globalToLocal(坐标);
            子弹属性.shootX = 坐标.x;
            子弹属性.shootY = 坐标.y;
            子弹属性.shootZ = 自机.Z轴坐标;
            子弹属性.子弹威力 = 反射对象.获得子弹威力(反射对象);
        };
    }

    if(参数对象.state)
    {
        反射对象.释放特效 = function(反射对象)
        {

        };
    }
    else
    {
        反射对象.释放特效 = function(反射对象)
        {

        };
    }
};

_root.装备生命周期函数.耗蓝特效周期 = function(反射对象, 参数对象)
{
    _root.装备生命周期函数.移除异常周期函数(反射对象);

    var 自机 = 反射对象.自机;

    if(_root.兵器攻击检测(自机))
    { 
        _root.更新并执行时间间隔动作(反射对象, 反射对象.生命周期函数, 反射对象.释放特效, 反射对象.特效间隔, false, 反射对象);
    }
};

_root.装备生命周期函数.通用变形初始化 = function(reflector:Object, paramObj:Object)
{
    // 1) 处理传入参数，赋予默认值
    var p = paramObj || {};
    
    reflector.animationDuration  = p.animationDuration  ? p.animationDuration  : 15;
    reflector.currentFrame       = p.currentFrame       ? p.currentFrame       : 1;
    reflector.animationTarget    = p.animationTarget    ? p.animationTarget    : "动画";
    reflector.instanceContainer  = p.instanceContainer  ? p.instanceContainer  : "长枪_引用";
    
    // 2) 获取动画目标，并同步到初始帧
    var target = reflector.自机[reflector.instanceContainer][reflector.animationTarget];
    target.gotoAndStop(reflector.currentFrame);

    // 3) 状态判断函数 (actionFunc)
    var af = p.actionFunc ? p.actionFunc : "自机状态检测";
    reflector.actionFunc = _root.装备生命周期函数[af];
    
    // 状态判断函数的参数
    reflector.actionFuncParam = p.actionFuncParam ? p.actionFuncParam : {
        matchConditions: { 攻击模式: "长枪" },
        funcType: "ALL_MATCH"
    };

    // 4) 状态更新函数 (updateFunc)
    var uf = p.updateFunc ? p.updateFunc : "自机状态检测";
    reflector.updateFunc = _root.装备生命周期函数[uf];

    // 状态更新函数的参数
    reflector.updateFuncParam = p.updateFuncParam ? p.updateFuncParam : {
        matchConditions: { 攻击模式:"长枪" },
        funcType: "FIRST_MATCH",
        triggerKey: "武器变形键",
        triggerFunc: "反转自机属性",
        triggerFuncParam: "通用变形中"
    };
};


_root.装备生命周期函数.通用变形周期 = function(reflector:Object, paramObj:Object)
{
    // 1) 通用移除异常检测
    _root.装备生命周期函数.移除异常周期函数(reflector);

    // 2) 自机状态更新
    //    这一步内部会去做按键检测等触发逻辑
    _root.装备生命周期函数.自机状态更新(reflector, reflector.updateFuncParam);

    // 3) 如果满足状态判断函数 => 帧数递增, 否则递减
    if (reflector.actionFunc(reflector, reflector.actionFuncParam))
    {
        if (reflector.currentFrame < reflector.animationDuration)
        {
            reflector.currentFrame++;
        }
    }
    else
    {
        if (reflector.currentFrame > 1)
        {
            reflector.currentFrame--;
        }
    }

    // 4) 同步动画帧
    var target = reflector.自机[reflector.instanceContainer][reflector.animationTarget];
    target.gotoAndStop(reflector.currentFrame);
};


_root.装备生命周期函数.自机状态检测 = function(reflector:Object, funcParam:Object) 
{
    var matchConditions:Object = funcParam.matchConditions;
    switch(funcParam.funcType) 
    {
        case "ANY_MATCH": // 任意条件满足即返回true
            for (var k in matchConditions) {
                if (reflector.自机[k] === matchConditions[k]) {
                    return true;
                }
            }
            return false;
            
        case "ALL_MATCH": // 全部条件满足才返回true
            for (var k in matchConditions) {
                if (reflector.自机[k] !== matchConditions[k]) {
                    return false;
                }
            }
            return true;
            
        case "FIRST_MATCH": // 默认模式：按顺序检查，第一个遇到的属性决定结果
        default:
            for (var k in matchConditions) {
                return (reflector.自机[k] === matchConditions[k]);
            }
            return false;
    }
};

_root.装备生命周期函数.自机状态更新 = function(reflector:Object, funcParam:Object) 
{
    if (_root.装备生命周期函数.自机状态检测(reflector, funcParam)) {
        if (_root.按键输入检测(reflector.自机, _root[funcParam.triggerKey])) {
            _root.更新并执行时间间隔动作(
                reflector,
                reflector.标签,
                _root.装备生命周期函数[funcParam.triggerFunc],
                funcParam.triggerInterval,
                false,
                reflector,
                funcParam.triggerFuncParam 
            );
        }
    }
};


_root.装备生命周期函数.反转自机属性 = function(reflector:Object, funcParam:Object) 
{
    reflector.自机[funcParam] = !reflector.自机[funcParam];
};