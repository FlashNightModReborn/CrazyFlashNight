import assert from 'node:assert/strict';
import test from 'node:test';
import {
  applyAs2BattleResume,
  buildAs2BattleEnvelope,
  canonicalJson,
  sha256Canonical,
  type As2BattleEnvelope,
  type As2ResumeEnvelope,
} from '../src/battle/as2-authority.js';
import { requireNode } from '../src/core/access.js';
import { applyCommand } from '../src/core/engine.js';
import { requireFaction } from '../src/core/factions.js';
import {
  auditOrganizationState,
  commandElementForMember,
  mergeTaskGroupInPlace,
} from '../src/core/organization.js';
import { createPieceInPlace } from '../src/core/pieces.js';
import type { GameState, MoveOrAttackCommand } from '../src/core/types.js';
import { getCardDefinition } from '../src/data/cards.js';
import { clearAllPieces, makeState, setAction } from './helpers.js';

const EXPECTED_CANONICAL_TASK_GROUP_SEED =
  'phase-c-task-group|1|1|["pet-red-12","pet-red-13"]|["pet-blue-15"]';

function battleFixture(): { state: GameState; command: MoveOrAttackCommand } {
  const state = makeState('phase-c-as2-authority');
  clearAllPieces(state);
  createPieceInPlace(state, 'red', 12, 'R-Supply', 1, { pieceId: 'pet-red-12' });
  createPieceInPlace(state, 'blue', 15, 'North-Choke', 1, { pieceId: 'pet-blue-15' });
  setAction(state, 'red', 4);
  return {
    state,
    command: {
      type: 'MOVE_OR_ATTACK',
      factionId: 'red',
      pieceIds: ['pet-red-12'],
      originNodeId: 'R-Supply',
      targetNodeId: 'North-Choke',
    },
  };
}

async function envelopeFixture(): Promise<As2BattleEnvelope> {
  const { state, command } = battleFixture();
  return buildAs2BattleEnvelope({
    panelInstanceId: 'warlord.panel.1',
    callId: 'warlord.call.1',
    sessionId: 'warlord.session.1',
    requestId: 'warlord.request.1',
    state,
    command,
    clientContext: {
      seed: state.gameSeed,
      preset: state.preset,
      difficulty: state.difficulty,
      mapTheme: 'desert',
      forceWebglFailure: false,
      aiSeenTransitions: [],
    },
  });
}

function taskGroupBattleFixture(): { state: GameState; command: MoveOrAttackCommand } {
  const state = makeState('phase-c-task-group');
  clearAllPieces(state);
  createPieceInPlace(state, 'red', 12, 'R-Supply', 1, { pieceId: 'pet-red-12' });
  createPieceInPlace(state, 'red', 13, 'R-Supply', 1, { pieceId: 'pet-red-13' });
  createPieceInPlace(state, 'blue', 15, 'North-Choke', 1, { pieceId: 'pet-blue-15' });
  const firstElementId = state.organization.memberToElementId['pet-red-12'];
  const secondElementId = state.organization.memberToElementId['pet-red-13'];
  if (!firstElementId || !secondElementId) throw new Error('TaskGroup fixture 缺少初始指挥单位。');
  mergeTaskGroupInPlace(
    state,
    [firstElementId, secondElementId],
    'demo1.mixed-detachment',
    'line',
  );
  setAction(state, 'red', 4);
  return {
    state,
    command: {
      type: 'MOVE_OR_ATTACK',
      factionId: 'red',
      pieceIds: ['pet-red-13', 'pet-red-12'],
      originNodeId: 'R-Supply',
      targetNodeId: 'North-Choke',
    },
  };
}

async function taskGroupEnvelopeFixture(state: GameState): Promise<As2BattleEnvelope> {
  const command: MoveOrAttackCommand = {
    type: 'MOVE_OR_ATTACK',
    factionId: 'red',
    pieceIds: ['pet-red-13', 'pet-red-12'],
    originNodeId: 'R-Supply',
    targetNodeId: 'North-Choke',
  };
  return buildAs2BattleEnvelope({
    panelInstanceId: 'warlord.panel.task-group',
    callId: 'warlord.call.task-group',
    sessionId: 'warlord.session.task-group',
    requestId: 'warlord.request.task-group',
    state,
    command,
    clientContext: {
      seed: state.gameSeed,
      preset: state.preset,
      difficulty: state.difficulty,
      mapTheme: 'desert',
      forceWebglFailure: false,
      aiSeenTransitions: [],
    },
  });
}

