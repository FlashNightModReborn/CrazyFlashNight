"use strict";
/// <reference path="types.ts" />
var HitNumber;
(function (HitNumber) {
    /** Flash 舞台固定尺寸（FlashCoordinateMapper 构造参数确认） */
    HitNumber.STAGE_W = 1024;
    HitNumber.STAGE_H = 576;
    HitNumber.camera = {
        gx: 0, gy: 0, sx: 1
    };
    /**
     * 由 C# FrameTask 调用，传入管道分隔字符串
     * 格式: "gx|gy|sx"（3 段）
     */
    function updateCameraRaw(raw) {
        const parts = raw.split("|");
        HitNumber.camera.gx = +parts[0];
        HitNumber.camera.gy = +parts[1];
        HitNumber.camera.sx = +parts[2];
    }
    HitNumber.updateCameraRaw = updateCameraRaw;
})(HitNumber || (HitNumber = {}));
/// <reference path="types.ts" />
var HitNumber;
(function (HitNumber) {
    /** Flash 侧 COLOR_TABLE 的镜像（HitNumberBatchProcessor.as:110） */
    HitNumber.COLOR_TABLE = [
        "#FFFFFF", "#FF0000", "#FFCC00", "#660033", "#4A0099",
        "#AC99FF", "#0099FF", "#7F0000", "#7F6A00", "#FF7F7F", "#FFE770"
    ];
    // 效果标志位常量（DamageResult.as bits 0-8）
    HitNumber.EF_CRUMBLE = 1;
    HitNumber.EF_TOXIC = 2;
    HitNumber.EF_EXECUTE = 4;
    HitNumber.EF_DMG_TYPE_LABEL = 8;
    HitNumber.EF_CRUSH_LABEL = 16;
    HitNumber.EF_LIFESTEAL = 32;
    HitNumber.EF_IS_ENEMY = 128;
    HitNumber.EF_SHIELD = 256;
    // packed 编码（DamageResult.as:462-469）：
    //   bits 0-8:   efFlags (9 bits)
    //   bit  9:     isMISS
    //   bits 10-17: damageSize (0-255)
    //   bits 18-21: colorId (0-15)
    function unpackFlags(packed) { return packed & 511; }
    HitNumber.unpackFlags = unpackFlags;
    function unpackIsMISS(packed) { return ((packed >> 9) & 1) !== 0; }
    HitNumber.unpackIsMISS = unpackIsMISS;
    function unpackSize(packed) { return (packed >> 10) & 255; }
    HitNumber.unpackSize = unpackSize;
    function unpackColorId(packed) { return (packed >> 18) & 15; }
    HitNumber.unpackColorId = unpackColorId;
    /**
     * 协议字段反序列化。
     *
     * 当前取值域审计结果：efText/efEmoji 均不含分隔符，
     * AS2 侧 safeField 仅做 null→空串，不做转义。
     * 此函数保留接口签名，当前为直通。
     *
     * 若未来协议需要转义，在此处实现反转义即可，
     * 无需修改 AS2 热路径。
     */
    function unescField(s) {
        if (!s)
            return "";
        return s;
    }
    HitNumber.unescField = unescField;
})(HitNumber || (HitNumber = {}));
/// <reference path="types.ts" />
/// <reference path="camera.ts" />
/// <reference path="animation.ts" />
/// <reference path="parser.ts" />
var HitNumber;
(function (HitNumber) {
    const POSITION_OFFSET = 60;
    const MAX_ACTIVE = 80;
    const TOTAL_FRAMES = 14;
    const MARGIN = 100;
    // ======== 混合密度管理 ========
    const DENSITY_LOW = 8;
    const MERGE_DIST = 40;
    const PULSE_REWIND = 4;
    // ======== 段数递增动画 ========
    /** 递增动画最大持续帧数（避免大段数计数太久） */
    const COUNT_ANIM_MAX_FRAMES = 8;
    const _active = [];
    let _activeCount = 0;
    function findMergeTarget(rawX, rawY) {
        for (let i = 0; i < _activeCount; i++) {
            const e = _active[i];
            const dx = e.rawX - rawX;
            const dy = e.rawY - rawY;
            if (dx * dx + dy * dy < MERGE_DIST * MERGE_DIST) {
                return i;
            }
        }
        return -1;
    }
    function spawnBatch(raw) {
        if (!raw || raw.length === 0)
            return;
        const entries = raw.split(";");
        const highDensity = _activeCount > DENSITY_LOW;
        for (let i = 0; i < entries.length; i++) {
            const parts = entries[i].split("|");
            if (parts.length < 8)
                continue;
            const rawX = +parts[1];
            const rawY = +parts[2];
            const dmg = +parts[0];
            if (highDensity) {
                const mi = findMergeTarget(rawX, rawY);
                if (mi >= 0) {
                    const existing = _active[mi];
                    existing.targetDmg += dmg;
                    existing.targetHits++;
                    // displayHits 不变——tick 时逐帧递增
                    existing.packed = +parts[3];
                    const et = HitNumber.unescField(parts[4]);
                    const ee = HitNumber.unescField(parts[5]);
                    if (et)
                        existing.efText = et;
                    if (ee)
                        existing.efEmoji = ee;
                    const ls = +parts[6];
                    const sa = +parts[7];
                    if (ls > 0)
                        existing.lifeSteal += ls;
                    if (sa > 0)
                        existing.shieldAbsorb += sa;
                    existing.frame = Math.max(0, existing.frame - PULSE_REWIND);
                    continue;
                }
            }
            if (_activeCount >= MAX_ACTIVE)
                continue;
            const entry = {
                worldX: rawX + (Math.random() - 0.5) * POSITION_OFFSET * 2,
                worldY: rawY + (Math.random() - 0.5) * POSITION_OFFSET * 2,
                rawX: rawX,
                rawY: rawY,
                targetDmg: dmg,
                displayDmg: dmg,
                packed: +parts[3],
                efText: HitNumber.unescField(parts[4]),
                efEmoji: HitNumber.unescField(parts[5]),
                lifeSteal: +parts[6],
                shieldAbsorb: +parts[7],
                frame: 0,
                targetHits: 1,
                displayHits: 1
            };
            _active[_activeCount++] = entry;
        }
    }
    HitNumber.spawnBatch = spawnBatch;
    /**
     * 每帧调用。输出 stride=12：
     * stgX,stgY,combinedScale,alpha,combinedBlur,damage,packed,efText,efEmoji,lifeSteal,shieldAbsorb,displayHits
     */
    function tick() {
        if (_activeCount === 0)
            return "";
        const cam = HitNumber.camera;
        let result = "";
        let writeIdx = 0;
        for (let i = 0; i < _activeCount; i++) {
            const e = _active[i];
            const f = e.frame;
            if (f >= TOTAL_FRAMES)
                continue;
            // 段数递增动画：displayHits 追赶 targetHits
            if (e.displayHits < e.targetHits) {
                const hitDelta = e.targetHits - e.displayHits;
                const hitRate = hitDelta <= COUNT_ANIM_MAX_FRAMES
                    ? 1
                    : Math.ceil(hitDelta / COUNT_ANIM_MAX_FRAMES);
                e.displayHits = Math.min(e.displayHits + hitRate, e.targetHits);
            }
            // 伤害递增动画：displayDmg 追赶 targetDmg（同步节奏）
            if (e.displayDmg < e.targetDmg) {
                const dmgDelta = e.targetDmg - e.displayDmg;
                const dmgRate = dmgDelta <= COUNT_ANIM_MAX_FRAMES
                    ? Math.ceil(dmgDelta / COUNT_ANIM_MAX_FRAMES)
                    : Math.ceil(dmgDelta / COUNT_ANIM_MAX_FRAMES);
                e.displayDmg = Math.min(e.displayDmg + dmgRate, e.targetDmg);
            }
            const textX = e.worldX + HitNumber.offsetXLUT[f];
            const textY = e.worldY + HitNumber.offsetYLUT[f];
            const stgX = cam.gx + textX * cam.sx;
            const stgY = cam.gy + textY * cam.sx;
            if (stgX < -MARGIN || stgX > HitNumber.STAGE_W + MARGIN ||
                stgY < -MARGIN || stgY > HitNumber.STAGE_H + MARGIN) {
                e.frame = f + 1;
                if (f + 1 < TOTAL_FRAMES)
                    _active[writeIdx++] = e;
                continue;
            }
            const combinedScale = HitNumber.scaleLUT[f] * cam.sx;
            const alpha = HitNumber.getAlpha(f);
            const combinedBlur = HitNumber.blurLUT[f] * cam.sx;
            if (result.length > 0)
                result += ";";
            result += stgX + "," + stgY + "," +
                combinedScale + "," + alpha + "," + combinedBlur + "," +
                (e.displayDmg | 0) + "," + e.packed + "," +
                e.efText + "," + e.efEmoji + "," +
                e.lifeSteal + "," + e.shieldAbsorb + "," +
                e.displayHits;
            e.frame = f + 1;
            if (f + 1 < TOTAL_FRAMES)
                _active[writeIdx++] = e;
        }
        _activeCount = writeIdx;
        return result;
    }
    HitNumber.tick = tick;
    function reset() {
        _activeCount = 0;
    }
    HitNumber.reset = reset;
    function activeCount() {
        return _activeCount;
    }
    HitNumber.activeCount = activeCount;
})(HitNumber || (HitNumber = {}));
/// <reference path="camera.ts" />
/// <reference path="animation.ts" />
/// <reference path="parser.ts" />
/// <reference path="pool.ts" />
/// <reference path="types.ts" />
var HitNumber;
(function (HitNumber) {
    /**
     * 从 打击伤害数字.xml 提取的关键帧数据
     *
     * SWF Layer 2 关键帧（XML index → Matrix [a, d, tx, ty] + GlowFilter blur）：
     *   0 (dur 4, static):  a=1.3176 tx=-241.65 ty=-136   blur=4
     *   4 (dur 3, tween→7): a=1.0687 tx=-196    ty=-131.1 blur=3
     *   7 (dur 2, static):  a=1.0    tx=-183.4  ty=-129.75 blur=3
     *   9 (dur 1, tween→10):a=0.9291 tx=-170.4  ty=-135.85 blur=2
     *  10 (dur 3, tween→13):a=0.9056 tx=-166.1  ty=-137.9  blur=2
     *  13 (dur 1):          a=0.3280 tx=-88.7   ty=-136.5  blur=1
     *  14: recovery (empty)
     *
     * Flash motion tween = 线性插值（无 easing）
     * static 帧段（无 tweenType）= 保持关键帧值不变
     *
     * 文本字段尺寸: 229×39.45, transformationPoint = (114.5, 19.65)
     * 文本中心 = Matrix(a) * center + tx  → 即 offsetXLUT / offsetYLUT
     */
    /** 文本字段中心点（SWF transformationPoint） */
    const TEXT_CENTER_X = 114.5;
    const TEXT_CENTER_Y = 19.65;
    // ====== scale LUT (14 帧) ======
    HitNumber.scaleLUT = [
        1.3176, 1.3176, 1.3176, 1.3176, // 0-3: static
        1.0687, // 4
        1.0687 + (1.0 - 1.0687) * (1 / 3), // 5
        1.0687 + (1.0 - 1.0687) * (2 / 3), // 6
        1.0, 1.0, // 7-8: static
        0.9291, // 9
        0.9056, // 10
        0.9056 + (0.3280 - 0.9056) * (1 / 3), // 11
        0.9056 + (0.3280 - 0.9056) * (2 / 3), // 12
        0.3280 // 13
    ];
    // ====== blur LUT (14 帧, GlowFilter 偏移半径) ======
    HitNumber.blurLUT = [
        4, 4, 4, 4, // 0-3
        3, 3, 3, 3, 3, // 4-8
        2, // 9
        2, // 10
        2 + (1 - 2) * (1 / 3), // 11
        2 + (1 - 2) * (2 / 3), // 12
        1 // 13
    ];
    // ====== tx LUT (Matrix tx, 14 帧) ======
    const txLUT = [
        -241.65, -241.65, -241.65, -241.65, // 0-3: static
        -196, // 4
        -196 + (-183.4 - (-196)) * (1 / 3), // 5: -191.8
        -196 + (-183.4 - (-196)) * (2 / 3), // 6: -187.6
        -183.4, -183.4, // 7-8: static
        -170.4, // 9
        -166.1, // 10
        -166.1 + (-88.7 - (-166.1)) * (1 / 3), // 11: -140.3
        -166.1 + (-88.7 - (-166.1)) * (2 / 3), // 12: -114.5
        -88.7 // 13
    ];
    // ====== ty LUT (Matrix ty, 14 帧) ======
    const tyLUT = [
        -136, -136, -136, -136, // 0-3: static
        -131.1, // 4
        -131.1 + (-129.75 - (-131.1)) * (1 / 3), // 5: -130.65
        -131.1 + (-129.75 - (-131.1)) * (2 / 3), // 6: -130.2
        -129.75, -129.75, // 7-8: static
        -135.85, // 9
        -137.9, // 10
        -137.9 + (-136.5 - (-137.9)) * (1 / 3), // 11: -137.43
        -137.9 + (-136.5 - (-137.9)) * (2 / 3), // 12: -136.97
        -136.5 // 13
    ];
    // ====== 预计算位置偏移 LUT ======
    // offsetX[f] = scaleLUT[f] * TEXT_CENTER_X + txLUT[f]
    // offsetY[f] = scaleLUT[f] * TEXT_CENTER_Y + tyLUT[f]
    // 这是 SWF 文本字段中心相对于 MC 原点的偏移（gameworld 坐标系）
    function buildOffsetLUT(centerCoord, scaleLut, translateLut) {
        const lut = [];
        for (let i = 0; i < 14; i++) {
            lut[i] = scaleLut[i] * centerCoord + translateLut[i];
        }
        return lut;
    }
    HitNumber.offsetXLUT = buildOffsetLUT(TEXT_CENTER_X, HitNumber.scaleLUT, txLUT);
    HitNumber.offsetYLUT = buildOffsetLUT(TEXT_CENTER_Y, HitNumber.scaleLUT, tyLUT);
    /**
     * Alpha：Flash SWF 中无显式 alpha 变化。
     * 保持全程 1.0，与 Flash 行为一致。
     * 缩小阶段（frame 10-13）的视觉消散完全靠 scale 实现。
     */
    function getAlpha(frame) {
        return 1.0;
    }
    HitNumber.getAlpha = getAlpha;
})(HitNumber || (HitNumber = {}));
/**
 * CommandDFA - 搓招 DFA 状态机 (镜像 AS2 CommandDFA.as 的 updateFast)
 *
 * V8 侧职责：DFA 状态转移 + 输入路径追踪。不做缓冲。
 * 超时语义与 AS2 原版一致：每帧 timer++，超过 timeout 回 ROOT。
 */
