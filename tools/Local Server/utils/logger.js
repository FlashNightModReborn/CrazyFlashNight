// utils/logger.js
const fs = require('fs');
const winston = require('winston');
require('winston-daily-rotate-file');

const logDir = 'logs';

// Ensure log directory exists
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
        winston.format.printf(
            ({ timestamp, level, message }) => `${timestamp} ${level}: ${message}`
        )
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

module.exports = logger;
