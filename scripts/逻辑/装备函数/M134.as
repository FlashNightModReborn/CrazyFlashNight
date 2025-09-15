_root.装备生命周期函数.M134初始化 = function(ref:Object, param:Object) {
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
    });
};

_root.装备生命周期函数.M134周期 = function(ref:Object, param:Object) {
    var target:MovieClip = ref.自机;
    var gun:MovieClip = target.长枪_引用;
    if (gun == undefined || gun.动画 == undefined) {
        return;
    }
    var gunAnim:MovieClip = gun.动画;

    // ===== AVM1性能优化：利用短路逻辑避免条件分支 =====
    // 
    // 传统的if-else会产生跳转指令，而短路逻辑可以让AVM1:
    // 1. 减少分支预测失败的开销
    // 2. 更好地利用寄存器进行连续运算
    // 3. 避免栈操作，直接在寄存器中完成赋值
    //
    // 执行逻辑分析：
    // - 当 isFiring=true:  左侧表达式为真，执行左侧赋值，右侧被短路跳过
    // - 当 isFiring=false: 左侧表达式为假，跳过左侧，执行右侧赋值
    //
    // 性能优势：
    // - 利用 && 和 || 的副作用进行条件赋值，避免显式的if分支
    // - 赋值表达式的返回值直接参与布尔运算，减少中间变量
    // - AVM1可以将整个表达式优化为寄存器操作序列

    // 1. 根据射击状态更新连射计数（短路优化版本）
    (ref.isFiring && (ref.fireCount = Math.min(ref.fireCount + ref.spinUpAmount, ref.maxSpinCount))) || 
    (ref.fireCount = Math.max(0, ref.fireCount - ref.spinDownRate));

    /* 
    短路执行路径详解：

    路径A（射击时）：ref.isFiring = true
    ├─ 评估 ref.isFiring → true
    ├─ 执行 ref.fireCount = Math.min(...) → 返回新的fireCount值（truthy）
    ├─ && 结果为真，整个表达式为真
    └─ || 右侧被短路，不执行递减操作

    路径B（未射击时）：ref.isFiring = false  
    ├─ 评估 ref.isFiring → false
    ├─ && 短路，不执行左侧赋值
    ├─ 转向 || 右侧
    ├─ 执行 ref.fireCount = Math.max(0, ...) → 返回新的fireCount值
    └─ || 右侧执行完毕，表达式结束

    AVM1寄存器利用模式：
    - fireCount 值保持在寄存器中，避免反复的栈操作
    - Math.min/max 的结果直接用于后续的布尔评估
    - 单一表达式链，减少指令间的依赖等待
    */

    // 2. 如果枪在转动，则计算并更新动画
    if (ref.fireCount > 0) {
        var currentSpeed:Number = ref.fireCount * ref.spinSpeedFactor;
        ref.gunFrame += currentSpeed;

        // 使用高效的单行取模运算来处理动画帧循环
        if (ref.gunFrame > gunAnim._totalFrames) {
            ref.gunFrame = ((ref.gunFrame - 1) % gunAnim._totalFrames) + 1;
        }
        
        gunAnim.gotoAndStop(Math.floor(ref.gunFrame));
    } else if(gunAnim._currentFrame != 1) {
        // 如果不在射击状态且当前帧不是第一帧，则重置到第一帧
        gunAnim.gotoAndStop(1);
    }

    // 3. 重置射击状态
    ref.isFiring = false;
};