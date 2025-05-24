// controllers/evalTask.js
const { VM } = require('vm2');
const logger = require('../utils/logger');

function handleEvalTask(code) {
    if (!code) {
        return JSON.stringify({ success: false, error: 'No code provided for eval' });
    }

    try {
        const vm = new VM({
            timeout: 1000,
            sandbox: {},
        });
        let result = vm.run(code);
        return JSON.stringify({ success: true, result: result });
    } catch (err) {
        logger.error('Error executing eval task: ' + err.message);
        return JSON.stringify({ success: false, error: err.message });
    }
}

module.exports = handleEvalTask;
