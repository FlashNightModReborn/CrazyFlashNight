/**
 * LUT 实验室 harness 静态服务器（dev-only）。
 *  - /        → launcher/web/（面板与 harness 页面）
 *  - /vhost/  → 程序化生成的确定性 QA 样品（模拟生产 vhost https://cf7-lutlab/ → tmp/lut-lab/；
 *               不落盘 .cube 文件，遵守「样品只写 tmp/lut-lab/」的仓库边界）
 *  - /vhost-missing/ 恒 404（降级路径 QA 用）
 */
import { createServer } from 'node:http';
import { existsSync, readFileSync, statSync } from 'node:fs';
import { extname, relative, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const moduleDir = resolve(fileURLToPath(new URL('..', import.meta.url)));
const webRoot = resolve(moduleDir, '..', '..');
const port = Number(process.env.CF7_LUTLAB_PORT || process.argv[2] || 4191);
const mime = {
  '.css': 'text/css; charset=utf-8',
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.cube': 'text/plain; charset=utf-8',
  '.png': 'image/png',
};

// ── 确定性 QA 样品（与 browser-qa.js 的 CPU 参考共用同一生成函数定义）──
const clamp01 = (x) => x < 0 ? 0 : x > 1 ? 1 : x;
function buildCube(title, size, fn) {
  const lines = ['# CF7 LUT 实验室 QA 样品（确定性程序生成）', `TITLE "${title}"`, `LUT_3D_SIZE ${size}`];
  for (let b = 0; b < size; b++) for (let g = 0; g < size; g++) for (let r = 0; r < size; r++) {
    const o = fn(r / (size - 1), g / (size - 1), b / (size - 1));
    lines.push(`${o[0].toFixed(6)} ${o[1].toFixed(6)} ${o[2].toFixed(6)}`);
  }
  return lines.join('\n') + '\n';
}
const VHOST_ROUTES = {
  'samples/manifest.generated.json': JSON.stringify([
    { name: 'QA · 非线性 17³', file: 'qa-nonlin-17.cube', source: 'lut-lab QA 程序生成', license: 'CF7 测试资产', notes: '17³ 非线性已知 LUT：解析器重采样 + GPU/CPU 逐像素对照基准' },
  ], null, 2) + '\n',
  'samples/manifest.free.json': JSON.stringify([
    { name: 'QA · 恒等 33³', file: 'qa-identity-33.cube', source: 'lut-lab QA 程序生成', license: 'CF7 测试资产', notes: '33³ 恒等：覆盖非 32³ 重采样后仍恒等' },
  ], null, 2) + '\n',
  // 故意畸形：验证单组 manifest 失败不拖垮整表合并
  'samples/manifest.xml-regression.json': '{ malformed on purpose\n',
  'samples/generated/qa-nonlin-17.cube': buildCube('qa-nonlin-17', 17, (r, g, b) => [
    clamp01(Math.pow(r, 1.6) * 0.92 + 0.02),
    clamp01(g * g * (3 - 2 * g) * 0.85 + 0.05 * g),
    clamp01(Math.sqrt(b) * 0.75),
  ]),
  'samples/free/qa-identity-33.cube': buildCube('qa-identity-33', 33, (r, g, b) => [r, g, b]),
  // v2：QA 演示集合（夜视绿强度斜坡语义的最小复刻：等级=绿色增益 L/9）
  'sets/manifest.sets.json': JSON.stringify([
    { name: 'qa-green-ramp', title: 'QA · 绿夜视强度斜坡', mode: '夜视', dir: 'qa-green-ramp',
      files: Array.from({ length: 10 }, (_, i) => `夜视-${i}.cube`),
      source: 'lut-lab QA 程序生成', license: 'CF7 测试资产', notes: '等级=绿夜视增益 L/9' },
  ], null, 2) + '\n',
  ...Object.fromEntries(Array.from({ length: 10 }, (_, i) => [
    `sets/qa-green-ramp/夜视-${i}.cube`,
    buildCube(`qa-green-ramp-${i}`, 32, (r, g, b) => {
      const l = Math.min(1, (0.2126 * r + 0.7152 * g + 0.0722 * b) * (1 + i / 9));
      return [l * 0.07, l, l * 0.13];
    }),
  ])),
};

const server = createServer((request, response) => {
  try {
    const requestUrl = new URL(request.url || '/', `http://127.0.0.1:${port}`);
    const decoded = decodeURIComponent(requestUrl.pathname).replace(/^\/+/, '');
    if (decoded.startsWith('vhost-missing')) {
      response.writeHead(404, { 'content-type': 'text/plain; charset=utf-8' });
      response.end('not found (intentional: degraded-path probe)');
      return;
    }
    if (decoded.startsWith('vhost/')) {
      const route = decoded.slice('vhost/'.length);
      if (!Object.prototype.hasOwnProperty.call(VHOST_ROUTES, route)) {
        response.writeHead(404, { 'content-type': 'text/plain; charset=utf-8' });
        response.end('not found');
        return;
      }
      response.writeHead(200, {
        'content-type': route.endsWith('.json') ? mime['.json'] : mime['.cube'],
        'cache-control': 'no-store',
        'x-content-type-options': 'nosniff',
      });
      response.end(VHOST_ROUTES[route]);
      return;
    }
    let path = resolve(webRoot, decoded || 'modules/lut-lab/dev/harness.html');
    const rel = relative(webRoot, path);
    if (rel.startsWith('..') || rel.includes(':')) throw new Error('path outside web root');
    if (existsSync(path) && statSync(path).isDirectory()) path = resolve(path, 'index.html');
    if (!existsSync(path) || !statSync(path).isFile()) {
      response.writeHead(404, { 'content-type': 'text/plain; charset=utf-8' });
      response.end('not found');
      return;
    }
    response.writeHead(200, {
      'content-type': mime[extname(path).toLowerCase()] || 'application/octet-stream',
      'cache-control': 'no-store',
      'x-content-type-options': 'nosniff',
    });
    response.end(readFileSync(path));
  } catch (error) {
    response.writeHead(400, { 'content-type': 'text/plain; charset=utf-8' });
    response.end(error instanceof Error ? error.message : String(error));
  }
});

server.listen(port, '127.0.0.1', () => {
  console.log(`lut-lab harness: http://127.0.0.1:${port}/modules/lut-lab/dev/harness.html`);
});
