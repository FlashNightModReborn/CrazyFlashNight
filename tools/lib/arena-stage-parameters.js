'use strict';

const stageFocusKeys = new Set(['focusHudRole', 'focusHudLabel', 'focusHudSuccessor']);

// Drop a container only if removing stage metadata emptied it. Other authored
// values, including false, zero, null and deliberately empty containers, survive.
function withoutStageFocus(value) {
    if (value === null || typeof value !== 'object') return value;
    if (Array.isArray(value)) {
        const kept = value.map(withoutStageFocus).filter(item => item !== undefined);
        return value.length && !kept.length ? undefined : kept;
    }
    const entries = Object.entries(value);
    const kept = [];
    for (const [key, child] of entries) {
        if (stageFocusKeys.has(key)) continue;
        const filtered = withoutStageFocus(child);
        if (filtered !== undefined) kept.push([key, filtered]);
    }
    return entries.length && !kept.length ? undefined : Object.fromEntries(kept);
}

function arenaStageParameters(parameters) {
    if (!parameters || typeof parameters !== 'object' || Array.isArray(parameters)
            || !Object.keys(parameters).length) return undefined;
    return withoutStageFocus(parameters);
}

module.exports = { arenaStageParameters };
