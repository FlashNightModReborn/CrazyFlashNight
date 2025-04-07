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
                toggleInstanceLabel : "wa90枪口位置",
                trueInstance : "枪口位置1",
                falseInstance : "枪口位置0",
                instanceContainer : "长枪_引用"
            }
        };
    }
    
    reflector.instanceContainer = paramObj.updateFuncParam.triggerFuncParam.instanceContainer;
    reflector.toggleInstance = paramObj.updateFuncParam.triggerFuncParam.toggleInstance;
    reflector.toggleInstanceLabel = paramObj.updateFuncParam.triggerFuncParam.toggleInstanceLabel;

    // 调用通用初始化
    _root.装备生命周期函数.通用变形初始化(reflector, paramObj);
};

/**
 * wa90专用周期逻辑
 */
_root.装备生命周期函数.wa90变形款周期 = function(reflector:Object, paramObj:Object) 
{
    // 1) 调用通用变形周期（处理动画帧数等基础逻辑）
    _root.装备生命周期函数.通用变形周期(reflector, paramObj);
    
    // 2) 同步实例切换（依赖于模板化初始化时设置的属性）
    var target:MovieClip = reflector.自机;
    var wa90:MovieClip = target[reflector.instanceContainer];
    wa90[reflector.toggleInstance] = wa90[reflector[reflector.toggleInstanceLabel]];
    
    // 3) 利用模板组件切换函数，根据配置控制多个部件的显隐
    _root.装备生命周期函数[paramObj.actionFunc](reflector, paramObj.actionFuncParam);
};



_root.装备生命周期函数.wa90变形款触发函数 = function(reflector:Object, paramObj:Object) 
{
    _root.装备生命周期函数.通用变形触发函数(reflector, paramObj)
};

