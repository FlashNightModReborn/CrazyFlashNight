/**
 * CommandDFA - 搓招 DFA 状态机 (镜像 AS2 CommandDFA.as 的 updateFast)
 *
 * V8 侧职责：DFA 状态转移 + 输入路径追踪。不做缓冲。
 */
namespace GameInput {

    const ROOT_STATE = 0;
    const NO_COMMAND = 0;
    const DEFAULT_TIMEOUT = 8; // 放宽到 8 帧 (~267ms @30fps)，对搓招新手更友好

    export class CommandDfa {
        private _dfa: TrieDfa | null = null;

        // DFA 状态
        private _state: number = ROOT_STATE;
        private _timer: number = 0;
        private _commandId: number = NO_COMMAND;
        private _lastCommandId: number = NO_COMMAND;

        // 输入路径追踪：从 ROOT 到当前 state 的有效转移事件序列
        private _inputPath: number[] = [];

        setDfa(dfa: TrieDfa): void {
            this._dfa = dfa;
            this.resetState();
        }

        resetState(): void {
            this._state = ROOT_STATE;
            this._timer = 0;
            this._commandId = NO_COMMAND;
            this._lastCommandId = NO_COMMAND;
            this._inputPath.length = 0;
        }

        getCommandId(): number { return this._commandId; }
        getLastCommandId(): number { return this._lastCommandId; }
        getState(): number { return this._state; }
        getInputPath(): number[] { return this._inputPath; }

        /**
         * 热路径：内联 DFA 状态转移 + 路径追踪
         */
        updateFast(events: number[], timeout: number = DEFAULT_TIMEOUT): void {
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
                    path.push(ev); // 追踪有效转移
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
                path.length = 0; // 超时重置路径
            }

            this._state = state;
            this._timer = timer;
        }
    }
}
