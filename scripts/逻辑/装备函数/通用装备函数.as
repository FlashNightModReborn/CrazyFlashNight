import org.flashNight.arki.render.*;

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

//【1】通用变形初始化：注入统一配置并设置默认值
_root.装备生命周期函数.通用变形初始化 = function(reflector:Object, paramObj:Object) {
    var p = paramObj || {};

    // 默认动画属性
    reflector.animationDuration = (p.animationDuration != undefined ? p.animationDuration : 15);
    reflector.currentFrame      = (p.currentFrame != undefined ? p.currentFrame : 1);
    reflector.animationTarget   = (p.animationTarget != undefined ? p.animationTarget : "动画");

    // 将统一配置注入到 reflector.config，
    // 如果 XML 中有 <config> 节，转换后放入 paramObj.config 中
    if (p.config) {
        reflector.config = p.config;
    } else {
        reflector.config = {};
    }
    // 若未在 config 中定义 instanceContainer，则取默认值或从 p 中取
    if (!reflector.config.instanceContainer) {
        reflector.config.instanceContainer = (p.instanceContainer ? p.instanceContainer : "长枪_引用");
    }

    // 同步初始帧
    var target:MovieClip = reflector.自机[reflector.config.instanceContainer][reflector.animationTarget];
    target.gotoAndStop(reflector.currentFrame);

    //【2】状态判断函数设置
    var af = p.actionFunc ? p.actionFunc : "自机状态检测";
    reflector.actionFunc      = _root.装备生命周期函数[af];
    reflector.actionFuncParam = p.actionFuncParam ? p.actionFuncParam : {
        matchConditions: { 攻击模式: "长枪" },
        funcType: "ALL_MATCH"
    };

    //【3】状态更新函数设置
    var uf = p.updateFunc ? p.updateFunc : "自机状态检测";
    reflector.updateFunc      = _root.装备生命周期函数[uf];
    reflector.updateFuncParam = p.updateFuncParam ? p.updateFuncParam : {
        matchConditions: { 攻击模式: "长枪" },
        funcType: "FIRST_MATCH",
        triggerKey: "武器变形键",
        triggerFunc: "反转自机属性",
        triggerFuncParam: { toggleProperty: "通用变形中" }
    };

    //【4】如果配置了提前执行更新动作，则执行之
    if (p.updateloadExecution) {
        for (var i:Number = Number(p.updateloadExecution); i > 0; i--) {
            _root.装备生命周期函数[p.updateFuncParam.triggerFunc](reflector, p.updateFuncParam.triggerFuncParam);
        }
    }
};

// 全局参数存储
_root.装备生命周期函数.globalParams = {};

//【5】通用变形周期：处理动画帧变化
_root.装备生命周期函数.通用变形周期 = function(reflector:Object, paramObj:Object) {
    // 移除异常检测
    _root.装备生命周期函数.移除异常周期函数(reflector);

    // 触发状态更新（内部可能进行按键检测等）
    reflector.updateFunc(reflector, reflector.updateFuncParam);

    // 根据状态判断函数，决定动画帧是递增还是递减
    if (reflector.actionFunc(reflector, reflector.actionFuncParam)) {
        if (reflector.currentFrame < reflector.animationDuration) {
            reflector.currentFrame++;
        }
    } else {
        if (reflector.currentFrame > 1) {
            reflector.currentFrame--;
        }
    }
    // 同步动画帧到目标影片剪辑
    var target:MovieClip = reflector.自机[reflector.config.instanceContainer][reflector.animationTarget];
    target.gotoAndStop(reflector.currentFrame);
};


//【6】自机状态检测：根据条件判断状态
_root.装备生命周期函数.自机状态检测 = function(reflector:Object, funcParam:Object) {
    var matchConditions:Object = funcParam.matchConditions;
    switch(funcParam.funcType) {
        case "ANY_MATCH": // 任一条件满足返回 true
            for (var k in matchConditions) {
                if (reflector.自机[k] === matchConditions[k]) {
                    return true;
                }
            }
            return false;
        case "ALL_MATCH": // 全部满足返回 true
            for (var k in matchConditions) {
                if (reflector.自机[k] !== matchConditions[k]) {
                    return false;
                }
            }
            return true;
        case "FIRST_MATCH": // 默认，检查第一个条件
        default:
            for (var k in matchConditions) {
                return (reflector.自机[k] === matchConditions[k]);
            }
            return false;
    }
};

