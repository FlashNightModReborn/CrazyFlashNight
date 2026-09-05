import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import test from 'node:test';

import { generateNextAiAction } from '../src/ai/heuristic.js';
import { requireNode } from '../src/core/access.js';
import { applyCommand } from '../src/core/engine.js';
import {
  auditOrganizationState,
  commandElementFormationProfileIds,
  commandElementMetrics,
  selectedCommandElements,
  selectionOrganizationMetrics,
} from '../src/core/organization.js';
import { createPieceInPlace } from '../src/core/pieces.js';
import type { GameState, NodeId } from '../src/core/types.js';
import {
  DEMO_1_ORGANIZATION,
  DEMO_1_ORGANIZATION_AUTHORING,
  ORGANIZATION_CONFIG_DIGEST,
} from '../src/data/organization.js';
import {
  exportReplay,
  makeReplay,
  parseReplay,
  replayGame,
} from '../src/replay/replay.js';
import { validateOrganizationDefinition } from '../src/strategy/organization.js';
import { validateCommand } from '../src/core/validator.js';
import { clearAllPieces, faction, makeState, setAction } from './helpers.js';

const TASK_GROUP_TEMPLATE_ID = 'demo1.mixed-detachment';
const RED_HQ = 'R-HQ' as NodeId;

function requireElementId(state: GameState, memberId: string): string {
  const elementId = state.organization.memberToElementId[memberId];
  assert.ok(elementId, `missing CommandElement for ${memberId}`);
  return elementId;
}

function applyLegal(state: GameState, command: Parameters<typeof applyCommand>[1]): GameState {
  const result = applyCommand(state, command);
  assert.equal(result.ok, true, result.error);
  return result.state;
}

function mergeMembers(state: GameState, memberIds: readonly string[]): GameState {
  const elementIds = memberIds.map((memberId) => requireElementId(state, memberId));
  return applyLegal(state, {
    type: 'MERGE_TASK_GROUP',
    factionId: 'red',
    nodeId: RED_HQ,
    commandElementIds: elementIds,
    taskGroupTemplateId: TASK_GROUP_TEMPLATE_ID,
    formationProfileId: 'line',
  });
}

function conservedMetrics(metrics: ReturnType<typeof selectionOrganizationMetrics>): object {
  return {
    deploymentSize: metrics.deploymentSize,
    encounterCost: metrics.encounterCost,
    apContribution: metrics.apContribution,
    memberCount: metrics.memberCount,
  };
}

function properNonEmptySubsets<T>(values: readonly T[]): T[][] {
  const subsets: T[][] = [];
  for (let mask = 1; mask < (1 << values.length) - 1; mask += 1) {
    subsets.push(values.filter((_, index) => (mask & (1 << index)) !== 0));
  }
  return subsets;
}

test('every living PieceState begins in exactly one auditable CommandElement', () => {
  for (const preset of ['standard', 'all-units'] as const) {
    const state = makeState(`organization-partition-${preset}`, preset);
    assert.deepEqual(auditOrganizationState(state), []);
    assert.equal(Object.keys(state.organization.memberToElementId).length, Object.keys(state.pieces).length);
    for (const piece of Object.values(state.pieces)) {
      const elementId = requireElementId(state, piece.pieceId);
      const element = state.organization.commandElements[elementId];
      assert.ok(element);
      assert.deepEqual(element.memberIds, [piece.pieceId]);
      assert.equal(element.kind, 'singleton');
      assert.equal(element.nodeId, piece.nodeId);
      assert.equal(element.factionId, piece.factionId);
    }
  }
});

