/**
 * CommandDFA - 搓招 DFA 状态机 (镜像 AS2 CommandDFA.as 的 updateFast)
 *
 * V8 侧职责：DFA 状态转移 + 输入路径追踪。不做缓冲。
 * 超时语义与 AS2 原版一致：每帧 timer++，超过 timeout 回 ROOT。
 */
namespace GameInput {

    const ROOT_STATE = 0;
    const NO_COMMAND = 0;
    const DEFAULT_TIMEOUT = 8;

    export class CommandDfa {
        private _dfa: TrieDfa | null = null;

        private _state: number = ROOT_STATE;
        private _timer: number = 0;
        private _commandId: number = NO_COMMAND;
        private _lastCommandId: number = NO_COMMAND;
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
         * 与 AS2 原版语义一致：每帧 timer++，有效转移时 timer=0，超时回 ROOT。
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
}