function acceptedResume(envelope: As2BattleEnvelope): As2ResumeEnvelope {
  const attackerDefinition = getCardDefinition(12);
  const defenderDefinition = getCardDefinition(15);
  return {
    schema: 'warlord.as2-resume.v1',
    request: structuredClone(envelope.request),
    state: structuredClone(envelope.request.state),
    command: structuredClone(envelope.request.command),
    inputDigest: envelope.inputDigest,
    clientContext: structuredClone(envelope.request.clientContext),
    receipt: {
      schema: 'warlord.as2-battle-receipt.v2',
      status: 'accepted',
      sessionId: envelope.request.sessionId,
      requestId: envelope.request.requestId,
      inputDigest: envelope.inputDigest,
      petProjectionProfile: 'catalog_identifier+strategic_progression_v1',
      playerPetSnapshotUsed: false,
      participantProjectionProfile: 'discriminated_player_avatar+catalog_pet_v1',
      playerAvatarProjectionProfile: 'trusted_demo2_commander_v1',
      playerPersistentSnapshotUsed: false,
      playerControlledSide: 'none',
      as2Status: 'finished',
      as2Winner: 'blue',
      sideMap: { blue: 'attacker', red: 'defender' },
      frames: 180,
      durationMs: 6000,
      attackerUnits: [{
        pieceId: 'pet-red-12', factionId: 'red', projectionKind: 'pet_projection', petId: 12,
        identifier: attackerDefinition.identifier, level: 1, strategicPromotions: [],
        resolvedType: attackerDefinition.identifier, startMaxHp: 1000, remainHp: 625,
        hpPermille: 625, alive: true,
      }],
      defenderUnits: [{
        pieceId: 'pet-blue-15', factionId: 'blue', projectionKind: 'pet_projection', petId: 15,
        identifier: defenderDefinition.identifier, level: 1, strategicPromotions: [],
        resolvedType: defenderDefinition.identifier, startMaxHp: 1000, remainHp: 0,
        hpPermille: 0, alive: false,
      }],
      economyObservation: {
        schema: 'warlord.pet-economy-observation.v1',
        mode: 'observe_only',
        writesPlayerState: false,
        settlementPolicy: 'none',
        catalogAuthority: 'data/merc/pets.xml',
        catalogPriceBasis: 'xml_base_price',
        currentAs2SessionPriceSampled: false,
        strategicValueBasis: 'piece.productionGoldValue',
        catalogCurrencyUnit: 'player_gold',
        strategicCurrencyUnit: 'warlord_gold',
        attacker: {
          catalogBaseExposureGold: 8000, catalogBaseLostGold: 0,
          catalogBaseExposureK: 0, catalogBaseLostK: 0,
          strategicExposureGold: 8, strategicLostGold: 0,
          units: [{
            pieceId: 'pet-red-12', projectionKind: 'pet_projection', petId: 12,
            identifier: attackerDefinition.identifier, catalogName: attackerDefinition.displayName,
            rosterType: 'pet', catalogEligible: true,
            strategicPromotions: [], strategicGoldValue: 8,
            basePrice: 8000, kPrice: 0, increasePrice: 0,
            hpPermille: 625, lost: false,
          }],
        },
        defender: {
          catalogBaseExposureGold: 10000, catalogBaseLostGold: 10000,
          catalogBaseExposureK: 0, catalogBaseLostK: 0,
          strategicExposureGold: 60, strategicLostGold: 60,
          units: [{
            pieceId: 'pet-blue-15', projectionKind: 'pet_projection', petId: 15,
            identifier: defenderDefinition.identifier, catalogName: defenderDefinition.displayName,
            rosterType: 'pet', catalogEligible: true,
            strategicPromotions: [], strategicGoldValue: 60,
            basePrice: 10000, kPrice: 0, increasePrice: 0,
            hpPermille: 0, lost: true,
          }],
        },
      },
    },
  };
}

