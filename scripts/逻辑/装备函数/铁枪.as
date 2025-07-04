// =======================================================
//  铁枪 · 装备生命周期函数 (FSM重构版)
// =======================================================

import org.flashNight.neur.StateMachine.*;

/*--------------------------------------------------------
 * 1. 初始化
 *------------------------------------------------------*/
_root.装备生命周期函数.铁枪初始化 = function (ref, param) 
{
    var 自机 = ref.自机;
    
    // 1. 创建状态机
    ref.fsm = new FSM_StateMachine(null, null, null);

    // 2. 创建共享数据对象 (替代原先ref上的大部分属性)
    ref.fsm.data = {
        // —— 引用
        target: 自机,
        
        // —— 核心状态
        unmaykr化: false,
        isWeaponActive: false, // 武器是否激活
        currentFrame: 1,       // 当前动画帧

        // —— 关键帧常量
        bfg起始帧: param.bfgStart || 1,
        bfg结束帧: param.bfgEnd || 15,
        变形起始帧: param.transStart || 16,
        变形结束帧: param.transEnd || 25,
        unmaykr起始帧: param.unmStart || 26,
        unmaykr结束帧: param.unmEnd || 41,

        // —— 变形相关参数
        transformInterval: param.transformInterval || 1000,
        transformLabel: param.transformLabel || "铁枪变形检测",

        // —— 主角状态同步相关
        isPlayer: ref.是否为主角,
        labelObject: null
    };
    var data = ref.fsm.data; // 方便下方引用

    // —— 处理主角状态同步（参考炎魔斩的实现）
    if (data.isPlayer) 
    {
        var 标签 = ref.标签名 + ref.初始化函数;
        var 标签对象 = _root.装备生命周期函数.全局参数[标签];
        if (标签对象) 
        {
            data.unmaykr化 = 标签对象.unmaykr化;
        }
        else 
        {
            _root.装备生命周期函数.全局参数[标签] = {};
            标签对象 = _root.装备生命周期函数.全局参数[标签];
            data.unmaykr化 = false; // 默认BFG形态
        }
        标签对象.unmaykr化 = data.unmaykr化;
        data.labelObject = 标签对象;
    }

    // —— 根据当前形态设置初始帧
    data.currentFrame = data.unmaykr化 ? data.unmaykr起始帧 : data.bfg起始帧;
    
    // 3. 定义状态
    // ==================== 状态: DEPLOYED (展开/激活) ====================
    var deployedState = new FSM_Status(
        // onAction: 核心动画逻辑，对应原 "铁枪展开动画"
        function():Void {
            var data = this.data;
            switch (data.currentFrame) {
                case data.bfg结束帧:
                    if (data.unmaykr化) { --data.currentFrame; }
                    break;
                case data.unmaykr结束帧:
                    if (!data.unmaykr化) { --data.currentFrame; }
                    break;
                case data.bfg起始帧:
                    if (data.unmaykr化) { data.currentFrame = data.变形起始帧 + 1; } 
                    else { ++data.currentFrame; }
                    break;
                case data.unmaykr起始帧:
                    if (data.unmaykr化) { ++data.currentFrame; } 
                    else { data.currentFrame = data.变形结束帧 - 1; }
                    break;
                case data.变形起始帧:
                    if (data.unmaykr化) { ++data.currentFrame; } 
                    else { data.currentFrame = data.bfg起始帧 + 1; }
                    break;
                case data.变形结束帧:
                    if (data.unmaykr化) { data.currentFrame = data.unmaykr起始帧 + 1; } 
                    else { --data.currentFrame; }
                    break;
                default:
                    if (data.currentFrame < data.bfg结束帧) { data.currentFrame += data.unmaykr化 ? -1 : 1; }
                    else if (data.currentFrame < data.变形结束帧) { data.currentFrame += data.unmaykr化 ? 1 : -1; }
                    else { data.currentFrame += data.unmaykr化 ? 1 : -1; }
                    break;
            }
        },
        null, // onEnter
        null  // onExit
    );

    // ==================== 状态: HOLSTERED (收纳) ====================
    var holsteredState = new FSM_Status(
        // onAction: 收纳动画逻辑，对应原 "铁枪收纳动画"
        function():Void {
            var data = this.data;
            var targetStartFrame = data.unmaykr化 ? data.unmaykr起始帧 : data.bfg起始帧;

            if (data.currentFrame == targetStartFrame) {
                return; // 已到位，无需操作
            }

            switch (data.currentFrame) {
                case data.bfg起始帧:
                case data.unmaykr起始帧:
                case data.变形起始帧:
                case data.变形结束帧:
                    data.currentFrame = targetStartFrame;
                    break;
                default:
                    if (data.currentFrame <= data.bfg结束帧) { --data.currentFrame; }
                    else if (data.currentFrame <= data.变形结束帧) { data.currentFrame += data.unmaykr化 ? 1 : -1; }
                    else { --data.currentFrame; }
                    // 确保不会收纳过头
                    if ( (data.unmaykr化 && data.currentFrame > data.unmaykr起始帧) || 
                         (!data.unmaykr化 && data.currentFrame < data.bfg起始帧) ) {
                        data.currentFrame = targetStartFrame;
                    }
                    break;
            }
        },
        null, // onEnter
        null  // onExit
    );

    // 4. 将状态和转换规则添加到状态机
    ref.fsm.AddStatus("DEPLOYED", deployedState);
    ref.fsm.AddStatus("HOLSTERED", holsteredState);

    // 转换规则: 当武器激活时，从HOLSTERED切换到DEPLOYED
    ref.fsm.transitions.push("HOLSTERED", "DEPLOYED", function():Boolean {
        return this.data.isWeaponActive === true;
    });

    // 转换规则: 当武器未激活时，从DEPLOYED切换到HOLSTERED
    ref.fsm.transitions.push("DEPLOYED", "HOLSTERED", function():Boolean {
        return this.data.isWeaponActive === false;
    });

    // 5. 设置初始状态
    var initialState = (自机.攻击模式 === "长枪") ? "DEPLOYED" : "HOLSTERED";
    ref.fsm.setActiveState(ref.fsm.statusDict[initialState]); // 直接设置，避免触发onEnter/onExit
    ref.fsm.setLastState(null);
};

/*--------------------------------------------------------
 * 2. 周期函数
 *------------------------------------------------------*/
_root.装备生命周期函数.铁枪周期 = function (ref, param) 
{
    _root.装备生命周期函数.移除异常周期函数(ref);
    var fsm = ref.fsm;
    var data = fsm.data;
    var 自机 = data.target;
    var 长枪 = 自机.长枪_引用;

    // 1. 更新FSM的共享数据 (同步外部世界状态)
    data.isWeaponActive = (自机.攻击模式 === "长枪");

    // 仅在武器激活时检测变形按键
    if (data.isWeaponActive) {
        if (_root.按键输入检测(自机, _root.武器变形键)) {
            _root.更新并执行时间间隔动作(ref, data.transformLabel, function(fsmData) {
                fsmData.unmaykr化 = !fsmData.unmaykr化;
                // 同步到全局参数（仅主角）
                if (fsmData.isPlayer) {
                    fsmData.labelObject.unmaykr化 = fsmData.unmaykr化;
                }
            }, data.transformInterval, false, data);
        }
    }
    
    // 2. 执行状态机逻辑
    fsm.onAction();

    // 3. 应用状态机结果 (更新动画帧)
    长枪.动画.gotoAndStop(data.currentFrame);
};