'use strict';

const fs = require('fs');
const path = require('path');

// Match MapTaskCatalog's two legacy optional sources. Present malformed data,
// broken links, directories and access failures remain errors.
function legacyAgentSourceMissing(directory, name, optionalName, fail) {
    if (!['agent_tasks.json', 'agent_text.json'].includes(optionalName) || name !== optionalName) return false;
    let stat;
    try { stat = fs.lstatSync(path.join(directory, name)); }
    catch (error) {
        if (error.code === 'ENOENT') return true;
        fail('cannot inspect legacy task source ' + name + ': ' + error.message);
    }
    if (stat.isSymbolicLink() || !stat.isFile()) fail('legacy task source must be a regular file: ' + name);
    return false;
}

module.exports = { legacyAgentSourceMissing };
