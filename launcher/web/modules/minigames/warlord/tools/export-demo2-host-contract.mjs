import { buildAs2BattleEnvelope } from '../runtime/battle/as2-authority.js';
import { commandElementForMember } from '../runtime/core/organization.js';
import { movePiecesInPlace } from '../runtime/core/pieces.js';
import { adjacentNodeIds } from '../runtime/core/selectors.js';
import { createGame } from '../runtime/core/state.js';
import { validateCommand } from '../runtime/core/validator.js';
import { DEMO_2_RUNTIME } from '../runtime/data/map.js';

const seed = 'demo2-host-contract-v1';
const state = createGame({
  runtimeBundle: DEMO_2_RUNTIME,
  difficulty: 'normal',
  preset: 'standard',
  seed,
});

const playerCommander = state.commanders['commander.player'];
if (!playerCommander?.pieceInstanceId) throw new Error('Demo 2 player commander is not fielded.');
const playerPiece = state.pieces[playerCommander.pieceInstanceId];
if (!playerPiece || playerPiece.cardId !== 83) throw new Error('Demo 2 player avatar piece is missing.');
const playerElement = commandElementForMember(state, playerPiece.pieceId);
if (!playerElement) throw new Error('Demo 2 player avatar has no command element.');

const targetNodeId = adjacentNodeIds(state, playerPiece.nodeId)[0];
if (targetNodeId !== 'd2-player-02') {
  throw new Error(`Unexpected deterministic player target: ${targetNodeId ?? 'missing'}.`);
}

// Build the same deterministic live-runtime fixture used to diagnose the Host
// contract: clear the adjacent node through the runtime move path, then field
// Surveyor there so the real validator sees a player-initiated battle.
const displacedPieceIds = [...state.map.nodes[targetNodeId].pieceIds];
if (displacedPieceIds.length > 0) {
  movePiecesInPlace(state, displacedPieceIds, playerPiece.nodeId);
}
const surveyor = state.commanders['commander.boss-independent'];
if (!surveyor?.pieceInstanceId || surveyor.cardId !== 113) {
  throw new Error('Demo 2 Surveyor commander is not fielded.');
}
movePiecesInPlace(state, [surveyor.pieceInstanceId], targetNodeId);

const battleCommand = {
  type: 'MOVE_OR_ATTACK',
  factionId: state.playerFactionId,
  pieceIds: [...playerElement.memberIds],
  originNodeId: playerPiece.nodeId,
  targetNodeId,
};
const validation = validateCommand(state, battleCommand);
if (!validation.ok || validation.isBattle !== true) {
  throw new Error(
    `Deterministic player battle is invalid: ${validation.reasonCode ?? validation.error ?? 'not_battle'}`,
  );
}
if (validation.defenderFactionId !== surveyor.factionId) {
  throw new Error(`Unexpected deterministic defender: ${validation.defenderFactionId ?? 'missing'}.`);
}

const envelope = await buildAs2BattleEnvelope({
  panelInstanceId: 'warlord.panel.live-contract',
  callId: 'warlord.call.live-contract',
  sessionId: 'warlord.session.live-contract',
  requestId: 'warlord.request.live-contract',
  state,
  command: battleCommand,
  clientContext: {
    seed,
    preset: state.preset,
    difficulty: state.difficulty,
    mapTheme: 'desert',
    forceWebglFailure: false,
    aiSeenTransitions: [],
  },
});

process.stdout.write(JSON.stringify(envelope));
