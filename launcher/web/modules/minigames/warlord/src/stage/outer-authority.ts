const OPAQUE_ID_PATTERN = /^[A-Za-z0-9][A-Za-z0-9._~-]{0,159}$/;

export const STAGE_OUTER_BINDING_SCHEMA = 'warlord.stage-outer-binding.v1' as const;
export const STAGE_OUTER_TERMINAL_SCHEMA = 'warlord.stage-outer-terminal.v1' as const;
export const STAGE_OUTER_ATTEMPT_SCHEMA = 'warlord.stage-outer-attempt.v1' as const;

export type StageOuterTerminalKind =
  | 'CompleteSubStage'
  | 'FailStage'
  | 'Suspended'
  | 'Unknown';

export interface StageOuterBindingV1 {
  readonly schema: typeof STAGE_OUTER_BINDING_SCHEMA;
  readonly runId: string;
  readonly subStageId: string;
  readonly scenarioRef: string;
  readonly callId: string;
  readonly revision: number;
}

export interface StageOuterTerminalV1 {
  readonly schema: typeof STAGE_OUTER_TERMINAL_SCHEMA;
  readonly runId: string;
  readonly subStageId: string;
  readonly scenarioRef: string;
  readonly callId: string;
  readonly revision: number;
  readonly terminal: StageOuterTerminalKind;
  readonly reasonCode: string;
}

export interface StageOuterAttemptV1 {
  readonly schema: typeof STAGE_OUTER_ATTEMPT_SCHEMA;
  readonly runId: string;
  readonly subStageId: string;
  readonly scenarioRef: string;
  readonly callId: string;
  readonly revision: number;
  readonly result: 'not_started';
  readonly reasonCode: string;
}

export type StageOuterContractIssueReasonCode =
  | 'invalid_type'
  | 'missing_key'
  | 'unexpected_key'
  | 'invalid_schema'
  | 'invalid_opaque_id'
  | 'invalid_revision'
  | 'invalid_terminal'
  | 'invalid_attempt_result'
  | 'identity_drift'
  | 'terminal_conflict'
  | 'late_event';

export interface StageOuterContractIssue {
  readonly reasonCode: StageOuterContractIssueReasonCode;
  readonly path: string;
  readonly params: Readonly<Record<string, unknown>>;
}

export type StageOuterContractParseResult<T> =
  | {
    readonly ok: true;
    readonly value: T;
    readonly issues: readonly [];
  }
  | {
    readonly ok: false;
    readonly issues: readonly StageOuterContractIssue[];
  };

export type StageOuterEventV1 =
  | { readonly kind: 'terminal'; readonly envelope: StageOuterTerminalV1 }
  | { readonly kind: 'attempt'; readonly envelope: StageOuterAttemptV1 };

export type StageOuterAuthorityState =
  | {
    readonly phase: 'awaiting_terminal';
    readonly binding: StageOuterBindingV1;
  }
  | {
    readonly phase: 'terminal';
    readonly binding: StageOuterBindingV1;
    readonly terminal: StageOuterTerminalV1;
  }
  | {
    readonly phase: 'not_started';
    readonly binding: StageOuterBindingV1;
    readonly attempt: StageOuterAttemptV1;
  };

export type StageOuterApplyResult =
  | {
    readonly ok: true;
    readonly disposition: 'accepted';
    readonly state: Extract<StageOuterAuthorityState, { readonly phase: 'terminal' }>;
    readonly terminal: StageOuterTerminalV1;
  }
  | {
    readonly ok: true;
    readonly disposition: 'duplicate';
    readonly state: Extract<StageOuterAuthorityState, { readonly phase: 'terminal' }>;
    readonly terminal: StageOuterTerminalV1;
  }
  | {
    readonly ok: true;
    readonly disposition: 'not_started';
    readonly state: Extract<StageOuterAuthorityState, { readonly phase: 'not_started' }>;
    readonly attempt: StageOuterAttemptV1;
  }
  | {
    readonly ok: false;
    readonly disposition: 'rejected';
    readonly reasonCode: 'invalid_contract' | 'identity_drift' | 'terminal_conflict' | 'late_event';
    readonly state: StageOuterAuthorityState;
    readonly issues: readonly StageOuterContractIssue[];
  };

