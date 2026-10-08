import * as THREE from '../../assets/stage-diorama/base-gate/vendor/three.module.js';
import { GLTFLoader } from '../../assets/stage-diorama/base-gate/vendor/GLTFLoader.js';
import { createCameraView } from './stage-select-diorama-camera.js';
import { usePortableIndices } from './stage-select-geometry-chunks.js';
import { normalizeDesertConfig, validateEmbeddedGlb, layoutDesertPins, WORLD_STAGE_IDS } from './stage-select-desert-config.js';
import { createDesertSurround } from './stage-select-desert-surround.js';
import { loadDesertSceneBytes } from './stage-select-desert-transport.js';

const assetRoot = new URL('../../assets/stage-diorama/desert-region/', import.meta.url);

function release(root) {
    const geometries = new Set(), materials = new Set(), textures = new Set(), images = new Set();
    root.traverse(object => {
        if (object.geometry) geometries.add(object.geometry);
        for (const material of [].concat(object.material || [])) {
            materials.add(material);
            for (const value of Object.values(material)) if (value?.isTexture) textures.add(value);
        }
    });
    geometries.forEach(value => value.dispose());
    materials.forEach(value => value.dispose());
    textures.forEach(value => { if (value.source?.data) images.add(value.source.data); value.dispose(); });
    images.forEach(value => value.close?.());
}

export function frameDesertOwner(camera, bounds, meshes = []) {
    const box = new THREE.Box3(new THREE.Vector3(...bounds.min), new THREE.Vector3(...bounds.max));
    const target = box.getCenter(new THREE.Vector3());
    const direction = new THREE.Vector3(...camera.gltfPosition).sub(new THREE.Vector3(...camera.gltfTarget)).normalize();
    const position = target.clone().addScaledVector(direction, 120);
    const probe = new THREE.PerspectiveCamera();
    probe.position.copy(position); probe.lookAt(target); probe.updateMatrixWorld(true);
    const projected = new THREE.Box3(), transform = new THREE.Matrix4(), point = new THREE.Vector3();
    let vertices = 0;
    for (const mesh of meshes) {
        const positions = mesh.geometry.attributes.position;
        if (!positions) continue;
        transform.multiplyMatrices(probe.matrixWorldInverse, mesh.matrixWorld);
        for (let i = 0; i < positions.count; i++) projected.expandByPoint(point.fromBufferAttribute(positions, i).applyMatrix4(transform));
        vertices += positions.count;
    }
    if (!vertices) {
        for (const x of [box.min.x, box.max.x]) for (const y of [box.min.y, box.max.y]) for (const z of [box.min.z, box.max.z]) {
            projected.expandByPoint(point.set(x, y, z).applyMatrix4(probe.matrixWorldInverse));
        }
    }
    const size = projected.getSize(new THREE.Vector3());
    const center = projected.getCenter(new THREE.Vector3());
    // Keep the established viewing direction, and center the actual silhouette.
    // A tall antenna only enlarges the range where its real vertices project;
    // it no longer creates imaginary high corners across the whole courtyard.
    const shift = new THREE.Vector3().setFromMatrixColumn(probe.matrixWorld, 0).multiplyScalar(center.x)
        .addScaledVector(new THREE.Vector3().setFromMatrixColumn(probe.matrixWorld, 1), center.y);
    target.add(shift); position.add(shift);
    // The established focus shell has a narrower viewport than the overview.
    const span = Math.max(camera.minSpan, Math.min(camera.maxSpan, Math.max(size.x, size.y * 1.17) * 1.15));
    return { camera: { position: position.toArray(), target: target.toArray(), span },
        framing: { source: vertices ? 'owner-vertices' : 'bounds-fallback', meshes: meshes.length, vertices,
            projectedWidth: size.x, projectedHeight: size.y, targetShift: shift.toArray(), span, viewportAspect: 1.17 } };
}

