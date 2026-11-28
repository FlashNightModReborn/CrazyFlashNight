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
namespace GameInput {

    interface ModuleSlot {
        dfa: TrieDfa;
        cmdDfa: CommandDfa;
    }

    interface FrameResult {
        cmdId: number;
        cmdName: string;
        typed: string;
        hints: string;
    }

    interface VersionedCursor {
        sessionId: string;
        connectionIncarnation: number;
        keyboardEpoch: number;
        inputFrameSeq: number;
        actorInc: number;
        moduleId: number;
        moduleInc: number;
        configInc: number;
        commandSeq: number;
    }

    const MAX_WIRE_INT = 2147483647;
    const MAX_FRAME_ATOMS = 64;
    // I1 actionBit -> historical \x04 mask bit.
    const atomMask: Record<string, number> = {
        "1": 16, "2": 32, "4": 64, "8": 4, "16": 8, "32": 1, "64": 2, "128": 128,
    };
    let _versioned: VersionedCursor | null = null;
    let _versionedContext = "";

    const _modules: { [id: number]: ModuleSlot } = {};
    let _sampler: InputSampler | null = null;
    let _currentModuleId: number = -1;
    let _lastHintState: number = -1;
    let _lastHintStr: string = "";

    // 显示层防闪烁：hints 非空时缓存，回 ROOT 时延持几帧再清空
    let _displayHints: string = "";
    let _displayTyped: string = "";
    let _displayHoldTimer: number = 0;
    const DISPLAY_HOLD_FRAMES = 10; // hints 消失后保持 10 帧（~333ms）

    // 日志
    let _logBuf: string[] = [];
    function _log(msg: string): void {
        _logBuf.push(msg);
    }

    export function flushLog(): string {
        if (_logBuf.length === 0) return "";
        const result = _logBuf.join("\n");
        _logBuf = [];
        return result;
    }

    export function init(): void {
        _sampler = new InputSampler();
        _versioned = null;
        _versionedContext = "";
        clearInputHistory();
        _log("[GameInput] init OK");
    }

    export function loadModule(moduleId: string, dataJson: string): void {
        const id = parseInt(moduleId, 10);
        if (isNaN(id)) {
            _log("[GameInput] loadModule: invalid moduleId: " + moduleId);
            return;
        }
        _log("[GameInput] loadModule: id=" + id + " jsonLen=" + dataJson.length);

        let data: DfaModuleData;
        try {
            data = JSON.parse(dataJson) as DfaModuleData;
        } catch (e) {
            _log("[GameInput] loadModule: JSON parse error: " + e);
            return;
        }

        const trans = data.transitions;
        for (let i = 0; i < trans.length; i++) {
            if (trans[i] === null || trans[i] === undefined) {
                trans[i] = -1;
            }
        }

        const dfa = new TrieDfa();
        dfa.load(data);
        const cmdDfa = new CommandDfa();
        cmdDfa.setDfa(dfa);
        _modules[id] = { dfa, cmdDfa };
        if (_versioned !== null && id === _currentModuleId) cancelInput();
        _log("[GameInput] loadModule OK: id=" + id +
             " alpha=" + data.alphabetSize +
             " states=" + (data.accept ? data.accept.length : 0) +
             " names=" + (data.commandNames ? data.commandNames.length : 0));
    }

    /**
     * 构建 hints 字符串：每个可达搓招的 name:fullSequence:remainSteps
     * fullSequence = typed 部分 + remaining 部分（完整路径，供 UI 渲染进度）
     */
    function buildHints(mod: ModuleSlot, state: number, typedStr: string): string {
        if (state === 0) return "";

        const reachable = mod.dfa.getReachable(state);
        if (reachable.length === 0) return "";

        let buf = "";
        let count = 0;
        for (let i = 0; i < reachable.length; i++) {
            const h = reachable[i];
            // 完整序列 = 已输入 + 剩余
            const fullSeq = typedStr + h.remaining;
            if (count > 0) buf += ";";
            buf += h.name + ":" + fullSeq + ":" + h.steps;
            count++;
        }
        return buf;
    }

    function clearDisplay(): void {
        _lastHintState = -1;
        _lastHintStr = "";
        _displayHints = "";
        _displayTyped = "";
        _displayHoldTimer = 0;
    }

