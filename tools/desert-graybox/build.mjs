import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import crypto from 'node:crypto';
import { THREE, MODES, createGraybox, disposeGraybox } from './model.mjs';
import { encodeGlb } from './export-glb.mjs';
import { GAME_FRAME, gameFrame } from './composition.mjs';
import { GLTFLoader } from '../../launcher/web/assets/stage-diorama/base-gate/vendor/GLTFLoader.js';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const out = path.join(root, 'tmp/desert-graybox');
const check = process.argv.includes('--check');
const sourcePath = 'docs/design-data/desert-spatial-draft.json';
const data = JSON.parse(await fs.readFile(path.join(root, sourcePath), 'utf8'));
const sha256 = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
const inputFiles = [sourcePath, ...['model.mjs','terrain.mjs','routes.mjs','landmarks.mjs','civil-massing.mjs','military-massing.mjs','environment.mjs','composition.mjs','export-glb.mjs','build.mjs','viewer.mjs','viewer.css','index.html','serve.cjs','style-study.mjs','terrain-study.mjs','landmark-study.mjs','local-detail.mjs','local-ground.mjs','local-navigation.mjs','local-roads.mjs','compare.html'].map(n=>'tools/desert-graybox/'+n),
  ...['three.module.js','three.core.js','GLTFLoader.js','BufferGeometryUtils.js','OrbitControls.js'].map(n=>'launcher/web/assets/stage-diorama/base-gate/vendor/'+n)];
const inputs = Object.fromEntries(await Promise.all(inputFiles.map(async name=>[name,sha256(await fs.readFile(path.join(root,name)))])));
const models = [], stages = data.stageMapping.filter(s=>s.id.startsWith('stage_'));
const manifest = { schema:'desert-graybox/1', status:'candidate_built', source:sourcePath, inputs,
  unitContract:'GLB units are metres. X east, Y candidate elevation multiplied by the documented display exaggeration, Z negative north. Local editable geometry is preserved.',
  limitations:['Not a production game scene','Landmark footprints are symbolic at region/city scales','Road widths, bridge works, artillery trajectories and travel windows are not validated','Hidden review water layers remain separate editable GLB groups'],
  models:[] };
