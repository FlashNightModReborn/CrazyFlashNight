_root.装备生命周期函数.MACSIII初始化 = function(ref:Object, param:Object) {
    var target:MovieClip = ref.自机;
    
    // --- 状态变量 ---
    ref.gunFrame = 1.0;              // 当前循环动画帧 (普通/过载共用)
    ref.isFiring = false;            // 是否正在射击
    ref.animBudget = 0.0;            // 动画预算，用于平滑启停
    
    // --- 新增：状态机变量 ---
    ref.state = "NORMAL";            // 初始状态为 "普通"
    ref.transitionCounter = 0;       // 过渡动画播放计数器

    // ... 您原有的等级判断和事件绑定代码保持不变 ...
    var upgradeLevel:Number = 自机.长枪.value.level;
    var executeLevel:Number = param.executeLevel || 3;
    var lifeStealLevel:Number = param.lifeStealLevel || 6;
    
    var execBonus:Number = (upgradeLevel >= executeLevel) ? 10 : 0;
    var lifeBonus:Number = (upgradeLevel >= lifeStealLevel) ? 18 : 0;
    
    var combo:Number = (execBonus ? 1 : 0) | (lifeBonus ? 2 : 0);
    
    function mkHandler0(ref:Object):Function { return function () { ref.isFiring = true; ref.自机.man.子弹属性.区域定位area = ref.自机.长枪_引用.枪口位置; }; }
    function mkHandlerE(ref:Object):Function { return function () { ref.isFiring = true; var mc = ref.自机; var prop = mc.man.子弹属性; prop.区域定位area = mc.长枪_引用.枪口位置; if(mc.MACSIII超载打击许可) { prop.斩杀 = 8; } }; }
    function mkHandlerL(ref:Object):Function { return function () { ref.isFiring = true; var mc = ref.自机; var prop = mc.man.子弹属性; prop.区域定位area = mc.长枪_引用.枪口位置; if(mc.MACSIII超载打击许可) { prop.吸血 = 10; } }; }
    function mkHandlerEL(ref:Object):Function { return function () { ref.isFiring = true; var mc = ref.自机; var prop = mc.man.子弹属性; prop.区域定位area = mc.长枪_引用.枪口位置; if(mc.MACSIII超载打击许可) { prop.斩杀 = 10; prop.吸血 = 18; } }; }
    
    var handlerTable:Array = [mkHandler0, mkHandlerE, mkHandlerL, mkHandlerEL];
    target.dispatcher.subscribe("长枪射击", handlerTable[combo](ref));
};

_root.装备生命周期函数.MACSIII周期 = function(ref:Object, param:Object) {
    var target:MovieClip = ref.自机;
    var gun:MovieClip = target.长枪_引用;

    // --- 动画帧常量定义 ---
    var NORMAL_LOOP_FRAMES:Number = 4;
    var OVERLOAD_OFFSET:Number = 4;         // 过载动画的起始偏移 (帧5 = 1 + 4)
    var TO_OVERLOAD_START_FRAME:Number = 9;
    var TO_OVERLOAD_TOTAL_FRAMES:Number = 4;
    var TO_NORMAL_START_FRAME:Number = 13;
    var TO_NORMAL_TOTAL_FRAMES = 4;
    
    var animFrame:Number; // 最终要播放的动画帧

    // --- 动画预算和帧推进逻辑 (这部分保持不变，因为它控制旋转速度) ---
    if(ref.isFiring) ref.animBudget += 10.0;
    if(ref.animBudget > 60.0) ref.animBudget = 60.0;
    
    var frameAdvance:Number = 0.0;
    if(ref.animBudget >= 1.0) {
        frameAdvance = 1.0;
        ref.animBudget -= 1.0;
    } else if(ref.animBudget > 0.0) {
        frameAdvance = ref.animBudget;
        ref.animBudget = 0.0;
    }

    // --- 核心状态机 ---
    switch (ref.state) {
        case "NORMAL":
            // 检查是否要启动超载
            if (target.MACSIII超载打击许可 && target.MACSIII超载打击剩余时间 > 0) {
                ref.state = "TO_OVERLOAD";
                ref.transitionCounter = 0;
            } else {
                // 播放普通循环动画
                ref.gunFrame += frameAdvance;
                if (ref.gunFrame > NORMAL_LOOP_FRAMES) ref.gunFrame -= NORMAL_LOOP_FRAMES;
                animFrame = Math.floor(ref.gunFrame);
            }
            break;

        case "TO_OVERLOAD": // 播放“普通 -> 过载”过渡动画
            animFrame = TO_OVERLOAD_START_FRAME + ref.transitionCounter;
            ref.transitionCounter++;
            if (ref.transitionCounter >= TO_OVERLOAD_TOTAL_FRAMES) {
                ref.state = "OVERLOAD"; // 过渡完毕，进入过载状态
                ref.gunFrame = 1.0; // 重置循环帧，准备播放过载循环
            }
            break;

        case "OVERLOAD":
            // 检查超载时间是否结束
            if (--target.MACSIII超载打击剩余时间 < 0) {
                target.MACSIII超载打击许可 = false;
                ref.state = "TO_NORMAL"; // 时间到，进入“过载 -> 普通”过渡
                ref.transitionCounter = 0;
            } else {
                // 播放过载循环动画
                ref.gunFrame += frameAdvance;
                if (ref.gunFrame > NORMAL_LOOP_FRAMES) ref.gunFrame -= NORMAL_LOOP_FRAMES;
                animFrame = Math.floor(ref.gunFrame) + OVERLOAD_OFFSET;
            }
            break;

        case "TO_NORMAL": // 播放“过载 -> 普通”过渡动画
            animFrame = TO_NORMAL_START_FRAME + ref.transitionCounter;
            ref.transitionCounter++;
            if (ref.transitionCounter >= TO_NORMAL_TOTAL_FRAMES) {
                ref.state = "NORMAL"; // 过渡完毕，返回普通状态
                ref.gunFrame = 1.0; // 重置循环帧，准备播放普通循环
            }
            break;
    }

    // 安全检查并应用最终帧
    if (animFrame) {
        gun.gotoAndStop(Math.floor(animFrame));
    }
    
    // 重置射击状态
    ref.isFiring = false;
};