var GameInput;
(function (GameInput) {
    const ROOT_STATE = 0;
    const NO_COMMAND = 0;
    const DEFAULT_TIMEOUT = 8;
    class CommandDfa {
        constructor() {
            this._dfa = null;
            this._state = ROOT_STATE;
            this._timer = 0;
            this._commandId = NO_COMMAND;
            this._lastCommandId = NO_COMMAND;
            this._inputPath = [];
        }
        setDfa(dfa) {
            this._dfa = dfa;
            this.resetState();
        }
        resetState() {
            this._state = ROOT_STATE;
            this._timer = 0;
            this._commandId = NO_COMMAND;
            this._lastCommandId = NO_COMMAND;
            this._inputPath.length = 0;
        }
        getCommandId() { return this._commandId; }
        getLastCommandId() { return this._lastCommandId; }
        getState() { return this._state; }
        getInputPath() { return this._inputPath; }
        /**
         * 热路径：内联 DFA 状态转移 + 路径追踪
         * 与 AS2 原版语义一致：每帧 timer++，有效转移时 timer=0，超时回 ROOT。
         */
        updateFast(events, timeout = DEFAULT_TIMEOUT) {
            const dfa = this._dfa;
            if (dfa === null || !dfa.isLoaded()) {
                this._commandId = NO_COMMAND;
                return;
            }
            let state = this._state;
            let timer = this._timer;
            const path = this._inputPath;
            this._commandId = NO_COMMAND;
            timer++;
            const evCount = events.length;
            for (let i = 0; i < evCount; i++) {
                const ev = events[i];
                const nextState = dfa.transition(state, ev);
                if (nextState >= 0) {
                    state = nextState;
                    timer = 0;
                    path.push(ev);
                    const cmd = dfa.getAccept(state);
                    if (cmd > 0) {
                        this._commandId = cmd;
                        this._lastCommandId = cmd;
                    }
                }
            }
            if (timer > timeout) {
                state = ROOT_STATE;
                timer = 0;
                path.length = 0;
            }
            this._state = state;
            this._timer = timer;
        }
    }
    GameInput.CommandDfa = CommandDfa;
})(GameInput || (GameInput = {}));
/**
 * InputEvent - 输入事件常量 (镜像 AS2 InputEvent.as)
 *
 * 搓招系统使用的 18 种输入事件。方向归一化：前/后/上/下，不区分左右。
 */
