#!/usr/bin/env node
'use strict';

const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

const repoRoot = path.resolve(__dirname, '..', '..');
const playwrightPath = path.join(
    repoRoot, 'launcher', 'perf', 'node_modules', 'playwright');
const cases = [
    {id:'empty', hpFrame:129, mpFrame:101},
    {id:'min_step', hpFrame:128, mpFrame:100},
    {id:'p25', hpFrame:97, mpFrame:76},
    {id:'p50', hpFrame:65, mpFrame:51},
    {id:'p75', hpFrame:33, mpFrame:26},
    {id:'p99', hpFrame:3, mpFrame:2},
    {id:'full', hpFrame:1, mpFrame:1},
    {id:'mp_vf34', hpFrame:44, mpFrame:34},
    {id:'mp_vf35', hpFrame:45, mpFrame:35},
    {id:'mp_vf70', hpFrame:90, mpFrame:70},
    {id:'mp_vf91', hpFrame:117, mpFrame:91}
];

function fail(message) {
    throw new Error(message);
}

function option(name) {
    const prefix = `--${name}=`;
    const value = process.argv.slice(2).find(arg => arg.startsWith(prefix));
    return value ? value.slice(prefix.length) : null;
}

function resolveInsideRepo(value, label) {
    if (!value) {
        fail(`Missing --${label}=<repo-relative-path>.`);
    }
    const resolved = path.resolve(repoRoot, value);
    const relative = path.relative(repoRoot, resolved);
    if (!relative || relative.startsWith('..') || path.isAbsolute(relative)) {
        fail(`${label} must resolve below the repository root.`);
    }
    return resolved;
}

function edgePath() {
    const candidates = [
        path.join(
            process.env['ProgramFiles(x86)'] || 'C:\\Program Files (x86)',
            'Microsoft', 'Edge', 'Application', 'msedge.exe'),
        path.join(
            process.env.ProgramFiles || 'C:\\Program Files',
            'Microsoft', 'Edge', 'Application', 'msedge.exe'),
        process.env.LOCALAPPDATA
            ? path.join(
                process.env.LOCALAPPDATA,
                'Microsoft', 'Edge', 'Application', 'msedge.exe')
            : null
    ];
    return candidates.find(candidate => candidate && fs.existsSync(candidate));
}

function sha256(bytes) {
    return crypto.createHash('sha256').update(bytes).digest('hex');
}

function readExactAsset(manifestRoot, asset) {
    const assetPath = path.resolve(manifestRoot, asset.path);
    const relative = path.relative(manifestRoot, assetPath);
    if (!relative || relative.startsWith('..') || path.isAbsolute(relative)) {
        fail(`Asset escaped manifest root: ${asset.path}`);
    }
    const bytes = fs.readFileSync(assetPath);
    const actual = sha256(bytes);
    if (actual !== asset.sha256) {
        fail(`Asset SHA-256 mismatch: ${asset.id}`);
    }
    return {
        id: asset.id,
        relativePath: asset.path.replace(/\\/g, '/'),
        bytes,
        sha256: actual,
        text: bytes.toString('utf8')
    };
}

function extractSvgInner(text, id) {
    if (!/^<svg\b[^>]*xmlns="http:\/\/www\.w3\.org\/2000\/svg"/u.test(text) ||
        !/<\/svg>\s*$/u.test(text)) {
        fail(`Asset is not a canonical standalone SVG: ${id}`);
    }
    const start = text.indexOf('>') + 1;
    return text.slice(start, text.lastIndexOf('</svg>'));
}

