// =======================================================
// G1111 · 装备生命周期函数 (单向推进版)
// =======================================================

_root.装备生命周期函数.G1111初始化 = function (ref, param)
{
    var target:MovieClip = ref.自机;

    /* ---------- 1. 帧常量 ---------- */
    ref.RIFLE_START      = param.rifleStart  ||  1;
    ref.RIFLE_END        = param.rifleEnd    || 15;
    ref.TRANSFORM_START  = param.transStart  || 16;
    ref.TRANSFORM_END    = param.transEnd    || 30;
    ref.ROCKET_START     = param.rocketStart || 31;
    ref.ROCKET_END       = param.rocketEnd   || 45;

    /* ---------- 2. 状态变量 ---------- */
    ref.isRocketMode     = false;   // false = 步枪, true = 导弹
    ref.isTransforming   = false;
    ref.transformToRock  = false;   // true = 步枪→导弹, false = 导弹→步枪
    ref.isFiring         = false;   // 射击进行中
    ref.fireRequest      = false;   // 当帧射击触发
    ref.currentFrame     = ref.RIFLE_START;
    ref.isWeaponActive   = false;

    /* ---------- 3. 变形冷却 ---------- */
    ref.transformCooldown = 0;
    ref.TRANSFORM_CD_F    = param.transformInterval || 30; // 30 fps = 1 s

    /* ---------- 4. 全局主角同步 ---------- */
    if (ref.是否为主角) {
        var key = ref.标签名 + ref.初始化函数;
        var gl  = _root.装备生命周期函数.全局参数[key] || {};
        ref.isRocketMode  = gl.isRocketMode || false;
        ref.currentFrame  = ref.isRocketMode ? ref.ROCKET_START : ref.RIFLE_START;
        ref.globalData    = gl;
    }

    /* ---------- 5. 射击事件监听 ---------- */
    target.dispatcher.subscribe
    ("长枪射击", function () {
        ref.fireRequest = true;
        _root.发布消息(target)
    });
};

/*--------------------------------------------------------
 * 周期函数
 *------------------------------------------------------*/
_root.装备生命周期函数.G1111周期 = function (ref)
{
    _root.装备生命周期函数.移除异常周期函数(ref);

    var 自机  = ref.自机;
    var 长枪  = 自机.长枪_引用;
    var prevFrame = ref.currentFrame;
    var prevFiring = ref.isFiring;
    var prevTransforming = ref.isTransforming;

    /* ===== 0. 武器激活检测 ===== */
    var prevActive = ref.isWeaponActive;
    ref.isWeaponActive = (自机.攻击模式 === "长枪");
    
    
    if (!ref.isWeaponActive) {
        // 收枪：立即复位并清状态
        ref.isTransforming = ref.isFiring = ref.fireRequest = false;
        ref.currentFrame   = ref.isRocketMode ? ref.ROCKET_START : ref.RIFLE_START;
        长枪.gotoAndStop(ref.currentFrame);
        return;
    }

    /* ===== 1. 读取并清除 fireRequest ===== */
    var wantFire = ref.fireRequest;
    ref.fireRequest = false;

    /* ===== 2. 冷却计数 ===== */
    if (ref.transformCooldown > 0) --ref.transformCooldown;

    /* ===== 3. 变形键触发 ===== */
    if (!ref.isTransforming && ref.transformCooldown == 0) {
        if (_root.按键输入检测(自机, _root.武器变形键)) {
            ref.isTransforming   = true;
            ref.transformToRock  = !ref.isRocketMode;          // 目标形态
            ref.transformCooldown = ref.TRANSFORM_CD_F;

            // 选定起始帧（单向推进）
            ref.currentFrame = ref.transformToRock ?
                               ref.TRANSFORM_START : ref.TRANSFORM_END;
        }
    }

    /* ===== 4. 射击优先级处理（可打断变形和重触发） ===== */
    if (wantFire) {
        // 如果正在变形，停止变形并切换到目标形态
        if (ref.isTransforming) {
            ref.isTransforming = false;
            ref.isRocketMode   = ref.transformToRock;
            if (ref.是否为主角 && ref.globalData)
                ref.globalData.isRocketMode = ref.isRocketMode;
        }
        
        // 设置射击状态并跳转到第一帧
        ref.isFiring = true;
        ref.currentFrame = ref.isRocketMode ? ref.ROCKET_START : ref.RIFLE_START;
        长枪.gotoAndStop(ref.currentFrame);  // 立即绘制第一帧
        return; // 本周期只绘制第一帧，下周期开始推进
    }

    /* ===== 5. 动画推进 ===== */
    // 5-A 变形段 ---------------------------------------------------
    if (ref.isTransforming) {
        长枪.gotoAndStop(ref.currentFrame);  // 先绘制

        if (ref.transformToRock) {           // 步枪→导弹（增帧）
            if (ref.currentFrame < ref.TRANSFORM_END) {
                ++ref.currentFrame;          // 只增不减
            } else {                         // 到 30，切导弹待机
                ref.isTransforming = false;
                ref.isRocketMode   = true;
                ref.currentFrame   = ref.ROCKET_START;
                if (ref.是否为主角 && ref.globalData)
                    ref.globalData.isRocketMode = true;
            }
        } else {                             // 导弹→步枪（减帧）
            if (ref.currentFrame > ref.TRANSFORM_START) {
                --ref.currentFrame;          // 只减不增
            } else {
                ref.isTransforming = false;
                ref.isRocketMode   = false;
                ref.currentFrame   = ref.RIFLE_START;
                if (ref.是否为主角 && ref.globalData)
                    ref.globalData.isRocketMode = false;
            }
        }
        return; // 变形帧已绘制完毕
    }

    // 5-B 射击段 ----------------------------------------------------
    if (ref.isFiring) {
        var endF = ref.isRocketMode ? ref.ROCKET_END : ref.RIFLE_END;

        if (ref.currentFrame < endF) {
            ++ref.currentFrame;                // 只向前播
        } else {
            // 播到 15 / 45 后回待机
            ref.isFiring     = false;
            ref.currentFrame = ref.isRocketMode ? ref.ROCKET_START : ref.RIFLE_START;
        }
    } else {
        // 待机：保证在 1 / 31，不平滑渐变
        var idleFrame = ref.isRocketMode ? ref.ROCKET_START : ref.RIFLE_START;
        if (ref.currentFrame !== idleFrame) {
            ref.currentFrame = idleFrame;
        }
    }


    /* ===== 7. 绘制 ===== */
    长枪.gotoAndStop(ref.currentFrame);
};