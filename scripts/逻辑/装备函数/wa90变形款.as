/**
 * wa90专用初始化
 */
_root.装备生命周期函数.wa90变形款初始化 = function(reflector:Object, paramObj:Object) 
{
    // 可以先对 paramObj 做一些wa90专属的默认参数处理
    paramObj = paramObj || {};

    // 针对wa90的默认值
    if (paramObj.animationDuration == undefined) {
        paramObj.animationDuration = 15;
    }
    if (paramObj.animationTarget == undefined) {
        paramObj.animationTarget = "动画";
    }
    if (paramObj.instanceContainer == undefined) {
        paramObj.instanceContainer = "长枪_引用";
    }
    if (paramObj.actionFunc == undefined) {
        paramObj.actionFunc = "自机状态检测";
    }
    if (paramObj.actionFuncParam == undefined) {
        paramObj.actionFuncParam = {
            matchConditions:{ 攻击模式:"长枪", wa90变形:true },
            funcType:"ALL_MATCH"
        };
    }
    if (paramObj.updateFunc == undefined) {
        paramObj.updateFunc = "自机状态检测";
    }
    if (paramObj.updateFuncParam == undefined) {
        paramObj.updateFuncParam = {
            matchConditions: { 攻击模式:"长枪" },
            funcType: "FIRST_MATCH",
            triggerKey: "武器变形键",
            triggerFunc: "wa90变形款触发函数",
            triggerFuncParam: {
                toggleProperty : "wa90变形",
                toggleInstance : "枪口位置",
                trueInstance : "枪口位置1",
                falseInstance : "枪口位置0",
                instanceContainer : "长枪_引用"
            }
        };
    }

    reflector.instanceContainer = paramObj.updateFuncParam.triggerFuncParam.instanceContainer;
    reflector.toggleInstance = paramObj.updateFuncParam.triggerFuncParam.toggleInstance;
    // 调用通用初始化
    _root.装备生命周期函数.通用变形初始化(reflector, paramObj);
};

/**
 * wa90专用周期逻辑
 */
_root.装备生命周期函数.wa90变形款周期 = function(reflector:Object, paramObj:Object) 
{
    // 直接调用通用周期
    _root.装备生命周期函数.通用变形周期(reflector, paramObj);
    var target:MovieClip = reflector.自机;
    var wa90:MovieClip = target[reflector.instanceContainer];
    wa90[reflector.toggleInstance] = wa90[reflector.instance]
    wa90.动画.激光._visible = target.攻击模式 == "长枪";
};


_root.装备生命周期函数.wa90变形款触发函数 = function(reflector:Object, paramObj:Object) 
{
    // 直接调用通用周期
    _root.装备生命周期函数.反转自机属性(reflector, paramObj);
    var target:MovieClip = reflector.自机;
    var wa90:MovieClip = target[paramObj.instanceContainer];
    var instance:MovieClip = target[paramObj.toggleProperty] ? paramObj.trueInstance : paramObj.falseInstance;
    reflector.instance = instance;
};
