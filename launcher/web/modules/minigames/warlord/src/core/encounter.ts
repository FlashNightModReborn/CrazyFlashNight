import {
  DEMO_1_ENCOUNTER_BINDING,
} from '../data/encounter.js';
import { runtimeMapBundleForScenarioRef } from '../data/map.js';
import type { EncounterRuntimeState, GameState, NodeId } from './types.js';
import type { EncounterDefinitionBindingV1 } from '../strategy/definitions.js';

export interface EncounterStateIssue {
  readonly code: string;
  readonly path: string;
}

const ENCOUNTER_STATE_FIELDS = Object.freeze(['configDigest', 'definitionId', 'rulesVersion']);
const NODE_ENCOUNTER_FIELDS = Object.freeze([
  'encounterProfileRef',
  'distanceBand',
  'spawnDistance',
] as const);

function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

export function createEncounterRuntimeState(
  binding: EncounterDefinitionBindingV1 = DEMO_1_ENCOUNTER_BINDING,
): EncounterRuntimeState {
  return {
    definitionId: binding.definition.id,
    rulesVersion: binding.definition.rulesVersion,
    configDigest: binding.configDigest,
  };
}

export function auditEncounterState(state: GameState): readonly EncounterStateIssue[] {
  const issues: EncounterStateIssue[] = [];
  let runtimeBundle;
  try {
    runtimeBundle = runtimeMapBundleForScenarioRef(state.scenarioId);
  } catch {
    return Object.freeze([{ code: 'encounter_scenario_unknown', path: '$.scenarioId' }]);
  }
  const encounterBinding = runtimeBundle.encounter;
  const rawState = state as unknown as Record<string, unknown>;
  if (!isRecord(rawState.encounter)) {
    return Object.freeze([{ code: 'encounter_sidecar_missing', path: '$.encounter' }]);
  }
  const fields = Object.keys(rawState.encounter).sort();
  if (fields.length !== ENCOUNTER_STATE_FIELDS.length
    || fields.some((field, index) => field !== ENCOUNTER_STATE_FIELDS[index])) {
    issues.push({ code: 'encounter_sidecar_shape_mismatch', path: '$.encounter' });
  }
  if (state.encounter.definitionId !== encounterBinding.definition.id) {
    issues.push({ code: 'encounter_definition_mismatch', path: '$.encounter.definitionId' });
  }
  if (state.encounter.rulesVersion !== encounterBinding.definition.rulesVersion) {
    issues.push({ code: 'encounter_rules_version_mismatch', path: '$.encounter.rulesVersion' });
  }
  if (state.encounter.configDigest !== encounterBinding.configDigest) {
    issues.push({ code: 'encounter_config_digest_mismatch', path: '$.encounter.configDigest' });
  }

  const expectedNodeIds = Object.keys(runtimeBundle.nodeConfigs).sort();
  const actualNodeIds = Object.keys(state.map.nodes).sort();
  if (actualNodeIds.length !== expectedNodeIds.length
    || actualNodeIds.some((nodeId, index) => nodeId !== expectedNodeIds[index])) {
    issues.push({ code: 'node_encounter_coverage_mismatch', path: '$.map.nodes' });
  }

  const profileById = new Map(encounterBinding.definition.profiles.map((profile) => [profile.id as string, profile]));
  for (const nodeId of expectedNodeIds) {
    const node = state.map.nodes[nodeId as NodeId];
    if (!node) continue;
    const rawNode = node as unknown as Record<string, unknown>;
    const presentCount = NODE_ENCOUNTER_FIELDS.filter((field) => (
      Object.prototype.hasOwnProperty.call(rawNode, field)
    )).length;
    if (presentCount !== NODE_ENCOUNTER_FIELDS.length) {
      issues.push({ code: 'node_encounter_shape_mismatch', path: `$.map.nodes.${nodeId}` });
      continue;
    }
    const profile = typeof rawNode.encounterProfileRef === 'string'
      ? profileById.get(rawNode.encounterProfileRef)
      : undefined;
    if (!profile) {
      issues.push({ code: 'node_encounter_profile_unknown', path: `$.map.nodes.${nodeId}.encounterProfileRef` });
    }
    const expected = runtimeBundle.nodeConfigs[nodeId];
    if (!expected) {
      issues.push({ code: 'node_encounter_coverage_mismatch', path: `$.map.nodes.${nodeId}` });
      continue;
    }
    if (rawNode.encounterProfileRef !== expected.encounterProfileRef) {
      issues.push({ code: 'node_encounter_profile_mismatch', path: `$.map.nodes.${nodeId}.encounterProfileRef` });
    }
    if (rawNode.distanceBand !== expected.distanceBand) {
      issues.push({ code: 'node_encounter_band_mismatch', path: `$.map.nodes.${nodeId}.distanceBand` });
    }
    if (rawNode.spawnDistance !== expected.spawnDistance) {
      issues.push({ code: 'node_encounter_distance_mismatch', path: `$.map.nodes.${nodeId}.spawnDistance` });
    }
  }
  return Object.freeze(issues.map((issue) => Object.freeze(issue)));
}

export function frozenStateHasAnyEncounterFields(value: GameState): boolean {
  const rawState = value as unknown as Record<string, unknown>;
  if (rawState.encounter !== undefined) return true;
  return Object.values(value.map.nodes).some((node) => {
    const rawNode = node as unknown as Record<string, unknown>;
    return NODE_ENCOUNTER_FIELDS.some((field) => (
      Object.prototype.hasOwnProperty.call(rawNode, field)
    ));
  });
}
