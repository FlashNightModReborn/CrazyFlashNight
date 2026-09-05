import type {
  EncounterDefinitionId,
  EncounterDefinitionV1,
  EncounterDistanceBand,
  EncounterProfileDefinitionV1,
  EncounterProfileId,
  EncounterValidationResult,
  StrategyValidationIssue,
  StrategyValidationReasonCode,
} from './definitions.js';
import { isRecord, normalizeOneOrMany } from './normalize.js';

export const ENCOUNTER_SPAWN_DISTANCE_MIN = 180;
export const ENCOUNTER_SPAWN_DISTANCE_MAX = 750;

const OPAQUE_ID_PATTERN = /^[A-Za-z0-9][A-Za-z0-9._~-]{0,159}$/;
const ROOT_FIELDS = new Set(['schemaVersion', 'id', 'rulesVersion', 'profiles']);
const PROFILE_FIELDS = new Set(['id', 'distanceBand', 'spawnDistance']);
const DISTANCE_BANDS = Object.freeze(['near', 'medium', 'far'] as const);
const DISTANCE_BAND_SET = new Set<EncounterDistanceBand>(DISTANCE_BANDS);
const FROZEN_PROFILE_CATALOG = Object.freeze({
  'encounter.near': Object.freeze({ distanceBand: 'near', spawnDistance: 180 }),
  'encounter.medium': Object.freeze({ distanceBand: 'medium', spawnDistance: 360 }),
  'encounter.far': Object.freeze({ distanceBand: 'far', spawnDistance: 650 }),
} as const);

function valueType(value: unknown): string {
  if (value === null) return 'null';
  if (Array.isArray(value)) return 'array';
  return typeof value;
}

function addIssue(
  issues: StrategyValidationIssue[],
  reasonCode: StrategyValidationReasonCode,
  path: string,
  params: Record<string, unknown>,
): void {
  issues.push(Object.freeze({ reasonCode, path, params: Object.freeze({ ...params }) }));
}

function rejectUnexpectedFields(
  value: Readonly<Record<string, unknown>>,
  allowed: ReadonlySet<string>,
  path: string,
  issues: StrategyValidationIssue[],
): void {
  for (const field of Object.keys(value).sort()) {
    if (!allowed.has(field)) addIssue(issues, 'unexpected_field', `${path}.${field}`, { field });
  }
}

function readId(
  value: unknown,
  path: string,
  kind: string,
  issues: StrategyValidationIssue[],
): string | null {
  if (typeof value !== 'string' || !OPAQUE_ID_PATTERN.test(value)) {
    addIssue(issues, 'invalid_opaque_id', path, {
      kind,
      actualType: valueType(value),
      pattern: OPAQUE_ID_PATTERN.source,
    });
    return null;
  }
  return value;
}

function readText(value: unknown, path: string, issues: StrategyValidationIssue[]): string | null {
  if (typeof value !== 'string' || value.length === 0 || value.trim() !== value) {
    addIssue(issues, 'invalid_text', path, {
      actualType: valueType(value),
      requirement: 'non-empty string without surrounding whitespace',
    });
    return null;
  }
  return value;
}

function readSpawnDistance(
  value: unknown,
  path: string,
  issues: StrategyValidationIssue[],
): number | null {
  if (typeof value !== 'number'
    || !Number.isSafeInteger(value)
    || value < ENCOUNTER_SPAWN_DISTANCE_MIN
    || value > ENCOUNTER_SPAWN_DISTANCE_MAX) {
    addIssue(issues, 'invalid_number', path, {
      actualType: valueType(value),
      integer: true,
      minimum: ENCOUNTER_SPAWN_DISTANCE_MIN,
      maximum: ENCOUNTER_SPAWN_DISTANCE_MAX,
    });
    return null;
  }
  return value;
}

