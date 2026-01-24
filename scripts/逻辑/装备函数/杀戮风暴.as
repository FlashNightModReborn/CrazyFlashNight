// ---------------------------------------------------------------
// 初始化：新增两个阈值 & 旋转区间长度
// ---------------------------------------------------------------
_root.装备生命周期函数.杀戮风暴初始化 = function(ref:Object, param:Object) {
    var target:MovieClip = ref.自机;
    var saber:MovieClip = target.刀_引用;
    var animMc:MovieClip = saber.动画;

    // --- 旋转参数 ---
    ref.maxSpinCount     = (param.maxSpinCount != undefined)     ? param.maxSpinCount     : 29;
    ref.spinUpAmount     = (param.spinUpAmount != undefined)     ? param.spinUpAmount     : 5;
    ref.spinSpeedFactor  = (param.spinSpeedFactor != undefined)  ? param.spinSpeedFactor  : 0.1;
    ref.spinDownRate     = (param.spinDownRate != undefined)     ? param.spinDownRate     : 0.33;

    // --- 进入/退出旋转的速度阈值（单位：帧/周期）---
    // 进入旋转门槛要略高于退出门槛，形成滞回，避免抖动
    ref.spinStartThreshold = (param.spinStartThreshold != undefined) ? param.spinStartThreshold : 0.40;
    ref.spinStopThreshold  = (param.spinStopThreshold  != undefined) ? param.spinStopThreshold  : 0.25;

    // --- 状态 ---
    ref.saberFrame   = 1;
    ref.spinCount    = 0;
    ref.isAttacking  = false;

    // --- 帧区间 ---
    ref.defaultFrame = (param.defaultFrame != undefined) ? param.defaultFrame : 1;
    ref.startFrame   = (param.startFrame   != undefined) ? param.startFrame   : 2;
    ref.endFrame     = (param.endFrame     != undefined) ? param.endFrame     : animMc._totalframes || 31;
    ref.rotLen       = ref.endFrame - ref.startFrame + 1; // 旋转区间长度

    // _root.服务器.发布服务器消息("杀戮风暴初始化完成，旋转区间：" + ref.startFrame + " 到 " + ref.endFrame);
};


// ---------------------------------------------------------------
// 周期：限制循环在 [startFrame .. endFrame]，并在回到 startFrame 前判断是否该退出
// ---------------------------------------------------------------
_root.装备生命周期函数.杀戮风暴周期 = function(ref:Object, param:Object) {
    //_root.装备生命周期函数.移除异常周期函数(ref);

    var target:MovieClip = ref.自机;
    var saber:MovieClip = target.刀_引用;
    if (saber == undefined || saber.动画 == undefined) return;

    var animMc:MovieClip = saber.动画;
    var start:Number = ref.startFrame;
    var end:Number   = ref.endFrame;
    var len:Number   = ref.rotLen;

    // 读取攻击状态（单帧有效）
    if (_root.兵器攻击检测(target)) {
        ref.isAttacking = true;
    }

    // ===== 连射计数更新（加速/自然衰减）=====
    (ref.isAttacking && (ref.spinCount = Math.min(ref.spinCount + ref.spinUpAmount, ref.maxSpinCount))) ||
    (ref.spinCount = Math.max(0, ref.spinCount - ref.spinDownRate));

    // 当前速度（帧/周期）
    var currentSpeed:Number = ref.spinCount * ref.spinSpeedFactor;

    // —— 未旋转：保持或回到默认帧 ——
    if (ref.spinCount <= 0 || currentSpeed <= 0) {
        if (animMc._currentframe != ref.defaultFrame) {
            animMc.gotoAndStop(ref.defaultFrame);
        }
        ref.saberFrame  = ref.defaultFrame;
        ref.isAttacking = false; // 重置
        return;
    }

    // —— 进入旋转门槛：只有速度足够才进入旋转区间 —— 
    if (ref.saberFrame < start) {
        if (currentSpeed < ref.spinStartThreshold) {
            // 速度不够，仍然视为未进入旋转，保持默认帧
            if (animMc._currentframe != ref.defaultFrame) animMc.gotoAndStop(ref.defaultFrame);
            ref.saberFrame  = ref.defaultFrame;
            ref.isAttacking = false;
            return;
        }
        // 速度达标，切入旋转区间起点
        ref.saberFrame = start;
    }

    // —— 前进帧 —— 
    ref.saberFrame += currentSpeed;

    // —— 回环判断：将从 end 回到 start 之前，如果低速且本帧未攻击，退出到 1 帧 —— 
    if (ref.saberFrame > end) {
        // 即将回到 startFrame 的临界点
        if (!ref.isAttacking && currentSpeed < ref.spinStopThreshold) {
            // 低速退出旋转，落回默认帧（1）
            ref.spinCount   = 0;
            ref.saberFrame  = ref.defaultFrame;
            if (animMc._currentframe != ref.defaultFrame) animMc.gotoAndStop(ref.defaultFrame);
        } else {
            // 仍保持旋转：在 [start..end] 区间取模回环
            ref.saberFrame = start + ((ref.saberFrame - start) % len);
            animMc.gotoAndStop(Math.floor(ref.saberFrame));
        }
    } else {
        // 普通前进
        animMc.gotoAndStop(Math.floor(ref.saberFrame));
    }

    // 重置单帧攻击标记
    ref.isAttacking = false;
    // _root.服务器.发布服务器消息("帧数:" + animMc._currentframe + " 速度:" + currentSpeed + " 计数:" + ref.spinCount );
};
