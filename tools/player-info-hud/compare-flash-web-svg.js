#!/usr/bin/env node
'use strict';

const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

const repoRoot = path.resolve(__dirname, '..', '..');
const playwrightRoot = path.join(
    repoRoot, 'launcher', 'perf', 'node_modules', 'playwright');
const viewport = {width:1024, height:64};
const canonicalStaticLayerScope = 'canonical_static_svg_layers_only';
const webRenderSemanticsKeys = [
    'capturedLayerScope',
    'compositeOrder',
    'csharpProgrammaticDynamicTextIncluded',
    'csharpProgrammaticGlowIncluded',
    'hpFillDegreesPerSourceFrame',
    'mpRimVariantStarts'
].sort();
const expectedCases = [
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
const expectedAssets = [
    {id:'hp.backplate', path:'hp/backplate.svg'},
    {id:'hp.fill', path:'hp/fill.svg'},
    {id:'hp.rim', path:'hp/rim.svg'},
    {id:'mp.backplate', path:'mp/backplate.svg'},
    {id:'mp.fill', path:'mp/fill.svg'},
    {id:'mp.rim', path:'mp/rim.svg'},
    {id:'mp.rim-vf70', path:'mp/rim-vf70.svg'},
    {id:'mp.rim-vf91', path:'mp/rim-vf91.svg'}
];

function fail(message) {
    throw new Error(message);
}

function parseOptions() {
    const names = ['flash', 'web', 'output'];
    const result = {};
    for (const argument of process.argv.slice(2)) {
        const match = argument.match(/^--([a-z]+)=(.+)$/u);
        if (!match || !names.includes(match[1]) ||
            Object.hasOwn(result, match[1])) {
            fail(`Unsupported or duplicate argument: ${argument}`);
        }
        result[match[1]] = match[2];
    }
    for (const name of names) {
        if (!Object.hasOwn(result, name)) {
            fail(`Expected exactly one --${name}=<repo-relative-path>.`);
        }
    }
    return result;
}

function resolveBelow(base, relativeValue, label) {
    if (typeof relativeValue !== 'string' || !relativeValue ||
        path.isAbsolute(relativeValue)) {
        fail(`${label} must be a non-empty relative path.`);
    }
    const resolved = path.resolve(base, relativeValue);
    const relative = path.relative(base, resolved);
    if (!relative || relative.startsWith('..') || path.isAbsolute(relative)) {
        fail(`${label} must resolve below its declared root.`);
    }
    return resolved;
}

function resolveInsideRepo(relativeValue, label) {
    return resolveBelow(repoRoot, relativeValue, label);
}

function repoRelative(filePath) {
    return path.relative(repoRoot, filePath).replace(/\\/g, '/');
}

function sha256(bytes) {
    return crypto.createHash('sha256').update(bytes).digest('hex');
}

function assertSha(value, label) {
    if (typeof value !== 'string' || !/^[0-9a-f]{64}$/iu.test(value)) {
        fail(`${label} is not a SHA-256.`);
    }
    return value.toLowerCase();
}

function pngSize(bytes, label) {
    const signature = Buffer.from([
        0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a
    ]);
    if (bytes.length < 24 || !bytes.subarray(0, 8).equals(signature) ||
        bytes.toString('ascii', 12, 16) !== 'IHDR') {
        fail(`${label} is not a complete PNG with an IHDR.`);
    }
    return {
        width: bytes.readUInt32BE(16),
        height: bytes.readUInt32BE(20)
    };
}

function assertPngSize(bytes, width, height, label) {
    const actual = pngSize(bytes, label);
    if (actual.width !== width || actual.height !== height) {
        fail(
            `${label} dimensions are ${actual.width}x${actual.height}; ` +
            `expected ${width}x${height}.`);
    }
}

function readJson(filePath, label) {
    let bytes;
    let value;
    try {
        bytes = fs.readFileSync(filePath);
        value = JSON.parse(bytes.toString('utf8'));
    } catch (error) {
        fail(`Cannot read ${label}: ${error.message}`);
    }
    return {bytes, value, sha256:sha256(bytes)};
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

function newInputTracker() {
    const entries = new Map();
    const read = (filePath, label) => {
        const absolute = path.resolve(filePath);
        const bytes = fs.readFileSync(absolute);
        const record = {
            path: repoRelative(absolute),
            bytes: bytes.length,
            sha256: sha256(bytes)
        };
        const prior = entries.get(absolute);
        if (prior && (prior.bytes !== record.bytes ||
            prior.sha256 !== record.sha256)) {
            fail(`${label} changed while its input closure was read.`);
        }
        entries.set(absolute, record);
        return {bytes, identity:record};
    };
    const verify = () => {
        for (const [filePath, expected] of entries) {
            const bytes = fs.readFileSync(filePath);
            if (bytes.length !== expected.bytes ||
                sha256(bytes) !== expected.sha256) {
                fail(`Input identity changed during comparison: ${expected.path}`);
            }
        }
    };
    return {read, verify, entries};
}

function readTrackedJson(tracker, filePath, label) {
    const tracked = tracker.read(filePath, label);
    let value;
    try {
        value = JSON.parse(tracked.bytes.toString('utf8'));
    } catch (error) {
        fail(`Cannot parse ${label}: ${error.message}`);
    }
    return {
        bytes: tracked.bytes,
        value,
        sha256: tracked.identity.sha256,
        identity: tracked.identity
    };
}

function readVerifiedArtifact(
    tracker, root, record, label, expectedWidth, expectedHeight) {
    if (!record || typeof record.path !== 'string') {
        fail(`${label} has no artifact path.`);
    }
    const expectedSha = assertSha(record.sha256, `${label}.sha256`);
    const artifactPath = resolveBelow(root, record.path, `${label}.path`);
    const tracked = tracker.read(artifactPath, label);
    if (tracked.identity.sha256 !== expectedSha) {
        fail(`${label} SHA-256 mismatch.`);
    }
    if (Object.hasOwn(record, 'bytes') &&
        record.bytes !== tracked.identity.bytes) {
        fail(`${label} encoded byte length mismatch.`);
    }
    assertPngSize(
        tracked.bytes, expectedWidth, expectedHeight, label);
    return {
        path: artifactPath,
        bytes: tracked.bytes,
        identity: tracked.identity
    };
}

function validateFlashManifest(flash, reportRoot, tracker) {
    if (flash.schema !== 'cf7.player_info.flash_oracle_manifest.v1' ||
        flash.status !== 'candidate' ||
        flash.requiresHumanReview !== true) {
        fail('Flash input is not a B0-01B candidate requiring human review.');
    }
    const review = flash.humanReview;
    const expectedReviewKeys = [
        'stateCorrect',
        'noOtherHudLayers',
        'cropDoesNotEatEdges',
        'visualAestheticsAccepted'
    ];
    if (!review || review.status !== 'required' ||
        review.reviewer !== null || !review.checks ||
        Object.keys(review.checks).sort().join('|') !==
            [...expectedReviewKeys].sort().join('|') ||
        expectedReviewKeys.some(key => review.checks[key] !== null)) {
        fail('Flash candidate is not in the untouched human-review state.');
    }
    if (typeof flash.runId !== 'string' || !flash.runId ||
        typeof flash.capturedUtc !== 'string' || !flash.capturedUtc) {
        fail('Flash candidate run identity is incomplete.');
    }
    if (!flash.source || !flash.source.captureLoaderContract ||
        flash.source.captureLoaderContract.actualCaptureLoaderVerified !== true ||
        flash.source.captureLoaderContract.mainParticipatesInCapture !== false ||
        flash.source.captureLoaderContract.asLoaderParticipatesInCapture !== false ||
        !flash.source.uiSwf ||
        !flash.source.loaderSwf) {
        fail('Flash candidate source/binary-chain boundary is incomplete.');
    }
    assertSha(flash.source.uiSwf.sha256, 'Flash UI SWF SHA-256');
    assertSha(flash.source.loaderSwf.sha256, 'Flash loader SWF SHA-256');
    if (!flash.runtime || !flash.runtime.player ||
        flash.runtime.player.naturalExit !== true ||
        !Number.isSafeInteger(flash.runtime.player.bytes) ||
        flash.runtime.player.bytes <= 0) {
        fail('Flash Player runtime identity/natural-exit evidence is incomplete.');
    }
    assertSha(
        flash.runtime.player.sha256,
        'Flash Player runtime executable SHA-256');

    const capture = flash.capture;
    if (!capture || capture.captureMethod !== 'AVM1 BitmapData.draw' ||
        !capture.canvas ||
        capture.canvas.width !== viewport.width ||
        capture.canvas.height !== viewport.height ||
        JSON.stringify(capture.canvas.matrix) !==
            JSON.stringify([1, 0, 0, 1, 0, 0]) ||
        capture.canvas.pixelFormat !== 'straight_argb32' ||
        capture.canvas.background !== 'transparent_argb_0' ||
        capture.canvas.compositeBackgroundId !== null ||
        !capture.protocol ||
        JSON.stringify(capture.protocol.caseOrder) !==
            JSON.stringify(expectedCases.map(item => item.id)) ||
        !Array.isArray(capture.cases) ||
        capture.cases.length !== expectedCases.length) {
        fail('Flash candidate capture/corpus contract drifted.');
    }

    const seenPaths = new Set();
    const cases = expectedCases.map((expected, index) => {
        const actual = capture.cases[index];
        const state = actual && actual.state;
        if (!actual || actual.caseId !== expected.id || !state ||
            state.hpTargetFrame !== expected.hpFrame ||
            state.hpCurrentFrame !== expected.hpFrame ||
            state.mpTargetFrame !== expected.mpFrame ||
            state.mpCurrentFrame !== expected.mpFrame ||
            state.outOfScopeHidden !== true) {
            fail(`Flash candidate case/frame drifted at ${expected.id}.`);
        }
        assertSha(
            actual.rawArgbSha256,
            `Flash ${expected.id}.rawArgbSha256`);
        if (!actual.raw ||
            actual.raw.path !== `${expected.id}.raw.png` ||
            actual.raw.width !== viewport.width ||
            actual.raw.height !== viewport.height ||
            seenPaths.has(actual.raw.path)) {
            fail(`Flash ${expected.id} raw artifact contract drifted.`);
        }
        seenPaths.add(actual.raw.path);
        const verified = readVerifiedArtifact(
            tracker,
            reportRoot,
            actual.raw,
            `Flash ${expected.id} raw`,
            viewport.width,
            viewport.height);
        return {
            id: expected.id,
            hpFrame: expected.hpFrame,
            mpFrame: expected.mpFrame,
            path: verified.path,
            bytes: verified.bytes,
            identity: verified.identity,
            rawArgbSha256: actual.rawArgbSha256.toLowerCase()
        };
    });
    return {
        runId: flash.runId,
        capturedUtc: flash.capturedUtc,
        sourceUiSwfSha256: flash.source.uiSwf.sha256.toLowerCase(),
        loaderSwfSha256: flash.source.loaderSwf.sha256.toLowerCase(),
        player: {
            version: flash.runtime.player.fileVersion,
            bytes: flash.runtime.player.bytes,
            sha256: flash.runtime.player.sha256.toLowerCase(),
            naturalExit: true
        },
        cases
    };
}

function validateWebReport(web, reportRoot, tracker) {
    if (web.schema !== 'cf7.player_info.web_svg_harness.v1' ||
        web.status !==
            'canonical_manifest_rendered_awaiting_human_review' ||
        JSON.stringify(web.viewport) !==
            JSON.stringify([viewport.width, viewport.height]) ||
        web.deviceScaleFactor !== 1 ||
        web.background !== 'transparent') {
        fail('Unsupported Web canonical render report contract.');
    }
    if (!web.manifest || web.manifest.schemaVersion !== 1 ||
        typeof web.manifest.assetSetRevision !== 'string' ||
        !/^sha256:[0-9a-f]{64}$/u.test(web.manifest.assetSetRevision)) {
        fail('Web report has no canonical manifest identity.');
    }
    if (!web.browser ||
        web.browser.family !== 'Microsoft Edge via Playwright chromium' ||
        typeof web.browser.version !== 'string' || !web.browser.version ||
        !Number.isSafeInteger(web.browser.executableBytes) ||
        web.browser.executableBytes <= 0) {
        fail('Web report browser identity is incomplete.');
    }
    assertSha(web.browser.executableSha256, 'Web browser SHA-256');

    const manifestPath = resolveInsideRepo(
        web.manifest.path, 'Web manifest path');
    const manifestInput = readTrackedJson(
        tracker, manifestPath, 'Web canonical manifest');
    if (manifestInput.sha256 !==
        assertSha(web.manifest.sha256, 'Web manifest SHA-256')) {
        fail('Web manifest file identity changed.');
    }
    if (manifestInput.bytes.includes(Buffer.from('pending-oracle'))) {
        fail('Web canonical manifest retains an unresolved oracle token.');
    }
    const manifest = manifestInput.value;
    if (manifest.format !== 'cf7.player-info-hud.asset-manifest' ||
        manifest.schemaVersion !== 1 ||
        !manifest.assetSet ||
        manifest.assetSet.id !== 'player-info-hp-mp-b0' ||
        manifest.assetSet.revision !== web.manifest.assetSetRevision ||
        manifest.assetSet.revisionAlgorithm !==
            'sha256(sorted UTF-8 relative path + NUL + exact file bytes + NUL)' ||
        manifest.assetSet.rasterContractVersion !== 1 ||
        JSON.stringify(manifest.assetSet.runtimeCacheIdentityComponents) !==
            JSON.stringify([
                'assetSet.revision',
                'exact-manifest-sha256'
            ]) ||
        !manifest.units ||
        manifest.units.svgUnit !== 'logical-pixel' ||
        manifest.units.sourceTwipsPerSvgUnit !== 20 ||
        !manifest.stage ||
        manifest.stage.logicalWidth !== viewport.width ||
        manifest.stage.logicalHeight !== viewport.height ||
        JSON.stringify(manifest.stage.compositeOrder) !==
            JSON.stringify(['mp', 'hp'])) {
        fail('Web canonical manifest identity/unit/stage contract drifted.');
    }
    if (!manifest.rendererContract ||
        manifest.rendererContract.package !== 'Svg.Skia' ||
        manifest.rendererContract.version !== '5.1.1' ||
        manifest.rendererContract.skiaSharpVersion !== '3.119.4' ||
        manifest.rendererContract.externalResources !== 'forbidden' ||
        manifest.rendererContract.scripts !== 'forbidden' ||
        manifest.rendererContract.runtimeTextElements !== 'forbidden') {
        fail('Web canonical renderer contract drifted.');
    }
    if (!web.renderSemantics ||
        JSON.stringify(Object.keys(web.renderSemantics).sort()) !==
            JSON.stringify(webRenderSemanticsKeys) ||
        web.renderSemantics.capturedLayerScope !==
            canonicalStaticLayerScope ||
        web.renderSemantics.csharpProgrammaticDynamicTextIncluded !== false ||
        web.renderSemantics.csharpProgrammaticGlowIncluded !== false ||
        JSON.stringify(web.renderSemantics.compositeOrder) !==
            JSON.stringify(['mp', 'hp']) ||
        web.renderSemantics.hpFillDegreesPerSourceFrame !== 2.8125 ||
        JSON.stringify(web.renderSemantics.mpRimVariantStarts) !==
            JSON.stringify([1, 70, 91])) {
        fail('Web report render semantics drifted.');
    }
    if (!Array.isArray(manifest.assets) ||
        !Array.isArray(web.assets) ||
        manifest.assets.length !== expectedAssets.length ||
        web.assets.length !== expectedAssets.length) {
        fail('Web canonical eight-asset closure is incomplete.');
    }

    const manifestRoot = path.dirname(manifestPath);
    const assets = expectedAssets.map((expected, index) => {
        const source = manifest.assets[index];
        const reported = web.assets[index];
        if (!source || !reported ||
            source.id !== expected.id || source.path !== expected.path ||
            reported.id !== expected.id ||
            reported.path !== expected.path ||
            reported.sha256 !== source.sha256) {
            fail(`Web canonical asset[${index}] contract drifted.`);
        }
        const assetPath = resolveBelow(
            manifestRoot, source.path, `Web asset[${index}].path`);
        const tracked = tracker.read(assetPath, `Web asset ${source.id}`);
        const expectedSha = assertSha(
            source.sha256, `Web asset[${index}].sha256`);
        if (tracked.identity.sha256 !== expectedSha ||
            reported.bytes !== tracked.identity.bytes) {
            fail(`Web canonical asset[${index}] identity changed.`);
        }
        return {
            id: source.id,
            relativePath: source.path,
            path: tracked.identity.path,
            bytes: tracked.identity.bytes,
            sha256: tracked.identity.sha256,
            exactBytes: tracked.bytes
        };
    });
    const revisionHash = crypto.createHash('sha256');
    for (const asset of [...assets].sort((left, right) =>
        Buffer.from(left.relativePath).compare(
            Buffer.from(right.relativePath)))) {
        revisionHash.update(Buffer.from(asset.relativePath, 'utf8'));
        revisionHash.update(Buffer.from([0]));
        revisionHash.update(asset.exactBytes);
        revisionHash.update(Buffer.from([0]));
    }
    const actualRevision = `sha256:${revisionHash.digest('hex')}`;
    if (actualRevision !== manifest.assetSet.revision) {
        fail('Web canonical asset-set revision no longer binds its bytes.');
    }

    if (!Array.isArray(web.cases) ||
        web.cases.length !== expectedCases.length) {
        fail('Web report is not the exact 11-case corpus.');
    }
    const cases = expectedCases.map((expected, index) => {
        const actual = web.cases[index];
        if (!actual || actual.caseId !== expected.id ||
            actual.hpVirtualFrame !== expected.hpFrame ||
            actual.mpVirtualFrame !== expected.mpFrame ||
            actual.path !== `${expected.id}.png`) {
            fail(`Web case/frame drifted at ${expected.id}.`);
        }
        const verified = readVerifiedArtifact(
            tracker,
            reportRoot,
            actual,
            `Web ${expected.id}`,
            viewport.width,
            viewport.height);
        return {
            id: expected.id,
            hpFrame: expected.hpFrame,
            mpFrame: expected.mpFrame,
            path: verified.path,
            bytes: verified.bytes,
            identity: verified.identity
        };
    });
    return {
        manifestIdentity: {
            path: repoRelative(manifestPath),
            bytes: manifestInput.bytes.length,
            sha256: manifestInput.sha256,
            schemaVersion: manifest.schemaVersion,
            assetSetRevision: manifest.assetSet.revision
        },
        assets: assets.map(({exactBytes, ...record}) => record),
        renderSemantics: {
            capturedLayerScope:
                web.renderSemantics.capturedLayerScope,
            csharpProgrammaticDynamicTextIncluded:
                web.renderSemantics.csharpProgrammaticDynamicTextIncluded,
            csharpProgrammaticGlowIncluded:
                web.renderSemantics.csharpProgrammaticGlowIncluded
        },
        cases
    };
}

function dataUrl(bytes) {
    return `data:image/png;base64,${bytes.toString('base64')}`;
}

function decodeDataUrl(value, label) {
    const prefix = 'data:image/png;base64,';
    if (typeof value !== 'string' || !value.startsWith(prefix)) {
        fail(`${label} did not return a PNG data URL.`);
    }
    return Buffer.from(value.slice(prefix.length), 'base64');
}

function writePng(
    outputRoot, relativePath, bytes, expectedWidth, expectedHeight) {
    const outputPath = resolveBelow(
        outputRoot, relativePath, `output ${relativePath}`);
    if (fs.existsSync(outputPath)) {
        fail(`Output artifact unexpectedly exists: ${relativePath}`);
    }
    fs.mkdirSync(path.dirname(outputPath), {recursive:true});
    fs.writeFileSync(outputPath, bytes, {flag:'wx'});
    assertPngSize(
        bytes, expectedWidth, expectedHeight, `output ${relativePath}`);
    return {
        path: relativePath.replace(/\\/g, '/'),
        width: expectedWidth,
        height: expectedHeight,
        bytes: bytes.length,
        sha256: sha256(bytes)
    };
}

function normalizedBrowserIdentity(edge, version, tracker) {
    const executable = tracker.read(edge, 'Microsoft Edge executable');
    return {
        family: 'Microsoft Edge via Playwright chromium',
        version,
        executableSha256: executable.identity.sha256,
        executableBytes: executable.identity.bytes
    };
}

function assertBrowserMatches(actual, expected) {
    if (actual.family !== expected.family ||
        actual.version !== expected.version ||
        actual.executableSha256 !==
            expected.executableSha256.toLowerCase() ||
        actual.executableBytes !== expected.executableBytes) {
        fail('Comparison browser identity differs from Web rendering.');
    }
}

async function compareCase(page, flashCase, webCase) {
    const payload = {
        width: viewport.width,
        height: viewport.height,
        flashImage: dataUrl(flashCase.bytes),
        webImage: dataUrl(webCase.bytes)
    };
    return page.evaluate(async input => {
        const loadImage = source => new Promise((resolve, reject) => {
            const image = new Image();
            image.onload = () => resolve(image);
            image.onerror = () => reject(new Error('PNG decode failed.'));
            image.src = source;
        });
        const makeCanvas = (width = input.width) => {
            const canvas = document.createElement('canvas');
            canvas.width = width;
            canvas.height = input.height;
            return canvas;
        };
        const [flashImage, webImage] = await Promise.all([
            loadImage(input.flashImage),
            loadImage(input.webImage)
        ]);
        for (const [label, image] of [
            ['Flash', flashImage],
            ['Web', webImage]
        ]) {
            if (image.naturalWidth !== input.width ||
                image.naturalHeight !== input.height) {
                throw new Error(`${label} image decoded at an unexpected size.`);
            }
        }
        const flashCanvas = makeCanvas();
        const flashContext = flashCanvas.getContext(
            '2d', {alpha:true, willReadFrequently:true});
        flashContext.drawImage(flashImage, 0, 0);
        const webCanvas = makeCanvas();
        const webContext = webCanvas.getContext(
            '2d', {alpha:true, willReadFrequently:true});
        webContext.drawImage(webImage, 0, 0);
        const flashPixels = flashContext.getImageData(
            0, 0, input.width, input.height);
        const webPixels = webContext.getImageData(
            0, 0, input.width, input.height);
        const overlayPixels = new ImageData(input.width, input.height);
        const heatmapPixels = new ImageData(input.width, input.height);

        let changedPixelCount = 0;
        let changedChannelCount = 0;
        let sumAbsoluteError = 0;
        let sumSquaredError = 0;
        let maxAbsoluteChannelError = 0;
        const channelNames = ['red', 'green', 'blue', 'alpha'];
        const perChannel = Object.fromEntries(channelNames.map(name => [
            name,
            {
                changedSampleCount:0,
                sumAbsoluteError:0,
                sumSquaredError:0,
                maxAbsoluteError:0
            }
        ]));
        let changedLeft = input.width;
        let changedTop = input.height;
        let changedRight = -1;
        let changedBottom = -1;

        for (let offset = 0, pixel = 0;
            offset < flashPixels.data.length;
            offset += 4, pixel++) {
            let pixelChanged = false;
            let pixelMaximum = 0;
            for (let channel = 0; channel < 4; channel++) {
                const difference = Math.abs(
                    flashPixels.data[offset + channel] -
                    webPixels.data[offset + channel]);
                const accumulator = perChannel[channelNames[channel]];
                accumulator.sumAbsoluteError += difference;
                accumulator.sumSquaredError += difference * difference;
                accumulator.maxAbsoluteError = Math.max(
                    accumulator.maxAbsoluteError, difference);
                sumAbsoluteError += difference;
                sumSquaredError += difference * difference;
                pixelMaximum = Math.max(pixelMaximum, difference);
                maxAbsoluteChannelError = Math.max(
                    maxAbsoluteChannelError, difference);
                if (difference !== 0) {
                    accumulator.changedSampleCount++;
                    changedChannelCount++;
                    pixelChanged = true;
                }
            }
            if (pixelChanged) {
                changedPixelCount++;
                const x = pixel % input.width;
                const y = Math.floor(pixel / input.width);
                changedLeft = Math.min(changedLeft, x);
                changedTop = Math.min(changedTop, y);
                changedRight = Math.max(changedRight, x);
                changedBottom = Math.max(changedBottom, y);
            }

            const flashAlpha = flashPixels.data[offset + 3] / 255;
            const webAlpha = webPixels.data[offset + 3] / 255;
            const overlayAlpha = (flashAlpha + webAlpha) / 2;
            for (let channel = 0; channel < 3; channel++) {
                const premultiplied =
                    (flashPixels.data[offset + channel] * flashAlpha +
                     webPixels.data[offset + channel] * webAlpha) / 2;
                overlayPixels.data[offset + channel] =
                    overlayAlpha === 0
                        ? 0
                        : Math.round(premultiplied / overlayAlpha);
                const colorDifference = Math.abs(
                    flashPixels.data[offset + channel] -
                    webPixels.data[offset + channel]);
                const alphaDifference = Math.abs(
                    flashPixels.data[offset + 3] -
                    webPixels.data[offset + 3]);
                heatmapPixels.data[offset + channel] =
                    Math.max(colorDifference, alphaDifference);
            }
            overlayPixels.data[offset + 3] =
                Math.round(overlayAlpha * 255);
            heatmapPixels.data[offset + 3] = 255;
        }

        const overlayCanvas = makeCanvas();
        overlayCanvas.getContext('2d').putImageData(overlayPixels, 0, 0);
        const heatmapCanvas = makeCanvas();
        heatmapCanvas.getContext('2d').putImageData(heatmapPixels, 0, 0);
        const sideBySideCanvas = makeCanvas(input.width * 2);
        const sideBySideContext = sideBySideCanvas.getContext(
            '2d', {alpha:true});
        sideBySideContext.drawImage(flashImage, 0, 0);
        sideBySideContext.drawImage(webImage, input.width, 0);

        const totalPixels = input.width * input.height;
        const totalChannels = totalPixels * 4;
        for (const accumulator of Object.values(perChannel)) {
            accumulator.meanAbsoluteError =
                accumulator.sumAbsoluteError / totalPixels;
            accumulator.rootMeanSquaredError = Math.sqrt(
                accumulator.sumSquaredError / totalPixels);
        }
        return {
            overlayPng: overlayCanvas.toDataURL('image/png'),
            absoluteDiffPng: heatmapCanvas.toDataURL('image/png'),
            sideBySidePng: sideBySideCanvas.toDataURL('image/png'),
            alpha: {
                flash: (() => {
                    const data = flashPixels.data;
                    let nonZeroAlphaPixels = 0;
                    let partialAlphaPixels = 0;
                    let opaqueAlphaPixels = 0;
                    let alphaSum = 0;
                    let left = input.width;
                    let top = input.height;
                    let right = -1;
                    let bottom = -1;
                    for (let offset = 3, pixel = 0;
                        offset < data.length;
                        offset += 4, pixel++) {
                        const alpha = data[offset];
                        alphaSum += alpha;
                        if (alpha === 0) continue;
                        nonZeroAlphaPixels++;
                        if (alpha === 255) opaqueAlphaPixels++;
                        else partialAlphaPixels++;
                        const x = pixel % input.width;
                        const y = Math.floor(pixel / input.width);
                        left = Math.min(left, x);
                        top = Math.min(top, y);
                        right = Math.max(right, x);
                        bottom = Math.max(bottom, y);
                    }
                    return {
                        nonZeroAlphaPixels,
                        partialAlphaPixels,
                        opaqueAlphaPixels,
                        alphaSum,
                        coverageFraction:
                            nonZeroAlphaPixels /
                            (input.width * input.height),
                        bounds:right < 0 ? null : {
                            left,
                            top,
                            rightInclusive:right,
                            bottomInclusive:bottom,
                            width:right - left + 1,
                            height:bottom - top + 1
                        }
                    };
                })(),
                webSvg: (() => {
                    const data = webPixels.data;
                    let nonZeroAlphaPixels = 0;
                    let partialAlphaPixels = 0;
                    let opaqueAlphaPixels = 0;
                    let alphaSum = 0;
                    let left = input.width;
                    let top = input.height;
                    let right = -1;
                    let bottom = -1;
                    for (let offset = 3, pixel = 0;
                        offset < data.length;
                        offset += 4, pixel++) {
                        const alpha = data[offset];
                        alphaSum += alpha;
                        if (alpha === 0) continue;
                        nonZeroAlphaPixels++;
                        if (alpha === 255) opaqueAlphaPixels++;
                        else partialAlphaPixels++;
                        const x = pixel % input.width;
                        const y = Math.floor(pixel / input.width);
                        left = Math.min(left, x);
                        top = Math.min(top, y);
                        right = Math.max(right, x);
                        bottom = Math.max(bottom, y);
                    }
                    return {
                        nonZeroAlphaPixels,
                        partialAlphaPixels,
                        opaqueAlphaPixels,
                        alphaSum,
                        coverageFraction:
                            nonZeroAlphaPixels /
                            (input.width * input.height),
                        bounds:right < 0 ? null : {
                            left,
                            top,
                            rightInclusive:right,
                            bottomInclusive:bottom,
                            width:right - left + 1,
                            height:bottom - top + 1
                        }
                    };
                })()
            },
            pixelDifferenceRgba8: {
                totalPixels,
                totalChannels,
                changedPixelCount,
                changedPixelFraction: changedPixelCount / totalPixels,
                changedPixelBounds: changedRight < 0 ? null : {
                    left:changedLeft,
                    top:changedTop,
                    rightInclusive:changedRight,
                    bottomInclusive:changedBottom,
                    width:changedRight - changedLeft + 1,
                    height:changedBottom - changedTop + 1
                },
                changedChannelCount,
                sumAbsoluteError,
                sumSquaredError,
                meanAbsoluteErrorRgba8:
                    sumAbsoluteError / totalChannels,
                rootMeanSquaredErrorRgba8:
                    Math.sqrt(sumSquaredError / totalChannels),
                maxAbsoluteChannelError,
                perChannel
            }
        };
    }, payload);
}

function aggregateMetrics(cases) {
    const aggregate = {
        caseCount:cases.length,
        totalPixels:0,
        totalChannels:0,
        changedPixelCount:0,
        changedChannelCount:0,
        sumAbsoluteError:0,
        sumSquaredError:0,
        meanAbsoluteErrorRgba8:0,
        rootMeanSquaredErrorRgba8:0,
        maxAbsoluteChannelError:0
    };
    for (const item of cases) {
        const metric = item.pixelDifferenceRgba8;
        aggregate.totalPixels += metric.totalPixels;
        aggregate.totalChannels += metric.totalChannels;
        aggregate.changedPixelCount += metric.changedPixelCount;
        aggregate.changedChannelCount += metric.changedChannelCount;
        aggregate.sumAbsoluteError += metric.sumAbsoluteError;
        aggregate.sumSquaredError += metric.sumSquaredError;
        aggregate.maxAbsoluteChannelError = Math.max(
            aggregate.maxAbsoluteChannelError,
            metric.maxAbsoluteChannelError);
    }
    aggregate.changedPixelFraction =
        aggregate.changedPixelCount / aggregate.totalPixels;
    aggregate.meanAbsoluteErrorRgba8 =
        aggregate.sumAbsoluteError / aggregate.totalChannels;
    aggregate.rootMeanSquaredErrorRgba8 = Math.sqrt(
        aggregate.sumSquaredError / aggregate.totalChannels);
    return aggregate;
}

async function main() {
    if (!fs.existsSync(playwrightRoot)) {
        fail(
            'Missing launcher/perf Playwright. Run ' +
            '"npm --prefix launcher/perf ci --ignore-scripts".');
    }
    const options = parseOptions();
    const flashReportPath = resolveInsideRepo(options.flash, 'flash');
    const webReportPath = resolveInsideRepo(options.web, 'web');
    const outputRoot = resolveInsideRepo(options.output, 'output');
    if (fs.existsSync(outputRoot)) {
        fail('Output directory already exists; use a fresh path.');
    }
    const outputParent = path.dirname(outputRoot);
    if (!fs.existsSync(outputParent) ||
        !fs.statSync(outputParent).isDirectory()) {
        fail('Output parent directory must already exist.');
    }

    const tracker = newInputTracker();
    const comparisonTool = tracker.read(
        __filename, 'Flash/Web comparison tool').identity;
    const flashInput = readTrackedJson(
        tracker, flashReportPath, 'Flash candidate manifest');
    const webInput = readTrackedJson(
        tracker, webReportPath, 'Web canonical render report');
    const flashValidated = validateFlashManifest(
        flashInput.value, path.dirname(flashReportPath), tracker);
    const webValidated = validateWebReport(
        webInput.value, path.dirname(webReportPath), tracker);
    for (let index = 0; index < expectedCases.length; index++) {
        const flashCase = flashValidated.cases[index];
        const webCase = webValidated.cases[index];
        if (flashCase.id !== webCase.id ||
            flashCase.hpFrame !== webCase.hpFrame ||
            flashCase.mpFrame !== webCase.mpFrame) {
            fail(`Cross-input case/frame mismatch at index ${index}.`);
        }
    }

    const edge = edgePath();
    if (!edge) {
        fail('Microsoft Edge executable was not found.');
    }
    const playwrightPackagePath = path.join(
        playwrightRoot, 'package.json');
    const playwrightPackage = readTrackedJson(
        tracker, playwrightPackagePath, 'Playwright package');
    const playwrightIdentity = {
        path: repoRelative(playwrightPackagePath),
        version: playwrightPackage.value.version,
        bytes: playwrightPackage.bytes.length,
        sha256: playwrightPackage.sha256
    };

    fs.mkdirSync(outputRoot, {recursive:false});
    const chromium = require(playwrightRoot).chromium;
    const browser = await chromium.launch({
        executablePath:edge,
        headless:true
    });
    const results = [];
    let comparisonBrowser;
    try {
        comparisonBrowser = normalizedBrowserIdentity(
            edge, browser.version(), tracker);
        assertBrowserMatches(comparisonBrowser, webInput.value.browser);
        const page = await browser.newPage({
            viewport,
            deviceScaleFactor:1,
            colorScheme:'dark',
            reducedMotion:'reduce'
        });
        const pageErrors = [];
        page.on('pageerror', error => pageErrors.push(error.message));
        await page.setContent(
            '<!doctype html><meta charset="utf-8">' +
            '<title>PlayerInfo Flash candidate/Web SVG diagnostic</title>',
            {waitUntil:'load'});
        for (let index = 0; index < expectedCases.length; index++) {
            pageErrors.length = 0;
            const expected = expectedCases[index];
            const flashCase = flashValidated.cases[index];
            const webCase = webValidated.cases[index];
            const compared = await compareCase(page, flashCase, webCase);
            if (pageErrors.length) {
                fail(`${expected.id} page error: ${pageErrors.join(' | ')}`);
            }
            const overlayBytes = decodeDataUrl(
                compared.overlayPng, `${expected.id} 50/50 overlay`);
            const differenceBytes = decodeDataUrl(
                compared.absoluteDiffPng, `${expected.id} absolute diff`);
            const sideBySideBytes = decodeDataUrl(
                compared.sideBySidePng, `${expected.id} side-by-side`);
            results.push({
                caseId:expected.id,
                hpVirtualFrame:expected.hpFrame,
                mpVirtualFrame:expected.mpFrame,
                flashCandidateRaw: {
                    path:repoRelative(flashCase.path),
                    bytes:flashCase.identity.bytes,
                    sha256:flashCase.identity.sha256,
                    rawArgbSha256:flashCase.rawArgbSha256
                },
                webCanonical: {
                    path:repoRelative(webCase.path),
                    bytes:webCase.identity.bytes,
                    sha256:webCase.identity.sha256
                },
                overlay50_50:writePng(
                    outputRoot,
                    `overlay-50-50/${expected.id}.png`,
                    overlayBytes,
                    viewport.width,
                    viewport.height),
                absoluteDiff:writePng(
                    outputRoot,
                    `absolute-diff/${expected.id}.png`,
                    differenceBytes,
                    viewport.width,
                    viewport.height),
                sideBySideFlashThenWeb:writePng(
                    outputRoot,
                    `side-by-side/${expected.id}.png`,
                    sideBySideBytes,
                    viewport.width * 2,
                    viewport.height),
                alpha:compared.alpha,
                pixelDifferenceRgba8:compared.pixelDifferenceRgba8
            });
        }
    } finally {
        await browser.close();
    }

    tracker.verify();
    const browserAfter = normalizedBrowserIdentity(
        edge, comparisonBrowser.version, tracker);
    assertBrowserMatches(browserAfter, comparisonBrowser);
    tracker.verify();

    const report = {
        schema:'cf7.player_info.flash_candidate_web_svg_diagnostic.v1',
        status:'diagnostic_visual_review_package_awaiting_human_review',
        scope:'11_case_flash_player_candidate_raw_vs_canonical_web_svg',
        claims: {
            flashInputStatus:'candidate',
            webCapturedLayerScope:
                webValidated.renderSemantics.capturedLayerScope,
            webCaptureIncludesCsharpProgrammaticDynamicText:
                webValidated.renderSemantics
                    .csharpProgrammaticDynamicTextIncluded,
            webCaptureIncludesCsharpProgrammaticGlow:
                webValidated.renderSemantics
                    .csharpProgrammaticGlowIncluded,
            flashCandidateHumanReviewRequired:true,
            oracleFrozenClaimed:false,
            closesOracleFrozenGate:false,
            rendererParityClaimed:false,
            passThresholdApplied:false,
            metricsOnly:true,
            humanReviewRequired:true,
            limitation:
                'The Flash input is an unaccepted candidate. The Web image ' +
                'contains the current static canonical SVG layers, while the ' +
                'Flash image also contains runtime text/effects. Pixel ' +
                'differences are review aids, not an acceptance verdict.'
        },
        inputs: {
            identityStableBeforeAndAfter:true,
            flashCandidateManifest: {
                path:repoRelative(flashReportPath),
                bytes:flashInput.bytes.length,
                sha256:flashInput.sha256,
                schema:flashInput.value.schema,
                status:flashInput.value.status,
                runId:flashValidated.runId,
                capturedUtc:flashValidated.capturedUtc,
                requiresHumanReview:true,
                humanReviewStatus:'required',
                sourceUiSwfSha256:
                    flashValidated.sourceUiSwfSha256,
                loaderSwfSha256:
                    flashValidated.loaderSwfSha256,
                player:flashValidated.player,
                rawArtifactCount:flashValidated.cases.length
            },
            webReport: {
                path:repoRelative(webReportPath),
                bytes:webInput.bytes.length,
                sha256:webInput.sha256,
                schema:webInput.value.schema,
                status:webInput.value.status,
                manifest:webValidated.manifestIdentity,
                assets:webValidated.assets,
                renderSemantics:webValidated.renderSemantics,
                renderArtifactCount:webValidated.cases.length
            },
            caseIdsAndFramesMatch:true,
            comparisonBrowserMatchesWebRenderBrowser:true
        },
        execution: {
            viewport:[viewport.width, viewport.height],
            deviceScaleFactor:1,
            background:'transparent',
            comparisonTool,
            browser:comparisonBrowser,
            playwright:playwrightIdentity,
            decoding:
                'Both exact PNG inputs are decoded by the recorded Edge ' +
                'Canvas2D implementation into straight-alpha RGBA8.',
            sideBySideOrder:['flash-candidate', 'web-canonical-svg']
        },
        metricDefinition: {
            basis:
                'Decoded straight-alpha RGBA8, 1024x64, four channels per pixel.',
            changedPixel:
                'Any RGBA channel has a non-zero absolute difference.',
            alphaCoverage:
                'Pixels with alpha > 0; bounds are inclusive integer pixel bounds.',
            overlay50_50:
                'Equal-weight average in premultiplied-alpha space, then ' +
                'unpremultiplied.',
            absoluteDiff:
                'Opaque RGB; each output color channel is the maximum of ' +
                'that color-channel difference and alpha-channel difference.',
            sideBySide:
                '2048x64 transparent canvas: exact Flash candidate PNG on ' +
                'the left and exact Web canonical PNG on the right.',
            threshold:null
        },
        aggregate:aggregateMetrics(results),
        cases:results
    };
    const reportPath = path.join(
        outputRoot, 'flash-web-comparison-report.json');
    fs.writeFileSync(
        reportPath, JSON.stringify(report, null, 2) + '\n', {flag:'wx'});
    tracker.verify();
    process.stdout.write(
        `PlayerInfo Flash-candidate/Web diagnostic ${results.length}/` +
        `${expectedCases.length}; human review required; no threshold, ` +
        `oracle-frozen, or renderer-parity claim; ` +
        `report=${repoRelative(reportPath)}\n`);
}

main().catch(error => {
    process.stderr.write(`${error && error.stack ? error.stack : error}\n`);
    process.exitCode = 1;
});
