// server.js
const express = require('express');
const app = express();
const { extractPorts } = require('./config/ports');
const logger = require('./utils/logger');
const httpRoutes = require('./routes/httpRoutes');
const SocketServer = require('./services/socketServer');
const path = require('path');
const fs = require('fs');

// 引入模拟的浏览器环境
require('./utils/browserEnv');


// 提取端口列表和最大重试次数，支持环境变量配置
let portList = extractPorts();
let usedPorts = new Set();
let portIndex = 0;
const maxRetries = process.env.MAX_RETRIES || 5;

// 初始化服务器变量
let server;
let socketServer;

// 中间件和配置
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

// CORS 设置
app.use((req, res, next) => {
    res.header("Access-Control-Allow-Origin", "*");
    res.header("Access-Control-Allow-Headers", "Origin, X-Requested-With, Content-Type, Accept");
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

// 使用 HTTP 路由
app.use('/', httpRoutes);

// 获取 XMLSocket 端口的接口
app.get('/getSocketPort', (req, res) => {
    res.set('Content-Type', 'application/x-www-form-urlencoded');
    if (socketServer && socketServer.socketPort) {
        res.status(200).send(`socketPort=${socketServer.socketPort}`);
    } else {
        res.status(500).send('error=Socket server not started yet.');
    }
});

// 处理批量日志
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

// 连接测试接口
app.post('/testConnection', (req, res) => {
    logger.info('Received testConnection request');
    res.status(200).send('status=success');
});

// 文件传输接口
app.get('/getFile', (req, res) => {
    const relativePath = req.query.path;
    const absolutePath = path.join(__dirname, 'resources', relativePath);

    fs.access(absolutePath, fs.constants.F_OK, (err) => {
        if (err) {
            logger.error(`File not found: ${absolutePath}`);
            return res.status(404).send('File not found');
        }
        fs.readFile(absolutePath, 'utf8', (err, data) => {
            if (err) {
                logger.error(`Error reading file: ${absolutePath}`);
                return res.status(500).send('Error reading file');
            }
            res.set('Content-Type', 'application/xml');
            res.status(200).send(data);
        });
    });
});

// 启动 HTTP 服务器
function startServer() {
    if (portIndex >= portList.length) {
        logger.error('No available ports found for HTTP server.');
        process.exit(1);
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

        // 启动 XMLSocket 服务器
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

// 平滑关闭
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

// 处理系统信号
process.on('SIGTERM', gracefulShutdown);
process.on('SIGINT', gracefulShutdown);

// 错误处理
process.on('uncaughtException', (err) => {
    logger.error('Uncaught Exception: ' + err.message);
    logger.error(err.stack);
});

process.on('unhandledRejection', (reason, promise) => {
    logger.error('Unhandled Rejection at:', promise, 'reason:', reason);
});

// 启动服务器
startServer();
