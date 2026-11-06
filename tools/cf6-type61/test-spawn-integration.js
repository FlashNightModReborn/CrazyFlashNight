"use strict";
// Same-source control-flow checks; native display/spawn behavior needs Flash.
const fs=require("node:fs"),path=require("node:path"),vm=require("node:vm");
const {test}=require("node:test"),assert=require("node:assert/strict");
const {functionBody,eraseTypes}=require("../cf6-soldier-assets/offline/as2-source");
const file=path.resolve(__dirname,"../../scripts/类定义/org/flashNight/arki/scene/WaveSpawner.as");
const source=fs.readFileSync(file,"utf8").replace(/public function spawn\(/,"\nspawn=function(");
const body=eraseTypes(functionBody(source,"spawn"));
function fixture({fixed=false,nest=false,born={},full=false}={}) {
  const point={QuantityMax:3,僵尸型敌人场上实际人数:full?3:0,僵尸型敌人总个数:4};
  const group={SpawnIndex:0,Level:37,Parameters:fixed?{cf6FixedSlots:["seat"]}:{},x:7,y:8};
  const calls=[],prepared=[];
  const c=vm.createContext({waveInfo:[{1:group}],spawnPoints:[point],gameworld:{地图:point,__noahMotherEncounter:nest?{}:undefined},
    ObjectUtil:{clone:x=>({...x}),cloneParameters:Object.assign},
    org:{flashNight:{arki:{scene:{Cf6SoldierRoster:{prepare(g,n,params){prepared.push(n);params.fixed=true;return{x:341,y:420};}}}}}},
    spawnEnemy(...args){calls.push(args);return born;}});
  vm.runInContext("var spawn="+body,c,{filename:file});
  return {point,calls,prepared,spawn:(enemy=true)=>c.spawn({兵种名:"soldier",名字:"unit",是否为敌人:enemy},1,0,1,2)};
}
test("fixed CF6 placement and provenance survive the upstream integration",()=>{
  const f=fixture({fixed:true});assert.equal(f.spawn(),true);assert.deepEqual(f.prepared,[2]);
  const a=f.calls[0];assert.equal(a[4],341);assert.equal(a[5],420);
  assert.equal(a[2].cf6SpawnWave,1);assert.equal(a[2].cf6SpawnEntry,0);assert.equal(a[2].cf6SpawnOrdinal,2);
  assert.equal(f.point.僵尸型敌人场上实际人数,1);
});
test("rejected Noah spawn keeps the point population and reports no birth",()=>{
  const f=fixture({nest:true,born:null});assert.equal(f.spawn(),false);assert.equal(f.calls.length,1);
  assert.equal(f.point.僵尸型敌人场上实际人数,0);assert.equal(f.point.僵尸型敌人总个数,4);
});
test("accepted ordinary spawn keeps authored position and increments population once",()=>{
  const f=fixture({nest:true});assert.equal(f.spawn(),true);assert.equal(f.calls[0][4],7);assert.equal(f.calls[0][5],8);
  assert.equal(f.prepared.length,0);assert.equal(f.point.僵尸型敌人场上实际人数,1);
});
test("full native spawn point refuses before fixed placement or attachment",()=>{
  const f=fixture({fixed:true,full:true});assert.equal(f.spawn(),false);assert.equal(f.calls.length,0);
  assert.equal(f.prepared.length,0);assert.equal(f.point.僵尸型敌人场上实际人数,3);
});
test("friendly spawn retains the existing non-enemy count path",()=>{
  const f=fixture();assert.equal(f.spawn(false),true);assert.equal(f.point.僵尸型敌人场上实际人数,0);
  assert.equal(f.point.僵尸型敌人总个数,3);
});
