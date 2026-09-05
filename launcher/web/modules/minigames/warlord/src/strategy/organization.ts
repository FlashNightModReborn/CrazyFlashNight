import type {
  ArenaFormationId,
  FormationProfileDefinitionV1,
  FormationProfileId,
  FormationSlotRole,
  OrganizationDefinitionV1,
  OrganizationId,
  OrganizationValidationResult,
  StrategyValidationIssue,
  StrategyValidationReasonCode,
  TaskGroupTemplateDefinitionV1,
  TaskGroupTemplateId,
  UnitTemplateMetricsDefinitionV1,
} from './definitions.js';
import { isRecord, normalizeOneOrMany } from './normalize.js';

const OPAQUE_ID_PATTERN = /^[A-Za-z0-9][A-Za-z0-9._~-]{0,159}$/;
const ROOT_FIELDS = new Set([
  'schemaVersion',
  'id',
  'rulesVersion',
  'defaultFormationProfileRef',
  'unitTemplates',
  'taskGroupTemplates',
  'formationProfiles',
]);
const FORMATION_FIELDS = new Set(['id', 'displayName', 'arenaFormationRef', 'slotRoles']);
const UNIT_FIELDS = new Set([
  'cardRef',
  'commandLoad',
  'deploymentSize',
  'encounterCost',
  'apContribution',
]);
const TASK_GROUP_FIELDS = new Set([
  'id',
  'displayName',
  'minimumMembers',
  'maximumMembers',
  'commandLoadDivisor',
  'formationProfileRefs',
]);
const ARENA_FORMATIONS = new Set<ArenaFormationId>(['line', 'column', 'wedge', 'shield', 'grid']);
const SLOT_ROLES = new Set<FormationSlotRole>(['vanguard', 'flank', 'fire_support', 'reserve']);

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

function readInteger(
  value: unknown,
  path: string,
  minimum: number,
  issues: StrategyValidationIssue[],
): number | null {
  if (typeof value !== 'number' || !Number.isSafeInteger(value) || value < minimum) {
    addIssue(issues, 'invalid_number', path, {
      actualType: valueType(value),
      integer: true,
      minimum,
    });
    return null;
  }
  return value;
}

