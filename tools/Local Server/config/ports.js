// config/ports.js
const logger = require('../utils/logger');

const eyeOf119 = "1192433993";

function isValidPort(port) {
    return port >= 1024 && port <= 65535;
}

function extractPorts() {
    let portList = [];

    // Extract 4-digit ports
    for (let i = 0; i <= eyeOf119.length - 4; i++) {
        const port4 = Number(eyeOf119.substring(i, i + 4));
        if (isValidPort(port4)) {
            portList.push(port4);
            logger.info(`Added port4: ${port4}`);
        }
    }

    // Extract 5-digit ports
    for (let j = 0; j <= eyeOf119.length - 5; j++) {
        const port5 = Number(eyeOf119.substring(j, j + 5));
        if (isValidPort(port5)) {
            portList.push(port5);
            logger.info(`Added port5: ${port5}`);
        }
    }

    // Ensure port 3000 is included
    if (!portList.includes(3000)) {
        portList.push(3000);
        logger.info('Added default port: 3000');
    }

    // Remove duplicates
    portList = [...new Set(portList)];
    logger.info(`Extracted ports: ${portList.join(", ")}`);

    return portList;
}

module.exports = {
    extractPorts,
    isValidPort,
};