function xmlEscape(value) {
    return String(value)
        .replace(/&/g, '&amp;')
        .replace(/"/g, '&quot;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;');
}

function matrix(values) {
    if (!Array.isArray(values) || values.length !== 6 ||
        values.some(value => !Number.isFinite(value))) {
        fail('Placement matrix must contain six finite numbers.');
    }
    return `matrix(${values.join(' ')})`;
}

function pointsPath(points) {
    if (!points.length) {
        return '';
    }
    const normalized = points.map(pair => {
        if (!Array.isArray(pair) || pair.length !== 2 ||
            pair.some(value => !Number.isFinite(value))) {
            fail('Mask correspondence contains a non-finite point.');
        }
        return [pair[0] / 20, pair[1] / 20];
    });
    const commands = [`M ${normalized[0][0]} ${normalized[0][1]}`];
    for (let index = 1; index < normalized.length; index++) {
        commands.push(`L ${normalized[index][0]} ${normalized[index][1]}`);
    }
    commands.push('Z');
    return commands.join(' ');
}

function interpolateCorrespondence(interval, sourceFrame) {
    const span = interval.sourceEnd - interval.sourceStart;
    if (span <= 0) {
        fail('Mask interval span must be positive.');
    }
    const u = (sourceFrame - interval.sourceStart) / span;
    return interval.correspondence.map(segment => {
        const a = segment.aStartAndAnchorsTwips;
        const b = segment.bStartAndAnchorsTwips;
        if (!Array.isArray(a) || !Array.isArray(b) ||
            a.length !== b.length || a.length < 4) {
            fail('Mask correspondence endpoints are incompatible.');
        }
        return pointsPath(a.map((point, index) => [
            point[0] + (b[index][0] - point[0]) * u,
            point[1] + (b[index][1] - point[1]) * u
        ]));
    });
}

function mpMaskPaths(manifest, maskId, virtualFrame) {
    const sourceFrame = virtualFrame - 1;
    if (sourceFrame === 100) {
        return [];
    }
    const interval = manifest.gauges.mp.morphIntervals.find(item =>
        item.mask === maskId &&
        sourceFrame >= item.sourceStart &&
        sourceFrame <= item.sourceEnd);
    if (!interval) {
        fail(`No ${maskId} interval for virtual frame ${virtualFrame}.`);
    }
    return interpolateCorrespondence(interval, sourceFrame);
}

function hpSector(manifest, frame) {
    const gauge = manifest.gauges.hp;
    const frameMap = gauge.frameMap;
    const fraction = Math.max(0, Math.min(
        1,
        (frameMap.emptyVirtualFrame - frame) / frameMap.stepCount));
    if (fraction === 0) {
        return '';
    }
    if (fraction === 1) {
        return '<circle cx="0" cy="0" r="128"/>';
    }
    if (gauge.clip.type !== 'radial-sector' ||
        gauge.clip.direction !== 'counterclockwise') {
        fail('HP clip contract drifted.');
    }
    const start = gauge.clip.startAngleDegrees * Math.PI / 180;
    const end = start - Math.PI * 2 * fraction;
    const radius = gauge.clip.radius;
    const startX = radius * Math.cos(start);
    const startY = radius * Math.sin(start);
    const endX = radius * Math.cos(end);
    const endY = radius * Math.sin(end);
    const largeArc = fraction > 0.5 ? 1 : 0;
    const d = [
        'M 0 0',
        `L ${startX} ${startY}`,
        `A ${radius} ${radius} 0 ${largeArc} 0 ${endX} ${endY}`,
        'Z'
    ].join(' ');
    return `<path d="${xmlEscape(d)}"/>`;
}

function addClipToGroup(inner, groupId, clipId) {
    const token = `<g id="${groupId}"`;
    const first = inner.indexOf(token);
    if (first < 0 || inner.indexOf(token, first + token.length) >= 0) {
        fail(`Expected exactly one SVG group: ${groupId}`);
    }
    return inner.slice(0, first) +
        `<g id="${groupId}" clip-path="url(#${clipId})"` +
        inner.slice(first + token.length);
}

function rotateSvgGradients(inner, gradientIds, degrees) {
    if (!Array.isArray(gradientIds) || gradientIds.length === 0 ||
        !Number.isFinite(degrees)) {
        fail('HP gradient rotation contract is incomplete.');
    }
    if (degrees === 0) {
        return inner;
    }
    const radians = degrees * Math.PI / 180;
    const cos = Math.cos(radians);
    const sin = Math.sin(radians);
    let result = inner;
    for (const gradientId of gradientIds) {
        if (typeof gradientId !== 'string' ||
            !/^[A-Za-z_][A-Za-z0-9_.:-]*$/u.test(gradientId)) {
            fail('HP gradient rotation contains an invalid SVG id.');
        }
        const idToken = `id="${gradientId}"`;
        const idOffset = result.indexOf(idToken);
        if (idOffset < 0 ||
            result.indexOf(idToken, idOffset + idToken.length) >= 0) {
            fail(`Expected exactly one HP gradient: ${gradientId}`);
        }
        const elementStart = result.lastIndexOf('<', idOffset);
        const elementEnd = result.indexOf('>', idOffset);
        if (elementStart < 0 || elementEnd < 0) {
            fail(`Malformed HP gradient element: ${gradientId}`);
        }
        const opening = result.slice(elementStart, elementEnd + 1);
        if (!/^<(?:linearGradient|radialGradient)\b/u.test(opening)) {
            fail(`HP rotation target is not a gradient: ${gradientId}`);
        }
        const match = opening.match(
            /\bgradientTransform="matrix\(([^")]+)\)"/u);
        if (!match) {
            fail(`HP gradient has no matrix transform: ${gradientId}`);
        }
        const values = match[1].trim().split(/\s+/u).map(Number);
        if (values.length !== 6 ||
            values.some(value => !Number.isFinite(value))) {
            fail(`HP gradient matrix is invalid: ${gradientId}`);
        }
        const [a, b, c, d, e, f] = values;
        const composed = [
            cos * a - sin * b,
            sin * a + cos * b,
            cos * c - sin * d,
            sin * c + cos * d,
            cos * e - sin * f,
            sin * e + cos * f
        ].map(value => Object.is(value, -0) ? 0 : value);
        const replacement =
            `gradientTransform="matrix(${composed.join(' ')})"`;
        const changed = opening.replace(match[0], replacement);
        result = result.slice(0, elementStart) + changed +
            result.slice(elementEnd + 1);
    }
    return result;
}

