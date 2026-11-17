#!/usr/bin/env node
'use strict';

// Executes the checked-in AS2 producer bodies with domain stubs. This proves the
// projection/transport contract only: JS is not an AVM1 oracle, and the bounded
// MovieClip stub does not prove linkage loading in Flash. Fresh CS6 remains a gate.
const fs = require('fs');
const path = require('path');
const vm = require('vm');
const assert = require('assert');
const root = path.resolve(__dirname, '..');
const packageDir = 'scripts/类定义/org/flashNight/gesh/tooltip/';
let passed = 0;
function test(name, fn) { fn(); passed++; console.log('ok - ' + name); }
function plain(value) { return JSON.parse(JSON.stringify(value)); }

// Syntax-only adaptation for these two static classes. Protect strings before
// removing AS2 type annotations; the function bodies come from production source.
function loadStaticClass(file, exports, context) {
  const bytes = fs.readFileSync(path.join(root, file));
  assert(bytes.subarray(0, 3).equals(Buffer.from([0xef, 0xbb, 0xbf])), file + ' BOM');
  const literals = [];
  let source = bytes.toString('utf8').replace(/^\uFEFF/, '').replace(
    /\/\*[\s\S]*?\*\/|\/\/[^\r\n]*|"(?:\\[\s\S]|[^"\\])*"|'(?:\\[\s\S]|[^'\\])*'/g,
    token => token.startsWith('/') ? '' : '__LITERAL_' + (literals.push(token) - 1) + '__');
  source = source.replace(/^\s*import\s+[^;]+;/gm, '')
    .replace(/class\s+[\w.]+\s*\{/, '(function () {')
    .replace(/\b(?:public|private)\s+static\s+/g, '')
    .replace(/\b(var\s+[\w$]+)\s*:\s*[\w.]+/g, '$1')
    .replace(/\bfunction\s*([\w$]+)?\s*\(([^)]*)\)\s*(?::\s*[\w.]+)?/g,
      (_, name, args) => 'function ' + (name || '') + '(' + args.replace(/:\s*[\w.]+/g, '') + ')');
  source = source.trim().replace(/\}\s*$/, 'return {' + exports.join(',') + '}; })()')
    .replace(/__LITERAL_(\d+)__/g, (_, index) => literals[Number(index)]);
  return vm.runInContext(source, context, {filename: file, timeout: 2000});
}

