import * as THREE from '../../assets/stage-diorama/base-gate/vendor/three.module.js';

// Static glTF batches only. Preserve triangle order and raw attributes while keeping
// every draw below the 16-bit index limit (including the reserved restart index).
export function partitionGeometry(geometry,limit=60000) {
    if(!Number.isInteger(limit)||limit<3||limit>65534)throw new RangeError('Invalid vertex limit');
    if(!geometry.index || geometry.index.array instanceof Uint16Array || geometry.index.array instanceof Uint8Array)return null;
    if(geometry.groups.length || Object.keys(geometry.morphAttributes).length || geometry.drawRange.start!==0 || geometry.drawRange.count!==Infinity)throw new Error('Unsupported static batch');
    const input=geometry.index.array,attributes=Object.entries(geometry.attributes),chunks=[];
    let remap=new Map(),vertices=[],indices=[];
    function finish(){
        if(!indices.length)return;
        const chunk=new THREE.BufferGeometry();
        for(const [name,a] of attributes){
            const array=a.isInterleavedBufferAttribute?a.data.array:a.array;
            const stride=a.isInterleavedBufferAttribute?a.data.stride:a.itemSize,offset=a.isInterleavedBufferAttribute?a.offset:0;
            const result=new array.constructor(vertices.length*a.itemSize);
            vertices.forEach((source,i)=>{for(let k=0;k<a.itemSize;k++)result[i*a.itemSize+k]=array[source*stride+offset+k];});
            const copied=new THREE.BufferAttribute(result,a.itemSize,a.normalized);copied.name=a.name;copied.gpuType=a.gpuType;chunk.setAttribute(name,copied);
        }
        chunk.setIndex(new THREE.BufferAttribute(new Uint16Array(indices),1));chunk.computeBoundingBox();chunk.computeBoundingSphere();
        chunks.push(chunk);remap=new Map();vertices=[];indices=[];
    }
    if(input.length%3)throw new Error('Non-triangle static batch');
    for(let i=0;i<input.length;i+=3){
        const triangle=[input[i],input[i+1],input[i+2]];
        if(triangle.some(v=>v>=geometry.attributes.position.count))throw new Error('Index out of range');
        const additional=new Set(triangle.filter(v=>!remap.has(v))).size;
        if(remap.size+additional>limit)finish();
        for(const source of triangle){if(!remap.has(source)){remap.set(source,vertices.length);vertices.push(source);}indices.push(remap.get(source));}
    }
    finish();return chunks;
}

export function usePortableIndices(root) {
    const meshes=[];root.traverse(o=>{if(o.isMesh)meshes.push(o);});
    const report={partitionedBatches:0,inputTriangles:0,outputTriangles:0,outputChunks:0};
    const retired=new Set();
    for(const mesh of meshes){
        const chunks=partitionGeometry(mesh.geometry);if(!chunks)continue;
        if(mesh.isSkinnedMesh || mesh.isInstancedMesh || Array.isArray(mesh.material))throw new Error('Unsupported batched mesh');
        const group=new THREE.Group();group.name=mesh.name;group.userData={...mesh.userData};group.position.copy(mesh.position);group.quaternion.copy(mesh.quaternion);group.scale.copy(mesh.scale);group.matrix.copy(mesh.matrix);group.matrixAutoUpdate=mesh.matrixAutoUpdate;group.visible=mesh.visible;group.layers.mask=mesh.layers.mask;
        chunks.forEach((geometry,index)=>{
            const child=new THREE.Mesh(geometry,mesh.material);child.name=mesh.name+'__part_'+index;
            child.userData={...mesh.userData,sourceBatch:mesh.name,indexPartition:index};child.castShadow=mesh.castShadow;child.receiveShadow=mesh.receiveShadow;child.renderOrder=mesh.renderOrder;child.frustumCulled=mesh.frustumCulled;child.layers.mask=mesh.layers.mask;group.add(child);
            report.outputTriangles+=geometry.index.count/3;
        });
        mesh.parent.add(group);
        for(const child of [...mesh.children])group.add(child);
        mesh.removeFromParent();retired.add(mesh.geometry);report.partitionedBatches++;report.inputTriangles+=mesh.geometry.index.count/3;report.outputChunks+=chunks.length;
    }
    retired.forEach(g=>g.dispose());return report;
}
