import type { BattleResult } from './types.js';

export interface PlaybackProjection {
  mode: 'watched' | 'skipped';
  winner: BattleResult['winner'];
  reason: BattleResult['reason'];
  pieceResults: BattleResult['pieceResults'];
  finalRngState: number;
}

function project(result: BattleResult, mode: PlaybackProjection['mode']): PlaybackProjection {
  return {
    mode,
    winner: result.winner,
    reason: result.reason,
    pieceResults: structuredClone(result.pieceResults),
    finalRngState: result.finalRngState,
  };
}

export function completePlayback(result: BattleResult): PlaybackProjection {
  // UI consumes the immutable resolver log; it never mutates campaign state.
  for (const _event of result.eventLog) {
    // Intentionally no rule execution here.
  }
  return project(result, 'watched');
}

export function skipPlayback(result: BattleResult): PlaybackProjection {
  return project(result, 'skipped');
}
