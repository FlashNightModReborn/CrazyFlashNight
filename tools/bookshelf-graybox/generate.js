// Bookshelf 3D shelf graybox generator (v3: native-material recomposed layout).
//   node tools/bookshelf-graybox/generate.js
// Reads docs/design-data/bookshelf-shelf-draft.json + data/books/catalog.json,
// the ffdec vector channel in tools/bookshelf-shelf-extract/out-ffdec/
// (DefineSprite_57 shelf body + native spines 59/65/69) and the Ruffle channel
// in tools/bookshelf-shelf-extract/out/ (CF1 title logo). The shelf front is a
// 9-patch recomposed from the 57 render (boards/divider/interior tiles) onto
// the design grid, so content compartments can outgrow the native pixel
// proportions while keeping the original furniture material. Generated labels
// (sail-twins spine, six disc faces, collection box art) use an offscreen
// canvas in headless Edge in the native spine typography. Geometry comes from
// the vendored three r180; GLB is written by ./glb-writer.js fully embedded.
// Imported by tools/import-bookshelf-shelf.py. CF2-6 are commercial assets and
// are never exported.
'use strict';
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { pathToFileURL } = require('url');

const ROOT = path.resolve(__dirname, '..', '..');
const DESIGN = path.join(ROOT, 'docs/design-data/bookshelf-shelf-draft.json');
const CATALOG = path.join(ROOT, 'data/books/catalog.json');
const EXTRACT_RUFFLE = path.join(ROOT, 'tools/bookshelf-shelf-extract/out');
const EXTRACT_FFDEC = path.join(ROOT, 'tools/bookshelf-shelf-extract/out-ffdec');
const OUT = path.join(__dirname, 'out');
const THREE_URL = pathToFileURL(path.join(ROOT, 'launcher/web/assets/stage-diorama/base-gate/vendor/three.module.js')).href;
const WRITER_URL = pathToFileURL(path.join(__dirname, 'glb-writer.js')).href;

const sha = data => crypto.createHash('sha256').update(data).digest('hex');
const hex = value => { const n = parseInt(value.slice(1), 16); return [(n >> 16 & 255) / 255, (n >> 8 & 255) / 255, (n & 255) / 255, 1]; };

