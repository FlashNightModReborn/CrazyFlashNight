/* ============ 初始化 ============ */
_root.装备生命周期函数.XM556_OC_Overlord初始化 = function (ref:Object, param:Object) {
    var target:MovieClip = ref.自机;
    var evtType:String   = ref.装备类型 + "射击";

    /* --- 运行时状态 --- */
    ref.currentFrame = 1;      // 展开/收拢帧
    ref.isFiring     = false;  // 本帧是否检测到射击事件
    ref.shootPlaying = false;  // 是否正在播放射击循环
    ref.shootFrame   = 0;      // 当前射击循环帧

    /* --- 战斗模式白名单 --- */
    ref.modeObject = { 双枪:true, 手枪:true, 手枪2:true };

    /* --- 动画实例引用 --- */
    

    /* --- 订阅射击事件 --- */
    target.dispatcher.subscribe(evtType, function ():Void {
        ref.isFiring = true;   // 标记收到射击指令，稍后在周期函数里消费
    });
};

/* ============ 周期更新 ============ */
_root.装备生命周期函数.XM556_OC_Overlord周期 = function (ref:Object, param:Object) {
    //_root.装备生命周期函数.移除异常周期函数(ref);
    
    var target:MovieClip = ref.自机;
    var gun:MovieClip    = target[ref.gunString];
    if (!gun) return;                       // 防御性检查
    var gunAnim:MovieClip = gun.动画;

    /* ---------- 1. 新射击请求 ---------- */
    if (ref.isFiring) {
        ref.isFiring     = false;           // 消费事件
        ref.shootPlaying = true;            // 进入射击循环
        ref.shootFrame   = 16;              // 从 16 帧开始
        gunAnim.gotoAndStop(ref.shootFrame);
        return;                             // 本帧已设置，退出
    }

    /* ---------- 2. 正在射击循环 ---------- */
    if (ref.shootPlaying) {
        ref.shootFrame++;
        if (ref.shootFrame > 30) {          // 一轮射击结束
            ref.shootPlaying = false;
            ref.shootFrame   = 0;           // 清零等待下次
            // 继续向下执行，回到展开/收拢逻辑
        } else {
            gunAnim.gotoAndStop(ref.shootFrame);
            return;                         // 射击帧已更新
        }
    }

    /* ---------- 3. 展开 / 收拢 ---------- */
    var inCombat:Boolean   = ref.modeObject[target.攻击模式];
    var targetFrame:Number = inCombat ? 15 : 1;

    if (ref.currentFrame < targetFrame) {
        ref.currentFrame++;
    } else if (ref.currentFrame > targetFrame) {
        ref.currentFrame--;
    }

    gunAnim.gotoAndStop(ref.currentFrame);
};