function acceptedTaskGroupResume(envelope: As2BattleEnvelope): As2ResumeEnvelope {
  const resume = acceptedResume(envelope);
  const receipt = resume.receipt as Record<string, unknown>;
  const attackerDefinition = getCardDefinition(13);
  const attackerPiece = envelope.request.state.pieces['pet-red-13'];
  if (!attackerPiece) throw new Error('TaskGroup fixture 缺少第二枚进攻棋子。');
  const attackerUnits = receipt.attackerUnits as Array<Record<string, unknown>>;
  attackerUnits.push({
    pieceId: 'pet-red-13', factionId: 'red', projectionKind: 'pet_projection', petId: 13,
    identifier: attackerDefinition.identifier, level: 1, strategicPromotions: [],
    resolvedType: attackerDefinition.identifier, startMaxHp: 1000, remainHp: 1000,
    hpPermille: 1000, alive: true,
  });
  const economy = receipt.economyObservation as Record<string, unknown>;
  const attacker = economy.attacker as Record<string, unknown>;
  const units = attacker.units as Array<Record<string, unknown>>;
  units.push({
    pieceId: 'pet-red-13', projectionKind: 'pet_projection', petId: 13,
    identifier: attackerDefinition.identifier, catalogName: attackerDefinition.displayName,
    rosterType: 'pet', catalogEligible: true,
    strategicPromotions: [], strategicGoldValue: attackerPiece.productionGoldValue,
    basePrice: 0, kPrice: 0, increasePrice: 0,
    hpPermille: 1000, lost: false,
  });
  attacker.strategicExposureGold = Number(attacker.strategicExposureGold)
    + attackerPiece.productionGoldValue;
  return resume;
}

async function playerAvatarEnvelopeFixture(): Promise<As2BattleEnvelope> {
  const state = makeState('phase-c-player-avatar');
  clearAllPieces(state);
  createPieceInPlace(state, 'red', 83, 'R-Supply', 1, { pieceId: 'player-avatar-piece' });
  createPieceInPlace(state, 'blue', 15, 'North-Choke', 1, { pieceId: 'pet-blue-15' });
  state.commanders = {
    'commander.player': {
      commanderId: 'commander.player',
      characterId: 'character.player-avatar',
      factionId: 'red',
      role: 'player_avatar',
      cardId: 83,
      status: 'fielded',
      pieceInstanceId: 'player-avatar-piece',
      nodeId: 'R-Supply',
      apContribution: 1,
      productionGoldCost: 0,
      productionRounds: 0,
      remainingProductionRounds: 0,
      readyFromRound: 1,
    },
  };
  setAction(state, 'red', 4);
  const command: MoveOrAttackCommand = {
    type: 'MOVE_OR_ATTACK',
    factionId: 'red',
    pieceIds: ['player-avatar-piece'],
    originNodeId: 'R-Supply',
    targetNodeId: 'North-Choke',
  };
  return buildAs2BattleEnvelope({
    panelInstanceId: 'warlord.panel.player-avatar',
    callId: 'warlord.call.player-avatar',
    sessionId: 'warlord.session.player-avatar',
    requestId: 'warlord.request.player-avatar',
    state,
    command,
    clientContext: {
      seed: state.gameSeed,
      preset: state.preset,
      difficulty: state.difficulty,
      mapTheme: 'desert',
      forceWebglFailure: false,
      aiSeenTransitions: [],
    },
  });
}

