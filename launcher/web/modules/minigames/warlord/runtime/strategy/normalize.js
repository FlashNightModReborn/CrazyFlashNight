export function isRecord(value) {
    return value !== null && typeof value === 'object' && !Array.isArray(value);
}
export function normalizeOneOrMany(value) {
    if (Array.isArray(value))
        return [...value];
    if (value === undefined)
        return [];
    return [value];
}
export function normalizeMapDefinitionInput(input) {
    if (!isRecord(input))
        return null;
    return {
        source: input,
        schemaVersion: input.schemaVersion,
        id: input.id,
        rulesVersion: input.rulesVersion,
        encounterDefinitionRef: input.encounterDefinitionRef,
        nodes: normalizeOneOrMany(input.nodes),
        edges: normalizeOneOrMany(input.edges),
    };
}
//# sourceMappingURL=normalize.js.map