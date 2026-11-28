"use strict";
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
         * 一个调用消费整个归一化事件桶：timer 只推进一次，有效转移时 timer=0。
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
    GameInput.EV_SHIFT_UP_FORWARD = 18;
    // 字母表大小（DFA 数组分配用）
    GameInput.ALPHABET_SIZE = 19;
    // 事件名称（调试 + 可视化提示）
    const _names = [
        "NONE",
        "→", // FORWARD
        "←", // BACK
        "↓", // DOWN
        "↑", // UP
        "↘", // DOWN_FORWARD
        "↙", // DOWN_BACK
        "↗", // UP_FORWARD
        "↖", // UP_BACK
        "A", // A_PRESS
        "B", // B_PRESS
        "C", // C_PRESS
        "→→", // DOUBLE_TAP_FORWARD
        "←←", // DOUBLE_TAP_BACK
        "Shift", // SHIFT_HOLD
        "Shift+→", // SHIFT_FORWARD
        "Shift+←", // SHIFT_BACK
        "Shift+↓", // SHIFT_DOWN
        "Shift+↑→" // SHIFT_UP_FORWARD
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
    const MAX_WIRE_INT = 2147483647;
    const MAX_FRAME_ATOMS = 64;
    // I1 actionBit -> historical \x04 mask bit.
    const atomMask = {
        "1": 16, "2": 32, "4": 64, "8": 4, "16": 8, "32": 1, "64": 2, "128": 128,
    };
    let _versioned = null;
    let _versionedContext = "";
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
        _versioned = null;
        _versionedContext = "";
        clearInputHistory();
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
        if (_versioned !== null && id === _currentModuleId)
            cancelInput();
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
    function clearDisplay() {
        _lastHintState = -1;
        _lastHintStr = "";
        _displayHints = "";
        _displayTyped = "";
        _displayHoldTimer = 0;
    }
    function cancelInput(_reason) {
        clearInputHistory();
    }
    GameInput.cancelInput = cancelInput;
    function clearInputHistory(mask = 0) {
        if (_sampler !== null)
            _sampler.reset(mask);
        for (const id of Object.keys(_modules))
            _modules[Number(id)].cmdDfa.resetState();
        _currentModuleId = -1;
        _versionedContext = "";
        clearDisplay();
    }
    function parseAtoms(wire, mask) {
        if (wire === "-")
            return [];
        if (typeof wire !== "string" || wire.length > 4096)
            throw new RangeError("I1 atoms length");
        const fields = wire.split(";");
        if (fields.length > MAX_FRAME_ATOMS)
            throw new RangeError("I1 atom count");
        const atoms = [];
        let previousSeq = 0;
        let previousAction = 0;
        let touched = 0;
        let projected = 0;
        for (const field of fields) {
            const match = /^([1-9][0-9]{0,9}),(1|2|4|8|16|32|64|128),([DU])$/.exec(field);
            if (match === null || match[0] !== field)
                throw new RangeError("I1 atom syntax");
            const seq = Number(match[1]);
            const action = Number(match[2]);
            const bit = atomMask[match[2]];
            const down = match[3] === "D";
            // One raw VK edge may fan out to different actions with the same seq.
            if (seq > MAX_WIRE_INT || seq < previousSeq ||
                (seq === previousSeq && action <= previousAction)) {
                throw new RangeError("I1 atom order");
            }
            if ((touched & bit) !== 0 && ((projected & bit) !== 0) === down) {
                throw new RangeError("I1 atom transition");
            }
            touched |= bit;
            projected = down ? projected | bit : projected & ~bit;
            atoms.push({ bit, down });
            previousSeq = seq;
            previousAction = action;
        }
        if ((mask & touched) !== projected)
            throw new RangeError("I1 atom mask");
        return atoms;
    }
    function wireHints(hints) {
        const rows = hints === "" ? [] : hints.split(";").map(row => {
            const end = row.lastIndexOf(":");
            const start = row.lastIndexOf(":", end - 1);
            return { name: row.slice(0, start), sequence: row.slice(start + 1, end), steps: Number(row.slice(end + 1)) };
        });
        return JSON.stringify(rows).replace(/[|\u007f-\uffff]/g, ch => "\\u" + ch.charCodeAt(0).toString(16).padStart(4, "0"));
    }
    function processFrame(mask, facingBit, moduleId, doubleTapDir) {
        const result = advanceFrame(mask, facingBit, moduleId, doubleTapDir);
        if (!result)
            return String.fromCharCode(0x20);
        return String.fromCharCode(result.cmdId + 0x20) + result.cmdName +
            "\x01" + result.typed + "\x02" + result.hints;
    }
    GameInput.processFrame = processFrame;
    function processVersionedFrame(mask, facingBit, moduleId, doubleTapDir, atomsWire, sessionId, connectionIncarnation, keyboardEpoch, inputFrameSeq, actorInc, moduleInc, configInc) {
        if (typeof sessionId !== "string" || sessionId.length !== 32 || !/^[0-9a-f]{32}$/.test(sessionId) ||
            ![connectionIncarnation, keyboardEpoch, inputFrameSeq, actorInc, moduleInc, configInc]
                .every(id => Number.isInteger(id) && id > 0 && id <= MAX_WIRE_INT) ||
            !Number.isInteger(mask) || mask < 0 || mask > 255 || (facingBit !== 0 && facingBit !== 1) ||
            !Number.isInteger(moduleId) || moduleId < 0 || moduleId > 2 ||
            (doubleTapDir !== -1 && doubleTapDir !== 0 && doubleTapDir !== 1)) {
            cancelInput();
            throw new RangeError("I1 frame identity or levels");
        }
        const previous = _versioned;
        const sameSession = previous !== null && previous.sessionId === sessionId;
        const sameConnection = sameSession && previous.connectionIncarnation === connectionIncarnation;
        const sameEpoch = sameConnection && previous.keyboardEpoch === keyboardEpoch;
        if ((sameSession && connectionIncarnation < previous.connectionIncarnation) ||
            (sameConnection && keyboardEpoch < previous.keyboardEpoch) ||
            (sameEpoch && (inputFrameSeq <= previous.inputFrameSeq || actorInc < previous.actorInc ||
                moduleInc < previous.moduleInc || configInc < previous.configInc ||
                (moduleInc === previous.moduleInc && moduleId !== previous.moduleId))))
            return "";
        let atoms;
        try {
            atoms = parseAtoms(atomsWire, mask);
        }
        catch (error) {
            cancelInput();
            throw error;
        }
        const context = actorInc + "|" + moduleId + "|" + moduleInc + "|" + configInc;
        if (!sameEpoch || context !== _versionedContext) {
            // Within an existing grant a new scope inherits levels, while only
            // explicitly observed presses can start an action on the boundary.
            clearInputHistory(sameEpoch ? mask : 0);
            _versionedContext = context;
        }
        const cursor = {
            sessionId, connectionIncarnation, keyboardEpoch, inputFrameSeq, actorInc, moduleId, moduleInc, configInc,
            commandSeq: sameEpoch ? previous.commandSeq : 0,
        };
        _versioned = cursor;
        const result = advanceFrame(mask, facingBit, moduleId, doubleTapDir, atoms);
        if (!result)
            return "";
        let commandSeq = 0;
        if (result.cmdId > 0) {
            if (cursor.commandSeq === MAX_WIRE_INT) {
                cancelInput();
                throw new RangeError("I1 command sequence exhausted");
            }
            commandSeq = ++cursor.commandSeq;
        }
        return JSON.stringify({ commandSeq, ...result, hintsJson: wireHints(result.hints) });
    }
    GameInput.processVersionedFrame = processVersionedFrame;
    function advanceFrame(mask, facingBit, moduleId, doubleTapDir, atoms) {
        if (_sampler === null)
            return null;
        const mod = _modules[moduleId];
        if (!mod)
            return null;
        // 模组切换时重置 DFA + 显示缓存
        if (moduleId !== _currentModuleId) {
            mod.cmdDfa.resetState();
            _currentModuleId = moduleId;
            clearDisplay();
        }
        // 1. InputSampler → events
        const facingRight = facingBit !== 0;
        const events = _sampler.sample(mask, facingRight, doubleTapDir, atoms);
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
            return { cmdId, cmdName: "", typed: outTyped, hints: outHints };
        }
        // 命中
        const cmdName = mod.dfa.getCommandName(cmdId);
        // HIT 日志已由 WebView2 combo overlay 接管，不再写文件日志
        // 命中时清空显示缓存（由 AS2 N 前缀接管显示）
        _displayHoldTimer = 0;
        _displayHints = "";
        _displayTyped = "";
        return { cmdId, cmdName, typed: typedStr, hints: "" };
    }
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
        reset(mask = 0) {
            this._prevMask = mask;
            this._buf.length = 0;
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
        sample(mask, facingRight, doubleTapDir, atoms) {
            this._frameCounter++;
            const buf = this._buf;
            buf.length = 0;
            const prevMask = this._prevMask;
            if (atoms && atoms.length > 0) {
                this.appendVersionedEvents(buf, mask, prevMask, facingRight, atoms);
            }
            else {
                this.appendDirections(buf, mask, facingRight);
                this.appendActionPresses(buf, mask & ~prevMask);
                this.appendShift(buf, mask, facingRight);
            }
            // === 双击检测通道1: doubleTapDir 边沿（KeyManager 逻辑帧）===
            const prevDir = this._prevDoubleTapDir;
            if (doubleTapDir !== 0 && prevDir === 0) {
                if (facingRight) {
                    buf.push(doubleTapDir > 0 ? GameInput.EV_DOUBLE_TAP_FORWARD : GameInput.EV_DOUBLE_TAP_BACK);
                }
                else {
                    buf.push(doubleTapDir < 0 ? GameInput.EV_DOUBLE_TAP_FORWARD : GameInput.EV_DOUBLE_TAP_BACK);
                }
            }
            // Fallback consumes horizontal changes at the same logical-frame timestamp.
            if (atoms && atoms.length > 0)
                this.replayFallback(buf, mask, facingRight, atoms);
            else
                this.appendFallback(buf, mask, facingRight);
            this._prevMask = mask;
            this._prevDoubleTapDir = doubleTapDir;
            return buf;
        }
        replayFallback(buf, mask, facingRight, atoms) {
            const horizontal = BIT_LEFT | BIT_RIGHT;
            let touched = 0;
            let levels = mask;
            for (const atom of atoms) {
                if (!(atom.bit & horizontal) || (touched & atom.bit))
                    continue;
                touched |= atom.bit;
                levels = atom.down ? levels & ~atom.bit : levels | atom.bit;
            }
            this.appendFallback(buf, levels, facingRight);
            if (touched === 0)
                return;
            for (const atom of atoms) {
                if (!(atom.bit & horizontal))
                    continue;
                levels = atom.down ? levels | atom.bit : levels & ~atom.bit;
                this.appendFallback(buf, levels, facingRight);
            }
        }
        appendFallback(buf, mask, facingRight) {
            const holdForward = (mask & (facingRight ? BIT_RIGHT : BIT_LEFT)) !== 0;
            const holdBack = (mask & (facingRight ? BIT_LEFT : BIT_RIGHT)) !== 0;
            const frame = this._frameCounter;
            if (holdForward && !this._prevHoldForward) {
                if (frame - this._lastForwardFrame <= this._doubleTapWindow) {
                    buf.push(GameInput.EV_DOUBLE_TAP_FORWARD);
                    this._lastForwardFrame = -100;
                }
            }
            if (!holdForward && this._prevHoldForward)
                this._lastForwardFrame = frame;
            if (holdBack && !this._prevHoldBack) {
                if (frame - this._lastBackFrame <= this._doubleTapWindow) {
                    buf.push(GameInput.EV_DOUBLE_TAP_BACK);
                    this._lastBackFrame = -100;
                }
            }
            if (!holdBack && this._prevHoldBack)
                this._lastBackFrame = frame;
            this._prevHoldForward = holdForward;
            this._prevHoldBack = holdBack;
        }
        appendVersionedEvents(buf, mask, prevMask, facingRight, atoms) {
            let touched = 0;
            let pressed = 0;
            let initialDown = 0;
            let hasPulse = false;
            for (const atom of atoms) {
                if (touched & atom.bit) {
                    hasPulse = true;
                }
                else if (!atom.down) {
                    initialDown |= atom.bit;
                }
                touched |= atom.bit;
                if (atom.down)
                    pressed |= atom.bit;
            }
            // For ordinary snapshots keep the original direction, A/B/C, Shift order.
            // Bits represented by atoms never also contribute a rising mask edge.
            const inferredPresses = mask & ~prevMask & ~touched;
            if (!hasPulse) {
                this.appendDirections(buf, mask, facingRight);
                this.appendActionPresses(buf, pressed | inferredPresses);
                this.appendShift(buf, mask, facingRight);
                return;
            }
            // Reconstruct the intra-frame bucket only where the wire supplies edges.
            // Untouched bits use their final levels, and can contribute at most once.
            const directions = BIT_LEFT | BIT_RIGHT | BIT_UP | BIT_DOWN;
            const shiftContext = directions | BIT_SHIFT;
            let levels = (mask & ~touched) | initialDown;
            let lastDirection = -1;
            let lastShiftContext = -1;
            if ((touched & directions) === 0) {
                this.appendDirections(buf, levels, facingRight);
                lastDirection = levels & directions;
            }
            for (const atom of atoms) {
                if (!atom.down) {
                    levels &= ~atom.bit;
                    if (atom.bit & directions)
                        lastDirection = -1;
                    if (atom.bit & shiftContext)
                        lastShiftContext = -1;
                    continue;
                }
                levels |= atom.bit;
                if (atom.bit & directions) {
                    this.appendDirections(buf, levels, facingRight);
                    lastDirection = levels & directions;
                }
                this.appendActionPresses(buf, atom.bit);
                if ((levels & BIT_SHIFT) && (atom.bit & shiftContext)) {
                    this.appendShift(buf, levels, facingRight);
                    lastShiftContext = levels & shiftContext;
                }
            }
            if ((mask & directions) !== lastDirection)
                this.appendDirections(buf, mask, facingRight);
            this.appendActionPresses(buf, inferredPresses);
            if ((mask & shiftContext) !== lastShiftContext)
                this.appendShift(buf, mask, facingRight);
        }
        appendDirections(buf, mask, facingRight) {
            const holdForward = (mask & (facingRight ? BIT_RIGHT : BIT_LEFT)) !== 0;
            const holdBack = (mask & (facingRight ? BIT_LEFT : BIT_RIGHT)) !== 0;
            const down = (mask & BIT_DOWN) !== 0;
            const up = (mask & BIT_UP) !== 0;
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
        }
        appendActionPresses(buf, presses) {
            if (presses & BIT_A)
                buf.push(GameInput.EV_A_PRESS);
            if (presses & BIT_B)
                buf.push(GameInput.EV_B_PRESS);
            if (presses & BIT_C)
                buf.push(GameInput.EV_C_PRESS);
        }
        appendShift(buf, mask, facingRight) {
            if (!(mask & BIT_SHIFT))
                return;
            const holdForward = (mask & (facingRight ? BIT_RIGHT : BIT_LEFT)) !== 0;
            const holdBack = (mask & (facingRight ? BIT_LEFT : BIT_RIGHT)) !== 0;
            buf.push(GameInput.EV_SHIFT_HOLD);
            if (holdForward)
                buf.push(GameInput.EV_SHIFT_FORWARD);
            if (holdBack)
                buf.push(GameInput.EV_SHIFT_BACK);
            if (mask & BIT_DOWN)
                buf.push(GameInput.EV_SHIFT_DOWN);
            if ((mask & BIT_UP) && holdForward)
                buf.push(GameInput.EV_SHIFT_UP_FORWARD);
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