    export function cancelInput(_reason?: string): void {
        clearInputHistory();
    }

    function clearInputHistory(mask: number = 0): void {
        if (_sampler !== null) _sampler.reset(mask);
        for (const id of Object.keys(_modules)) _modules[Number(id)].cmdDfa.resetState();
        _currentModuleId = -1;
        _versionedContext = "";
        clearDisplay();
    }

    function parseAtoms(wire: string, mask: number): InputAtom[] {
        if (wire === "-") return [];
        if (typeof wire !== "string" || wire.length > 4096) throw new RangeError("I1 atoms length");
        const fields = wire.split(";");
        if (fields.length > MAX_FRAME_ATOMS) throw new RangeError("I1 atom count");
        const atoms: InputAtom[] = [];
        let previousSeq = 0;
        let previousAction = 0;
        let touched = 0;
        let projected = 0;
        for (const field of fields) {
            const match = /^([1-9][0-9]{0,9}),(1|2|4|8|16|32|64|128),([DU])$/.exec(field);
            if (match === null || match[0] !== field) throw new RangeError("I1 atom syntax");
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
        if ((mask & touched) !== projected) throw new RangeError("I1 atom mask");
        return atoms;
    }

    function wireHints(hints: string): string {
        const rows = hints === "" ? [] : hints.split(";").map(row => {
            const end = row.lastIndexOf(":");
            const start = row.lastIndexOf(":", end - 1);
            return { name: row.slice(0, start), sequence: row.slice(start + 1, end), steps: Number(row.slice(end + 1)) };
        });
        return JSON.stringify(rows).replace(/[|\u007f-\uffff]/g,
            ch => "\\u" + ch.charCodeAt(0).toString(16).padStart(4, "0"));
    }

    export function processFrame(mask: number, facingBit: number, moduleId: number,
                                 doubleTapDir: number): string {
        const result = advanceFrame(mask, facingBit, moduleId, doubleTapDir);
        if (!result) return String.fromCharCode(0x20);
        return String.fromCharCode(result.cmdId + 0x20) + result.cmdName +
            "\x01" + result.typed + "\x02" + result.hints;
    }

    export function processVersionedFrame(
        mask: number, facingBit: number, moduleId: number, doubleTapDir: number,
        atomsWire: string, sessionId: string, connectionIncarnation: number,
        keyboardEpoch: number, inputFrameSeq: number, actorInc: number, moduleInc: number, configInc: number
    ): string {
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
                (moduleInc === previous.moduleInc && moduleId !== previous.moduleId)))) return "";

        let atoms: InputAtom[];
        try {
            atoms = parseAtoms(atomsWire, mask);
        } catch (error) {
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
        if (!result) return "";
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

    function advanceFrame(mask: number, facingBit: number, moduleId: number,
                          doubleTapDir: number, atoms?: readonly InputAtom[]): FrameResult | null {
        if (_sampler === null) return null;

        const mod = _modules[moduleId];
        if (!mod) return null;

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
        const typedStr = sequenceToString(inputPath);

        // 3. hints: 仅 state 变化时重算
        let rawHints: string;
        if (state !== _lastHintState) {
            _lastHintState = state;
            _lastHintStr = buildHints(mod, state, typedStr);
        }
        rawHints = _lastHintStr;

        // 4. 显示层防闪烁
        //    DFA 在"持续按住 → 超时回 ROOT → 再转移"时会导致 hints 在有/无之间振荡。
        //    解决：hints 非空时更新显示缓存；hints 变空后延持 DISPLAY_HOLD_FRAMES 帧再清。
        let outTyped: string;
        let outHints: string;

        if (rawHints.length > 0) {
            // 有新 hints → 更新显示缓存
            _displayHints = rawHints;
            _displayTyped = typedStr;
            _displayHoldTimer = DISPLAY_HOLD_FRAMES;
            outTyped = typedStr;
            outHints = rawHints;
        } else if (_displayHoldTimer > 0) {
            // hints 变空但延持中 → 继续输出缓存
            _displayHoldTimer--;
            outTyped = _displayTyped;
            outHints = _displayHints;
        } else {
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
}
