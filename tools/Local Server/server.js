const express = require('express');
const fs = require('fs');
const winston = require('winston');
require('winston-daily-rotate-file');

const app = express();
const logDir = 'logs';
let portList = new Set();
let portIndex = 0;
let retryCount = 0;
const maxRetries = 5;
const eyeOf119 = "1192433993";

// 确保日志目录存在
if (!fs.existsSync(logDir)) {
    fs.mkdirSync(logDir);
}

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

app.get('/', (req, res) => {
    res.send('Hello World!');
});

app.get('/about', (req, res) => {
    res.send('This is the about page');
});

app.use(express.json());
app.use(express.urlencoded({ extended: true })); // 启用 URL 编码的请求体解析

app.use((req, res, next) => {
    res.header("Access-Control-Allow-Origin", "*");
    res.header("Access-Control-Allow-Headers", "Origin, X-Requested-With, Content-Type, Accept");
    next();
});

// 移除单独的日志处理端点，避免重复日志
/*
app.post('/log', (req, res) => {
    const message = req.body.message;
    if (message) {
        logger.info(`Received log message: ${message}`);
        res.status(200).send('Message logged');
    } else {
        res.status(400).send('No message received');
    }
});
*/

// 处理 AS2 客户端发送的批量日志消息
app.post('/logBatch', (req, res) => {
    const messages = req.body.messages;

    if (messages) {
        const messageArray = messages.split('|'); // 使用 '|' 作为分隔符

        // 逐条记录日志
        messageArray.forEach(msg => {
            if (msg.trim() !== '') { // 避免记录空消息
                logger.info(`Received batch message: ${msg}`);
            }
        });

        res.status(200).send('Messages logged');
    } else {
        res.status(400).send('No messages received');
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
            portList.add(port4);
            logger.info(`Added port4: ${port4}`);
        }
    }

    // 提取5位数的端口
    for (let j = 0; j <= eyeOf119.length - 5; j++) {
        const port5 = Number(eyeOf119.substring(j, j + 5));
        if (isValidPort(port5)) {
            portList.add(port5);
            logger.info(`Added port5: ${port5}`);
        }
    }

    // 确保端口3000被加入（如果还未加入）
    if (!portList.has(3000)) {
        portList.add(3000);
        logger.info('Added default port: 3000');
    }

    logger.info(`Extracted ports: ${[...portList].join(", ")}`);
}

// 验证端口号是否有效（范围在 1024-65535 之间）
function isValidPort(port) {
    return port >= 1024 && port <= 65535;
}

// 递归尝试启动服务器
let server; // 全局可访问的 server 变量

function startServer() {
    if (portIndex >= portList.size) {
        logger.error('No available ports found.');
        process.exit(1); // 使用错误代码退出
        return;
    }

    const port = [...portList][portIndex];
    const startTime = Date.now();
    server = app.listen(port, () => {
        const duration = Date.now() - startTime;
        logger.info(`Server running on http://localhost:${port} (Started in ${duration}ms)`);
        retryCount = 0; // 重置重试计数
    });

    server.on('error', (err) => {
        if (err.code === 'EADDRINUSE') {
            logger.error(`Port ${port} is in use, retrying with next port...`);
            portIndex++;
            retryCount++;
            if (retryCount < maxRetries) {
                setTimeout(startServer, 1000); // 等待1秒后重试
            } else {
                logger.error(`Max retries reached (${maxRetries}). Server startup failed.`);
                process.exit(1); // 达到最大重试次数后退出
            }
        } else {
            logger.error(`Server encountered an error: ${err.message}`);
            process.exit(1); // 处理其他关键错误后退出
        }
    });
}

// 优雅关闭服务器
function gracefulShutdown() {
    logger.info('Shutting down server gracefully...');
    if (server) {
        server.close(() => {
            logger.info('Closed out remaining connections');
            process.exit(0); // 关闭所有连接后退出
        });
    } else {
        process.exit(0);
    }
}

process.on('SIGTERM', gracefulShutdown);
process.on('SIGINT', gracefulShutdown);

// 提取端口并启动服务器
extractPorts();
startServer();
