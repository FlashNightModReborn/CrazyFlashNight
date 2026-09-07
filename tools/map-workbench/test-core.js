'use strict';
const fs=require('fs'),path=require('path'),cp=require('child_process'),assert=require('assert');
const root=path.resolve(__dirname,'../..'),tmp=path.join(root,'tmp');fs.mkdirSync(tmp,{recursive:true});
const work=fs.mkdtempSync(path.join(tmp,'map-core-test-'));
const dotnet=process.env.CF7_DOTNET||path.join(process.env.LOCALAPPDATA,'Microsoft/dotnet/dotnet.exe');
const dll=path.join(__dirname,'bin/Release/net10.0/MapWorkbench.dll');
const file=path.join(work,'data/map/map_definition.json');fs.mkdirSync(path.dirname(file),{recursive:true});
// Frozen V1 receipt compatibility only; V2 content journeys live in test-ui-* and C# tests.
const original=cp.execFileSync('git',['show','3ac9227cbdfdeb6d73f99e408414b03bfc338b5d:data/map/map_definition.json'],{cwd:root});fs.writeFileSync(file,original);
let checks=0;function check(label,fn){fn();checks++;console.log('PASS '+label);}
function api(request){const r=cp.spawnSync(dotnet,[dll,'api',work],{input:JSON.stringify(request),encoding:'utf8',maxBuffer:4e6});if(r.error)throw r.error;return JSON.parse(r.stdout);}
try {
 const read=api({op:'read'});assert(read.success,read.error);const d=read.data.definition,digest=read.data.digest;
 check('C# 读取完整四页定义',()=>assert.equal(Object.keys(d.pages).length,4));
 const v=d.pages.base.sceneVisuals[0];const changes=[{pageId:'base',kind:'scene',id:v.id,values:{rect:{...v.rect,x:v.rect.x+12.5}}}];
 const preview=api({op:'preview',expectedDigest:digest,changes});
 check('候选图块与热点边界同步',()=>{assert(preview.success,preview.error);assert.equal(preview.data.definition.pages.base.hotspots[0].rect.x,d.pages.base.hotspots[0].rect.x+12.5);});
 check('预览零项目写入',()=>assert(fs.readFileSync(file).equals(original)));
 check('地点身份与任务分组不变',()=>assert.deepStrictEqual(preview.data.definition.pageUnlockGroups,d.pageUnlockGroups));
 check('拒绝修改导航目标',()=>assert.equal(api({op:'preview',expectedDigest:digest,changes:[{pageId:'base',kind:'hotspot',id:d.pages.base.hotspots[0].id,values:{sceneName:'任意帧'}}]}).success,false));
 check('拒绝修改 NPC 身份',()=>assert.equal(api({op:'preview',expectedDigest:digest,changes:[{pageId:'base',kind:'avatar',id:d.pages.base.staticAvatars[0].id,values:{label:'另一个 NPC'}}]}).success,false));
 check('拒绝非正尺寸',()=>assert.equal(api({op:'preview',expectedDigest:digest,changes:[{pageId:'base',kind:'scene',id:v.id,values:{rect:{...v.rect,w:0}}}]}).success,false));
 const operationId='a'.repeat(32),request={op:'apply',expectedDigest:digest,changes,operationId};
 const applied=api(request);check('保存成功且可重启读取',()=>{assert(applied.success,applied.error);assert.equal(api({op:'read'}).data.digest,applied.data.digest);assert.equal(applied.data.state,'applied');});
 check('相同操作重试不重复修改',()=>assert.equal(api(request).data.digest,applied.data.digest));
 check('同一操作不能改绑',()=>assert.equal(api({...request,changes:[]}).success,false));
 check('旧摘要阻止覆盖',()=>assert.equal(api({...request,operationId:'b'.repeat(32)}).success,false));
 check('查询对账返回实际文件状态',()=>assert.equal(api({op:'query',operationId}).data.state,'applied'));
 const after=fs.readFileSync(file);fs.writeFileSync(file,Buffer.concat([after,Buffer.from(' ')]));
 check('撤回保护后续修改',()=>assert.equal(api({op:'undo',operationId}).success,false));
 fs.writeFileSync(file,after);
 check('撤回恢复原始字节',()=>{assert(api({op:'undo',operationId}).success);assert(fs.readFileSync(file).equals(original));});
 check('撤回重试幂等',()=>assert.equal(api({op:'undo',operationId}).data.state,'original'));
 check('拒绝目录穿越操作编号',()=>assert.equal(api({op:'query',operationId:'../elsewhere'}).success,false));
 const native=cp.spawnSync(dotnet,[dll,'hud',work],{encoding:'utf8',maxBuffer:4e6});const actual=JSON.parse(native.stdout).hotspots;
 const legacy=require('./renderer-contract.js'),web=legacy.loadMapData(d),expected={};
 web.getAllHotspotIds().forEach(id=>{expected[id]=legacy.buildHotspotEntry(web,id);});
 check('C# NativeHud 与生产地图的当前定义投影逐字段一致',()=>assert.deepStrictEqual(actual,JSON.parse(JSON.stringify(expected))));
 check('改名后的层级筛选不改变 HUD 聚焦',()=>{
  const renamed=JSON.parse(JSON.stringify(d)),page=renamed.pages.base,layer=page.filters.find(f=>f.id==='hierarchy');
  assert(layer,'frozen base hierarchy filter is required');
  layer.id='copied-layer-view';layer.viewMode='hierarchy';layer.hotspotIds=[page.hotspots[0].id];
  const renamedWeb=legacy.loadMapData(renamed);
  assert.deepStrictEqual(JSON.parse(JSON.stringify(legacy.buildHotspotEntry(renamedWeb,page.hotspots[0].id))),JSON.parse(JSON.stringify(expected[page.hotspots[0].id])));
 });
 console.log(checks+' map core checks passed');
} finally {assert(work.startsWith(path.resolve(tmp)+path.sep));fs.rmSync(work,{recursive:true});}
