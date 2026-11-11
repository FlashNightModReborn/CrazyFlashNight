'use strict';

// Build-time catalogs must never read player-owned Agent files, including when
// they exist locally. Runtime loading and validation remain in MapTaskCatalog.Load.
function isRuntimeAgentSource(name, expectedName) {
    return ['agent_tasks.json', 'agent_text.json'].includes(expectedName) && name === expectedName;
}

module.exports = { isRuntimeAgentSource };
