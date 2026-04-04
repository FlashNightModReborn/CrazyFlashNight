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

    const _modules: { [id: number]: ModuleSlot } = {};
    let _sampler: InputSampler | null = null;
    let _currentModuleId: number = -1;
    let _lastHintState: number = -1;
    let _lastHintStr: string = "";

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
        _currentModuleId = -1;
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

    export function processFrame(
        mask: number,
        facingBit: number,
        moduleId: number,
        doubleTapDir: number
    ): string {
        if (_sampler === null) return String.fromCharCode(0x20);

        const mod = _modules[moduleId];
        if (!mod) return String.fromCharCode(0x20);

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
        const typedStr = sequenceToString(inputPath);

        // 3. hints: 仅 state 变化时重算
        let hints: string;
        if (state !== _lastHintState) {
            _lastHintState = state;
            _lastHintStr = buildHints(mod, state, typedStr);
        }
        hints = _lastHintStr;

        // 4. 格式化 K payload: chr(cmdId+0x20) \x01 typed \x02 hints
        if (cmdId === 0) {
            return String.fromCharCode(0x20) + "\x01" + typedStr + "\x02" + hints;
        }

        // 命中
        const cmdName = mod.dfa.getCommandName(cmdId);
        _log("[GameInput] HIT cmdId=" + cmdId + " name=" + cmdName + " typed=" + typedStr);

        // 命中时输出完整触发序列，不输出分支
        return String.fromCharCode(cmdId + 0x20) + cmdName + "\x01" + typedStr + "\x02";
    }
}
