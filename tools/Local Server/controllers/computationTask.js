// controllers/computationTask.js
const logger = require('../utils/logger');

function handleComputationTask(payload, extra) {
    if (!extra.data || !Array.isArray(extra.data)) {
        return JSON.stringify({ success: false, error: 'No data array provided for computation' });
    }

    try {
        let sum = extra.data.reduce((a, b) => a + b, 0);
        return JSON.stringify({ success: true, result: sum });
    } catch (err) {
        logger.error('Error executing computation task: ' + err.message);
        return JSON.stringify({ success: false, error: err.message });
    }
}

module.exports = handleComputationTask;