const results = [];
for (const mode of MODES) {
  const model=createGraybox(data,mode);models.push(model);
  const ids=new Set(model.anchors.map(a=>a.id));
  if(mode==='region')for(const s of stages)if(!ids.has(s.place))throw new Error('Missing stage landmark '+s.id);
  for(const anchor of model.anchors){
    const place=data.places.find(p=>p.id===anchor.id);
    if(Math.abs(anchor.world.x-place.xy[0])>1e-9||Math.abs(anchor.world.z+place.xy[1])>1e-9)throw new Error('Moved geographic anchor '+anchor.id);
  }
  const framingChecks=[];
  for(const projection of ['orthographic','perspective']){
    const f=gameFrame(THREE,model,data,mode,projection);
    const c=projection==='orthographic'?new THREE.OrthographicCamera(-f.horizontal/2,f.horizontal/2,f.vertical/2,-f.vertical/2,f.near,f.far):new THREE.PerspectiveCamera(f.fov,GAME_FRAME.aspect,f.near,f.far);
    c.position.copy(f.position);c.lookAt(f.target);c.updateMatrixWorld(true);
    for(const p of f.points){const q=p.clone().project(c);if(q.x<f.safe.left-1e-6||q.x>f.safe.right+1e-6||q.y<f.safe.bottom-1e-6||q.y>f.safe.top+1e-6||Math.abs(q.z)>1)throw new Error('Game frame cropped required content: '+mode+'/'+projection);}
    if(mode==='region')for(const s of data.stageMapping.filter(s=>s.place))if(!f.covered.includes(s.place))throw new Error('Game frame lost entry '+s.id);
    framingChecks.push({projection,logicalFrame:GAME_FRAME,covered:f.covered,position:f.position.toArray(),target:f.target.toArray(),horizontalSpan:f.horizontal,requiredContentInsideSafeFrame:true});
  }
  const bytes=encodeGlb(model.group,{...model.group.userData,sourceSha256:inputs[sourcePath],sourceUnits:'km',exportUnits:'m'});
  const functionalAreas=[];
  model.group.traverse(o=>{if(o.isGroup&&o.userData.subareaId)functionalAreas.push({placeId:o.userData.placeId,subareaId:o.userData.subareaId,label:o.userData.designRole});});
  // Reload through the existing independent GLTFLoader and compare bounds and semantic anchors.
  const buffer=bytes.buffer.slice(bytes.byteOffset,bytes.byteOffset+bytes.byteLength);
  const reloaded=await new GLTFLoader().parseAsync(buffer,'');reloaded.scene.updateMatrixWorld(true);
  const decodedBounds=new THREE.Box3().setFromObject(reloaded.scene);
  const expected=new THREE.Box3(model.bounds.min.clone().multiplyScalar(1000),model.bounds.max.clone().multiplyScalar(1000));
  const delta=Math.max(...decodedBounds.min.toArray().map((v,i)=>Math.abs(v-expected.min.toArray()[i])),...decodedBounds.max.toArray().map((v,i)=>Math.abs(v-expected.max.toArray()[i])));
  if(delta>Math.max(.05,expected.getSize(new THREE.Vector3()).length()*1e-6))throw new Error('GLB bounds changed '+mode+': '+delta);
  let roundTripAnchors=0,roundTripTriangles=0;const importedAreas=new Set();
  reloaded.scene.traverse(o=>{
    if(o.name.startsWith('ANCHOR_')){roundTripAnchors++;if(!Array.isArray(o.userData.geographicXY))throw new Error('GLB lost geographic identity');}
    if(o.isMesh)roundTripTriangles+=(o.geometry.index?.count||o.geometry.attributes.position.count)/3;
    if(!o.isMesh&&o.userData.subareaId)importedAreas.add(o.userData.placeId+':'+o.userData.subareaId);
  });
  if(roundTripAnchors!==model.anchors.length)throw new Error('GLB lost anchors');
  if(roundTripTriangles!==model.metrics.triangles)throw new Error('GLB triangle count changed');
  for(const area of functionalAreas)if(!importedAreas.has(area.placeId+':'+area.subareaId))throw new Error('GLB lost functional group '+area.subareaId);
  const file='desert-'+mode+'.glb';
  results.push({file,bytes});
  manifest.models.push({mode,file,sha256:sha256(bytes),bytes:bytes.length,...model.metrics,roundTripBoundsMaxErrorMeters:delta,roundTripAnchors,roundTripTriangles,functionalAreas,framing:framingChecks});
  console.log(`${mode}: ${model.metrics.meshes} meshes, ${model.metrics.triangles} triangles, ${roundTripAnchors} anchors, ${bytes.length} bytes; GLB round-trip OK`);
}
for(const p of data.places){
  const heights=models.map(m=>m.terrain.heightAt(...p.xy));
  if(Math.max(...heights)-Math.min(...heights)>1e-8)throw new Error('Cross-scale height mismatch '+p.id);
}
for(const s of data.baseProfile.samples){const p=data.places.find(p=>p.id===s.place);if(Math.abs(models[2].terrain.heightAt(...p.xy)-s.heightM)>1e-6)throw new Error('Profile mismatch '+s.place);}
manifest.checks={activeStageCount:stages.length,sharedGeographicAnchors:true,sharedPhysicalHeights:true,candidateProfileMatched:true,glbRoundTrip:true};
results.push({file:'manifest.json',bytes:Buffer.from(JSON.stringify(manifest,null,2)+'\n')});
if(check){
  for(const item of results){const previous=await fs.readFile(path.join(out,item.file));if(!Buffer.from(item.bytes).equals(previous))throw new Error('Stale derived output: '+item.file);}
  console.log('check: all generated models and manifest match current inputs');
}else{
  await fs.mkdir(out,{recursive:true});
  for(const item of results)await fs.writeFile(path.join(out,item.file),item.bytes);
  console.log('Built editable grayboxes under '+out);
}
models.forEach(disposeGraybox);
