import type { GameEvent, GameState } from './types.js';

export function addGameEvent(
  state: GameState,
  event: Omit<GameEvent, 'eventId' | 'strategicRound' | 'commandSequence'>,
): GameEvent {
  state.nextEventOrdinal += 1;
  const full: GameEvent = {
    ...event,
    eventId: `g${state.nextEventOrdinal}`,
    strategicRound: state.strategicRound,
    commandSequence: state.commandSequence,
  };
  state.eventLog.push(full);
  return full;
}
