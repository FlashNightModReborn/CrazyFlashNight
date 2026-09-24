import fs from 'node:fs';
import assert from 'node:assert/strict';
import * as THREE from '../launcher/web/assets/stage-diorama/base-gate/vendor/three.module.js';
import {partitionGeometry,usePortableIndices} from '../launcher/web/modules/stage-select/stage-select-geometry-chunks.js';

const file=new URL('../launcher/web/assets/stage-diorama/fallen-city/city.glb',import.meta.url),raw=fs.readFileSync(file);
const length=raw.readUInt32LE(12),gltf=JSON.parse(raw.subarray(20,20+length)),binary=raw.subarray(28+length);
function attribute(index){
    const a=gltf.accessors[index],v=gltf.bufferViews[a.bufferView],size={SCALAR:1,VEC2:2,VEC3:3,VEC4:4}[a.type];
    const Type={5126:Float32Array,5125:Uint32Array,5123:Uint16Array,5121:Uint8Array}[a.componentType];
    const array=new Type(a.count*size),view=new DataView(binary.buffer,binary.byteOffset,binary.byteLength);
    const read={5126:'getFloat32',5125:'getUint32',5123:'getUint16',5121:'getUint8'}[a.componentType];
    for(let i=0;i<a.count;i++)for(let k=0;k<size;k++)array[i*size+k]=view[read]((v.byteOffset||0)+(a.byteOffset||0)+i*(v.byteStride||Type.BYTES_PER_ELEMENT*size)+k*Type.BYTES_PER_ELEMENT,true);
    return new THREE.BufferAttribute(array,size,!!a.normalized);
}
const semantic={POSITION:'position',NORMAL:'normal',TEXCOORD_0:'uv',TEXCOORD_1:'uv1',COLOR_0:'color',TANGENT:'tangent'};
let batches=0,triangles=0,totalChunks=0,comparedComponents=0;
for(const node of gltf.nodes){
    if(node.mesh===undefined)continue;
    for(const p of gltf.meshes[node.mesh].primitives){
        if(gltf.accessors[p.indices].componentType!==5125)continue;
        const geometry=new THREE.BufferGeometry();geometry.setIndex(attribute(p.indices));
        for(const [key,index] of Object.entries(p.attributes)){assert.ok(semantic[key],key);geometry.setAttribute(semantic[key],attribute(index));}
        const chunks=partitionGeometry(geometry);assert.ok(chunks.length>1);let cursor=0;
        for(const c of chunks){
            assert.ok(c.index.array instanceof Uint16Array);assert.ok(c.attributes.position.count<=60000);
            assert.equal(c.index.count%3,0);
            for(const [name,a] of Object.entries(geometry.attributes)){
                const b=c.attributes[name];assert.equal(b.normalized,a.normalized);assert.equal(b.array.constructor,a.array.constructor);
                for(let i=0;i<c.index.count;i++)for(let k=0;k<a.itemSize;k++){
                    assert.equal(b.array[c.index.array[i]*b.itemSize+k],a.array[geometry.index.array[cursor+i]*a.itemSize+k],node.name+' '+name);
                    comparedComponents++;
                }
            }
            cursor+=c.index.count;
        }
        assert.equal(cursor,geometry.index.count);batches++;triangles+=cursor/3;totalChunks+=chunks.length;
        const root=new THREE.Group(),mesh=new THREE.Mesh(geometry,new THREE.MeshBasicMaterial());mesh.name=node.name;mesh.userData={buildingId:'test',cutaway:'bar'};mesh.position.set(3,4,5);mesh.rotation.set(.1,.2,.3);mesh.scale.set(2,3,4);root.add(mesh);
        const before=new THREE.Box3().setFromObject(root,true),report=usePortableIndices(root),after=new THREE.Box3().setFromObject(root,true);
        assert.ok(before.min.distanceTo(after.min)<1e-4&&before.max.distanceTo(after.max)<1e-4);assert.equal(report.inputTriangles,report.outputTriangles);
        const group=root.getObjectByName(node.name);assert.ok(group.isGroup);assert.ok(group.children.every(c=>c.material===mesh.material&&c.userData.cutaway==='bar'));
    }
}
assert.equal(batches,1);assert.equal(triangles,172371);
const small=new THREE.BoxGeometry();assert.equal(partitionGeometry(small),null);
console.log(JSON.stringify({pass:true,batches,triangles,totalChunks,comparedComponents,checks:['exact triangle order and all raw attributes','Uint16 only, bounded vertices','material and semantic tags','world bounds/transforms','unchanged small meshes']}));
