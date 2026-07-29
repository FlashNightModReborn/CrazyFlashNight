#!/usr/bin/env node
'use strict';

const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

const repoRoot = path.resolve(__dirname, '..', '..');
const playwrightRoot = path.join(
    repoRoot, 'launcher', 'perf', 'node_modules', 'playwright');
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
const viewport = {width:1024, height:64};
const frozenSwfSha256 =
    '450b1f9a8b445ee3e28c63682ea00124a191f56d05d759b8590210fc0066a615';

function fail(message) {
    throw new Error(message);
}

function option(name) {
    const prefix = `--${name}=`;
    const matches = process.argv.slice(2)
        .filter(argument => argument.startsWith(prefix));
    if (matches.length !== 1 || matches[0].length === prefix.length) {
        fail(`Expected exactly one --${name}=<repo-relative-path>.`);
    }
    return matches[0].slice(prefix.length);
}

function resolveBelow(base, relativeValue, label) {
    if (path.isAbsolute(relativeValue)) {
        fail(`${label} must be relative.`);
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

function assertSha(value, label) {
    if (typeof value !== 'string' || !/^[0-9a-f]{64}$/u.test(value)) {
        fail(`${label} is not a lowercase SHA-256.`);
    }
}

function identity(filePath) {
    const bytes = fs.readFileSync(filePath);
    return {
        path: repoRelative(filePath),
        bytes: bytes.length,
        sha256: sha256(bytes)
    };
}

function assertIdentity(filePath, expected, label) {
    if (!expected || !Number.isSafeInteger(expected.sizeBytes) ||
        expected.sizeBytes < 0) {
        fail(`${label} has no valid sizeBytes identity.`);
    }
    assertSha(expected.sha256, `${label}.sha256`);
    const actual = identity(filePath);
    if (actual.bytes !== expected.sizeBytes ||
        actual.sha256 !== expected.sha256) {
        fail(`${label} identity changed.`);
    }
    return actual;
}

function readVerifiedArtifact(root, record, label) {
    if (!record || typeof record.path !== 'string') {
        fail(`${label} has no artifact path.`);
    }
    assertSha(record.sha256, `${label}.sha256`);
    const artifactPath = resolveBelow(root, record.path, `${label}.path`);
    const actual = identity(artifactPath);
    if (actual.sha256 !== record.sha256) {
        fail(`${label} SHA-256 mismatch.`);
    }
    return {path:artifactPath, identity:actual, bytes:fs.readFileSync(artifactPath)};
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

function finiteNumber(value, label) {
    if (!Number.isFinite(value)) {
        fail(`${label} must be finite.`);
    }
    return value;
}

function near(left, right) {
    return Math.abs(left - right) <= 1e-9;
}

function componentContract(ffdec, component) {
    const topology = ffdec.topology && ffdec.topology[component];
    const canvas = ffdec.componentCanvasContract &&
        ffdec.componentCanvasContract[component];
    if (!topology || !canvas) {
        fail(`FFDec report lacks the ${component} compositor contract.`);
    }
    const matrix = topology.stageMatrixPx;
    if (!Array.isArray(matrix) || matrix.length !== 6) {
        fail(`${component}.stageMatrixPx must have six numbers.`);
    }
    matrix.forEach((value, index) =>
        finiteNumber(value, `${component}.stageMatrixPx[${index}]`));
    const logical = canvas.logicalCanvasPx;
    const encoded = canvas.encodedPngPixels;
    const origin = canvas.localOriginPx;
    const reportedTopLeft = canvas.stageTopLeftPx;
    const reportedDrawSize = canvas.stageDrawSizePx;
    for (const [name, object, keys] of [
        ['logicalCanvasPx', logical, ['width', 'height']],
        ['encodedPngPixels', encoded, ['width', 'height']],
        ['localOriginPx', origin, ['x', 'y']],
        ['stageTopLeftPx', reportedTopLeft, ['x', 'y']],
        ['stageDrawSizePx', reportedDrawSize, ['width', 'height']]
    ]) {
        if (!object) {
            fail(`${component}.${name} is missing.`);
        }
        keys.forEach(key =>
            finiteNumber(object[key], `${component}.${name}.${key}`));
    }
    if (!Number.isInteger(encoded.width) || !Number.isInteger(encoded.height) ||
        encoded.width <= 0 || encoded.height <= 0 ||
        logical.width <= 0 || logical.height <= 0) {
        fail(`${component} canvas dimensions are invalid.`);
    }
    const [a, b, c, d, e, f] = matrix;
    if (a <= 0 || d <= 0 || b !== 0 || c !== 0) {
        fail(
            `${component} stage matrix must retain its positive, ` +
            'axis-aligned scale contract.');
    }
    const expectedTopLeft = {
        x: e - a * origin.x - c * origin.y,
        y: f - b * origin.x - d * origin.y
    };
    const expectedDrawSize = {
        width: a * logical.width,
        height: d * logical.height
    };
    if (!near(reportedTopLeft.x, expectedTopLeft.x) ||
        !near(reportedTopLeft.y, expectedTopLeft.y) ||
        !near(reportedDrawSize.width, expectedDrawSize.width) ||
        !near(reportedDrawSize.height, expectedDrawSize.height)) {
        fail(`${component} redundant stage compositor values disagree.`);
    }
    return {
        matrix: matrix.slice(),
        logicalCanvasPx: {
            width: logical.width,
            height: logical.height
        },
        encodedPngPixels: {
            width: encoded.width,
            height: encoded.height
        },
        localOriginPx: {
            x: origin.x,
            y: origin.y
        },
        stageTopLeftPx: expectedTopLeft,
        stageDrawSizePx: expectedDrawSize
    };
}

function validateFfdecReport(ffdec, reportRoot) {
    if (ffdec.schemaVersion !== 'player-info-hud-ffdec-reference/v1' ||
        ffdec.status !== 'ffdec_binary_reference_frozen') {
        fail('Unsupported FFDec reference report schema/status.');
    }
    if (!ffdec.oracleBoundary ||
        ffdec.oracleBoundary.flashPlayerRuntimeOracleEquivalent !== false ||
        ffdec.oracleBoundary.closesOracleFrozenGate !== false) {
        fail('FFDec report lost its explicit non-oracle boundary.');
    }
    if (!ffdec.source || !ffdec.source.swf ||
        ffdec.source.swf.sha256 !== frozenSwfSha256) {
        fail('FFDec report is not bound to the frozen player-info SWF.');
    }
    const swfPath = resolveInsideRepo(
        ffdec.source.swf.path, 'FFDec source SWF path');
    const swfIdentity = assertIdentity(
        swfPath, ffdec.source.swf, 'FFDec source SWF');
    if (ffdec.source.ffdecVersion !== '21.1.1' ||
        !Array.isArray(ffdec.source.ffdecClosure) ||
        ffdec.source.ffdecClosure.length === 0) {
        fail('FFDec runtime closure identity is incomplete.');
    }
    const closure = ffdec.source.ffdecClosure.map((record, index) => {
        const filePath = resolveInsideRepo(
            record.path, `FFDec closure[${index}].path`);
        return assertIdentity(
            filePath, record, `FFDec closure[${index}]`);
    });
    if (!ffdec.source.javaRuntime ||
        !Number.isSafeInteger(ffdec.source.javaRuntime.sizeBytes) ||
        ffdec.source.javaRuntime.sizeBytes <= 0) {
        fail('FFDec Java runtime identity is incomplete.');
    }
    assertSha(
        ffdec.source.javaRuntime.sha256,
        'FFDec Java runtime recorded SHA-256');
    if (!ffdec.source.swf2xml || ffdec.source.swf2xml.retained !== false) {
        fail('FFDec swf2xml identity/retention contract is missing.');
    }
    assertSha(ffdec.source.swf2xml.sha256, 'FFDec swf2xml.sha256');
    if (!ffdec.topology || ffdec.topology.linkage.characterId !== 454 ||
        ffdec.topology.hp.characterId !== 380 ||
        ffdec.topology.mp.characterId !== 119) {
        fail('FFDec root/HP/MP topology identity changed.');
    }
    const hpContract = componentContract(ffdec, 'hp');
    const mpContract = componentContract(ffdec, 'mp');
    if (!Array.isArray(ffdec.selectedCases) ||
        ffdec.selectedCases.length !== expectedCases.length ||
        !Array.isArray(ffdec.artifacts)) {
        fail('FFDec selected corpus is not the expected 11 cases.');
    }
    const artifactByPath = new Map();
    for (const artifact of ffdec.artifacts) {
        if (!artifact || typeof artifact.path !== 'string' ||
            artifactByPath.has(artifact.path)) {
            fail('FFDec artifact paths must be unique.');
        }
        artifactByPath.set(artifact.path, artifact);
    }
    const cases = expectedCases.map((expected, index) => {
        const actual = ffdec.selectedCases[index];
        if (!actual || actual.id !== expected.id ||
            !actual.hp || actual.hp.frame !== expected.hpFrame ||
            !actual.mp || actual.mp.frame !== expected.mpFrame) {
            fail(`FFDec case mapping drifted at ${expected.id}.`);
        }
        const result = {id:expected.id};
        for (const component of ['hp', 'mp']) {
            const selected = actual[component];
            const artifact = artifactByPath.get(selected.artifact);
            const contract = component === 'hp' ? hpContract : mpContract;
            if (!artifact || artifact.component !== component ||
                artifact.frame !== selected.frame ||
                artifact.sha256 !== selected.sha256 ||
                artifact.encodedWidthPx !==
                    contract.encodedPngPixels.width ||
                artifact.encodedHeightPx !==
                    contract.encodedPngPixels.height) {
                fail(`${expected.id}/${component} artifact record disagrees.`);
            }
            const verified = readVerifiedArtifact(
                reportRoot, artifact, `FFDec ${expected.id}/${component}`);
            assertPngSize(
                verified.bytes,
                contract.encodedPngPixels.width,
                contract.encodedPngPixels.height,
                `FFDec ${expected.id}/${component}`);
            result[component] = {
                frame: selected.frame,
                path: verified.path,
                identity: verified.identity,
                bytes: verified.bytes,
                contract
            };
        }
        return result;
    });
    return {
        swfIdentity,
        closure,
        hpContract,
        mpContract,
        cases
    };
}

function validateWebReport(web, reportRoot) {
    if (web.schema !== 'cf7.player_info.web_svg_harness.v1' ||
        web.status !==
            'canonical_manifest_rendered_awaiting_human_review' ||
        !Array.isArray(web.viewport) ||
        web.viewport[0] !== viewport.width ||
        web.viewport[1] !== viewport.height ||
        web.deviceScaleFactor !== 1 ||
        web.background !== 'transparent') {
        fail('Unsupported Web render report contract.');
    }
    if (!web.manifest ||
        web.manifest.schemaVersion !== 1 ||
        typeof web.manifest.assetSetRevision !== 'string' ||
        !/^sha256:[0-9a-f]{64}$/u.test(
            web.manifest.assetSetRevision)) {
        fail('Web render report has no canonical manifest identity.');
    }
    if (!web.browser ||
        web.browser.family !== 'Microsoft Edge via Playwright chromium') {
        fail('Web report browser family is not Microsoft Edge/Playwright.');
    }
    assertSha(web.browser.executableSha256, 'Web browser SHA-256');
    if (!Number.isSafeInteger(web.browser.executableBytes) ||
        web.browser.executableBytes <= 0 ||
        typeof web.browser.version !== 'string' ||
        !web.browser.version) {
        fail('Web report browser identity is incomplete.');
    }
    const manifestPath = resolveInsideRepo(
        web.manifest.path, 'Web manifest path');
    const manifestInput = readJson(manifestPath, 'Web manifest');
    assertSha(web.manifest.sha256, 'Web manifest SHA-256');
    if (manifestInput.sha256 !== web.manifest.sha256) {
        fail('Web manifest file identity changed.');
    }
    const manifest = manifestInput.value;
    if (manifest.format !== 'cf7.player-info-hud.asset-manifest' ||
        manifest.schemaVersion !== web.manifest.schemaVersion ||
        !manifest.assetSet ||
        manifest.assetSet.revision !==
            web.manifest.assetSetRevision) {
        fail('Web canonical manifest contract changed.');
    }
    if (!manifest.stage ||
        JSON.stringify(manifest.stage.compositeOrder) !==
            JSON.stringify(['mp', 'hp']) ||
        !web.renderSemantics ||
        JSON.stringify(Object.keys(web.renderSemantics).sort()) !==
            JSON.stringify(webRenderSemanticsKeys) ||
        web.renderSemantics.capturedLayerScope !==
            canonicalStaticLayerScope ||
        web.renderSemantics.csharpProgrammaticDynamicTextIncluded !== false ||
        web.renderSemantics.csharpProgrammaticGlowIncluded !== false ||
        JSON.stringify(web.renderSemantics.compositeOrder) !==
            JSON.stringify(manifest.stage.compositeOrder) ||
        web.renderSemantics.hpFillDegreesPerSourceFrame !== 2.8125 ||
        JSON.stringify(web.renderSemantics.mpRimVariantStarts) !==
            JSON.stringify([1, 70, 91])) {
        fail('Web render semantics drifted from the canonical contract.');
    }
    if (!Array.isArray(manifest.assets) || !Array.isArray(web.assets) ||
        manifest.assets.length !== web.assets.length ||
        manifest.assets.length !== 8) {
        fail('Web canonical eight-asset closure is incomplete.');
    }
    const manifestRoot = path.dirname(manifestPath);
    const revisionHash = crypto.createHash('sha256');
    const assets = web.assets.map((record, index) => {
        const source = manifest.assets[index];
        if (!source || source.id !== record.id ||
            source.path !== record.path || source.sha256 !== record.sha256) {
            fail(`Web asset[${index}] disagrees with its manifest.`);
        }
        const assetPath = resolveBelow(
            manifestRoot, record.path, `Web asset[${index}].path`);
        const actual = identity(assetPath);
        assertSha(record.sha256, `Web asset[${index}].sha256`);
        if (actual.bytes !== record.bytes ||
            actual.sha256 !== record.sha256) {
            fail(`Web asset[${index}] identity changed.`);
        }
        return {...actual, relativePath:record.path};
    });
    for (const asset of [...assets].sort(
        (left, right) => Buffer.from(left.relativePath).compare(
            Buffer.from(right.relativePath)))) {
        revisionHash.update(Buffer.from(asset.relativePath, 'utf8'));
        revisionHash.update(Buffer.from([0]));
        revisionHash.update(fs.readFileSync(
            resolveBelow(
                manifestRoot, asset.relativePath,
                `Web revision asset ${asset.relativePath}`)));
        revisionHash.update(Buffer.from([0]));
    }
    const actualRevision = `sha256:${revisionHash.digest('hex')}`;
    if (actualRevision !== manifest.assetSet.revision) {
        fail('Web canonical asset-set revision no longer binds its bytes.');
    }
    if (!Array.isArray(web.cases) ||
        web.cases.length !== expectedCases.length) {
        fail('Web corpus is not the expected 11 cases.');
    }
    const cases = expectedCases.map((expected, index) => {
        const actual = web.cases[index];
        if (!actual || actual.caseId !== expected.id ||
            actual.hpVirtualFrame !== expected.hpFrame ||
            actual.mpVirtualFrame !== expected.mpFrame) {
            fail(`Web case mapping drifted at ${expected.id}.`);
        }
        const verified = readVerifiedArtifact(
            reportRoot, actual, `Web ${expected.id}`);
        if (verified.identity.bytes !== actual.bytes) {
            fail(`Web ${expected.id} encoded length changed.`);
        }
        assertPngSize(
            verified.bytes, viewport.width, viewport.height,
            `Web ${expected.id}`);
        return {
            id: expected.id,
            hpFrame: expected.hpFrame,
            mpFrame: expected.mpFrame,
            path: verified.path,
            identity: verified.identity,
            bytes: verified.bytes
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
        assets,
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

function writeArtifact(outputRoot, relativePath, bytes) {
    const outputPath = resolveBelow(
        outputRoot, relativePath, `output ${relativePath}`);
    fs.mkdirSync(path.dirname(outputPath), {recursive:true});
    fs.writeFileSync(outputPath, bytes);
    assertPngSize(bytes, viewport.width, viewport.height, relativePath);
    return {
        path: relativePath.replace(/\\/g, '/'),
        bytes: bytes.length,
        sha256: sha256(bytes)
    };
}

function normalizedBrowserIdentity(edge, version) {
    const executable = identity(edge);
    return {
        family: 'Microsoft Edge via Playwright chromium',
        version,
        executableSha256: executable.sha256,
        executableBytes: executable.bytes
    };
}

function assertBrowserMatches(actual, expected) {
    if (actual.family !== expected.family ||
        actual.version !== expected.version ||
        actual.executableSha256 !== expected.executableSha256 ||
        actual.executableBytes !== expected.executableBytes) {
        fail('Current comparison browser identity differs from Web rendering.');
    }
}

function aggregateMetrics(cases) {
    const aggregate = {
        caseCount: cases.length,
        totalPixels: 0,
        totalChannels: 0,
        changedPixelCount: 0,
        changedChannelCount: 0,
        sumAbsoluteError: 0,
        sumSquaredError: 0,
        meanAbsoluteErrorRgba8: 0,
        rootMeanSquaredErrorRgba8: 0,
        maxAbsoluteChannelError: 0
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
    aggregate.meanAbsoluteErrorRgba8 =
        aggregate.sumAbsoluteError / aggregate.totalChannels;
    aggregate.rootMeanSquaredErrorRgba8 = Math.sqrt(
        aggregate.sumSquaredError / aggregate.totalChannels);
    return aggregate;
}

async function renderCase(page, ffdecCase, webCase) {
    const payload = {
        width: viewport.width,
        height: viewport.height,
        components: [
            {
                id: 'mp',
                image: dataUrl(ffdecCase.mp.bytes),
                matrix: ffdecCase.mp.contract.matrix,
                logicalCanvasPx:
                    ffdecCase.mp.contract.logicalCanvasPx,
                localOriginPx:
                    ffdecCase.mp.contract.localOriginPx
            },
            {
                id: 'hp',
                image: dataUrl(ffdecCase.hp.bytes),
                matrix: ffdecCase.hp.contract.matrix,
                logicalCanvasPx:
                    ffdecCase.hp.contract.logicalCanvasPx,
                localOriginPx:
                    ffdecCase.hp.contract.localOriginPx
            }
        ],
        webImage: dataUrl(webCase.bytes)
    };
    return page.evaluate(async input => {
        const loadImage = source => new Promise((resolve, reject) => {
            const image = new Image();
            image.onload = () => resolve(image);
            image.onerror = () => reject(new Error('PNG decode failed.'));
            image.src = source;
        });
        const canvas = () => {
            const result = document.createElement('canvas');
            result.width = input.width;
            result.height = input.height;
            return result;
        };
        const oldCanvas = canvas();
        const oldContext = oldCanvas.getContext(
            '2d', {alpha:true, willReadFrequently:true});
        oldContext.imageSmoothingEnabled = true;
        oldContext.imageSmoothingQuality = 'low';
        for (const component of input.components) {
            const image = await loadImage(component.image);
            const [a, b, c, d, e, f] = component.matrix;
            oldContext.setTransform(a, b, c, d, e, f);
            oldContext.drawImage(
                image,
                -component.localOriginPx.x,
                -component.localOriginPx.y,
                component.logicalCanvasPx.width,
                component.logicalCanvasPx.height);
        }
        oldContext.resetTransform();

        const webCanvas = canvas();
        const webContext = webCanvas.getContext(
            '2d', {alpha:true, willReadFrequently:true});
        const webImage = await loadImage(input.webImage);
        if (webImage.naturalWidth !== input.width ||
            webImage.naturalHeight !== input.height) {
            throw new Error('Web image decoded at an unexpected size.');
        }
        webContext.drawImage(webImage, 0, 0);

        const oldPixels = oldContext.getImageData(
            0, 0, input.width, input.height);
        const webPixels = webContext.getImageData(
            0, 0, input.width, input.height);
        const overlayPixels = new ImageData(input.width, input.height);
        const heatmapPixels = new ImageData(input.width, input.height);

        const alphaProfile = pixels => {
            let nonZeroAlphaPixels = 0;
            let partialAlphaPixels = 0;
            let opaqueAlphaPixels = 0;
            let alphaSum = 0;
            let left = input.width;
            let top = input.height;
            let right = -1;
            let bottom = -1;
            for (let offset = 3, pixel = 0;
                offset < pixels.data.length;
                offset += 4, pixel++) {
                const alpha = pixels.data[offset];
                alphaSum += alpha;
                if (alpha === 0) {
                    continue;
                }
                nonZeroAlphaPixels++;
                if (alpha === 255) {
                    opaqueAlphaPixels++;
                } else {
                    partialAlphaPixels++;
                }
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
                    nonZeroAlphaPixels / (input.width * input.height),
                bounds: right < 0 ? null : {
                    left,
                    top,
                    rightInclusive: right,
                    bottomInclusive: bottom,
                    width: right - left + 1,
                    height: bottom - top + 1
                }
            };
        };

        let changedPixelCount = 0;
        let changedChannelCount = 0;
        let sumAbsoluteError = 0;
        let sumSquaredError = 0;
        let maxAbsoluteChannelError = 0;
        for (let offset = 0; offset < oldPixels.data.length; offset += 4) {
            let pixelChanged = false;
            let pixelMaximum = 0;
            for (let channel = 0; channel < 4; channel++) {
                const difference = Math.abs(
                    oldPixels.data[offset + channel] -
                    webPixels.data[offset + channel]);
                sumAbsoluteError += difference;
                sumSquaredError += difference * difference;
                pixelMaximum = Math.max(pixelMaximum, difference);
                maxAbsoluteChannelError = Math.max(
                    maxAbsoluteChannelError, difference);
                if (difference !== 0) {
                    changedChannelCount++;
                    pixelChanged = true;
                }
            }
            if (pixelChanged) {
                changedPixelCount++;
            }

            const oldAlpha = oldPixels.data[offset + 3] / 255;
            const webAlpha = webPixels.data[offset + 3] / 255;
            const overlayAlpha = (oldAlpha + webAlpha) / 2;
            for (let channel = 0; channel < 3; channel++) {
                const premultiplied =
                    (oldPixels.data[offset + channel] * oldAlpha +
                     webPixels.data[offset + channel] * webAlpha) / 2;
                overlayPixels.data[offset + channel] =
                    overlayAlpha === 0
                        ? 0
                        : Math.round(premultiplied / overlayAlpha);
            }
            overlayPixels.data[offset + 3] =
                Math.round(overlayAlpha * 255);

            const alphaDifference = Math.abs(
                oldPixels.data[offset + 3] -
                webPixels.data[offset + 3]);
            for (let channel = 0; channel < 3; channel++) {
                const colorDifference = Math.abs(
                    oldPixels.data[offset + channel] -
                    webPixels.data[offset + channel]);
                heatmapPixels.data[offset + channel] =
                    Math.max(colorDifference, alphaDifference);
            }
            heatmapPixels.data[offset + 3] = 255;
        }

        const overlayCanvas = canvas();
        overlayCanvas.getContext('2d').putImageData(overlayPixels, 0, 0);
        const heatmapCanvas = canvas();
        heatmapCanvas.getContext('2d').putImageData(heatmapPixels, 0, 0);
        const totalPixels = input.width * input.height;
        const totalChannels = totalPixels * 4;
        return {
            ffdecCompositePng: oldCanvas.toDataURL('image/png'),
            overlayPng: overlayCanvas.toDataURL('image/png'),
            absoluteDiffHeatmapPng: heatmapCanvas.toDataURL('image/png'),
            alpha: {
                ffdecComposite: alphaProfile(oldPixels),
                webSvg: alphaProfile(webPixels)
            },
            pixelDifferenceRgba8: {
                totalPixels,
                totalChannels,
                changedPixelCount,
                changedChannelCount,
                sumAbsoluteError,
                sumSquaredError,
                meanAbsoluteErrorRgba8:
                    sumAbsoluteError / totalChannels,
                rootMeanSquaredErrorRgba8:
                    Math.sqrt(sumSquaredError / totalChannels),
                maxAbsoluteChannelError
            }
        };
    }, payload);
}

async function main() {
    if (!fs.existsSync(playwrightRoot)) {
        fail(
            'Missing launcher/perf Playwright. Run ' +
            '"npm --prefix launcher/perf ci --ignore-scripts".');
    }
    const ffdecReportPath = resolveInsideRepo(option('ffdec'), 'ffdec');
    const webReportPath = resolveInsideRepo(option('web'), 'web');
    const outputRoot = resolveInsideRepo(option('output'), 'output');
    if (fs.existsSync(outputRoot)) {
        fail('Output directory already exists; use a fresh path.');
    }

    const ffdecInput = readJson(ffdecReportPath, 'FFDec report');
    const webInput = readJson(webReportPath, 'Web report');
    const ffdecValidated = validateFfdecReport(
        ffdecInput.value, path.dirname(ffdecReportPath));
    const webValidated = validateWebReport(
        webInput.value, path.dirname(webReportPath));
    for (let index = 0; index < expectedCases.length; index++) {
        const ffdecCase = ffdecValidated.cases[index];
        const webCase = webValidated.cases[index];
        if (ffdecCase.id !== webCase.id ||
            ffdecCase.hp.frame !== webCase.hpFrame ||
            ffdecCase.mp.frame !== webCase.mpFrame) {
            fail(`Cross-report case/frame mismatch at index ${index}.`);
        }
    }

    const edge = edgePath();
    if (!edge) {
        fail('Microsoft Edge executable was not found.');
    }
    const playwrightPackagePath = path.join(
        playwrightRoot, 'package.json');
    const playwrightPackage = readJson(
        playwrightPackagePath, 'Playwright package');
    const playwrightIdentity = {
        path: repoRelative(playwrightPackagePath),
        version: playwrightPackage.value.version,
        bytes: playwrightPackage.bytes.length,
        sha256: playwrightPackage.sha256
    };
    fs.mkdirSync(outputRoot, {recursive:false});
    const chromium = require(playwrightRoot).chromium;
    const browser = await chromium.launch({
        executablePath: edge,
        headless: true
    });
    const results = [];
    let comparisonBrowser;
    try {
        comparisonBrowser = normalizedBrowserIdentity(
            edge, browser.version());
        assertBrowserMatches(comparisonBrowser, webInput.value.browser);
        const page = await browser.newPage({
            viewport,
            deviceScaleFactor: 1,
            colorScheme: 'dark',
            reducedMotion: 'reduce'
        });
        await page.setContent(
            '<!doctype html><meta charset="utf-8">' +
            '<title>PlayerInfo cross-renderer diagnostic</title>',
            {waitUntil:'load'});
        for (let index = 0; index < expectedCases.length; index++) {
            const expected = expectedCases[index];
            const ffdecCase = ffdecValidated.cases[index];
            const webCase = webValidated.cases[index];
            const rendered = await renderCase(page, ffdecCase, webCase);
            const ffdecCompositeBytes = decodeDataUrl(
                rendered.ffdecCompositePng,
                `${expected.id} FFDec composite`);
            const overlayBytes = decodeDataUrl(
                rendered.overlayPng,
                `${expected.id} overlay`);
            const heatmapBytes = decodeDataUrl(
                rendered.absoluteDiffHeatmapPng,
                `${expected.id} heatmap`);
            results.push({
                caseId: expected.id,
                hpVirtualFrame: expected.hpFrame,
                mpVirtualFrame: expected.mpFrame,
                ffdecComponents: {
                    hp: {
                        path: repoRelative(ffdecCase.hp.path),
                        sha256: ffdecCase.hp.identity.sha256
                    },
                    mp: {
                        path: repoRelative(ffdecCase.mp.path),
                        sha256: ffdecCase.mp.identity.sha256
                    }
                },
                webOriginal: {
                    path: repoRelative(webCase.path),
                    bytes: webCase.identity.bytes,
                    sha256: webCase.identity.sha256
                },
                ffdecComposite: writeArtifact(
                    outputRoot,
                    `ffdec-composite/${expected.id}.png`,
                    ffdecCompositeBytes),
                overlay50_50: writeArtifact(
                    outputRoot,
                    `overlay-50-50/${expected.id}.png`,
                    overlayBytes),
                absoluteDiffHeatmap: writeArtifact(
                    outputRoot,
                    `absolute-diff/${expected.id}.png`,
                    heatmapBytes),
                alpha: rendered.alpha,
                pixelDifferenceRgba8:
                    rendered.pixelDifferenceRgba8
            });
        }
    } finally {
        await browser.close();
    }

    const edgeAfter = normalizedBrowserIdentity(
        edge, comparisonBrowser.version);
    assertBrowserMatches(edgeAfter, comparisonBrowser);
    const ffdecAfter = fs.readFileSync(ffdecReportPath);
    const webAfter = fs.readFileSync(webReportPath);
    if (sha256(ffdecAfter) !== ffdecInput.sha256 ||
        sha256(webAfter) !== webInput.sha256) {
        fail('An input report changed during comparison.');
    }

    const report = {
        schema: 'cf7.player_info.ffdec_web_svg_comparison.v1',
        status: 'diagnostic_cross_renderer_comparison',
        scope: '11_case_ffdec_binary_reference_vs_canonical_web_svg',
        claims: {
            flashPlayerRuntimeOracleEquivalent: false,
            webCapturedLayerScope:
                webValidated.renderSemantics.capturedLayerScope,
            webCaptureIncludesCsharpProgrammaticDynamicText:
                webValidated.renderSemantics
                    .csharpProgrammaticDynamicTextIncluded,
            webCaptureIncludesCsharpProgrammaticGlow:
                webValidated.renderSemantics
                    .csharpProgrammaticGlowIncluded,
            closesOracleFrozenGate: false,
            rendererParityClaimed: false,
            passThresholdApplied: false,
            metricsOnly: true,
            humanReviewRequired: true,
            limitation:
                'FFDec does not execute Adobe Flash Player. Differences ' +
                'measure two renderer outputs and are not an acceptance verdict.'
        },
        inputs: {
            ffdecReport: {
                path: repoRelative(ffdecReportPath),
                bytes: ffdecInput.bytes.length,
                sha256: ffdecInput.sha256,
                schemaVersion: ffdecInput.value.schemaVersion,
                status: ffdecInput.value.status,
                referenceSetRevision:
                    ffdecInput.value.referenceSetRevision,
                sourceSwf: ffdecValidated.swfIdentity,
                ffdecClosure: ffdecValidated.closure
            },
            webReport: {
                path: repoRelative(webReportPath),
                bytes: webInput.bytes.length,
                sha256: webInput.sha256,
                schema: webInput.value.schema,
                status: webInput.value.status,
                manifest: webValidated.manifestIdentity,
                assetSetRevision:
                    webInput.value.manifest.assetSetRevision,
                assets: webValidated.assets,
                renderSemantics:webValidated.renderSemantics
            },
            caseIdsAndFramesMatch: true,
            browserIdentityMatch: true
        },
        execution: {
            viewport: [viewport.width, viewport.height],
            deviceScaleFactor: 1,
            background: 'transparent',
            browser: comparisonBrowser,
            playwright: playwrightIdentity,
            componentOrderBottomToTop: ['mp', 'hp'],
            frozenSwfComponentDepths: {
                mpCharacter119: 140,
                hpCharacter380: 164
            },
            componentMapping:
                'Each FFDec PNG is mapped to its report logical canvas, ' +
                'translated by the negative local origin, transformed by ' +
                'the report stage matrix, and cropped to 1024x64.',
            rasterResampling:
                'Edge Canvas2D image smoothing enabled, quality=low.'
        },
        metricDefinition: {
            basis:
                'Decoded straight-alpha RGBA8, 1024x64, four channels per pixel.',
            changedPixel:
                'Any of the four RGBA channels has a non-zero absolute difference.',
            alphaCoverage:
                'Pixels with alpha > 0; bounds are inclusive integer pixel bounds.',
            overlay50_50:
                'Equal-weight average in premultiplied-alpha space, then unpremultiplied.',
            absoluteDiffHeatmap:
                'Opaque RGB where each color channel is max(abs(color-channel ' +
                'difference), abs(alpha difference)); zero difference is black.',
            threshold: null
        },
        aggregate: aggregateMetrics(results),
        cases: results
    };
    const reportPath = path.join(
        outputRoot, 'ffdec-web-comparison-report.json');
    fs.writeFileSync(
        reportPath, JSON.stringify(report, null, 2) + '\n');
    process.stdout.write(
        `PlayerInfo FFDec/Web diagnostic ${results.length}/` +
        `${expectedCases.length}; no threshold or parity claim; ` +
        `report=${repoRelative(reportPath)}\n`);
}

main().catch(error => {
    process.stderr.write(`${error && error.stack ? error.stack : error}\n`);
    process.exitCode = 1;
});
