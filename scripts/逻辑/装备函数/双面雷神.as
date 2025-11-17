// =======================================================
// 双面雷神 · 步枪/狙击枪双形态装备生命周期函数
// =======================================================

_root.装备生命周期函数.双面雷神初始化 = function(ref:Object, param:Object) {
    var target:MovieClip = ref.自机;
    target.syncRequiredEquips.长枪_引用 = true;

    /* ---------- 1. 帧常量定义 ---------- */
    ref.RIFLE_START = param.rifleStartFrame || 1;      // 步枪起始帧
    ref.RIFLE_END = param.rifleEndFrame || 18;         // 步枪结束帧
    ref.SNIPER_START = param.sniperStartFrame || 19;   // 狙击枪起始帧
    ref.SNIPER_END = param.sniperEndFrame || 32;       // 狙击枪结束帧

    /* ---------- 2. 状态变量 ---------- */
    ref.isSniperMode = false;       // false = 步枪模式, true = 狙击枪模式
    ref.isTransforming = false;     // 是否正在变形
    ref.transformToSniper = false;  // 变形方向：true = 步枪→狙击, false = 狙击→步枪
    ref.currentFrame = ref.RIFLE_START;

    /* ---------- 3. 变形冷却 ---------- */
    ref.transformCooldown = 0;
    ref.TRANSFORM_CD_F = param.transformInterval || 30; // 变形冷却时间（帧）

    /* ---------- 4. 狙击枪参数 ---------- */
    ref.sniperCapacity = param.capacity2 || 14;    // 狙击模式弹容量
    ref.sniperSound = param.sound2 || "apwersound.wav";  // 狙击音效
    ref.sniperSplit = param.split2 || 1;           // 狙击霰弹值

    /* ---------- 5. 全局主角同步 ---------- */
    if (ref.是否为主角) {
        var key = ref.标签名 + ref.初始化函数;
        // 确保全局参数对象存在
        if (!_root.装备生命周期函数.全局参数) {
            _root.装备生命周期函数.全局参数 = {};
        }
        if (!_root.装备生命周期函数.全局参数[key]) {
            _root.装备生命周期函数.全局参数[key] = {};
        }
        var gl = _root.装备生命周期函数.全局参数[key];
        ref.isSniperMode = gl.isSniperMode || false;
        ref.currentFrame = ref.isSniperMode ? ref.SNIPER_START : ref.RIFLE_START;
        ref.globalData = gl;
        // 确保全局数据同步
        gl.isSniperMode = ref.isSniperMode;
    }

    /* ---------- 6. 射击事件监听 ---------- */
    target.dispatcher.subscribe("长枪射击", function() {
        if (target.攻击模式 !== "长枪") return;
        var prop:Object = target.man.子弹属性;

        // 根据当前形态设置武器属性
        if (ref.isSniperMode) {
            // 狙击枪模式
            prop.霰弹值 = ref.sniperSplit;
        } else {
            // 步枪模式 - 使用默认值
        }

        // 同步模式状态到自机
        target.isSniperMode = ref.isSniperMode;
    });

    target.dispatcher.subscribe("StatusChange", function() {
        _root.装备生命周期函数.双面雷神视觉(ref);
    });
};

/*--------------------------------------------------------
 * 视觉函数 - 处理武器形态切换的视觉动画
 *------------------------------------------------------*/
_root.装备生命周期函数.双面雷神视觉 = function(ref:Object) {
    var 自机 = ref.自机;
    var 长枪 = 自机.长枪_引用;

    if (!长枪) return;

    // 武器未激活时，复位到对应形态的起始帧
    if (自机.攻击模式 !== "长枪") {
        ref.isTransforming = false;
        ref.currentFrame = ref.isSniperMode ? ref.SNIPER_START : ref.RIFLE_START;
        长枪.gotoAndStop(ref.currentFrame);
        return;
    }

    // 绘制当前帧
    长枪.gotoAndStop(ref.currentFrame);
};

/*--------------------------------------------------------
 * 周期函数 - 只处理形态转换逻辑
 *------------------------------------------------------*/
_root.装备生命周期函数.双面雷神周期 = function(ref:Object) {
    _root.装备生命周期函数.移除异常周期函数(ref);

    var 自机 = ref.自机;

    // 只在武器激活时处理逻辑
    if (自机.攻击模式 !== "长枪") {
        return;
    }

    /* ===== 1. 冷却计数 ===== */
    if (ref.transformCooldown > 0) --ref.transformCooldown;

    /* ===== 2. 变形键触发 ===== */
    if (!ref.isTransforming && ref.transformCooldown == 0) {
        if (_root.按键输入检测(自机, _root.武器变形键)) {
            ref.isTransforming = true;
            ref.transformToSniper = !ref.isSniperMode;    // 切换到相反形态
            ref.transformCooldown = ref.TRANSFORM_CD_F;

            // 选定起始帧（单向推进）
            ref.currentFrame = ref.transformToSniper ?
                               (ref.RIFLE_END + 1) : (ref.SNIPER_START - 1);
        }
    }

    /* ===== 3. 变形动画推进 ===== */
    if (ref.isTransforming) {
        if (ref.transformToSniper) {           // 步枪→狙击（增帧）
            if (ref.currentFrame < ref.SNIPER_START - 1) {
                ++ref.currentFrame;            // 只增不减
            } else {                           // 到达狙击模式起始帧前，切换到狙击模式
                ref.isTransforming = false;
                ref.isSniperMode = true;
                ref.currentFrame = ref.SNIPER_START;
                if (ref.是否为主角 && ref.globalData)
                    ref.globalData.isSniperMode = true;
            }
        } else {                               // 狙击→步枪（减帧）
            if (ref.currentFrame > ref.RIFLE_END + 1) {
                --ref.currentFrame;            // 只减不增
            } else {                           // 到达步枪模式结束帧后，切换到步枪模式
                ref.isTransforming = false;
                ref.isSniperMode = false;
                ref.currentFrame = ref.RIFLE_START;
                if (ref.是否为主角 && ref.globalData)
                    ref.globalData.isSniperMode = false;
            }
        }
    } else {
        // 待机：保证在起始帧
        var idleFrame = ref.isSniperMode ? ref.SNIPER_START : ref.RIFLE_START;
        if (ref.currentFrame !== idleFrame) {
            ref.currentFrame = idleFrame;
        }
    }

    // 同步模式状态到自机
    自机.isSniperMode = ref.isSniperMode;

    // 调用视觉函数绘制
    _root.装备生命周期函数.双面雷神视觉(ref);
};