function acceptedPlayerAvatarResume(envelope: As2BattleEnvelope): As2ResumeEnvelope {
  const resume = acceptedResume(envelope);
  const receipt = resume.receipt as Record<string, unknown>;
  const attackerPiece = envelope.request.state.pieces['player-avatar-piece'];
  if (!attackerPiece) throw new Error('玩家主角 fixture 缺少战略棋子。');
  receipt.playerControlledSide = 'blue';
  receipt.attackerUnits = [{
    pieceId: 'player-avatar-piece',
    factionId: 'red',
    projectionKind: 'player_avatar',
    commanderId: 'commander.player',
    characterId: 'character.player-avatar',
    runtimeLevel: 99,
    startMaxHp: 2000,
    remainHp: 1500,
    hpPermille: 750,
    alive: true,
  }];
  const economy = receipt.economyObservation as Record<string, unknown>;
  economy.attacker = {
    catalogBaseExposureGold: 0,
    catalogBaseLostGold: 0,
    catalogBaseExposureK: 0,
    catalogBaseLostK: 0,
    strategicExposureGold: attackerPiece.productionGoldValue,
    strategicLostGold: 0,
    units: [{
      pieceId: 'player-avatar-piece',
      projectionKind: 'player_avatar',
      commanderId: 'commander.player',
      characterId: 'character.player-avatar',
      catalogEligible: false,
      strategicGoldValue: attackerPiece.productionGoldValue,
      hpPermille: 750,
      lost: false,
    }],
  };
  return resume;
}

function applyZeroApReorganizationRoundTrip(state: GameState): GameState {
  const initialElement = commandElementForMember(state, 'pet-red-12');
  if (!initialElement) throw new Error('TaskGroup fixture 缺少合并后的指挥单位。');
  const formation = applyCommand(state, {
    type: 'SET_FORMATION',
    factionId: 'red',
    nodeId: 'R-Supply',
    commandElementId: initialElement.elementId,
    formationProfileId: 'wedge',
  });
  if (!formation.ok) throw new Error(formation.error);
  const split = applyCommand(formation.state, {
    type: 'SPLIT_TASK_GROUP',
    factionId: 'red',
    nodeId: 'R-Supply',
    commandElementId: initialElement.elementId,
    memberIds: ['pet-red-13'],
  });
  if (!split.ok) throw new Error(split.error);
  const firstElementId = split.state.organization.memberToElementId['pet-red-12'];
  const secondElementId = split.state.organization.memberToElementId['pet-red-13'];
  if (!firstElementId || !secondElementId) throw new Error('TaskGroup 往返 fixture 拆分后缺少指挥单位。');
  const merged = applyCommand(split.state, {
    type: 'MERGE_TASK_GROUP',
    factionId: 'red',
    nodeId: 'R-Supply',
    commandElementIds: [firstElementId, secondElementId],
    taskGroupTemplateId: 'demo1.mixed-detachment',
    formationProfileId: 'line',
  });
  if (!merged.ok) throw new Error(merged.error);
  return merged.state;
}

test('Phase C canonical digest 与对象键插入顺序无关', async () => {
  const left = { z: 1, nested: { b: 2, a: [3, { y: 4, x: 5 }] } };
  const right = { nested: { a: [3, { x: 5, y: 4 }], b: 2 }, z: 1 };
  assert.equal(canonicalJson(left), canonicalJson(right));
  assert.equal(await sha256Canonical(left), await sha256Canonical(right));
});

test('Phase C canonical digest 按 Host 序列化数字形卡牌键', async () => {
  const value = { cards: { 12: 1, 111: 2 } };
  assert.equal(canonicalJson(value), '{"cards":{"111":2,"12":1}}');
  assert.match(await sha256Canonical(value), /^sha256:[0-9a-f]{64}$/);
});

test('Phase C 产品请求只冻结战略命令，不提交旧 unitTypeId 或玩家战宠写入', async () => {
  const envelope = await envelopeFixture();
  assert.equal(envelope.request.state.pieces['pet-red-12']?.cardId, 12);
  assert.equal(getCardDefinition(12).identifier, '敌人-军阀狙击兵');
  assert.equal(canonicalJson(envelope.request).includes('unitTypeId'), false);
  assert.equal(canonicalJson(envelope.request).includes('productionWrites'), false);
  assert.match(envelope.inputDigest, /^sha256:[0-9a-f]{64}$/);
});

