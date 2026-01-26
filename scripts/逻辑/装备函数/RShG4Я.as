// =======================================================
// RShG4Я · 装备生命周期函数（参照 G1111 单向推进风格）
// 说明：
// - 状态机：idle(收纳待机) → draw(展开) → standby(长枪待机) → fire(开火) → reload(装填) → standby
// - 支持在任意播放中切出长枪：触发 undraw，按帧反向推进到 defaultStartFrame 并锁定 idle
// - 每次收到一次“updateBullet”即视为一次射击请求（ref.fireRequest=true），由周期函数消化成动画与弹药处理
// - 外露弹药：gun.弹头1 / gun.弹头2 会根据剩余容量显隐（remaining = capacity - shot）
// - 帧参数可由 param 覆写
// =======================================================

_root.装备生命周期函数.RShG4Я初始化 = function(ref, param)
{
    var target:MovieClip = ref.自机;
    /* ---------- 1) 帧参数 ---------- */
    ref.defaultStartFrame = (param != undefined && param.defaultStartFrame != undefined) ? param.defaultStartFrame : 1;   // 收纳状态保持帧
    ref.defaultEndFrame   = (param != undefined && param.defaultEndFrame   != undefined) ? param.defaultEndFrame   : 4;   // 收纳过渡结束帧
    ref.startFrame        = (param != undefined && param.startFrame        != undefined) ? param.startFrame        : 5;   // 展开起始
    ref.endFrame          = (param != undefined && param.endFrame          != undefined) ? param.endFrame          : 19;  // 展开结束（长枪待机停在此）
    ref.fireStartFrame    = (param != undefined && param.fireStartFrame    != undefined) ? param.fireStartFrame    : 20;  // 开火起始
    ref.fireEndFrame      = (param != undefined && param.fireEndFrame      != undefined) ? param.fireEndFrame      : 26;  // 开火结束
    ref.reloadStartFrame  = (param != undefined && param.reloadStartFrame  != undefined) ? param.reloadStartFrame  : 27;  // 装填起始
    ref.reloadEndFrame    = (param != undefined && param.reloadEndFrame    != undefined) ? param.reloadEndFrame    : 35;  // 装填结束

    /* ---------- 2) 弹药 ---------- */
    // 注意：弹药数据使用游戏系统的 target.长枪属性.capacity 和 target[ref.装备类型].value.shot
    // ref.capacity 仅作为默认值备用（如果游戏系统未初始化）
    ref.capacity          = (param != undefined && param.capacity          != undefined) ? param.capacity          : 2;   // 外露弹容量（默认2）
    ref.fireRequest       = false;        // 当帧射击请求
    ref.isWeaponActive    = false;        // 是否处于长枪模式

    /* ---------- 3) 播放控制 ---------- */
    ref.currentAction     = "idle";       // idle/draw/standby/fire/reload/undraw
    ref.currentFrame      = ref.defaultStartFrame;
    ref.emptyStandby      = false;        // 是否处于空仓待机状态

    /* ---------- 4) 事件订阅 ---------- */
    // 长枪引用加载时刷新可视
    target.syncRefs.长枪_引用 = true;
    target.dispatcher.subscribe("长枪_引用", function () {
        _root.装备生命周期函数.RShG4Я视觉(ref);
    });

    // 触发一次射击请求（由周期函数消化）
    target.dispatcher.subscribe("updateBullet", function () {
        if (target.攻击模式 !== "长枪") return;
        ref.fireRequest = true;
    });

    // 首次渲染
    _root.装备生命周期函数.RShG4Я视觉(ref);
};

/*--------------------------------------------------------
 * 周期函数：逐帧推进动画与状态
 *------------------------------------------------------*/