test('merge and every proper partial split preserve member identity and conserved quantities at zero AP', () => {
  const original = makeState('organization-conservation');
  setAction(original, 'red', 37);
  const candidates = requireNode(original, RED_HQ).pieceIds
    .filter((pieceId) => original.pieces[pieceId]?.factionId === 'red')
    .sort();

  for (const memberCount of [2, 3, 4]) {
    const memberIds = candidates.slice(0, memberCount);
    const beforeState = structuredClone(original);
    const beforeMetrics = selectionOrganizationMetrics(beforeState, memberIds);
    const beforePieces = Object.fromEntries(memberIds.map((memberId) => (
      [memberId, structuredClone(beforeState.pieces[memberId])]
    )));
    const beforeAp = faction(beforeState, 'red').actionPoints;
    const beforeSpent = faction(beforeState, 'red').apSpentThisRound;
    const merged = mergeMembers(beforeState, memberIds);
    const mergedElement = merged.organization.commandElements[requireElementId(merged, memberIds[0] ?? '')];
    assert.ok(mergedElement);
    assert.equal(mergedElement.kind, 'task_group');
    assert.deepEqual(mergedElement.memberIds, [...memberIds].sort());
    assert.deepEqual(conservedMetrics(commandElementMetrics(merged, mergedElement)), conservedMetrics(beforeMetrics));
    assert.deepEqual(
      Object.fromEntries(memberIds.map((memberId) => [memberId, merged.pieces[memberId]])),
      beforePieces,
    );
    assert.equal(faction(merged, 'red').actionPoints, beforeAp);
    assert.equal(faction(merged, 'red').apSpentThisRound, beforeSpent);
    assert.deepEqual(auditOrganizationState(merged), []);

    for (const extractedMemberIds of properNonEmptySubsets(memberIds)) {
      const splitBase = structuredClone(merged);
      const split = applyLegal(splitBase, {
        type: 'SPLIT_TASK_GROUP',
        factionId: 'red',
        nodeId: RED_HQ,
        commandElementId: mergedElement.elementId,
        memberIds: extractedMemberIds,
      });
      const afterMetrics = selectionOrganizationMetrics(split, memberIds);
      assert.deepEqual(conservedMetrics(afterMetrics), conservedMetrics(beforeMetrics));
      assert.deepEqual(
        Object.fromEntries(memberIds.map((memberId) => [memberId, split.pieces[memberId]])),
        beforePieces,
      );
      assert.equal(faction(split, 'red').actionPoints, beforeAp);
      assert.equal(faction(split, 'red').apSpentThisRound, beforeSpent);
      assert.deepEqual(auditOrganizationState(split), []);
    }
  }
});

test('formation changes cost zero AP and exact no-op repeats fail without state mutation', () => {
  const initial = makeState('organization-no-op');
  setAction(initial, 'red', 19);
  const memberIds = requireNode(initial, RED_HQ).pieceIds.slice(0, 2);
  const merged = mergeMembers(initial, memberIds);
  const commandElementId = requireElementId(merged, memberIds[0] ?? '');
  const changed = applyCommand(merged, {
    type: 'SET_FORMATION',
    factionId: 'red',
    nodeId: RED_HQ,
    commandElementId,
    formationProfileId: 'wedge',
  });
  assert.equal(changed.ok, true, changed.error);
  assert.equal(faction(changed.state, 'red').actionPoints, 19);
  assert.equal(faction(changed.state, 'red').apSpentThisRound, 0);

  const snapshot = structuredClone(changed.state);
  const duplicate = applyCommand(changed.state, {
    type: 'SET_FORMATION',
    factionId: 'red',
    nodeId: RED_HQ,
    commandElementId,
    formationProfileId: 'wedge',
  });
  assert.equal(duplicate.ok, false);
  assert.equal(duplicate.reasonCode, 'reorganization_selection_invalid');
  assert.equal(duplicate.state, changed.state);
  assert.deepEqual(duplicate.state, snapshot);
});

test('friendly capacity truncation moves only complete CommandElements in request order', () => {
  const initial = makeState('organization-capacity');
  setAction(initial, 'red', 99);
  const memberIds = requireNode(initial, RED_HQ).pieceIds.slice(0, 4);
  const grouped = mergeMembers(initial, memberIds.slice(0, 2));
  requireNode(grouped, 'R-Supply' as NodeId).capacity = 3;

  const moved = applyLegal(grouped, {
    type: 'MOVE_OR_ATTACK',
    factionId: 'red',
    originNodeId: RED_HQ,
    targetNodeId: 'R-Supply' as NodeId,
    pieceIds: memberIds,
  });
  for (const memberId of memberIds.slice(0, 3)) {
    assert.equal(moved.pieces[memberId]?.nodeId, 'R-Supply');
  }
  assert.equal(moved.pieces[memberIds[3] ?? '']?.nodeId, RED_HQ);
  assert.deepEqual(auditOrganizationState(moved), []);
});