export function reserveObservationFrame(frame, camera, width, height, bottomInset) {
    const inset = Math.min(Math.max(0, bottomInset), height * .45), area = frame.framing;
    const span = Math.max(camera.minSpan, Math.min(camera.maxSpan,
        Math.max(area.projectedWidth, area.projectedHeight * width / (height - inset)) * 1.15));
    const target = new THREE.Vector3(...frame.camera.target), position = new THREE.Vector3(...frame.camera.position);
    const direction = position.clone().sub(target).normalize();
    const right = new THREE.Vector3(0, 1, 0).cross(direction).normalize(), up = direction.clone().cross(right).normalize();
    const shift = up.multiplyScalar(-inset * span / (2 * width));
    target.add(shift); position.add(shift);
    const pixelWidth = area.projectedWidth * width / span, pixelHeight = area.projectedHeight * width / span;
    return { camera: { position: position.toArray(), target: target.toArray(), span },
        framing: { ...area, span, viewportAspect: width / height,
            targetShift: new THREE.Vector3(...area.targetShift).add(shift).toArray(),
            viewport: { width, height, bottomInset: inset },
            projectedPixels: { left: (width - pixelWidth) / 2, right: (width + pixelWidth) / 2,
                top: (height - inset - pixelHeight) / 2, bottom: (height - inset + pixelHeight) / 2 } } };
}

function createFocusControls(config, subareaCameras, view, lifetime, prepare) {
    const bar = document.createElement('div'); bar.className = 'stage-desert-area-controls';
    bar.setAttribute('role', 'group'); bar.setAttribute('aria-label', '观察范围');
    let stageId = '', selected = 'whole', hostNode = null, layout = null;
    function update() {
        bar.querySelectorAll('button').forEach(button => button.setAttribute('aria-pressed', String(button.dataset.subarea === selected)));
    }
    function resize(apply) {
        if (!stageId || !hostNode || !bar.isConnected || view.stats().editing || !bar.offsetHeight) return;
        const width = hostNode.clientWidth, height = hostNode.clientHeight;
        const bottomInset = bar.offsetHeight + (parseFloat(getComputedStyle(bar).bottom) || 0) + 6;
        if (!width || !height || layout && layout.width === width && layout.height === height && layout.bottomInset === bottomInset) return;
        layout = { width, height, bottomInset }; prepare(stageId, width, height, bottomInset);
        if (apply && view.stats().focusId === stageId) {
            view.resize(width, height);
            view.focus(stageId, selected === 'whole' ? config.focusCameras[stageId] : subareaCameras[stageId][selected], false);
        }
    }
    const observer = new ResizeObserver(() => resize(true));
    function unmount() { observer.disconnect(); bar.remove(); stageId = ''; selected = 'whole'; hostNode = null; layout = null; }
    lifetime.defer(unmount);
    lifetime.listen(bar, 'click', event => {
        event.stopPropagation();
        const button = event.target.closest('button[data-subarea]');
        if (!button || !bar.contains(button) || !stageId || view.stats().editing || view.stats().focusId !== stageId) return;
        const id = button.dataset.subarea;
        const camera = id === 'whole' ? config.focusCameras[stageId] : subareaCameras[stageId]?.[id];
        if (!camera) return;
        selected = id; update(); view.focus(stageId, camera);
    });
    return {
        mount(host, id) {
            if (stageId === id && bar.parentElement === host) { resize(true); return; }
            unmount();
            const pin = config.pins[id], areas = pin?.subareas;
            if (!areas?.length) return;
            stageId = id; hostNode = host;
            const caption = document.createElement('span'); caption.textContent = '观察范围';
            bar.replaceChildren(caption);
            [{ id: 'whole', label: '整关' }, ...areas].forEach((area, index) => {
                const button = document.createElement('button'); button.type = 'button'; button.className = 'stage-focus-action';
                button.dataset.subarea = area.id; button.dataset.audioCue = 'select';
                button.textContent = index ? '第' + index + '段' : '整关';
                button.setAttribute('aria-label', '观察' + pin.shortLabel + '的' + button.textContent);
                bar.appendChild(button);
            });
            update(); host.appendChild(bar);
            // The geometry fit reserves the bar plus its bottom offset and a
            // small visible gap. The source projection ranges are reused.
            resize(false); observer.observe(host); observer.observe(bar);
        },
        unmount,
        reset() { selected = 'whole'; update(); },
        stats() { return { stageId, selectedSubareaId: stageId ? selected : '', count: config.pins[stageId]?.subareas?.length || 0, mounted: bar.isConnected, layout: layout ? { ...layout } : null }; }
    };
}

