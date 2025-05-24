const express = require('express');
const fs = require('fs');
const http = require('http');

const app = express();
let PORT = 3000; 
const flashNight = '1192433993';
const winston = require('winston');
require('winston-daily-rotate-file');

const logDir = 'logs';

// 确保日志目录存在
if (!fs.existsSync(logDir)) {
    fs.mkdirSync(logDir);
}

// 配置Winston日志记录
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

app.use(express.json());
app.use(express.urlencoded({ extended: true }));
app.use((req, res, next) => {
    res.header("Access-Control-Allow-Origin", "*");
    res.header("Access-Control-Allow-Headers", "Origin, X-Requested-With, Content-Type, Accept");
    next();
});

app.get('/', (req, res) => {
    res.send('Hello World!');
});

app.get('/about', (req, res) => {
    res.send('This is the about page');
});

app.post('/log', (req, res) => {
    const message = req.body.message;
    logger.info(`Received log message: ${message}`);
    res.status(200).send('Message logged');
});

app.get('/getPort', (req, res) => {
    res.json({ port: PORT });
});


// 获取下一个端口
function getNextPort(currentPort) {
    let ports = [];
    // 提取所有四位数
    for (let i = 0; i <= flashNight.length - 4; i++) {
        ports.push(parseInt(flashNight.substring(i, i + 4)));
    }
    // 提取所有五位数
    for (let i = 0; i <= flashNight.length - 5; i++) {
        ports.push(parseInt(flashNight.substring(i, i + 5)));
    }

    let nextPortIndex = ports.indexOf(currentPort) + 1;
    if (nextPortIndex < ports.length) {
        listenOnPort(ports[nextPortIndex]);
    } else {
        logger.error('No available ports found.');
    }
}

// 尝试监听端口，并更新当前端口变量
function listenOnPort(port) {
    const server = http.createServer(app);
    server.listen(port, () => {
        PORT = port;  // This will now work because PORT is declared with `let`
        logger.info(`Server running on http://localhost:${PORT}`);
    }).on('error', (err) => {
        if (err.code === 'EADDRINUSE') {
            logger.error(`Port ${port} is already in use`);
            getNextPort(port); // Try the next port if the current one is in use
        } else {
            logger.error(`Failed to start server on port ${port}: ${err}`);
        }
    });
}


// 开始监听
listenOnPort(PORT);