test('AI never slices a TaskGroup to fit friendly capacity or attack width', () => {
  const friendly = makeState('organization-ai-friendly');
  setAction(friendly, 'red', 99);
  const allRed = requireNode(friendly, RED_HQ).pieceIds.filter((pieceId) => (
    friendly.pieces[pieceId]?.factionId === 'red'
  ));
  const friendlyGrouped = mergeMembers(friendly, allRed);
  requireNode(friendlyGrouped, 'R-Supply' as NodeId).capacity = 1;
  requireNode(friendlyGrouped, 'R-Economy' as NodeId).capacity = 1;
  assert.equal(generateNextAiAction(friendlyGrouped, 'red'), null);

  const battle = makeState('organization-ai-battle');
  clearAllPieces(battle);
  createPieceInPlace(battle, 'red', 14, RED_HQ, 1, { pieceId: 'red-a' });
  createPieceInPlace(battle, 'red', 12, RED_HQ, 1, { pieceId: 'red-b' });
  createPieceInPlace(battle, 'blue', 15, 'R-Supply' as NodeId, 1, { pieceId: 'blue-a' });
  setAction(battle, 'red', 99);
  const battleGrouped = mergeMembers(battle, ['red-a', 'red-b']);
  requireNode(battleGrouped, 'R-Supply' as NodeId).attackWidth = 1;
  requireNode(battleGrouped, 'R-Economy' as NodeId).capacity = 0;
  assert.equal(generateNextAiAction(battleGrouped, 'red'), null);
});

test('battle preflight rejects mixed formations independently on attacker and defender sides', () => {
  const state = makeState('organization-formation-preflight');
  clearAllPieces(state);
  createPieceInPlace(state, 'red', 14, RED_HQ, 1, { pieceId: 'red-a' });
  createPieceInPlace(state, 'red', 12, RED_HQ, 1, { pieceId: 'red-b' });
  createPieceInPlace(state, 'blue', 15, 'R-Supply' as NodeId, 1, { pieceId: 'blue-a' });
  createPieceInPlace(state, 'blue', 13, 'R-Supply' as NodeId, 1, { pieceId: 'blue-b' });
  setAction(state, 'red', 99);

  const redB = state.organization.commandElements[requireElementId(state, 'red-b')];
  const blueB = state.organization.commandElements[requireElementId(state, 'blue-b')];
  assert.ok(redB);
  assert.ok(blueB);
  redB.formationProfileId = 'wedge';

  const command = {
    type: 'MOVE_OR_ATTACK' as const,
    factionId: 'red' as const,
    originNodeId: RED_HQ,
    targetNodeId: 'R-Supply' as NodeId,
    pieceIds: ['red-b', 'red-a'],
  };
  const attackerMixed = validateCommand(state, command);
  assert.equal(attackerMixed.ok, false);
  assert.equal(attackerMixed.reasonCode, 'formation_mix_unsupported');
  assert.equal(attackerMixed.reasonParams?.side, 'attacker');
  assert.equal(attackerMixed.reasonParams?.formationProfileIds, 'line,wedge');

  redB.formationProfileId = 'line';
  blueB.formationProfileId = 'wedge';
  const defenderMixed = validateCommand(state, command);
  assert.equal(defenderMixed.ok, false);
  assert.equal(defenderMixed.reasonCode, 'formation_mix_unsupported');
  assert.equal(defenderMixed.reasonParams?.side, 'defender');
  assert.equal(defenderMixed.reasonParams?.formationProfileIds, 'line,wedge');

  blueB.formationProfileId = 'line';
  const uniform = validateCommand(state, command);
  assert.equal(uniform.ok, true, uniform.error);
});

test('AI selects one stable formation bucket and never emits a mixed battle command', () => {
  const state = makeState('organization-ai-formation');
  clearAllPieces(state);
  createPieceInPlace(state, 'red', 14, RED_HQ, 1, { pieceId: 'red-a' });
  createPieceInPlace(state, 'red', 12, RED_HQ, 1, { pieceId: 'red-b' });
  createPieceInPlace(state, 'blue', 15, 'R-Supply' as NodeId, 1, { pieceId: 'blue-a' });
  setAction(state, 'red', 99);
  requireNode(state, 'R-Economy' as NodeId).capacity = 0;
  const redB = state.organization.commandElements[requireElementId(state, 'red-b')];
  assert.ok(redB);
  redB.formationProfileId = 'wedge';

  const command = generateNextAiAction(state, 'red');
  assert.ok(command);
  assert.equal(command.targetNodeId, 'R-Supply');
  const selected = selectedCommandElements(state, command.pieceIds);
  assert.equal(selected.complete, true);
  assert.equal(commandElementFormationProfileIds(selected.elements).length, 1);
  assert.equal(validateCommand(state, command).ok, true);

  const reordered = structuredClone(state);
  reordered.organization.commandElements = Object.fromEntries(
    Object.entries(reordered.organization.commandElements).reverse(),
  );
  assert.deepEqual(generateNextAiAction(reordered, 'red'), command);

  createPieceInPlace(state, 'blue', 13, 'R-Supply' as NodeId, 1, { pieceId: 'blue-b' });
  const blueB = state.organization.commandElements[requireElementId(state, 'blue-b')];
  assert.ok(blueB);
  blueB.formationProfileId = 'wedge';
  assert.equal(generateNextAiAction(state, 'red'), null);
});

