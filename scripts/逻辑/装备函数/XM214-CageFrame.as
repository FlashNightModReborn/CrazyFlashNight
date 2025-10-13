/* ---------------------------------------------------------
 * XM214_CageFrame  初始化 (重构版)
 * --------------------------------------------------------- */
_root.装备生命周期函数.XM214初始化 = function(ref:Object, param:Object) {
    var target:MovieClip = ref.自机;

    /* ========== ① 性能参数 (基于新的数学模型) ========== */
    // 核心：当霰弹值达到峰值时，每游戏帧动画前进的最大帧数。这个值决定了视觉上的最高转速。
    ref.maxVisualSpinSpeed = param.maxVisualSpinSpeed || 8; // ★ 推荐值 5 ~ 10，可自行调整

    // 霰弹值参数
    ref.MIN_SHOTGUN_VAL = param.minShotgunVal || 5; // 霰弹值下限，此时转速为0
    ref.MAX_SHOTGUN_VAL = param.maxShotgunVal || 12; // 霰弹值上限，此时转速达到峰值
    ref.shotgunDecayDelay = param.shotgunDecayDelay || 10; // 多少帧不射击后开始衰减
    
    // 射击增量参数
    ref.shotgunIncrement = param.shotgunIncrement || 1; // 每次射击霰弹值增量

    // 弹药系统参数 - 从装备动态读取弹匣容量(支持扩容弹匣等插件)
    ref.maxBulletCapacity = target["长枪弹匣容量"] || param.maxBulletCapacity || 360; // 最大子弹容量
    
    // 武器属性配置
    ref.weaponAttributeValue = param.weaponAttributeValue || 150; // 武器属性值
    
    // 视觉效果参数
    ref.flickerCycle = param.flickerCycle || 3; // 抖动周期帧数

    /* ========== ② 状态变量 ========== */
    ref.gunFrame = 1; // 动画帧 (float)
    ref.shotgunValue = ref.MIN_SHOTGUN_VAL; // 当前霰弹值，初始为下限

    // 射击频率检测与衰减相关
    ref.lastFireFrame = 0; // 最后一次射击的游戏帧
    ref.currentFrame = 0; // 当前游戏帧计数器

    /* ========== ③ 事件订阅 (逻辑简化) ========== */
    var evtType:String = ref.装备类型 + "射击";
    target.dispatcher.subscribe(evtType, function() {
        // 标记射击帧，用于后续的衰减判断
        ref.lastFireFrame = ref.currentFrame;

        // 每次射击，霰弹值增加配置的增量，并确保不超过上限
        ref.shotgunValue = Math.min(ref.shotgunValue + ref.shotgunIncrement, ref.MAX_SHOTGUN_VAL);

        // 子弹属性设置 (原逻辑)
        var prop:Object = target.man.子弹属性;
        var bulletCount:Number = target.长枪.value.shot;
        prop.霰弹值 = Math.min(ref.shotgunValue, ref.maxBulletCapacity - bulletCount);

        // _root.服务器.发布服务器消息("fire:" + prop.霰弹值);
    });

    target.dispatcher.subscribe("updateBullet", function() {
        if (target.攻击模式 != "长枪")
            return;
        var prop:Object = target.man.子弹属性;
        var bulletCount:Number = target.长枪.value.shot;
        var bulletDisplay:Number = target.长枪.value.shot = Math.min(ref.maxBulletCapacity, bulletCount + prop.霰弹值 - 1);
        _root.玩家信息界面.玩家必要信息界面["子弹数"] = ref.maxBulletCapacity - bulletDisplay;

        // _root.服务器.发布服务器消息("bulletCount:" + bulletDisplay);
    });

    ref.gunString = ref.装备类型 + "_引用"; // target[gunString]

    target.长枪属性.interval = ref.weaponAttributeValue;
};

/* ---------------------------------------------------------
 * XM214_CageFrame  周期函数 (重构版)
 * --------------------------------------------------------- */
