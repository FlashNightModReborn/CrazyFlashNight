import * as THREE from '../../assets/stage-diorama/base-gate/vendor/three.module.js';

const SOIL_IMAGE = 'R10 normalized soil grain';
const CUT_IMAGE = 'terrain-geographic-palette.png';
const ROWS = [0, 0.03, 0.12, 0.32, 0.65, 1];

function textureName(mesh) { return !Array.isArray(mesh.material) && mesh.material?.map?.name || ''; }
function worldPoint(mesh, index, target) { return target.fromBufferAttribute(mesh.geometry.attributes.position, index).applyMatrix4(mesh.matrixWorld); }
function pointArray(point) { return point.toArray().map(value => Math.round(value * 1e6) / 1e6); }

// The original regional sheet remains the only terrain source. This outer apron
// is a disposable presentation layer: it cannot move anchors or receive picks.
export function createDesertSurround(root) {
    root.updateMatrixWorld(true);
    const tops = [], wallCandidates = [], bounds = new THREE.Box3();
    root.traverse(mesh => {
        if (!mesh.isMesh || mesh.userData.placeId !== 'environment') return;
        const name = textureName(mesh);
        if (name === SOIL_IMAGE || name.startsWith(SOIL_IMAGE + '.')) {
            tops.push(mesh); bounds.expandByObject(mesh, true);
        } else if (name === CUT_IMAGE) wallCandidates.push(mesh);
    });
    const size = bounds.getSize(new THREE.Vector3());
    if (!tops.length || size.x < 20 || size.z < 20) throw new Error('Desert regional terrain boundary is unavailable');
    const center = bounds.getCenter(new THREE.Vector3()), epsilon = Math.max(size.x, size.z) * 0.000002;
    const perimeter = 2 * (size.x + size.z), samples = new Map(), point = new THREE.Vector3();
    function boundaryDistance(p) {
        if (Math.abs(p.z - bounds.max.z) <= epsilon) return p.x - bounds.min.x;
        if (Math.abs(p.x - bounds.max.x) <= epsilon) return size.x + bounds.max.z - p.z;
        if (Math.abs(p.z - bounds.min.z) <= epsilon) return size.x + size.z + bounds.max.x - p.x;
        if (Math.abs(p.x - bounds.min.x) <= epsilon) return 2 * size.x + size.z + p.z - bounds.min.z;
        return null;
    }
    for (const mesh of tops) {
        const { position, color, uv } = mesh.geometry.attributes;
        if (!color || !uv) throw new Error('Desert terrain boundary needs its source colour and UV attributes');
        for (let i = 0; i < position.count; i++) {
            worldPoint(mesh, i, point);
            const distance = boundaryDistance(point);
            if (distance === null) continue;
            const key = Math.round((distance % perimeter) / epsilon);
            let sample = samples.get(key);
            if (!sample) {
                sample = { distance, count: 0, point: new THREE.Vector3(), color: new THREE.Vector3(), uv: new THREE.Vector2() };
                samples.set(key, sample);
            }
            sample.count++; sample.point.add(point);
            sample.color.add(new THREE.Vector3(color.getX(i), color.getY(i), color.getZ(i)));
            sample.uv.add(new THREE.Vector2(uv.getX(i), uv.getY(i)));
        }
    }
    const edge = [...samples.values()].sort((a, b) => a.distance - b.distance);
    for (const sample of edge) {
        sample.point.divideScalar(sample.count); sample.color.divideScalar(sample.count); sample.uv.divideScalar(sample.count);
    }
    if (edge.length < 4) throw new Error('Desert terrain does not expose a closed regional perimeter');
    // A missing side must fail before any source display object is hidden.
    for (const distance of [0, size.x, size.x + size.z, 2 * size.x + size.z]) {
        if (!edge.some(sample => Math.abs(sample.distance - distance) <= epsilon)) throw new Error('Desert terrain perimeter has a missing corner');
    }

    // Fit the source planar UV field, rather than copying a scale guessed from
    // a material name. Extending this same field keeps grain continuous.
    const matrix = new THREE.Matrix3(), sums = Array(9).fill(0), rhsU = new THREE.Vector3(), rhsV = new THREE.Vector3();
    for (const sample of edge) {
        const a = [(sample.point.x - center.x) / size.x, (sample.point.z - center.z) / size.z, 1];
        for (let row = 0; row < 3; row++) for (let col = 0; col < 3; col++) sums[row * 3 + col] += a[row] * a[col];
        rhsU.addScaledVector(new THREE.Vector3(...a), sample.uv.x); rhsV.addScaledVector(new THREE.Vector3(...a), sample.uv.y);
    }
    matrix.set(...sums);
    if (Math.abs(matrix.determinant()) < 1e-8) throw new Error('Desert terrain UV continuation is singular');
    matrix.invert(); rhsU.applyMatrix3(matrix); rhsV.applyMatrix3(matrix);
    function extendUV(p) {
        const a = new THREE.Vector3((p.x - center.x) / size.x, (p.z - center.z) / size.z, 1);
        return [rhsU.dot(a), rhsV.dot(a)];
    }
    const uvError = Math.max(...edge.map(sample => {
        const uv = extendUV(sample.point); return Math.max(Math.abs(uv[0] - sample.uv.x), Math.abs(uv[1] - sample.uv.y));
    }));
    if (uvError > 0.001) throw new Error('Desert terrain UV field cannot be continued without a seam');

    const lowland = edge.filter(sample => sample.point.y < bounds.min.y + 0.3);
    const flatColor = new THREE.Vector3();
    for (const sample of lowland.length ? lowland : edge) flatColor.add(sample.color);
    flatColor.divideScalar((lowland.length ? lowland : edge).length);
    const padding = Math.max(size.x, size.z) * 1.5, positions = [], colors = [], uvs = [], indices = [];
    const outerBounds = bounds.clone();
    outerBounds.min.x -= padding; outerBounds.max.x += padding;
    outerBounds.min.z -= padding; outerBounds.max.z += padding;
    outerBounds.min.y = 0;
    for (const amount of ROWS) {
        const blend = THREE.MathUtils.smoothstep(amount, 0, 0.65);
        for (const sample of edge) {
            const p = sample.point.clone();
            p.x += (p.x - center.x) / (size.x / 2) * padding * amount;
            p.z += (p.z - center.z) / (size.z / 2) * padding * amount;
            p.y *= 1 - blend;
            positions.push(...p.toArray()); colors.push(...sample.color.clone().lerp(flatColor, blend).toArray());
            uvs.push(...(amount === 0 ? sample.uv.toArray() : extendUV(p)));
        }
    }
    for (let row = 0; row < ROWS.length - 1; row++) for (let i = 0; i < edge.length; i++) {
        const j = (i + 1) % edge.length, a = row * edge.length + i, b = row * edge.length + j;
        const c = a + edge.length, d = b + edge.length;
        indices.push(a, c, b, b, c, d);
    }
    const geometry = new THREE.BufferGeometry();
    geometry.setAttribute('position', new THREE.Float32BufferAttribute(positions, 3));
    geometry.setAttribute('color', new THREE.Float32BufferAttribute(colors, 3));
    geometry.setAttribute('uv', new THREE.Float32BufferAttribute(uvs, 2));
    geometry.setIndex(indices); geometry.computeBoundingBox(); geometry.computeBoundingSphere();
    const object = new THREE.Mesh(geometry, tops[0].material.clone());
    object.name = 'DESERT_PRESENTATION_SURROUND';
    object.userData = { presentationOnly: true, terrainRole: 'derived-regional-surround' };
    object.raycast = () => {};
    const hiddenWalls = [];
    for (const mesh of wallCandidates) {
        const position = mesh.geometry.attributes.position;
        let allOnBoundary = true, lowest = Infinity, highest = -Infinity;
        const wallBounds = new THREE.Box3();
        for (let i = 0; i < position.count; i++) {
            worldPoint(mesh, i, point); wallBounds.expandByPoint(point);
            if (boundaryDistance(point) === null) allOnBoundary = false;
            lowest = Math.min(lowest, point.y); highest = Math.max(highest, point.y);
        }
        const spansOuterFrame = ['x', 'z'].every(axis => Math.abs(wallBounds.min[axis] - bounds.min[axis]) <= epsilon
            && Math.abs(wallBounds.max[axis] - bounds.max[axis]) <= epsilon);
        if (allOnBoundary && spansOuterFrame && lowest < bounds.min.y - 0.5 && highest <= bounds.max.y + epsilon) {
            hiddenWalls.push({ name: mesh.name, triangles: (mesh.geometry.index?.count || position.count) / 3, bottomY: lowest });
            mesh.visible = false;
        }
    }
    const evidence = { state: 'ready', sourceTopBounds: { min: pointArray(bounds.min), max: pointArray(bounds.max) },
        sourceBoundaryHeightRange: [Math.min(...edge.map(sample => sample.point.y)), Math.max(...edge.map(sample => sample.point.y))],
        outerBounds: { min: pointArray(outerBounds.min), max: pointArray(outerBounds.max) },
        sourceBoundaryVertices: edge.length, triangles: indices.length / 3, uvFitMaxError: uvError,
        hiddenCutWalls: hiddenWalls, sharedSourceTexture: textureName(tops[0]), sourceAttributesChanged: false };
    const ray = new THREE.Raycaster(), ground = new THREE.Plane(new THREE.Vector3(0, 1, 0), 0), intersection = new THREE.Vector3();
    return { object, stats(camera) {
        const corners = [[-1, -1], [1, -1], [-1, 1], [1, 1]].map(ndc => {
            ray.setFromCamera(new THREE.Vector2(...ndc), camera);
            const hit = ray.ray.intersectPlane(ground, intersection);
            return { ndc, groundPoint: hit ? pointArray(hit) : null, inside: !!hit && hit.x >= outerBounds.min.x
                && hit.x <= outerBounds.max.x && hit.z >= outerBounds.min.z && hit.z <= outerBounds.max.z };
        });
        return { ...evidence, groundPlaneViewportCorners: corners, groundPlaneViewportCovered: corners.every(corner => corner.inside) };
    } };
}