test('Phase C accepted 回执按 petId+Identifier 结算棋子、伤亡与只读经济观测', async () => {
  const envelope = await envelopeFixture();
  const result = await applyAs2BattleResume(acceptedResume(envelope));
  assert.equal(result.ok, true, result.error);
  assert.equal(result.resultUnknown, false);
  assert.ok(result.state);
  const state = result.state;
  assert.equal(state.pieces['pet-red-12']?.nodeId, 'North-Choke');
  assert.equal(state.pieces['pet-red-12']?.hp,
    Math.round((envelope.request.state.pieces['pet-red-12']?.maxHp ?? 0) * 0.625));
  assert.equal(state.pieces['pet-blue-15'], undefined);
  assert.equal(requireNode(state, 'North-Choke').ownerFactionId, null);
  assert.equal(state.eventLog.some((event) => event.type === 'node_captured'), false);
  assert.equal(requireFaction(state, 'red').actionPoints, 3);
  assert.equal(state.casualtyLedger.length, 1);
  assert.equal(result.battleRecord?.authority?.authority, 'as2');
  assert.equal(result.battleRecord?.authority?.economyObservation.writesPlayerState, false);
  assert.equal(result.battleRecord?.authority?.economyObservation.catalogPriceBasis, 'xml_base_price');
  assert.equal(result.battleRecord?.result.finalRngState, 0);
});

test('Phase C accepted 回执以 player_avatar 结算真实主角且不把运行等级当战略卡等级', async () => {
  const envelope = await playerAvatarEnvelopeFixture();
  const resume = acceptedPlayerAvatarResume(envelope);
  const result = await applyAs2BattleResume(resume);
  assert.equal(result.ok, true, result.error);
  assert.ok(result.state);
  assert.equal(result.state.pieces['player-avatar-piece']?.nodeId, 'North-Choke');
  assert.equal(result.state.pieces['player-avatar-piece']?.hp,
    Math.round((envelope.request.state.pieces['player-avatar-piece']?.maxHp ?? 0) * 0.75));
  const avatarResult = result.battleRecord?.result.pieceResults
    .find((piece) => piece.pieceId === 'player-avatar-piece');
  const avatarSnapshot = result.battleRecord?.attackerSnapshots
    .find((piece) => piece.pieceId === 'player-avatar-piece');
  assert.equal(avatarSnapshot?.encounterProjectionKind, 'player_avatar');
  assert.equal(avatarSnapshot?.displayName, '我方主角');
  assert.notEqual(avatarSnapshot?.displayName, getCardDefinition(83).displayName);
  assert.equal(avatarResult?.frozenCardLevel, 1);
  assert.notEqual(avatarResult?.frozenCardLevel, 99);
  const economy = result.battleRecord?.authority?.economyObservation as Record<string, unknown>;
  const attacker = economy.attacker as Record<string, unknown>;
  assert.equal(attacker.catalogBaseExposureGold, 0);
  assert.equal(attacker.strategicExposureGold,
    envelope.request.state.pieces['player-avatar-piece']?.productionGoldValue);
  assert.equal(result.state.commanders['commander.player']?.status, 'fielded');
  assert.equal(result.state.commanders['commander.player']?.nodeId, 'North-Choke');
});

test('Phase C player_avatar 回执拒绝指挥官伪造、控制侧漂移与伪装战宠经济字段', async () => {
  const envelope = await playerAvatarEnvelopeFixture();

  const identityTampered = acceptedPlayerAvatarResume(envelope);
  const identityReceipt = identityTampered.receipt as Record<string, unknown>;
  (identityReceipt.attackerUnits as Array<Record<string, unknown>>)[0]!.commanderId = 'commander.spoof';
  assert.equal((await applyAs2BattleResume(identityTampered)).ok, false);

  const sideTampered = acceptedPlayerAvatarResume(envelope);
  (sideTampered.receipt as Record<string, unknown>).playerControlledSide = 'none';
  assert.equal((await applyAs2BattleResume(sideTampered)).ok, false);

  const economyTampered = acceptedPlayerAvatarResume(envelope);
  const economyReceipt = economyTampered.receipt as Record<string, unknown>;
  const economy = economyReceipt.economyObservation as Record<string, unknown>;
  const attacker = economy.attacker as Record<string, unknown>;
  const unit = (attacker.units as Array<Record<string, unknown>>)[0]!;
  unit.catalogEligible = true;
  unit.petId = 83;
  assert.equal((await applyAs2BattleResume(economyTampered)).ok, false);
});

