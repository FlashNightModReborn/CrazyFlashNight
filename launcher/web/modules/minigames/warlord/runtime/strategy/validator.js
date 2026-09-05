import { validateEncounterDefinition } from './encounter.js';
import { isRecord, normalizeMapDefinitionInput } from './normalize.js';
const OPAQUE_ID_PATTERN = /^[A-Za-z0-9][A-Za-z0-9._~-]{0,159}$/;
const CONFIG_DIGEST_PATTERN = /^sha256:[0-9A-F]{64}$/;
const MAP_FIELDS = new Set([
    'schemaVersion',
    'id',
    'rulesVersion',
    'encounterDefinitionRef',
    'nodes',
    'edges',
]);
const NODE_FIELDS = new Set([
    'id',
    'kind',
    'garrisonCapacity',
    'attackWidth',
    'defenseBonus',
    'nodeAPBonus',
    'encounterProfileRef',
]);
const EDGE_FIELDS = new Set(['id', 'a', 'b']);
function valueType(value) {
    if (value === null)
        return 'null';
    if (Array.isArray(value))
        return 'array';
    return typeof value;
}
function freezeParamValue(value) {
    if (Array.isArray(value))
        return Object.freeze(value.map(freezeParamValue));
    if (isRecord(value)) {
        const frozenEntries = Object.entries(value)
            .map(([key, entry]) => [key, freezeParamValue(entry)]);
        return Object.freeze(Object.fromEntries(frozenEntries));
    }
    return value;
}
function addIssue(issues, reasonCode, path, params) {
    const frozenParams = Object.freeze(Object.fromEntries(Object.entries(params).map(([key, value]) => [key, freezeParamValue(value)])));
    issues.push(Object.freeze({ reasonCode, path, params: frozenParams }));
}
function rejectUnexpectedFields(value, allowedFields, path, issues) {
    for (const field of Object.keys(value).sort()) {
        if (!allowedFields.has(field)) {
            addIssue(issues, 'unexpected_field', `${path}.${field}`, { field });
        }
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
function readNumber(value, path, issues, options) {
    const valid = typeof value === 'number'
        && Number.isFinite(value)
        && (!options.integer || Number.isInteger(value))
        && value >= options.minimum;
    if (!valid) {
        addIssue(issues, 'invalid_number', path, {
            actualType: valueType(value),
            integer: options.integer,
            minimum: options.minimum,
        });
        return null;
    }
    return value;
}
function collectComponents(nodeIds, edges) {
    const adjacency = new Map(nodeIds.map((nodeId) => [nodeId, []]));
    for (const edge of edges) {
        adjacency.get(edge.a)?.push(edge.b);
        adjacency.get(edge.b)?.push(edge.a);
    }
    const visited = new Set();
    const components = [];
    for (const start of nodeIds) {
        if (visited.has(start))
            continue;
        const component = [];
        const queue = [start];
        visited.add(start);
        for (let cursor = 0; cursor < queue.length; cursor += 1) {
            const current = queue[cursor];
            if (current === undefined)
                continue;
            component.push(current);
            for (const neighbor of adjacency.get(current) ?? []) {
                if (visited.has(neighbor))
                    continue;
                visited.add(neighbor);
                queue.push(neighbor);
            }
        }
        components.push(component);
    }
    return components;
}
function validateEncounterBinding(binding, issues) {
    if (!isRecord(binding)) {
        addIssue(issues, 'invalid_type', '$.encounterDefinitionRef', {
            expected: 'resolved encounter definition binding',
            actualType: valueType(binding),
        });
        return null;
    }
    const definitionResult = validateEncounterDefinition(binding.definition);
    if (!definitionResult.ok) {
        for (const issue of definitionResult.issues) {
            addIssue(issues, issue.reasonCode, `$.encounterDefinition${issue.path === '$' ? '' : issue.path.slice(1)}`, { ...issue.params });
        }
    }
    if (typeof binding.configDigest !== 'string'
        || !CONFIG_DIGEST_PATTERN.test(binding.configDigest)) {
        addIssue(issues, 'invalid_text', '$.encounterConfigDigest', {
            actualType: valueType(binding.configDigest),
            pattern: CONFIG_DIGEST_PATTERN.source,
        });
    }
    if (!definitionResult.ok
        || typeof binding.configDigest !== 'string'
        || !CONFIG_DIGEST_PATTERN.test(binding.configDigest)) {
        return null;
    }
    return Object.freeze({
        definition: definitionResult.definition,
        configDigest: binding.configDigest,
    });
}
export function validateMapDefinition(input, encounterBinding) {
    const issues = [];
    const normalized = normalizeMapDefinitionInput(input);
    if (normalized === null) {
        addIssue(issues, 'invalid_type', '$', {
            expected: 'object',
            actualType: valueType(input),
        });
        return Object.freeze({ ok: false, issues: Object.freeze(issues) });
    }
    rejectUnexpectedFields(normalized.source, MAP_FIELDS, '$', issues);
    if (normalized.schemaVersion !== 1) {
        addIssue(issues, 'unsupported_schema_version', '$.schemaVersion', {
            expected: 1,
            actual: normalized.schemaVersion,
        });
    }
    if (!Object.prototype.hasOwnProperty.call(normalized.source, 'nodes')) {
        addIssue(issues, 'invalid_type', '$.nodes', {
            expected: 'one-or-many object',
            actualType: 'undefined',
        });
    }
    if (!Object.prototype.hasOwnProperty.call(normalized.source, 'edges')) {
        addIssue(issues, 'invalid_type', '$.edges', {
            expected: 'one-or-many object',
            actualType: 'undefined',
        });
    }
    const mapId = readOpaqueId(normalized.id, '$.id', 'map', issues);
    const rulesVersion = readText(normalized.rulesVersion, '$.rulesVersion', issues);
    const encounterDefinitionRef = readOpaqueId(normalized.encounterDefinitionRef, '$.encounterDefinitionRef', 'encounter-definition-reference', issues);
    const resolvedEncounter = validateEncounterBinding(encounterBinding, issues);
    if (encounterDefinitionRef !== null
        && resolvedEncounter !== null
        && encounterDefinitionRef !== resolvedEncounter.definition.id) {
        addIssue(issues, 'unknown_reference', '$.encounterDefinitionRef', {
            kind: 'encounter-definition',
            reference: encounterDefinitionRef,
            expected: resolvedEncounter.definition.id,
        });
    }
    const encounterProfileById = new Map(resolvedEncounter?.definition.profiles.map((profile) => [profile.id, profile]) ?? []);
    const nodeDefinitions = [];
    const uniqueNodeIds = [];
    const nodeFirstPath = new Map();
    for (let index = 0; index < normalized.nodes.length; index += 1) {
        const rawNode = normalized.nodes[index];
        const path = `$.nodes[${index}]`;
        if (!isRecord(rawNode)) {
            addIssue(issues, 'invalid_type', path, {
                expected: 'object',
                actualType: valueType(rawNode),
            });
            continue;
        }
        const issueStart = issues.length;
        rejectUnexpectedFields(rawNode, NODE_FIELDS, path, issues);
        const id = readOpaqueId(rawNode.id, `${path}.id`, 'node', issues);
        let duplicate = false;
        if (id !== null) {
            const firstPath = nodeFirstPath.get(id);
            if (firstPath !== undefined) {
                duplicate = true;
                addIssue(issues, 'duplicate_id', `${path}.id`, {
                    kind: 'node',
                    id,
                    firstPath,
                });
            }
            else {
                nodeFirstPath.set(id, `${path}.id`);
                uniqueNodeIds.push(id);
            }
        }
        const kind = readText(rawNode.kind, `${path}.kind`, issues);
        const garrisonCapacity = readNumber(rawNode.garrisonCapacity, `${path}.garrisonCapacity`, issues, { integer: true, minimum: 1 });
        const attackWidth = readNumber(rawNode.attackWidth, `${path}.attackWidth`, issues, { integer: true, minimum: 1 });
        const defenseBonus = readNumber(rawNode.defenseBonus, `${path}.defenseBonus`, issues, { integer: false, minimum: 0 });
        const nodeAPBonus = rawNode.nodeAPBonus === undefined
            ? 0
            : readNumber(rawNode.nodeAPBonus, `${path}.nodeAPBonus`, issues, { integer: true, minimum: 0 });
        const encounterProfileRef = readOpaqueId(rawNode.encounterProfileRef, `${path}.encounterProfileRef`, 'encounter-profile-reference', issues);
        const encounterProfile = encounterProfileRef === null
            ? undefined
            : encounterProfileById.get(encounterProfileRef);
        if (encounterProfileRef !== null && encounterProfile === undefined) {
            addIssue(issues, 'unknown_reference', `${path}.encounterProfileRef`, {
                kind: 'encounter-profile',
                reference: encounterProfileRef,
            });
        }
        if (garrisonCapacity !== null && attackWidth !== null && attackWidth > garrisonCapacity) {
            addIssue(issues, 'attack_width_exceeds_garrison_capacity', `${path}.attackWidth`, {
                attackWidth,
                garrisonCapacity,
            });
        }
        if (issues.length === issueStart
            && !duplicate
            && id !== null
            && kind !== null
            && garrisonCapacity !== null
            && attackWidth !== null
            && defenseBonus !== null
            && nodeAPBonus !== null
            && encounterProfileRef !== null
            && encounterProfile !== undefined) {
            nodeDefinitions.push(Object.freeze({
                id: id,
                kind,
                garrisonCapacity,
                attackWidth,
                defenseBonus,
                nodeAPBonus,
                encounterProfileRef: encounterProfileRef,
                distanceBand: encounterProfile.distanceBand,
                spawnDistance: encounterProfile.spawnDistance,
            }));
        }
    }
    if (uniqueNodeIds.length === 0) {
        addIssue(issues, 'map_empty', '$.nodes', { minimumNodeCount: 1 });
    }
    const edgeDefinitions = [];
    const edgeFirstPath = new Map();
    const pairFirstEdge = new Map();
    const connectivityEdges = [];
    const knownNodeIds = new Set(uniqueNodeIds);
    for (let index = 0; index < normalized.edges.length; index += 1) {
        const rawEdge = normalized.edges[index];
        const path = `$.edges[${index}]`;
        if (!isRecord(rawEdge)) {
            addIssue(issues, 'invalid_type', path, {
                expected: 'object',
                actualType: valueType(rawEdge),
            });
            continue;
        }
        const issueStart = issues.length;
        rejectUnexpectedFields(rawEdge, EDGE_FIELDS, path, issues);
        const id = readOpaqueId(rawEdge.id, `${path}.id`, 'edge', issues);
        let duplicateId = false;
        if (id !== null) {
            const firstPath = edgeFirstPath.get(id);
            if (firstPath !== undefined) {
                duplicateId = true;
                addIssue(issues, 'duplicate_id', `${path}.id`, {
                    kind: 'edge',
                    id,
                    firstPath,
                });
            }
            else {
                edgeFirstPath.set(id, `${path}.id`);
            }
        }
        const a = readOpaqueId(rawEdge.a, `${path}.a`, 'node-reference', issues);
        const b = readOpaqueId(rawEdge.b, `${path}.b`, 'node-reference', issues);
        let endpointsKnown = true;
        if (a !== null && !knownNodeIds.has(a)) {
            endpointsKnown = false;
            addIssue(issues, 'unknown_reference', `${path}.a`, {
                kind: 'node',
                reference: a,
            });
        }
        if (b !== null && !knownNodeIds.has(b)) {
            endpointsKnown = false;
            addIssue(issues, 'unknown_reference', `${path}.b`, {
                kind: 'node',
                reference: b,
            });
        }
        let selfLoop = false;
        let duplicatePair = false;
        if (a !== null && b !== null) {
            if (a === b) {
                selfLoop = true;
                addIssue(issues, 'self_loop', path, { nodeId: a });
            }
            else {
                const pairKey = a < b ? `${a}\u0000${b}` : `${b}\u0000${a}`;
                const firstEdge = pairFirstEdge.get(pairKey);
                if (firstEdge !== undefined) {
                    duplicatePair = true;
                    addIssue(issues, 'duplicate_edge', path, {
                        a,
                        b,
                        firstEdgeId: firstEdge.id,
                        firstPath: firstEdge.path,
                    });
                }
                else {
                    pairFirstEdge.set(pairKey, { id, path });
                }
            }
        }
        if (a !== null && b !== null && endpointsKnown && !selfLoop && !duplicatePair) {
            connectivityEdges.push({ a, b });
        }
        if (issues.length === issueStart
            && !duplicateId
            && id !== null
            && a !== null
            && b !== null) {
            edgeDefinitions.push(Object.freeze({
                id: id,
                a: a,
                b: b,
            }));
        }
    }
    if (uniqueNodeIds.length > 0) {
        const components = collectComponents(uniqueNodeIds, connectivityEdges);
        if (components.length > 1) {
            addIssue(issues, 'map_disconnected', '$.edges', {
                componentCount: components.length,
                components,
            });
        }
    }
    if (issues.length > 0) {
        return Object.freeze({ ok: false, issues: Object.freeze(issues) });
    }
    if (mapId === null
        || rulesVersion === null
        || encounterDefinitionRef === null
        || resolvedEncounter === null) {
        throw new Error('Map validation invariant failed after a successful validation pass.');
    }
    const definition = Object.freeze({
        schemaVersion: 1,
        id: mapId,
        rulesVersion,
        encounterDefinitionRef: encounterDefinitionRef,
        encounterConfigDigest: resolvedEncounter.configDigest,
        nodes: Object.freeze(nodeDefinitions),
        edges: Object.freeze(edgeDefinitions),
    });
    return Object.freeze({ ok: true, definition, issues: [] });
}
//# sourceMappingURL=validator.js.map