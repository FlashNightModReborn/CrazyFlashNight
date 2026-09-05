import { applyCommand } from '../core/engine.js';
import type { GameState, MoveOrAttackCommand } from '../core/types.js';

export type DefinitiveAs2BattleFailureRecovery =
  | { outcome: 'player_retry'; state: GameState }
  | { outcome: 'ai_action_ended'; state: GameState }
  | { outcome: 'blocked'; state: GameState };

/**
 * Recover only from a definitive "battle did not start" result.
 * Unknown outcomes must remain fail-closed in the session authority path.
 */
export function recoverDefinitiveAs2BattleFailure(
  state: GameState,
  command: MoveOrAttackCommand,
): DefinitiveAs2BattleFailureRecovery {
  const faction = state.factions[command.factionId];
  if (!faction) return { outcome: 'blocked', state };

  if (faction.controller === 'player') {
    return { outcome: 'player_retry', state };
  }

  const actionPhase = state.phase === 'FIRST_FACTION_ACTION'
    || state.phase === 'SECOND_FACTION_ACTION';
  if (!actionPhase || state.activeFactionId !== command.factionId) {
    return { outcome: 'blocked', state };
  }

  const ended = applyCommand(state, {
    type: 'END_ACTION',
    factionId: command.factionId,
  });
  return ended.ok
    ? { outcome: 'ai_action_ended', state: ended.state }
    : { outcome: 'blocked', state };
}
