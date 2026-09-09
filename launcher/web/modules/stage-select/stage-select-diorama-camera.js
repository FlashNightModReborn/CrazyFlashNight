import * as THREE from '../../assets/stage-diorama/base-gate/vendor/three.module.js';

// 相机与高亮只在输入/过渡时出帧；总览、特写、开发取景共用同一个相机和 Canvas。
export function createCameraView(config, root, camera, renderer, render, onChange) {
    let width=1024, height=576, span=config.camera.horizontalSpan;
    let target=new THREE.Vector3(...config.camera.gltfTarget), motion=0, controls=null, disposed=false;
    let highlighted='', materials=[], focusId='', editGeneration=0, controlsPromise=null;
    const heldKeys=new Set(), walkKeys={KeyW:[0,1],ArrowUp:[0,1],KeyS:[0,-1],ArrowDown:[0,-1],KeyA:[-1,0],ArrowLeft:[-1,0],KeyD:[1,0],ArrowRight:[1,0]};
    let walkFrame=0, walkTime=0, fastWalk=false;
    const home={position:config.camera.gltfPosition, target:config.camera.gltfTarget, span};
    function stopWalk() { heldKeys.clear(); fastWalk=false; if(walkFrame)cancelAnimationFrame(walkFrame);walkFrame=0; }
    function stop() { if (motion) cancelAnimationFrame(motion); motion=0; stopWalk(); }
    function isTextInput(el) { return el && (el.isContentEditable || /^(INPUT|TEXTAREA|SELECT)$/.test(el.tagName)); }
    function walk(now) {
        walkFrame=0;
        if(disposed || !controls || !controls.enabled || !heldKeys.size || document.hidden || renderer.getContext().isContextLost()) {stopWalk();return;}
        const dt=Math.min(.05,Math.max(0,(now-walkTime)/1000));walkTime=now;
        let x=0,y=0;
        heldKeys.forEach(key=>{x+=walkKeys[key][0];y+=walkKeys[key][1];});
        if(x || y) {
            const forward=controls.target.clone().sub(camera.position);forward.y=0;forward.normalize();
            const right=forward.clone().cross(new THREE.Vector3(0,1,0));
            const delta=right.multiplyScalar(x).addScaledVector(forward,y).normalize().multiplyScalar(span/camera.zoom*.4*dt*(fastWalk?2.5:1));
            // 同时平移相机和轨道中心，保留鼠标正在改变的观察方向。
            camera.position.add(delta);controls.target.add(delta);controls.update();
        }
        walkFrame=requestAnimationFrame(walk);
    }
    function keyDown(e) {
        if(!controls || !controls.enabled || e.ctrlKey || e.metaKey || e.altKey || isTextInput(e.target))return;
        fastWalk=e.shiftKey;
        if(!walkKeys[e.code])return;
        e.preventDefault();e.stopPropagation();heldKeys.add(e.code);
        if(!walkFrame){walkTime=performance.now();walkFrame=requestAnimationFrame(walk);}
    }
    function keyUp(e) {
        fastWalk=e.shiftKey;
        if(!heldKeys.delete(e.code))return;
        e.preventDefault();e.stopPropagation();
        if(!heldKeys.size)stopWalk();
    }
    function focusInput(e) { if(isTextInput(e.target))stopWalk(); }
    document.addEventListener('keydown',keyDown,true);
    document.addEventListener('keyup',keyUp,true);
    document.addEventListener('focusin',focusInput);
    document.addEventListener('visibilitychange',stopWalk);
    window.addEventListener('blur',stopWalk);
    function project() {
        camera.left=-span/2; camera.right=span/2; camera.top=span*height/width/2; camera.bottom=-camera.top;
        camera.lookAt(target); camera.updateProjectionMatrix(); camera.updateMatrixWorld(true);
    }
    function draw() { project(); render(); if (onChange) onChange(); }
    function resize(w,h) {
        width=Math.max(1,Math.round(w)); height=Math.max(1,Math.round(h));
        renderer.setSize(width,height,false); project();
    }
    function snapshot() { return {position:camera.position.toArray(),target:target.toArray(),span:span/camera.zoom}; }
    function valid(value) {
        return value && ['position','target'].every(key=>Array.isArray(value[key]) && value[key].length===3 && value[key].every(n=>Number.isFinite(n) && Math.abs(n)<10000))
            && Number.isFinite(value.span) && value.span>=5 && value.span<=240
            && new THREE.Vector3(...value.position).distanceTo(new THREE.Vector3(...value.target))>1;
    }
    function move(value, animate) {
        if (!valid(value)) throw new Error('镜头预设无效');
        stop();
        if (controls) controls.enabled=false;
        const start=snapshot(), started=performance.now(); camera.zoom=1;
        const duration=animate && !matchMedia('(prefers-reduced-motion: reduce)').matches ? 400 : 0;
        function tick(now) {
            motion=0; if (disposed) return;
            const t=duration ? Math.min(1,(now-started)/duration) : 1, blend=t*t*(3-2*t);
            camera.position.fromArray(start.position).lerp(new THREE.Vector3(...value.position),blend);
            target.fromArray(start.target).lerp(new THREE.Vector3(...value.target),blend);
            span=start.span+(value.span-start.span)*blend;
            if (renderer.getContext().isContextLost()) return;
            draw();
            if (t<1) motion=requestAnimationFrame(tick);
        }
        tick(started);
    }
    function highlight(id) {
        if (id===highlighted) return;
        materials.forEach(row=>{row.mesh.material=row.original; row.clones.forEach(m=>m.dispose());}); materials=[];
        highlighted=id || '';
        const pin=config.pins[id], building=pin && root.getObjectByName(pin.building);
        if (!building) return;
        building.traverse(mesh=>{
            if (!mesh.isMesh) return;
            const original=mesh.material;
            const clones=[].concat(original).map(base=>{
                const clone=base.clone();
                clone.onBeforeCompile=shader=>{
                    base.onBeforeCompile(shader);
                    shader.fragmentShader=shader.fragmentShader.replace('#include <dithering_fragment>',
                        'gl_FragColor.rgb=mix(gl_FragColor.rgb,vec3(1.0,0.72,0.20),0.28);\n#include <dithering_fragment>');
                };
                clone.customProgramCacheKey=()=>base.customProgramCacheKey()+'-selected';
                return clone;
            });
            materials.push({mesh,original,clones}); mesh.material=Array.isArray(original) ? clones : clones[0];
        });
    }
    function defaultFocus(id) {
        const pin=config.pins[id], building=pin && root.getObjectByName(pin.building);
        if (!building) return home;
        const box=new THREE.Box3().setFromObject(building);
        const aim=box.getCenter(new THREE.Vector3());
        const direction=new THREE.Vector3(...home.position).sub(new THREE.Vector3(...home.target)).normalize();
        const position=aim.clone().addScaledVector(direction,90), probe=camera.clone();
        probe.position.copy(position);probe.lookAt(aim);probe.updateMatrixWorld(true);
        const projected=new THREE.Box3();
        for (const x of [box.min.x,box.max.x]) for (const y of [box.min.y,box.max.y]) for (const z of [box.min.z,box.max.z])
            projected.expandByPoint(new THREE.Vector3(x,y,z).applyMatrix4(probe.matrixWorldInverse));
        const size=projected.getSize(new THREE.Vector3());
        return {position:position.toArray(),target:aim.toArray(),
            span:Math.max(12,Math.min(120,Math.max(size.x,size.y*width/height)*1.3))};
    }
    function focus(id,preset,animate=true) { focusId=id; highlight(id); move(preset || defaultFocus(id),animate); }
    function overview(preset,animate=true) { focusId=''; highlight(''); move(preset || home,animate); }
    async function edit(enabled) {
        const token=++editGeneration;
        if (!enabled) { stopWalk(); if (controls) controls.enabled=false; return; }
        stop();
        if (!controls) {
            if (!controlsPromise) controlsPromise=import('../../assets/stage-diorama/base-gate/vendor/OrbitControls.js');
            const {OrbitControls}=await controlsPromise;
            if (disposed || token!==editGeneration) return;
            controls=new OrbitControls(camera,renderer.domElement); controls.enableDamping=false;
            controls.minPolarAngle=.15; controls.maxPolarAngle=Math.PI/2-.08;
            controls.addEventListener('change',()=>{
                target.copy(controls.target); camera.updateMatrixWorld(true); render(); if(onChange)onChange();
            });
        }
        controls.minZoom=span/240; controls.maxZoom=span/5;
        controls.target.copy(target); controls.enabled=true; controls.update();
    }
    function pins() {
        const result={};
        Object.entries(config.pins).forEach(([id,pin])=>{
            const anchor=root.getObjectByName(pin.labelAnchor), p=anchor.getWorldPosition(new THREE.Vector3()).project(camera);
            result[id]=Object.assign({},pin,{x:(p.x*.5+.5)*width,y:(-.5*p.y+.5)*height,visible:p.z>=-1 && p.z<=1});
        });
        return result;
    }
    return {resize,focus,overview,edit,snapshot,valid,pins,stop,
        hover(id) { if (!focusId && !motion && !(controls && controls.enabled)) {highlight(id);draw();} },
        dispose() {
            disposed=true;stop();if(controls)controls.dispose();highlight('');
            document.removeEventListener('keydown',keyDown,true);document.removeEventListener('keyup',keyUp,true);
            document.removeEventListener('focusin',focusInput);document.removeEventListener('visibilitychange',stopWalk);window.removeEventListener('blur',stopWalk);
        },
        stats() {return {moving:!!motion,editing:!!(controls&&controls.enabled),focusId,highlighted};}
    };
}