test('organization-only command history cannot perturb the next battle identity or RNG result', () => {
  const base = makeState('organization-rng');
  clearAllPieces(base);
  createPieceInPlace(base, 'red', 14, 'North-Choke' as NodeId, 1, { pieceId: 'attacker' });
  createPieceInPlace(base, 'blue', 15, 'B-Supply' as NodeId, 1, { pieceId: 'defender' });
  createPieceInPlace(base, 'red', 12, RED_HQ, 1, { pieceId: 'support-a' });
  createPieceInPlace(base, 'red', 13, RED_HQ, 1, { pieceId: 'support-b' });
  setAction(base, 'red', 99);

  const plain = structuredClone(base);
  let reorganized = mergeMembers(structuredClone(base), ['support-a', 'support-b']);
  reorganized = applyLegal(reorganized, {
    type: 'SPLIT_TASK_GROUP',
    factionId: 'red',
    nodeId: RED_HQ,
    commandElementId: requireElementId(reorganized, 'support-a'),
    memberIds: ['support-a'],
  });
  assert.equal(plain.commandSequence, 0);
  assert.equal(reorganized.commandSequence, 2);

  const battleCommand = {
    type: 'MOVE_OR_ATTACK' as const,
    factionId: 'red' as const,
    originNodeId: 'North-Choke' as NodeId,
    targetNodeId: 'B-Supply' as NodeId,
    pieceIds: ['attacker'],
  };
  const plainResult = applyCommand(plain, battleCommand);
  const reorganizedResult = applyCommand(reorganized, battleCommand);
  assert.equal(plainResult.ok, true, plainResult.error);
  assert.equal(reorganizedResult.ok, true, reorganizedResult.error);
  const plainBattle = plainResult.state.battles[0];
  const reorganizedBattle = reorganizedResult.state.battles[0];
  assert.ok(plainBattle);
  assert.ok(reorganizedBattle);
  assert.equal(plainBattle.commandSequence, 1);
  assert.equal(reorganizedBattle.commandSequence, 3);
  assert.equal(plainBattle.battleId, 'b-r1-o1');
  assert.equal(plainBattle.seed, 'organization-rng|1|1|["attacker"]|["defender"]');
  assert.equal(reorganizedBattle.battleId, plainBattle.battleId);
  assert.equal(reorganizedBattle.seed, plainBattle.seed);
  assert.deepEqual(reorganizedBattle.result, plainBattle.result);
});

test('replays bind organization config and reject legacy or mismatched digests fail closed', () => {
  const state = makeState('organization-replay');
  const replay = makeReplay(state);
  assert.equal(replay.organizationConfigDigest, state.organization.configDigest);
  assert.deepEqual(replayGame(replay), state);

  const legacy = JSON.parse(exportReplay(state)) as Record<string, unknown>;
  delete legacy.organizationConfigDigest;
  assert.throws(
    () => parseReplay(JSON.stringify(legacy)),
    /旧录像缺少编制配置摘要/,
  );
  assert.throws(
    () => replayGame({ ...replay, organizationConfigDigest: 'sha256:mismatch' }),
    /录像编制配置摘要不匹配/,
  );
});

