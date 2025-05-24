// services/socketServer.js
const net = require('net');
const logger = require('../utils/logger');
const handleEvalTask = require('../controllers/evalTask');
const handleRegexTask = require('../controllers/regexTask');
const handleComputationTask = require('../controllers/computationTask');
const handleAudioTask = require('../controllers/audioTask');


const policyResponse = '<cross-domain-policy><allow-access-from domain="*" to-ports="*" /></cross-domain-policy>\0';

class SocketServer {
    constructor(portList, usedPorts) {
        this.portList = portList;
        this.usedPorts = usedPorts;
        this.socketPort = null;
        this.socketServerInstance = null;
        this.httpPort = null;
    }

    startSocketServer(httpPort, callback) {
        this.httpPort = httpPort;
        this.tryNextPort(0, callback);
    }

    tryNextPort(currentIndex, callback) {
        if (currentIndex >= this.portList.length) {
            logger.error('No available ports found for XMLSocket server.');
            callback(false);
            process.exit(1);
            return;
        }

        const port = this.portList[currentIndex];
        currentIndex++;

        if (this.usedPorts.has(port) || port === this.httpPort) {
            // Skip used ports and the HTTP server port
            this.tryNextPort(currentIndex, callback);
            return;
        }

        const socketServer = net.createServer((socket) => {
            logger.info('XMLSocket client connected');

            // Handle per-socket message buffering
            let buffer = '';

            socket.on('data', (data) => {
                buffer += data.toString();

                // Split messages using '\0' as delimiter
                let parts = buffer.split('\0');
                // Retain the last part (possibly incomplete)
                buffer = parts.pop();

                parts.forEach((message) => {
                    if (message.length === 0) {
                        return;
                    }

                    // Handle policy file request
                    if (message.indexOf('<policy-file-request/>') !== -1) {
                        socket.write(policyResponse);
                        logger.info('Sent policy file to client');
                        return;
                    }

                    logger.info('Received data from AS2 client: ' + message);

                    // Process message
                    const result = this.processSocketMessage(message);

                    // Send result back to AS2 client, append null terminator
                    socket.write(result + '\0');
                    logger.info('Sent response to AS2 client: ' + result);
                });
            });

            socket.on('end', () => {
                logger.info('XMLSocket client disconnected');
            });

            socket.on('error', (err) => {
                logger.error('XMLSocket socket error: ' + err.message);
            });
        });

        socketServer.listen(port, () => {
            logger.info(`XMLSocket server listening on port ${port}`);
            this.socketPort = port;
            this.usedPorts.add(port);
            this.socketServerInstance = socketServer;
            callback(true, port);
        });

        socketServer.on('error', (err) => {
            if (err.code === 'EADDRINUSE') {
                logger.error(`Port ${port} is in use for XMLSocket server, trying next port...`);
                this.tryNextPort(currentIndex, callback);
            } else {
                logger.error('XMLSocket server error: ' + err.message);
                process.exit(1);
            }
        });
    }

    processSocketMessage(message) {
        let parsedMessage;

        try {
            parsedMessage = JSON.parse(message);
        } catch (err) {
            logger.warn('Received a non-JSON message: ' + message);
            return JSON.stringify({ success: false, error: 'Expected JSON format' });
        }

        const { task: taskType, payload, extra = {} } = parsedMessage;

        if (!taskType) {
            return JSON.stringify({ success: false, error: 'No task type provided' });
        }

        switch (taskType) {
            case 'eval':
                return handleEvalTask(payload);
            case 'regex':
                return handleRegexTask(payload, extra);
            case 'computation':
                return handleComputationTask(payload, extra);
            case 'audio':
                return handleAudioTask(payload);
            default:
                return JSON.stringify({ success: false, error: 'Unknown task type' });
        }        
    }
}

module.exports = SocketServer;