var GameInput;
(function (GameInput) {
    // 无事件
    GameInput.EV_NONE = 0;
    // 方向事件（归一化：前=面向方向，后=背向方向）
    GameInput.EV_FORWARD = 1;
    GameInput.EV_BACK = 2;
    GameInput.EV_DOWN = 3;
    GameInput.EV_UP = 4;
    GameInput.EV_DOWN_FORWARD = 5;
    GameInput.EV_DOWN_BACK = 6;
    GameInput.EV_UP_FORWARD = 7;
    GameInput.EV_UP_BACK = 8;
    // 按键边沿事件（按下瞬间触发）
    GameInput.EV_A_PRESS = 9;
    GameInput.EV_B_PRESS = 10;
    GameInput.EV_C_PRESS = 11;
    // 复合事件
    GameInput.EV_DOUBLE_TAP_FORWARD = 12;
    GameInput.EV_DOUBLE_TAP_BACK = 13;
    GameInput.EV_SHIFT_HOLD = 14;
    GameInput.EV_SHIFT_FORWARD = 15;
    GameInput.EV_SHIFT_BACK = 16;
    GameInput.EV_SHIFT_DOWN = 17;
    // 字母表大小（DFA 数组分配用）
    GameInput.ALPHABET_SIZE = 18;
    // 事件名称（调试 + 可视化提示）
    const _names = [
        "NONE",
        "\u2192", // →  FORWARD
        "\u2190", // ←  BACK
        "\u2193", // ↓  DOWN
        "\u2191", // ↑  UP
        "\u2198", // ↘  DOWN_FORWARD
        "\u2199", // ↙  DOWN_BACK
        "\u2197", // ↗  UP_FORWARD
        "\u2196", // ↖  UP_BACK
        "A", // A_PRESS
        "B", // B_PRESS
        "C", // C_PRESS
        "\u2192\u2192", // →→ DOUBLE_TAP_FORWARD
        "\u2190\u2190", // ←← DOUBLE_TAP_BACK
        "Shift", // SHIFT_HOLD
        "Shift+\u2192", // Shift+→ SHIFT_FORWARD
        "Shift+\u2190", // Shift+← SHIFT_BACK
        "Shift+\u2193" // Shift+↓ SHIFT_DOWN
    ];
    function eventName(id) {
        return (id >= 0 && id < _names.length) ? _names[id] : "?";
    }
    GameInput.eventName = eventName;
    function sequenceToString(events) {
        let s = "";
        for (let i = 0; i < events.length; i++) {
            s += eventName(events[i]);
        }
        return s;
    }
    GameInput.sequenceToString = sequenceToString;
})(GameInput || (GameInput = {}));
/**
 * InputProcessor - 顶层编排 (GameInput namespace 入口)
 *
 * K payload 格式 v2:
 *   chr(cmdId+0x20) \x01 {typed} \x02 {hints}
 *
 *   - cmdId=0: 无命中, typed=已输入序列符号, hints=可达分支
 *   - cmdId>0: 命中, typed=完整触发序列, hints="" (命中时无分支)
 *
 *   typed: "↓↘" (已输入的事件符号序列)
 *   hints: "波动拳:↓↘A:1;诛杀步:→→:2" (name:fullSequence:remainSteps)
 *          fullSequence 包含 typed 部分 + 剩余部分
 */