_root.装备生命周期函数.RShG4Я周期 = function (ref)
{
    /*

       切换到长枪模式时，立即展开
       射击结束后阻塞，利用isEmpty判定是否自动装填，这样玩家完成换弹后也可以正常播放换弹动画？
       切换到非长枪模式时，立即收起，从当前的帧数逆向播放到defaultStartFrame
       射击有最高优先级
       展开动画是单次播放，推进到endFrame后保持在那里，等待射击指令
       射击动画是单次播放，推进到fireEndFrame后，如果没有弹药则保持在那里，等待收起指令；如果有弹药则切换到装填状态
       装填动画是单次播放，推进到reloadEndFrame后跳转到endFrame，等待射击指令
       待机动画是单次播放，最终保持在defaultStartFrame，等待切换到长枪指令
       每次射击后，只要还有弹药就都装填
       gun.弹头1和gun.弹头2是外露的弹药，如果没有弹药的话那就应该不显示
       shot代表射击次数，capacity == shot意味着已经把弹容量打光了
       玩家连续按射击键，理论上这把武器的射速不支持连发，但如果发生，那就重置重新播放射击动画
       切换武器时，如果正在播放动画，那就触发待机状态，从当前帧反向推进，直到锁定在defaultStartFrame
       需要支持从param传入帧数配置
       动画播放速度不需要可调
     */
    // 统一异常守护（与 G1111风格对齐，如未定义可忽略）
    _root.装备生命周期函数.移除异常周期函数(ref);

    var 自机:MovieClip  = ref.自机;
    var 长枪:MovieClip  = 自机.长枪_引用;
    if (长枪 == undefined) return;

    // 使用与视觉函数相同的判断方式
    var isEmpty:Boolean = (自机.长枪属性.capacity == 自机[ref.装备类型].value.shot);

    // 0) 长枪激活状态判定
    var prevActive = ref.isWeaponActive;
    ref.isWeaponActive = (自机.攻击模式 === "长枪");

    // 若切出长枪：进入 undraw，反向播放到 defaultStartFrame 并锁定 idle
    if (!ref.isWeaponActive) {
        if (ref.currentAction != "idle") {
            ref.currentAction = "undraw";
        }
        // 反向推进
        if (ref.currentFrame > ref.defaultStartFrame) {
            ref.currentFrame -= 1;
            if (ref.currentFrame <= ref.defaultStartFrame) {
                ref.currentFrame  = ref.defaultStartFrame;
                ref.currentAction = "idle";
            }
        } else {
            ref.currentAction = "idle";
            ref.currentFrame  = ref.defaultStartFrame;
        }
        // 绘制与外露弹显隐
        _root.装备生命周期函数.RShG4Я视觉(ref);
        return;
    }

    // 1) 长枪激活：若之前不活跃或仍处于收纳，则进入 draw
    if (prevActive != ref.isWeaponActive && ref.isWeaponActive) {
        ref.currentAction = "draw";
        if (ref.currentFrame < ref.startFrame) ref.currentFrame = ref.startFrame;
    }

    // 2) 状态机推进
    var nextAction:String = ref.currentAction;
    // _root.发布消息("状态机开始", "currentAction=" + ref.currentAction, "currentFrame=" + ref.currentFrame);

    if (ref.currentAction == "idle") {
        // 从 idle 进入 draw
        nextAction = "draw";
        if (ref.currentFrame < ref.startFrame) ref.currentFrame = ref.startFrame;
    }
    else if (ref.currentAction == "draw") {
        if (ref.currentFrame < ref.endFrame) {
            ref.currentFrame += 1;
        } else {
            nextAction = "standby";
            ref.currentFrame = ref.endFrame;  // draw完成后停在待机位置（19帧）
        }
    }
    else if (ref.currentAction == "standby") {
        // 记录状态用于调试
        // _root.发布消息("standby状态", "currentFrame=" + ref.currentFrame, "isEmpty=" + isEmpty, "emptyStandby=" + ref.emptyStandby);

        // 有射击请求时，无条件进入 fire 动画（让动画播放，即使是空仓）
        if (ref.fireRequest) {
            nextAction = "fire";
            ref.currentFrame = ref.fireStartFrame;
            ref.emptyStandby = false;  // 清除空仓标记
            // 消费本帧请求
            ref.fireRequest = false;
        } else {
            // 非射击情况下的处理
            if (ref.emptyStandby) {
                // 空仓待机状态
                if (!isEmpty) {
                    // 弹药已补充，触发装填动画
                    nextAction = "reload";
                    ref.currentFrame = ref.reloadStartFrame;
                    ref.emptyStandby = false;
                } else {
                    // 仍然空仓，保持在射击结束位置
                    ref.currentFrame = ref.fireEndFrame;
                }
            } else {
                // 正常待机状态，保持在待机位置
                ref.currentFrame = ref.endFrame;
            }
        }
    }
    else if (ref.currentAction == "fire") {
        // 若玩家在开火动画期间又按了一次（虽然不支持连发），则重置动画
        if (ref.fireRequest) {
            // 需要重新检查当前的弹药状态
            var currentIsEmpty:Boolean = (自机.长枪属性.capacity == 自机[ref.装备类型].value.shot);
            if (!currentIsEmpty) {
                ref.currentFrame = ref.fireStartFrame;
                // 射击计数由游戏系统管理
            }
            ref.fireRequest = false;
        }

        if (ref.currentFrame < ref.fireEndFrame) {
            ref.currentFrame += 1;
        } else {
            // 开火结束 → 重新检查弹药状态，决定是装填还是待机
            var afterFireIsEmpty:Boolean = (自机.长枪属性.capacity == 自机[ref.装备类型].value.shot);
            if (!afterFireIsEmpty) {  // 还有弹药，进入装填
                nextAction = "reload";
                ref.currentFrame = ref.reloadStartFrame;
                ref.emptyStandby = false;
            } else {  // 弹药打光，停在射击结束帧待机
                nextAction = "standby";
                ref.currentFrame = ref.fireEndFrame;  // 保持在射击结束位置
                ref.emptyStandby = true;  // 标记为空仓待机
            }
        }
    }
    else if (ref.currentAction == "reload") {
        if (ref.currentFrame < ref.reloadEndFrame) {
            ref.currentFrame += 1;
        } else {
            // 装填完成 → 回到 standby
            // 注意：弹药重置由游戏系统负责，动画系统不需要管理
            nextAction = "standby";
            ref.currentFrame = ref.endFrame;
            ref.emptyStandby = false;  // 装填完成，清除空仓标记
        }
    }
    else if (ref.currentAction == "undraw") {
        // 理论上在 isWeaponActive=true 时不会出现；保险处理
        if (ref.currentFrame > ref.defaultStartFrame) {
            ref.currentFrame -= 1;
        } else {
            nextAction = "idle";
            ref.currentFrame = ref.defaultStartFrame;
        }
    }

    ref.currentAction = nextAction;
    _root.装备生命周期函数.RShG4Я视觉(ref);
};

/*--------------------------------------------------------
 * 视觉渲染：帧切换与外露弹显隐
 *------------------------------------------------------*/
_root.装备生命周期函数.RShG4Я视觉 = function (ref)
{
    var target:MovieClip = ref.自机;
    var gun:MovieClip   = target.长枪_引用;
    // 帧跳转
    gun.gotoAndStop(ref.currentFrame);
    // _root.服务器.发布服务器消息("RShG4Я视觉", target.长枪属性.capacity, target[ref.装备类型].value.shot, ref.currentAction, ref.currentFrame);
    // 外露弹药显隐
    var isEmpty:Boolean = (target.长枪属性.capacity == target[ref.装备类型].value.shot);

    gun.弹头1._visible = gun.弹头2._visible = !isEmpty;

};
