// 初始化阶段：只配置常量与订阅事件
_root.装备生命周期函数.Jackhammer初始化 = function(ref:Object, param:Object) {
    var target:MovieClip = ref.自机;
    
    // 初始帧和计数
    ref.gunFrame        = 1;
    ref.gunAnimFrame    = 1;
    ref.chargeCount     = 0;
    
    // 配置常量（可由 param 覆盖）
    ref.chargeCountMax  = param.chargeCountMax  || 30;
    ref.chargeStep      = param.chargeStep      || 1;
    ref.frameStep       = param.frameStep       || 1;
    
    target.chargeComplete = false;
    ref.lastChargeComplete = target.chargeComplete;

    // 射击时重置充能与动效
    target.dispatcher.subscribe("长枪射击", function() {
        ref.gunAnimFrame    = 2;
        ref.chargeCount     = 0;
        target.chargeComplete = false;
    });

    ref.skill_normal = param.skill_0;
    ref.skill_chargeComplete = param.skill_1;

    // target.装载主动战技(ref.skill_normal, "长枪");
};

// 每帧周期更新：充能 → 主枪帧 → 动画帧
_root.装备生命周期函数.Jackhammer周期 = function(ref:Object, param:Object) {
    var target:MovieClip = ref.自机;
    var gun:MovieClip    = target.长枪_引用;
    var gunAnim:MovieClip= gun.动画;
    var barrel:MovieClip = gun.枪管;
    var laser:MovieClip  = gun.激光模组;
    
    // —— 1. 充能逻辑 —— 
    var isActive = (target.攻击模式 === "长枪");
    laser._visible = isActive;
    
    if (isActive) {
        // 长枪模式：按键增加充能，松开时减少（仅当 > 0 时）
        if (_root.按键输入检测(target, _root.武器变形键)) {
            ref.chargeCount = Math.min(ref.chargeCount + ref.chargeStep, ref.chargeCountMax);
        } else if (ref.chargeCount > 0) {
            ref.chargeCount = Math.max(ref.chargeCount - ref.chargeStep, 0);
        }
        
        // 只有在达到最大充能时才设置完成状态（保持锁定机制）
        if (ref.chargeCount >= ref.chargeCountMax) {
            target.chargeComplete = true;
            
        }
    } else {
        // 非长枪模式：强制重置充能状态
        target.chargeComplete = false;
        if (ref.chargeCount > 0) {
            ref.chargeCount = Math.max(ref.chargeCount - ref.chargeStep, 0);
        }
    }

    var chargeComplete:Boolean = target.chargeComplete;
    
    // —— 2. 主枪帧更新 —— 
    if (chargeComplete) {
        // 充能完成：增加帧数到最大值
        if (ref.gunFrame < gun._totalFrames) {
            ref.gunFrame = Math.min(ref.gunFrame + ref.frameStep, gun._totalFrames);
        }
    } else {
        // 充能未完成：减少帧数到最小值
        if (ref.gunFrame > 1) {
            ref.gunFrame = Math.max(ref.gunFrame - ref.frameStep, 1);
        }
    }
    gun.gotoAndStop(ref.gunFrame);
    
    // —— 3. 动画帧更新 —— 
    if (ref.gunAnimFrame > 1) {
        // 先显示当前帧
        gunAnim.gotoAndStop(ref.gunAnimFrame);
        barrel.gotoAndStop(ref.gunAnimFrame);
        
        // 然后更新到下一帧
        if (ref.gunAnimFrame >= gunAnim._totalFrames) {
            ref.gunAnimFrame = 1;
        } else {
            ref.gunAnimFrame++;
        }
    }


    // 根据充能状态切换战技装载
    if(ref.lastChargeComplete != chargeComplete) {
        var skill:Object = chargeComplete ? ref.skill_chargeComplete : ref.skill_normal;
        target.装载主动战技(skill, "长枪");
        ref.lastChargeComplete = target.chargeComplete;
    }
};