export async function createScene(shellConfig, onLost, onChange, onSelect, signal) {
    const started = performance.now();
    const lifetime = new globalThis.WorkbenchLifecycle.DisposableStack();
    const abort = new AbortController();
    const scene = new THREE.Scene();
    let renderer, view, root, canvas, surround, disposed = false, frames = 0, down = null;
    let layoutFailures = [], current = '', indexCompatibility = null, sceneHash = '', sceneTransport = null;
    const focusBoxes = new Map();
    const focusFraming = {};
    lifetime.defer(() => abort.abort());
    lifetime.defer(() => {
        if (!renderer) return;
        renderer.renderLists.dispose(); renderer.dispose();
        if (!renderer.getContext().isContextLost()) renderer.forceContextLoss();
        canvas.remove();
    });
    lifetime.defer(() => release(scene));
    lifetime.defer(() => view?.dispose());
    if (signal) {
        lifetime.listen(signal, 'abort', () => abort.abort());
        if (signal.aborted) abort.abort();
    }
    const timeout = lifetime.timeout(() => abort.abort(), 45000);
    function live() {
        if (disposed || abort.signal.aborted) throw new DOMException('Closed', 'AbortError');
    }
    function dispose() {
        if (disposed) return;
        disposed = true;
        lifetime.dispose();
    }
    function render() {
        if (disposed || !renderer || renderer.getContext().isContextLost()) return;
        renderer.info.reset(); renderer.render(scene, camera); frames++;
    }
    let camera;
    try {
        live();
        const configResponse = await fetch(new URL('config.json', assetRoot), { signal: abort.signal, cache: 'no-store' });
        if (!configResponse.ok) throw new Error('Desert config HTTP ' + configResponse.status);
        const config = normalizeDesertConfig(await configResponse.json());
        live();
        const loaded = await loadDesertSceneBytes(config, assetRoot, abort.signal);
        const bytes = loaded.bytes; sceneHash = loaded.sceneHash; sceneTransport = loaded.transport;
        live(); validateEmbeddedGlb(bytes);
        live();
        const gltf = await new GLTFLoader().parseAsync(bytes, assetRoot.href);
        root = gltf.scene;
        // Register parsed resources before checking cancellation so late loads are released.
        scene.add(root); live();
        indexCompatibility = usePortableIndices(root);
        surround = createDesertSurround(root); scene.add(surround.object);
        renderer = new THREE.WebGLRenderer({ antialias: true, powerPreference: 'low-power' });
        renderer.setPixelRatio(1); renderer.setSize(1024, 576, false);
        renderer.outputColorSpace = THREE.SRGBColorSpace; renderer.toneMapping = THREE.NoToneMapping;
        canvas = renderer.domElement; canvas.className = 'stage-select-diorama-canvas'; canvas.setAttribute('aria-hidden', 'true');
        lifetime.listen(canvas, 'webglcontextlost', event => { event.preventDefault(); if (!disposed) onLost(); });
        scene.background = new THREE.Color(config.lighting.background || '#665845');
        scene.add(new THREE.HemisphereLight(config.lighting.skyColor || '#e2e7df', config.lighting.groundColor || '#504331',
            Number.isFinite(config.lighting.ambientStrength) ? config.lighting.ambientStrength : 0.9));
        const sun = new THREE.DirectionalLight(config.lighting.sunColor || '#fff0d6',
            Number.isFinite(config.lighting.sunStrength) ? config.lighting.sunStrength : 1.8);
        sun.position.set(-80, 120, 60); scene.add(sun);
        camera = new THREE.OrthographicCamera(-100, 100, 56.25, -56.25, 0.01, 5000);
        camera.position.fromArray(config.camera.gltfPosition); camera.lookAt(new THREE.Vector3(...config.camera.gltfTarget));
        const ring = new THREE.Mesh(new THREE.RingGeometry(0.97, 1, 48), new THREE.MeshBasicMaterial({
            color: '#e1be72', transparent: true, opacity: 0.4, side: THREE.DoubleSide,
            depthWrite: false, polygonOffset: true, polygonOffsetFactor: -2, polygonOffsetUnits: -2
        }));
        ring.rotation.x = -Math.PI / 2; ring.visible = false; scene.add(ring);
        config.focusCameras = {};
        const subareaCameras = {};
        const rawFocusFrames = {};
        const ownerMeshes = new Map();
        root.updateMatrixWorld(true);
        root.traverseVisible(mesh => {
            const owner = mesh.userData.placeId;
            if (!mesh.isMesh || !owner) return;
            if (!ownerMeshes.has(owner)) ownerMeshes.set(owner, []);
            ownerMeshes.get(owner).push(mesh);
        });
        for (const id of WORLD_STAGE_IDS) {
            const pin = config.pins[id];
            const anchor = new THREE.Object3D(); anchor.name = pin.labelAnchor; anchor.position.fromArray(pin.worldAnchor); scene.add(anchor);
            const box = new THREE.Box3(new THREE.Vector3(...pin.focusBounds.min), new THREE.Vector3(...pin.focusBounds.max));
            focusBoxes.set(id, box);
            const framed = frameDesertOwner(config.camera, pin.focusBounds, ownerMeshes.get(pin.placeId) || []);
            config.focusCameras[id] = framed.camera;
            focusFraming[id] = { placeId: pin.placeId || null, ...framed.framing };
            if (pin.subareas) {
                subareaCameras[id] = {};
                rawFocusFrames[id] = { whole: framed, subareas: {} };
                focusFraming[id].subareas = pin.subareas.map(area => {
                    const meshes = (ownerMeshes.get(pin.placeId) || []).filter(mesh => mesh.userData.submapIndex === area.subStageIndex);
                    const section = frameDesertOwner(config.camera, area.worldBounds, meshes);
                    subareaCameras[id][area.id] = section.camera;
                    rawFocusFrames[id].subareas[area.id] = section;
                    return { id: area.id, subStageIndex: area.subStageIndex, ...section.framing };
                });
            }
        }
        scene.updateMatrixWorld(true);
        function highlight(id) {
            current = id || '';
            const pin = config.pins[id]; ring.visible = !!pin;
            if (!pin) return;
            const size = focusBoxes.get(id).getSize(new THREE.Vector3());
            ring.position.fromArray(pin.worldAnchor); ring.position.y += 0.025;
            ring.scale.set(Math.max(0.3, Math.min(3, size.x * 0.35)), Math.max(0.3, Math.min(3, size.z * 0.35)), 1);
        }
        const sharedView = createCameraView(config, scene, camera, renderer, render, onChange, { highlight });
        view = Object.assign({}, sharedView, {
            pins() {
                const arranged = layoutDesertPins(sharedView.pins(), shellConfig.screenPins);
                layoutFailures = arranged.failures;
                return arranged.pins;
            }
        });
        const focusControls = createFocusControls(config, subareaCameras, view, lifetime, (id, width, height, inset) => {
            const raw = rawFocusFrames[id], whole = reserveObservationFrame(raw.whole, config.camera, width, height, inset);
            config.focusCameras[id] = whole.camera;
            focusFraming[id] = { placeId: config.pins[id].placeId, ...whole.framing,
                subareas: config.pins[id].subareas.map(area => {
                    const framed = reserveObservationFrame(raw.subareas[area.id], config.camera, width, height, inset);
                    subareaCameras[id][area.id] = framed.camera;
                    return { id: area.id, subStageIndex: area.subStageIndex, ...framed.framing };
                }) };
        });
        const raycaster = new THREE.Raycaster();
        lifetime.listen(canvas, 'pointerdown', event => { down = [event.clientX, event.clientY]; });
        lifetime.listen(canvas, 'click', event => {
            if (!down || view.stats().editing || view.stats().focusId || Math.hypot(event.clientX - down[0], event.clientY - down[1]) > 5) return;
            const rect = canvas.getBoundingClientRect();
            raycaster.setFromCamera(new THREE.Vector2((event.clientX - rect.left) / rect.width * 2 - 1,
                1 - (event.clientY - rect.top) / rect.height * 2), camera);
            const hit = raycaster.intersectObject(root, true)[0];
            if (!hit) return;
            const matches = [...focusBoxes].filter(([, box]) => box.containsPoint(hit.point));
            matches.sort((a, b) => a[1].getSize(new THREE.Vector3()).lengthSq() - b[1].getSize(new THREE.Vector3()).lengthSq());
            if (matches.length) onSelect?.(matches[0][0]);
        });
        view.resize(1024, 576); view.overview(null, false); clearTimeout(timeout); live();
        const loadMs = Math.round(performance.now() - started);
        return {
            canvas, view, render, dispose, focusControls,
            visualConfig: { pins: config.pins, camera: config.camera },
            stats: () => Object.assign({ scene: 'desert', frames, loadMs, calls: renderer.info.render.calls,
                triangles: renderer.info.render.triangles, geometries: renderer.info.memory.geometries,
                textures: renderer.info.memory.textures, width: canvas.width, height: canvas.height,
                worldStageIds: [...WORLD_STAGE_IDS], screenStageIds: Object.keys(shellConfig.screenPins),
                loadedHashes: { 'scene.glb': sceneHash }, sceneTransport, indexCompatibility, layoutFailures: [...layoutFailures],
                surround: surround.stats(camera), focusFraming, subareaObservation: focusControls.stats(),
                selectedVisualId: current }, view.stats())
        };
    } catch (error) { dispose(); throw error; }
}
