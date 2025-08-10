import org.flashNight.neur.Event.*; 

/* ---------------------------------------------------------
 * XM214_CageFrame  初始化
 * --------------------------------------------------------- */
_root.装备生命周期函数.XM214初始化 = function (ref:Object, param:Object)
{
    var target:MovieClip = ref.自机;

    /* ========== ① 性能参数 ========== */
    ref.maxSpinCount   = param.maxSpinCount   || 24;   // CageFrame 连射计数峰值
    ref.spinUpAmount   = param.spinUpAmount   || 5;    // 每次开火累积连射计数
    ref.spinDownRate   = param.spinDownRate   || 0.4;  // 自然衰减速率

    /* --- 关键差异：每圈射弹数 --- */
    ref.shotsPerCycle  = param.shotsPerCycle  || 6;    // ★ 6 发/圈
    var baseFactor     = (param.baseSpinSpeedFactor != undefined) ? param.baseSpinSpeedFactor : 0.1;

    /* 根据 shotsPerCycle 自动推算转速系数：
       spinSpeedFactor = baseFactor × ( M134_shotsPerCycle / XM214_shotsPerCycle )            */
    ref.spinSpeedFactor = (param.spinSpeedFactor != undefined)
                          ? param.spinSpeedFactor
                          : baseFactor * (6 / ref.shotsPerCycle);

    /* ========== ② 状态变量 ========== */
    ref.gunFrame  = 1;     // 动画帧 (float)
    ref.fireCount = 0;     // 连射计数
    ref.isFiring  = false; // 本帧是否开火

    /* ========== ③ 事件订阅 ========== */
    var evtType:String   = ref.装备类型 + "射击";
    target.dispatcher.subscribe(evtType, function () {
        ref.isFiring = true;
    });

    ref.gunString = ref.装备类型 + "_引用";   // target[gunString]
};

/* ---------------------------------------------------------
 * XM214_CageFrame  周期函数
 * --------------------------------------------------------- */
_root.装备生命周期函数.XM214周期 = function (ref:Object, param:Object)
{
    var target:MovieClip = ref.自机;
    var gun:MovieClip    = target[ref.gunString];
    if (!gun) return;

    /* -------- 1. 连射计数更新（短路写法） -------- */
    (ref.isFiring && (ref.fireCount = Math.min(ref.fireCount + ref.spinUpAmount,
                                               ref.maxSpinCount))) ||
    (ref.fireCount = Math.max(0, ref.fireCount - ref.spinDownRate));

    /* -------- 2. 长枪引用跳帧操作（直接操作gun） -------- */
    if (ref.fireCount > 0)
    {
        var currentSpeed:Number = ref.fireCount * ref.spinSpeedFactor;
        ref.gunFrame += currentSpeed;

        // 高效取模，循环播放
        if (ref.gunFrame > gun._totalFrames)
            ref.gunFrame = ((ref.gunFrame - 1) % gun._totalFrames) + 1;

        gun.gotoAndStop(Math.floor(ref.gunFrame));
    }
    else if (gun._currentFrame != 1)
    {
        gun.gotoAndStop(1);
    }

    /* -------- 3. 本帧逻辑结束，重置射击标记 -------- */
    ref.isFiring = false;
};