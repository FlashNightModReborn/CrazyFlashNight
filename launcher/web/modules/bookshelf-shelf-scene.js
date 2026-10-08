// Bookshelf overview 3D shelf scene. Render-on-demand graybox diorama:
// hover pulls an entry out of the shelf, click only selects (no writes here).
import * as THREE from '../assets/stage-diorama/base-gate/vendor/three.module.js';
import { GLTFLoader } from '../assets/stage-diorama/base-gate/vendor/GLTFLoader.js';
import { createCameraView } from './stage-select/stage-select-diorama-camera.js';
import { normalizeShelfConfig, validateEmbeddedGlb } from './bookshelf-shelf-config.js';
import './workbench-lifecycle.js';

const assetRoot = new URL('../assets/bookshelf/shelf/', import.meta.url);

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

export async function createScene(options, onLost, onSelect, signal) {
    const started = performance.now();
    const lifetime = new globalThis.WorkbenchLifecycle.DisposableStack();
    const abort = new AbortController();
    const scene = new THREE.Scene();
    let renderer, view, root, canvas, disposed = false, frames = 0, down = null, sceneHash = '';
    let width = 1024, height = 576, highlighted = '';
    const entries = new Map();
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
        if (!configResponse.ok) throw new Error('Shelf config HTTP ' + configResponse.status);
        const config = normalizeShelfConfig(await configResponse.json());
        live();
        const sceneUrl = new URL('scene.glb', assetRoot);
        sceneUrl.searchParams.set('sha256', config.assetHashes['scene.glb']);
        const response = await fetch(sceneUrl, { signal: abort.signal });
        if (!response.ok) throw new Error('Shelf scene HTTP ' + response.status);
        const bytes = await response.arrayBuffer();
        live(); validateEmbeddedGlb(bytes);
        if (!globalThis.crypto?.subtle) throw new Error('Shelf scene fingerprint verification unavailable');
        const digest = await crypto.subtle.digest('SHA-256', bytes);
        sceneHash = [...new Uint8Array(digest)].map(value => value.toString(16).padStart(2, '0')).join('');
        if (sceneHash !== config.assetHashes['scene.glb']) throw new Error('Shelf scene fingerprint mismatch');
        live();
        const gltf = await new GLTFLoader().parseAsync(bytes, assetRoot.href);
        root = gltf.scene;
        // Register parsed resources before checking cancellation so late loads are released.
        scene.add(root); live();
        renderer = new THREE.WebGLRenderer({ antialias: true, powerPreference: 'low-power' });
        renderer.setPixelRatio(1); renderer.setSize(1024, 576, false);
        renderer.outputColorSpace = THREE.SRGBColorSpace; renderer.toneMapping = THREE.NoToneMapping;
        const maxAnisotropy = renderer.capabilities.getMaxAnisotropy();
        root.traverse(object => {
            for (const material of [].concat(object.material || [])) {
                if (material.map) { material.map.anisotropy = Math.min(8, maxAnisotropy); material.map.needsUpdate = true; }
            }
        });
        canvas = renderer.domElement; canvas.className = 'bookshelf-shelf-canvas'; canvas.setAttribute('aria-hidden', 'true');
        lifetime.listen(canvas, 'webglcontextlost', event => { event.preventDefault(); if (!disposed) onLost(); });
        scene.background = new THREE.Color(config.lighting.background || '#221c17');
        camera = new THREE.OrthographicCamera(-100, 100, 56.25, -56.25, 0.01, 5000);
        camera.position.fromArray(config.camera.gltfPosition); camera.lookAt(new THREE.Vector3(...config.camera.gltfTarget));
        const wanted = options && Array.isArray(options.entries) ? new Set(options.entries) : null;
        for (const [id, entry] of Object.entries(config.entries)) {
            if (wanted && !wanted.has(id)) continue;
            const nodes = entry.meshes.map(name => {
                const node = root.getObjectByName(name);
                if (!node) throw new Error('Shelf mesh missing: ' + name);
                node.userData.entryId = id;
                return node;
            });
            entries.set(id, { kind: entry.kind, nodes, base: nodes.map(node => node.position.z),
                colors: nodes.map(node => node.material.color.clone()) });
        }
        if (!entries.size) throw new Error('Shelf scene has no catalog entries');
        scene.updateMatrixWorld(true);
        // Archive folders for resident character slots are runtime data: created
        // and disposed on each snapshot sync, never part of the GLB closure.
        const zone = config.archiveZone;
        const folderBox = new THREE.BoxGeometry(1, 1, 1);
        // CanvasTexture keeps three's default flipY=true, unlike GLB-embedded
        // textures; the plane UVs stay unflipped here.
        const folderPlane = new THREE.PlaneGeometry(1, 1);
        lifetime.defer(() => { folderBox.dispose(); folderPlane.dispose(); });
        const archives = new Map();
        let archiveSignature = '';
        function folderLabel(name, active, more) {
            const c = document.createElement('canvas');
            c.width = 96; c.height = 288;
            const g = c.getContext('2d');
            g.fillStyle = zone.color; g.fillRect(0, 0, 96, 288);
            // Folder edge thickness lines keep the body from reading as a bare box.
            g.fillStyle = 'rgba(60,45,25,0.28)'; g.fillRect(0, 0, 8, 288); g.fillRect(88, 0, 8, 288);
            g.fillStyle = 'rgba(255,248,230,0.35)'; g.fillRect(8, 0, 4, 288);
            // Inset label card like a real archive box label holder.
            g.fillStyle = zone.label; g.fillRect(14, 18, 68, 216);
            g.strokeStyle = 'rgba(60,45,25,0.65)'; g.lineWidth = 3; g.strokeRect(14, 18, 68, 216);
            g.fillStyle = '#2e2417'; g.textAlign = 'center'; g.textBaseline = 'middle';
            g.font = '600 26px "Microsoft YaHei", sans-serif';
            const chars = [...name].slice(0, 7);
            const step = Math.min(30, 180 / Math.max(1, chars.length));
            chars.forEach((ch, i) => g.fillText(ch, 48, 34 + step / 2 + i * step));
            if (active) { g.fillStyle = '#7a2e1d'; g.beginPath(); g.arc(48, 254, 7, 0, Math.PI * 2); g.fill(); }
            g.fillStyle = '#2e2417'; g.font = '500 18px "Microsoft YaHei", sans-serif';
            g.fillText(more ? '展开…' : '档案', 48, 272);
            const texture = new THREE.CanvasTexture(c);
            texture.colorSpace = THREE.SRGBColorSpace;
            return texture;
        }
        function setArchives(items) {
            if (disposed) return;
            const list = (Array.isArray(items) ? items : [])
                .filter(item => item && typeof item.id === 'string' && typeof item.name === 'string')
                .slice(0, zone.max + 1); // max folders plus one optional "more archives" box
            const signature = JSON.stringify(list);
            if (signature === archiveSignature) return;
            archiveSignature = signature;
            for (const record of archives.values()) {
                record.nodes.forEach(node => node.removeFromParent());
                record.ownedMaterials.forEach(material => material.dispose());
                record.ownedTextures.forEach(texture => texture.dispose());
                entries.delete(record.id);
            }
            archives.clear();
            list.forEach((item, i) => {
                const xc = zone.leftEdge + i * (zone.width + zone.gap) + zone.width / 2;
                const yc = zone.floorY + zone.height / 2;
                const body = new THREE.Mesh(folderBox, new THREE.MeshBasicMaterial({ color: zone.color }));
                body.scale.set(zone.width, zone.height, zone.depth);
                body.position.set(xc, yc, zone.z);
                body.userData.entryId = item.id;
                const texture = folderLabel(item.name, item.active, item.more === true);
                const label = new THREE.Mesh(folderPlane, new THREE.MeshBasicMaterial({ map: texture }));
                label.scale.set(zone.width, zone.height, 1);
                label.position.set(xc, yc, zone.z + zone.depth / 2 + 0.12);
                label.userData.entryId = item.id;
                scene.add(body, label);
                const record = { id: item.id, nodes: [body, label], ownedMaterials: [body.material, label.material], ownedTextures: [texture] };
                archives.set(item.id, record);
                entries.set(item.id, { kind: 'archive', nodes: record.nodes,
                    base: record.nodes.map(node => node.position.z),
                    colors: record.nodes.map(node => node.material.color.clone()) });
            });
            render();
        }
        function highlight(id) {
            if (id === highlighted) return;
            const previous = entries.get(highlighted);
            if (previous) previous.nodes.forEach((node, i) => {
                node.position.z = previous.base[i];
                node.material.color.copy(previous.colors[i]);
            });
            highlighted = id || '';
            const entry = entries.get(highlighted);
            if (entry) entry.nodes.forEach((node, i) => {
                node.position.z = entry.base[i] + config.hoverPull;
                node.material.color.copy(entry.colors[i]).multiplyScalar(1.35);
            });
            canvas.style.cursor = entry ? 'pointer' : '';
        }
        view = createCameraView(config, scene, camera, renderer, render, null, {
            highlight,
            resize: (w, h) => { width = w; height = h; }
        });
        const raycaster = new THREE.Raycaster();
        function pick(event) {
            const rect = canvas.getBoundingClientRect();
            raycaster.setFromCamera(new THREE.Vector2((event.clientX - rect.left) / rect.width * 2 - 1,
                1 - (event.clientY - rect.top) / rect.height * 2), camera);
            const hit = raycaster.intersectObjects([...entries.values()].flatMap(entry => entry.nodes), false)[0];
            return hit ? hit.object.userData.entryId : '';
        }
        lifetime.listen(canvas, 'pointerdown', event => { down = [event.clientX, event.clientY]; });
        lifetime.listen(canvas, 'pointermove', event => { if (!event.buttons && !view.stats().editing) view.hover(pick(event)); });
        lifetime.listen(canvas, 'pointerleave', () => view.hover(''));
        lifetime.listen(canvas, 'click', event => {
            if (!down || view.stats().editing || Math.hypot(event.clientX - down[0], event.clientY - down[1]) > 5) return;
            const id = pick(event);
            if (id) onSelect?.(id);
        });
        view.resize(1024, 576); view.overview(null, false); clearTimeout(timeout); live();
        const loadMs = Math.round(performance.now() - started);
        return {
            canvas, view, render, dispose, setArchives,
            archiveMax: () => zone.max,
            targets() {
                const result = {};
                for (const [id, entry] of entries) {
                    const bounds = new THREE.Box3();
                    entry.nodes.forEach(node => bounds.expandByObject(node));
                    const center = bounds.getCenter(new THREE.Vector3()).project(camera);
                    result[id] = { x: (center.x * 0.5 + 0.5) * width, y: (-center.y * 0.5 + 0.5) * height };
                }
                return result;
            },
            stats: () => Object.assign({ scene: 'bookshelf-shelf', frames, loadMs, calls: renderer.info.render.calls,
                triangles: renderer.info.render.triangles, geometries: renderer.info.memory.geometries,
                textures: renderer.info.memory.textures, width: canvas.width, height: canvas.height,
                loadedHashes: { 'scene.glb': sceneHash }, entries: [...entries.keys()], archives: archives.size }, view.stats())
        };
    } catch (error) { dispose(); throw error; }
}
