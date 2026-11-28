'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const root = path.resolve(process.argv[2] ?? '.');
const serverSource = fs.readFileSync(path.join(root, 'scripts/类定义/org/flashNight/neur/Server/ServerManager.as'), 'utf8');
const bountySource = fs.readFileSync(path.join(root, 'flashswf/UI/通缉令界面/DOMDocument.xml'), 'utf8');
const hitSource = fs.readFileSync(path.join(root, 'flashswf/UI/通缉令界面/LIBRARY/sprite/通缉令拖拽命中.xml'), 'utf8');
const nativeButton = fs.readFileSync(path.join(root, 'flashswf/UI/通缉令界面/LIBRARY/button/Symbol 728.xml'), 'utf8');

function action(text, prefix) {
  const start = text.indexOf(prefix);
  assert(start >= 0, prefix);
  const brace = text.indexOf('{', start);
  let depth = 0;
  for (let cursor = brace; cursor < text.length; ++cursor) {
    if (text[cursor] === '{') ++depth;
    if (text[cursor] === '}' && --depth === 0) return text.slice(start, cursor + 1);
  }
  throw Error('Unclosed action ' + prefix);
}

const code = [];
for (const name of ['installAuthoredWorldDragMouse', 'onAuthoredWorldMouseDown', 'onAuthoredWorldMouseUp',
  'retireAuthoredWorldDragInstance', 'beginAuthoredWorldDrag', 'endAuthoredWorldDrag', 'cancelAuthoredWorldDrag',
  'stageWorldPointerCancel', 'settleWorldPointerCancel']) code.push(action(serverSource, 'function ' + name));
for (const name of ['cf7BindBountyDrag', 'cf7BeginBountyDrag', 'cf7EndBountyDrag']) code.push(action(bountySource, 'function ' + name));
const button = [...bountySource.matchAll(/<!\[CDATA\[([\s\S]*?)\]\]>/g)].find((match) => match[1].includes('this.cf7EndBountyDrag();'))?.[1];
assert(button, 'Exact named button actions');
code.push(action(button, 'on(press)').replace('on(press)', 'function authoredPress()'));
code.push(action(button, 'on(release, releaseOutside)').replace('on(release, releaseOutside)', 'function authoredRelease()'));
code.push(action(button, 'on(rollOver)').replace('on(rollOver)', 'function authoredHover()'));
code.push(action(button, 'on(rollOut)').replace('on(rollOut)', 'function authoredLeave()'));

const listeners = [], receipts = [];
const input = { bound: true, passiveActive: true, gateOpen: true, connectionIncarnation: 1, snapshot: { keyboardEpoch: 19 } };
const transport = { connection: 1, worldPointerCancelTicket: 0 };
let owner, starts = 0, stops = 0, cursor = '', paintedHit = true;
const uiLayer = { _visible: true };
const fullScreen = { _visible: true, 当前UI: { _visible: false } };
const stage = { 通用UI层: uiLayer, 全屏UI层: fullScreen, cf7R1PassiveInput: '1', _xmouse: 199, _ymouse: 134,
  鼠标: { gotoAndStop(value) { cursor = value; } } };
const context = vm.createContext({ _inputCell: input, _inputWire: transport, _authoredWorldDrag: null,
  _authoredWorldDragMouse: null, _root: stage, Mouse: { addListener(value) { listeners.push(value); } },
  inputUInt: (value) => /^\d+$/.test(value) ? Number(value) : 0,
  startDrag(value) { assert.equal(owner, undefined); owner = value; ++starts; },
  stopDrag() { owner = undefined; ++stops; },
  trace() {}, sendSocketMessage(message) { receipts.push(message); } });
stage.stopDrag = context.stopDrag;
vm.runInContext(code.join('\n').replace(/:(?:ServerManager|MovieClip|Object|Boolean|String|Array|Void|Number)\b/g, ''), context);
stage.server = context;
context.installAuthoredWorldDragMouse();
context.installAuthoredWorldDragMouse();
assert.equal(listeners.length, 1, 'Session installs only one observer');
const [mouse] = listeners;

const panel = { _visible: true, __cf7BountyDragButton: { enabled: true },
  __cf7BountyDragHit: { hitTest(x, y, shape) { assert.equal(x, 199); assert.equal(y, 134); assert.equal(shape, true); return paintedHit; } },
  cf7BeginBountyDrag: context.cf7BeginBountyDrag, cf7EndBountyDrag: context.cf7EndBountyDrag };
