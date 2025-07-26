import org.flashNight.neur.Event.*;

_root.装备生命周期函数.混凝土切割机初始化 = function(ref:Object, param:Object) {
    var target:MovieClip = ref.自机;

    // --- 性能参数常量化 ---
    ref.maxSpinCount = param.maxSpinCount || 29;            // 最大连射计数 
    ref.spinUpAmount = param.spinUpAmount || 5;             // 每次射击增加的连射计数 
    ref.spinSpeedFactor = param.spinSpeedFactor || 0.1;     // 连射计数转换为转速的系数
    ref.spinDownRate = param.spinDownRate || 0.33;          // 连射计数的自然衰减率

    // --- 状态变量 ---
    ref.gunFrame = 1;              // 当前动画帧 (浮点数)
    ref.fireCount = 0;             // 当前连射计数
    ref.isFiring = false;          // 是否正在射击 

    // 订阅射击事件
    target.dispatcher.subscribe("长枪射击", function() {
        ref.isFiring = true; // 标记本帧正在射击
        var target:MovieClip = ref.自机;
        var gun:MovieClip = target.长枪_引用;
        var prop:Object = target.man.子弹属性;
        var area:MovieClip = gun.枪口位置;
        var spark:MovieClip = gun.火花;
        var flag:Boolean = target.混凝土切割机超载打击许可;
        spark.play();
        spark._visible = true;
        prop.区域定位area = area;
        prop.伤害类型 = flag ? "魔法" : null;
    });
};

_root.装备生命周期函数.混凝土切割机周期 = function(ref:Object, param:Object) {
    var target:MovieClip = ref.自机;
    var gun:MovieClip = target.长枪_引用;

    (ref.isFiring && (ref.fireCount = Math.min(ref.fireCount + ref.spinUpAmount, ref.maxSpinCount))) || 
    (ref.fireCount = Math.max(0, ref.fireCount - ref.spinDownRate));


    // 2. 如果枪在转动，则计算并更新动画
    if (ref.fireCount > 0) {
        var currentSpeed:Number = ref.fireCount * ref.spinSpeedFactor;
        ref.gunFrame += currentSpeed;

        // 使用高效的单行取模运算来处理动画帧循环
        if (ref.gunFrame > gun._totalFrames) {
            ref.gunFrame = ((ref.gunFrame - 1) % gun._totalFrames) + 1;
        }
        
        gun.gotoAndStop(Math.floor(ref.gunFrame));
    } else if(gun._currentFrame != 1) {
        // 如果不在射击状态且当前帧不是第一帧，则重置到第一帧
        gun.gotoAndStop(1);
    }

    // 3. 重置射击状态
    ref.isFiring = false;

    var flag:Boolean = target.混凝土切割机超载打击许可;
    var clip:MovieClip = gun.锯片.晶片;

    if(flag) {
        if(--target.混凝土切割机超载打击剩余时间 < 0) {
            target.混凝土切割机超载打击许可 = false;
        }
        // 0‑1 归一化进度
        var prog:Number = 1 - (target.混凝土切割机超载打击剩余时间 /
                            target.混凝土切割机超载打击持续时间);

        var ramp:Number = 0.05;      // 峰值所处的时间占比（越小 = 越快亮）
        var fade:Number;             // 0‑1 的可见度系数

        if (prog <= ramp) {
            // --- 快速线性冲峰 ---
            fade = prog / ramp;                 // 0 → 1
        } else {
            // --- 慢速衰减 ---
            var t:Number = (prog - ramp) / (1 - ramp);     // 0 → 1
            fade = Math.pow(1 - t, 2);   // 二次幂衰减，比线性更平滑
        }

        // fade = fade * 2 - 1;

        // 10‑100 Alpha 区间
        clip._alpha = 10 + 90 * fade;
    }

    clip._visible = flag;
};