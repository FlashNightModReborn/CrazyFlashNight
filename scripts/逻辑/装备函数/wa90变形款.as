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
            triggerFunc: "反转自机属性",
            triggerFuncParam: "wa90变形"
        };
    }

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
};
