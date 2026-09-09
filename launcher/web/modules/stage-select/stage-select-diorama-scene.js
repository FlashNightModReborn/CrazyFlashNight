// 废城固定镜头；Three r180 与交付使用同版本，独立本地加载，不改军阀依赖。
import * as THREE from '../../assets/stage-diorama/base-gate/vendor/three.module.js';
import { GLTFLoader } from '../../assets/stage-diorama/base-gate/vendor/GLTFLoader.js';
import { createCameraView } from './stage-select-diorama-camera.js';

export async function createScene(config, onLost, onChange) {
    const started = performance.now();
    const renderer = new THREE.WebGLRenderer({ antialias: true, powerPreference: 'low-power' });
    // 固定逻辑分辨率，避免高 DPI 平板按物理像素倍增 GPU 工作。
    renderer.setPixelRatio(1);
    renderer.setSize(1024, 576);
    renderer.outputColorSpace = THREE.SRGBColorSpace;
    renderer.toneMapping = THREE.NoToneMapping;
    const canvas = renderer.domElement;
    canvas.className = 'stage-select-diorama-canvas';
    canvas.setAttribute('aria-hidden', 'true');
    const lost = event => { event.preventDefault(); onLost(); };
    canvas.addEventListener('webglcontextlost', lost);
    const scene = new THREE.Scene();
    const env = config.environment;
    scene.background = new THREE.Color(env.background);
    scene.fog = new THREE.Fog(env.fog.color, env.fog.near, env.fog.far);
    const span = config.camera.horizontalSpan;
    const camera = new THREE.OrthographicCamera(-span/2, span/2, span*9/32, -span*9/32, .1, 500);
    camera.position.fromArray(config.camera.gltfPosition);
    camera.lookAt(new THREE.Vector3().fromArray(config.camera.gltfTarget));
    let root, view;
    function dispose() {
        if (view) view.dispose();
        canvas.removeEventListener('webglcontextlost', lost);
        const geometries = new Set(), materials = new Set(), textures = new Set();
        if (root) root.traverse(object => {
            if (object.geometry) geometries.add(object.geometry);
            for (const material of [].concat(object.material || [])) {
                materials.add(material);
                for (const value of Object.values(material)) if (value && value.isTexture) textures.add(value);
            }
        });
        geometries.forEach(value => value.dispose());
        materials.forEach(value => value.dispose());
        const images = new Set();
        textures.forEach(value => { if (value.source && value.source.data) images.add(value.source.data); value.dispose(); });
        images.forEach(value => { if (typeof value.close === 'function') value.close(); });
        renderer.dispose();
        renderer.forceContextLoss();
        canvas.remove();
    }
    try {
        const asset = new URL('../../assets/stage-diorama/base-gate/city.glb', import.meta.url);
        const response = await fetch(asset.href, { signal: AbortSignal.timeout(10000) });
        if (!response.ok) throw new Error('City asset HTTP ' + response.status);
        const gltf = await new GLTFLoader().parseAsync(await response.arrayBuffer(), new URL('./', asset).href);
        root = gltf.scene;
        const materials = new Set();
        root.traverse(object => { if (object.isMesh) [].concat(object.material).forEach(material => materials.add(material)); });
        materials.forEach(material => {
            if (material.map) material.map.anisotropy = Math.min(4, renderer.capabilities.getMaxAnisotropy());
            // 保留交付页的远边渐隐及其颜色空间，避免把 C 再次压暗。
            material.onBeforeCompile = shader => {
                Object.assign(shader.uniforms, {
                    cityFog: { value: new THREE.Color(env.fog.color).convertLinearToSRGB() },
                    cityInner: { value: new THREE.Vector2(...env.edgeFade.innerHalfExtent) },
                    cityDistance: { value: env.edgeFade.distance },
                    cityYaw: { value: new THREE.Vector2(Math.cos(config.gridYawRadians), Math.sin(config.gridYawRadians)) }
                });
                shader.vertexShader = 'varying vec3 vCityWorld;\n' + shader.vertexShader.replace('#include <project_vertex>',
                    '#include <project_vertex>\nvCityWorld=(modelMatrix*vec4(transformed,1.0)).xyz;');
                shader.fragmentShader = 'varying vec3 vCityWorld;\nuniform vec3 cityFog;\nuniform vec2 cityInner;\nuniform float cityDistance;\nuniform vec2 cityYaw;\n' +
                    shader.fragmentShader.replace('#include <fog_fragment>', `#include <fog_fragment>
                    vec2 gridXY=vec2(vCityWorld.x*cityYaw.x-vCityWorld.z*cityYaw.y,-vCityWorld.x*cityYaw.y-vCityWorld.z*cityYaw.x);
                    float edge=smoothstep(0.,cityDistance,length(max(abs(gridXY)-cityInner,vec2(0.))));
                    gl_FragColor.rgb=mix(gl_FragColor.rgb,cityFog,edge);`);
            };
            material.customProgramCacheKey = () => 'cf7-base-gate-c-fixed-v1';
        });
        scene.add(root);
        scene.updateMatrixWorld(true);
        camera.updateMatrixWorld(true);
        for (const pin of Object.values(config.pins)) {
            const anchor = root.getObjectByName(pin.labelAnchor);
            if (!anchor) throw new Error('Missing anchor: ' + pin.labelAnchor);
            const point = anchor.getWorldPosition(new THREE.Vector3()).project(camera);
            if (Math.abs((point.x*.5+.5)*1024-pin.x) > 1 || Math.abs((-.5*point.y+.5)*576-pin.y) > 1)
                throw new Error('Fixed camera anchor drift: ' + pin.labelAnchor);
        }
        let frames = 0;
        function render() {
            if (renderer.getContext().isContextLost()) throw new Error('City graphics context lost');
            renderer.render(scene, camera);
            frames++;
        }
        render();
        view=createCameraView(config,root,camera,renderer,render,onChange);
        const loadMs = Math.round(performance.now()-started);
        return { canvas, render, dispose, view, stats: () => Object.assign({ loadMs, frames, calls: renderer.info.render.calls,
            triangles: renderer.info.render.triangles, geometries: renderer.info.memory.geometries,
            textures: renderer.info.memory.textures, width: canvas.width, height: canvas.height },view.stats()) };
    } catch (error) {
        dispose();
        throw error;
    }
}
