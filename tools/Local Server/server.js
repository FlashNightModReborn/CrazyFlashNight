const express = require('express');
const fs = require('fs');
const winston = require('winston');
require('winston-daily-rotate-file');
const net = require('net');
const { VM } = require('vm2'); // 安全的沙箱模块

const app = express();
const logDir = 'logs';
let portList = [];
let usedPorts = new Set();
let portIndex = 0;
let retryCount = 0;
const maxRetries = 5;
const eyeOf119 = "1192433993";

// 初始化 socketPort
let socketPort = null;

// 记录 socketServer 实例
let socketServerInstance = null;

// 确保日志目录存在
if (!fs.existsSync(logDir)) {
    fs.mkdirSync(logDir);
}

// 配置 Winston 日志记录器
const transport = new winston.transports.DailyRotateFile({
    filename: `${logDir}/app-%DATE%.log`,
    datePattern: 'YYYY-MM-DD',
    zippedArchive: true,
    maxSize: '20m',
    maxFiles: '14d',
    format: winston.format.combine(
        winston.format.timestamp(),
        winston.format.printf(({ timestamp, level, message }) => `${timestamp} ${level}: ${message}`)
    ),
});

const logger = winston.createLogger({
    transports: [
        transport,
        new winston.transports.Console({
            format: winston.format.simple(),
        }),
    ],
});

// 定义 HTTP 路由
app.get('/', (req, res) => {
    res.send('Hello World!');
});

app.get('/about', (req, res) => {
    res.send('This is the about page');
});

// 新增：提供当前的 XMLSocket 端口号给客户端
app.get('/getSocketPort', (req, res) => {
    res.set('Content-Type', 'application/x-www-form-urlencoded'); // 设置 Content-Type
    if (socketPort) {
        res.status(200).send(`socketPort=${socketPort}`);
    } else {
        res.status(500).send('error=Socket server not started yet.');
    }
});

app.use(express.json());
app.use(express.urlencoded({ extended: true })); // 启用 URL 编码的请求体解析

app.use((req, res, next) => {
    res.header("Access-Control-Allow-Origin", "*");
    res.header("Access-Control-Allow-Headers", "Origin, X-Requested-With, Content-Type, Accept");
    next();
});

// 处理 AS2 客户端发送的批量日志消息
app.post('/logBatch', (req, res) => {
    const frame = req.body.frame;
    const messages = req.body.messages;

    if (frame !== undefined && messages) {
        const messageArray = messages.split('|'); // 使用 '|' 作为分隔符

        // 逐条记录日志，将帧数信息嵌入到每一条消息前
        messageArray.forEach(msg => {
            if (msg.trim() !== '') { // 避免记录空消息
                logger.info(`[F: ${frame}] ${msg}`);
            }
        });

        res.status(200).send('Messages logged');
    } else {
        res.status(400).send('Frame or messages not received');
    }
});

// 连接测试端点
app.post('/testConnection', (req, res) => {
    logger.info('Received testConnection request');
    res.status(200).send('status=success');
});

// 提取端口号并将其加入 portList
function extractPorts() {
    // 提取4位数的端口
    for (let i = 0; i <= eyeOf119.length - 4; i++) {
        const port4 = Number(eyeOf119.substring(i, i + 4));
        if (isValidPort(port4)) {
            portList.push(port4);
            logger.info(`Added port4: ${port4}`);
        }
    }

    // 提取5位数的端口
    for (let j = 0; j <= eyeOf119.length - 5; j++) {
        const port5 = Number(eyeOf119.substring(j, j + 5));
        if (isValidPort(port5)) {
            portList.push(port5);
            logger.info(`Added port5: ${port5}`);
        }
    }

    // 确保端口3000被加入（如果还未加入）
    if (!portList.includes(3000)) {
        portList.push(3000);
        logger.info('Added default port: 3000');
    }

    // 移除重复的端口
    portList = [...new Set(portList)];

    logger.info(`Extracted ports: ${portList.join(", ")}`);
}

// 验证端口号是否有效（范围在 1024-65535 之间）
function isValidPort(port) {
    return port >= 1024 && port <= 65535;
}

// 递归尝试启动 HTTP 服务器
let server; // 全局可访问的 server 变量

function startServer() {
    if (portIndex >= portList.length) {
        logger.error('No available ports found for HTTP server.');
        process.exit(1); // 使用错误代码退出
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
        usedPorts.add(port); // 将端口添加到已使用端口集合中
        retryCount = 0; // 重置重试计数

        // 启动 XMLSocket 服务器
        startSocketServer(port, (success) => {
            if (success) {
                logger.info(`XMLSocket server successfully started on port ${socketPort}`);
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
                setTimeout(startServer, 1000); // 等待1秒后重试
            } else {
                logger.error(`Max retries reached (${maxRetries}). HTTP server startup failed.`);
                process.exit(1); // 达到最大重试次数后退出
            }
        } else {
            logger.error(`HTTP server encountered an error: ${err.message}`);
            process.exit(1); // 处理其他关键错误后退出
        }
    });
}