const bind = () => {
  panel.__cf7AuthoredWorldDragInstance = context.cf7BindBountyDrag(panel);
  uiLayer.外部导入UI界面 = panel;
  context.authoredHover.call(panel);
  return panel.__cf7AuthoredWorldDragInstance;
};
const active = bind();
const begin = () => context.authoredPress.call(panel);
const end = () => context.authoredRelease.call(panel);
const cancel = (ticket, epoch) => {
  const fields = `I1|WorldPointerCancel|session|1|${ticket}|${epoch}`.split('|');
  context.stageWorldPointerCancel(transport, fields);
  return fields;
};
const settle = () => context.settleWorldPointerCancel(transport);
const arm = (ticket, epoch) => { begin(); cancel(ticket, epoch); settle(); };

mouse.onMouseDown();
assert.equal(starts, 0, 'No fallback before a world cancellation');
begin();
assert.equal(starts, 1);
mouse.onMouseUp();
assert.equal(owner, panel, 'Normal Button retains its own release');
end();
assert.equal(stops, 1);

begin();
const cancelled = cancel(7, 103);
assert.equal(owner, panel);
assert.equal(receipts.length, 0);
settle();
assert.equal(receipts[0], 'I1|WorldPointerCancelled|session|1|7|103|1');
assert.equal(cursor, '手型普通');
assert.equal(stops, 2);
input.snapshot.keyboardEpoch = 21;
mouse.onMouseUp();
assert.equal(owner, undefined, 'Old Up cannot become a start or a second stop');
mouse.onMouseDown();
assert.equal(owner, panel, 'Fresh Mouse Down needs no Button Press');
assert.equal(context._authoredWorldDrag, active);
begin();
assert.equal(starts, 3, 'A coincident authored Press does not start again');
context.stageWorldPointerCancel(transport, cancelled);
settle();
assert.equal(owner, panel, 'The old exact receipt cannot cancel the fresh drag again');
mouse.onMouseUp();
end();
assert.equal(stops, 3, 'One physical Up settles the adapter and authored Release once');

arm(8, 105);
paintedHit = false;
mouse.onMouseDown();
paintedHit = true;
mouse.onMouseDown();
assert.equal(owner, undefined, 'Outside click retires its retry without taking the next click');

arm(9, 106);
fullScreen.当前UI._visible = true;
mouse.onMouseDown();
fullScreen.当前UI._visible = false;
assert.equal(owner, undefined, 'A covering Flash screen is not taken over');

arm(10, 107);
panel.__cf7BountyDragButton.enabled = false;
mouse.onMouseDown();
panel.__cf7BountyDragButton.enabled = true;
assert.equal(owner, undefined, 'A disabled actual Button cannot be reacquired');

arm(11, 108);
const superseded = panel.onUnload;
const replacement = bind();
mouse.onMouseDown();
assert.equal(owner, undefined, 'Same display path and geometry do not replace the ordinary token');
begin();
superseded();
assert.equal(context._authoredWorldDrag, replacement, 'An old unload cannot retire the new owner');
end();

arm(12, 109);
const foreign = {};
assert.equal(context.beginAuthoredWorldDrag(foreign), true);
mouse.onMouseDown();
mouse.onMouseUp();
assert.equal(context._authoredWorldDrag, foreign, 'Another drag lease remains in charge');
assert.equal(context.endAuthoredWorldDrag(foreign), true);

arm(13, 110);
cancel(14, 111);
mouse.onMouseDown();
settle();
mouse.onMouseDown();
assert.equal(owner, undefined, 'Pending or later cancellation invalidates a stale retry');

arm(15, 112);
input.gateOpen = false;
mouse.onMouseDown();
input.gateOpen = true;
mouse.onMouseDown();
assert.equal(owner, undefined, 'A closed gate never leaves a queued click to replay');

arm(16, 113);
context._inputWire = { connection: 2, worldPointerCancelTicket: 0 };
input.connectionIncarnation = 2;
mouse.onMouseDown();
assert.equal(owner, undefined, 'A new I1 incarnation cannot use the old cancellation identity');

const hitTransform = /<Matrix[^>]*a="3\.57843017578125"[^>]*d="3\.56863403320313"[^>]*tx="-16\.8"[^>]*ty="-16\.75"\//;
assert.match(hitSource, /libraryItemName="shape\/Symbol 534"/);
assert.match(nativeButton, /<DOMFrame index="3"[\s\S]*libraryItemName="shape\/Symbol 534"/);
assert.match(hitSource, hitTransform);
assert.match(nativeButton, hitTransform);

console.log(JSON.stringify({ status: 'PASS', level: 'T0 source transcript', starts, stops, receipts,
  checks: ['paired normal and recovered start/release', 'exact, duplicate and pending cancellation', 'active I1 grant and replacement token',
    'outside hit, covering screen and disabled Button', 'other drag lease retained', 'same published hit artwork'],
  runtimeStillRequired: ['native AVM1 MouseDown/Up behavior for secondary buttons', 'alpha-zero exact shape hitTest in FP20'] }, null, 2));