test('Phase C accepted 回执中的指挥官伤亡同步 Commander ledger 并立即移除前线行动点', async () => {
  const { state, command } = battleFixture();
  const blue = requireFaction(state, 'blue');
  blue.apLedger.fieldGenerated = 1;
  blue.apLedger.fieldRemaining = 1;
  blue.actionPoints = blue.apLedger.baseRemaining + blue.apLedger.fieldRemaining;
  state.commanders['commander.blue'] = {
    commanderId: 'commander.blue',
    characterId: 'character.test-boss',
    factionId: 'blue',
    role: 'boss_unique',
    cardId: 15,
    status: 'fielded',
    pieceInstanceId: 'pet-blue-15',
    nodeId: 'North-Choke',
    apContribution: 1,
    productionGoldCost: 180,
    productionRounds: 4,
    remainingProductionRounds: 0,
    readyFromRound: 1,
  };
  const envelope = await buildAs2BattleEnvelope({
    panelInstanceId: 'warlord.panel.commander-casualty',
    callId: 'warlord.call.commander-casualty',
    sessionId: 'warlord.session.commander-casualty',
    requestId: 'warlord.request.commander-casualty',
    state,
    command,
    clientContext: {
      seed: state.gameSeed,
      preset: state.preset,
      difficulty: state.difficulty,
      mapTheme: 'desert',
      forceWebglFailure: false,
      aiSeenTransitions: [],
    },
  });

  const result = await applyAs2BattleResume(acceptedResume(envelope));
  assert.equal(result.ok, true);
  assert.ok(result.state);
  const resolvedState = result.state;
  const commander = resolvedState.commanders['commander.blue'];
  const resolvedBlue = requireFaction(resolvedState, 'blue');
  assert.equal(commander?.status, 'available');
  assert.equal(commander?.pieceInstanceId, null);
  assert.equal(commander?.nodeId, null);
  assert.equal(resolvedState.pieces['pet-blue-15'], undefined);
  assert.equal(resolvedBlue.apLedger.fieldRemaining, 0);
  assert.equal(
    resolvedBlue.actionPoints,
    resolvedBlue.apLedger.baseRemaining,
  );
});

test('Phase C accepted 进攻胜利只移动幸存者，行动末才驻点染色并结算敌方指挥所', async () => {
  const { state, command } = battleFixture();
  requireFaction(state, 'blue').commandPostNodeId = command.targetNodeId;
  requireNode(state, command.targetNodeId).ownerFactionId = 'blue';
  requireNode(state, command.targetNodeId).activeFromRound = 1;
  const envelope = await buildAs2BattleEnvelope({
    panelInstanceId: 'warlord.panel.command-post',
    callId: 'warlord.call.command-post',
    sessionId: 'warlord.session.command-post',
    requestId: 'warlord.request.command-post',
    state,
    command,
    clientContext: {
      seed: state.gameSeed,
      preset: state.preset,
      difficulty: state.difficulty,
      mapTheme: 'desert',
      forceWebglFailure: false,
      aiSeenTransitions: [],
    },
  });

  const result = await applyAs2BattleResume(acceptedResume(envelope));
  assert.equal(result.ok, true);
  assert.ok(result.state);
  assert.equal(result.state.pieces['pet-red-12']?.nodeId, command.targetNodeId);
  assert.equal(requireNode(result.state, command.targetNodeId).ownerFactionId, 'blue');
  assert.equal(requireFaction(result.state, 'blue').defeatReason, null);
  assert.equal(result.state.capturedCommandPostNodeIds.includes(command.targetNodeId), false);
  assert.equal(result.state.result, null);
  assert.equal(result.state.eventLog.some((event) => event.type === 'node_captured'), false);

  const ended = applyCommand(result.state, { type: 'END_ACTION', factionId: command.factionId });
  assert.equal(ended.ok, true, ended.error);
  assert.equal(requireNode(ended.state, command.targetNodeId).ownerFactionId, command.factionId);
  assert.equal(requireFaction(ended.state, 'blue').defeatReason, 'command_post_captured');
  assert.equal(ended.state.capturedCommandPostNodeIds.includes(command.targetNodeId), true);
  assert.equal(ended.state.result?.reasonCode, 'CommandPostCaptured');
  assert.deepEqual(
    ended.state.eventLog
      .filter((event) => event.type === 'node_captured' && event.nodeId === command.targetNodeId)
      .map((event) => event.captureCause),
    ['direct_end_turn'],
  );
});