function renderSvg(manifest, assets, scenario) {
    const byId = new Map(assets.map(asset => [
        asset.id, extractSvgInner(asset.text, asset.id)]));
    const leftPaths = mpMaskPaths(
        manifest, 'mp-left-mask', scenario.mpFrame);
    const rightPaths = mpMaskPaths(
        manifest, 'mp-right-mask', scenario.mpFrame);
    let mpFill = byId.get('mp.fill');
    mpFill = addClipToGroup(
        mpFill, 'mp-fill-left-background-copy', 'mp-left-clip');
    mpFill = addClipToGroup(
        mpFill, 'mp-fill-left-slot', 'mp-left-clip');
    mpFill = addClipToGroup(
        mpFill, 'mp-fill-right-decoration', 'mp-right-clip');
    mpFill = addClipToGroup(
        mpFill, 'mp-fill-right-slot', 'mp-right-clip');

    const pathElements = paths => paths
        .map(value => `<path d="${xmlEscape(value)}"/>`).join('');
    const defs = [
        '<defs>',
        `<clipPath id="hp-sector">${hpSector(manifest, scenario.hpFrame)}</clipPath>`,
        `<clipPath id="mp-left-clip">${pathElements(leftPaths)}</clipPath>`,
        `<clipPath id="mp-right-clip">${pathElements(rightPaths)}</clipPath>`,
        '</defs>'
    ].join('');
    const layer = (id, extra) =>
        `<g data-layer="${id}"${extra || ''}>${byId.get(id)}</g>`;
    const rimVariant = manifest.gauges.mp.rimVariants
        .filter(item => scenario.mpFrame >= item.startVirtualFrame)
        .at(-1);
    if (!rimVariant || !byId.has(rimVariant.assetId)) {
        fail(`No MP rim variant for virtual frame ${scenario.mpFrame}.`);
    }
    const rotation = manifest.gauges.hp.fillTextureRotation;
    if (rotation.assetId !== 'hp.fill' ||
        rotation.positiveDirection !== 'clockwise' ||
        JSON.stringify(rotation.pivot) !== JSON.stringify([0, 0])) {
        fail('HP fill texture rotation contract drifted.');
    }
    const hpRotation = (
        scenario.hpFrame +
        rotation.sourceFrameOffset
    ) * rotation.degreesPerSourceFrame;
    const hpFill = rotateSvgGradients(
        byId.get(rotation.assetId),
        rotation.svgGradientIds,
        hpRotation);

    return [
        '<svg id="player-info-render" xmlns="http://www.w3.org/2000/svg"',
        ' width="1024" height="64" viewBox="0 0 1024 64"',
        ' preserveAspectRatio="none">',
        defs,
        `<g id="mp" transform="${matrix(manifest.gauges.mp.stageMatrix)}">`,
        layer('mp.backplate'),
        `<g data-layer="mp.fill">${mpFill}</g>`,
        layer(rimVariant.assetId),
        '</g>',
        `<g id="hp" transform="${matrix(manifest.gauges.hp.stageMatrix)}">`,
        layer('hp.backplate'),
        '<g data-layer="hp.fill" clip-path="url(#hp-sector)">',
        hpFill,
        '</g>',
        layer('hp.rim'),
        '</g>',
        '</svg>'
    ].join('');
}

