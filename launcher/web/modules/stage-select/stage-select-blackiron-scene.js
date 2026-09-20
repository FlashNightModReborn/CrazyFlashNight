// Adopted R8 rendering, adapted to the existing stage-focus/camera contract.
import * as THREE from '../../assets/stage-diorama/base-gate/vendor/three.module.js';
import {GLTFLoader} from '../../assets/stage-diorama/base-gate/vendor/GLTFLoader.js';
import {EffectComposer} from '../../assets/stage-diorama/blackiron-hq/vendor/postprocessing/EffectComposer.js';
import {RenderPass} from '../../assets/stage-diorama/blackiron-hq/vendor/postprocessing/RenderPass.js';
import {UnrealBloomPass} from '../../assets/stage-diorama/blackiron-hq/vendor/postprocessing/UnrealBloomPass.js';
import {OutputPass} from '../../assets/stage-diorama/blackiron-hq/vendor/postprocessing/OutputPass.js';
import {createCameraView} from './stage-select-diorama-camera.js';
import {createBlackironEnvironment} from './stage-select-blackiron-environment.js';

export async function createScene(config,onLost,onChange,onSelect,signal) {
    config=Object.assign({},config,{pins:config.pins});
    const started=performance.now(), abort=new AbortController(), listeners=[];
    const renderer=new THREE.WebGLRenderer({antialias:true,powerPreference:'low-power'});
    renderer.setPixelRatio(1);renderer.setSize(1024,576);renderer.outputColorSpace=THREE.SRGBColorSpace;renderer.toneMapping=THREE.NoToneMapping;
    const canvas=renderer.domElement;canvas.className='stage-select-diorama-canvas';canvas.setAttribute('aria-hidden','true');
    const scene=new THREE.Scene();scene.background=new THREE.Color('#211e21');scene.fog=new THREE.Fog('#292123',225,400);
    const environment=createBlackironEnvironment();scene.add(environment);
    const rimStrength={value:.12};let presentation=config.defaultPresentation||'front';
    const camera=new THREE.OrthographicCamera(-160,160,90,-90,.1,900);
    camera.position.fromArray(config.camera.gltfPosition);camera.lookAt(new THREE.Vector3(...config.camera.gltfTarget));
    const composer=new EffectComposer(renderer),pass=new RenderPass(scene,camera);
    let frames=0,calls=0,triangles=0,view,disposed=false,base,selection,down;
    const masks=new Map(), oldMaterials=new Set();
    const nativeRender=pass.render.bind(pass);
    pass.render=(...args)=>{nativeRender(...args);calls=renderer.info.render.calls;triangles=renderer.info.render.triangles;};
    composer.addPass(pass);composer.addPass(new UnrealBloomPass(new THREE.Vector2(1024,576),.28,.14,.65));composer.addPass(new OutputPass());
    function listen(target,name,fn){target.addEventListener(name,fn);listeners.push(()=>target.removeEventListener(name,fn));}
    listen(canvas,'webglcontextlost',e=>{e.preventDefault();if(!disposed)onLost();});
    if(signal){listen(signal,'abort',()=>abort.abort());if(signal.aborted)abort.abort();}
    const timeout=setTimeout(()=>abort.abort(),15000);
    function release(root) {
        const geometries=new Set(),materials=new Set(),textures=new Set(),images=new Set();
        root.traverse(o=>{if(o.geometry)geometries.add(o.geometry);for(const m of [].concat(o.material||[])){materials.add(m);for(const v of Object.values(m))if(v?.isTexture)textures.add(v);}});
        geometries.forEach(g=>g.dispose());materials.forEach(m=>m.dispose());
        textures.forEach(t=>{if(t.source?.data)images.add(t.source.data);t.dispose();});images.forEach(i=>i.close?.());
    }
    function dispose(){
        if(disposed)return;disposed=true;abort.abort();clearTimeout(timeout);listeners.forEach(off=>off());view?.dispose();
        release(scene);oldMaterials.forEach(m=>m.dispose());
        composer.passes.forEach(p=>p.dispose?.());composer.dispose();renderer.renderLists.dispose();renderer.dispose();
        if(!renderer.getContext().isContextLost())renderer.forceContextLoss();canvas.remove();
    }
    async function load(name){
        const url=new URL('../../assets/stage-diorama/blackiron-hq/'+name,import.meta.url);
        const response=await fetch(url,{signal:abort.signal});if(!response.ok)throw Error('HQ asset HTTP '+response.status);
        const gltf=await new GLTFLoader().parseAsync(await response.arrayBuffer(),new URL('./',url).href);
        if(disposed || abort.signal.aborted){release(gltf.scene);throw new DOMException('Closed','AbortError');}
        return gltf.scene;
    }
    function render(){if(disposed || renderer.getContext().isContextLost())return;renderer.info.reset();composer.render();frames++;}
    try {
        base=await load('headquarters.glb');scene.add(base);
        selection=await load('selection.glb');scene.add(selection);clearTimeout(timeout);
        const materials=new Set();base.traverse(o=>{if(o.isMesh)[].concat(o.material).forEach(m=>materials.add(m));});
        for(const material of materials){
            for(const key of ['map','emissiveMap'])if(material[key])material[key].anisotropy=Math.min(4,renderer.capabilities.getMaxAnisotropy());
            material.onBeforeCompile=shader=>{
                shader.uniforms.hqBackground={value:new THREE.Color('#211e21')};
                shader.uniforms.hqRim=rimStrength;
                shader.vertexShader='varying vec3 hqWorld;\n'+shader.vertexShader.replace('#include <project_vertex>','#include <project_vertex>\nhqWorld=(modelMatrix*vec4(transformed,1.)).xyz;');
                shader.fragmentShader='varying vec3 hqWorld;uniform vec3 hqBackground;uniform float hqRim;\n'+shader.fragmentShader.replace('#include <fog_fragment>','#include <fog_fragment>\nfloat rim=smoothstep(68.,85.,max(abs(hqWorld.x),abs(hqWorld.z+1.)))*hqRim;gl_FragColor.rgb=mix(gl_FragColor.rgb,hqBackground,rim);');
            };material.customProgramCacheKey=()=> 'hq-i1-edge-native';
        }
        selection.traverse(o=>{
            if(!o.isMesh)return;const id=o.userData.entryId;if(!config.pins[id])throw Error('Unknown selection identity');
            oldMaterials.add(o.material);o.material=new THREE.MeshBasicMaterial({color:'#f2bd67',transparent:true,opacity:.11,depthWrite:false,polygonOffset:true,polygonOffsetFactor:-1,polygonOffsetUnits:-1});
            const line=new THREE.LineSegments(new THREE.EdgesGeometry(o.geometry,32),new THREE.LineBasicMaterial({color:'#f3ce8f',transparent:true,opacity:.92,depthWrite:false}));
            line.renderOrder=9;o.renderOrder=8;o.add(line);o.visible=false;masks.set(id,o);
        });
        if(masks.size!==11)throw Error('Incomplete HQ selections');
        Object.values(config.pins).forEach(p=>{if(!base.getObjectByName(p.labelAnchor))throw Error('Missing anchor '+p.labelAnchor);});
        view=createCameraView(config,scene,camera,renderer,render,onChange,{
            resize:(w,h)=>composer.setSize(w,h),
            highlight:id=>{masks.forEach((m,key)=>{m.visible=key===id;});}
        });
        const ray=new THREE.Raycaster();
        function pick(e){
            const r=canvas.getBoundingClientRect();ray.setFromCamera(new THREE.Vector2((e.clientX-r.left)/r.width*2-1,-(e.clientY-r.top)/r.height*2+1),camera);
            const front=ray.intersectObject(base,true)[0];if(!front)return '';
            const hits=ray.intersectObjects([...masks.values()],false).filter(h=>h.distance<=front.distance+.45);
            hits.sort((a,b)=>Math.abs(a.distance-b.distance)<.01 ? (a.object.userData.entryId==='stage_18_9'?1:b.object.userData.entryId==='stage_18_9'?-1:0):a.distance-b.distance);
            return hits[0]?.object.userData.entryId || '';
        }
        listen(canvas,'pointerdown',e=>{down=[e.clientX,e.clientY];});
        listen(canvas,'pointermove',e=>{if(!e.buttons&&!view.stats().editing&&!view.stats().focusId)view.hover(pick(e));});
        listen(canvas,'pointerleave',()=>view.hover(''));
        listen(canvas,'click',e=>{if(view.stats().editing||view.stats().focusId||!down||Math.hypot(e.clientX-down[0],e.clientY-down[1])>=5)return;const id=pick(e);if(id){e.stopPropagation();onSelect?.(id);}});
        view.resize(1024,576);view.overview(null,false);
        const loadMs=Math.round(performance.now()-started);
        return {canvas,view,render,dispose,
            setPresentation(id){
                const variant=config.presentationViews[id];if(!variant)throw Error('Unknown presentation');presentation=id;config.pins=variant.pins;
                const c=variant.camera;view.setOverview({position:c.gltfPosition,target:c.gltfTarget,span:c.horizontalSpan});view.overview(null,false);
            },
            setEnvironment(enabled){environment.visible=!!enabled;rimStrength.value=enabled ? .12 : .62;render();},
            stats:()=>Object.assign({frames,calls,triangles,loadMs,presentation,environment:environment.visible,environmentRevision:environment.userData.revision,environmentDrawCalls:environment.children.filter(o=>o.visible).length,environmentTriangles:environment.userData.triangles,geometries:renderer.info.memory.geometries,textures:renderer.info.memory.textures,width:canvas.width,height:canvas.height},view.stats())};
    }catch(error){dispose();throw error;}
}