function composeAll(job) {
    // Runs in a Playwright page. job = {labels: [...], shelf: {...}}; returns
    // {name: dataURL} for each label plus the recomposed shelf front.
    const out = {};
    for (const spec of job.labels) {
        const canvas = document.createElement('canvas');
        canvas.width = spec.width; canvas.height = spec.height;
        const g = canvas.getContext('2d');
        g.fillStyle = spec.color; g.fillRect(0, 0, spec.width, spec.height);
        g.strokeStyle = spec.border || 'rgba(0,0,0,0.45)'; g.lineWidth = 4;
        g.strokeRect(2, 2, spec.width - 4, spec.height - 4);
        g.textAlign = 'center'; g.textBaseline = 'middle';
        if (spec.kind === 'spine') {
            g.fillStyle = spec.ink;
            g.font = '600 ' + spec.fontSize + 'px "' + spec.fontFamily + '", sans-serif';
            const chars = [...spec.title], step = Math.min(spec.fontSize * 1.3, (spec.height * 0.72) / chars.length);
            const top = spec.height * 0.06 + step / 2;
            chars.forEach((ch, i) => g.fillText(ch, spec.width / 2, top + i * step));
            if (spec.author) {
                g.font = '500 ' + Math.round(spec.fontSize * 0.42) + 'px "' + spec.fontFamily + '", sans-serif';
                g.fillText(spec.author, spec.width / 2, spec.height * 0.9);
            }
        } else if (spec.kind === 'disc') {
            g.fillStyle = spec.ink;
            g.font = '700 ' + spec.fontSize + 'px "' + spec.fontFamily + '", sans-serif';
            const chars = [...spec.series], step = spec.fontSize * 1.24;
            const top = spec.height * 0.07 + step / 2;
            chars.forEach((ch, i) => g.fillText(ch, spec.width / 2, top + i * step));
            g.font = '700 ' + Math.round(spec.fontSize * 1.35) + 'px "' + spec.fontFamily + '", sans-serif';
            g.fillText(spec.number, spec.width / 2, spec.height * 0.72);
            g.font = '500 ' + Math.round(spec.fontSize * 0.4) + 'px "' + spec.fontFamily + '", sans-serif';
            g.fillText(spec.subtitle, spec.width / 2, spec.height * 0.86);
        }
        out[spec.name] = canvas.toDataURL('image/png');
    }
    const work = [];
    for (const spec of job.labels.filter(s => s.kind === 'box')) {
        work.push((async () => {
            const canvas = document.createElement('canvas');
            canvas.width = spec.width; canvas.height = spec.height;
            const g = canvas.getContext('2d');
            g.fillStyle = spec.color; g.fillRect(0, 0, spec.width, spec.height);
            const logo = new Image();
            await new Promise((resolve, reject) => { logo.onload = resolve; logo.onerror = reject; logo.src = spec.logo; });
            // The tray and disc row occlude the lower band of the panel from the
            // fixed camera, so every element stays in the top band.
            const h = spec.height * 0.44, w = h * (logo.width / logo.height);
            g.drawImage(logo, (spec.width - w) / 2, spec.height * 0.02, w, h);
            g.fillStyle = spec.ink; g.textAlign = 'center'; g.textBaseline = 'middle';
            g.font = '700 ' + Math.round(spec.height * 0.17) + 'px "' + spec.fontFamily + '", sans-serif';
            g.fillText(spec.title, spec.width / 2, spec.height * 0.57);
            g.font = '500 ' + Math.round(spec.height * 0.09) + 'px "' + spec.fontFamily + '", sans-serif';
            g.fillStyle = spec.subInk;
            g.fillText(spec.subtitle, spec.width / 2, spec.height * 0.70);
            const bw = spec.width * 0.09, gap = spec.width * 0.024, y = spec.height * 0.78, bh = spec.height * 0.055;
            const total = spec.colors.length * bw + (spec.colors.length - 1) * gap;
            spec.colors.forEach((color, i) => {
                g.fillStyle = color;
                g.fillRect((spec.width - total) / 2 + i * (bw + gap), y, bw, bh);
            });
            g.strokeStyle = 'rgba(255,255,255,0.16)'; g.lineWidth = 4;
            g.strokeRect(2, 2, spec.width - 4, spec.height - 4);
            out[spec.name] = canvas.toDataURL('image/png');
        })());
    }
    work.push((async () => {
        const shelf = job.shelf;
        const img = new Image();
        await new Promise((resolve, reject) => { img.onload = resolve; img.onerror = reject; img.src = shelf.image; });
        const canvas = document.createElement('canvas');
        canvas.width = shelf.W; canvas.height = shelf.H;
        const g = canvas.getContext('2d');
        g.fillStyle = shelf.base; g.fillRect(0, 0, shelf.W, shelf.H);
        // Tile rects are recorded against a 1064-wide baseline raster.
        const ts = img.naturalWidth / shelf.tileBaseline;
        const tile = (rect, dx, dy, dw, dh) => g.drawImage(img,
            rect[0] * ts, rect[1] * ts, rect[2] * ts, rect[3] * ts, dx, dy, dw, dh);
        // Compartment interiors first, then boards/walls over their edges.
        const rows = shelf.rows; // [{top, floor}] canvas px
        for (const colName of ['left', 'right']) {
            const [x0, x1] = shelf.columns[colName];
            rows.forEach((row, i) => {
                tile(shelf.tiles.interior, x0, row.top, x1 - x0, row.floor - row.top);
                const shade = shelf.shadeCells.find(c => c.column === colName && c.row === i);
                if (shade) { g.fillStyle = 'rgba(0,0,0,' + shade.alpha + ')'; g.fillRect(x0, row.top, x1 - x0, row.floor - row.top); }
            });
        }
        tile(shelf.tiles.top, 0, 0, shelf.W, shelf.topH);
        rows.forEach(row => tile(shelf.tiles.board, 0, row.floor, shelf.W, shelf.boardH));
        tile(shelf.tiles.bottom, 0, shelf.H - shelf.bottomH, shelf.W, shelf.bottomH);
        tile(shelf.tiles.left, 0, shelf.topH, shelf.sideW, shelf.H - shelf.topH - shelf.bottomH);
        tile(shelf.tiles.right, shelf.W - shelf.sideW, shelf.topH, shelf.sideW, shelf.H - shelf.topH - shelf.bottomH);
        tile(shelf.tiles.divider, shelf.columns.left[1], shelf.topH, shelf.columns.right[0] - shelf.columns.left[1],
            shelf.H - shelf.topH - shelf.bottomH);
        out[shelf.name] = canvas.toDataURL('image/png');
    })());
    return Promise.all(work).then(() => out);
}

