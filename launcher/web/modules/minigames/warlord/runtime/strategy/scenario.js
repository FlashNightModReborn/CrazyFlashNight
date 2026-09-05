import { isRecord, normalizeOneOrMany } from './normalize.js';
const OPAQUE_ID_PATTERN = /^[A-Za-z0-9][A-Za-z0-9._~-]{0,159}$/;
const ROOT_FIELDS = new Set([
    'schemaVersion',
    'id',
    'rulesVersion',
    'mapRef',
    'mapPresentationRef',
    'playerFactionRef',
    'turnOrder',
    'factions',
    'nodeRules',
    'initialState',
]);
const FACTION_FIELDS = new Set([
    'id',
    'displayName',
    'controller',
    'headquartersNodeRef',
    'supplyNodeRef',
]);
const NODE_RULE_FIELDS = new Set([
    'nodeRef',
    'displayName',
    'strategicValue',
    'goldIncome',
    'population',
    'productionSlots',
]);
const INITIAL_STATE_FIELDS = new Set([
    'nodeControls',
    'standardDeployments',
    'allUnitsDeployments',
]);
const NODE_CONTROL_FIELDS = new Set(['nodeRef', 'factionRef']);
const DEPLOYMENT_FIELDS = new Set(['nodeRef', 'factionRef', 'cardIds']);
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
function rejectUnexpectedFields(source, allowed, path, issues) {
    for (const key of Object.keys(source).sort()) {
        if (!allowed.has(key))
            addIssue(issues, 'unexpected_field', `${path}.${key}`, { field: key });
    }
}
function readId(value, path, kind, issues) {
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
function readText(value, path, issues) {
    if (typeof value !== 'string' || value.length === 0 || value.trim() !== value) {
        addIssue(issues, 'invalid_text', path, {
            actualType: valueType(value),
            requirement: 'non-empty string without surrounding whitespace',
        });
        return null;
    }
    return value;
}
function readInteger(value, path, minimum, issues) {
    if (typeof value !== 'number' || !Number.isInteger(value) || value < minimum) {
        addIssue(issues, 'invalid_number', path, {
            actualType: valueType(value),
            integer: true,
            minimum,
        });
        return null;
    }
    return value;
}
function readKnownNode(value, path, knownNodeIds, issues) {
    const nodeRef = readId(value, path, 'node-reference', issues);
    if (nodeRef !== null && !knownNodeIds.has(nodeRef)) {
        addIssue(issues, 'unknown_reference', path, { kind: 'node', reference: nodeRef });
        return null;
    }
    return nodeRef;
}
function validateSetEquality(actual, expected, path, issues) {
    const actualSet = new Set(actual);
    const expectedSet = new Set(expected);
    const missing = expected.filter((entry) => !actualSet.has(entry));
    const extra = actual.filter((entry) => !expectedSet.has(entry));
    if (actual.length !== actualSet.size || missing.length > 0 || extra.length > 0) {
        addIssue(issues, 'coverage_mismatch', path, { missing, extra, duplicateCount: actual.length - actualSet.size });
    }
}
function parseDeployments(value, path, knownNodeIds, knownFactionIds, controlByNode, issues) {
    const result = [];
    for (const [index, raw] of normalizeOneOrMany(value).entries()) {
        const itemPath = `${path}[${index}]`;
        if (!isRecord(raw)) {
            addIssue(issues, 'invalid_type', itemPath, { expected: 'object', actualType: valueType(raw) });
            continue;
        }
        const issueStart = issues.length;
        rejectUnexpectedFields(raw, DEPLOYMENT_FIELDS, itemPath, issues);
        const nodeRef = readKnownNode(raw.nodeRef, `${itemPath}.nodeRef`, knownNodeIds, issues);
        const factionRef = readId(raw.factionRef, `${itemPath}.factionRef`, 'faction-reference', issues);
        if (factionRef !== null && !knownFactionIds.has(factionRef)) {
            addIssue(issues, 'unknown_reference', `${itemPath}.factionRef`, {
                kind: 'faction',
                reference: factionRef,
            });
        }
        const cardIds = [];
        for (const [cardIndex, cardValue] of normalizeOneOrMany(raw.cardIds).entries()) {
            const cardId = readInteger(cardValue, `${itemPath}.cardIds[${cardIndex}]`, 1, issues);
            if (cardId !== null)
                cardIds.push(cardId);
        }
        if (cardIds.length === 0) {
            addIssue(issues, 'invalid_type', `${itemPath}.cardIds`, {
                expected: 'one-or-many positive integer',
                actualType: valueType(raw.cardIds),
            });
        }
        // cardIds are unit-template references, not entity identities. Repetition is
        // intentional when a deployment contains more than one unit of the same type.
        if (nodeRef !== null && factionRef !== null) {
            const controllingFaction = controlByNode.get(nodeRef);
            if (controllingFaction !== undefined && controllingFaction !== factionRef) {
                addIssue(issues, 'deployment_faction_mismatch', itemPath, {
                    nodeRef,
                    factionRef,
                    controllingFaction: controllingFaction ?? null,
                });
            }
        }
        if (issues.length === issueStart && nodeRef !== null && factionRef !== null) {
            result.push(Object.freeze({
                nodeRef: nodeRef,
                factionRef: factionRef,
                cardIds: Object.freeze(cardIds),
            }));
        }
    }
    return result;
}
export function validateWarlordScenario(input, map, expectedPresentationId) {
    const issues = [];
    if (!isRecord(input)) {
        addIssue(issues, 'invalid_type', '$', { expected: 'object', actualType: valueType(input) });
        return Object.freeze({ ok: false, issues: Object.freeze(issues) });
    }
    rejectUnexpectedFields(input, ROOT_FIELDS, '$', issues);
    if (input.schemaVersion !== 1) {
        addIssue(issues, 'unsupported_schema_version', '$.schemaVersion', { expected: 1, actual: input.schemaVersion });
    }
    const scenarioId = readId(input.id, '$.id', 'scenario', issues);
    const rulesVersion = readText(input.rulesVersion, '$.rulesVersion', issues);
    const mapRef = readId(input.mapRef, '$.mapRef', 'map-reference', issues);
    if (mapRef !== null && mapRef !== map.id) {
        addIssue(issues, 'unknown_reference', '$.mapRef', { kind: 'map', reference: mapRef, expected: map.id });
    }
    const presentationRef = readId(input.mapPresentationRef, '$.mapPresentationRef', 'presentation-reference', issues);
    if (presentationRef !== null && presentationRef !== expectedPresentationId) {
        addIssue(issues, 'unknown_reference', '$.mapPresentationRef', {
            kind: 'map-presentation',
            reference: presentationRef,
            expected: expectedPresentationId,
        });
    }
    const knownNodeIds = new Set(map.nodes.map((node) => node.id));
    const factions = [];
    const factionIds = [];
    const factionFirstPath = new Map();
    for (const [index, raw] of normalizeOneOrMany(input.factions).entries()) {
        const path = `$.factions[${index}]`;
        if (!isRecord(raw)) {
            addIssue(issues, 'invalid_type', path, { expected: 'object', actualType: valueType(raw) });
            continue;
        }
        const issueStart = issues.length;
        rejectUnexpectedFields(raw, FACTION_FIELDS, path, issues);
        const id = readId(raw.id, `${path}.id`, 'faction', issues);
        if (id !== null) {
            const firstPath = factionFirstPath.get(id);
            if (firstPath !== undefined)
                addIssue(issues, 'duplicate_id', `${path}.id`, { kind: 'faction', id, firstPath });
            else {
                factionFirstPath.set(id, `${path}.id`);
                factionIds.push(id);
            }
        }
        const displayName = readText(raw.displayName, `${path}.displayName`, issues);
        const controller = raw.controller === 'player' || raw.controller === 'ai' ? raw.controller : null;
        if (controller === null) {
            addIssue(issues, 'invalid_text', `${path}.controller`, { allowed: ['player', 'ai'], actual: raw.controller });
        }
        const headquartersNodeRef = readKnownNode(raw.headquartersNodeRef, `${path}.headquartersNodeRef`, knownNodeIds, issues);
        const supplyNodeRef = readKnownNode(raw.supplyNodeRef, `${path}.supplyNodeRef`, knownNodeIds, issues);
        if (issues.length === issueStart
            && id !== null
            && displayName !== null
            && controller !== null
            && headquartersNodeRef !== null
            && supplyNodeRef !== null) {
            factions.push(Object.freeze({
                id: id,
                displayName,
                controller,
                headquartersNodeRef: headquartersNodeRef,
                supplyNodeRef: supplyNodeRef,
            }));
        }
    }
    const knownFactionIds = new Set(factionIds);
    const playerFactionRef = readId(input.playerFactionRef, '$.playerFactionRef', 'faction-reference', issues);
    const playerFaction = factions.find((faction) => faction.id === playerFactionRef);
    if (playerFactionRef !== null && (playerFaction?.controller !== 'player' || factions.filter((faction) => faction.controller === 'player').length !== 1)) {
        addIssue(issues, 'player_faction_mismatch', '$.playerFactionRef', {
            playerFactionRef,
            playerController: playerFaction?.controller ?? null,
            playerControllerCount: factions.filter((faction) => faction.controller === 'player').length,
        });
    }
    const turnOrder = normalizeOneOrMany(input.turnOrder)
        .map((entry, index) => readId(entry, `$.turnOrder[${index}]`, 'faction-reference', issues))
        .filter((entry) => entry !== null);
    validateSetEquality(turnOrder, factionIds, '$.turnOrder', issues);
    if (turnOrder[0] !== playerFactionRef) {
        addIssue(issues, 'turn_order_mismatch', '$.turnOrder[0]', { expected: playerFactionRef, actual: turnOrder[0] ?? null });
    }
    const nodeRules = [];
    const nodeRuleIds = [];
    const nodeRuleFirstPath = new Map();
    for (const [index, raw] of normalizeOneOrMany(input.nodeRules).entries()) {
        const path = `$.nodeRules[${index}]`;
        if (!isRecord(raw)) {
            addIssue(issues, 'invalid_type', path, { expected: 'object', actualType: valueType(raw) });
            continue;
        }
        const issueStart = issues.length;
        rejectUnexpectedFields(raw, NODE_RULE_FIELDS, path, issues);
        const nodeRef = readKnownNode(raw.nodeRef, `${path}.nodeRef`, knownNodeIds, issues);
        if (nodeRef !== null) {
            const firstPath = nodeRuleFirstPath.get(nodeRef);
            if (firstPath !== undefined)
                addIssue(issues, 'duplicate_id', `${path}.nodeRef`, { kind: 'node-rule', id: nodeRef, firstPath });
            else {
                nodeRuleFirstPath.set(nodeRef, `${path}.nodeRef`);
                nodeRuleIds.push(nodeRef);
            }
        }
        const displayName = readText(raw.displayName, `${path}.displayName`, issues);
        const strategicValue = readInteger(raw.strategicValue, `${path}.strategicValue`, 0, issues);
        const goldIncome = readInteger(raw.goldIncome, `${path}.goldIncome`, 0, issues);
        const population = readInteger(raw.population, `${path}.population`, 0, issues);
        const productionSlots = readInteger(raw.productionSlots, `${path}.productionSlots`, 0, issues);
        if (issues.length === issueStart
            && nodeRef !== null
            && displayName !== null
            && strategicValue !== null
            && goldIncome !== null
            && population !== null
            && productionSlots !== null) {
            nodeRules.push(Object.freeze({
                nodeRef: nodeRef,
                displayName,
                strategicValue,
                goldIncome,
                population,
                productionSlots,
            }));
        }
    }
    validateSetEquality(nodeRuleIds, [...knownNodeIds], '$.nodeRules', issues);
    const initialState = isRecord(input.initialState) ? input.initialState : null;
    if (initialState === null) {
        addIssue(issues, 'invalid_type', '$.initialState', { expected: 'object', actualType: valueType(input.initialState) });
    }
    else {
        rejectUnexpectedFields(initialState, INITIAL_STATE_FIELDS, '$.initialState', issues);
    }
    const nodeControls = [];
    const controlByNode = new Map();
    for (const [index, raw] of normalizeOneOrMany(initialState?.nodeControls).entries()) {
        const path = `$.initialState.nodeControls[${index}]`;
        if (!isRecord(raw)) {
            addIssue(issues, 'invalid_type', path, { expected: 'object', actualType: valueType(raw) });
            continue;
        }
        const issueStart = issues.length;
        rejectUnexpectedFields(raw, NODE_CONTROL_FIELDS, path, issues);
        const nodeRef = readKnownNode(raw.nodeRef, `${path}.nodeRef`, knownNodeIds, issues);
        const factionRef = readId(raw.factionRef, `${path}.factionRef`, 'faction-reference', issues);
        if (factionRef !== null && !knownFactionIds.has(factionRef)) {
            addIssue(issues, 'unknown_reference', `${path}.factionRef`, { kind: 'faction', reference: factionRef });
        }
        if (nodeRef !== null && controlByNode.has(nodeRef)) {
            addIssue(issues, 'node_control_conflict', `${path}.nodeRef`, {
                nodeRef,
                firstFactionRef: controlByNode.get(nodeRef),
                factionRef,
            });
        }
        if (issues.length === issueStart && nodeRef !== null && factionRef !== null) {
            controlByNode.set(nodeRef, factionRef);
            nodeControls.push(Object.freeze({ nodeRef: nodeRef, factionRef: factionRef }));
        }
    }
    const standardDeployments = parseDeployments(initialState?.standardDeployments, '$.initialState.standardDeployments', knownNodeIds, knownFactionIds, controlByNode, issues);
    const allUnitsDeployments = parseDeployments(initialState?.allUnitsDeployments, '$.initialState.allUnitsDeployments', knownNodeIds, knownFactionIds, controlByNode, issues);
    if (issues.length > 0)
        return Object.freeze({ ok: false, issues: Object.freeze(issues) });
    if (scenarioId === null
        || rulesVersion === null
        || mapRef === null
        || presentationRef === null
        || playerFactionRef === null) {
        throw new Error('Scenario validation invariant failed after a successful validation pass.');
    }
    const definition = Object.freeze({
        schemaVersion: 1,
        id: scenarioId,
        rulesVersion,
        mapRef: mapRef,
        mapPresentationRef: presentationRef,
        playerFactionRef: playerFactionRef,
        turnOrder: Object.freeze(turnOrder),
        factions: Object.freeze(factions),
        nodeRules: Object.freeze(nodeRules),
        initialState: Object.freeze({
            nodeControls: Object.freeze(nodeControls),
            standardDeployments: Object.freeze(standardDeployments),
            allUnitsDeployments: Object.freeze(allUnitsDeployments),
        }),
    });
    return Object.freeze({ ok: true, definition, issues: [] });
}
//# sourceMappingURL=scenario.js.map