// 递归尝试启动 XMLSocket 服务器
function startSocketServer(httpPort, callback) {
    let currentIndex = 0;

    function tryNextPort() {
        if (currentIndex >= portList.length) {
            logger.error('No available ports found for XMLSocket server.');
            callback(false);
            process.exit(1);
            return;
        }

        const port = portList[currentIndex];
        currentIndex++;

        if (usedPorts.has(port) || port === httpPort) {
            // 跳过已使用的端口和 HTTP 服务器的端口
            tryNextPort();
            return;
        }

        const socketServer = net.createServer((socket) => {
            logger.info('XMLSocket client connected');

            // 处理每个 socket 的消息缓冲
            let buffer = '';

            socket.on('data', (data) => {
                buffer += data.toString();

                // 分割消息，以 '\0' 作为结束符
                let parts = buffer.split('\0');
                // 保留最后一部分（可能是不完整的）
                buffer = parts.pop();

                parts.forEach(message => {
                    if (message.length === 0) {
                        return;
                    }

                    // 处理策略文件请求
                    if (message.indexOf('<policy-file-request/>') !== -1) {
                        socket.write(policyResponse);
                        logger.info('Sent policy file to client');
                        return; // 处理策略文件请求后不继续处理
                    }

                    logger.info('Received data from AS2 client: ' + message);

                    // 处理消息
                    const result = processSocketMessage(message);

                    // 发送结果回 AS2 客户端，附加 null 终止符
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
            socketPort = port; // 设置全局 socketPort，供客户端获取
            usedPorts.add(port); // 将端口添加到已使用端口集合中
            socketServerInstance = socketServer; // 记录 socketServer 实例
            callback(true);
        });

        socketServer.on('error', (err) => {
            if (err.code === 'EADDRINUSE') {
                logger.error(`Port ${port} is in use for XMLSocket server, trying next port...`);
                tryNextPort();
            } else {
                logger.error('XMLSocket server error: ' + err.message);
                process.exit(1);
            }
        });
    }

    tryNextPort();
}

// 定义安全策略响应
const policyResponse = '<cross-domain-policy><allow-access-from domain="*" to-ports="*" /></cross-domain-policy>\0';

// 处理从 AS2 客户端接收到的消息
function processSocketMessage(message) {
    let parsedMessage;

    try {
        parsedMessage = JSON.parse(message);
    } catch (err) {
        logger.warn('Received a non-JSON message: ' + message);
        return JSON.stringify({ success: false, error: 'Expected JSON format' });
    }

    let taskType = parsedMessage.task;
    let payload = parsedMessage.payload;
    let extra = parsedMessage.extra || {};

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
        default:
            return JSON.stringify({ success: false, error: 'Unknown task type' });
    }
}

// 处理 eval 任务
function handleEvalTask(code) {
    if (!code) {
        return JSON.stringify({ success: false, error: 'No code provided for eval' });
    }

    try {
        const vm = new VM({
            timeout: 1000,  // 设置超时时间，防止死循环等
            sandbox: {}
        });
        let result = vm.run(code);
        return JSON.stringify({ success: true, result: result });
    } catch (err) {
        logger.error('Error executing eval task: ' + err.message);
        return JSON.stringify({ success: false, error: err.message });
    }
}

// 处理正则表达式任务
function handleRegexTask(text, extra) {
    let pattern = extra.pattern;
    let flags = extra.flags || '';

    if (!pattern) {
        return JSON.stringify({ success: false, error: 'No pattern provided' });
    }

    try {
        let regex = new RegExp(pattern, flags);
        let match = regex.exec(text);
        // 如果 match 为 null，返回 false
        if (match === null) {
            return JSON.stringify({ success: true, match: false });
        }
        // 返回匹配结果数组
        return JSON.stringify({ success: true, match: match });
    } catch (err) {
        logger.error('Error executing regex task: ' + err.message);
        return JSON.stringify({ success: false, error: err.message });
    }
}

// 处理计算任务
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

// 优雅关闭服务器
function gracefulShutdown() {
    logger.info('Shutting down servers gracefully...');
    if (server) {
        server.close(() => {
            logger.info('Closed HTTP server');
            // 关闭 XMLSocket 服务器
            if (socketServerInstance) {
                socketServerInstance.close(() => {
                    logger.info('Closed XMLSocket server');
                    process.exit(0); // 关闭所有连接后退出
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

// 捕获未处理的异常，防止服务器崩溃
process.on('uncaughtException', (err) => {
    logger.error('Uncaught Exception: ' + err.message);
    logger.error(err.stack);
    // 根据情况决定是否退出
    // process.exit(1);
});

// 捕获未处理的 Promise 拒绝，防止服务器崩溃
process.on('unhandledRejection', (reason, promise) => {
    logger.error('Unhandled Rejection at:', promise, 'reason:', reason);
    // 根据情况决定是否退出
    // process.exit(1);
});

// 提取端口并启动服务器
extractPorts();
startServer();
