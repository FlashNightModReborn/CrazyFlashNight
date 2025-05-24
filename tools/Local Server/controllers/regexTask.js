// controllers/regexTask.js
const logger = require('../utils/logger');

function handleRegexTask(text, extra) {
    let pattern = extra.pattern;
    let flags = extra.flags || '';

    if (!pattern) {
        return JSON.stringify({ success: false, error: 'No pattern provided' });
    }

    try {
        let regex = new RegExp(pattern, flags);
        let match = regex.exec(text);
        if (match === null) {
            return JSON.stringify({ success: true, match: false });
        }
        return JSON.stringify({ success: true, match: match });
    } catch (err) {
        logger.error('Error executing regex task: ' + err.message);
        return JSON.stringify({ success: false, error: err.message });
    }
}

module.exports = handleRegexTask;