const EMPTY_ISSUES = Object.freeze([]) as readonly [];
const BINDING_KEYS = Object.freeze([
  'schema', 'runId', 'subStageId', 'scenarioRef', 'callId', 'revision',
]);
const TERMINAL_KEYS = Object.freeze([
  'schema', 'runId', 'subStageId', 'scenarioRef', 'callId', 'revision',
  'terminal', 'reasonCode',
]);
const ATTEMPT_KEYS = Object.freeze([
  'schema', 'runId', 'subStageId', 'scenarioRef', 'callId', 'revision',
  'result', 'reasonCode',
]);
const TERMINAL_KINDS: ReadonlySet<string> = new Set<StageOuterTerminalKind>([
  'CompleteSubStage', 'FailStage', 'Suspended', 'Unknown',
]);

function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

function valueType(value: unknown): string {
  if (value === null) return 'null';
  if (Array.isArray(value)) return 'array';
  return typeof value;
}

function addIssue(
  issues: StageOuterContractIssue[],
  reasonCode: StageOuterContractIssueReasonCode,
  path: string,
  params: Record<string, unknown>,
): void {
  issues.push(Object.freeze({
    reasonCode,
    path,
    params: Object.freeze({ ...params }),
  }));
}

function success<T>(value: T): StageOuterContractParseResult<T> {
  return Object.freeze({ ok: true, value, issues: EMPTY_ISSUES });
}

function failure<T>(issues: StageOuterContractIssue[]): StageOuterContractParseResult<T> {
  return Object.freeze({ ok: false, issues: Object.freeze(issues) });
}

function validateExactKeys(
  value: Readonly<Record<string, unknown>>,
  expectedKeys: readonly string[],
  path: string,
  issues: StageOuterContractIssue[],
): void {
  const expected = new Set(expectedKeys);
  for (const key of expectedKeys) {
    if (!Object.prototype.hasOwnProperty.call(value, key)) {
      addIssue(issues, 'missing_key', `${path}.${key}`, { key });
    }
  }
  for (const key of Object.keys(value).sort()) {
    if (!expected.has(key)) {
      addIssue(issues, 'unexpected_key', `${path}.${key}`, { key });
    }
  }
  for (const symbol of Object.getOwnPropertySymbols(value)) {
    addIssue(issues, 'unexpected_key', path, { key: String(symbol) });
  }
}