var GameInput;
(function (GameInput) {
    const _modules = {};
    let _sampler = null;
    let _currentModuleId = -1;
    let _lastHintState = -1;
    let _lastHintStr = "";
    // 显示层防闪烁：hints 非空时缓存，回 ROOT 时延持几帧再清空
    let _displayHints = "";
    let _displayTyped = "";
    let _displayHoldTimer = 0;
    const DISPLAY_HOLD_FRAMES = 10; // hints 消失后保持 10 帧（~333ms）
    // 日志
    let _logBuf = [];
    function _log(msg) {
        _logBuf.push(msg);
    }
    function flushLog() {
        if (_logBuf.length === 0)
            return "";
        const result = _logBuf.join("\n");
        _logBuf = [];
        return result;
    }
    GameInput.flushLog = flushLog;
    function init() {
        _sampler = new GameInput.InputSampler();
        _currentModuleId = -1;
        _log("[GameInput] init OK");
    }
    GameInput.init = init;
    function loadModule(moduleId, dataJson) {
        const id = parseInt(moduleId, 10);
        if (isNaN(id)) {
            _log("[GameInput] loadModule: invalid moduleId: " + moduleId);
            return;
        }
        _log("[GameInput] loadModule: id=" + id + " jsonLen=" + dataJson.length);
        let data;
        try {
            data = JSON.parse(dataJson);
        }
        catch (e) {
            _log("[GameInput] loadModule: JSON parse error: " + e);
            return;
        }
        const trans = data.transitions;
        for (let i = 0; i < trans.length; i++) {
            if (trans[i] === null || trans[i] === undefined) {
                trans[i] = -1;
            }
        }
        const dfa = new GameInput.TrieDfa();
        dfa.load(data);
        const cmdDfa = new GameInput.CommandDfa();
        cmdDfa.setDfa(dfa);
        _modules[id] = { dfa, cmdDfa };
        _log("[GameInput] loadModule OK: id=" + id +
            " alpha=" + data.alphabetSize +
            " states=" + (data.accept ? data.accept.length : 0) +
            " names=" + (data.commandNames ? data.commandNames.length : 0));
    }
    GameInput.loadModule = loadModule;
    /**
     * 构建 hints 字符串：每个可达搓招的 name:fullSequence:remainSteps
     * fullSequence = typed 部分 + remaining 部分（完整路径，供 UI 渲染进度）
     */
    function buildHints(mod, state, typedStr) {
        if (state === 0)
            return "";
        const reachable = mod.dfa.getReachable(state);
        if (reachable.length === 0)
            return "";
        let buf = "";
        let count = 0;
        for (let i = 0; i < reachable.length; i++) {
            const h = reachable[i];
            // 完整序列 = 已输入 + 剩余
            const fullSeq = typedStr + h.remaining;
            if (count > 0)
                buf += ";";
            buf += h.name + ":" + fullSeq + ":" + h.steps;
            count++;
        }
        return buf;
    }
    function processFrame(mask, facingBit, moduleId, doubleTapDir) {
        if (_sampler === null)
            return String.fromCharCode(0x20);
        const mod = _modules[moduleId];
        if (!mod)
            return String.fromCharCode(0x20);
        // 模组切换时重置
        if (moduleId !== _currentModuleId) {
            mod.cmdDfa.resetState();
            _currentModuleId = moduleId;
            _lastHintState = -1;
        }
        // 1. InputSampler → events
        const facingRight = facingBit !== 0;
        const events = _sampler.sample(mask, facingRight, doubleTapDir);
        // 2. CommandDFA → cmdId (timeout 已内置 8 帧)
        mod.cmdDfa.updateFast(events);
        const cmdId = mod.cmdDfa.getCommandId();
        const state = mod.cmdDfa.getState();
        const inputPath = mod.cmdDfa.getInputPath();
        // typed: 已输入事件的符号序列
        const typedStr = GameInput.sequenceToString(inputPath);
        // 3. hints: 仅 state 变化时重算
        let rawHints;
        if (state !== _lastHintState) {
            _lastHintState = state;
            _lastHintStr = buildHints(mod, state, typedStr);
        }
        rawHints = _lastHintStr;
        // 4. 显示层防闪烁
        //    DFA 在"持续按住 → 超时回 ROOT → 再转移"时会导致 hints 在有/无之间振荡。
        //    解决：hints 非空时更新显示缓存；hints 变空后延持 DISPLAY_HOLD_FRAMES 帧再清。
        let outTyped;
        let outHints;
        if (rawHints.length > 0) {
            // 有新 hints → 更新显示缓存
            _displayHints = rawHints;
            _displayTyped = typedStr;
            _displayHoldTimer = DISPLAY_HOLD_FRAMES;
            outTyped = typedStr;
            outHints = rawHints;
        }
        else if (_displayHoldTimer > 0) {
            // hints 变空但延持中 → 继续输出缓存
            _displayHoldTimer--;
            outTyped = _displayTyped;
            outHints = _displayHints;
        }
        else {
            // 延持结束 → 真正清空
            _displayHints = "";
            _displayTyped = "";
            outTyped = "";
            outHints = "";
        }
        // 5. 格式化 K payload: chr(cmdId+0x20) \x01 typed \x02 hints
        if (cmdId === 0) {
            return String.fromCharCode(0x20) + "\x01" + outTyped + "\x02" + outHints;
        }
        // 命中
        const cmdName = mod.dfa.getCommandName(cmdId);
        _log("[GameInput] HIT cmdId=" + cmdId + " name=" + cmdName + " typed=" + typedStr);
        // 命中时清空显示缓存（由 AS2 N 前缀接管显示）
        _displayHoldTimer = 0;
        _displayHints = "";
        _displayTyped = "";
        return String.fromCharCode(cmdId + 0x20) + cmdName + "\x01" + typedStr + "\x02";
    }
    GameInput.processFrame = processFrame;
})(GameInput || (GameInput = {}));
/**
 * InputSampler - 输入采样器 (镜像 AS2 InputSampler.as)
 *
 * 职责：将 8-bit bitmask + 朝向 + doubleTapDir 转换为 InputEvent[] 列表。
 * 帧制语义：双击检测用帧计数器 + 帧间隔窗口（与 AS2 一致，不用 ms）。
 *
 * Bitmask bit 分配:
 *   0=左 1=右 2=上 3=下 4=A 5=B 6=C 7=Shift
 */
