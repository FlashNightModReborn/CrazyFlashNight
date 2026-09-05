import { validateEncounterDefinition } from '../strategy/encounter.js';
export const ENCOUNTER_CONFIG_DIGEST = 'sha256:6D94E0ABCA11BE5AE1574219D30E4E8E1E3890293496FB2192E081AB24DFE29E';
export const DEMO_1_ENCOUNTER_AUTHORING = {
    schemaVersion: 1,
    id: 'demo1-encounter-distance',
    rulesVersion: 'warlord.encounter-distance.v1',
    profiles: [
        { id: 'encounter.near', distanceBand: 'near', spawnDistance: 180 },
        { id: 'encounter.medium', distanceBand: 'medium', spawnDistance: 360 },
        { id: 'encounter.far', distanceBand: 'far', spawnDistance: 650 },
    ],
};
const validation = validateEncounterDefinition(DEMO_1_ENCOUNTER_AUTHORING);
if (!validation.ok) {
    throw new Error(`[warlord-encounter:invalid_definition] ${JSON.stringify(validation.issues)}`);
}
export const DEMO_1_ENCOUNTER = validation.definition;
export const DEMO_1_ENCOUNTER_BINDING = Object.freeze({
    definition: DEMO_1_ENCOUNTER,
    configDigest: ENCOUNTER_CONFIG_DIGEST,
});
export function encounterProfile(profileId) {
    const profile = DEMO_1_ENCOUNTER.profiles.find((candidate) => candidate.id === profileId);
    if (!profile)
        throw new Error(`Unknown encounter profile ${profileId}.`);
    return profile;
}
//# sourceMappingURL=encounter.js.map