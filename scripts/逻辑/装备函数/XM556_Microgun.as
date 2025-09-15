/* ---------------------------------------------------------
 * XM556_Microgun  初始化
 * --------------------------------------------------------- */
_root.装备生命周期函数.XM556初始化 = function (ref:Object, param:Object)
{
    var target:MovieClip = ref.自机;

    /* ========== ① 性能参数 ========== */
    ref.maxSpinCount   = param.maxSpinCount   || 24;   // Microgun 缩小后惯量更低 → 峰值连射计数略降
    ref.spinUpAmount   = param.spinUpAmount   || 5;    // 每次开火累积连射计数
    ref.spinDownRate   = param.spinDownRate   || 0.4;  // 自然衰减稍快，便于快速停转

    /* --- 关键差异：每圈射弹数 --- */
    ref.shotsPerCycle  = param.shotsPerCycle  || 2;    // ★ 2 发/圈（M134 为 6）
    var baseFactor     = (param.baseSpinSpeedFactor != undefined) ? param.baseSpinSpeedFactor : 0.1;

    /* 根据 shotsPerCycle 自动推算转速系数：
       spinSpeedFactor = baseFactor × ( M134_shotsPerCycle / XM556_shotsPerCycle )            */
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


    ref.gunString = ref.装备类型 + "_引用";   // target[gunString].动画
};

/* ---------------------------------------------------------
 * XM556_Microgun  周期函数
 * --------------------------------------------------------- */
_root.装备生命周期函数.XM556周期 = function (ref:Object, param:Object)
{
    var target:MovieClip = ref.自机;
    var gun:MovieClip    = target[ref.gunString];
    if (!gun || !gun.动画) return;

    var gunAnim:MovieClip = gun.动画;

    /* -------- 1. 连射计数更新（短路写法） -------- */
    (ref.isFiring && (ref.fireCount = Math.min(ref.fireCount + ref.spinUpAmount,
                                               ref.maxSpinCount))) ||
    (ref.fireCount = Math.max(0, ref.fireCount - ref.spinDownRate));

    /* -------- 2. 枪管旋转动画 -------- */
    if (ref.fireCount > 0)
    {
        var currentSpeed:Number = ref.fireCount * ref.spinSpeedFactor; // ← 与 shotsPerCycle 相关
        ref.gunFrame += currentSpeed;

        // 高效取模，循环播放
        if (ref.gunFrame > gunAnim._totalFrames)
            ref.gunFrame = ((ref.gunFrame - 1) % gunAnim._totalFrames) + 1;

        gunAnim.gotoAndStop(Math.floor(ref.gunFrame));
    }
    else if (gunAnim._currentFrame != 1)
    {
        gunAnim.gotoAndStop(1);
    }

    /* -------- 3. 本帧逻辑结束，重置射击标记 -------- */
    ref.isFiring = false;
};