export function validateOrganizationDefinition(input: unknown): OrganizationValidationResult {
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
  const id = readId(input.id, '$.id', 'organization', issues);
  const rulesVersion = readText(input.rulesVersion, '$.rulesVersion', issues);

  const formationProfiles: FormationProfileDefinitionV1[] = [];
  const formationFirstPath = new Map<string, string>();
  for (const [index, value] of normalizeOneOrMany(input.formationProfiles).entries()) {
    const path = `$.formationProfiles[${index}]`;
    if (!isRecord(value)) {
      addIssue(issues, 'invalid_type', path, { expected: 'object', actualType: valueType(value) });
      continue;
    }
    const issueStart = issues.length;
    rejectUnexpectedFields(value, FORMATION_FIELDS, path, issues);
    const profileId = readId(value.id, `${path}.id`, 'formation-profile', issues);
    if (profileId !== null) {
      const firstPath = formationFirstPath.get(profileId);
      if (firstPath !== undefined) {
        addIssue(issues, 'duplicate_id', `${path}.id`, {
          kind: 'formation-profile',
          id: profileId,
          firstPath,
        });
      } else {
        formationFirstPath.set(profileId, `${path}.id`);
      }
    }
    const displayName = readText(value.displayName, `${path}.displayName`, issues);
    const arenaFormationRef = typeof value.arenaFormationRef === 'string'
      && ARENA_FORMATIONS.has(value.arenaFormationRef as ArenaFormationId)
      ? value.arenaFormationRef as ArenaFormationId
      : null;
    if (arenaFormationRef === null) {
      addIssue(issues, 'unknown_reference', `${path}.arenaFormationRef`, {
        kind: 'arena-formation',
        reference: value.arenaFormationRef,
      });
    }
    const slotRoles: FormationSlotRole[] = [];
    for (const [roleIndex, role] of normalizeOneOrMany(value.slotRoles).entries()) {
      if (typeof role !== 'string' || !SLOT_ROLES.has(role as FormationSlotRole)) {
        addIssue(issues, 'unknown_reference', `${path}.slotRoles[${roleIndex}]`, {
          kind: 'formation-slot-role',
          reference: role,
        });
      } else {
        slotRoles.push(role as FormationSlotRole);
      }
    }
    if (slotRoles.length === 0) {
      addIssue(issues, 'invalid_type', `${path}.slotRoles`, {
        expected: 'one-or-many registered slot roles',
        actualType: valueType(value.slotRoles),
      });
    }
    if (
      issues.length === issueStart
      && profileId !== null
      && displayName !== null
      && arenaFormationRef !== null
    ) {
      formationProfiles.push(Object.freeze({
        id: profileId as FormationProfileId,
        displayName,
        arenaFormationRef,
        slotRoles: Object.freeze(slotRoles),
      }));
    }
  }
  if (formationFirstPath.size === 0) {
    addIssue(issues, 'invalid_type', '$.formationProfiles', { expected: 'at least one profile' });
  }

  const unitTemplates: UnitTemplateMetricsDefinitionV1[] = [];
  const unitFirstPath = new Map<number, string>();
  for (const [index, value] of normalizeOneOrMany(input.unitTemplates).entries()) {
    const path = `$.unitTemplates[${index}]`;
    if (!isRecord(value)) {
      addIssue(issues, 'invalid_type', path, { expected: 'object', actualType: valueType(value) });
      continue;
    }
    const issueStart = issues.length;
    rejectUnexpectedFields(value, UNIT_FIELDS, path, issues);
    const cardRef = readInteger(value.cardRef, `${path}.cardRef`, 1, issues);
    if (cardRef !== null) {
      const firstPath = unitFirstPath.get(cardRef);
      if (firstPath !== undefined) {
        addIssue(issues, 'duplicate_id', `${path}.cardRef`, { kind: 'unit-template', id: cardRef, firstPath });
      } else {
        unitFirstPath.set(cardRef, `${path}.cardRef`);
      }
    }
    const commandLoad = readInteger(value.commandLoad, `${path}.commandLoad`, 1, issues);
    const deploymentSize = readInteger(value.deploymentSize, `${path}.deploymentSize`, 1, issues);
    const encounterCost = readInteger(value.encounterCost, `${path}.encounterCost`, 1, issues);
    const apContribution = readInteger(value.apContribution, `${path}.apContribution`, 0, issues);
    if (
      issues.length === issueStart
      && cardRef !== null
      && commandLoad !== null
      && deploymentSize !== null
      && encounterCost !== null
      && apContribution !== null
    ) {
      unitTemplates.push(Object.freeze({
        cardRef,
        commandLoad,
        deploymentSize,
        encounterCost,
        apContribution,
      }));
    }
  }
  if (unitFirstPath.size === 0) {
    addIssue(issues, 'invalid_type', '$.unitTemplates', { expected: 'at least one unit template' });
  }

  const taskGroupTemplates: TaskGroupTemplateDefinitionV1[] = [];
  const taskGroupFirstPath = new Map<string, string>();
  for (const [index, value] of normalizeOneOrMany(input.taskGroupTemplates).entries()) {
    const path = `$.taskGroupTemplates[${index}]`;
    if (!isRecord(value)) {
      addIssue(issues, 'invalid_type', path, { expected: 'object', actualType: valueType(value) });
      continue;
    }
    const issueStart = issues.length;
    rejectUnexpectedFields(value, TASK_GROUP_FIELDS, path, issues);
    const templateId = readId(value.id, `${path}.id`, 'task-group-template', issues);
    if (templateId !== null) {
      const firstPath = taskGroupFirstPath.get(templateId);
      if (firstPath !== undefined) {
        addIssue(issues, 'duplicate_id', `${path}.id`, {
          kind: 'task-group-template',
          id: templateId,
          firstPath,
        });
      } else {
        taskGroupFirstPath.set(templateId, `${path}.id`);
      }
    }
    const displayName = readText(value.displayName, `${path}.displayName`, issues);
    const minimumMembers = readInteger(value.minimumMembers, `${path}.minimumMembers`, 2, issues);
    const maximumMembers = readInteger(value.maximumMembers, `${path}.maximumMembers`, 2, issues);
    const commandLoadDivisor = readInteger(value.commandLoadDivisor, `${path}.commandLoadDivisor`, 1, issues);
    if (minimumMembers !== null && maximumMembers !== null && maximumMembers < minimumMembers) {
      addIssue(issues, 'invalid_number', `${path}.maximumMembers`, {
        minimum: minimumMembers,
        actual: maximumMembers,
      });
    }
    const formationProfileRefs: FormationProfileId[] = [];
    const seenRefs = new Set<string>();
    for (const [refIndex, refValue] of normalizeOneOrMany(value.formationProfileRefs).entries()) {
      const ref = readId(refValue, `${path}.formationProfileRefs[${refIndex}]`, 'formation-profile-reference', issues);
      if (ref === null) continue;
      if (!formationFirstPath.has(ref)) {
        addIssue(issues, 'unknown_reference', `${path}.formationProfileRefs[${refIndex}]`, {
          kind: 'formation-profile',
          reference: ref,
        });
        continue;
      }
      if (seenRefs.has(ref)) {
        addIssue(issues, 'duplicate_id', `${path}.formationProfileRefs[${refIndex}]`, {
          kind: 'formation-profile-reference',
          id: ref,
        });
        continue;
      }
      seenRefs.add(ref);
      formationProfileRefs.push(ref as FormationProfileId);
    }
    if (formationProfileRefs.length === 0) {
      addIssue(issues, 'invalid_type', `${path}.formationProfileRefs`, {
        expected: 'at least one registered formation profile',
      });
    }
    if (
      issues.length === issueStart
      && templateId !== null
      && displayName !== null
      && minimumMembers !== null
      && maximumMembers !== null
      && commandLoadDivisor !== null
    ) {
      taskGroupTemplates.push(Object.freeze({
        id: templateId as TaskGroupTemplateId,
        displayName,
        minimumMembers,
        maximumMembers,
        commandLoadDivisor,
        formationProfileRefs: Object.freeze(formationProfileRefs),
      }));
    }
  }
  if (taskGroupFirstPath.size === 0) {
    addIssue(issues, 'invalid_type', '$.taskGroupTemplates', { expected: 'at least one task-group template' });
  }

  const defaultFormationRef = readId(
    input.defaultFormationProfileRef,
    '$.defaultFormationProfileRef',
    'formation-profile-reference',
    issues,
  );
  if (defaultFormationRef !== null && !formationFirstPath.has(defaultFormationRef)) {
    addIssue(issues, 'unknown_reference', '$.defaultFormationProfileRef', {
      kind: 'formation-profile',
      reference: defaultFormationRef,
    });
  }

  if (issues.length > 0) {
    return Object.freeze({ ok: false, issues: Object.freeze(issues) });
  }
  if (id === null || rulesVersion === null || defaultFormationRef === null) {
    throw new Error('Organization validation invariant failed after a successful validation pass.');
  }
  const definition: OrganizationDefinitionV1 = Object.freeze({
    schemaVersion: 1,
    id: id as OrganizationId,
    rulesVersion,
    defaultFormationProfileRef: defaultFormationRef as FormationProfileId,
    unitTemplates: Object.freeze(unitTemplates),
    taskGroupTemplates: Object.freeze(taskGroupTemplates),
    formationProfiles: Object.freeze(formationProfiles),
  });
  return Object.freeze({ ok: true, definition, issues: [] as const });
}
