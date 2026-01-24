//【11】wa90专用初始化：统一注入配置并调用通用初始化
_root.装备生命周期函数.wa90变形款初始化 = function(reflector:Object, paramObj:Object) {
    paramObj = paramObj || {};

    // 设置 wa90 默认值
    if (paramObj.animationDuration == undefined) {
        paramObj.animationDuration = 15;
    }
    if (paramObj.animationTarget == undefined) {
        paramObj.animationTarget = "动画";
    }
    // 统一配置：如果 XML 中定义了 <config>，转换后传入 paramObj.config
    if (!paramObj.config) {
        paramObj.config = {};
    }
    if (!paramObj.config.instanceContainer) {
        paramObj.config.instanceContainer = (paramObj.instanceContainer ? paramObj.instanceContainer : "长枪_引用");
    }
    if (!paramObj.config.toggleInstance) {
        if (paramObj.updateFuncParam && paramObj.updateFuncParam.triggerFuncParam) {
            paramObj.config.toggleInstance = paramObj.updateFuncParam.triggerFuncParam.toggleInstance;
        } else {
            paramObj.config.toggleInstance = "枪口位置";
        }
    }
    if (!paramObj.config.toggleInstanceLabel) {
        if (paramObj.updateFuncParam && paramObj.updateFuncParam.triggerFuncParam) {
            paramObj.config.toggleInstanceLabel = paramObj.updateFuncParam.triggerFuncParam.toggleInstanceLabel;
        } else {
            paramObj.config.toggleInstanceLabel = "wa90枪口位置";
        }
    }

    if (paramObj.actionFunc == undefined) {
        paramObj.actionFunc = "自机状态检测";
    }
    if (paramObj.actionFuncParam == undefined) {
        paramObj.actionFuncParam = {
            matchConditions: { 攻击模式:"长枪", wa90变形:true },
            funcType: "ALL_MATCH"
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
            triggerInterval: 1000,
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
    // 调用通用变形初始化（内部会将 paramObj.config 注入 reflector）
    _root.装备生命周期函数.通用变形初始化(reflector, paramObj);
};

//【12】wa90专用周期逻辑：在通用周期基础上同步实例切换
_root.装备生命周期函数.wa90变形款周期 = function(reflector:Object, paramObj:Object) {
    //_root.装备生命周期函数.移除异常周期函数(reflector);

    _root.装备生命周期函数.通用变形周期(reflector, paramObj);
    
    // 从注入的统一配置中获取参数
    var cfg = reflector.config;
    var target:MovieClip = reflector.自机;
    var wa90:MovieClip   = target[cfg.instanceContainer];
    
    // 利用统一配置切换实例：这里不再硬编码，而是从 config 中读取
    wa90[cfg.toggleInstance] = wa90[reflector[cfg.toggleInstanceLabel]];
    
    // 继续调用模板组件切换逻辑（用于控制部件显示/隐藏）
    _root.装备生命周期函数[paramObj.actionFunc](reflector, paramObj.actionFuncParam);

    var bulletFrame = target.长枪.value.shot + 1;
    reflector.自机.长枪_引用.动画.弹匣.gotoAndStop(bulletFrame);
};

//【13】wa90专用触发函数：直接调用通用触发函数
_root.装备生命周期函数.wa90变形款触发函数 = function(reflector:Object, paramObj:Object) {
    _root.装备生命周期函数.通用变形触发函数(reflector, paramObj);
};