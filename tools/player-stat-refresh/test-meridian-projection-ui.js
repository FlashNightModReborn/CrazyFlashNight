'use strict';
const fs=require('fs'),path=require('path'),vm=require('vm'),assert=require('assert');
const file=path.resolve(__dirname,'../../launcher/web/modules/meridians-panel.js');
const messages=[],handlers={};
function element() {return {children:[],listeners:{},textContent:'',className:'',
  set innerHTML(value) {this.children=[];},appendChild(child){this.children.push(child);},
  addEventListener(name,fn){this.listeners[name]=fn;}};}
// 只插入访问私有状态的夹具端口；执行的判定、按钮、query/late-response 路径是生产函数。
const source=fs.readFileSync(file,'utf8').replace('applyStateForTest: function(resp)',
  `__projectionProbe: function(value,box) {
    _refs={action:box};_meridians=[{id:'test',nodes:[{id:'node',cost:20,bonusType:'hp',bonusAmount:5}]}];
    _selectedIndex=0;_selectedNode='node';_busyNodes={};_kpoint=100;_lit={};_caps={hp:100};_used={hp:0};
    adoptProjection(value);renderAction();return _projection;
  },__directLight:lightNode,__close:onClose,
  applyStateForTest: function(resp)`);
const context={Panels:{register(){}},Bridge:{on(name,fn){handlers[name]=fn;},send(value){messages.push(value);}},
  document:{createElement:element},window:{},console};
vm.runInNewContext(source,context,{filename:file});
const api=context.MeridiansPanel;let count=0;
for(const value of [undefined,null,{status:'bogus',reason:''},{status:'failed',reason:'x',extra:1},
  {status:'failed',reason:1},{status:'failed',reason:'x'.repeat(161)},
  {status:'failed',reason:'injected'},{status:'pending',reason:'pending_ready'}]) {
  const box=element();api.__projectionProbe(value,box);
  assert.strictEqual(box.children[1].textContent,'重试属性更新');
  const before=messages.length;box.children[1].listeners.click();
  assert.strictEqual(messages.length,before+1);assert.strictEqual(messages.at(-1).cmd,'state');
  api.__directLight('node');assert.strictEqual(messages.at(-1).cmd,'state');
  assert(!messages.some(row=>row.cmd==='light'));count++;
}
for(const value of [{status:'applied',reason:''},{status:'unchanged',reason:''},{status:'pending',reason:'pending_actor'}]) {
  const box=element();api.__projectionProbe(value,box);
  assert.notStrictEqual(box.children[1].textContent,'重试属性更新');count++;
}
const box=element();api.__projectionProbe({status:'failed',reason:'injected'},box);
box.children[1].listeners.click();const request=messages.at(-1);api.__close();
handlers.panel_resp({panel:'meridians',callId:request.callId,success:true,projection:{status:'applied',reason:''}});
assert.strictEqual(box.children[1].textContent,'重试属性更新');count++;
console.log(`Meridian production JS + DOM boundary fixtures: ${count} passed (no Host/Flash claim)`);