test('OrganizationDefinition rejects malformed fields, identities, references, and metrics fail closed', () => {
  type MutableOrganization = {
    unexpected?: boolean;
    unitTemplates: Array<Record<string, unknown>>;
    taskGroupTemplates: Array<Record<string, unknown>>;
    formationProfiles: Array<Record<string, unknown>>;
  } & Record<string, unknown>;
  const makeMutable = (): MutableOrganization => (
    structuredClone(DEMO_1_ORGANIZATION_AUTHORING) as unknown as MutableOrganization
  );
  const cases: Array<{
    name: string;
    mutate: (definition: MutableOrganization) => void;
    reasonCode: string;
    path: string;
  }> = [
    {
      name: 'unknown root field',
      mutate: (definition) => { definition.unexpected = true; },
      reasonCode: 'unexpected_field',
      path: '$.unexpected',
    },
    {
      name: 'duplicate formation identity',
      mutate: (definition) => {
        const first = definition.formationProfiles[0];
        const second = definition.formationProfiles[1];
        if (!first || !second) throw new Error('fixture formations missing');
        second.id = first.id;
      },
      reasonCode: 'duplicate_id',
      path: '$.formationProfiles[1].id',
    },
    {
      name: 'unknown formation reference',
      mutate: (definition) => {
        const taskGroup = definition.taskGroupTemplates[0];
        if (!taskGroup) throw new Error('fixture task-group missing');
        taskGroup.formationProfileRefs = ['missing-profile'];
      },
      reasonCode: 'unknown_reference',
      path: '$.taskGroupTemplates[0].formationProfileRefs[0]',
    },
    {
      name: 'fractional metric',
      mutate: (definition) => {
        const unit = definition.unitTemplates[0];
        if (!unit) throw new Error('fixture unit missing');
        unit.deploymentSize = 1.5;
      },
      reasonCode: 'invalid_number',
      path: '$.unitTemplates[0].deploymentSize',
    },
    {
      name: 'negative metric',
      mutate: (definition) => {
        const unit = definition.unitTemplates[0];
        if (!unit) throw new Error('fixture unit missing');
        unit.apContribution = -1;
      },
      reasonCode: 'invalid_number',
      path: '$.unitTemplates[0].apContribution',
    },
    {
      name: 'zero command-load divisor',
      mutate: (definition) => {
        const taskGroup = definition.taskGroupTemplates[0];
        if (!taskGroup) throw new Error('fixture task-group missing');
        taskGroup.commandLoadDivisor = 0;
      },
      reasonCode: 'invalid_number',
      path: '$.taskGroupTemplates[0].commandLoadDivisor',
    },
  ];

  for (const entry of cases) {
    const definition = makeMutable();
    entry.mutate(definition);
    const result = validateOrganizationDefinition(definition);
    assert.equal(result.ok, false, entry.name);
    assert.ok(result.issues.some((issue) => (
      issue.reasonCode === entry.reasonCode && issue.path === entry.path
    )), `${entry.name}: ${JSON.stringify(result.issues)}`);
  }
});

test('frozen organization manifest matches runtime authoring and declared SHA-256 digest', async () => {
  const manifestText = String(readFileSync(resolve(
    process.cwd(),
    'src/data/organization-manifest.json',
  ), 'utf8'));
  const manifest = JSON.parse(manifestText) as unknown;
  assert.deepEqual(manifest, DEMO_1_ORGANIZATION_AUTHORING);
  const validation = validateOrganizationDefinition(manifest);
  assert.equal(validation.ok, true, JSON.stringify(validation.issues));
  if (!validation.ok) throw new Error('validated organization manifest unexpectedly failed');
  assert.deepEqual(validation.definition, DEMO_1_ORGANIZATION);

  const digestBytes = await globalThis.crypto.subtle.digest(
    'SHA-256',
    new TextEncoder().encode(manifestText.replaceAll('\r\n', '\n')),
  );
  const digest = `sha256:${[...new Uint8Array(digestBytes)]
    .map((byte) => byte.toString(16).padStart(2, '0')).join('').toUpperCase()}`;
  assert.equal(digest, ORGANIZATION_CONFIG_DIGEST);
});

test('partial member movement is rejected while a complete TaskGroup remains legal', () => {
  const initial = makeState('organization-atomic-move');
  setAction(initial, 'red', 99);
  const memberIds = requireNode(initial, RED_HQ).pieceIds.slice(0, 2);
  const grouped = mergeMembers(initial, memberIds);
  const partial = applyCommand(grouped, {
    type: 'MOVE_OR_ATTACK',
    factionId: 'red',
    originNodeId: RED_HQ,
    targetNodeId: 'R-Supply' as NodeId,
    pieceIds: memberIds.slice(0, 1),
  });
  assert.equal(partial.ok, false);
  assert.equal(partial.reasonCode, 'command_element_partial_selection');

  const whole = applyCommand(grouped, {
    type: 'MOVE_OR_ATTACK',
    factionId: 'red',
    originNodeId: RED_HQ,
    targetNodeId: 'R-Supply' as NodeId,
    pieceIds: memberIds,
  });
  assert.equal(whole.ok, true, whole.error);
  assert.equal(selectedCommandElements(whole.state, memberIds).complete, true);
  assert.deepEqual(auditOrganizationState(whole.state), []);
});
