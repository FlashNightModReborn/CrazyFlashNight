// 静态文件服务器：把 launcher/web 目录映射到 http://localhost:<port>/
// WebView2 的 overlay.local 虚拟主机替代品；Playwright 直接 navigate 此 URL。

'use strict';

const http = require('http');
const fs = require('fs');
const path = require('path');
const url = require('url');

const MIME = {
    '.html': 'text/html; charset=utf-8',
    '.css': 'text/css; charset=utf-8',
    '.js': 'application/javascript; charset=utf-8',
    '.json': 'application/json; charset=utf-8',
    '.svg': 'image/svg+xml',
    '.png': 'image/png',
    '.jpg': 'image/jpeg',
    '.jpeg': 'image/jpeg',
    '.gif': 'image/gif',
    '.webp': 'image/webp',
    '.woff2': 'font/woff2',
    '.woff': 'font/woff',
    '.ttf': 'font/ttf',
};

function startServer(rootDir, port = 0) {
    return new Promise((resolve, reject) => {
        const server = http.createServer((req, res) => {
            try {
                let pathname = decodeURIComponent(url.parse(req.url).pathname);
                if (pathname === '/') pathname = '/overlay.html';
                const file = path.join(rootDir, pathname);
                const rel = path.relative(rootDir, file);
                if (rel.startsWith('..') || path.isAbsolute(rel)) {
                    res.writeHead(403); res.end('forbidden'); return;
                }
                fs.stat(file, (err, st) => {
                    if (err || !st.isFile()) { res.writeHead(404); res.end('not found: ' + pathname); return; }
                    const ext = path.extname(file).toLowerCase();
                    res.writeHead(200, {
                        'content-type': MIME[ext] || 'application/octet-stream',
                        'cache-control': 'no-store',
                    });
                    fs.createReadStream(file).pipe(res);
                });
            } catch (e) {
                res.writeHead(500); res.end(String(e));
            }
        });
        server.listen(port, '127.0.0.1', () => {
            const addr = server.address();
            resolve({ server, port: addr.port, url: 'http://127.0.0.1:' + addr.port + '/' });
        });
        server.on('error', reject);
    });
}

function stopServer(handle) {
    return new Promise((resolve) => {
        if (!handle || !handle.server) { resolve(); return; }
        handle.server.close(() => resolve());
    });
}

module.exports = { startServer, stopServer };