var GameInput;
(function (GameInput) {
    // Bitmask bit constants
    const BIT_LEFT = 1;
    const BIT_RIGHT = 2;
    const BIT_UP = 4;
    const BIT_DOWN = 8;
    const BIT_A = 16;
    const BIT_B = 32;
    const BIT_C = 64;
    const BIT_SHIFT = 128;
    class InputSampler {
        constructor() {
            // 上一帧状态（边沿检测）
            this._prevMask = 0;
            this._prevDoubleTapDir = 0;
            // 帧级双击检测状态
            this._frameCounter = 0;
            this._lastForwardFrame = -100;
            this._lastBackFrame = -100;
            this._doubleTapWindow = 12; // ~400ms @30fps
            // 上一帧归一化方向（用于帧级双击边沿）
            this._prevHoldForward = false;
            this._prevHoldBack = false;
            // 事件缓冲（复用）
            this._buf = [];
        }
        reset() {
            this._prevMask = 0;
            this._prevDoubleTapDir = 0;
            this._frameCounter = 0;
            this._lastForwardFrame = -100;
            this._lastBackFrame = -100;
            this._prevHoldForward = false;
            this._prevHoldBack = false;
        }
        /**
         * 采样本帧输入，返回事件列表
         *
         * @param mask 当前帧 8-bit bitmask（AS2 Key.isDown() 生成）
         * @param facingRight 角色面向右=true
         * @param doubleTapDir -1/0/1（KeyManager 写入的双击方向）
         * @returns InputEvent ID 数组
         */
        sample(mask, facingRight, doubleTapDir) {
            this._frameCounter++;
            const buf = this._buf;
            buf.length = 0;
            const prevMask = this._prevMask;
            // 解码 bitmask
            const left = (mask & BIT_LEFT) !== 0;
            const right = (mask & BIT_RIGHT) !== 0;
            const up = (mask & BIT_UP) !== 0;
            const down = (mask & BIT_DOWN) !== 0;
            const keyA = (mask & BIT_A) !== 0;
            const keyB = (mask & BIT_B) !== 0;
            const keyC = (mask & BIT_C) !== 0;
            const shift = (mask & BIT_SHIFT) !== 0;
            const prevA = (prevMask & BIT_A) !== 0;
            const prevB = (prevMask & BIT_B) !== 0;
            const prevC = (prevMask & BIT_C) !== 0;
            // 方向归一化
            const holdForward = facingRight ? right : left;
            const holdBack = facingRight ? left : right;
            // === 方向事件（复合优先）===
            if (down && holdForward) {
                buf.push(GameInput.EV_DOWN_FORWARD);
            }
            else if (down && holdBack) {
                buf.push(GameInput.EV_DOWN_BACK);
            }
            else if (up && holdForward) {
                buf.push(GameInput.EV_UP_FORWARD);
            }
            else if (up && holdBack) {
                buf.push(GameInput.EV_UP_BACK);
            }
            else {
                if (down)
                    buf.push(GameInput.EV_DOWN);
                if (up)
                    buf.push(GameInput.EV_UP);
                if (holdForward)
                    buf.push(GameInput.EV_FORWARD);
                if (holdBack)
                    buf.push(GameInput.EV_BACK);
            }
            // === 按键边沿检测（按下瞬间）===
            if (keyA && !prevA)
                buf.push(GameInput.EV_A_PRESS);
            if (keyB && !prevB)
                buf.push(GameInput.EV_B_PRESS);
            if (keyC && !prevC)
                buf.push(GameInput.EV_C_PRESS);
            // === Shift 组合事件 ===
            if (shift) {
                buf.push(GameInput.EV_SHIFT_HOLD);
                if (holdForward)
                    buf.push(GameInput.EV_SHIFT_FORWARD);
                if (holdBack)
                    buf.push(GameInput.EV_SHIFT_BACK);
                if (down)
                    buf.push(GameInput.EV_SHIFT_DOWN);
            }
            // === 双击检测通道1: doubleTapDir 边沿（KeyManager 毫秒级）===
            const prevDir = this._prevDoubleTapDir;
            if (doubleTapDir !== 0 && prevDir === 0) {
                if (facingRight) {
                    buf.push(doubleTapDir > 0 ? GameInput.EV_DOUBLE_TAP_FORWARD : GameInput.EV_DOUBLE_TAP_BACK);
                }
                else {
                    buf.push(doubleTapDir < 0 ? GameInput.EV_DOUBLE_TAP_FORWARD : GameInput.EV_DOUBLE_TAP_BACK);
                }
            }
            // === 双击检测通道2: 帧级 fallback（镜像 InputSampler.as:256-283）===
            const frame = this._frameCounter;
            // 前方向
            if (holdForward && !this._prevHoldForward) {
                if (frame - this._lastForwardFrame <= this._doubleTapWindow) {
                    buf.push(GameInput.EV_DOUBLE_TAP_FORWARD);
                    this._lastForwardFrame = -100;
                }
            }
            if (!holdForward && this._prevHoldForward) {
                this._lastForwardFrame = frame;
            }
            // 后方向
            if (holdBack && !this._prevHoldBack) {
                if (frame - this._lastBackFrame <= this._doubleTapWindow) {
                    buf.push(GameInput.EV_DOUBLE_TAP_BACK);
                    this._lastBackFrame = -100;
                }
            }
            if (!holdBack && this._prevHoldBack) {
                this._lastBackFrame = frame;
            }
            // === 更新 prev 状态 ===
            this._prevMask = mask;
            this._prevDoubleTapDir = doubleTapDir;
            this._prevHoldForward = holdForward;
            this._prevHoldBack = holdBack;
            return buf;
        }
    }
    GameInput.InputSampler = InputSampler;
})(GameInput || (GameInput = {}));
/**
 * TrieDFA - 扁平数组前缀树 DFA (镜像 AS2 TrieDFA.as 运行时部分)
 *
 * 不实现 insert/compile（由 AS2 编译后序列化传入），
 * 只实现运行时查询：transition, getAccept, getReachable(BFS)。
 */
