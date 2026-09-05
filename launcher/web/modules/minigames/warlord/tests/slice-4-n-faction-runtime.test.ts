import assert from 'node:assert/strict';
import test from 'node:test';
import { runAiActionPhase } from '../src/ai/heuristic.js';
import {
  evacuateDownedPlayerAvatarsInPlace,
  handleCommanderCasualtyInPlace,
  progressCommanderProductionInPlace,
} from '../src/core/commanders.js';
import { applyCommand } from '../src/core/engine.js';
import {
  requireFaction,
  relationBetween,
  spendFactionActionPointsInPlace,
} from '../src/core/factions.js';
import { captureCommandPostInPlace } from '../src/core/objectives.js';
import { removePieceInPlace } from '../src/core/pieces.js';
import { createGame } from '../src/core/state.js';
import { DEMO_2_RUNTIME } from '../src/data/map.js';

function createDemo2() {
  return createGame({
    seed: 'slice-4-n-faction-runtime',
    runtimeBundle: DEMO_2_RUNTIME,
  });
}

test('Slice 4 Demo 2 materializes four factions, three victory groups and a complete relation matrix', () => {
  const state = createDemo2();
  assert.deepEqual(state.turnOrder, [
    'player',
    'boss-pact-a',
    'boss-independent',
    'boss-pact-b',
  ]);
  assert.equal(Object.keys(state.factions).length, 4);
  assert.equal(Object.keys(state.victoryGroups).length, 3);
  for (const left of state.turnOrder) {
    for (const right of state.turnOrder) {
      assert.equal(relationBetween(state, left, right), relationBetween(state, right, left));
    }
  }
  assert.equal(relationBetween(state, 'boss-pact-a', 'boss-pact-b'), 'allied');
  assert.equal(relationBetween(state, 'player', 'boss-independent'), 'hostile');
  assert.equal(requireFaction(state, 'boss-pact-a').victoryGroupId, 'victory-group.pact');
  assert.equal(requireFaction(state, 'boss-pact-b').victoryGroupId, 'victory-group.pact');
});

test('Slice 4 Demo 2 binds one field commander per faction and separates field AP', () => {
  const state = createDemo2();
  assert.equal(Object.keys(state.commanders).length, 4);
  assert.deepEqual(Object.fromEntries(Object.values(state.commanders).map((commander) => [
    commander.factionId,
    [commander.characterId, commander.cardId],
  ])), {
    player: ['character.player-avatar', 83],
    'boss-pact-a': ['character.itinerant', 111],
    'boss-independent': ['character.surveyor', 113],
    'boss-pact-b': ['character.gazer', 112],
  });
  for (const commander of Object.values(state.commanders)) {
    assert.equal(commander.status, 'fielded');
    assert.ok(commander.pieceInstanceId);
    const piece = state.pieces[commander.pieceInstanceId ?? ''];
    assert.ok(piece);
    assert.equal(piece?.factionId, commander.factionId);
    assert.equal(piece?.cardId, commander.cardId);
    assert.equal(piece?.nodeId, commander.nodeId);
    const faction = requireFaction(state, commander.factionId);
    assert.equal(faction.apLedger.fieldGenerated, commander.apContribution);
    assert.equal(faction.apLedger.fieldRemaining, commander.apContribution);
  }
});

test('Slice 4 all-units preset still binds every commander to the authored headquarters piece', () => {
  const state = createGame({
    seed: 'slice-4-all-units-commander-binding',
    preset: 'all-units',
    runtimeBundle: DEMO_2_RUNTIME,
  });
  for (const commander of Object.values(state.commanders)) {
    const piece = state.pieces[commander.pieceInstanceId ?? ''];
    const headquartersNodeId = requireFaction(state, commander.factionId).commandPostNodeId;
    assert.ok(piece);
    assert.equal(commander.nodeId, headquartersNodeId);
    assert.equal(piece?.nodeId, headquartersNodeId);
  }
});

test('Slice 4 field AP is spent first and disappears immediately when its commander falls', () => {
  const spentState = createDemo2();
  const spentFaction = requireFaction(spentState, 'boss-independent');
  const durableBase = spentFaction.apLedger.baseRemaining;
  spendFactionActionPointsInPlace(spentFaction, 1);
  assert.equal(spentFaction.apLedger.fieldSpent, 1);
  assert.equal(spentFaction.apLedger.fieldRemaining, 0);
  assert.equal(spentFaction.apLedger.baseRemaining, durableBase);

  const casualtyState = createDemo2();
  const commander = Object.values(casualtyState.commanders).find((entry) => (
    entry.factionId === 'boss-independent'
  ));
  assert.ok(commander?.pieceInstanceId);
  const pieceId = commander?.pieceInstanceId ?? '';
  const faction = requireFaction(casualtyState, 'boss-independent');
  assert.equal(faction.apLedger.fieldRemaining, 1);
  handleCommanderCasualtyInPlace(casualtyState, pieceId);
  removePieceInPlace(casualtyState, pieceId);
  assert.equal(commander?.status, 'available');
  assert.equal(commander?.pieceInstanceId, null);
  assert.equal(faction.apLedger.fieldRemaining, 0);
  assert.equal(faction.apLedger.baseRemaining, faction.apLedger.baseGenerated);
});

