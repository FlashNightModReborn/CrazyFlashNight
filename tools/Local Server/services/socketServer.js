// services/socketServer.js
const net = require('net');
const logger = require('../utils/logger');
const handleEvalTask = require('../controllers/evalTask');
const handleRegexTask = require('../controllers/regexTask');
const handleComputationTask = require('../controllers/computationTask');
const handleAudioTask = require('../controllers/audioTask');
const { handleGomokuTask } = require('../controllers/gomokuTask');

// 统一注入 callId：确保 success/error 路径都回传 callId
function wrapResponse(resultString, parsedMessage) {
    if (parsedMessage && parsedMessage.callId !== undefined) {
        try {
            const obj = JSON.parse(resultString);
            obj.callId = parsedMessage.callId;
            return JSON.stringify(obj);
        } catch (e) { /* keep original */ }
    }
    return resultString;
}

const policyResponse = '<cross-domain-policy><allow-access-from domain="*" to-ports="*" /></cross-domain-policy>\0';

class SocketServer {
    constructor(portList, usedPorts) {
        this.portList = portList;
        this.usedPorts = usedPorts;
        this.socketPort = null;
        this.socketServerInstance = null;
        this.httpPort = null;
        this.as2Socket = null; // Active AS2 client socket
        this.pendingConsoleCallbacks = []; // Queue of {resolve, timer} for console commands
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
            this.as2Socket = socket;

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

                    // Check if this is a console_result from AS2
                    try {
                        const parsed = JSON.parse(message);
                        if (parsed.task === 'console_result') {
                            this.resolveConsoleCallback(parsed);
                            return;
                        }
                    } catch (e) {
                        // Not JSON or not console_result, proceed normally
                    }

                    // Process message (sync or async)
                    let parsedMsg = null;
                    try { parsedMsg = JSON.parse(message); } catch (e) { /* handled in processSocketMessage */ }

                    const resultOrPromise = this.processSocketMessage(message);

                    if (resultOrPromise && typeof resultOrPromise.then === 'function') {
                        // Async task (e.g. gomoku_eval)
                        resultOrPromise
                            .then(r => {
                                const wrapped = wrapResponse(r, parsedMsg);
                                socket.write(wrapped + '\0');
                                logger.info('Sent async response to AS2 client: ' + wrapped);
                            })
                            .catch(err => {
                                const errResp = JSON.stringify({ success: false, error: err.message });
                                const wrapped = wrapResponse(errResp, parsedMsg);
                                socket.write(wrapped + '\0');
                                logger.error('Async task error: ' + err.message);
                            });
                    } else if (resultOrPromise) {
                        // Sync task
                        const wrapped = wrapResponse(resultOrPromise, parsedMsg);
                        socket.write(wrapped + '\0');
                        logger.info('Sent response to AS2 client: ' + wrapped);
                    }
                });
            });

            socket.on('end', () => {
                logger.info('XMLSocket client disconnected');
                if (this.as2Socket === socket) this.as2Socket = null;
            });

            socket.on('error', (err) => {
                logger.error('XMLSocket socket error: ' + err.message);
                if (this.as2Socket === socket) this.as2Socket = null;
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
            case 'gomoku_eval':
                // 返回 Promise，由上层 async 路径处理
                return handleGomokuTask(payload).then(result =>
                    JSON.stringify({ success: true, task: 'gomoku_eval', result: result })
                );
            default:
                return JSON.stringify({ success: false, error: 'Unknown task type' });
        }        
    }
    // Encode non-ASCII characters as %uXXXX for AS2 unescape() compatibility
    escapeForAS2(str) {
        return str.replace(/[^\x00-\x7F]/g, (c) => {
            return '%u' + ('0000' + c.charCodeAt(0).toString(16).toUpperCase()).slice(-4);
        });
    }

    // Send a console command to AS2 and return a Promise that resolves with the result
    sendConsoleCommand(command, timeoutMs) {
        timeoutMs = timeoutMs || 5000;
        return new Promise((resolve, reject) => {
            if (!this.as2Socket) {
                return reject(new Error('No AS2 client connected'));
            }

            const entry = { resolve: null, timer: null };

            entry.timer = setTimeout(() => {
                const idx = this.pendingConsoleCallbacks.indexOf(entry);
                if (idx !== -1) this.pendingConsoleCallbacks.splice(idx, 1);
                reject(new Error('Console command timed out'));
            }, timeoutMs);

            entry.resolve = resolve;
            this.pendingConsoleCallbacks.push(entry);

            // Encode non-ASCII chars to avoid UTF-8/GBK mismatch over XMLSocket
            const safeCommand = this.escapeForAS2(command);
            const msg = JSON.stringify({ task: 'console', command: safeCommand });
            this.as2Socket.write(msg + '\0');
            logger.info('Sent console command to AS2: ' + command + ' (encoded: ' + safeCommand + ')');
        });
    }

    // Resolve the oldest pending console callback with AS2's result
    resolveConsoleCallback(parsed) {
        logger.info('Received console_result from AS2: ' + JSON.stringify(parsed));
        if (this.pendingConsoleCallbacks.length > 0) {
            const entry = this.pendingConsoleCallbacks.shift();
            clearTimeout(entry.timer);
            entry.resolve(parsed);
        }
    }
}

module.exports = SocketServer;
