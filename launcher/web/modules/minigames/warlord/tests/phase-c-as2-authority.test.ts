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
import { createPieceInPlace } from '../src/core/pieces.js';
import type { GameState, MoveOrAttackCommand } from '../src/core/types.js';
import { getCardDefinition } from '../src/data/cards.js';
import { clearAllPieces, makeState, setAction } from './helpers.js';

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
      schema: 'warlord.as2-battle-receipt.v1',
      status: 'accepted',
      sessionId: envelope.request.sessionId,
      requestId: envelope.request.requestId,
      inputDigest: envelope.inputDigest,
      petProjectionProfile: 'catalog_identifier+strategic_progression_v1',
      playerPetSnapshotUsed: false,
      winner: 'attacker',
      reason: 'wiped',
      frames: 180,
      durationMs: 6000,
      attackerUnits: [{
        pieceId: 'pet-red-12', factionId: 'red', petId: 12,
        identifier: attackerDefinition.identifier, level: 1, strategicPromotions: [],
        hpPermille: 625, alive: true,
      }],
      defenderUnits: [{
        pieceId: 'pet-blue-15', factionId: 'blue', petId: 15,
        identifier: defenderDefinition.identifier, level: 1, strategicPromotions: [],
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
            pieceId: 'pet-red-12', petId: 12, identifier: attackerDefinition.identifier,
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
            pieceId: 'pet-blue-15', petId: 15, identifier: defenderDefinition.identifier,
            strategicPromotions: [], strategicGoldValue: 60,
            basePrice: 10000, kPrice: 0, increasePrice: 0,
            hpPermille: 0, lost: true,
          }],
        },
      },
    },
  };
}

test('Phase C canonical digest 与对象键插入顺序无关', async () => {
  const left = { z: 1, nested: { b: 2, a: [3, { y: 4, x: 5 }] } };
  const right = { nested: { a: [3, { x: 5, y: 4 }], b: 2 }, z: 1 };
  assert.equal(canonicalJson(left), canonicalJson(right));
  assert.equal(await sha256Canonical(left), await sha256Canonical(right));
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
  assert.equal(result.state.pieces['pet-red-12']?.nodeId, 'North-Choke');
  assert.equal(result.state.pieces['pet-red-12']?.hp,
    Math.round((envelope.request.state.pieces['pet-red-12']?.maxHp ?? 0) * 0.625));
  assert.equal(result.state.pieces['pet-blue-15'], undefined);
  assert.equal(result.state.factions.red.actionPoints, 3);
  assert.equal(result.state.casualtyLedger.length, 1);
  assert.equal(result.battleRecord?.authority?.authority, 'as2');
  assert.equal(result.battleRecord?.authority?.economyObservation.writesPlayerState, false);
  assert.equal(result.battleRecord?.authority?.economyObservation.catalogPriceBasis, 'xml_base_price');
  assert.equal(result.battleRecord?.result.finalRngState, 0);
});

test('Phase C unknown 回执保持冻结战略态并要求阻断继续结算', async () => {
  const envelope = await envelopeFixture();
  const resume = acceptedResume(envelope);
  resume.receipt = {
    schema: 'warlord.as2-battle-receipt.v1',
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
    schema: 'warlord.as2-battle-receipt.v1',
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
});