test('Phase C accepted 回执整组移动 TaskGroup、同步组织 sidecar 并按 Demo1 commandLoad 扣点', async () => {
  const fixture = taskGroupBattleFixture();
  const envelope = await taskGroupEnvelopeFixture(fixture.state);
  const result = await applyAs2BattleResume(acceptedTaskGroupResume(envelope));
  assert.equal(result.ok, true, result.error);
  assert.ok(result.state);
  const state = result.state;
  assert.equal(state.pieces['pet-red-12']?.nodeId, 'North-Choke');
  assert.equal(state.pieces['pet-red-13']?.nodeId, 'North-Choke');
  const firstElement = commandElementForMember(state, 'pet-red-12');
  const secondElement = commandElementForMember(state, 'pet-red-13');
  assert.equal(firstElement?.elementId, secondElement?.elementId);
  assert.equal(firstElement?.nodeId, 'North-Choke');
  assert.deepEqual(auditOrganizationState(state), []);
  assert.equal(requireFaction(state, 'red').actionPoints, 2);
  assert.equal(requireFaction(state, 'red').apSpentThisRound, 2);
});

test('Phase C 零 AP 往返重组不改变下一战 battleId/seed，commandSequence 仅作审计', async () => {
  const baseline = taskGroupBattleFixture().state;
  const reorganized = applyZeroApReorganizationRoundTrip(taskGroupBattleFixture().state);
  assert.equal(requireFaction(baseline, 'red').actionPoints, 4);
  assert.equal(requireFaction(reorganized, 'red').actionPoints, 4);
  assert.notEqual(baseline.commandSequence, reorganized.commandSequence);

  const baselineEnvelope = await taskGroupEnvelopeFixture(baseline);
  const reorganizedEnvelope = await taskGroupEnvelopeFixture(reorganized);
  const baselineResult = await applyAs2BattleResume(acceptedTaskGroupResume(baselineEnvelope));
  const reorganizedResult = await applyAs2BattleResume(acceptedTaskGroupResume(reorganizedEnvelope));
  assert.equal(baselineResult.ok, true, baselineResult.error);
  assert.equal(reorganizedResult.ok, true, reorganizedResult.error);
  assert.equal(baselineResult.battleRecord?.battleId, 'b-r1-o1');
  assert.equal(reorganizedResult.battleRecord?.battleId, 'b-r1-o1');
  assert.equal(baselineResult.battleRecord?.seed, EXPECTED_CANONICAL_TASK_GROUP_SEED);
  assert.equal(reorganizedResult.battleRecord?.seed, EXPECTED_CANONICAL_TASK_GROUP_SEED);
  assert.notEqual(
    baselineResult.battleRecord?.commandSequence,
    reorganizedResult.battleRecord?.commandSequence,
  );
});

test('Phase C unknown 回执保持冻结战略态并要求阻断继续结算', async () => {
  const envelope = await envelopeFixture();
  const resume = acceptedResume(envelope);
  resume.receipt = {
    schema: 'warlord.as2-battle-receipt.v2',
    status: 'unknown',
    sessionId: envelope.request.sessionId,
    requestId: envelope.request.requestId,
    inputDigest: envelope.inputDigest,
    message: 'socket lost after dispatch',
  };
  const result = await applyAs2BattleResume(resume);
  assert.equal(result.ok, false);
  assert.equal(result.resultUnknown, true);
  assert.deepEqual(result.state, envelope.request.state);
});

