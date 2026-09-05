import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import test from 'node:test';

import {
  buildAs2BattleEnvelope,
  sha256Canonical,
} from '../src/battle/as2-authority.js';
import { auditEncounterState } from '../src/core/encounter.js';
import { createGame } from '../src/core/state.js';
import type { GameState, NodeId } from '../src/core/types.js';
import { validateCommand } from '../src/core/validator.js';
import {
  DEMO_1_ENCOUNTER,
  DEMO_1_ENCOUNTER_AUTHORING,
  DEMO_1_ENCOUNTER_BINDING,
  ENCOUNTER_CONFIG_DIGEST,
} from '../src/data/encounter.js';
import { DEMO_1_MAP_AUTHORING, DEMO_1_MAP_PRESENTATION } from '../src/data/demo1.js';
import { projectNodes, buildActionPreviews } from '../src/app/presenter.js';
import { playerEncounterDistanceText } from '../src/app/player-text-catalog.js';
import { piecesAtNode } from '../src/core/selectors.js';
import {
  exportReplay,
  makeReplay,
  parseReplay,
  replayGame,
} from '../src/replay/replay.js';
import { computeMapContractDigests } from '../src/strategy/digest.js';
import {
  ENCOUNTER_SPAWN_DISTANCE_MIN,
  ENCOUNTER_SPAWN_DISTANCE_MAX,
  validateEncounterDefinition,
} from '../src/strategy/encounter.js';
import type {
  EncounterDefinitionAuthoringV1,
  MapDefinition,
} from '../src/strategy/definitions.js';
import { validateMapDefinition } from '../src/strategy/validator.js';

function mutableEncounterDefinition(): {
  schemaVersion: 1;
  id: string;
  rulesVersion: string;
  profiles: Array<{ id: string; distanceBand?: string; spawnDistance?: number }>;
} {
  return structuredClone(DEMO_1_ENCOUNTER_AUTHORING) as unknown as {
    schemaVersion: 1;
    id: string;
    rulesVersion: string;
    profiles: Array<{ id: string; distanceBand?: string; spawnDistance?: number }>;
  };
}

async function expectAsyncFailure(
  operation: () => Promise<unknown>,
  pattern: RegExp,
): Promise<void> {
  let failure: unknown;
  try {
    await operation();
  } catch (error) {
    failure = error;
  }
  assert.ok(failure instanceof Error, 'expected asynchronous operation to fail');
  assert.match(failure.message, pattern);
}

function validatedDemoMap(): MapDefinition {
  const result = validateMapDefinition(DEMO_1_MAP_AUTHORING, DEMO_1_ENCOUNTER_BINDING);
  if (!result.ok) throw new Error(JSON.stringify(result.issues));
  return result.definition;
}

test('EncounterProfile manifest is digest-bound and resolves the exact three-value catalog', async () => {
  const manifestText = String(readFileSync(resolve(
    process.cwd(),
    'src/data/encounter-manifest.json',
  ), 'utf8'));
  const manifest = JSON.parse(manifestText) as unknown;
  assert.deepEqual(manifest, DEMO_1_ENCOUNTER_AUTHORING);
  const validation = validateEncounterDefinition(manifest);
  assert.equal(validation.ok, true, JSON.stringify(validation.issues));
  if (!validation.ok) throw new Error('validated encounter manifest unexpectedly failed');
  assert.deepEqual(validation.definition, DEMO_1_ENCOUNTER);

  const digestBytes = await globalThis.crypto.subtle.digest(
    'SHA-256',
    new TextEncoder().encode(manifestText.replaceAll('\r\n', '\n')),
  );
  const digest = `sha256:${[...new Uint8Array(digestBytes)]
    .map((byte) => byte.toString(16).padStart(2, '0')).join('').toUpperCase()}`;
  assert.equal(digest, ENCOUNTER_CONFIG_DIGEST);
  assert.equal(ENCOUNTER_SPAWN_DISTANCE_MIN, 180);
  assert.equal(ENCOUNTER_SPAWN_DISTANCE_MAX, 750);
  assert.deepEqual(
    DEMO_1_ENCOUNTER.profiles.map((profile) => [profile.id, profile.distanceBand, profile.spawnDistance]),
    [
      ['encounter.near', 'near', 180],
      ['encounter.medium', 'medium', 360],
      ['encounter.far', 'far', 650],
    ],
  );
});

