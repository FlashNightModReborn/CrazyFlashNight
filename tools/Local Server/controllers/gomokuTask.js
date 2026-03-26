// controllers/gomokuTask.js
// Rapfi 引擎桥接：通过 Piskvork/Gomocup 协议与 Rapfi CLI 通信
const { spawn } = require('child_process');
const path = require('path');
const fs = require('fs');
const logger = require('../utils/logger');

let rapfiProcess = null;
let requestQueue = [];
let currentRequest = null;

// Rapfi 二进制路径：优先环境变量，回退到 bin/ 目录
function getRapfiPath() {
    if (process.env.RAPFI_PATH) return process.env.RAPFI_PATH;
    const binDir = path.join(__dirname, '..', 'bin');
    // 精确名称优先
    const exact = ['rapfi.exe', 'rapfi', 'pbrain-rapfi.exe', 'pbrain-rapfi'];
    for (const name of exact) {
        const p = path.join(binDir, name);
        if (fs.existsSync(p)) return p;
    }
    // 自动检测 pbrain-rapfi-windows-*.exe（优先 avx2）
    try {
        const files = fs.readdirSync(binDir);
        const preferred = ['avx2', 'avxvnni', 'sse', 'avx512'];
        for (const pref of preferred) {
            for (const f of files) {
                if (f.startsWith('pbrain-rapfi-windows-') && f.includes(pref) && f.endsWith('.exe')) {
                    return path.join(binDir, f);
                }
            }
        }
    } catch (e) { /* bin dir missing */ }
    return null;
}

function ensureRapfi() {
    if (rapfiProcess && !rapfiProcess.killed) return true;

    const rapfiPath = getRapfiPath();
    if (!rapfiPath) {
        logger.error('Rapfi binary not found. Set RAPFI_PATH or place binary in bin/');
        return false;
    }

    logger.info('Spawning Rapfi: ' + rapfiPath);
    rapfiProcess = spawn(rapfiPath, [], { stdio: ['pipe', 'pipe', 'pipe'] });

    let buffer = '';
    rapfiProcess.stdout.on('data', (data) => {
        buffer += data.toString();
        const lines = buffer.split('\n');
        buffer = lines.pop(); // 保留不完整行
        for (const line of lines) {
            const trimmed = line.trim();
            if (trimmed) handleRapfiLine(trimmed);
        }
    });

    rapfiProcess.stderr.on('data', (data) => {
        logger.warn('Rapfi stderr: ' + data.toString().trim());
    });

    rapfiProcess.on('exit', (code) => {
        logger.error('Rapfi exited with code ' + code);
        rapfiProcess = null;
        if (currentRequest) {
            clearTimeout(currentRequest.timer);
            currentRequest.reject(new Error('Rapfi process crashed'));
            currentRequest = null;
        }
        // 清空队列
        while (requestQueue.length > 0) {
            requestQueue.shift().reject(new Error('Rapfi not available'));
        }
    });

    // 发送初始化命令
    rapfiProcess.stdin.write('START 15\n');
    return true;
}

function handleRapfiLine(line) {
    if (!currentRequest) return;

    // OK = 启动确认，忽略
    if (line === 'OK') return;

    // MESSAGE 信息行：解析 depth/eval/pv
    // Rapfi 格式: "MESSAGE Depth 17-34 | Eval -499 | Time 2142ms | H7 I6 J8 ..."
    if (line.startsWith('MESSAGE')) {
        const depthMatch = line.match(/Depth\s+(\d+)/i);
        const evalMatch = line.match(/Eval\s+(-?\d+)/i);
        // PV 在最后一个 | 之后（坐标序列）
        const pvMatch = line.match(/Time\s+\d+m?s\s*\|\s*(.+)/i);
        if (depthMatch) currentRequest.info.depth = parseInt(depthMatch[1]);
        if (evalMatch) currentRequest.info.score = parseInt(evalMatch[1]);
        if (pvMatch) currentRequest.info.pv = pvMatch[1].trim();
        return;
    }

    // Best move: "x,y" 格式
    const moveMatch = line.match(/^(\d+),(\d+)$/);
    if (moveMatch) {
        const result = {
            x: parseInt(moveMatch[1]),
            y: parseInt(moveMatch[2]),
            depth: currentRequest.info.depth || 0,
            score: currentRequest.info.score || 0,
            pv: currentRequest.info.pv || ''
        };
        clearTimeout(currentRequest.timer);
        currentRequest.resolve(result);
        currentRequest = null;
        processNext();
        return;
    }

    // 未识别行，记录日志
    logger.debug('Rapfi unrecognized: ' + line);
}

function processNext() {
    if (currentRequest || requestQueue.length === 0) return;
    currentRequest = requestQueue.shift();

    if (!ensureRapfi()) {
        currentRequest.reject(new Error('Rapfi binary not found'));
        currentRequest = null;
        processNext();
        return;
    }

    const { moves, timeLimit } = currentRequest;

    // 设置时间限制
    if (timeLimit) {
        rapfiProcess.stdin.write('INFO timeout_turn ' + timeLimit + '\n');
    }

    // 构建 BOARD 命令（无状态，每次发完整局面）
    let cmd = 'BOARD\n';
    for (const m of moves) {
        // m = [x, y, role]  role: 1=black → piece 1, -1=white → piece 2
        const piece = m[2] === 1 ? 1 : 2;
        cmd += m[0] + ',' + m[1] + ',' + piece + '\n';
    }
    cmd += 'DONE\n';

    // 超时安全网
    const timeout = (timeLimit || 5000) + 2000;
    currentRequest.timer = setTimeout(() => {
        if (currentRequest) {
            logger.error('Rapfi timeout after ' + timeout + 'ms, killing process');
            currentRequest.reject(new Error('Rapfi timeout'));
            currentRequest = null;
            if (rapfiProcess) {
                rapfiProcess.kill();
                rapfiProcess = null;
            }
            processNext();
        }
    }, timeout);

    rapfiProcess.stdin.write(cmd);
}

/**
 * 处理五子棋评估任务
 * @param {Object} payload - {moves: [[x,y,role],...], timeLimit: Number}
 * @returns {Promise<Object>} - {x, y, score, depth, pv}
 */
function handleGomokuTask(payload) {
    return new Promise((resolve, reject) => {
        if (!payload || !Array.isArray(payload.moves)) {
            return reject(new Error('Invalid payload: moves array required'));
        }

        const entry = {
            moves: payload.moves,
            timeLimit: payload.timeLimit || 5000,
            info: {},
            resolve,
            reject,
            timer: null
        };

        requestQueue.push(entry);
        processNext();
    });
}

/**
 * 优雅关闭 Rapfi 进程
 * @returns {Promise<void>}
 */
function shutdown() {
    return new Promise((resolve) => {
        if (!rapfiProcess || rapfiProcess.killed) {
            resolve();
            return;
        }

        logger.info('Shutting down Rapfi...');
        const timer = setTimeout(() => {
            if (rapfiProcess && !rapfiProcess.killed) {
                rapfiProcess.kill('SIGKILL');
            }
            resolve();
        }, 3000);

        rapfiProcess.on('exit', () => {
            clearTimeout(timer);
            resolve();
        });

        try {
            rapfiProcess.stdin.write('END\n');
        } catch (e) {
            // stdin 可能已关闭
        }
        rapfiProcess.kill();
    });
}

module.exports = { handleGomokuTask, shutdown };
