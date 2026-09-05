import { isRecord, normalizeOneOrMany } from '../strategy/normalize.js';
import { validateWarlordScenario } from '../strategy/scenario.js';
import { buildMapIndexes } from '../strategy/topology.js';
import { validateMapDefinition } from '../strategy/validator.js';
import { DEMO_1_MAP_AUTHORING, DEMO_1_MAP_PRESENTATION, DEMO_1_SCENARIO_AUTHORING, } from './demo1.js';
import { DEMO_2_MAP_AUTHORING, DEMO_2_MAP_PRESENTATION, DEMO_2_SCENARIO_AUTHORING, } from './demo2.js';
import { DEMO_1_ENCOUNTER_BINDING } from './encounter.js';
function configurationError(code, path, detail) {
    return new Error(`[warlord-map:${code}] ${path} ${JSON.stringify(detail)}`);
}
function validatePresentation(input, map) {
    if (!isRecord(input))
        throw configurationError('invalid_type', '$.presentation', { expected: 'object' });
    const allowedRoot = new Set(['schemaVersion', 'id', 'mapRef', 'themeRef', 'nodes']);
    for (const key of Object.keys(input)) {
        if (!allowedRoot.has(key))
            throw configurationError('unexpected_field', `$.presentation.${key}`, { key });
    }
    if (input.schemaVersion !== 1) {
        throw configurationError('unsupported_schema_version', '$.presentation.schemaVersion', { expected: 1, actual: input.schemaVersion });
    }
    if (typeof input.id !== 'string' || input.id.length === 0) {
        throw configurationError('invalid_id', '$.presentation.id', { actual: input.id });
    }
    if (input.mapRef !== map.id) {
        throw configurationError('unknown_reference', '$.presentation.mapRef', { expected: map.id, actual: input.mapRef });
    }
    const knownNodeIds = new Set(map.nodes.map((node) => node.id));
    const nodes = [];
    const seen = new Set();
    for (const [index, raw] of normalizeOneOrMany(input.nodes).entries()) {
        const path = `$.presentation.nodes[${index}]`;
        if (!isRecord(raw))
            throw configurationError('invalid_type', path, { expected: 'object' });
        const allowedNode = new Set(['nodeRef', 'x', 'y', 'visualAnchor', 'landmarkAssetRef']);
        for (const key of Object.keys(raw)) {
            if (!allowedNode.has(key))
                throw configurationError('unexpected_field', `${path}.${key}`, { key });
        }
        if (typeof raw.nodeRef !== 'string' || !knownNodeIds.has(raw.nodeRef)) {
            throw configurationError('unknown_reference', `${path}.nodeRef`, { nodeRef: raw.nodeRef });
        }
        if (seen.has(raw.nodeRef))
            throw configurationError('duplicate_id', `${path}.nodeRef`, { nodeRef: raw.nodeRef });
        if (typeof raw.x !== 'number' || !Number.isFinite(raw.x) || typeof raw.y !== 'number' || !Number.isFinite(raw.y)) {
            throw configurationError('invalid_number', path, { x: raw.x, y: raw.y });
        }
        seen.add(raw.nodeRef);
        nodes.push(Object.freeze({ nodeRef: raw.nodeRef, x: raw.x, y: raw.y }));
    }
    const missing = [...knownNodeIds].filter((nodeId) => !seen.has(nodeId));
    if (missing.length > 0 || seen.size !== knownNodeIds.size) {
        throw configurationError('coverage_mismatch', '$.presentation.nodes', { missing });
    }
    return Object.freeze({ id: input.id, nodes: Object.freeze(nodes) });
}
export function buildRuntimeMapBundle(mapInput, presentationInput, scenarioInput, encounterBinding = DEMO_1_ENCOUNTER_BINDING) {
    const mapResult = validateMapDefinition(mapInput, encounterBinding);
    if (!mapResult.ok)
        throw configurationError('invalid_map', '$.map', mapResult.issues);
    const mapDefinition = mapResult.definition;
    const presentation = validatePresentation(presentationInput, mapDefinition);
    const scenarioResult = validateWarlordScenario(scenarioInput, mapDefinition, presentation.id);
    if (!scenarioResult.ok)
        throw configurationError('invalid_scenario', '$.scenario', scenarioResult.issues);
    const scenario = scenarioResult.definition;
    const presentationByNode = new Map(presentation.nodes.map((node) => [node.nodeRef, node]));
    const ruleByNode = new Map(scenario.nodeRules.map((rule) => [rule.nodeRef, rule]));
    const nodeConfigs = Object.create(null);
    for (const node of mapDefinition.nodes) {
        const nodeId = node.id;
        const presentationNode = presentationByNode.get(nodeId);
        const scenarioRule = ruleByNode.get(nodeId);
        if (!presentationNode || !scenarioRule) {
            throw configurationError('coverage_mismatch', `$.nodes.${nodeId}`, {
                presentation: Boolean(presentationNode),
                scenarioRule: Boolean(scenarioRule),
            });
        }
        nodeConfigs[nodeId] = Object.freeze({
            nodeId: node.id,
            displayName: scenarioRule.displayName,
            kind: node.kind,
            capacity: node.garrisonCapacity,
            attackWidth: node.attackWidth,
            defenseWidth: node.garrisonCapacity,
            strategicValue: scenarioRule.strategicValue,
            goldIncome: scenarioRule.goldIncome,
            population: scenarioRule.population,
            apBonus: node.nodeAPBonus,
            productionSlots: scenarioRule.productionSlots,
            defenseBonus: node.defenseBonus,
            encounterProfileRef: node.encounterProfileRef,
            distanceBand: node.distanceBand,
            spawnDistance: node.spawnDistance,
            x: presentationNode.x,
            y: presentationNode.y,
        });
    }
    const mapIndexes = buildMapIndexes(mapDefinition);
    const adjacencyByNode = Object.create(null);
    for (const node of mapDefinition.nodes) {
        adjacencyByNode[node.id] = Object.freeze((mapIndexes.adjacencyByNode[node.id] ?? []).map((entry) => entry.nodeId));
    }
    const initialControlByNode = Object.freeze(Object.fromEntries(scenario.initialState.nodeControls.map((control) => [control.nodeRef, control.factionRef])));
    return Object.freeze({
        mapDefinition,
        encounter: Object.freeze({
            definition: encounterBinding.definition,
            configDigest: encounterBinding.configDigest,
        }),
        mapIndexes,
        scenario,
        nodeConfigs: Object.freeze(nodeConfigs),
        edges: Object.freeze(mapDefinition.edges.map((edge) => Object.freeze({
            a: edge.a,
            b: edge.b,
        }))),
        adjacencyByNode: Object.freeze(adjacencyByNode),
        initialControlByNode,
    });
}
export const DEMO_1_RUNTIME = buildRuntimeMapBundle(DEMO_1_MAP_AUTHORING, DEMO_1_MAP_PRESENTATION, DEMO_1_SCENARIO_AUTHORING, DEMO_1_ENCOUNTER_BINDING);
export const DEMO_2_RUNTIME = buildRuntimeMapBundle(DEMO_2_MAP_AUTHORING, DEMO_2_MAP_PRESENTATION, DEMO_2_SCENARIO_AUTHORING, DEMO_1_ENCOUNTER_BINDING);
export function runtimeMapBundleForScenarioRef(scenarioRef) {
    if (!scenarioRef || scenarioRef === DEMO_1_RUNTIME.scenario.id)
        return DEMO_1_RUNTIME;
    if (scenarioRef === DEMO_2_RUNTIME.scenario.id)
        return DEMO_2_RUNTIME;
    throw configurationError('unknown_reference', '$.scenarioRef', { scenarioRef });
}
export const NODE_CONFIGS = DEMO_1_RUNTIME.nodeConfigs;
export const MAP_EDGES = DEMO_1_RUNTIME.edges;
export const DEMO_1_MAP_DEFINITION = DEMO_1_RUNTIME.mapDefinition;
export const DEMO_1_SCENARIO = DEMO_1_RUNTIME.scenario;
export const DEMO_1_INITIAL_CONTROL = DEMO_1_RUNTIME.initialControlByNode;
export function nodeConfig(nodeId) {
    const config = NODE_CONFIGS[nodeId];
    if (!config)
        throw configurationError('unknown_reference', '$.nodeId', { nodeId });
    return config;
}
export function adjacentNodeIds(nodeId) {
    const adjacent = DEMO_1_RUNTIME.adjacencyByNode[nodeId];
    if (!adjacent)
        throw configurationError('unknown_reference', '$.nodeId', { nodeId });
    // Preserve the legacy command-preview order while topology indexes retain
    // authoring order for graph algorithms and diagnostics.
    return [...adjacent].sort();
}
export function scenarioFaction(factionId) {
    const definition = DEMO_1_SCENARIO.factions.find((faction) => faction.id === factionId);
    if (!definition)
        throw configurationError('unknown_reference', '$.factionId', { factionId });
    return definition;
}
export function initialDeployments(preset) {
    return preset === 'all-units'
        ? DEMO_1_SCENARIO.initialState.allUnitsDeployments
        : DEMO_1_SCENARIO.initialState.standardDeployments;
}
//# sourceMappingURL=map.js.map