test('EncounterProfile validator rejects unknown, missing, duplicate, out-of-range and mismatched triples', () => {
  const cases: Array<{
    name: string;
    mutate: (definition: ReturnType<typeof mutableEncounterDefinition>) => void;
    reasonCode: string;
    path: string;
  }> = [
    {
      name: 'unknown profile',
      mutate: (definition) => { definition.profiles[0]!.id = 'encounter.unknown'; },
      reasonCode: 'unknown_reference',
      path: '$.profiles[0].id',
    },
    {
      name: 'missing profile field',
      mutate: (definition) => { delete definition.profiles[1]!.distanceBand; },
      reasonCode: 'unknown_reference',
      path: '$.profiles[1].distanceBand',
    },
    {
      name: 'duplicate profile id',
      mutate: (definition) => { definition.profiles[1]!.id = 'encounter.near'; },
      reasonCode: 'duplicate_id',
      path: '$.profiles[1].id',
    },
    {
      name: 'Warlord stage range underflow',
      mutate: (definition) => { definition.profiles[0]!.spawnDistance = 179; },
      reasonCode: 'invalid_number',
      path: '$.profiles[0].spawnDistance',
    },
    {
      name: 'Warlord stage range exceeded',
      mutate: (definition) => { definition.profiles[2]!.spawnDistance = 751; },
      reasonCode: 'invalid_number',
      path: '$.profiles[2].spawnDistance',
    },
    {
      name: 'known profile has the wrong band',
      mutate: (definition) => { definition.profiles[0]!.distanceBand = 'medium'; },
      reasonCode: 'unknown_reference',
      path: '$.profiles[0].distanceBand',
    },
    {
      name: 'known profile has an in-range but wrong distance',
      mutate: (definition) => { definition.profiles[1]!.spawnDistance = 520; },
      reasonCode: 'invalid_number',
      path: '$.profiles[1].spawnDistance',
    },
  ];

  for (const entry of cases) {
    const definition = mutableEncounterDefinition();
    entry.mutate(definition);
    const result = validateEncounterDefinition(definition as EncounterDefinitionAuthoringV1);
    assert.equal(result.ok, false, entry.name);
    assert.ok(result.issues.some((issue) => (
      issue.reasonCode === entry.reasonCode && issue.path === entry.path
    )), `${entry.name}: ${JSON.stringify(result.issues)}`);
  }
});

test('MapDefinition requires every node profile and materializes Demo 1 target-owned distances', () => {
  const definition = validatedDemoMap();
  assert.equal(definition.encounterDefinitionRef, DEMO_1_ENCOUNTER.id);
  assert.equal(definition.encounterConfigDigest, ENCOUNTER_CONFIG_DIGEST);
  assert.deepEqual(
    definition.nodes.map((node) => [node.id, node.encounterProfileRef, node.distanceBand, node.spawnDistance]),
    [
      ['R-HQ', 'encounter.near', 'near', 180],
      ['R-Supply', 'encounter.medium', 'medium', 360],
      ['R-Economy', 'encounter.medium', 'medium', 360],
      ['North-Choke', 'encounter.far', 'far', 650],
      ['Center-Command', 'encounter.far', 'far', 650],
      ['South-Depot', 'encounter.far', 'far', 650],
      ['B-Economy', 'encounter.medium', 'medium', 360],
      ['B-Supply', 'encounter.medium', 'medium', 360],
      ['B-HQ', 'encounter.near', 'near', 180],
    ],
  );

  const missing = structuredClone(DEMO_1_MAP_AUTHORING) as unknown as Record<string, unknown>;
  const missingNodes = missing.nodes as Array<Record<string, unknown>>;
  delete missingNodes[0]!.encounterProfileRef;
  const missingResult = validateMapDefinition(missing, DEMO_1_ENCOUNTER_BINDING);
  assert.equal(missingResult.ok, false);
  assert.ok(missingResult.issues.some((issue) => issue.path === '$.nodes[0].encounterProfileRef'));

  const unknown = structuredClone(DEMO_1_MAP_AUTHORING) as unknown as Record<string, unknown>;
  const unknownNodes = unknown.nodes as Array<Record<string, unknown>>;
  unknownNodes[0]!.encounterProfileRef = 'encounter.unknown';
  const unknownResult = validateMapDefinition(unknown, DEMO_1_ENCOUNTER_BINDING);
  assert.equal(unknownResult.ok, false);
  assert.ok(unknownResult.issues.some((issue) => (
    issue.reasonCode === 'unknown_reference' && issue.path === '$.nodes[0].encounterProfileRef'
  )));
});

