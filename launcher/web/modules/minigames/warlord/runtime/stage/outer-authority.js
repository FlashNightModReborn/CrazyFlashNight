const OPAQUE_ID_PATTERN = /^[A-Za-z0-9][A-Za-z0-9._~-]{0,159}$/;
export const STAGE_OUTER_BINDING_SCHEMA = 'warlord.stage-outer-binding.v1';
export const STAGE_OUTER_TERMINAL_SCHEMA = 'warlord.stage-outer-terminal.v1';
export const STAGE_OUTER_ATTEMPT_SCHEMA = 'warlord.stage-outer-attempt.v1';
const EMPTY_ISSUES = Object.freeze([]);
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
const TERMINAL_KINDS = new Set([
    'CompleteSubStage', 'FailStage', 'Suspended', 'Unknown',
]);
function isRecord(value) {
    return value !== null && typeof value === 'object' && !Array.isArray(value);
}
function valueType(value) {
    if (value === null)
        return 'null';
    if (Array.isArray(value))
        return 'array';
    return typeof value;
}
function addIssue(issues, reasonCode, path, params) {
    issues.push(Object.freeze({
        reasonCode,
        path,
        params: Object.freeze({ ...params }),
    }));
}
function success(value) {
    return Object.freeze({ ok: true, value, issues: EMPTY_ISSUES });
}
function failure(issues) {
    return Object.freeze({ ok: false, issues: Object.freeze(issues) });
}
function validateExactKeys(value, expectedKeys, path, issues) {
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
function readOpaqueId(value, path, kind, issues) {
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
function readRevision(value, path, issues) {
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
function readIdentityFields(value, path, issues) {
    const runId = readOpaqueId(value.runId, `${path}.runId`, 'run', issues);
    const subStageId = readOpaqueId(value.subStageId, `${path}.subStageId`, 'sub-stage', issues);
    const scenarioRef = readOpaqueId(value.scenarioRef, `${path}.scenarioRef`, 'scenario-reference', issues);
    const callId = readOpaqueId(value.callId, `${path}.callId`, 'call', issues);
    const revision = readRevision(value.revision, `${path}.revision`, issues);
    if (runId === null
        || subStageId === null
        || scenarioRef === null
        || callId === null
        || revision === null)
        return null;
    return { runId, subStageId, scenarioRef, callId, revision };
}
export function parseStageOuterBinding(input) {
    const issues = [];
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
    if (issues.length > 0 || identity === null)
        return failure(issues);
    return success(Object.freeze({ schema: STAGE_OUTER_BINDING_SCHEMA, ...identity }));
}
export function parseStageOuterTerminal(input) {
    const issues = [];
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
        ? input.terminal
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
export function parseStageOuterAttempt(input) {
    const issues = [];
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
    if (issues.length > 0 || identity === null || reasonCode === null)
        return failure(issues);
    return success(Object.freeze({
        schema: STAGE_OUTER_ATTEMPT_SCHEMA,
        ...identity,
        result: 'not_started',
        reasonCode,
    }));
}
function parseStageOuterEvent(input) {
    if (isRecord(input) && input.schema === STAGE_OUTER_TERMINAL_SCHEMA) {
        const parsed = parseStageOuterTerminal(input);
        if (!parsed.ok)
            return parsed;
        return success(Object.freeze({ kind: 'terminal', envelope: parsed.value }));
    }
    if (isRecord(input) && input.schema === STAGE_OUTER_ATTEMPT_SCHEMA) {
        const parsed = parseStageOuterAttempt(input);
        if (!parsed.ok)
            return parsed;
        return success(Object.freeze({ kind: 'attempt', envelope: parsed.value }));
    }
    const issues = [];
    addIssue(issues, 'invalid_schema', '$.schema', {
        expected: [STAGE_OUTER_TERMINAL_SCHEMA, STAGE_OUTER_ATTEMPT_SCHEMA],
        actual: isRecord(input) ? input.schema : undefined,
    });
    return failure(issues);
}
export function createStageOuterAuthorityState(bindingInput) {
    const parsed = parseStageOuterBinding(bindingInput);
    if (!parsed.ok)
        return parsed;
    return success(Object.freeze({
        phase: 'awaiting_terminal',
        binding: parsed.value,
    }));
}
function issueList(reasonCode, path, params) {
    const issues = [];
    addIssue(issues, reasonCode, path, params);
    return Object.freeze(issues);
}
function rejected(state, reasonCode, issues) {
    return Object.freeze({ ok: false, disposition: 'rejected', reasonCode, state, issues });
}
function identityRejection(state, event) {
    const envelope = event.envelope;
    const stableFields = ['runId', 'subStageId', 'scenarioRef', 'callId'];
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
function sameTerminal(left, right) {
    return left.schema === right.schema
        && left.runId === right.runId
        && left.subStageId === right.subStageId
        && left.scenarioRef === right.scenarioRef
        && left.callId === right.callId
        && left.revision === right.revision
        && left.terminal === right.terminal
        && left.reasonCode === right.reasonCode;
}
export function applyStageOuterEvent(state, eventInput) {
    const parsed = parseStageOuterEvent(eventInput);
    if (!parsed.ok)
        return rejected(state, 'invalid_contract', parsed.issues);
    const identityFailure = identityRejection(state, parsed.value);
    if (identityFailure !== null)
        return identityFailure;
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
            phase: 'not_started',
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
        phase: 'terminal',
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
//# sourceMappingURL=outer-authority.js.map