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

    DressupSubscriber.onPlacement(target, ref.gunString, function () {
        _root.装备生命周期函数.XM556_OC_Overlord视觉更新(ref);
    });
};

/* ============ 周期更新 ============ */
_root.装备生命周期函数.XM556_OC_Overlord周期 = function (ref:Object, param:Object) {
    _root.装备生命周期函数.移除异常周期函数(ref);
    if (!VisualSync.beginTick(ref)) return;

    var target:MovieClip = ref.自机;

    /* ---------- 1. 新射击请求 ---------- */
    if (ref.isFiring) {
        ref.isFiring     = false;           // 消费事件
        ref.shootPlaying = true;            // 进入射击循环
        ref.shootFrame   = 16;              // 从 16 帧开始
        _root.装备生命周期函数.XM556_OC_Overlord视觉更新(ref);
        return;
    }

    /* ---------- 2. 正在射击循环 ---------- */
    if (ref.shootPlaying) {
        ref.shootFrame++;
        if (ref.shootFrame > 30) {          // 一轮射击结束
            ref.shootPlaying = false;
            ref.shootFrame   = 0;           // 清零等待下次
            // 继续向下执行，回到展开/收拢逻辑
        } else {
            _root.装备生命周期函数.XM556_OC_Overlord视觉更新(ref);
            return;
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

    _root.装备生命周期函数.XM556_OC_Overlord视觉更新(ref);
};

_root.装备生命周期函数.XM556_OC_Overlord视觉更新 = function (ref:Object) {
    var gun:MovieClip = ref.自机[ref.gunString];
    if (!gun || !gun.动画) return;
    var gunAnim:MovieClip = gun.动画;

    // shootPlaying 时渲染 shootFrame，否则渲染 currentFrame
    gunAnim.gotoAndStop(ref.shootPlaying ? ref.shootFrame : ref.currentFrame);
};