test('rules digest includes encounter identity, profile, band and numeric distance without touching presentation', async () => {
  const baseline = validatedDemoMap();
  const changed = structuredClone(baseline) as MapDefinition;
  const changedNode = changed.nodes.find((node) => node.id === 'North-Choke');
  assert.ok(changedNode);
  (changedNode as unknown as { spawnDistance: number }).spawnDistance = 500;
  const baselineDigests = await computeMapContractDigests(baseline, DEMO_1_MAP_PRESENTATION);
  const changedDigests = await computeMapContractDigests(changed, DEMO_1_MAP_PRESENTATION);
  assert.notEqual(baselineDigests.rulesDigest, changedDigests.rulesDigest);
  assert.equal(baselineDigests.presentationDigest, changedDigests.presentationDigest);
});

test('runtime projections expose zero-background Chinese distance guidance for nodes and commands', () => {
  const state = createGame({ seed: 'encounter-runtime-copy', preset: 'all-units' });
  assert.deepEqual(state.encounter, {
    definitionId: DEMO_1_ENCOUNTER.id,
    rulesVersion: DEMO_1_ENCOUNTER.rulesVersion,
    configDigest: ENCOUNTER_CONFIG_DIGEST,
  });
  assert.deepEqual(auditEncounterState(state), []);

  const nodes = new Map(projectNodes(state).map((node) => [node.nodeId, node]));
  assert.equal(nodes.get('R-HQ' as NodeId)?.distanceBand, 'near');
  assert.equal(nodes.get('R-Supply' as NodeId)?.distanceBand, 'medium');
  assert.equal(nodes.get('North-Choke' as NodeId)?.distanceBand, 'far');
  assert.deepEqual(playerEncounterDistanceText('near'), {
    compactLabel: '接敌：近',
    label: '接敌距离：近',
    impact: '很快接战，突击与持续供弹更容易发挥。',
    assistiveText: '接敌距离：近 · 很快接战，突击与持续供弹更容易发挥。',
  });
  assert.equal(playerEncounterDistanceText('medium').impact, '双方都有准备时间。');
  assert.equal(playerEncounterDistanceText('far').impact, '狙击先手时间更长。');

  const selected = piecesAtNode(state, 'R-Supply' as NodeId, 'red')
    .slice(0, 2).map((piece) => piece.pieceId);
  const previews = buildActionPreviews(state, 'R-Supply' as NodeId, selected);
  const attack = previews.find((preview) => preview.targetNodeId === 'North-Choke');
  const move = previews.find((preview) => preview.targetNodeId === 'R-HQ');
  assert.ok(attack);
  assert.equal(attack.isBattle, true);
  assert.deepEqual(
    [attack.encounterProfileRef, attack.distanceBand, attack.spawnDistance],
    ['encounter.far', 'far', 650],
  );
  assert.ok(move);
  assert.deepEqual(
    [move.encounterProfileRef, move.distanceBand, move.spawnDistance],
    ['encounter.near', 'near', 180],
  );
});