function readChannel(dir, reportName, schema) {
    const report = JSON.parse(fs.readFileSync(path.join(dir, reportName), 'utf8'));
    if (report.schema !== schema) throw new Error('unexpected extract report: ' + reportName);
    return {
        report,
        read(name) {
            const data = fs.readFileSync(path.join(dir, name));
            const entry = report.files[name];
            if (!entry || sha(data) !== entry.sha256) throw new Error('extract closure drift: ' + name);
            return data;
        }
    };
}

async function main() {
    const design = JSON.parse(fs.readFileSync(DESIGN, 'utf8'));
    const catalog = JSON.parse(fs.readFileSync(CATALOG, 'utf8'));
    if (design.schema !== 'bookshelf-shelf-design/1') throw new Error('unexpected design draft');
    const catalogBooks = catalog.books.map(b => b.id);
    if (JSON.stringify(design.books.concat([design.playableBook])) !== JSON.stringify(catalogBooks)) {
        throw new Error('design books do not match catalog order: ' + catalogBooks);
    }
    const playable = catalog.books.find(b => b.id === design.playableBook);
    if (JSON.stringify(playable.chapters.map(c => c.id)) !== JSON.stringify(design.discs)) throw new Error('design discs mismatch');
    const ffdec = readChannel(EXTRACT_FFDEC, 'ffdec-report.json', 'bookshelf-shelf-ffdec-report/1');
    const ruffle = readChannel(EXTRACT_RUFFLE, 'extract-report.json', 'bookshelf-shelf-extract-report/1');
    const averages = ffdec.report.averages || {};
    const THREE = await import(THREE_URL);
    const { buildGlb } = await import(WRITER_URL);

    const spineExtract = design.extractSources.spines;
    const discPalette = design.extractSources.discPalette.map(key => {
        if (!averages[key]) throw new Error('missing average for ' + key);
        return averages[key];
    });
    const logoPng = ruffle.read(design.extractSources.boxLogo + '.png');
    const shelfBodyPng = ffdec.read(design.extractSources.body + '.png');

    // Shared box geometry with per-face baked shade as vertex color (unlit style).
    const box = new THREE.BoxGeometry(1, 1, 1);
    const shade = { '1,0,0': 0.82, '-1,0,0': 0.72, '0,1,0': 1, '0,-1,0': 0.5, '0,0,1': 0.92, '0,0,-1': 0.6 };
    const normals = box.attributes.normal.array, colors = new Float32Array(box.attributes.position.count * 3);
    for (let i = 0; i < normals.length; i += 3) {
        const s = shade[[normals[i], normals[i + 1], normals[i + 2]].join(',')] || 1;
        colors[i] = colors[i + 1] = colors[i + 2] = s;
    }
    const plane = new THREE.PlaneGeometry(1, 1);
    // glTF textures are not flipped (flipY=false); plane v=1 sits at the top,
    // so flip v to keep canvas-rendered labels upright.
    for (let i = 1; i < plane.attributes.uv.array.length; i += 2) plane.attributes.uv.array[i] = 1 - plane.attributes.uv.array[i];
    const geometries = {
        box: { position: box.attributes.position.array, normal: box.attributes.normal.array,
            uv: box.attributes.uv.array, color: colors, indices: box.index.array },
        plane: { position: plane.attributes.position.array, normal: plane.attributes.normal.array,
            uv: plane.attributes.uv.array, indices: plane.index.array }
    };

    const luminance = value => {
        const n = parseInt(value.slice(1), 16);
        return (0.2126 * (n >> 16 & 255) + 0.7152 * (n >> 8 & 255) + 0.0722 * (n & 255)) / 255;
    };
    const labelSpecs = [];
    for (const book of catalog.books) {
        if (book.format === 'playable' || spineExtract[book.id]) continue;
        labelSpecs.push({ name: 'spine-' + book.id, kind: 'spine', title: book.title, author: 'Forever爱牛 著',
            color: '#e8e8e8', ink: '#202020', fontSize: 44, ...design.textures.spine });
    }
    playable.chapters.forEach((chapter, i) => {
        const base = discPalette[i];
        labelSpecs.push({ name: 'disc-' + chapter.id, kind: 'disc',
            series: '闪客快打', subtitle: i === 0 ? chapter.title : '第 ' + (i + 1) + ' 章', number: String(i + 1),
            color: base, ink: luminance(base) > 0.45 ? '#202020' : '#f2ead8',
            border: luminance(base) > 0.45 ? 'rgba(0,0,0,0.45)' : 'rgba(255,255,255,0.35)',
            fontSize: 52, ...design.textures.disc });
    });
    labelSpecs.push({ name: 'box-crazy-flasher', kind: 'box', title: '闪客快打', subtitle: '六碟合集 · 原版',
        ink: '#f2ead8', subInk: '#d3dde3', colors: discPalette,
        logo: 'data:image/png;base64,' + logoPng.toString('base64'),
        color: design.shelf.palette.box, ...design.textures.box });

    // 9-patch recomposition of the native shelf front onto the design grid.
    const S = design.shelf, G = S.grid, body = S.body;
    // Books fill cells in catalog order; used cells stay lit, the rest are shaded.
    const bookCells = [];
    {
        const queue = design.books.slice();
        for (const cell of S.bookFillOrder) {
            const take = Math.min(queue.length, cell.capacity);
            if (take > 0) bookCells.push({ column: cell.column, row: cell.row, books: queue.splice(0, take) });
        }
        if (queue.length) throw new Error('book fill order capacity exhausted: ' + queue.length + ' books unplaced');
    }
    const usedCells = bookCells.map(c => c.column + c.row)
        .concat([design.placements.archives.column + design.placements.archives.row,
            design.placements.boxSet.column + design.placements.boxSet.row]);
    const shadeCells = [];
    for (const column of ['left', 'right']) {
        G.rowFloors.forEach((_, row) => {
            if (!usedCells.includes(column + row)) {
                shadeCells.push({ column, row, alpha: row >= 2 ? S.emptyShade.row2 : S.emptyShade.other });
            }
        });
    }
    const k = body.textureWidth / body.width;
    const px = value => value * k;
    const W = Math.round(px(body.width)), H = Math.round(px(body.height));
    const rowsTopDown = G.rowFloors.map((floor, i) => ({ floor: H - px(floor), top: H - px(floor + G.rowHeights[i]) }));
    const shelfJob = {
        name: design.extractSources.body, W, H, base: '#4b4b4b', tileBaseline: 1064,
        image: 'data:image/png;base64,' + shelfBodyPng.toString('base64'),
        tiles: S.composeTiles,
        topH: px(G.topH), bottomH: px(G.bottomH), boardH: px(G.boardH),
        sideW: px(G.sideW),
        columns: { left: [px(S.columns.left[0] + body.width / 2), px(S.columns.left[1] + body.width / 2)],
            right: [px(S.columns.right[0] + body.width / 2), px(S.columns.right[1] + body.width / 2)] },
        rows: rowsTopDown,
        shadeCells
    };

    const edge = [process.env['ProgramFiles(x86)'], process.env.ProgramFiles].filter(Boolean)
        .map(p => path.join(p, 'Microsoft/Edge/Application/msedge.exe')).find(fs.existsSync);
    if (!edge) throw new Error('Edge not found for canvas texture rendering');
    const { chromium } = require(path.join(ROOT, 'launcher/perf/node_modules/playwright'));
    const browser = await chromium.launch({ executablePath: edge, headless: true });
    const images = [];
    try {
        const page = await browser.newPage();
        const composed = await page.evaluate(composeAll, {
            labels: labelSpecs.map(s => ({ fontFamily: design.textures.fontFamily, ...s })),
            shelf: shelfJob
        });
        for (const spec of labelSpecs) images.push({ name: spec.name, png: Buffer.from(composed[spec.name].split(',')[1], 'base64') });
        images.push({ name: design.extractSources.body, png: Buffer.from(composed[design.extractSources.body].split(',')[1], 'base64') });
    } finally { await browser.close(); }
    for (const key of Object.values(spineExtract)) images.push({ name: key, png: ffdec.read(key + '.png') });

    const palette = S.palette;
    const spineAverage = id => averages[spineExtract[id]] || '#e8e8e8';
    const materials = [
        { name: 'tray', baseColorFactor: hex(palette.tray) },
        { name: 'box-panel', baseColorFactor: hex(palette.box) },
        { name: 'shell-side', baseColorFactor: hex(S.shell.colors.side) },
        { name: 'shell-top', baseColorFactor: hex(S.shell.colors.top) },
        { name: 'shell-bottom', baseColorFactor: hex(S.shell.colors.bottom) },
        { name: 'floor', baseColorFactor: hex(S.floorSlab.color) }
    ];
    const materialIndex = {};
    materials.forEach((m, i) => { materialIndex[m.name] = i; });
    for (const book of design.books) {
        materialIndex['book-' + book] = materials.length;
        materials.push({ name: 'book-' + book, baseColorFactor: hex(spineAverage(book)) });
    }
    design.discs.forEach((id, i) => {
        materialIndex['disc-' + id] = materials.length;
        materials.push({ name: 'disc-' + id, baseColorFactor: hex(discPalette[i]) });
    });
    const nodes = [];
    function addBox(name, material, size, center) {
        nodes.push({ name, geometry: 'box', material: materialIndex[material], translation: center, scale: size });
    }
    function addLabel(name, imageName, size, center) {
        materialIndex[imageName] = materials.length;
        materials.push({ name: imageName, texture: images.findIndex(i => i.name === imageName), doubleSided: false });
        nodes.push({ name, geometry: 'plane', material: materialIndex[imageName], translation: center, scale: [size[0], size[1], 1] });
    }

    // Recomposed native shelf front as the furniture main visual.
    materialIndex['shelf-body'] = materials.length;
    materials.push({ name: 'shelf-body', texture: images.findIndex(i => i.name === design.extractSources.body) });
    nodes.push({ name: 'SHELF_body', geometry: 'plane', material: materialIndex['shelf-body'],
        translation: [0, body.height / 2, body.z], scale: [body.width, body.height, 1] });
    // Shallow shell giving the billboard furniture a body (edge colors extended).
    const shell = S.shell, zc = body.z + shell.depth / 2;
    addBox('SHELL_left', 'shell-side', [shell.side, body.height, shell.depth], [-body.width / 2 - shell.side / 2, body.height / 2, zc]);
    addBox('SHELL_right', 'shell-side', [shell.side, body.height, shell.depth], [body.width / 2 + shell.side / 2, body.height / 2, zc]);
    addBox('SHELL_top', 'shell-top', [body.width + 2 * shell.side, shell.top, shell.depth], [0, body.height + shell.top / 2, zc]);
    addBox('SHELL_bottom', 'shell-bottom', [body.width + 2 * shell.side, shell.side, shell.depth], [0, -shell.side / 2, zc]);
    // Real floor slabs under each used compartment so contents have contact.
    function addFloor(name, column, row) {
        const [x0, x1] = S.columns[column], floor = G.rowFloors[row];
        addBox(name, 'floor', [x1 - x0, S.floorSlab.thickness, S.floorSlab.depth],
            [(x0 + x1) / 2, floor - S.floorSlab.thickness / 2, body.z + S.floorSlab.depth / 2 - 0.4]);
    }
    addFloor('FLOOR_archives', design.placements.archives.column, design.placements.archives.row);
    addFloor('FLOOR_boxset', design.placements.boxSet.column, design.placements.boxSet.row);
    bookCells.forEach((cell, i) => addFloor('FLOOR_books_' + i, cell.column, cell.row));

    // Books fill cells in catalog order, left-aligned within each compartment.
    const bookMargin = 1.2;
    for (const cell of bookCells) {
        const floor = G.rowFloors[cell.row], [x0] = S.columns[cell.column];
        let cursor = x0 + bookMargin;
        for (const id of cell.books) {
            const g = design.bookGeometry[id];
            const xc = cursor + g.width / 2;
            addBox('BOOK_' + id, 'book-' + id, [g.width, g.height, g.depth], [xc, floor + g.height / 2, design.bookGeometry.centerZ]);
            addLabel('LABEL_' + id, 'spine-' + id, [g.width * 0.8, g.height * 0.96],
                [xc, floor + g.height / 2, design.bookGeometry.centerZ + g.depth / 2 + 0.08]);
            cursor += g.width + design.bookGeometry.gap;
        }
    }

    const B = design.boxSet, boxFloor = G.rowFloors[design.placements.boxSet.row];
    addBox('BOX_crazy-flasher', 'box-panel', [B.panel.width, B.panel.height, B.panel.depth],
        [B.panel.x, boxFloor + B.panel.height / 2, B.panel.z]);
    addLabel('LABEL_box_crazy-flasher', 'box-crazy-flasher', [B.panel.width * 0.92, B.panel.height * 0.9],
        [B.panel.x, boxFloor + B.panel.height / 2, B.panel.z + B.panel.depth / 2 + 0.08]);
    addBox('TRAY_base', 'tray', [B.tray.width, B.tray.height, B.tray.depth], [B.tray.x, boxFloor + B.tray.height / 2, B.tray.z]);
    addBox('TRAY_lip', 'tray', [B.tray.width, B.tray.lipHeight, 0.35],
        [B.tray.x, boxFloor + B.tray.height + B.tray.lipHeight / 2, B.tray.z + B.tray.depth / 2 - 0.18]);
    addBox('TRAY_left', 'tray', [0.35, B.tray.lipHeight, B.tray.depth], [B.tray.x - B.tray.width / 2 + 0.18, boxFloor + B.tray.height + B.tray.lipHeight / 2, B.tray.z]);
    addBox('TRAY_right', 'tray', [0.35, B.tray.lipHeight, B.tray.depth], [B.tray.x + B.tray.width / 2 - 0.18, boxFloor + B.tray.height + B.tray.lipHeight / 2, B.tray.z]);
    const discBase = boxFloor + B.tray.height;
    const rowWidth = design.discs.length * B.disc.width + (design.discs.length - 1) * B.disc.gap;
    design.discs.forEach((id, i) => {
        const xc = B.tray.x - rowWidth / 2 + B.disc.width / 2 + i * (B.disc.width + B.disc.gap);
        addBox('DISC_' + id, 'disc-' + id, [B.disc.width, B.disc.height, B.disc.depth], [xc, discBase + B.disc.height / 2, B.disc.z]);
        addLabel('LABEL_' + id, 'disc-' + id, [B.disc.width * 0.88, B.disc.height * 0.94],
            [xc, discBase + B.disc.height / 2, B.disc.z + B.disc.depth / 2 + 0.06]);
    });

    const glb = buildGlb({ geometries, materials, images, nodes,
        generator: 'tools/bookshelf-graybox (three r' + THREE.REVISION + ' vendor)' });
    fs.rmSync(OUT, { recursive: true, force: true });
    fs.mkdirSync(path.join(OUT, 'textures'), { recursive: true });
    fs.writeFileSync(path.join(OUT, 'scene.glb'), glb);
    const textures = {};
    for (const image of images) {
        fs.writeFileSync(path.join(OUT, 'textures', image.name + '.png'), image.png);
        textures[image.name] = { bytes: image.png.length, sha256: sha(image.png) };
    }
    const inputs = ['tools/bookshelf-graybox/generate.js', 'tools/bookshelf-graybox/glb-writer.js',
        'docs/design-data/bookshelf-shelf-draft.json', 'data/books/catalog.json',
        'tools/bookshelf-shelf-extract/extract.js', 'tools/bookshelf-shelf-extract/patch-swf.js',
        'tools/bookshelf-shelf-extract/extract-ffdec.js', 'tools/bookshelf-shelf-extract/crops.json',
        'tools/bookshelf-shelf-extract/out/extract-report.json', 'tools/bookshelf-shelf-extract/out-ffdec/ffdec-report.json']
        .map(p => ({ path: p, sha256: sha(fs.readFileSync(path.join(ROOT, p))) }));
    fs.writeFileSync(path.join(OUT, 'report.json'), JSON.stringify({
        schema: 'bookshelf-shelf-graybox-report/1', generatorInputs: inputs,
        threeRevision: THREE.REVISION,
        artSources: 'ffdec vector channel (out-ffdec, shelf body 9-patch + native spines) + Ruffle channel (out, CF1 title logo); see both reports for source identity',
        discPalette,
        scene: { bytes: glb.length, sha256: sha(glb) }, textures,
        nodes: nodes.map(n => n.name)
    }, null, 2) + '\n');
    console.log('bookshelf graybox: ' + nodes.length + ' nodes, ' + images.length + ' textures, glb ' + glb.length + ' bytes');
}
main().catch(error => { console.error(error); process.exitCode = 1; });
