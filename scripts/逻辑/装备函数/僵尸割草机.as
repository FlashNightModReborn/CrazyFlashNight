_root.装备生命周期函数.僵尸割草机初始化 = function(ref:Object, param:Object) {
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
        prop.区域定位area = area;
    });
};

_root.装备生命周期函数.僵尸割草机周期 = function(ref:Object, param:Object) {
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
};