test('AS2 frozen battle input binds exact node profiles, preserves wholly legacy input, and rejects partial drift', async () => {
  const state = createGame({ seed: 'encounter-frozen-input', preset: 'all-units' });
  const pieceIds = piecesAtNode(state, 'R-Supply' as NodeId, 'red')
    .slice(0, 2).map((piece) => piece.pieceId);
  const command = {
    type: 'MOVE_OR_ATTACK' as const,
    factionId: 'red' as const,
    pieceIds,
    originNodeId: 'R-Supply' as NodeId,
    targetNodeId: 'North-Choke' as NodeId,
  };
  assert.equal(validateCommand(state, command).ok, true);
  const envelope = await buildAs2BattleEnvelope({
    panelInstanceId: 'warlord.panel.encounter',
    callId: 'warlord.call.encounter',
    sessionId: 'warlord.session.encounter',
    requestId: 'warlord.request.encounter',
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
  const target = envelope.request.state.map.nodes['North-Choke' as NodeId];
  assert.ok(target);
  assert.deepEqual(
    [
      envelope.request.state.encounter.configDigest,
      target.encounterProfileRef,
      target.distanceBand,
      target.spawnDistance,
    ],
    [ENCOUNTER_CONFIG_DIGEST, 'encounter.far', 'far', 650],
  );
  assert.equal(envelope.inputDigest, await sha256Canonical(envelope.request));

  const drifted = structuredClone(state);
  drifted.map.nodes['North-Choke' as NodeId]!.spawnDistance = 500;
  await expectAsyncFailure(
    () => buildAs2BattleEnvelope({
      panelInstanceId: 'warlord.panel.encounter',
      callId: 'warlord.call.encounter-drift',
      sessionId: 'warlord.session.encounter',
      requestId: 'warlord.request.encounter-drift',
      state: drifted,
      command,
      clientContext: envelope.request.clientContext,
    }),
    /node_encounter_distance_mismatch/,
  );

  const swapped = structuredClone(state);
  Object.assign(swapped.map.nodes['R-HQ' as NodeId]!, {
    encounterProfileRef: 'encounter.far',
    distanceBand: 'far',
    spawnDistance: 650,
  });
  await expectAsyncFailure(
    () => buildAs2BattleEnvelope({
      panelInstanceId: 'warlord.panel.encounter',
      callId: 'warlord.call.encounter-profile-swap',
      sessionId: 'warlord.session.encounter',
      requestId: 'warlord.request.encounter-profile-swap',
      state: swapped,
      command,
      clientContext: envelope.request.clientContext,
    }),
    /node_encounter_profile_mismatch/,
  );

  const partial = structuredClone(state) as GameState;
  delete (partial as unknown as Record<string, unknown>).encounter;
  await expectAsyncFailure(
    () => buildAs2BattleEnvelope({
      panelInstanceId: 'warlord.panel.encounter',
      callId: 'warlord.call.encounter-partial',
      sessionId: 'warlord.session.encounter',
      requestId: 'warlord.request.encounter-partial',
      state: partial,
      command,
      clientContext: envelope.request.clientContext,
    }),
    /encounter_sidecar_missing/,
  );

  const legacy = structuredClone(state) as GameState;
  delete (legacy as unknown as Record<string, unknown>).encounter;
  for (const node of Object.values(legacy.map.nodes)) {
    const rawNode = node as unknown as Record<string, unknown>;
    delete rawNode.encounterProfileRef;
    delete rawNode.distanceBand;
    delete rawNode.spawnDistance;
  }
  const legacyEnvelope = await buildAs2BattleEnvelope({
    panelInstanceId: 'warlord.panel.encounter',
    callId: 'warlord.call.encounter-legacy',
    sessionId: 'warlord.session.encounter',
    requestId: 'warlord.request.encounter-legacy',
    state: legacy,
    command,
    clientContext: envelope.request.clientContext,
  });
  const legacyFrozen = legacyEnvelope.request.state as unknown as Record<string, unknown>;
  assert.equal(Object.prototype.hasOwnProperty.call(legacyFrozen, 'encounter'), false);
  assert.equal(Object.values(legacyEnvelope.request.state.map.nodes).some((node) => (
    Object.prototype.hasOwnProperty.call(node, 'encounterProfileRef')
      || Object.prototype.hasOwnProperty.call(node, 'distanceBand')
      || Object.prototype.hasOwnProperty.call(node, 'spawnDistance')
  )), false);
  assert.equal(legacyEnvelope.inputDigest, await sha256Canonical(legacyEnvelope.request));
  assert.deepEqual(
    DEMO_1_ENCOUNTER.profiles.find((profile) => profile.distanceBand === 'far'),
    { id: 'encounter.far', distanceBand: 'far', spawnDistance: 650 },
  );
});

test('replays bind encounter config and reject legacy or mismatched distance rules fail closed', () => {
  const state = createGame({ seed: 'encounter-replay', preset: 'all-units' });
  const replay = makeReplay(state);
  assert.equal(replay.encounterConfigDigest, ENCOUNTER_CONFIG_DIGEST);
  assert.deepEqual(replayGame(replay), state);

  const legacy = JSON.parse(exportReplay(state)) as Record<string, unknown>;
  delete legacy.encounterConfigDigest;
  assert.throws(
    () => parseReplay(JSON.stringify(legacy)),
    /旧录像缺少接敌距离配置摘要/,
  );
  assert.throws(
    () => replayGame({ ...replay, encounterConfigDigest: 'sha256:mismatch' }),
    /录像接敌距离配置摘要不匹配/,
  );
});
