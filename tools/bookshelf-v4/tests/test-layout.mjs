import {target,targetUrl,resultFile} from './target.mjs';
import fs from 'node:fs';import assert from 'node:assert/strict';
const THREE=await import(targetUrl('web/assets/stage-diorama/base-gate/vendor/three.module.js'));
const {layoutFor,validateLayout,chooseLayout,aabbOverlap}=await import(targetUrl('web/modules/layout-core.mjs'));
const {applyLayout}=await import(targetUrl('web/modules/layout-three.js'));
import {loadGeometryGlb,box} from './load-glb.mjs';
const {root}=loadGeometryGlb(target('web/assets/bookshelf/shelf/v3.glb'),THREE),baseline=new Map();root.traverse(n=>baseline.set(n.uuid,{q:n.quaternion.toArray(),s:n.scale.toArray()}));
const results=[];for(const key of ['wide','medium','narrow','wide']){const l=layoutFor(key),applied=applyLayout(root,key,THREE);const errors=[],actual=[];assert.equal(validateLayout(l).ok,true);
 for(const item of l.items){const node=root.getObjectByName(item.name),bounds=box(node,THREE),old=baseline.get(node.uuid);assert.deepEqual(node.scale.toArray(),old.s);assert.deepEqual(node.quaternion.toArray(),old.q);actual.push({...item,aabb:bounds});for(let a=0;a<3;a++){if(bounds.min[a]<item.aabb.min[a]-.002||bounds.max[a]>item.aabb.max[a]+.002)errors.push(`${item.name}: actual geometry exceeds metadata envelope axis ${a}: ${JSON.stringify(bounds)} vs ${JSON.stringify(item.aabb)}`);}}
 for(const item of actual){for(const board of l.boards)if(aabbOverlap(item.aabb,board.aabb,1e-4))errors.push(`${item.name} intersects ${board.name}`);for(const slot of l.reserveSlots)if(aabbOverlap(item.aabb,slot.aabb,1e-4))errors.push(`${item.name} intersects ${slot.id}`);}
 for(let i=0;i<actual.length;i++)for(let j=i+1;j<actual.length;j++)if(aabbOverlap(actual[i].aabb,actual[j].aabb,1e-4))errors.push(`${actual[i].name} intersects ${actual[j].name}`);
 for(const slot of l.reserveSlots)for(const board of l.boards)if(aabbOverlap(slot.aabb,board.aabb,1e-4))errors.push(`${slot.id} intersects ${board.name}`);
 // Open drawer at 21 points, checking all other solid objects and boards.
 const drawer=root.getObjectByName('ARCHIVE_ALL_DRAWER'),rest=drawer.position.z;
 for(let n=0;n<=20;n++){drawer.position.z=rest+3.15*n/20;const d=box(drawer,THREE);for(const item of actual.filter(x=>x.name!==drawer.name))if(aabbOverlap(d,item.aabb,1e-4))errors.push(`drawer t=${n/20} intersects ${item.name}`);for(const board of l.boards)if(aabbOverlap(d,board.aabb,1e-4))errors.push(`drawer t=${n/20} intersects ${board.name}`);}drawer.position.z=rest;
 results.push({key,pass:!errors.length,reserves:l.reserveSlots.length,height:l.height,errors});}
assert.equal(chooseLayout(1.40,'wide'),'wide');assert.equal(chooseLayout(.86,'narrow'),'narrow');
fs.writeFileSync(resultFile('layout-results.json'),JSON.stringify({scope:'Actual GLB vertex AABBs with actual Three layout transform; conservative bounding boxes, not triangle collision or browser render',results},null,2));console.log(JSON.stringify(results,null,2));process.exitCode=results.some(r=>!r.pass)?1:0;
