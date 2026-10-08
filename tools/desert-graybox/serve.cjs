'use strict';
const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '../..');
const portArg = process.argv.find(v => v.startsWith('--port='));
const port = portArg ? Number(portArg.split('=')[1]) : 0;
const allowed = ['/tools/desert-graybox/', '/launcher/web/assets/stage-diorama/base-gate/vendor/'];
const files = {
  '/': 'tools/desert-graybox/index.html',
  '/layout.json': 'docs/design-data/desert-spatial-draft.json',
  '/reference/base.jpg': 'tmp/map-camera-candidates-20260926/shots/base-overview-context.jpg',
  '/reference/hq.jpg': 'tmp/map-camera-candidates-20260926/shots/hq-overview-main.jpg',
  '/reference/city.jpg': 'tmp/map-camera-candidates-20260926/shots/city-landmark-main.jpg',
  '/models/manifest.json': 'tmp/desert-graybox/manifest.json',
  ...Object.fromEntries(['region', 'city', 'base'].map(mode => ['/models/desert-' + mode + '.glb', 'tmp/desert-graybox/desert-' + mode + '.glb'])),
};
const types = { '.html': 'text/html; charset=utf-8', '.mjs': 'text/javascript', '.js': 'text/javascript', '.css': 'text/css', '.json': 'application/json; charset=utf-8', '.glb': 'model/gltf-binary', '.jpg': 'image/jpeg' };
const server = http.createServer((req, res) => {
  if (!['GET', 'HEAD'].includes(req.method)) { res.writeHead(405); res.end(); return; }
  let url; try { url = decodeURIComponent(new URL(req.url, 'http://localhost').pathname); } catch { res.writeHead(400); res.end(); return; }
  if (url === '/favicon.ico') { res.writeHead(204); res.end(); return; }
  const relative = files[url] || (allowed.some(p => url.startsWith(p)) ? url.slice(1) : null);
  if (!relative || relative.includes('..') || relative.includes('\\')) { res.writeHead(403); res.end('Not served'); return; }
  const file = path.resolve(root, relative);
  if (!file.startsWith(root + path.sep)) { res.writeHead(403); res.end(); return; }
  fs.readFile(file, (error, bytes) => {
    res.writeHead(error ? 404 : 200, { 'Content-Type': types[path.extname(file)] || 'application/octet-stream', 'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff' });
    res.end(req.method === 'HEAD' ? '' : error ? 'Not found' : bytes);
  });
});
server.listen(port, '127.0.0.1', () => console.log('Desert graybox: http://127.0.0.1:' + server.address().port + '/'));