function fixture() {
  const calls = [];
  const state = {ready:true, records:[{kind:'drop', dropType:'enemy', enemyType:'enemy.known', variants:[{unused:true}], probability:20}]};
  const item = {name:'test.gun', displayname:'配置名', icon:'base.icon', type:'武器', use:'长枪',
    weapontype:'霰弹枪', data:{power:100, bullet:'普通子弹', level:2, modslot:2}};
  const mod = {name:'test.mod', grantsUseDict:{手枪:true}, stats:{}, subweapon:{name:'副武器'}};
  const calculated = {displayname:'真实涂装名', icon:'real.icon', use:'长枪', weapontype:'霰弹枪',
    description:'真实实例说明', data:{power:333, bullet:'穿刺子弹', level:2, modslot:2},
    lifecycle:{lamp:{__modName:'test.mod', init:{initRoutines:'装备光源初始化', initParam:{kind:'flashlight'}}}},
    transactionJournal:{secret:'never send'}, elite:{power:999}};
  const instance = {name:item.name, value:{level:5, tier:'二阶', mods:['test.mod','rejected.mod'], privateTransaction:'never send'},
    getData() { calls.push('getData'); return calculated; }};
  const items = {[item.name]:item, 'test.mod':{name:'test.mod', type:'收集品', use:'材料'},
    'display.mod':{name:'display.mod', type:'收集品', use:'材料'},
    'test.drug':{name:'test.drug', type:'消耗品', use:'药剂', data:{effects:{effect:{type:'hp', value:45}}}}};
  const itemUtil = {getItemData:name => items[name], isEquipment:name => name === item.name,
    isMaterial:name => name === 'test.mod' || name === 'display.mod', isInformation:() => false};
  const equipment = {modDict:{'test.mod':mod}, levelStatList:{5:1.75}};
  const registry = {
    getModDict:() => equipment.modDict,
    getModDataByDisplayName:name => name === 'display.mod' ? mod : null,
    buildItemUseLookup:(use, type, granted) => { calls.push(['lookup',use,type,plain(granted)]); return {use,type,granted}; },
    matchUseSwitchAll:(value, lookup) => { calls.push(['use',value.name,lookup.type]); return [{name:'weapontype:霰弹枪',_isDefault:false,override:{power:222}}]; },
    matchBulletSwitchAll:(value, bullet) => { calls.push(['bullet',value.name,bullet]); return [{name:'normal',multiplier:{power:0.2}}]; },
    resolveSkillForUse:() => ({skillname:'权威当前战技'})
  };
  const context = vm.createContext({Array,Object,Number,String,Boolean,Math,isFinite,isNaN,
    MovieClip:function MovieClip(){}, ItemUtil:itemUtil, EquipmentUtil:equipment, ModRegistry:registry,
    TagManager:{buildPresentTagsDict:(mods, data) => { calls.push(['tags',data.icon]); return {'电力':true}; }},
    TierSystem:{getAllTierOptionsByName:name => [{name:'二阶', available:true, material:'强化石'}]},
    SubweaponDataUtil:{normalizeSubweapon:value => value ? {name:value.name, normalizedByDomain:true} : null},
    DrugEffectNormalizer:{normalize:data => { calls.push('drugNormalizer'); return [data.effects.effect]; }},
    BulletTypeUtil:{isVertical:bullet => { calls.push(['vertical',bullet]); return false; }},
    TooltipDataSelector:{getEquipmentData:(data,tier) => { calls.push(['tier',tier]); return data.data; }},
    ItemObtainIndex:{getInstance:() => ({isIndexBuilt:() => state.ready, getObtainRecords:() => state.records})},
    StringUtils:{trim:value => String(value).trim()},
    _root:{敌人属性表:{'enemy.known':{displayname:'已发现敌人'}},主角技能表:[['skill.one',3,true,0,false]],
      技能表对象:{'skill.one':{Name:'技能一',Type:'主动',CD:1500,MP:10,Description:'说明',Equippable:true,privateState:'no'}},
      技能表:[{Name:'学习一',MaxLevel:5,UnlockSP:2,Description:'学习说明'}]}
  });
  const api = loadStaticClass(packageDir+'TooltipInputProjection.as',
    ['forItem','preview','loadoutSkill','learningSkill','body'], context);
  return {api,context,calls,state,item,mod,calculated,instance,items,equipment};
}

test('real calculated values, baseline, branch decisions and narrow identity survive detached projection', () => {
  const f = fixture();
  const before = JSON.stringify([f.item,f.instance.value,f.calculated,f.mod]);
  const input = f.api.forItem(f.item.name,{},f.instance,'inventory');
  assert.equal(input.version,1); assert.equal(input.kind,'item');
  assert.equal(input.projection.calculated.data.power,333);
  assert.equal(input.projection.baselineData.power,100);
  assert.equal(input.projection.levelMultiplier,1.75);
  assert.equal(input.projection.calculated.icon,'real.icon');
  assert.equal(input.projection.calculated.lifecycle.lamp.__modName,'test.mod');
  assert.equal(input.projection.calculated.transactionJournal,undefined);
  assert.equal(input.projection.calculated.elite,undefined);
  assert.equal(input.value.privateTransaction,undefined);
  assert.equal(f.calls.filter(call => call === 'getData').length,1);
  assert(f.calls.some(call => Array.isArray(call) && call[0] === 'bullet' && call[2] === '普通子弹'));
  assert(f.calls.some(call => Array.isArray(call) && call[0] === 'lookup' && call[3]['手枪'] === true));
  assert.equal(input.projection.mods['test.mod'].present,true);
  assert.equal(input.projection.mods['rejected.mod'].present,false);
  assert.deepEqual(plain(input.projection.mods['rejected.mod'].useCases),[]);
  assert.deepEqual(plain(input.projection.drugEffects),[]);
  assert.equal(input.projection.electric,true);
  assert.equal(JSON.stringify([f.item,f.instance.value,f.calculated,f.mod]),before);
  input.value.mods.push('mutated dto'); input.projection.calculated.data.power = 0;
  assert.equal(f.instance.value.mods.length,2); assert.equal(f.calculated.data.power,333);
});

