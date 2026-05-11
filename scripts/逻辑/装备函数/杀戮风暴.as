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

    DressupSubscriber.onPlacement(target, "刀_引用", function() {
        _root.装备生命周期函数.杀戮风暴视觉更新(ref);
    });

    // _root.服务器.发布服务器消息("杀戮风暴初始化完成，旋转区间：" + ref.startFrame + " 到 " + ref.endFrame);
};


// ---------------------------------------------------------------
// 周期：限制循环在 [startFrame .. endFrame]，并在回到 startFrame 前判断是否该退出
// ---------------------------------------------------------------
_root.装备生命周期函数.杀戮风暴周期 = function(ref:Object, param:Object) {
    _root.装备生命周期函数.移除异常周期函数(ref);
    if (!VisualSync.beginTick(ref)) return;

    var target:MovieClip = ref.自机;
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

    // ===== 推进 saberFrame 最终值（state 推进，不直接 apply 视觉）=====
    if (ref.spinCount <= 0 || currentSpeed <= 0) {
        // 未旋转：回到默认帧
        ref.saberFrame = ref.defaultFrame;
    } else if (ref.saberFrame < start && currentSpeed < ref.spinStartThreshold) {
        // 进入旋转门槛：速度不够，保持默认帧
        ref.saberFrame = ref.defaultFrame;
    } else {
        // 速度达标 / 已在旋转区间
        if (ref.saberFrame < start) {
            ref.saberFrame = start;
        }
        ref.saberFrame += currentSpeed;

        if (ref.saberFrame > end) {
            if (!ref.isAttacking && currentSpeed < ref.spinStopThreshold) {
                // 低速退出旋转
                ref.spinCount  = 0;
                ref.saberFrame = ref.defaultFrame;
            } else {
                // 区间回环
                ref.saberFrame = start + ((ref.saberFrame - start) % len);
            }
        }
    }

    // 重置单帧攻击标记
    ref.isAttacking = false;

    _root.装备生命周期函数.杀戮风暴视觉更新(ref);
    // _root.服务器.发布服务器消息("帧数:" + animMc._currentframe + " 速度:" + currentSpeed + " 计数:" + ref.spinCount );
};

_root.装备生命周期函数.杀戮风暴视觉更新 = function(ref:Object) {
    var saber:MovieClip = ref.自机.刀_引用;
    if (saber == undefined || saber.动画 == undefined) return;

    var animMc:MovieClip = saber.动画;
    var targetFrame:Number = Math.floor(ref.saberFrame);
    if (animMc._currentframe != targetFrame) {
        animMc.gotoAndStop(targetFrame);
    }
};
