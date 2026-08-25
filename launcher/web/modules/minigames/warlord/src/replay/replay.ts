import { applyCommand } from '../core/engine.js';
import { createGame } from '../core/state.js';
import type { Difficulty, GameCommand, GameState, PresetId } from '../core/types.js';

export interface ReplayFile {
  schemaVersion: 1;
  rulesVersion: string;
  configDigest: string;
  gameSeed: string;
  difficulty: Difficulty;
  preset: PresetId;
  commands: GameCommand[];
  expected?: {
    strategicRound: number;
    phase: GameState['phase'];
    result: GameState['result'];
  };
}

export function makeReplay(state: GameState): ReplayFile {
  return {
    schemaVersion: 1,
    rulesVersion: state.rulesVersion,
    configDigest: state.configDigest,
    gameSeed: state.gameSeed,
    difficulty: state.difficulty,
    preset: state.preset,
    commands: state.commandHistory.map((record) => structuredClone(record.command)),
    expected: {
      strategicRound: state.strategicRound,
      phase: state.phase,
      result: structuredClone(state.result),
    },
  };
}

export function exportReplay(state: GameState): string {
  return JSON.stringify(makeReplay(state), null, 2);
}

export function parseReplay(json: string): ReplayFile {
  const parsed = JSON.parse(json) as Partial<ReplayFile>;
  if (parsed.schemaVersion !== 1) throw new Error('不支持的录像 schemaVersion。');
  if (typeof parsed.gameSeed !== 'string' || !Array.isArray(parsed.commands)) throw new Error('录像缺少种子或命令列表。');
  if (!parsed.rulesVersion || !parsed.configDigest || !parsed.difficulty || !parsed.preset) throw new Error('录像版本字段不完整。');
  return parsed as ReplayFile;
}

export function replayGame(replay: ReplayFile): GameState {
  let state = createGame({ seed: replay.gameSeed, difficulty: replay.difficulty, preset: replay.preset });
  if (state.rulesVersion !== replay.rulesVersion) throw new Error(`录像规则版本不匹配：${replay.rulesVersion} != ${state.rulesVersion}`);
  if (state.configDigest !== replay.configDigest) throw new Error('录像配置摘要不匹配。');
  for (const [index, command] of replay.commands.entries()) {
    const result = applyCommand(state, command);
    if (!result.ok) throw new Error(`录像命令 ${index + 1} 非法：${result.error}`);
    state = result.state;
  }
  return state;
}

export function importAndReplay(json: string): GameState {
  return replayGame(parseReplay(json));
}

export function deterministicStateView(state: GameState): unknown {
  const clone = structuredClone(state);
  return clone;
}
