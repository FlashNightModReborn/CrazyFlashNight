'use strict';
// Read the shipped assets and the authoritative catalog independently of the importer.
const fs=require('fs'),path=require('path'),vm=require('vm'),assert=require('assert/strict');
const root=path.resolve(__dirname,'..'),dir=path.join(root,'launcher/web/assets/stage-diorama/fallen-city');
const ctx={};for(const p of ['launcher/web/modules/stage-select-data.js','launcher/web/modules/stage-select/stage-select-fallen-data.js'])vm.runInNewContext(fs.readFileSync(path.join(root,p),'utf8'),ctx);
const c=JSON.parse(JSON.stringify(ctx.StageSelectFallenData));
const frame=JSON.parse(JSON.stringify(ctx.StageSelectData.exportManifest().frames.find(f=>f.frameLabel===c.frameLabel)));
assert.deepEqual(frame,JSON.parse(fs.readFileSync(path.join(dir,'game-frame.snapshot.json'),'utf8')));
assert.deepEqual(c.entries.map(e=>e.id).sort(),frame.stageButtons.map(e=>e.id).sort());
assert.deepEqual(c.navigation.map(e=>e.id).sort(),frame.navButtons.map(e=>e.id).sort());
const bytes=fs.readFileSync(path.join(dir,'selection.glb')),g=JSON.parse(bytes.subarray(20,20+bytes.readUInt32LE(12)));
const units=new Set(g.nodes.filter(n=>n.mesh!==undefined).map(n=>n.extras.buildingId));assert.equal(units.size,70);
for(const e of c.entries)for(const id of Object.values(e.relations).flat())assert.ok(units.has(id),e.id+' missing unit '+id);
for(const [id,part] of [['stage_10_9','assembly'],['stage_10_5','residential']]){
 const e=c.entries.find(e=>e.id===id);assert.deepEqual(e.selectionPartitions.AS01,[part]);
 assert.ok(g.nodes.some(n=>n.extras?.buildingId==='AS01'&&n.extras.selectionPart===part));
}
assert.deepEqual(c.entries.find(e=>e.id==='stage_10_9').worldAnchor,[-26.7,14.2,30]);
const campaign=c.entries.find(e=>e.name==='堕落城保卫战');assert.ok(campaign.relations.main.length>=8);
const boxes=[];for(const [id,p] of Object.entries(c.pins)){
 const x=p.x+p.labelX,y=p.y+p.labelY;boxes.push({id,x:x-p.labelWidth/2,y:y-16,w:p.labelWidth,h:32});
 if(id.startsWith('stage'))boxes.push({id,x:p.x-20,y:p.y-20,w:40,h:40});
}
for(let i=0;i<boxes.length;i++){const a=boxes[i];assert.ok(a.x>=0&&a.y>=54&&a.x+a.w<=1024&&a.y+a.h<=576,a.id+' outside');for(let j=i+1;j<boxes.length;j++){const b=boxes[j];if(a.id!==b.id)assert.ok(!(a.x<b.x+b.w&&b.x<a.x+a.w&&a.y<b.y+b.h&&b.y<a.y+a.h),a.id+' overlaps '+b.id);}}
const registry=fs.readFileSync(path.join(root,'launcher/web/modules/panels-lazy-registry.js'),'utf8');assert.ok(registry.includes('stage-select-fallen-data.js'));
console.log(JSON.stringify({pass:true,stages:c.entries.length,units:units.size,worldPins:Object.keys(c.pins).length,layoutBoxes:boxes.length,checks:['current game identities','AS01 partition contract','campaign extent','default label/marker bounds','production script registration']}));
