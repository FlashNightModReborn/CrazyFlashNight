/**
 * CommandDFA - 搓招 DFA 状态机 (镜像 AS2 CommandDFA.as 的 updateFast)
 *
 * V8 侧职责：DFA 状态转移 + 输入路径追踪。不做缓冲。
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

        // 上帧事件指纹（用于去重持续按住不变的输入）
        private _prevEventKey: string = "";

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
            this._prevEventKey = "";
        }

        getCommandId(): number { return this._commandId; }
        getLastCommandId(): number { return this._lastCommandId; }
        getState(): number { return this._state; }
        getInputPath(): number[] { return this._inputPath; }

        /**
         * 热路径：内联 DFA 状态转移 + 路径追踪
         *
         * 去重逻辑：如果本帧事件和上帧完全相同，且 DFA 不在 ROOT，
         * 则只维持 timer（不重新转移），避免"持续按住 → 超时 → 回 ROOT → 再转移"的闪烁循环。
         */
        updateFast(events: number[], timeout: number = DEFAULT_TIMEOUT): void {
            const dfa = this._dfa;
            if (dfa === null || !dfa.isLoaded()) {
                this._commandId = NO_COMMAND;
                return;
            }

            // 计算本帧事件指纹
            let eventKey = "";
            for (let k = 0; k < events.length; k++) {
                if (k > 0) eventKey += ",";
                eventKey += events[k];
            }

            let state = this._state;
            let timer = this._timer;
            const path = this._inputPath;

            this._commandId = NO_COMMAND;

            // 去重：事件不变 + 不在 ROOT → 只维持 timer，不推进 DFA
            if (eventKey === this._prevEventKey && state !== ROOT_STATE && eventKey.length > 0) {
                // 持续按住同样的键，保持当前状态，timer 不增加（防止超时回 ROOT）
                this._prevEventKey = eventKey;
                this._state = state;
                this._timer = timer;
                return;
            }

            this._prevEventKey = eventKey;
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
