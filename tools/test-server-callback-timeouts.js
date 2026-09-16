'use strict';

// 执行生产握手 shim、BootstrapHandshake 与 ServerManager 的发送/超时分支。
// 仅擦除 AS2 类型注解，注入时钟和传输；不是 AVM1/真实 socket 验收。
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const root = path.resolve(__dirname, '..');
const read = file => fs.readFileSync(path.join(root, file), 'utf8');
const eraseTypes = source => source.replace(
  /:\s*(?:Object|Boolean|Number|String|Array|Function|Void|Error|MovieClip)\b(?=\s*(?:[,)=;{]|in\b))/g, '');

// 同一词法扫描提取函数体及调用参数，避免用正则截断嵌套 callback。
function region(source, start, splitArgs = false) {
  const stack = [], parts = [];
  let part = start + 1, quote = '', comment = '', escaped = false;
  for (let i = start; i < source.length; i++) {
    const c = source[i], next = source[i + 1];
    if (comment === '//') { if (c === '\n') comment = ''; continue; }
    if (comment === '/*') { if (c === '*' && next === '/') { comment = ''; i++; } continue; }
    if (quote) {
      if (escaped) escaped = false;
      else if (c === '\\') escaped = true;
      else if (c === quote) quote = '';
      continue;
    }
    if (c === '/' && (next === '/' || next === '*')) { comment = c + next; i++; continue; }
    if (c === '"' || c === "'") { quote = c; continue; }
    if ('([{'.includes(c)) stack.push(c);
    else if (')]}'.includes(c)) {
      stack.pop();
      if (stack.length === 0) {
        parts.push(source.slice(part, i).trim());
        return {end: i + 1, parts};
      }
    } else if (splitArgs && c === ',' && stack.length === 1) {
      parts.push(source.slice(part, i).trim()); part = i + 1;
    }
  }
  throw new Error('Unclosed source region');
}

const server = read('scripts/类定义/org/flashNight/neur/Server/ServerManager.as');
const methodStart = server.indexOf('function sendTaskWithCallback(');
assert(methodStart >= 0);
const methodEnd = region(server, server.indexOf('{', methodStart)).end;
const sendMethod = eraseTypes(server.slice(methodStart, methodEnd));
const scanStart = server.indexOf('if (currentFrame % 60 === 0)');
assert(scanStart >= 0);
const scan = eraseTypes(server.slice(scanStart, region(server, server.indexOf('{', scanStart)).end));
const timeoutMatch = /CALLBACK_TIMEOUT_MS:Number\s*=\s*(\d+)/.exec(server);
assert(timeoutMatch);
let checks = 0;
function check(name, run) { run(); checks++; console.log('[PASS] ' + name); }
function transport() {
  const clock = {now: 0};
  const ctx = {
    getTimer: () => clock.now, currentFrame: 60, _pendingCallbacks: {}, _callIdCounter: 1,
    CALLBACK_TIMEOUT_MS: Number(timeoutMatch[1]), isSocketConnected: true,
    jsonParser: JSON, sendSocketMessage: () => true, sendServerMessage: () => {}
  };
  vm.createContext(ctx); vm.runInContext(sendMethod, ctx);
  return {ctx, clock, sweep: ms => { clock.now = ms; vm.runInContext(scan, ctx); }};
}
function expectDeadline(name, argument, deadline) {
  check(name, () => {
    const t = transport(), responses = [];
    t.ctx.sendTaskWithCallback('probe', {}, null, response => responses.push(response), argument);
    t.sweep(deadline - 1);
    assert.equal(responses.length, 0, 'must preserve the whole waiting budget');
    t.sweep(deadline + 1);
    assert.equal(responses.length, 1, 'must still expire after the budget');
    assert.equal(responses[0].error, 'callback timeout');
    t.sweep(deadline + 2000);
    assert.equal(responses.length, 1, 'timeout must consume its callback once');
  });
}

check('production bootstrap keeps its 60-second prewarm budget', () => {
  const t = transport();
  const hs = read('scripts/类定义/org/flashNight/neur/Server/BootstrapHandshake.as');
  vm.runInContext(eraseTypes(hs.slice(hs.indexOf('{') + 1, hs.lastIndexOf('}'))
    .replace(/\b(?:private|public) static /g, '')), t.ctx);
  Object.assign(t.ctx, {setTimeout: () => 1, clearTimeout: () => {},
    _root: {server: t.ctx}, BootstrapHandshake: t.ctx});
  t.ctx.org = {flashNight: {neur: {Server: {BootstrapHandshake: t.ctx}}}};
  vm.runInContext(eraseTypes(read('scripts/通信/通信_fs_bootstrap.as')), t.ctx);
  t.ctx._root._bootstrap.startHandshake();
  t.sweep(2000); assert.equal(t.ctx.getState(), 'WaitResp');
  t.sweep(45000); assert.equal(t.ctx.getState(), 'WaitResp');
  t.sweep(60001); assert.equal(t.ctx.getState(), 'Failed');
  assert.equal(t.ctx._root._bootstrapFailed, 'callback timeout');
});

const budgets = [
  ['scripts/类定义/org/flashNight/arki/map/MapDomainBridge.as', [4000, 3000, 3000, 3000]],
  ['scripts/类定义/org/flashNight/arki/item/RewardInboxService.as', [20000]],
  ['scripts/类定义/org/flashNight/arki/item/LootContainerService.as', [20000]]
];
for (const [file, expected] of budgets) {
  const source = read(file), calls = [], re = /\.sendTaskWithCallback\s*\(/g;
  let match;
  while ((match = re.exec(source))) {
    const call = region(source, source.indexOf('(', match.index), true);
    re.lastIndex = call.end;
    assert.equal(call.parts.length, 5, file + ': explicit callback budget required');
    assert(/^\d+$/.test(call.parts[4]), file + ': inspect a changed timeout expression');
    calls.push(Number(call.parts[4]));
  }
  assert.equal(calls.length, expected.length, file + ': review changed call sites');
  calls.forEach((argument, i) => expectDeadline(path.basename(file) + ' callback ' + (i + 1), argument, expected[i]));
}
expectDeadline('omitted timeout keeps the default 20 seconds', undefined, 20000);
check('send failure removes the callback immediately', () => {
  const t = transport(), responses = [];
  t.ctx.sendSocketMessage = () => false;
  t.ctx.sendTaskWithCallback('probe', {}, null, response => responses.push(response), 3000);
  assert.equal(responses.length, 1);
  assert.equal(responses[0].error, 'send failed');
  assert.equal(Object.keys(t.ctx._pendingCallbacks).length, 0);
});
console.log('[server-callback-timeouts] PASS ' + checks);