_root.装备生命周期函数.XM214周期 = function(ref:Object, param:Object) {
    _root.装备生命周期函数.移除异常周期函数(ref);
    
    var target:MovieClip = ref.自机;
    var gun:MovieClip = target[ref.gunString];
    if (!gun)
        return;

    /* -------- 1. 游戏帧计数器更新 -------- */
    ref.currentFrame++;

    /* -------- 2. 霰弹值衰减逻辑 (更精确的实现) -------- */
    // 如果距离上次射击超过了延迟时间，并且霰弹值高于下限
    if (ref.currentFrame - ref.lastFireFrame > ref.shotgunDecayDelay && ref.shotgunValue > ref.MIN_SHOTGUN_VAL) {
        // 每过 shotgunDecayDelay 帧，霰弹值衰减 1 点
        // 使用取模确保每隔固定的帧数才执行一次衰减，避免浮点数累积误差和不均匀衰减
        if ((ref.currentFrame - ref.lastFireFrame) % ref.shotgunDecayDelay == 1) {
            ref.shotgunValue = Math.max(ref.shotgunValue - 1, ref.MIN_SHOTGUN_VAL);
        }
    }

    // _root.服务器.发布服务器消息("更新霰弹值:" + ref.shotgunValue);

    /* -------- 3. 核心：根据霰弹值计算视觉转速 (应用数学模型) -------- */

    // Step 3.1: 计算归一化因子 (0.0 ~ 1.0)
    var rangeSize = ref.MAX_SHOTGUN_VAL - ref.MIN_SHOTGUN_VAL;
    // 使用 Math.max 确保 shotgunValue 不会低于下限，避免负值
    var spinFactor = (Math.max(ref.MIN_SHOTGUN_VAL, ref.shotgunValue) - ref.MIN_SHOTGUN_VAL) / rangeSize;

    // Step 3.2: 计算当前帧的动画速度
    var currentSpeed:Number = ref.maxVisualSpinSpeed * spinFactor;

    /* -------- 4. 应用转速，更新动画帧 -------- */
    if (currentSpeed > 0) {
        // 累加动画帧
        ref.gunFrame += currentSpeed;

        // 高效取模，使动画循环播放
        // (gun._totalframes 是动画总帧数)
        if (ref.gunFrame > gun._totalframes) {
            ref.gunFrame = ((ref.gunFrame - 1) % gun._totalframes) + 1;
        }

        gun.gotoAndStop(Math.floor(ref.gunFrame));
    } else // 如果转速为0 (即 shotgunValue <= 5)，则强制停在第1帧
    {
        if (gun._currentframe != 1) {
            gun.gotoAndStop(1);
        }
        ref.gunFrame = 1; // 重置动画帧变量，以便下次转动时从头开始
    }

    // 获取元件引用
    var ring1:MovieClip = gun.环1;
    var ring2:MovieClip = gun.环2;

    // 检查元件是否存在，避免出错
    if (!ring1 || !ring2) {
        return;
    }

    // 计算基础帧。环动画有8帧，分别对应 shotgunValue 的 5 到 12。
    // shotgunValue = 5  -> 基础帧 = 1
    // shotgunValue = 6  -> 基础帧 = 2
    // ...
    // shotgunValue = 12 -> 基础帧 = 8
    var baseFrame:Number = ref.shotgunValue - ref.MIN_SHOTGUN_VAL + 1;

    var frame1:Number; // 最终用于 ring1 的帧
    var frame2:Number; // 最终用于 ring2 的帧

    // 根据 shotgunValue 的不同情况应用不同策略
    switch (ref.shotgunValue) {

        case ref.MIN_SHOTGUN_VAL: // 情况一：霰弹值为5 (最小值)
            // 不错开，不抖动，都停在第1帧 (代表关闭/无能量状态)
            frame1 = 1;
            frame2 = 1;
            break;

        default: // 情况三：霰弹值在 6 到 12 之间 (抖动状态)
            // 使用游戏帧数 currentFrame 来创建周期性的变化
            var flickerType:Number = ref.currentFrame % ref.flickerCycle; // 得到抖动周期内的索引

            // --- 环1的抖动逻辑 ---
            // 让它在 [baseFrame-1, baseFrame] 之间抖动
            if (flickerType == 0) {
                frame1 = baseFrame - 1;
            } else { // 其他情况显示基础帧，让基础帧的停留时间更长
                frame1 = baseFrame;
            }

            // --- 环2的抖动逻辑 (与环1错开) ---
            // 让它在 [baseFrame, baseFrame+1] 之间抖动
            // 使用不同的时机来错开时间
            if (flickerType == (ref.flickerCycle - 1)) {
                frame2 = baseFrame + 1;
            } else {
                frame2 = baseFrame;
            }
            break;
    }

    // 最后，应用计算出的帧数
    // 同时要确保帧数在有效范围内 (例如 1 到 _totalframes)
    var totalFrames:Number = ring1._totalframes; // 假设 ring1 和 ring2 总帧数相同

    // 使用 Math.max 和 Math.min 来防止帧数越界
    var finalFrame1:Number = Math.max(1, Math.min(frame1, totalFrames));
    var finalFrame2:Number = Math.max(1, Math.min(frame2, totalFrames));
    //_root.发布消息(finalFrame1, finalFrame2)

    ring1.gotoAndStop(finalFrame1);
    ring2.gotoAndStop(finalFrame2);
};