test('only discovered source records cross wire and runtime enemy name is frozen', () => {
  const f = fixture();
  const input = f.api.forItem(f.item.name,{level:1},null,'web');
  assert.deepEqual(plain(input.projection.obtainRecords),[
    {kind:'drop',dropType:'enemy',enemyType:'enemy.known',enemyDisplayName:'已发现敌人'}]);
  assert.equal(f.state.records[0].enemyDisplayName,undefined);
  f.state.ready = false;
  assert.deepEqual(plain(f.api.forItem(f.item.name,{level:1},null,'web').projection.obtainRecords),[]);
});

test('preview does not compute an equipment instance and non-applicable arrays stay explicit', () => {
  const f = fixture();
  const input = f.api.forItem(f.item.name,{level:1},null,'web');
  assert.equal(input.projection.calculated,null);
  assert(!f.calls.includes('getData'));
  const drug = f.api.forItem('test.drug',{count:4},null,'native');
  assert.deepEqual(plain(drug.projection.tierOptions),[]);
  assert.deepEqual(plain(drug.projection.drugEffects),[{type:'hp',value:45}]);
  assert.equal(drug.value.count,4); assert.equal(drug.presentation,'native');
  assert(f.calls.includes('drugNormalizer'));
  f.items['test.fieldkit'] = {name:'test.fieldkit',type:'收集品',use:'材料',data:{effects:{effect:{value:99}}}};
  const fieldkit = f.api.forItem('test.fieldkit',{level:1},null,'web');
  assert.equal(fieldkit.projection.isEquipment,false);
  assert.equal(fieldkit.projection.baselineData.effects.effect.value,99);
});

test('registered standalone mod identity and normalized subweapon cannot revive a rejected catalog entry', () => {
  const f = fixture();
  const input = f.api.forItem('display.mod',{level:1},null,'web');
  assert.equal(input.projection.registeredModName,'test.mod');
  assert.equal(input.projection.subweapon.normalizedByDomain,true);
  delete f.equipment.modDict['test.mod'];
  const missing = f.api.forItem('test.mod',{level:1},null,'web');
  assert.equal(missing.projection.registeredModName,null);
  assert.equal(missing.projection.subweapon,null);
});

test('NaN/Infinity and undefined array entries have explicit wire tokens; null stays null', () => {
  const f = fixture();
  f.calculated.data.special = [NaN,Infinity,-Infinity,undefined,null];
  f.calculated.data.omitted = undefined;
  f.calculated.data.__dictUID = 123;
  const wire = plain(f.api.forItem(f.item.name,{},f.instance,'inventory'));
  assert.deepEqual(wire.projection.calculated.data.special,[
    {__tooltipNumber:'NaN'},{__tooltipNumber:'Infinity'},{__tooltipNumber:'-Infinity'},
    {__tooltipUndefined:true},null]);
  assert(!Object.hasOwn(wire.projection.calculated.data,'omitted'));
  assert(!Object.hasOwn(wire.projection.calculated.data,'__dictUID'));
});

test('missing item and failed authoritative getData never become base-catalog success', () => {
  const f = fixture();
  assert.equal(f.api.forItem('unknown',{},f.instance,'native'),null);
  f.instance.getData = () => null;
  assert.equal(f.api.forItem(f.item.name,{},f.instance,'inventory'),null);
});

test('input values are bounded data and a cyclic object fails the projection instead of hanging', () => {
  const f = fixture();
  f.calculated.data.cycle = f.calculated.data;
  assert.throws(() => f.api.forItem(f.item.name,{},f.instance,'inventory'), error => error === 'tooltip_projection_depth');
});