var GameInput;
(function (GameInput) {
    class TrieDfa {
        constructor() {
            this._alpha = 0;
            this._trans = [];
            this._accept = [];
            this._depth = [];
            this._hint = [];
            this._patterns = [];
            this._names = [];
            this._stateCount = 0;
            this._loaded = false;
        }
        load(data) {
            this._alpha = data.alphabetSize;
            this._trans = data.transitions;
            this._accept = data.accept;
            this._depth = data.depth;
            this._hint = data.hint;
            this._patterns = data.patterns;
            this._names = data.commandNames;
            this._stateCount = this._accept.length;
            this._loaded = true;
        }
        isLoaded() {
            return this._loaded;
        }
        /**
         * O(1) 状态转移
         * @returns nextState, or -1 if no transition
         */
        transition(state, symbol) {
            const next = this._trans[state * this._alpha + symbol];
            return (next !== undefined && next >= 0) ? next : -1;
        }
        /**
         * 获取 accepting state 的 patternId (0 = non-accepting)
         */
        getAccept(state) {
            const a = this._accept[state];
            return (a !== undefined && a > 0) ? a : 0;
        }
        getDepth(state) {
            return this._depth[state] || 0;
        }
        getHint(state) {
            return this._hint[state] || 0;
        }
        getCommandName(patternId) {
            return this._names[patternId] || "";
        }
        getPattern(patternId) {
            return this._patterns[patternId] || null;
        }
        getAlphabetSize() {
            return this._alpha;
        }
        /**
         * BFS 从 currentState 出发，找所有可达的 accepting states
         * 返回搓招提示列表（Phase 4 可视化用）
         */
        getReachable(currentState) {
            if (!this._loaded || currentState < 0)
                return [];
            const alpha = this._alpha;
            const trans = this._trans;
            const accept = this._accept;
            const names = this._names;
            const patterns = this._patterns;
            // BFS: [state, path from currentState]
            const queue = [];
            const visited = new Set();
            const hints = [];
            visited.add(currentState);
            // Seed: all transitions from currentState
            for (let sym = 0; sym < alpha; sym++) {
                const next = trans[currentState * alpha + sym];
                if (next !== undefined && next >= 0 && !visited.has(next)) {
                    visited.add(next);
                    queue.push({ state: next, path: [sym] });
                }
            }
            let head = 0;
            while (head < queue.length) {
                const item = queue[head++];
                const st = item.state;
                const path = item.path;
                // Check if accepting
                const pid = accept[st];
                if (pid !== undefined && pid > 0) {
                    const name = names[pid] || "";
                    if (name.length > 0) {
                        hints.push({
                            name: name,
                            remaining: GameInput.sequenceToString(path),
                            steps: path.length
                        });
                    }
                }
                // Expand neighbors (limit depth to avoid explosion)
                if (path.length < 8) {
                    for (let sym = 0; sym < alpha; sym++) {
                        const next = trans[st * alpha + sym];
                        if (next !== undefined && next >= 0 && !visited.has(next)) {
                            visited.add(next);
                            const newPath = path.slice();
                            newPath.push(sym);
                            queue.push({ state: next, path: newPath });
                        }
                    }
                }
            }
            return hints;
        }
    }
    GameInput.TrieDfa = TrieDfa;
})(GameInput || (GameInput = {}));
