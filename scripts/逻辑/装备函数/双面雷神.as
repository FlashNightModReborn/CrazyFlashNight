// =======================================================
// 双面雷神 · 步枪/狙击枪双形态装备生命周期函数
// =======================================================

_root.装备生命周期函数.双面雷神初始化 = function(ref:Object, param:Object) {
    var target:MovieClip = ref.自机;
    target.syncRequiredEquips.长枪_引用 = true;

    /* ---------- 1. 帧常量定义 ---------- */
    ref.RIFLE_START = param.rifleStartFrame || 1;      // 步枪起始帧
    ref.RIFLE_END = param.rifleEndFrame || 18;         // 步枪结束帧
    ref.SNIPER_START = param.sniperStartFrame || 18;   // 狙击枪起始帧
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
        ref.currentFrame = ref.isSniperMode ? ref.SNIPER_END : ref.RIFLE_END;
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
    _root.服务器.发布服务器消息("双面雷神当前帧: " + ref.currentFrame);
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
    if (ref.transformCooldown > 0) {
        --ref.transformCooldown;
    }

    // 用于避免“首帧被推进”
    var startedThisFrame:Boolean = false;

    /* ===== 2. 变形键触发 ===== */
    if (!ref.isTransforming && ref.transformCooldown == 0) {
        if (_root.按键输入检测(自机, _root.武器变形键)) {
            ref.isTransforming = true;
            ref.transformToSniper = !ref.isSniperMode;    // 切换到相反形态
            ref.transformCooldown = ref.TRANSFORM_CD_F;

            // 起始帧：一次性定位，不在同一帧推进，避免跳过起始帧
            if (ref.transformToSniper) {
                // 步枪→狙击：从步枪结束帧+1开始向狙击结束帧推进
                ref.currentFrame = ref.RIFLE_END + 1;
            } else {
                // 狙击→步枪：从狙击结束帧-1开始向步枪结束帧推进
                ref.currentFrame = ref.SNIPER_END - 1;
            }

            startedThisFrame = true;
        }
    }

    /* ===== 3. 变形动画推进 ===== */
    if (ref.isTransforming && !startedThisFrame) {
        if (ref.transformToSniper) {           // 步枪→狙击（增帧）
            if (ref.currentFrame < ref.SNIPER_END) {
                ++ref.currentFrame;            // 向狙击结束帧推进
            } else {                           // == SNIPER_END，完成变形
                ref.isTransforming = false;
                ref.isSniperMode = true;
                // 停在结束帧，不再跳回起始帧
                // 此时 currentFrame 已经是 SNIPER_END
                if (ref.是否为主角 && ref.globalData) {
                    ref.globalData.isSniperMode = true;
                }
            }
        } else {                               // 狙击→步枪（减帧）
            if (ref.currentFrame > ref.RIFLE_END) {
                --ref.currentFrame;            // 向步枪结束帧推进
            } else {                           // == RIFLE_END，完成变形
                ref.isTransforming = false;
                ref.isSniperMode = false;
                // 同理，停在 RIFLE_END
                if (ref.是否为主角 && ref.globalData) {
                    ref.globalData.isSniperMode = false;
                }
            }
        }
    }

    // ★ 关键改变：
    // 不在变形时，不再强制把 currentFrame 拉回 *_START，
    // 这样才能真正“停在结束帧”。
    // 你如果之后想专门定义一个“待机静止帧”，可以再额外加显式赋值。

    // 同步模式状态到自机
    自机.isSniperMode = ref.isSniperMode;

    // 调用视觉函数绘制（内部会根据 currentFrame 做 gotoAndStop）
    _root.装备生命周期函数.双面雷神视觉(ref);
};