test('Slice 4 boss commander rebuild and player-avatar evacuation/redeployment use distinct lifecycles', () => {
  let bossState = createDemo2();
  const boss = Object.values(bossState.commanders).find((entry) => entry.factionId === 'boss-pact-a');
  assert.ok(boss?.pieceInstanceId);
  const bossPieceId = boss?.pieceInstanceId ?? '';
  handleCommanderCasualtyInPlace(bossState, bossPieceId);
  removePieceInPlace(bossState, bossPieceId);
  bossState.phase = 'SETTLEMENT_PLANNING';
  requireFaction(bossState, 'boss-pact-a').gold = boss?.productionGoldCost ?? 0;
  const queued = applyCommand(bossState, {
    type: 'ENQUEUE_COMMANDER_PRODUCTION',
    factionId: 'boss-pact-a',
    commanderId: boss?.commanderId ?? '',
  });
  assert.equal(queued.ok, true, queued.ok ? undefined : queued.error);
  if (!queued.ok) throw new Error(queued.error);
  bossState = queued.state;
  assert.equal(bossState.commanders[boss?.commanderId ?? '']?.status, 'queued');
  for (let round = 0; round < (boss?.productionRounds ?? 0); round += 1) {
    progressCommanderProductionInPlace(bossState);
  }
  const rebuilt = bossState.commanders[boss?.commanderId ?? ''];
  assert.equal(rebuilt?.status, 'fielded');
  assert.ok(rebuilt?.pieceInstanceId);
  assert.equal(bossState.pieces[rebuilt?.pieceInstanceId ?? '']?.nodeId, requireFaction(bossState, 'boss-pact-a').commandPostNodeId);

  let playerState = createDemo2();
  const avatar = Object.values(playerState.commanders).find((entry) => entry.role === 'player_avatar');
  assert.ok(avatar?.pieceInstanceId);
  const avatarPieceId = avatar?.pieceInstanceId ?? '';
  handleCommanderCasualtyInPlace(playerState, avatarPieceId);
  removePieceInPlace(playerState, avatarPieceId);
  assert.equal(avatar?.status, 'downed');
  evacuateDownedPlayerAvatarsInPlace(playerState);
  assert.equal(avatar?.status, 'rear');
  playerState.phase = 'SETTLEMENT_PLANNING';
  const commandPostNodeId = requireFaction(playerState, playerState.playerFactionId).commandPostNodeId;
  const redeployed = applyCommand(playerState, {
    type: 'REDEPLOY_PLAYER_AVATAR',
    factionId: playerState.playerFactionId,
    commanderId: avatar?.commanderId ?? '',
    nodeId: commandPostNodeId,
  });
  assert.equal(redeployed.ok, true, redeployed.ok ? undefined : redeployed.error);
  if (!redeployed.ok) throw new Error(redeployed.error);
  const fieldedAvatar = redeployed.state.commanders[avatar?.commanderId ?? ''];
  assert.equal(fieldedAvatar?.status, 'fielded');
  assert.equal(fieldedAvatar?.nodeId, commandPostNodeId);
  assert.ok(fieldedAvatar?.pieceInstanceId);
});

test('Slice 4 block turn order executes every living faction before settlement', () => {
  let state = createDemo2();
  for (const factionId of state.turnOrder) {
    assert.equal(state.activeFactionId, factionId);
    const result = applyCommand(state, { type: 'END_ACTION', factionId });
    assert.equal(result.ok, true, result.ok ? undefined : result.error);
    if (!result.ok) throw new Error(result.error);
    state = result.state;
  }
  assert.equal(state.phase, 'SETTLEMENT_PLANNING');
  assert.equal(state.activeFactionId, null);
});

test('Slice 6 Demo 2 completes a deterministic four-faction action block without invalid AI commands', () => {
  const runBlock = () => {
    let state = createDemo2();
    const playerEnd = applyCommand(state, { type: 'END_ACTION', factionId: state.playerFactionId });
    assert.equal(playerEnd.ok, true, playerEnd.ok ? undefined : playerEnd.error);
    if (!playerEnd.ok) throw new Error(playerEnd.error);
    state = playerEnd.state;
    const commandTypes: string[] = [];
    for (const factionId of ['boss-pact-a', 'boss-independent', 'boss-pact-b'] as const) {
      const result = runAiActionPhase(state, factionId);
      assert.equal(result.invalidGenerated, 0);
      commandTypes.push(...result.commands.map((command) => `${factionId}:${command.type}`));
      state = result.state;
      if (state.phase === 'GAME_OVER') break;
    }
    return { state, commandTypes };
  };

  const first = runBlock();
  const second = runBlock();
  assert.deepEqual(second, first);
  assert.equal(first.state.phase, 'SETTLEMENT_PLANNING');
  assert.equal(first.state.activeFactionId, null);
  assert.equal(first.commandTypes.filter((entry) => entry.endsWith(':END_ACTION')).length, 3);
});

test('capturing one allied command post removes only that faction; player command-post loss is terminal', () => {
  const state = createDemo2();
  const pactA = requireFaction(state, 'boss-pact-a');
  const pactB = requireFaction(state, 'boss-pact-b');
  assert.equal(captureCommandPostInPlace(state, 'player', pactA.commandPostNodeId), false);
  assert.equal(pactA.defeatReason, 'command_post_captured');
  assert.equal(pactB.defeatedAtRound, null);
  assert.equal(state.result, null);
  assert.equal(Object.values(state.pieces).some((piece) => piece.factionId === pactA.factionId), false);

  const playerLoss = createDemo2();
  const player = requireFaction(playerLoss, playerLoss.playerFactionId);
  assert.equal(captureCommandPostInPlace(playerLoss, 'boss-independent', player.commandPostNodeId), true);
  assert.equal(playerLoss.phase, 'GAME_OVER');
  assert.equal(playerLoss.result?.reasonCode, 'CommandPostCaptured');
  assert.equal(playerLoss.result?.winner, 'boss-independent');
});
