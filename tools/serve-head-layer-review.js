#!/usr/bin/env node
'use strict';

// 头部层级验收台的人类打开发方式：静态服务 launcher/web 并用默认浏览器打开
// modules/dressup/dev/head-layer-review-harness.html。Ctrl+C 结束服务。
//
// 另挂载 /review-data/ 只读路由到 tmp/head-layer-verdicts（swe2 打标结果），
// 以及 POST /review-data/decisions.json 的逐件人工拍板持久化（同目录落盘）。

const fs = require('fs');
const http = require('http');
const path = require('path');
const { exec } = require('child_process');

const projectRoot = path.resolve(__dirname, '..');
const webRoot = path.join(projectRoot, 'launcher', 'web');
const reviewRoot = path.join(projectRoot, 'tmp', 'head-layer-verdicts');
const pagePath = '/modules/dressup/dev/head-layer-review-harness.html';
const REVIEW_FILES = new Set(['verdicts.jsonl', 'summary.json', 'decisions.json']);

function mimeType(filePath) {
    const ext = path.extname(filePath).toLowerCase();
    if (ext === '.html') return 'text/html; charset=utf-8';
    if (ext === '.js') return 'application/javascript; charset=utf-8';
    if (ext === '.css') return 'text/css; charset=utf-8';
    if (ext === '.json') return 'application/json; charset=utf-8';
    if (ext === '.jsonl') return 'application/x-ndjson; charset=utf-8';
    if (ext === '.png') return 'image/png';
    if (ext === '.jpg' || ext === '.jpeg') return 'image/jpeg';
    if (ext === '.svg') return 'image/svg+xml';
    if (ext === '.woff2') return 'font/woff2';
    return 'application/octet-stream';
}

function isPathInside(baseDir, candidate) {
    const relative = path.relative(baseDir, candidate);
    return relative === '' || (!relative.startsWith('..' + path.sep) && relative !== '..' && !path.isAbsolute(relative));
}

function serveFile(res, filePath) {
    fs.readFile(filePath, (error, data) => {
        if (error) {
            res.writeHead(404);
            res.end('not found');
            return;
        }
        res.writeHead(200, { 'Content-Type': mimeType(filePath) });
        res.end(data);
    });
}

function handleReviewData(req, res) {
    const rel = decodeURIComponent(req.url.slice('/review-data/'.length).split('?')[0]);
    if (!REVIEW_FILES.has(rel)) {
        res.writeHead(403);
        res.end('forbidden');
        return true;
    }
    const filePath = path.join(reviewRoot, rel);
    if (req.method === 'GET') {
        serveFile(res, filePath);
        return true;
    }
    if (req.method === 'POST' && rel === 'decisions.json') {
        let body = '';
        req.on('data', chunk => { body += chunk; });
        req.on('end', () => {
            try {
                const parsed = JSON.parse(body);
                if (!parsed || parsed.schema !== 'cf7.head-layer-decisions.v1'
                        || typeof parsed.decisions !== 'object') {
                    res.writeHead(400);
                    res.end('bad decisions payload');
                    return;
                }
                fs.mkdirSync(reviewRoot, { recursive: true });
                fs.writeFileSync(filePath, JSON.stringify(parsed, null, 2));
                res.writeHead(200, { 'Content-Type': 'application/json' });
                res.end('{"ok":true}');
            } catch (error) {
                res.writeHead(400);
                res.end('bad json');
            }
        });
        return true;
    }
    res.writeHead(405);
    res.end('method not allowed');
    return true;
}

const server = http.createServer((req, res) => {
    const pathname = (req.url || '/').split('?')[0] || '/';
    if (pathname.startsWith('/review-data/')) {
        handleReviewData(req, res);
        return;
    }
    let decoded;
    try {
        decoded = decodeURIComponent(pathname);
    } catch (error) {
        res.writeHead(400);
        res.end('bad request');
        return;
    }
    const filePath = path.join(webRoot, decoded === '/' ? pagePath : decoded);
    if (!isPathInside(webRoot, filePath)) {
        res.writeHead(403);
        res.end('forbidden');
        return;
    }
    serveFile(res, filePath);
});

server.listen(0, '127.0.0.1', () => {
    const url = 'http://127.0.0.1:' + server.address().port + pagePath;
    console.log('头部层级验收台已启动: ' + url);
    console.log('Ctrl+C 结束服务。');
    if (process.argv.indexOf('--no-open') < 0) {
        exec('start "" "' + url + '"');
    }
});