//【7】自机状态更新：检测状态后根据按键触发后续动作
_root.装备生命周期函数.自机状态更新 = function(reflector:Object, funcParam:Object) {
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


//【8】反转自机属性：切换某个属性，区分主角与非主角，主角属性使用全局空间以持久化
_root.装备生命周期函数.反转自机属性 = function(reflector:Object, funcParam:Object) {
    if (reflector.是否为主角) {
        _root.装备生命周期函数.globalParams[funcParam.toggleProperty] = !_root.装备生命周期函数.globalParams[funcParam.toggleProperty];
        reflector.自机[funcParam.toggleProperty] = _root.装备生命周期函数.globalParams[funcParam.toggleProperty];
    } else {
        reflector.自机[funcParam.toggleProperty] = !reflector.自机[funcParam.toggleProperty];
    }
};

//【9】通用变形触发函数：调用反转属性，并根据状态切换实例
_root.装备生命周期函数.通用变形触发函数 = function(reflector:Object, paramObj:Object) {
    _root.装备生命周期函数.反转自机属性(reflector, paramObj);
    
    var target:MovieClip = reflector.自机;
    var weapon:MovieClip = target[reflector.config.instanceContainer];
    // 根据属性决定使用哪个实例
    var instance:String = target[paramObj.toggleProperty] ? paramObj.trueInstance : paramObj.falseInstance;
    reflector[paramObj.toggleInstanceLabel] = instance;
};


//【10】模板组件切换：根据条件控制部件的显示或隐藏
_root.装备生命周期函数.模板组件切换 = function(reflector:Object, paramObj:Object) {
    var target:MovieClip = reflector.自机;
    var container:MovieClip = target[reflector.config.instanceContainer];
    var matchFuncName:String = paramObj.matchFunc || "自机状态检测";
    var matchFunc:Function = _root.装备生命周期函数[matchFuncName];
    var condition:Object = { matchConditions: paramObj.matchConditions, funcType: paramObj.funcType };
    var isVisible:Boolean = matchFunc(reflector, condition);
    var containerName:String = paramObj.containerName || "动画";
    var componentName:String = paramObj.componentName || "激光";

    container[containerName][componentName]._visible = isVisible;
};


_root.装备生命周期函数.通用刀光初始化 = function(reflector, paramObj) 
{
   reflector.basicStyle = paramObj.basicStyle ? paramObj.basicStyle : "白色蓝框";
};

_root.装备生命周期函数.通用刀光周期 = function(reflector, paramObj) 
{
   _root.装备生命周期函数.移除异常周期函数(reflector);
   var 自机 = reflector.自机;

   if(_root.兵器使用检测(自机))
   {
      BladeMotionTrailsRenderer.processBladeTrail(自机, 自机.刀_引用, reflector.basicStyle)
   }
};


_root.装备生命周期函数.通用拖影初始化 = function(reflector, paramObj) 
{
    reflector.basicStyle = paramObj.basicStyle ? paramObj.basicStyle : "白色蓝框";
    reflector.target = paramObj.target ? paramObj.target : "刀口位置1";
    reflector.actionFuncParam = paramObj.actionFuncParam ? paramObj.actionFuncParam : {
        matchConditions: { 攻击模式: "兵器" },
        funcType: "ALL_MATCH"
    };
};

_root.装备生命周期函数.通用拖影周期 = function(reflector, paramObj) 
{
    _root.装备生命周期函数.移除异常周期函数(reflector);

    if (_root.装备生命周期函数.自机状态检测(reflector, reflector.actionFuncParam))
    {
        var self:MovieClip = reflector.自机;
        var target:MovieClip = self[reflector.装备类型 + "_引用"][reflector.target];
        if (!(target && target._x != undefined)) return;

        var map:MovieClip = _root.gameworld.deadbody;

        // 直接获取 target 在 map 坐标系下的矩形
        var rect:Object = target.getRect(map);

        var edge1:Object = { x: rect.xMin, y: rect.yMax };
        var edge2:Object = { x: rect.xMax, y: rect.yMin };

        var trail:Array = [{ edge1: edge1, edge2: edge2 }];

        TrailRenderer.getInstance().addTrailData(self._name + self.version + reflector.标签名, trail, reflector.basicStyle);
    }
};


_root.装备生命周期函数.通用特效刀口初始化 = function (reflector:Object, paramObj:Object) {
    reflector.position = (paramObj.position != undefined) ? paramObj.position : "刀口位置2";
    var funcString:String = (paramObj.func != undefined) ? paramObj.func : "_root.刀口触发特效.黑铁的剑特效";
    reflector.func = eval(funcString);                        

    if(paramObj.states) {
        reflector.states = paramObj.states;
    } else {
        reflector.states = {};
        reflector.states["兵器攻击"] = true;
    }
};

_root.装备生命周期函数.通用特效刀口周期 = function (reflector:Object) {
    _root.装备生命周期函数.移除异常周期函数(reflector);

    var target:MovieClip = reflector.自机;
    var self:MovieClip   = target.刀_引用[reflector.position];
    self.自机 = target;
    var isActive:Boolean = Boolean(reflector.states[target.状态]);

    if (isActive) {
        if (!self.特效刀口触发) self.特效刀口触发 = reflector.func;
        if (!target.特效刀口)   target.特效刀口   = self;
    } else {
        target.特效刀口 = null;
    }
};
