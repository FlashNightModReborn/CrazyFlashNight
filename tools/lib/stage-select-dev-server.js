'use strict';
// ESM / GLB 与生产虚拟主机同源；文件 URL 无法覆盖模块加载。
const http = require('http');
const fs = require('fs');
const path = require('path');
async function startServer(root) {
    const base = path.resolve(root);
    const server = http.createServer((req, res) => {
        let file;
        try { file = path.resolve(base, '.' + decodeURIComponent(new URL(req.url, 'http://localhost').pathname)); }
        catch (_) { res.writeHead(400); res.end(); return; }
        if (!file.startsWith(base + path.sep)) { res.writeHead(403); res.end(); return; }
        const types = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.json': 'application/json',
            '.glb': 'model/gltf-binary', '.png': 'image/png', '.jpg': 'image/jpeg', '.svg': 'image/svg+xml', '.woff2': 'font/woff2' };
        fs.readFile(file, (error, bytes) => {
            res.writeHead(error ? 404 : 200, { 'content-type': types[path.extname(file)] || 'application/octet-stream', 'cache-control': 'no-store' });
            res.end(error ? '' : bytes);
        });
    });
    await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
    return { server, origin: 'http://127.0.0.1:' + server.address().port };
}
module.exports = { startServer };