function readOpaqueId(
  value: unknown,
  path: string,
  kind: string,
  issues: StageOuterContractIssue[],
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

function readRevision(
  value: unknown,
  path: string,
  issues: StageOuterContractIssue[],
): number | null {
  if (typeof value !== 'number' || !Number.isSafeInteger(value) || value < 0) {
    addIssue(issues, 'invalid_revision', path, {
      actualType: valueType(value),
      minimum: 0,
      safeInteger: true,
    });
    return null;
  }
  return value;
}

interface ParsedIdentityFields {
  readonly runId: string;
  readonly subStageId: string;
  readonly scenarioRef: string;
  readonly callId: string;
  readonly revision: number;
}

function readIdentityFields(
  value: Readonly<Record<string, unknown>>,
  path: string,
  issues: StageOuterContractIssue[],
): ParsedIdentityFields | null {
  const runId = readOpaqueId(value.runId, `${path}.runId`, 'run', issues);
  const subStageId = readOpaqueId(value.subStageId, `${path}.subStageId`, 'sub-stage', issues);
  const scenarioRef = readOpaqueId(value.scenarioRef, `${path}.scenarioRef`, 'scenario-reference', issues);
  const callId = readOpaqueId(value.callId, `${path}.callId`, 'call', issues);
  const revision = readRevision(value.revision, `${path}.revision`, issues);
  if (
    runId === null
    || subStageId === null
    || scenarioRef === null
    || callId === null
    || revision === null
  ) return null;
  return { runId, subStageId, scenarioRef, callId, revision };
}

export function parseStageOuterBinding(
  input: unknown,
): StageOuterContractParseResult<StageOuterBindingV1> {
  const issues: StageOuterContractIssue[] = [];
  if (!isRecord(input)) {
    addIssue(issues, 'invalid_type', '$', {
      expected: 'object',
      actualType: valueType(input),
    });
    return failure(issues);
  }
  validateExactKeys(input, BINDING_KEYS, '$', issues);
  if (input.schema !== STAGE_OUTER_BINDING_SCHEMA) {
    addIssue(issues, 'invalid_schema', '$.schema', {
      expected: STAGE_OUTER_BINDING_SCHEMA,
      actual: input.schema,
    });
  }
  const identity = readIdentityFields(input, '$', issues);
  if (issues.length > 0 || identity === null) return failure(issues);
  return success(Object.freeze({ schema: STAGE_OUTER_BINDING_SCHEMA, ...identity }));
}

export function parseStageOuterTerminal(
  input: unknown,
): StageOuterContractParseResult<StageOuterTerminalV1> {
  const issues: StageOuterContractIssue[] = [];
  if (!isRecord(input)) {
    addIssue(issues, 'invalid_type', '$', {
      expected: 'object',
      actualType: valueType(input),
    });
    return failure(issues);
  }
  validateExactKeys(input, TERMINAL_KEYS, '$', issues);
  if (input.schema !== STAGE_OUTER_TERMINAL_SCHEMA) {
    addIssue(issues, 'invalid_schema', '$.schema', {
      expected: STAGE_OUTER_TERMINAL_SCHEMA,
      actual: input.schema,
    });
  }
  const identity = readIdentityFields(input, '$', issues);
  const terminal = typeof input.terminal === 'string' && TERMINAL_KINDS.has(input.terminal)
    ? input.terminal as StageOuterTerminalKind
    : null;
  if (terminal === null) {
    addIssue(issues, 'invalid_terminal', '$.terminal', {
      allowed: [...TERMINAL_KINDS],
      actual: input.terminal,
    });
  }
  const reasonCode = readOpaqueId(input.reasonCode, '$.reasonCode', 'reason-code', issues);
  if (issues.length > 0 || identity === null || terminal === null || reasonCode === null) {
    return failure(issues);
  }
  return success(Object.freeze({
    schema: STAGE_OUTER_TERMINAL_SCHEMA,
    ...identity,
    terminal,
    reasonCode,
  }));
}

export function parseStageOuterAttempt(
  input: unknown,
): StageOuterContractParseResult<StageOuterAttemptV1> {
  const issues: StageOuterContractIssue[] = [];
  if (!isRecord(input)) {
    addIssue(issues, 'invalid_type', '$', {
      expected: 'object',
      actualType: valueType(input),
    });
    return failure(issues);
  }
  validateExactKeys(input, ATTEMPT_KEYS, '$', issues);
  if (input.schema !== STAGE_OUTER_ATTEMPT_SCHEMA) {
    addIssue(issues, 'invalid_schema', '$.schema', {
      expected: STAGE_OUTER_ATTEMPT_SCHEMA,
      actual: input.schema,
    });
  }
  const identity = readIdentityFields(input, '$', issues);
  if (input.result !== 'not_started') {
    addIssue(issues, 'invalid_attempt_result', '$.result', {
      expected: 'not_started',
      actual: input.result,
    });
  }
  const reasonCode = readOpaqueId(input.reasonCode, '$.reasonCode', 'reason-code', issues);
  if (issues.length > 0 || identity === null || reasonCode === null) return failure(issues);
  return success(Object.freeze({
    schema: STAGE_OUTER_ATTEMPT_SCHEMA,
    ...identity,
    result: 'not_started',
    reasonCode,
  }));
}

function parseStageOuterEvent(input: unknown): StageOuterContractParseResult<StageOuterEventV1> {
  if (isRecord(input) && input.schema === STAGE_OUTER_TERMINAL_SCHEMA) {
    const parsed = parseStageOuterTerminal(input);
    if (!parsed.ok) return parsed;
    return success(Object.freeze({ kind: 'terminal', envelope: parsed.value }));
  }
  if (isRecord(input) && input.schema === STAGE_OUTER_ATTEMPT_SCHEMA) {
    const parsed = parseStageOuterAttempt(input);
    if (!parsed.ok) return parsed;
    return success(Object.freeze({ kind: 'attempt', envelope: parsed.value }));
  }
  const issues: StageOuterContractIssue[] = [];
  addIssue(issues, 'invalid_schema', '$.schema', {
    expected: [STAGE_OUTER_TERMINAL_SCHEMA, STAGE_OUTER_ATTEMPT_SCHEMA],
    actual: isRecord(input) ? input.schema : undefined,
  });
  return failure(issues);
}

export function createStageOuterAuthorityState(
  bindingInput: unknown,
): StageOuterContractParseResult<StageOuterAuthorityState> {
  const parsed = parseStageOuterBinding(bindingInput);
  if (!parsed.ok) return parsed;
  return success(Object.freeze({
    phase: 'awaiting_terminal',
    binding: parsed.value,
  }));
}

function issueList(
  reasonCode: StageOuterContractIssueReasonCode,
  path: string,
  params: Record<string, unknown>,
): readonly StageOuterContractIssue[] {
  const issues: StageOuterContractIssue[] = [];
  addIssue(issues, reasonCode, path, params);
  return Object.freeze(issues);
}

function rejected(
  state: StageOuterAuthorityState,
  reasonCode: 'invalid_contract' | 'identity_drift' | 'terminal_conflict' | 'late_event',
  issues: readonly StageOuterContractIssue[],
): StageOuterApplyResult {
  return Object.freeze({ ok: false, disposition: 'rejected', reasonCode, state, issues });
}

function identityRejection(
  state: StageOuterAuthorityState,
  event: StageOuterEventV1,
): StageOuterApplyResult | null {
  const envelope = event.envelope;
  const stableFields = ['runId', 'subStageId', 'scenarioRef', 'callId'] as const;
  for (const field of stableFields) {
    if (envelope[field] !== state.binding[field]) {
      return rejected(state, 'identity_drift', issueList('identity_drift', `$.${field}`, {
        expected: state.binding[field],
        actual: envelope[field],
      }));
    }
  }
  if (envelope.revision < state.binding.revision) {
    return rejected(state, 'late_event', issueList('late_event', '$.revision', {
      expected: state.binding.revision,
      actual: envelope.revision,
    }));
  }
  if (envelope.revision > state.binding.revision) {
    return rejected(state, 'identity_drift', issueList('identity_drift', '$.revision', {
      expected: state.binding.revision,
      actual: envelope.revision,
    }));
  }
  return null;
}

function sameTerminal(left: StageOuterTerminalV1, right: StageOuterTerminalV1): boolean {
  return left.schema === right.schema
    && left.runId === right.runId
    && left.subStageId === right.subStageId
    && left.scenarioRef === right.scenarioRef
    && left.callId === right.callId
    && left.revision === right.revision
    && left.terminal === right.terminal
    && left.reasonCode === right.reasonCode;
}

export function applyStageOuterEvent(
  state: StageOuterAuthorityState,
  eventInput: unknown,
): StageOuterApplyResult {
  const parsed = parseStageOuterEvent(eventInput);
  if (!parsed.ok) return rejected(state, 'invalid_contract', parsed.issues);

  const identityFailure = identityRejection(state, parsed.value);
  if (identityFailure !== null) return identityFailure;

  if (state.phase === 'terminal') {
    if (parsed.value.kind === 'attempt') {
      return rejected(state, 'late_event', issueList('late_event', '$.result', {
        acceptedTerminal: state.terminal.terminal,
        actual: parsed.value.envelope.result,
      }));
    }
    if (sameTerminal(state.terminal, parsed.value.envelope)) {
      return Object.freeze({
        ok: true,
        disposition: 'duplicate',
        state,
        terminal: state.terminal,
      });
    }
    return rejected(state, 'terminal_conflict', issueList('terminal_conflict', '$.terminal', {
      acceptedTerminal: state.terminal.terminal,
      acceptedReasonCode: state.terminal.reasonCode,
      actualTerminal: parsed.value.envelope.terminal,
      actualReasonCode: parsed.value.envelope.reasonCode,
    }));
  }

  if (state.phase === 'not_started') {
    return rejected(state, 'late_event', issueList('late_event', '$.schema', {
      acceptedResult: state.attempt.result,
      actualSchema: parsed.value.envelope.schema,
    }));
  }

  if (parsed.value.kind === 'attempt') {
    const notStartedState = Object.freeze({
      phase: 'not_started' as const,
      binding: state.binding,
      attempt: parsed.value.envelope,
    });
    return Object.freeze({
      ok: true,
      disposition: 'not_started',
      state: notStartedState,
      attempt: parsed.value.envelope,
    });
  }

  const terminalState = Object.freeze({
    phase: 'terminal' as const,
    binding: state.binding,
    terminal: parsed.value.envelope,
  });
  return Object.freeze({
    ok: true,
    disposition: 'accepted',
    state: terminalState,
    terminal: parsed.value.envelope,
  });
}