test('Phase C 明确未发出的 AS2 请求恢复冻结态但不制造未知战果锁', async () => {
  const envelope = await envelopeFixture();
  const resume = acceptedResume(envelope);
  resume.receipt = {
    schema: 'warlord.as2-battle-receipt.v2',
    status: 'not_started',
    sessionId: envelope.request.sessionId,
    requestId: envelope.request.requestId,
    inputDigest: envelope.inputDigest,
    message: 'pause lease was not released',
  };
  const result = await applyAs2BattleResume(resume);
  assert.equal(result.ok, false);
  assert.equal(result.resultUnknown, false);
  assert.deepEqual(result.state, envelope.request.state);
});

test('Phase C 旧 v1 frozen state 缺 organization 时按存活棋子确定性补 singleton 后结算', async () => {
  const envelope = await envelopeFixture();
  const resume = acceptedResume(envelope);
  delete (resume.request.state as unknown as { organization?: unknown }).organization;
  delete (resume.state as unknown as { organization?: unknown }).organization;
  const legacyDigest = await sha256Canonical(resume.request);
  resume.inputDigest = legacyDigest;
  (resume.receipt as Record<string, unknown>).inputDigest = legacyDigest;

  const result = await applyAs2BattleResume(resume);
  assert.equal(result.ok, true, result.error);
  assert.ok(result.state);
  const state = result.state;
  assert.deepEqual(auditOrganizationState(state), []);
  assert.equal(state.pieces['pet-red-12']?.nodeId, 'North-Choke');
  assert.equal(commandElementForMember(state, 'pet-red-12')?.kind, 'singleton');
});

test('Phase C 拒绝摘要篡改、战宠身份漂移与可写经济声明', async () => {
  const envelope = await envelopeFixture();
  const digestTampered = acceptedResume(envelope);
  digestTampered.state.commandSequence += 1;
  assert.equal((await applyAs2BattleResume(digestTampered)).ok, false);

  const identityTampered = acceptedResume(envelope);
  const identityReceipt = identityTampered.receipt as Record<string, unknown>;
  (identityReceipt.attackerUnits as Array<Record<string, unknown>>)[0]!.petId = 13;
  assert.equal((await applyAs2BattleResume(identityTampered)).ok, false);

  const economyTampered = acceptedResume(envelope);
  const economyReceipt = economyTampered.receipt as Record<string, unknown>;
  (economyReceipt.economyObservation as Record<string, unknown>).writesPlayerState = true;
  assert.equal((await applyAs2BattleResume(economyTampered)).ok, false);

  const strategicValueTampered = acceptedResume(envelope);
  const strategicReceipt = strategicValueTampered.receipt as Record<string, unknown>;
  const strategicObservation = strategicReceipt.economyObservation as Record<string, unknown>;
  const strategicAttacker = strategicObservation.attacker as Record<string, unknown>;
  const strategicUnits = strategicAttacker.units as Array<Record<string, unknown>>;
  strategicUnits[0]!.strategicGoldValue = 9;
  assert.equal((await applyAs2BattleResume(strategicValueTampered)).ok, false);

  const contextTampered = acceptedResume(envelope);
  contextTampered.clientContext.mapTheme = 'tundra';
  assert.equal((await applyAs2BattleResume(contextTampered)).ok, false);

  const winnerTampered = acceptedResume(envelope);
  (winnerTampered.receipt as Record<string, unknown>).as2Winner = 'red';
  assert.equal((await applyAs2BattleResume(winnerTampered)).ok, false);

  const sideMapTampered = acceptedResume(envelope);
  (sideMapTampered.receipt as Record<string, unknown>).sideMap = {
    blue: 'defender',
    red: 'attacker',
  };
  assert.equal((await applyAs2BattleResume(sideMapTampered)).ok, false);

  const obsoleteReceipt = acceptedResume(envelope);
  (obsoleteReceipt.receipt as Record<string, unknown>).schema = 'warlord.as2-battle-receipt.v1';
  assert.equal((await applyAs2BattleResume(obsoleteReceipt)).ok, false);
});