export function validateEncounterDefinition(input: unknown): EncounterValidationResult {
  const issues: StrategyValidationIssue[] = [];
  if (!isRecord(input)) {
    addIssue(issues, 'invalid_type', '$', { expected: 'object', actualType: valueType(input) });
    return Object.freeze({ ok: false, issues: Object.freeze(issues) });
  }

  rejectUnexpectedFields(input, ROOT_FIELDS, '$', issues);
  if (input.schemaVersion !== 1) {
    addIssue(issues, 'unsupported_schema_version', '$.schemaVersion', {
      expected: 1,
      actual: input.schemaVersion,
    });
  }
  const id = readId(input.id, '$.id', 'encounter-definition', issues);
  const rulesVersion = readText(input.rulesVersion, '$.rulesVersion', issues);
  if (!Object.prototype.hasOwnProperty.call(input, 'profiles')) {
    addIssue(issues, 'invalid_type', '$.profiles', {
      expected: 'one-or-many encounter profiles',
      actualType: 'undefined',
    });
  }

  const profiles: EncounterProfileDefinitionV1[] = [];
  const profileFirstPath = new Map<string, string>();
  const bandFirstPath = new Map<EncounterDistanceBand, string>();
  for (const [index, value] of normalizeOneOrMany(input.profiles).entries()) {
    const path = `$.profiles[${index}]`;
    if (!isRecord(value)) {
      addIssue(issues, 'invalid_type', path, { expected: 'object', actualType: valueType(value) });
      continue;
    }
    const issueStart = issues.length;
    rejectUnexpectedFields(value, PROFILE_FIELDS, path, issues);
    const profileId = readId(value.id, `${path}.id`, 'encounter-profile', issues);
    if (profileId !== null) {
      const firstPath = profileFirstPath.get(profileId);
      if (firstPath !== undefined) {
        addIssue(issues, 'duplicate_id', `${path}.id`, {
          kind: 'encounter-profile',
          id: profileId,
          firstPath,
        });
      } else {
        profileFirstPath.set(profileId, `${path}.id`);
      }
      if (!(profileId in FROZEN_PROFILE_CATALOG)) {
        addIssue(issues, 'unknown_reference', `${path}.id`, {
          kind: 'encounter-profile-catalog',
          reference: profileId,
          allowed: Object.keys(FROZEN_PROFILE_CATALOG),
        });
      }
    }

    const distanceBand = typeof value.distanceBand === 'string'
      && DISTANCE_BAND_SET.has(value.distanceBand as EncounterDistanceBand)
      ? value.distanceBand as EncounterDistanceBand
      : null;
    if (distanceBand === null) {
      addIssue(issues, 'unknown_reference', `${path}.distanceBand`, {
        kind: 'encounter-distance-band',
        reference: value.distanceBand,
        allowed: DISTANCE_BANDS,
      });
    } else {
      const firstPath = bandFirstPath.get(distanceBand);
      if (firstPath !== undefined) {
        addIssue(issues, 'duplicate_id', `${path}.distanceBand`, {
          kind: 'encounter-distance-band',
          id: distanceBand,
          firstPath,
        });
      } else {
        bandFirstPath.set(distanceBand, `${path}.distanceBand`);
      }
    }
    const spawnDistance = readSpawnDistance(value.spawnDistance, `${path}.spawnDistance`, issues);
    const catalogEntry = profileId === null
      ? undefined
      : FROZEN_PROFILE_CATALOG[profileId as keyof typeof FROZEN_PROFILE_CATALOG];
    if (catalogEntry !== undefined && distanceBand !== null
      && distanceBand !== catalogEntry.distanceBand) {
      addIssue(issues, 'unknown_reference', `${path}.distanceBand`, {
        kind: 'encounter-profile-distance-band',
        profileId,
        expected: catalogEntry.distanceBand,
        actual: distanceBand,
      });
    }
    if (catalogEntry !== undefined && spawnDistance !== null
      && spawnDistance !== catalogEntry.spawnDistance) {
      addIssue(issues, 'invalid_number', `${path}.spawnDistance`, {
        kind: 'encounter-profile-spawn-distance',
        profileId,
        expected: catalogEntry.spawnDistance,
        actual: spawnDistance,
      });
    }
    if (
      issues.length === issueStart
      && profileId !== null
      && distanceBand !== null
      && spawnDistance !== null
    ) {
      profiles.push(Object.freeze({
        id: profileId as EncounterProfileId,
        distanceBand,
        spawnDistance,
      }));
    }
  }

  const missingBands = DISTANCE_BANDS.filter((band) => !bandFirstPath.has(band));
  if (missingBands.length > 0 || bandFirstPath.size !== DISTANCE_BANDS.length) {
    addIssue(issues, 'coverage_mismatch', '$.profiles', {
      kind: 'encounter-distance-band',
      expected: DISTANCE_BANDS,
      missing: missingBands,
    });
  }

  if (issues.length > 0) {
    return Object.freeze({ ok: false, issues: Object.freeze(issues) });
  }
  if (id === null || rulesVersion === null) {
    throw new Error('Encounter validation invariant failed after a successful validation pass.');
  }
  const definition: EncounterDefinitionV1 = Object.freeze({
    schemaVersion: 1,
    id: id as EncounterDefinitionId,
    rulesVersion,
    profiles: Object.freeze(profiles),
  });
  return Object.freeze({ ok: true, definition, issues: [] as const });
}
