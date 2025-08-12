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
    var shotgunSpeedBonus = (param.shotgunSpeedBonus != undefined) ? param.shotgunSpeedBonus : 0.05; // 霰弹值转速加成系数

    /* 根据 shotsPerCycle 自动推算转速系数：
       spinSpeedFactor = baseFactor × ( M134_shotsPerCycle / XM214_shotsPerCycle )            */
    ref.spinSpeedFactor = (param.spinSpeedFactor != undefined)
                          ? param.spinSpeedFactor
                          : baseFactor * (6 / ref.shotsPerCycle);
    ref.shotgunSpeedBonus = shotgunSpeedBonus;

    /* ========== ② 状态变量 ========== */
    ref.gunFrame  = 1;     // 动画帧 (float)
    ref.fireCount = 0;     // 连射计数
    ref.isFiring  = false; // 本帧是否开火
    
    /* ========== ③ 霰弹值系统 ========== */
    ref.shotgunValue = 5;      // 当前霰弹值
    ref.lastFireFrame = 0;     // 最后一次射击的帧数
    ref.currentFrame = 0;      // 当前帧计数器
    ref.shotCounter = 0;       // 射击计数器，每2次射击增长1次霰弹值

    /* ========== ④ 事件订阅 ========== */
    var evtType:String   = ref.装备类型 + "射击";
    target.dispatcher.subscribe(evtType, function () {
        ref.isFiring = true;
        ref.lastFireFrame = ref.currentFrame;
        
        // 每2次射击霰弹值+1，上限12
        ref.shotCounter++;
        if (ref.shotCounter >= 2) {
            ref.shotgunValue = Math.min(ref.shotgunValue + 1, 12);
            ref.shotCounter = 0; // 重置计数器
        }
        
        var prop:Object = target.man.子弹属性;
        var bulletCount:Number = target["长枪射击次数"][target["长枪"]];
        prop.霰弹值 = Math.min(ref.shotgunValue, 360 - bulletCount);
        


        _root.服务器.发布服务器消息("fire:" + prop.霰弹值)
    });

    target.dispatcher.subscribe("updateBullet", function () {
        if (target.攻击模式 != "长枪")
            return;
        var prop:Object = target.man.子弹属性;
        var bulletCount:Number = target["长枪射击次数"][target["长枪"]];
        var bulletDisplay:Number = target["长枪射击次数"][target["长枪"]] = Math.min(360, bulletCount + prop.霰弹值 - 1);
        _root.玩家信息界面.玩家必要信息界面["子弹数"] = 360 - bulletDisplay;

        _root.服务器.发布服务器消息("bulletCount:" + bulletDisplay)
    });

    ref.gunString = ref.装备类型 + "_引用";   // target[gunString]

    target.长枪属性数组[14][5] = 150;
};

/* ---------------------------------------------------------
 * XM214_CageFrame  周期函数
 * --------------------------------------------------------- */
_root.装备生命周期函数.XM214周期 = function (ref:Object, param:Object)
{
    var target:MovieClip = ref.自机;
    var gun:MovieClip    = target[ref.gunString];
    if (!gun) return;

    /* -------- 1. 帧计数器更新 -------- */
    ref.currentFrame++;

    /* -------- 2. 霰弹值衰减逻辑 -------- */
    if (ref.currentFrame - ref.lastFireFrame > 10) {
        var secondsPassed = Math.floor((ref.currentFrame - ref.lastFireFrame) / 10);
        ref.shotgunValue = Math.max(ref.shotgunValue - secondsPassed, 5);
        ref.lastFireFrame = ref.currentFrame - 10; // 重置时间基准
    }

    _root.服务器.发布服务器消息("更新霰弹值:" +ref.shotgunValue);

    /* -------- 3. 连射计数更新（短路写法） -------- */
    (ref.isFiring && (ref.fireCount = Math.min(ref.fireCount + ref.spinUpAmount,
                                               ref.maxSpinCount))) ||
    (ref.fireCount = Math.max(0, ref.fireCount - ref.spinDownRate));

    /* -------- 4. 长枪引用跳帧操作（直接操作gun） -------- */
    if (ref.fireCount > 0)
    {
        var currentSpeed:Number = ref.fireCount * ref.spinSpeedFactor * (1 + ref.shotgunValue * ref.shotgunSpeedBonus);
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

    /* -------- 5. 本帧逻辑结束，重置射击标记 -------- */
    ref.isFiring = false;
};