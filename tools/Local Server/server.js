// server.js
const express = require('express');
const app = express();
const { extractPorts } = require('./config/ports');
const logger = require('./utils/logger');
const httpRoutes = require('./routes/httpRoutes');
const SocketServer = require('./services/socketServer');

let portList = extractPorts();
let usedPorts = new Set();
let portIndex = 0;
let retryCount = 0;
const maxRetries = 5;

// Initialize variables
let server; // HTTP server instance
let socketServer; // SocketServer instance

// Middleware and configurations
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

// CORS settings
app.use((req, res, next) => {
    res.header("Access-Control-Allow-Origin", "*");
    res.header(
        "Access-Control-Allow-Headers",
        "Origin, X-Requested-With, Content-Type, Accept"
    );
    next();
});

// Serve crossdomain.xml
app.get('/crossdomain.xml', (req, res) => {
    res.set('Content-Type', 'application/xml');
    res.status(200).send(`
        <?xml version="1.0"?>
        <cross-domain-policy>
            <allow-access-from domain="*" />
        </cross-domain-policy>
    `);
});

// Use HTTP routes
app.use('/', httpRoutes);

// Provide the current XMLSocket port to the client
app.get('/getSocketPort', (req, res) => {
    res.set('Content-Type', 'application/x-www-form-urlencoded');
    if (socketServer && socketServer.socketPort) {
        res.status(200).send(`socketPort=${socketServer.socketPort}`);
    } else {
        res.status(500).send('error=Socket server not started yet.');
    }
});

// Handle AS2 client batch log messages
app.post('/logBatch', (req, res) => {
    const frame = req.body.frame;
    const messages = req.body.messages;

    if (frame !== undefined && messages) {
        const messageArray = messages.split('|');

        messageArray.forEach((msg) => {
            if (msg.trim() !== '') {
                logger.info(`[F: ${frame}] ${msg}`);
            }
        });

        res.status(200).send('Messages logged');
    } else {
        res.status(400).send('Frame or messages not received');
    }
});

// Connection test endpoint
app.post('/testConnection', (req, res) => {
    logger.info('Received testConnection request');
    res.status(200).send('status=success');
});

// Start the HTTP server
function startServer() {
    if (portIndex >= portList.length) {
        logger.error('No available ports found for HTTP server.');
        process.exit(1);
        return;
    }

    const port = portList[portIndex];
    if (usedPorts.has(port)) {
        portIndex++;
        startServer();
        return;
    }

    const startTime = Date.now();
    server = app.listen(port, () => {
        const duration = Date.now() - startTime;
        logger.info(`HTTP server running on http://localhost:${port} (Started in ${duration}ms)`);
        usedPorts.add(port);
        retryCount = 0;

        // Start XMLSocket server
        socketServer = new SocketServer(portList, usedPorts);
        socketServer.startSocketServer(port, (success) => {
            if (success) {
                logger.info(`XMLSocket server successfully started on port ${socketServer.socketPort}`);
            } else {
                logger.error('Failed to start XMLSocket server.');
                process.exit(1);
            }
        });
    });

    server.on('error', (err) => {
        if (err.code === 'EADDRINUSE') {
            logger.error(`Port ${port} is in use for HTTP server, retrying with next port...`);
            portIndex++;
            retryCount++;
            if (retryCount < maxRetries) {
                setTimeout(startServer, 1000);
            } else {
                logger.error(`Max retries reached (${maxRetries}). HTTP server startup failed.`);
                process.exit(1);
            }
        } else {
            logger.error(`HTTP server encountered an error: ${err.message}`);
            process.exit(1);
        }
    });
}

// Graceful shutdown
function gracefulShutdown() {
    logger.info('Shutting down servers gracefully...');
    if (server) {
        server.close(() => {
            logger.info('Closed HTTP server');
            if (socketServer && socketServer.socketServerInstance) {
                socketServer.socketServerInstance.close(() => {
                    logger.info('Closed XMLSocket server');
                    process.exit(0);
                });
            } else {
                process.exit(0);
            }
        });
    } else {
        process.exit(0);
    }
}

process.on('SIGTERM', gracefulShutdown);
process.on('SIGINT', gracefulShutdown);

// Error handling
process.on('uncaughtException', (err) => {
    logger.error('Uncaught Exception: ' + err.message);
    logger.error(err.stack);
});

process.on('unhandledRejection', (reason, promise) => {
    logger.error('Unhandled Rejection at:', promise, 'reason:', reason);
});

// Start the server
startServer();