async function main() {
    if (!fs.existsSync(playwrightPath)) {
        fail(
            'Missing launcher/perf Playwright. Run ' +
            '"npm --prefix launcher/perf ci --ignore-scripts".');
    }
    const manifestPath = resolveInsideRepo(option('manifest'), 'manifest');
    const outputRoot = resolveInsideRepo(option('output'), 'output');
    const manifestBytes = fs.readFileSync(manifestPath);
    const manifest = JSON.parse(manifestBytes.toString('utf8'));
    if (manifest.format !== 'cf7.player-info-hud.asset-manifest' ||
        manifest.schemaVersion !== 1 ||
        manifest.units?.sourceTwipsPerSvgUnit !== 20 ||
        manifest.stage?.compositeOrder?.join('|') !== 'mp|hp') {
        fail('Harness only accepts the exact canonical runtime manifest.');
    }
    if (manifestBytes.includes(Buffer.from('pending-oracle'))) {
        fail('Canonical manifest retains an unresolved oracle token.');
    }
    const manifestRoot = path.dirname(manifestPath);
    const assets = manifest.assets.map(asset =>
        readExactAsset(manifestRoot, asset));
    const required = [
        'hp.backplate', 'hp.fill', 'hp.rim',
        'mp.backplate', 'mp.fill', 'mp.rim',
        'mp.rim-vf70', 'mp.rim-vf91'
    ];
    if (assets.map(asset => asset.id).join('|') !== required.join('|')) {
        fail('Manifest asset order/closure is not the exact eight-file B0 set.');
    }
    const revisionHash = crypto.createHash('sha256');
    for (const asset of [...assets].sort((left, right) =>
        Buffer.from(left.relativePath).compare(Buffer.from(right.relativePath)))) {
        revisionHash.update(Buffer.from(asset.relativePath, 'utf8'));
        revisionHash.update(Buffer.from([0]));
        revisionHash.update(asset.bytes);
        revisionHash.update(Buffer.from([0]));
    }
    const actualRevision = `sha256:${revisionHash.digest('hex')}`;
    if (actualRevision !== manifest.assetSet.revision) {
        fail('Manifest asset-set revision does not bind the exact asset bytes.');
    }

    const edge = edgePath();
    if (!edge) {
        fail('Microsoft Edge executable was not found.');
    }
    fs.mkdirSync(outputRoot, {recursive:true});
    const chromium = require(playwrightPath).chromium;
    const browser = await chromium.launch({
        executablePath: edge,
        headless: true
    });
    const results = [];
    let browserVersion;
    try {
        browserVersion = browser.version();
        const page = await browser.newPage({
            viewport: {width: 1024, height: 64},
            deviceScaleFactor: 1,
            colorScheme: 'dark',
            reducedMotion: 'reduce'
        });
        const pageErrors = [];
        page.on('pageerror', error => pageErrors.push(error.message));
        for (const scenario of cases) {
            pageErrors.length = 0;
            const svg = renderSvg(manifest, assets, scenario);
            await page.setContent(
                '<!doctype html><meta charset="utf-8">' +
                '<style>html,body{margin:0;width:1024px;height:64px;' +
                'overflow:hidden;background:transparent}</style>' + svg,
                {waitUntil: 'load'});
            if (pageErrors.length) {
                fail(`${scenario.id} page error: ${pageErrors.join(' | ')}`);
            }
            const metrics = await page.locator('#player-info-render').evaluate(
                element => {
                    const rect = element.getBoundingClientRect();
                    return {
                        width: rect.width,
                        height: rect.height,
                        dpr: window.devicePixelRatio
                    };
                });
            if (metrics.width !== 1024 || metrics.height !== 64 ||
                metrics.dpr !== 1) {
                fail(`${scenario.id} viewport/DPR drifted.`);
            }
            const pngPath = path.join(outputRoot, `${scenario.id}.png`);
            await page.locator('#player-info-render').screenshot({
                path: pngPath,
                omitBackground: true,
                animations: 'disabled'
            });
            const png = fs.readFileSync(pngPath);
            results.push({
                caseId: scenario.id,
                hpVirtualFrame: scenario.hpFrame,
                mpVirtualFrame: scenario.mpFrame,
                path: `${scenario.id}.png`,
                bytes: png.length,
                sha256: sha256(png)
            });
        }
    } finally {
        await browser.close();
    }

    const edgeBytes = fs.readFileSync(edge);
    const report = {
        schema: 'cf7.player_info.web_svg_harness.v1',
        status: 'canonical_manifest_rendered_awaiting_human_review',
        viewport: [1024, 64],
        deviceScaleFactor: 1,
        background: 'transparent',
        manifest: {
            path: path.relative(repoRoot, manifestPath).replace(/\\/g, '/'),
            sha256: sha256(manifestBytes),
            assetSetRevision: manifest.assetSet.revision,
            schemaVersion: manifest.schemaVersion
        },
        renderSemantics: {
            compositeOrder: manifest.stage.compositeOrder,
            hpFillDegreesPerSourceFrame:
                manifest.gauges.hp.fillTextureRotation.degreesPerSourceFrame,
            mpRimVariantStarts:
                manifest.gauges.mp.rimVariants.map(item => item.startVirtualFrame)
        },
        browser: {
            family: 'Microsoft Edge via Playwright chromium',
            version: browserVersion,
            executableSha256: sha256(edgeBytes),
            executableBytes: edgeBytes.length
        },
        assets: assets.map(asset => ({
            id: asset.id,
            path: asset.relativePath,
            bytes: asset.bytes.length,
            sha256: asset.sha256
        })),
        cases: results
    };
    const reportPath = path.join(outputRoot, 'web-render-report.json');
    fs.writeFileSync(reportPath, JSON.stringify(report, null, 2) + '\n');
    process.stdout.write(
        `PlayerInfo Web SVG canonical harness ${results.length}/${cases.length} ` +
        `rendered; report=${path.relative(repoRoot, reportPath)}\n`);
}

main().catch(error => {
    process.stderr.write(`${error && error.stack ? error.stack : error}\n`);
    process.exitCode = 1;
});
