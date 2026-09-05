import { addGameEvent } from './events.js';
import { clearUnspentFieldActionPointsInPlace, requireFaction } from './factions.js';
import { createPieceInPlace } from './pieces.js';
import { requireNode } from './access.js';
import type { CommanderState, FactionId, GameState, NodeId } from './types.js';

export function commanderForPiece(state: GameState, pieceInstanceId: string): CommanderState | null {
  return Object.values(state.commanders).find((commander) => commander.pieceInstanceId === pieceInstanceId) ?? null;
}

export function fieldCommanderAp(state: GameState, factionId: FactionId): number {
  return Object.values(state.commanders)
    .filter((commander) => (
      commander.factionId === factionId
      && commander.status === 'fielded'
      && commander.readyFromRound <= state.strategicRound
    ))
    .reduce((sum, commander) => sum + commander.apContribution, 0);
}

export function handleCommanderCasualtyInPlace(state: GameState, pieceInstanceId: string): void {
  const commander = commanderForPiece(state, pieceInstanceId);
  if (!commander) return;
  commander.pieceInstanceId = null;
  commander.nodeId = null;
  commander.status = commander.role === 'player_avatar' ? 'downed' : 'available';
  clearUnspentFieldActionPointsInPlace(requireFaction(state, commander.factionId));
  addGameEvent(state, {
    type: 'commander_downed',
    factionId: commander.factionId,
    pieceId: pieceInstanceId,
    message: commander.role === 'player_avatar'
      ? '玩家指挥官已经倒地；结算时将撤往后方。'
      : `${requireFaction(state, commander.factionId).displayName}的指挥官已经阵亡，可在指挥所重新生产。`,
    data: { commanderId: commander.commanderId, characterId: commander.characterId },
  });
}

export function evacuateDownedPlayerAvatarsInPlace(state: GameState): void {
  for (const commander of Object.values(state.commanders)) {
    if (commander.role !== 'player_avatar' || commander.status !== 'downed') continue;
    commander.status = 'rear';
    commander.readyFromRound = state.strategicRound + 1;
    addGameEvent(state, {
      type: 'commander_evacuated',
      factionId: commander.factionId,
      message: '玩家指挥官已撤往后方；可从己方安全指挥所重新部署。',
      data: { commanderId: commander.commanderId },
    });
  }
}

export function enqueueCommanderProductionInPlace(state: GameState, commanderId: string): void {
  const commander = state.commanders[commanderId];
  if (!commander || commander.role !== 'boss_unique' || commander.status !== 'available') {
    throw new Error(`Commander ${commanderId} is not available for production.`);
  }
  const faction = requireFaction(state, commander.factionId);
  faction.gold -= commander.productionGoldCost;
  commander.status = 'queued';
  commander.remainingProductionRounds = commander.productionRounds;
  addGameEvent(state, {
    type: 'commander_production_enqueued',
    factionId: commander.factionId,
    nodeId: faction.commandPostNodeId,
    amount: commander.productionGoldCost,
    message: `${faction.displayName}开始重建指挥官部队。`,
    data: { commanderId, characterId: commander.characterId },
  });
}

export function progressCommanderProductionInPlace(state: GameState): void {
  for (const commander of Object.values(state.commanders)) {
    if (commander.status !== 'queued') continue;
    const faction = requireFaction(state, commander.factionId);
    if (faction.defeatedAtRound !== null) continue;
    const node = requireNode(state, faction.commandPostNodeId);
    if (node.ownerFactionId !== commander.factionId) continue;
    commander.remainingProductionRounds -= 1;
    if (commander.remainingProductionRounds > 0) continue;
    const piece = createPieceInPlace(
      state,
      commander.factionId,
      commander.cardId,
      faction.commandPostNodeId,
      state.strategicRound + 1,
    );
    commander.status = 'fielded';
    commander.pieceInstanceId = piece.pieceId;
    commander.nodeId = piece.nodeId;
    commander.readyFromRound = state.strategicRound + 1;
  }
}

export function redeployPlayerAvatarInPlace(
  state: GameState,
  commanderId: string,
  nodeId: NodeId,
): void {
  const commander = state.commanders[commanderId];
  if (!commander || commander.role !== 'player_avatar' || commander.status !== 'rear') {
    throw new Error(`Player avatar ${commanderId} is not available for redeployment.`);
  }
  const piece = createPieceInPlace(
    state,
    commander.factionId,
    commander.cardId,
    nodeId,
    state.strategicRound + 1,
  );
  commander.status = 'fielded';
  commander.pieceInstanceId = piece.pieceId;
  commander.nodeId = nodeId;
  commander.readyFromRound = state.strategicRound + 1;
  addGameEvent(state, {
    type: 'commander_redeployed',
    factionId: commander.factionId,
    nodeId,
    pieceId: piece.pieceId,
    message: '玩家指挥官已从安全指挥所重新部署；下个战略回合开始贡献前线行动点。',
    data: { commanderId, characterId: commander.characterId },
  });
}

export function syncCommanderNodeInPlace(state: GameState, pieceInstanceId: string, nodeId: NodeId): void {
  const commander = commanderForPiece(state, pieceInstanceId);
  if (commander) commander.nodeId = nodeId;
}
