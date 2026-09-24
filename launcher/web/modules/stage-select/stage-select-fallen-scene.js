// P8 visual adapter. Stable gameplay identities remain owned by StageSelectData.
import * as THREE from '../../assets/stage-diorama/base-gate/vendor/three.module.js';
import {GLTFLoader} from '../../assets/stage-diorama/base-gate/vendor/GLTFLoader.js';
import {EffectComposer} from '../../assets/stage-diorama/blackiron-hq/vendor/postprocessing/EffectComposer.js';
import {RenderPass} from '../../assets/stage-diorama/blackiron-hq/vendor/postprocessing/RenderPass.js';
import {UnrealBloomPass} from '../../assets/stage-diorama/blackiron-hq/vendor/postprocessing/UnrealBloomPass.js';
import {OutputPass} from '../../assets/stage-diorama/blackiron-hq/vendor/postprocessing/OutputPass.js';
import {usePortableIndices} from './stage-select-geometry-chunks.js';
import {createCameraView} from './stage-select-diorama-camera.js';

export async function createScene(config,onLost,onChange,onSelect,signal) {
    config=Object.assign({},config,{focusCameras:{}});
    const started=performance.now(),abort=new AbortController(),listeners=[];
    const renderer=new THREE.WebGLRenderer({antialias:true,powerPreference:'low-power'});
    renderer.setPixelRatio(1);renderer.setSize(1024,576);renderer.outputColorSpace=THREE.SRGBColorSpace;renderer.toneMapping=THREE.NoToneMapping;
    const canvas=renderer.domElement;canvas.className='stage-select-diorama-canvas';canvas.setAttribute('aria-hidden','true');
    const scene=new THREE.Scene();scene.background=new THREE.Color(config.lighting.background);
    const camera=new THREE.OrthographicCamera(-160,160,90,-90,.1,2200);
    const target=new THREE.WebGLRenderTarget(1024,576,{type:THREE.HalfFloatType});target.samples=Math.min(4,renderer.capabilities.maxSamples);
    const composer=new EffectComposer(renderer,target),pass=new RenderPass(scene,camera);
    const bloom=new UnrealBloomPass(new THREE.Vector2(1024,576),config.lighting.bloomStrength,config.lighting.bloomRadius,config.lighting.bloomThreshold);
    composer.addPass(pass);composer.addPass(bloom);composer.addPass(new OutputPass());
    let base,selection,view,disposed=false,frames=0,calls=0,triangles=0,current='',cutaway=false;
    const loadedHashes={},indexCompatibility=[];
    const materials=new Set(),masks=new Map(),entries=new Map(config.entries.map(e=>[e.id,e]));
    const nativeRender=pass.render.bind(pass);pass.render=(...args)=>{nativeRender(...args);calls=renderer.info.render.calls;triangles=renderer.info.render.triangles;};
    function listen(el,name,fn){el.addEventListener(name,fn);listeners.push(()=>el.removeEventListener(name,fn));}
    listen(canvas,'webglcontextlost',e=>{e.preventDefault();if(!disposed)onLost();});
    if(signal){listen(signal,'abort',()=>abort.abort());if(signal.aborted)abort.abort();}
    const timer=setTimeout(()=>abort.abort(),30000);
    function release(root){
        const gs=new Set(),ms=new Set(),ts=new Set(),images=new Set();
        root.traverse(o=>{if(o.geometry)gs.add(o.geometry);for(const m of [].concat(o.material||[])){ms.add(m);for(const t of Object.values(m))if(t?.isTexture)ts.add(t);}});
        gs.forEach(g=>g.dispose());ms.forEach(m=>m.dispose());ts.forEach(t=>{if(t.source?.data)images.add(t.source.data);t.dispose();});images.forEach(i=>i.close?.());
    }
    function dispose(){if(disposed)return;disposed=true;abort.abort();clearTimeout(timer);listeners.forEach(off=>off());view?.dispose();release(scene);materials.forEach(m=>m.dispose());composer.passes.forEach(p=>p.dispose?.());composer.dispose();renderer.renderLists.dispose();renderer.dispose();if(!renderer.getContext().isContextLost())renderer.forceContextLoss();canvas.remove();}
    async function load(name){
        const url=new URL('../../assets/stage-diorama/fallen-city/'+name,import.meta.url),expected=config.assetHashes?.[name];
        if(expected)url.searchParams.set('sha256',expected);
        const r=await fetch(url,{signal:abort.signal});
        if(!r.ok)throw Error('Fallen city HTTP '+r.status);
        const bytes=await r.arrayBuffer();
        if(expected&&globalThis.crypto?.subtle){
            const digest=Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',bytes)),v=>v.toString(16).padStart(2,'0')).join('');
            if(digest!==expected)throw Error('Fallen city asset fingerprint mismatch: '+name);loadedHashes[name]=digest;
        }
        const gltf=await new GLTFLoader().parseAsync(bytes,new URL('./',url).href);
        if(disposed||abort.signal.aborted){release(gltf.scene);throw new DOMException('Closed','AbortError');}return gltf.scene;
    }
    function render(){if(disposed||renderer.getContext().isContextLost())return;renderer.info.reset();composer.render();frames++;}
    function parts(entry){
        if(!entry)return [];
        const ids=new Set(Object.values(entry.relations||{}).flat());
        return [...ids].flatMap(id=>(masks.get(id)||[]).filter(m=>!entry.selectionPartitions?.[id]||entry.selectionPartitions[id].includes(m.userData.selectionPart||'')));
    }
    function highlight(id){
        current=id||'';const selected=new Set(parts(entries.get(id)));cutaway=entries.get(id)?.name==='外交-堕落城酒吧';
        base?.traverse(o=>{if(o.isMesh&&o.userData.cutaway==='bar')o.visible=!cutaway;});
        masks.forEach(list=>list.forEach(m=>{
            m.visible=selected.has(m)&&!(cutaway&&m.userData.cutaway==='bar');
            const entry=entries.get(id),role=Object.keys(entry?.relations||{}).find(role=>entry.relations[role].includes(m.userData.buildingId))||'main';
            const styles={main:[0xf0c476,.23],transit:[0x83c7cf,.10],service:[0xa8bd85,.10],anchor:[0xd79bae,.13],adjacent:[0x9a9bb6,.04]},style=styles[role]||styles.main;
            m.material.color.setHex(style[0]);m.material.opacity=style[1];
        }));
    }
    try {
        base=await load('city.glb');scene.add(base);indexCompatibility.push({asset:'city.glb',...usePortableIndices(base)});
        selection=await load('selection.glb');scene.add(selection);indexCompatibility.push({asset:'selection.glb',...usePortableIndices(selection)});clearTimeout(timer);
        base.traverse(o=>{if(!o.isMesh)return;if(o.userData.effect==='stageBeam'){o.renderOrder=2;[].concat(o.material).forEach(m=>{m.depthWrite=false;m.forceSinglePass=true;m.blending=THREE.AdditiveBlending;});}});
        selection.traverse(o=>{
            if(!o.isMesh)return;const id=o.userData.buildingId;if(!id)throw Error('Selection without unit');
            [].concat(o.material).forEach(m=>materials.add(m));o.material=new THREE.MeshBasicMaterial({color:'#f0c476',transparent:true,opacity:.15,depthWrite:false,polygonOffset:true,polygonOffsetFactor:-2,polygonOffsetUnits:-2,side:THREE.DoubleSide});
            o.visible=false;o.renderOrder=5;if(!masks.has(id))masks.set(id,[]);masks.get(id).push(o);
        });
        if(masks.size!==70)throw Error('Incomplete fallen city units');scene.updateMatrixWorld(true);
        for(const e of config.entries){
            const box=new THREE.Box3(),all=parts(e),primary=all.filter(m=>(e.relations.main||[]).includes(m.userData.buildingId));(primary.length?primary:all).forEach(m=>box.union(new THREE.Box3().setFromObject(m)));if(box.isEmpty())throw Error('Missing selected geometry '+e.id);
            const proxy=new THREE.Mesh(new THREE.BoxGeometry(...box.getSize(new THREE.Vector3()).toArray()),new THREE.MeshBasicMaterial());proxy.name='FOCUS_'+e.id;proxy.position.copy(box.getCenter(new THREE.Vector3()));proxy.visible=false;scene.add(proxy);
            const aim=box.getCenter(new THREE.Vector3()),position=aim.clone().add(new THREE.Vector3(8,100,115)),probe=camera.clone(),projected=new THREE.Box3();
            probe.position.copy(position);probe.lookAt(aim);probe.updateMatrixWorld(true);
            for(const x of [box.min.x,box.max.x])for(const y of [box.min.y,box.max.y])for(const z of [box.min.z,box.max.z])projected.expandByPoint(new THREE.Vector3(x,y,z).applyMatrix4(probe.matrixWorldInverse));
            const size=projected.getSize(new THREE.Vector3());config.focusCameras[e.id]={position:position.toArray(),target:aim.toArray(),span:Math.max(26,Math.max(size.x,size.y*1.2)*1.45)};
        }
        for(const [id,p] of Object.entries(config.pins))if(!scene.getObjectByName(p.labelAnchor)){
            // Use the validated semantic file, not raw layout coordinates.
            const e=config.entries.find(e=>e.id===id)||config.navigation.find(e=>e.id===id);if(!e?.worldAnchor)throw Error('Missing anchor '+id);
            const a=new THREE.Object3D();a.name=p.labelAnchor;a.position.fromArray(e.worldAnchor);scene.add(a);
        }
        view=createCameraView(config,scene,camera,renderer,render,onChange,{resize:(w,h)=>composer.setSize(w,h),highlight});
        view.resize(1024,576);view.overview(null,false);
        const loadMs=Math.round(performance.now()-started);
        return {canvas,view,render,dispose,stats:()=>Object.assign({frames,calls,triangles,loadMs,cutaway,indexCompatibility,loadedHashes,selectedParts:parts(entries.get(current)).map(m=>({unit:m.userData.buildingId,part:m.userData.selectionPart||''})),geometries:renderer.info.memory.geometries,textures:renderer.info.memory.textures,width:canvas.width,height:canvas.height},view.stats())};
    }catch(e){dispose();throw e;}
}