test('skill projection reads live learned/equipped state and exports no arbitrary metadata', () => {
  const f = fixture();
  const input = f.api.loadoutSkill(0);
  assert.equal(input.kind,'skill'); assert.equal(input.mode,'loadout');
  assert.equal(input.skillName,'skill.one');
  assert.deepEqual(plain(input.state),{level:3,equipped:true,enabled:false});
  assert.equal(input.skillData.privateState,undefined);
  assert.equal(f.api.learningSkill(0).skillData.Name,'学习一');
  assert.equal(f.api.body('<B>来自既有文本生产者</B>','dense').kind,'body');
});

test('blade exception prefers authored count and keeps the original bounded probe/cached result', () => {
  const f = fixture();
  f.item.use = '刀'; f.item.data.bladeCount = 5;
  assert.equal(f.api.forItem(f.item.name,{level:1},null,'native').projection.bladeCount,5);
  let attached = 0;
  delete f.item.data.bladeCount;
  f.item.data.dressup = '刀-测试';
  const container = {tempBlade:null,getNextHighestDepth:() => 1,attachMovie:() => {
    attached++; const clip = new f.context.MovieClip();
    clip['刀口位置1'] = {}; clip['刀口位置2'] = {}; clip['刀口位置3'] = {};
    clip.removeMovieClip = () => {}; return clip;
  }};
  f.context._root.createEmptyMovieClip = () => container;
  assert.equal(f.api.forItem(f.item.name,{level:1},null,'native').projection.bladeCount,3);
  assert.equal(f.api.forItem(f.item.name,{level:1},null,'native').projection.bladeCount,3);
  assert.equal(attached,1);
});

test('native bridge preserves request/scene/anchor identity and stale hide cannot retire the latest input', () => {
  let serial = 0; const sent = []; const teardowns = [];
  const owner = {nextRequestId:() => 'ni:'+ ++serial,getSceneId:() => 'scene:42',install(){},onSceneTeardown:fn => teardowns.push(fn)};
  const context = vm.createContext({Array,Object,Number,String,Boolean,Math,isNaN,
    _global:{org:{flashNight:{arki:{interaction:{NativeInteractionContext:owner}}}}},
    org:{flashNight:{arki:{item:{itemIcon:{ItemIcon:{prototype:{}}}}}}},
    _root:{_xmouse:42,_ymouse:80,server:{isSocketConnected:true,sendTaskToNode:(task,payload) => { sent.push({task,payload}); return true; }}}
  });
  const api = loadStaticClass(packageDir+'NativeTooltipBridge.as',
    ['show','hide','hideCurrent','reset','activeRequestId','activeSceneId','install'],context);
  context.NativeTooltipBridge = api;
  const input = {version:1,kind:'body',html:'x'};
  const first = api.show(input,null,'top',{x:10,y:20,width:40,height:50});
  const second = api.show(input,null,'bottom');
  api.hide(first);
  assert.equal(api.activeRequestId(),second);
  assert.equal(sent[0].payload.document,undefined);
  assert.strictEqual(sent[0].payload.tooltipInput,input);
  assert.equal(sent[0].payload.sceneId,'scene:42');
  assert.deepEqual(plain(sent[0].payload.anchorRect),{x:10,y:20,width:40,height:50});
  assert.equal(sent[0].payload.x,30);
  assert.equal(teardowns.length,1);
  teardowns[0]();
  assert.equal(api.activeRequestId(),null);
  assert.equal(sent.at(-1).payload.requestId,second);
});

test('missing AVM1 information capacity remains an explicit false on the wire', () => {
  const f = fixture();
  f.context.ItemUtil.isInformation = () => undefined;
  const input = f.api.forItem(f.item.name,{},f.instance,'inventory');
  const wire = JSON.parse(JSON.stringify(input));
  assert.equal(wire.projection.isInformation,false);
  f.context.ItemUtil.isInformation = () => true;
  assert.equal(f.api.forItem(f.item.name,{},f.instance,'inventory').projection.isInformation,true);
});

console.log('TooltipInput producer mock: ' + passed + ' passed. Evidence: JS bodies + domain stubs; AVM1 not executed.');
