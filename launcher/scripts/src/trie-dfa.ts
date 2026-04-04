/**
 * TrieDFA - 扁平数组前缀树 DFA (镜像 AS2 TrieDFA.as 运行时部分)
 *
 * 不实现 insert/compile（由 AS2 编译后序列化传入），
 * 只实现运行时查询：transition, getAccept, getReachable(BFS)。
 */
namespace GameInput {

    export interface DfaModuleData {
        alphabetSize: number;
        transitions: number[];   // flat: state * alphabetSize + symbol -> nextState (-1 = no transition)
        accept: number[];        // state -> patternId (0 = non-accepting)
        depth: number[];         // state -> steps from root
        hint: number[];          // state -> hinted patternId
        patterns: number[][];    // patternId -> original event sequence
        commandNames: string[];  // patternId -> command name ("", "波动拳", ...)
    }

    export interface ComboHint {
        name: string;
        remaining: string;
        steps: number;
    }

    export class TrieDfa {
        private _alpha: number = 0;
        private _trans: number[] = [];
        private _accept: number[] = [];
        private _depth: number[] = [];
        private _hint: number[] = [];
        private _patterns: number[][] = [];
        private _names: string[] = [];
        private _stateCount: number = 0;
        private _loaded: boolean = false;

        load(data: DfaModuleData): void {
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

        isLoaded(): boolean {
            return this._loaded;
        }

        /**
         * O(1) 状态转移
         * @returns nextState, or -1 if no transition
         */
        transition(state: number, symbol: number): number {
            const next = this._trans[state * this._alpha + symbol];
            return (next !== undefined && next >= 0) ? next : -1;
        }

        /**
         * 获取 accepting state 的 patternId (0 = non-accepting)
         */
        getAccept(state: number): number {
            const a = this._accept[state];
            return (a !== undefined && a > 0) ? a : 0;
        }

        getDepth(state: number): number {
            return this._depth[state] || 0;
        }

        getHint(state: number): number {
            return this._hint[state] || 0;
        }

        getCommandName(patternId: number): string {
            return this._names[patternId] || "";
        }

        getPattern(patternId: number): number[] | null {
            return this._patterns[patternId] || null;
        }

        getAlphabetSize(): number {
            return this._alpha;
        }

        /**
         * BFS 从 currentState 出发，找所有可达的 accepting states
         * 返回搓招提示列表（Phase 4 可视化用）
         */
        getReachable(currentState: number): ComboHint[] {
            if (!this._loaded || currentState < 0) return [];

            const alpha = this._alpha;
            const trans = this._trans;
            const accept = this._accept;
            const names = this._names;
            const patterns = this._patterns;

            // BFS: [state, path from currentState]
            const queue: Array<{ state: number; path: number[] }> = [];
            const visited = new Set<number>();
            const hints: ComboHint[] = [];

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
                            remaining: sequenceToString(path),
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
}
