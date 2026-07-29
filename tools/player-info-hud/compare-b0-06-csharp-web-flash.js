#!/usr/bin/env node
'use strict';

const crypto = require('crypto');
const childProcess = require('child_process');
const fs = require('fs');
const path = require('path');

const repoRoot = path.resolve(__dirname, '..', '..');
const playwrightRoot = path.join(
    repoRoot, 'launcher', 'perf', 'node_modules', 'playwright');
const viewport = {width:1024, height:576};
const childAuthoringStage = {width:1024, height:64};
const darkBackground = {
    id:'fixed-diagnostic-dark-game-matte-v1',
    css:'#181c20',
    rgb8:[24, 28, 32]
};
const canonicalStaticLayerScope = 'canonical_static_svg_layers_only';
const comparisonScope =
    '11_case_direct_csharp_main_viewport_composite_to_web_canonical_' +
    'static_layers_and_csharp_to_flash';
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
const expectedCsharpSourcePaths = [
    'launcher/src/Guardian/Hud/PlayerInfo/PlayerInfoAnimationModel.cs',
    'launcher/src/Guardian/Hud/PlayerInfo/PlayerInfoFrameCompositor.cs',
    'launcher/src/Guardian/Hud/PlayerInfo/PlayerInfoPathGlyphAtlas.cs',
    'launcher/src/Guardian/Hud/PlayerInfo/PlayerInfoPathGlyphAtlas.Generated.cs',
    'launcher/src/Guardian/Hud/PlayerInfo/PlayerInfoRasterPipeline.cs',
    'launcher/src/Guardian/Hud/PlayerInfo/PlayerInfoRasterPlan.cs',
    'launcher/src/Guardian/Hud/PlayerInfo/PlayerInfoSplitSurface.cs',
    'launcher/src/Guardian/Hud/PlayerInfo/PlayerInfoStrictSvg.cs',
    'launcher/src/Guardian/Hud/PlayerInfo/PlayerInfoSvgAssetCatalog.cs',
    'launcher/src/Guardian/Hud/PlayerInfo/PlayerInfoSvgRasterizer.cs',
    'launcher/src/Guardian/Hud/PlayerInfo/PlayerInfoVisualState.cs',
    'launcher/src/Guardian/Hud/PlayerInfo/PlayerInfoWidget.cs',
    'launcher/tests/Guardian/Hud/PlayerInfo/PlayerInfoB006VisualCaptureTests.cs'
];
const expectedRendererBinaryNames = [
    'ExCSS.dll',
    'HarfBuzzSharp.dll',
    'ShimSkiaSharp.dll',
    'SkiaSharp.dll',
    'Svg.Animation.dll',
    'Svg.Custom.dll',
    'Svg.Model.dll',
    'Svg.SceneGraph.dll',
    'Svg.Skia.dll',
    'runtimes/win-x64/native/libHarfBuzzSharp.dll',
    'runtimes/win-x64/native/libSkiaSharp.dll'
];
const expectedViewportContracts = [
    {
        id:'viewport_1024x576_dpi100',
        host:{x:0, y:0, width:1024, height:576},
        content:{x:0, y:0, width:1024, height:576},
        monitorDpiScale:1,
        physicalScale:1,
        stage:{x:0, y:512, width:1024, height:64},
        tight:{x:0, y:474, width:282, height:81}
    },
    {
        id:'viewport_1600x900_dpi125',
        host:{x:0, y:0, width:1600, height:900},
        content:{x:0, y:0, width:1600, height:900},
        monitorDpiScale:1.25,
        physicalScale:1.5625,
        stage:{x:0, y:800, width:1600, height:100},
        tight:{x:0, y:741, width:440, height:126}
    },
    {
        id:'viewport_1920x1080_dpi150',
        host:{x:0, y:0, width:1920, height:1080},
        content:{x:0, y:0, width:1920, height:1080},
        monitorDpiScale:1.5,
        physicalScale:1.875,
        stage:{x:0, y:960, width:1920, height:120},
        tight:{x:0, y:890, width:528, height:150}
    },
    {
        id:'host_1280x960_letterbox_content_1280x720_dpi175',
        host:{x:0, y:0, width:1280, height:960},
        content:{x:0, y:120, width:1280, height:720},
        monitorDpiScale:1.75,
        physicalScale:1.25,
        stage:{x:0, y:760, width:1280, height:80},
        tight:{x:0, y:713, width:352, height:101}
    }
];
const expectedViewportIds =
    expectedViewportContracts.map(contract => contract.id);
const mpHorizontalAlignmentContract = {
    caseId:'p50',
    canvas:{width:1024, height:576, yNormalization:0},
    dxSearch:{minimum:-8, maximum:8, fixedDy:0},
    minimumPixelCount:32,
    minimumJaccard:0.35,
    mask:{
        alphaMinimum:224,
        greenMinimum:170,
        blueMinimum:170,
        greenMinusRedMinimum:40,
        blueMinusRedMinimum:40
    },
    fields:[
        {id:'label', roi:{x:91, y:514, width:30, height:16}},
        {id:'current', roi:{x:126, y:516, width:50, height:14}},
        {id:'maximum', roi:{x:176, y:516, width:50, height:14}},
        {id:'percent', roi:{x:86, y:530, width:31, height:13}}
    ]
};
const expectedHpFullToEmptyFrames = [
    1, 10, 18, 26, 33, 40, 46, 52, 58, 63, 68, 73, 77, 81,
    85, 88, 91, 94, 97, 100, 102, 104, 106, 108, 110, 112,
    114, 115, 116, 117, 118, 119, 120, 121, 122, 123, 124,
    125, 126, 127, 128, 129
];
const expectedMpFullToEmptyFrames = [
    1, 8, 15, 21, 27, 32, 37, 42, 46, 50, 54, 58, 61, 64,
    67, 70, 73, 75, 77, 79, 81, 83, 85, 87, 88, 89, 90, 91,
    92, 93, 94, 95, 96, 97, 98, 99, 100, 101, 101, 101, 101,
    101
];
const expectedFullToEmptyElapsedMilliseconds = [
    0,
    ...Array.from(
        {length:41},
        (_, index) => index % 3 === 0 ? 34 : 33)
];

function fail(message) {
    throw new Error(message);
}

function isPlainObject(value) {
    return value !== null &&
        typeof value === 'object' &&
        !Array.isArray(value);
}

function assertExactKeys(value, expectedKeys, label) {
    if (!isPlainObject(value)) {
        fail(`${label} must be an object.`);
    }
    const actual = Object.keys(value).sort(compareUtf8);
    const expected = [...expectedKeys].sort(compareUtf8);
    if (JSON.stringify(actual) !== JSON.stringify(expected)) {
        fail(
            `${label} keys drifted; actual=${actual.join(',')}; ` +
            `expected=${expected.join(',')}.`);
    }
}

function assertNonEmptyString(value, label) {
    if (typeof value !== 'string' || value.length === 0) {
        fail(`${label} must be a non-empty string.`);
    }
}

function assertPositiveSafeInteger(value, label) {
    if (!Number.isSafeInteger(value) || value <= 0) {
        fail(`${label} must be a positive safe integer.`);
    }
}

function assertFiniteNumber(value, label) {
    if (typeof value !== 'number' || !Number.isFinite(value)) {
        fail(`${label} must be a finite number.`);
    }
}

function assertJsonEqual(actual, expected, label) {
    if (JSON.stringify(actual) !== JSON.stringify(expected)) {
        fail(`${label} drifted.`);
    }
}

function compareUtf8(left, right) {
    return Buffer.from(left, 'utf8').compare(Buffer.from(right, 'utf8'));
}

function parseOptions() {
    const names = ['csharp', 'web', 'flash', 'output'];
    const result = {};
    const arguments_ = process.argv.slice(2);
    if (arguments_.length !== names.length) {
        fail(
            'Expected exactly --csharp, --web, --flash, and --output.');
    }
    for (const argument of arguments_) {
        const match = argument.match(
            /^--(csharp|web|flash|output)=(.+)$/u);
        if (!match || Object.hasOwn(result, match[1])) {
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
    if (!relative || relative.startsWith('..') ||
        path.isAbsolute(relative)) {
        fail(`${label} must resolve below its declared root.`);
    }
    return resolved;
}

function resolveInsideRepo(relativeValue, label) {
    return resolveBelow(repoRoot, relativeValue, label);
}

function repoRelative(filePath) {
    return path.relative(repoRoot, filePath).replace(/\\/gu, '/');
}

function isSameOrBelow(parentPath, candidatePath) {
    const relative = path.relative(
        path.resolve(parentPath),
        path.resolve(candidatePath));
    return relative === '' ||
        (!relative.startsWith('..') && !path.isAbsolute(relative));
}

function assertRootsDisjoint(leftRoot, rightRoot, label) {
    if (isSameOrBelow(leftRoot, rightRoot) ||
        isSameOrBelow(rightRoot, leftRoot)) {
        fail(`${label} roots must not contain one another.`);
    }
}

function assertExactDirectoryClosure(root, expectedPaths, label) {
    const actual = [];
    const walk = directory => {
        for (const entry of fs.readdirSync(
            directory,
            {withFileTypes:true})) {
            const entryPath = path.join(directory, entry.name);
            if (entry.isDirectory()) {
                walk(entryPath);
            } else if (entry.isFile()) {
                actual.push(
                    path.relative(root, entryPath).replace(/\\/gu, '/'));
            } else {
                fail(`${label} contains a non-file/non-directory entry.`);
            }
        }
    };
    walk(root);
    actual.sort(compareUtf8);
    const expected = [...expectedPaths]
        .map(value => value.replace(/\\/gu, '/'))
        .sort(compareUtf8);
    if (new Set(expected).size !== expected.length ||
        JSON.stringify(actual) !== JSON.stringify(expected)) {
        fail(
            `${label} is not its exact declared file closure; ` +
            `actual=${actual.join(',')}; expected=${expected.join(',')}.`);
    }
}

function sha256(bytes) {
    return crypto.createHash('sha256').update(bytes).digest('hex');
}

function readGitBlob(commit, relativePath, expectedOid, label) {
    const commitId = assertHex(commit, 40, `${label}.commit`);
    const pathValue = relativePath.replace(/\\/gu, '/');
    const resolvedPath = resolveInsideRepo(pathValue, `${label}.path`);
    if (repoRelative(resolvedPath) !== pathValue) {
        fail(`${label}.path is not canonical repo-relative syntax.`);
    }
    let actualOid;
    let bytes;
    try {
        actualOid = childProcess.execFileSync(
            'git',
            ['-C', repoRoot, 'rev-parse', `${commitId}:${pathValue}`],
            {
                encoding:'utf8',
                windowsHide:true,
                maxBuffer:1024 * 1024
            }).trim().toLowerCase();
        bytes = childProcess.execFileSync(
            'git',
            ['-C', repoRoot, 'cat-file', 'blob', actualOid],
            {
                encoding:null,
                windowsHide:true,
                maxBuffer:64 * 1024 * 1024
            });
    } catch (error) {
        fail(`${label} Git blob could not be read: ${error.message}`);
    }
    const expected = assertHex(expectedOid, 40, `${label}.gitBlobOid`);
    if (actualOid !== expected) {
        fail(`${label} Git blob OID drifted.`);
    }
    return {
        oid:actualOid,
        bytes,
        identity: {
            bytes:bytes.length,
            sha256:sha256(bytes)
        }
    };
}

function assertSha(value, label) {
    if (typeof value !== 'string' ||
        !/^[0-9a-f]{64}$/iu.test(value)) {
        fail(`${label} is not a SHA-256.`);
    }
    return value.toLowerCase();
}

function assertHex(value, length, label) {
    const expression = new RegExp(`^[0-9a-f]{${length}}$`, 'iu');
    if (typeof value !== 'string' || !expression.test(value)) {
        fail(`${label} is not a ${length}-digit hexadecimal identity.`);
    }
    return value.toLowerCase();
}

function assertRevision(value, label) {
    if (typeof value !== 'string' ||
        !/^sha256:[0-9a-f]{64}$/u.test(value)) {
        fail(`${label} is not a lowercase sha256: revision.`);
    }
    return value;
}

function pngSize(bytes, label) {
    const signature = Buffer.from([
        0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a
    ]);
    if (bytes.length < 24 ||
        !bytes.subarray(0, 8).equals(signature) ||
        bytes.toString('ascii', 12, 16) !== 'IHDR') {
        fail(`${label} is not a complete PNG with an IHDR.`);
    }
    return {
        width:bytes.readUInt32BE(16),
        height:bytes.readUInt32BE(20)
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

function newInputTracker() {
    const entries = new Map();
    const read = (filePath, label) => {
        const absolute = path.resolve(filePath);
        let bytes;
        try {
            bytes = fs.readFileSync(absolute);
        } catch (error) {
            fail(`Cannot read ${label}: ${error.message}`);
        }
        const record = {
            path:repoRelative(absolute),
            bytes:bytes.length,
            sha256:sha256(bytes)
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
                fail(
                    'Input identity changed during comparison: ' +
                    expected.path);
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
        bytes:tracked.bytes,
        value,
        sha256:tracked.identity.sha256,
        identity:tracked.identity
    };
}

function readVerifiedPng(
    tracker,
    root,
    relativePath,
    expectedBytes,
    expectedSha,
    label,
    expectedWidth = viewport.width,
    expectedHeight = viewport.height) {
    const artifactPath = resolveBelow(root, relativePath, `${label}.path`);
    const tracked = tracker.read(artifactPath, label);
    if (expectedBytes !== null &&
        tracked.identity.bytes !== expectedBytes) {
        fail(`${label} encoded byte length mismatch.`);
    }
    if (tracked.identity.sha256 !==
        assertSha(expectedSha, `${label}.sha256`)) {
        fail(`${label} SHA-256 mismatch.`);
    }
    assertPngSize(
        tracked.bytes, expectedWidth, expectedHeight, label);
    return {
        path:artifactPath,
        bytes:tracked.bytes,
        identity:tracked.identity
    };
}

function assertRect(value, expected, label) {
    assertExactKeys(value, ['x', 'y', 'width', 'height'], label);
    for (const key of ['x', 'y', 'width', 'height']) {
        if (!Number.isSafeInteger(value[key])) {
            fail(`${label}.${key} must be a safe integer.`);
        }
    }
    if (expected) {
        assertJsonEqual(value, expected, label);
    } else if (value.width <= 0 || value.height <= 0) {
        fail(`${label} must have positive dimensions.`);
    }
}

function validateCsharpGauge(gauge, gaugeId, frame, label) {
    assertExactKeys(gauge, [
        'gaugeId',
        'hasRenderableState',
        'isInputValid',
        'clampedCurrent',
        'maximum',
        'normalizedRatio',
        'currentVirtualFrame',
        'targetVirtualFrame',
        'currentText',
        'maximumText',
        'percentText',
        'combinedText',
        'diagnostic'
    ], label);
    if (gauge.gaugeId !== gaugeId ||
        gauge.hasRenderableState !== true ||
        gauge.isInputValid !== true ||
        gauge.currentVirtualFrame !== frame ||
        gauge.targetVirtualFrame !== frame ||
        gauge.diagnostic !== null) {
        fail(`${label} state/frame contract drifted.`);
    }
    for (const key of [
        'clampedCurrent', 'maximum', 'normalizedRatio'
    ]) {
        assertFiniteNumber(gauge[key], `${label}.${key}`);
    }
    for (const key of [
        'currentText', 'maximumText', 'percentText'
    ]) {
        assertNonEmptyString(gauge[key], `${label}.${key}`);
    }
    if (gaugeId === 'hp' && gauge.combinedText !== null) {
        fail(`${label}.combinedText must remain null.`);
    }
    if (gaugeId === 'mp') {
        assertNonEmptyString(gauge.combinedText, `${label}.combinedText`);
    }
}

function validateCsharpManifest(csharp, reportPath, tracker) {
    const reportRoot = path.dirname(reportPath);
    const baseKeys = [
        'schema',
        'schemaVersion',
        'status',
        'scope',
        'canvasContract',
        'determinism',
        'asset',
        'binaries',
        'sourceFiles',
        'layerOrder',
        'baseline',
        'cases',
        'viewportMatrix',
        'hpFullToEmpty',
        'outputs',
        'outputClosure',
        'verifiedContracts',
        'unverifiedClaims'
    ];
    assertExactKeys(csharp, baseKeys, 'C# capture manifest');
    if (csharp.schema !==
            'cf7.player-info-hud.b0-06-csharp-visual-capture' ||
        csharp.schemaVersion !== 2 ||
        csharp.status !== 'structural_capture_complete' ||
        csharp.scope !== 'fixture_only') {
        fail('Unsupported C# B0-06 visual capture contract.');
    }
    assertExactKeys(csharp.canvasContract, [
        'logicalWidth',
        'logicalHeight',
        'background',
        'compositeBackgroundId',
        'detail'
    ], 'C# canvasContract');
    if (csharp.canvasContract.logicalWidth !== viewport.width ||
        csharp.canvasContract.logicalHeight !== viewport.height ||
        csharp.canvasContract.background !== 'transparent_argb_0' ||
        csharp.canvasContract.compositeBackgroundId !== null) {
        fail('C# canvas contract drifted.');
    }
    assertNonEmptyString(
        csharp.canvasContract.detail,
        'C# canvasContract.detail');

    assertExactKeys(csharp.determinism, [
        'runSpecificFieldsOmitted',
        'sameInputPArgbBytesVerified',
        'sameBitmapPngBytesVerified',
        'manifestRule',
        'inProcessVerification'
    ], 'C# determinism');
    if (csharp.determinism.runSpecificFieldsOmitted !== true ||
        csharp.determinism.sameInputPArgbBytesVerified !== true ||
        csharp.determinism.sameBitmapPngBytesVerified !== true) {
        fail('C# capture does not assert its deterministic fixture contract.');
    }

    const expectedBinaries = [
        {
            id:'core',
            fileName:'CRAZYFLASHER7MercenaryEmpire.Core.dll'
        },
        {id:'tests', fileName:'Launcher.Tests.dll'},
        ...expectedRendererBinaryNames.map(fileName => ({
            id:`renderer:${fileName}`,
            fileName
        }))
    ];
    if (!Array.isArray(csharp.binaries) ||
        csharp.binaries.length !== expectedBinaries.length) {
        fail('C# capture binary closure must contain Core and tests.');
    }
    for (const [index, expected] of expectedBinaries.entries()) {
        const binary = csharp.binaries[index];
        const label = `C# binaries[${index}]`;
        assertExactKeys(
            binary, ['id', 'fileName', 'bytes', 'sha256'], label);
        if (binary.id !== expected.id ||
            binary.fileName !== expected.fileName) {
            fail(`${label} identity/order drifted.`);
        }
        assertPositiveSafeInteger(binary.bytes, `${label}.bytes`);
        const binaryPath = resolveInsideRepo(
            `launcher/tests/bin/Release/${binary.fileName}`,
            `${label}.fileName`);
        const tracked = tracker.read(binaryPath, label);
        if (tracked.identity.bytes !== binary.bytes ||
            tracked.identity.sha256 !==
                assertSha(binary.sha256, `${label}.sha256`)) {
            fail(`${label} no longer matches the executed Release output.`);
        }
    }

    if (!Array.isArray(csharp.sourceFiles) ||
        csharp.sourceFiles.length !== expectedCsharpSourcePaths.length) {
        fail('C# capture source closure is incomplete.');
    }
    for (const [index, expectedPath] of
        expectedCsharpSourcePaths.entries()) {
        const source = csharp.sourceFiles[index];
        const label = `C# sourceFiles[${index}]`;
        assertExactKeys(
            source, ['relativePath', 'bytes', 'sha256'], label);
        if (source.relativePath !== expectedPath) {
            fail(`${label} path/order drifted.`);
        }
        assertPositiveSafeInteger(source.bytes, `${label}.bytes`);
        const sourcePath = resolveInsideRepo(
            source.relativePath, `${label}.relativePath`);
        const tracked = tracker.read(sourcePath, label);
        if (tracked.identity.bytes !== source.bytes ||
            tracked.identity.sha256 !==
                assertSha(source.sha256, `${label}.sha256`)) {
            fail(`${label} no longer matches the captured source bytes.`);
        }
    }

    assertExactKeys(csharp.asset, [
        'assetSetId',
        'revision',
        'exactManifestSha256',
        'rasterContractVersion',
        'rendererPackage',
        'rendererVersion',
        'skiaSharpVersion',
        'featureSet',
        'colorType',
        'alphaType'
    ], 'C# asset identity');
    const revision = assertRevision(
        csharp.asset.revision, 'C# asset.revision');
    const exactManifestSha256 = assertSha(
        csharp.asset.exactManifestSha256,
        'C# asset.exactManifestSha256');
    if (csharp.asset.assetSetId !== 'player-info-hp-mp-b0' ||
        csharp.asset.rasterContractVersion !== 1 ||
        csharp.asset.rendererPackage !== 'Svg.Skia' ||
        csharp.asset.rendererVersion !== '5.1.1' ||
        csharp.asset.skiaSharpVersion !== '3.119.4' ||
        csharp.asset.featureSet !==
            'cf7-player-info-static-svg-v1' ||
        csharp.asset.colorType !== 'Bgra8888' ||
        csharp.asset.alphaType !== 'premultiplied') {
        fail('C# asset/renderer identity drifted.');
    }

    assertExactKeys(csharp.layerOrder, [
        'compositeOrder',
        'mpAssetIds',
        'hpAssetIds',
        'rasterLayerOrder'
    ], 'C# layerOrder');
    assertJsonEqual(
        csharp.layerOrder.compositeOrder, ['mp', 'hp'],
        'C# composite order');
    assertJsonEqual(
        csharp.layerOrder.rasterLayerOrder,
        expectedAssets
            .filter(asset => asset.id.startsWith('mp.'))
            .concat(expectedAssets.filter(asset =>
                asset.id.startsWith('hp.')))
            .map(asset => asset.id),
        'C# raster layer order');

    assertExactKeys(csharp.baseline, [
        'viewportId',
        'contentViewport',
        'monitorDpiScale',
        'physicalScale',
        'stagePhysicalBounds',
        'tightPhysicalBounds',
        'batchKey'
    ], 'C# baseline');
    if (csharp.baseline.viewportId !==
            'viewport_1024x576_dpi100' ||
        csharp.baseline.monitorDpiScale !== 1 ||
        csharp.baseline.physicalScale !== 1) {
        fail('C# baseline scale/viewport contract drifted.');
    }
    assertRect(
        csharp.baseline.contentViewport,
        {x:0, y:0, width:1024, height:576},
        'C# baseline.contentViewport');
    assertRect(
        csharp.baseline.stagePhysicalBounds,
        {x:0, y:512, width:1024, height:64},
        'C# baseline.stagePhysicalBounds');
    assertRect(
        csharp.baseline.tightPhysicalBounds,
        {x:0, y:474, width:282, height:81},
        'C# baseline.tightPhysicalBounds');
    assertNonEmptyString(csharp.baseline.batchKey, 'C# baseline.batchKey');

    if (!Array.isArray(csharp.outputs) ||
        csharp.outputs.length !== 35) {
        fail('C# output closure must contain exactly 35 records.');
    }
    const outputKeys = [
        'relativePath',
        'kind',
        'viewportId',
        'stateId',
        'width',
        'height',
        'sourcePixelFormat',
        'physicalScale',
        'monitorDpiScale',
        'flashViewportPhysical',
        'stagePhysicalBounds',
        'tightPhysicalBounds',
        'alphaBounds',
        'pixelSha256',
        'pngBytes',
        'pngSha256'
    ];
    const outputByPath = new Map();
    const verifiedOutputByPath = new Map();
    let priorPath = null;
    let outputTotalBytes = 0;
    const outputClosureSource = [];
    for (const [index, output] of csharp.outputs.entries()) {
        const label = `C# outputs[${index}]`;
        assertExactKeys(output, outputKeys, label);
        assertNonEmptyString(output.relativePath, `${label}.relativePath`);
        resolveBelow(reportRoot, output.relativePath, `${label}.relativePath`);
        if (outputByPath.has(output.relativePath)) {
            fail(`Duplicate C# output path: ${output.relativePath}`);
        }
        if (priorPath !== null &&
            compareUtf8(priorPath, output.relativePath) >= 0) {
            fail('C# output records are not in strict canonical order.');
        }
        priorPath = output.relativePath;
        outputByPath.set(output.relativePath, output);
        assertNonEmptyString(output.kind, `${label}.kind`);
        assertNonEmptyString(output.viewportId, `${label}.viewportId`);
        assertNonEmptyString(output.stateId, `${label}.stateId`);
        assertPositiveSafeInteger(output.width, `${label}.width`);
        assertPositiveSafeInteger(output.height, `${label}.height`);
        if (output.sourcePixelFormat !== 'Format32bppPArgb') {
            fail(`${label}.sourcePixelFormat drifted.`);
        }
        assertFiniteNumber(output.physicalScale, `${label}.physicalScale`);
        assertFiniteNumber(
            output.monitorDpiScale, `${label}.monitorDpiScale`);
        assertRect(
            output.flashViewportPhysical, null,
            `${label}.flashViewportPhysical`);
        assertRect(
            output.stagePhysicalBounds, null,
            `${label}.stagePhysicalBounds`);
        assertRect(
            output.tightPhysicalBounds, null,
            `${label}.tightPhysicalBounds`);
        assertRect(output.alphaBounds, null, `${label}.alphaBounds`);
        assertSha(output.pixelSha256, `${label}.pixelSha256`);
        assertPositiveSafeInteger(output.pngBytes, `${label}.pngBytes`);
        assertSha(output.pngSha256, `${label}.pngSha256`);
        const verified = readVerifiedPng(
            tracker,
            reportRoot,
            output.relativePath,
            output.pngBytes,
            output.pngSha256,
            `${label} PNG`,
            output.width,
            output.height);
        verifiedOutputByPath.set(output.relativePath, verified);
        outputTotalBytes += output.pngBytes;
        outputClosureSource.push(
            `${output.relativePath}\0${output.pngBytes}\0` +
            `${output.pngSha256.toUpperCase()}\n`);
    }
    assertExactKeys(csharp.outputClosure, [
        'fileCount',
        'totalPngBytes',
        'sha256',
        'canonicalFormat'
    ], 'C# outputClosure');
    const outputClosureSha = sha256(
        Buffer.from(outputClosureSource.join(''), 'utf8'));
    if (csharp.outputClosure.fileCount !== csharp.outputs.length ||
        csharp.outputClosure.totalPngBytes !== outputTotalBytes ||
        assertSha(
            csharp.outputClosure.sha256,
            'C# outputClosure.sha256') !== outputClosureSha ||
        csharp.outputClosure.canonicalFormat !==
            'sorted relativePath + NUL + decimal byte length + NUL + uppercase SHA-256 + LF') {
        fail('C# outputClosure no longer binds its output records.');
    }
    const expectedCsharpOutputPaths = [
        ...expectedCases.flatMap(item => [
            `cases/${item.id}.main.png`,
            `cases/${item.id}.tight.png`
        ]),
        ...expectedViewportIds.flatMap(viewportId => [
            `viewports/${viewportId}/empty.png`,
            `viewports/${viewportId}/full.png`,
            `viewports/${viewportId}/half.png`
        ]),
        'transitions/hp-full-to-empty-contact-sheet.png'
    ].sort(compareUtf8);
    const actualCsharpOutputPaths =
        [...outputByPath.keys()].sort(compareUtf8);
    if (JSON.stringify(actualCsharpOutputPaths) !==
        JSON.stringify(expectedCsharpOutputPaths)) {
        fail('C# capture output paths are not the exact 35-file matrix.');
    }
    for (const item of expectedCases) {
        if (outputByPath.get(`cases/${item.id}.main.png`).kind !==
                'fixture-main-viewport' ||
            outputByPath.get(`cases/${item.id}.tight.png`).kind !==
                'fixture-alpha-tight-crop') {
            fail(`C# case output kinds drifted at ${item.id}.`);
        }
    }
    for (const viewportId of expectedViewportIds) {
        for (const stateId of ['empty', 'full', 'half']) {
            const output = outputByPath.get(
                `viewports/${viewportId}/${stateId}.png`);
            if (output.kind !== 'viewport-key-state-main-viewport' ||
                output.viewportId !== viewportId) {
                fail(
                    `C# viewport output contract drifted at ` +
                    `${viewportId}/${stateId}.`);
            }
        }
    }
    if (outputByPath.get(
        'transitions/hp-full-to-empty-contact-sheet.png').kind !==
            'hp-full-to-empty-contact-sheet') {
        fail('C# HP transition contact-sheet output kind drifted.');
    }
    assertExactDirectoryClosure(
        reportRoot,
        [path.basename(reportPath), ...expectedCsharpOutputPaths],
        'C# visual capture root');

    if (!Array.isArray(csharp.cases) ||
        csharp.cases.length !== expectedCases.length) {
        fail('C# capture is not the exact 11-case corpus.');
    }
    const cases = expectedCases.map((expected, index) => {
        const actual = csharp.cases[index];
        const label = `C# case ${expected.id}`;
        assertExactKeys(actual, [
            'caseId',
            'visualState',
            'paintResult',
            'mainViewportPng',
            'tightCropPng'
        ], label);
        if (actual.caseId !== expected.id ||
            actual.mainViewportPng !==
                `cases/${expected.id}.main.png` ||
            actual.tightCropPng !==
                `cases/${expected.id}.tight.png`) {
            fail(`${label} path/order contract drifted.`);
        }
        assertExactKeys(actual.visualState, [
            'hp', 'mp', 'hasRenderableState', 'wantsAnimationTick'
        ], `${label}.visualState`);
        if (actual.visualState.hasRenderableState !== true ||
            actual.visualState.wantsAnimationTick !== false) {
            fail(`${label} is not a snapped renderable fixture state.`);
        }
        validateCsharpGauge(
            actual.visualState.hp, 'hp', expected.hpFrame,
            `${label}.visualState.hp`);
        validateCsharpGauge(
            actual.visualState.mp, 'mp', expected.mpFrame,
            `${label}.visualState.mp`);
        assertExactKeys(actual.paintResult, [
            'hpVirtualFrame',
            'mpVirtualFrame',
            'mpLeftContourCount',
            'mpRightContourCount',
            'mpRimAssetId',
            'mpPaletteStart'
        ], `${label}.paintResult`);
        if (actual.paintResult.hpVirtualFrame !== expected.hpFrame ||
            actual.paintResult.mpVirtualFrame !== expected.mpFrame) {
            fail(`${label} paint frames drifted.`);
        }
        for (const key of [
            'mpLeftContourCount', 'mpRightContourCount'
        ]) {
            if (!Number.isSafeInteger(actual.paintResult[key]) ||
                actual.paintResult[key] < 0) {
                fail(`${label}.paintResult.${key} is invalid.`);
            }
        }
        assertNonEmptyString(
            actual.paintResult.mpRimAssetId,
            `${label}.paintResult.mpRimAssetId`);
        assertNonEmptyString(
            actual.paintResult.mpPaletteStart,
            `${label}.paintResult.mpPaletteStart`);

        const output = outputByPath.get(actual.mainViewportPng);
        const tightOutput = outputByPath.get(actual.tightCropPng);
        if (!output ||
            output.kind !== 'fixture-main-viewport' ||
            output.viewportId !== csharp.baseline.viewportId ||
            output.stateId !== expected.id ||
            output.width !== viewport.width ||
            output.height !== viewport.height ||
            output.physicalScale !== 1 ||
            output.monitorDpiScale !== 1) {
            fail(
                `${label} has no exact baseline main-viewport output record.`);
        }
        if (!tightOutput ||
            tightOutput.kind !== 'fixture-alpha-tight-crop' ||
            tightOutput.viewportId !== csharp.baseline.viewportId ||
            tightOutput.stateId !== expected.id ||
            tightOutput.physicalScale !== 1 ||
            tightOutput.monitorDpiScale !== 1) {
            fail(`${label} has no exact baseline tight-crop output record.`);
        }
        assertRect(
            output.flashViewportPhysical,
            csharp.baseline.contentViewport,
            `${label} output.flashViewportPhysical`);
        assertRect(
            output.stagePhysicalBounds,
            csharp.baseline.stagePhysicalBounds,
            `${label} output.stagePhysicalBounds`);
        assertRect(
            output.tightPhysicalBounds,
            csharp.baseline.tightPhysicalBounds,
            `${label} output.tightPhysicalBounds`);
        const verified = verifiedOutputByPath.get(actual.mainViewportPng);
        if (!verified) {
            fail(
                `${label} main-viewport PNG was not read from the closure.`);
        }
        return {
            id:expected.id,
            hpFrame:expected.hpFrame,
            mpFrame:expected.mpFrame,
            path:verified.path,
            bytes:verified.bytes,
            identity:verified.identity,
            sourcePixelFormat:output.sourcePixelFormat,
            sourcePixelSha256:
                assertSha(output.pixelSha256, `${label}.pixelSha256`)
        };
    });

    if (!Array.isArray(csharp.viewportMatrix) ||
        csharp.viewportMatrix.length !== expectedViewportIds.length) {
        fail('C# viewport matrix must contain the exact four ADR cases.');
    }
    const viewportStateContract = [
        {stateId:'full', caseId:'full'},
        {stateId:'half', caseId:'p50'},
        {stateId:'empty', caseId:'empty'}
    ];
    for (const [index, viewportCapture] of
        csharp.viewportMatrix.entries()) {
        const expectedViewport = expectedViewportContracts[index];
        const viewportId = expectedViewport.id;
        const label = `C# viewportMatrix[${index}]`;
        assertExactKeys(
            viewportCapture,
            ['viewportId', 'hostViewport', 'plan', 'states'],
            label);
        if (viewportCapture.viewportId !== viewportId) {
            fail(`${label}.viewportId/order drifted.`);
        }
        assertRect(
            viewportCapture.hostViewport,
            expectedViewport.host,
            `${label}.hostViewport`);
        assertExactKeys(viewportCapture.plan, [
            'viewportId',
            'contentViewport',
            'monitorDpiScale',
            'physicalScale',
            'stagePhysicalBounds',
            'tightPhysicalBounds',
            'batchKey'
        ], `${label}.plan`);
        if (viewportCapture.plan.viewportId !== viewportId) {
            fail(`${label}.plan.viewportId drifted.`);
        }
        assertRect(
            viewportCapture.plan.contentViewport,
            expectedViewport.content,
            `${label}.plan.contentViewport`);
        assertRect(
            viewportCapture.plan.stagePhysicalBounds,
            expectedViewport.stage,
            `${label}.plan.stagePhysicalBounds`);
        assertRect(
            viewportCapture.plan.tightPhysicalBounds,
            expectedViewport.tight,
            `${label}.plan.tightPhysicalBounds`);
        assertFiniteNumber(
            viewportCapture.plan.monitorDpiScale,
            `${label}.plan.monitorDpiScale`);
        assertFiniteNumber(
            viewportCapture.plan.physicalScale,
            `${label}.plan.physicalScale`);
        if (viewportCapture.plan.monitorDpiScale !==
                expectedViewport.monitorDpiScale ||
            viewportCapture.plan.physicalScale !==
                expectedViewport.physicalScale) {
            fail(`${label}.plan scale contract drifted.`);
        }
        assertNonEmptyString(
            viewportCapture.plan.batchKey,
            `${label}.plan.batchKey`);
        if (!Array.isArray(viewportCapture.states) ||
            viewportCapture.states.length !==
                viewportStateContract.length) {
            fail(`${label}.states must contain full/half/empty.`);
        }
        for (const [stateIndex, expectedState] of
            viewportStateContract.entries()) {
            const state = viewportCapture.states[stateIndex];
            const stateLabel = `${label}.states[${stateIndex}]`;
            assertExactKeys(state, [
                'stateId',
                'caseId',
                'visualState',
                'paintResult',
                'png'
            ], stateLabel);
            const expectedPath =
                `viewports/${viewportId}/${expectedState.stateId}.png`;
            const stateOutput = outputByPath.get(expectedPath);
            if (state.stateId !== expectedState.stateId ||
                state.caseId !== expectedState.caseId ||
                state.png !== expectedPath ||
                !stateOutput) {
                fail(`${stateLabel} reference drifted.`);
            }
            if (stateOutput.width !== expectedViewport.content.width ||
                stateOutput.height !== expectedViewport.content.height ||
                stateOutput.monitorDpiScale !==
                    expectedViewport.monitorDpiScale ||
                stateOutput.physicalScale !==
                    expectedViewport.physicalScale) {
                fail(`${stateLabel} output dimension/scale drifted.`);
            }
            assertRect(
                stateOutput.flashViewportPhysical,
                expectedViewport.content,
                `${stateLabel} output.flashViewportPhysical`);
            assertRect(
                stateOutput.stagePhysicalBounds,
                expectedViewport.stage,
                `${stateLabel} output.stagePhysicalBounds`);
            assertRect(
                stateOutput.tightPhysicalBounds,
                expectedViewport.tight,
                `${stateLabel} output.tightPhysicalBounds`);
        }
    }

    assertExactKeys(csharp.hpFullToEmpty, [
        'id',
        'logicalFramesPerSecond',
        'transitionTickCount',
        'frameCountIncludingInitial',
        'contactSheetPng',
        'contactSheetColumns',
        'contactSheetGapPixels',
        'frames'
    ], 'C# hpFullToEmpty');
    if (csharp.hpFullToEmpty.id !== 'hp_full_to_empty' ||
        csharp.hpFullToEmpty.logicalFramesPerSecond !== 30 ||
        csharp.hpFullToEmpty.transitionTickCount !== 41 ||
        csharp.hpFullToEmpty.frameCountIncludingInitial !== 42 ||
        csharp.hpFullToEmpty.contactSheetPng !==
            'transitions/hp-full-to-empty-contact-sheet.png' ||
        csharp.hpFullToEmpty.contactSheetColumns !== 7 ||
        csharp.hpFullToEmpty.contactSheetGapPixels !== 2 ||
        !Array.isArray(csharp.hpFullToEmpty.frames) ||
        csharp.hpFullToEmpty.frames.length !== 42) {
        fail('C# HP full-to-empty transition contract drifted.');
    }
    for (const [index, frame] of
        csharp.hpFullToEmpty.frames.entries()) {
        const label = `C# hpFullToEmpty.frames[${index}]`;
        assertExactKeys(frame, [
            'tickIndex',
            'elapsedMilliseconds',
            'hpVirtualFrame',
            'mpVirtualFrame',
            'contactCell',
            'alphaBounds',
            'pixelSha256',
            'visualState',
            'paintResult'
        ], label);
        if (frame.tickIndex !== index ||
            frame.hpVirtualFrame !==
                expectedHpFullToEmptyFrames[index] ||
            frame.mpVirtualFrame !==
                expectedMpFullToEmptyFrames[index] ||
            frame.elapsedMilliseconds !==
                expectedFullToEmptyElapsedMilliseconds[index]) {
            fail(`${label} logical progression drifted.`);
        }
        assertRect(frame.contactCell, null, `${label}.contactCell`);
        assertRect(frame.alphaBounds, null, `${label}.alphaBounds`);
        assertSha(frame.pixelSha256, `${label}.pixelSha256`);
    }
    if (!Array.isArray(csharp.verifiedContracts) ||
        csharp.verifiedContracts.length === 0 ||
        !Array.isArray(csharp.unverifiedClaims)) {
        fail('C# capture verification boundary is missing.');
    }
    for (const required of [
        'Flash, FFDec, Web, or cross-renderer pixel parity',
        'visual similarity threshold or aesthetic acceptance',
        'game-scene composite appearance',
        'human visual or UI acceptance',
        'real UiData or pi_* integration',
        'candidate execution, e2e verification, promotion, deployment, or standard entry'
    ]) {
        if (!csharp.unverifiedClaims.includes(required)) {
            fail(`C# capture no longer defers: ${required}.`);
        }
    }

    return {
        assetSetId:csharp.asset.assetSetId,
        assetSetRevision:revision,
        exactManifestSha256,
        renderer: {
            package:csharp.asset.rendererPackage,
            version:csharp.asset.rendererVersion,
            skiaSharpVersion:csharp.asset.skiaSharpVersion,
            featureSet:csharp.asset.featureSet,
            colorType:csharp.asset.colorType,
            alphaType:csharp.asset.alphaType
        },
        baselineGeometry: {
            viewportId:csharp.baseline.viewportId,
            contentViewport:csharp.baseline.contentViewport,
            monitorDpiScale:csharp.baseline.monitorDpiScale,
            physicalScale:csharp.baseline.physicalScale,
            stagePhysicalBounds:csharp.baseline.stagePhysicalBounds,
            tightPhysicalBounds:csharp.baseline.tightPhysicalBounds
        },
        canvasContractPresent:true,
        selectedArtifactCount:cases.length,
        cases
    };
}

function validateWebReport(web, reportPath, tracker) {
    const reportRoot = path.dirname(reportPath);
    assertExactKeys(web, [
        'schema',
        'status',
        'viewport',
        'deviceScaleFactor',
        'background',
        'manifest',
        'renderSemantics',
        'browser',
        'tooling',
        'assets',
        'cases'
    ], 'Web render report');
    if (web.schema !== 'cf7.player_info.web_svg_harness.v2' ||
        web.status !==
            'canonical_manifest_rendered_awaiting_human_review' ||
        JSON.stringify(web.viewport) !==
            JSON.stringify([viewport.width, viewport.height]) ||
        web.deviceScaleFactor !== 1 ||
        web.background !== 'transparent') {
        fail('Unsupported Web canonical render report contract.');
    }
    assertExactKeys(web.manifest, [
        'path', 'sha256', 'assetSetRevision', 'schemaVersion'
    ], 'Web report manifest identity');
    if (web.manifest.schemaVersion !== 1) {
        fail('Web report manifest schema version drifted.');
    }
    const reportedRevision = assertRevision(
        web.manifest.assetSetRevision,
        'Web manifest assetSetRevision');
    const reportedManifestSha = assertSha(
        web.manifest.sha256, 'Web manifest SHA-256');

    assertExactKeys(web.browser, [
        'family',
        'version',
        'executableSha256',
        'executableBytes'
    ], 'Web browser identity');
    if (web.browser.family !==
            'Microsoft Edge via Playwright chromium') {
        fail('Web report browser family drifted.');
    }
    assertNonEmptyString(web.browser.version, 'Web browser.version');
    assertPositiveSafeInteger(
        web.browser.executableBytes,
        'Web browser.executableBytes');
    assertSha(
        web.browser.executableSha256,
        'Web browser.executableSha256');

    assertExactKeys(web.tooling, [
        'harness',
        'playwright',
        'edgeIdentityStableDuringRender',
        'harnessIdentityStableDuringRender',
        'playwrightIdentityStableDuringRender',
        'networkUsed',
        'packagesInstalled'
    ], 'Web tooling');
    if (web.tooling.edgeIdentityStableDuringRender !== true ||
        web.tooling.harnessIdentityStableDuringRender !== true ||
        web.tooling.playwrightIdentityStableDuringRender !== true ||
        web.tooling.networkUsed !== false ||
        web.tooling.packagesInstalled !== false) {
        fail('Web tooling stability/offline boundary drifted.');
    }
    for (const [tool, expectedPath, label] of [
        [
            web.tooling.harness,
            'tools/player-info-hud/run-web-svg-harness.js',
            'Web tooling.harness'
        ],
        [
            web.tooling.playwright,
            'launcher/perf/node_modules/playwright/package.json',
            'Web tooling.playwright'
        ]
    ]) {
        const keys = label.endsWith('playwright')
            ? ['path', 'version', 'bytes', 'sha256']
            : ['path', 'bytes', 'sha256'];
        assertExactKeys(tool, keys, label);
        if (tool.path !== expectedPath) {
            fail(`${label}.path drifted.`);
        }
        assertPositiveSafeInteger(tool.bytes, `${label}.bytes`);
        const toolPath = resolveInsideRepo(tool.path, `${label}.path`);
        const tracked = tracker.read(toolPath, label);
        if (tracked.identity.bytes !== tool.bytes ||
            tracked.identity.sha256 !==
                assertSha(tool.sha256, `${label}.sha256`)) {
            fail(`${label} no longer matches the renderer input.`);
        }
        if (label.endsWith('playwright')) {
            assertNonEmptyString(tool.version, `${label}.version`);
            const packageValue = JSON.parse(tracked.bytes.toString('utf8'));
            if (packageValue.version !== tool.version) {
                fail(`${label}.version does not match package.json.`);
            }
        }
    }

    const manifestPath = resolveInsideRepo(
        web.manifest.path, 'Web manifest path');
    const manifestInput = readTrackedJson(
        tracker, manifestPath, 'Web canonical manifest');
    if (manifestInput.sha256 !== reportedManifestSha) {
        fail('Web manifest file identity changed.');
    }
    if (manifestInput.bytes.includes(Buffer.from('pending-oracle'))) {
        fail('Web canonical manifest retains an unresolved oracle token.');
    }
    const manifest = manifestInput.value;
    assertExactKeys(manifest, [
        'format',
        'schemaVersion',
        'assetSet',
        'units',
        'stage',
        'rendererContract',
        'assets',
        'gauges',
        'effectPolicy'
    ], 'Web canonical manifest');
    assertExactKeys(manifest.assetSet, [
        'id',
        'revision',
        'revisionAlgorithm',
        'rasterContractVersion',
        'runtimeCacheIdentityComponents'
    ], 'Web canonical manifest assetSet');
    assertExactKeys(manifest.units, [
        'svgUnit', 'sourceTwipsPerSvgUnit'
    ], 'Web canonical manifest units');
    assertExactKeys(manifest.stage, [
        'logicalWidth', 'logicalHeight', 'compositeOrder'
    ], 'Web canonical manifest stage');
    assertExactKeys(manifest.rendererContract, [
        'package',
        'version',
        'skiaSharpVersion',
        'featureSet',
        'colorType',
        'alphaType',
        'externalResources',
        'scripts',
        'runtimeTextElements'
    ], 'Web canonical manifest rendererContract');
    if (manifest.format !==
            'cf7.player-info-hud.asset-manifest' ||
        manifest.schemaVersion !== 1 ||
        manifest.assetSet.id !== 'player-info-hp-mp-b0' ||
        manifest.assetSet.revision !== reportedRevision ||
        manifest.assetSet.revisionAlgorithm !==
            'sha256(sorted UTF-8 relative path + NUL + exact file bytes + NUL)' ||
        manifest.assetSet.rasterContractVersion !== 1 ||
        JSON.stringify(
            manifest.assetSet.runtimeCacheIdentityComponents) !==
            JSON.stringify([
                'assetSet.revision',
                'exact-manifest-sha256'
            ]) ||
        manifest.units.svgUnit !== 'logical-pixel' ||
        manifest.units.sourceTwipsPerSvgUnit !== 20 ||
        manifest.stage.logicalWidth !== childAuthoringStage.width ||
        manifest.stage.logicalHeight !== childAuthoringStage.height ||
        JSON.stringify(manifest.stage.compositeOrder) !==
            JSON.stringify(['mp', 'hp'])) {
        fail('Web canonical manifest identity/unit/stage contract drifted.');
    }
    if (manifest.rendererContract.package !== 'Svg.Skia' ||
        manifest.rendererContract.version !== '5.1.1' ||
        manifest.rendererContract.skiaSharpVersion !== '3.119.4' ||
        manifest.rendererContract.featureSet !==
            'cf7-player-info-static-svg-v1' ||
        manifest.rendererContract.colorType !== 'Bgra8888' ||
        manifest.rendererContract.alphaType !== 'premultiplied' ||
        manifest.rendererContract.externalResources !== 'forbidden' ||
        manifest.rendererContract.scripts !== 'forbidden' ||
        manifest.rendererContract.runtimeTextElements !== 'forbidden') {
        fail('Web canonical renderer contract drifted.');
    }

    assertExactKeys(web.renderSemantics, [
        'capturedLayerScope',
        'coordinateSpace',
        'compositeOrder',
        'csharpProgrammaticDynamicTextIncluded',
        'csharpProgrammaticGlowIncluded',
        'childDocumentWrapperExcluded',
        'exportedSymbolMainY',
        'hpFillDegreesPerSourceFrame',
        'mpRimVariantStarts'
    ], 'Web renderSemantics');
    if (web.renderSemantics.capturedLayerScope !==
            canonicalStaticLayerScope ||
        web.renderSemantics.coordinateSpace !==
            'main_flash_content_viewport' ||
        web.renderSemantics.csharpProgrammaticDynamicTextIncluded !==
            false ||
        web.renderSemantics.csharpProgrammaticGlowIncluded !== false ||
        web.renderSemantics.childDocumentWrapperExcluded !== true ||
        web.renderSemantics.exportedSymbolMainY !== 512 ||
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
        assertExactKeys(source, [
            'id',
            'path',
            'sha256',
            'viewBox',
            'sourceGeometryBounds',
            'registration',
            'gaugeLayerOrder',
            'blendMode',
            'opacity',
            'cacheable'
        ], `Web manifest asset[${index}]`);
        assertExactKeys(reported, [
            'id', 'path', 'bytes', 'sha256'
        ], `Web report asset[${index}]`);
        if (source.id !== expected.id ||
            source.path !== expected.path ||
            reported.id !== expected.id ||
            reported.path !== expected.path ||
            reported.sha256 !== source.sha256) {
            fail(`Web canonical asset[${index}] contract drifted.`);
        }
        const assetPath = resolveBelow(
            manifestRoot, source.path,
            `Web asset[${index}].path`);
        const tracked = tracker.read(
            assetPath, `Web asset ${source.id}`);
        const expectedSha = assertSha(
            source.sha256, `Web asset[${index}].sha256`);
        if (tracked.identity.sha256 !== expectedSha ||
            reported.bytes !== tracked.identity.bytes) {
            fail(`Web canonical asset[${index}] identity changed.`);
        }
        return {
            id:source.id,
            relativePath:source.path,
            path:tracked.identity.path,
            bytes:tracked.identity.bytes,
            sha256:tracked.identity.sha256,
            exactBytes:tracked.bytes
        };
    });
    const revisionHash = crypto.createHash('sha256');
    for (const asset of [...assets].sort((left, right) =>
        compareUtf8(left.relativePath, right.relativePath))) {
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
        assertExactKeys(actual, [
            'caseId',
            'hpVirtualFrame',
            'mpVirtualFrame',
            'path',
            'bytes',
            'sha256'
        ], `Web case ${expected.id}`);
        if (actual.caseId !== expected.id ||
            actual.hpVirtualFrame !== expected.hpFrame ||
            actual.mpVirtualFrame !== expected.mpFrame ||
            actual.path !== `${expected.id}.png`) {
            fail(`Web case/frame drifted at ${expected.id}.`);
        }
        assertPositiveSafeInteger(
            actual.bytes, `Web ${expected.id}.bytes`);
        const verified = readVerifiedPng(
            tracker,
            reportRoot,
            actual.path,
            actual.bytes,
            actual.sha256,
            `Web ${expected.id} PNG`);
        return {
            id:expected.id,
            hpFrame:expected.hpFrame,
            mpFrame:expected.mpFrame,
            path:verified.path,
            bytes:verified.bytes,
            identity:verified.identity
        };
    });
    assertExactDirectoryClosure(
        reportRoot,
        [
            path.basename(reportPath),
            ...expectedCases.map(item => `${item.id}.png`)
        ],
        'Web render root');
    return {
        manifestIdentity: {
            path:repoRelative(manifestPath),
            bytes:manifestInput.bytes.length,
            sha256:manifestInput.sha256,
            schemaVersion:manifest.schemaVersion,
            assetSetId:manifest.assetSet.id,
            assetSetRevision:manifest.assetSet.revision
        },
        assets:assets.map(({exactBytes, ...record}) => record),
        renderSemantics: {
            capturedLayerScope:
                web.renderSemantics.capturedLayerScope,
            coordinateSpace:
                web.renderSemantics.coordinateSpace,
            csharpProgrammaticDynamicTextIncluded:
                web.renderSemantics.csharpProgrammaticDynamicTextIncluded,
            csharpProgrammaticGlowIncluded:
                web.renderSemantics.csharpProgrammaticGlowIncluded,
            childDocumentWrapperExcluded:
                web.renderSemantics.childDocumentWrapperExcluded,
            exportedSymbolMainY:
                web.renderSemantics.exportedSymbolMainY
        },
        selectedArtifactCount:cases.length,
        cases
    };
}

function assertComparisonScopeClaims(report) {
    if (report.scope !== comparisonScope) {
        fail('Comparison report scope drifted.');
    }
    assertExactKeys(report.claims, [
        'acceptanceThreshold',
        'csharpWebMetricsIncludeLayerScopeDifference',
        'directEdges',
        'flashOracleAccepted',
        'humanReviewRequired',
        'limitation',
        'metricsOnly',
        'parityClaimed',
        'transitiveInferenceUsed',
        'webCapturedLayerScope',
        'webCaptureIncludesCsharpProgrammaticDynamicText',
        'webCaptureIncludesCsharpProgrammaticGlow',
        'webFlashEdgeComputed'
    ], 'Comparison report claims');
    if (report.claims.webCapturedLayerScope !==
            canonicalStaticLayerScope ||
        report.claims.webCaptureIncludesCsharpProgrammaticDynamicText !==
            false ||
        report.claims.webCaptureIncludesCsharpProgrammaticGlow !== false ||
        report.claims.csharpWebMetricsIncludeLayerScopeDifference !== true) {
        fail('Comparison report layer-scope claims drifted.');
    }
}

function validateSnapshot(
    snapshot,
    reportRoot,
    tracker,
    expectedSha,
    label,
    extraKeys = []) {
    assertExactKeys(
        snapshot,
        ['path', 'bytes', 'sha256', ...extraKeys],
        label);
    assertPositiveSafeInteger(snapshot.bytes, `${label}.bytes`);
    const snapshotPath = resolveBelow(
        reportRoot, snapshot.path, `${label}.path`);
    const tracked = tracker.read(snapshotPath, label);
    const snapshotSha = assertSha(snapshot.sha256, `${label}.sha256`);
    if (tracked.identity.bytes !== snapshot.bytes ||
        tracked.identity.sha256 !== snapshotSha ||
        (expectedSha && snapshotSha !== expectedSha)) {
        fail(`${label} identity changed.`);
    }
    return {
        path:tracked.identity.path,
        bytes:tracked.identity.bytes,
        sha256:tracked.identity.sha256
    };
}

function validateRepoBoundSnapshot(
    relativePath,
    snapshot,
    reportRoot,
    tracker,
    label) {
    const repoPath = resolveInsideRepo(relativePath, `${label}.repoPath`);
    const repoInput = tracker.read(repoPath, `${label} current repo input`);
    const verified = validateSnapshot(
        snapshot,
        reportRoot,
        tracker,
        repoInput.identity.sha256,
        `${label}.snapshot`);
    if (repoInput.identity.bytes !== verified.bytes) {
        fail(`${label} snapshot byte length differs from current repo input.`);
    }
    return {
        path:repoRelative(repoPath),
        bytes:repoInput.identity.bytes,
        sha256:repoInput.identity.sha256,
        snapshot:verified
    };
}

function validateDerivedIdentity(
    value,
    label,
    {requireExists = false} = {}) {
    assertExactKeys(value, [
        'exists', 'bytes', 'sha256', 'lastWriteUtc'
    ], label);
    if (typeof value.exists !== 'boolean') {
        fail(`${label}.exists must be boolean.`);
    }
    if (!value.exists) {
        if (requireExists) {
            fail(`${label}.exists must be true.`);
        }
        if (value.bytes !== 0 ||
            ![null, ''].includes(value.sha256) ||
            ![null, ''].includes(value.lastWriteUtc)) {
            fail(`${label} absent-file identity must be 0/null-or-empty.`);
        }
        return {
            exists:false,
            bytes:0,
            sha256:null,
            lastWriteUtc:null
        };
    }
    assertPositiveSafeInteger(value.bytes, `${label}.bytes`);
    const digest = assertSha(value.sha256, `${label}.sha256`);
    assertNonEmptyString(value.lastWriteUtc, `${label}.lastWriteUtc`);
    return {
        exists:true,
        bytes:value.bytes,
        sha256:digest,
        lastWriteUtc:value.lastWriteUtc
    };
}

function validateRestoredDerivedIdentity(value, label) {
    assertExactKeys(value, [
        'exists', 'bytes', 'sha256', 'lastWriteUtc', 'verifiedUtc'
    ], label);
    const identity = validateDerivedIdentity({
        exists:value.exists,
        bytes:value.bytes,
        sha256:value.sha256,
        lastWriteUtc:value.lastWriteUtc
    }, label);
    assertNonEmptyString(value.verifiedUtc, `${label}.verifiedUtc`);
    return {
        ...identity,
        verifiedUtc:value.verifiedUtc
    };
}

function validateFlashReceipt(
    receiptInput,
    receiptPath,
    flashInput,
    flash,
    compiled,
    original,
    restored) {
    const receipt = receiptInput.value;
    assertExactKeys(receipt, [
        'schema',
        'status',
        'runId',
        'placement',
        'manifest',
        'scratchRestoredByteExact',
        'sourceScratch',
        'derivedSwf',
        'canonicalRunSummary',
        'restoredSwfIdentityVerifiedUnderMutex',
        'compileMutexReleased',
        'requiresHumanReview'
    ], 'Flash candidate receipt');
    if (receipt.schema !==
            'cf7.player_info.flash_oracle_candidate_receipt.v2' ||
        receipt.status !== 'candidate_ready_after_restore' ||
        receipt.runId !== flash.runId ||
        receipt.scratchRestoredByteExact !== true ||
        receipt.restoredSwfIdentityVerifiedUnderMutex !== true ||
        receipt.compileMutexReleased !== true ||
        receipt.requiresHumanReview !== true) {
        fail('Flash candidate receipt boundary drifted.');
    }
    assertExactKeys(receipt.placement, [
        'placementProfile',
        'referencePlacementProfile',
        'extractionMode',
        'mainRslPlacementEquivalent',
        'mainParticipatesInCapture',
        'mainBinaryRole',
        'childDocumentWrapperApplied',
        'exportedSymbolRootTy',
        'mainPlacementY',
        'canvas'
    ], 'Flash candidate receipt placement');
    if (receipt.placement.placementProfile !==
            'main_rsl_exported_symbol_equivalent' ||
        receipt.placement.referencePlacementProfile !==
            'main_rsl_exported_symbol' ||
        receipt.placement.extractionMode !==
            'loaded_child_exported_symbol_instance' ||
        receipt.placement.mainRslPlacementEquivalent !== true ||
        receipt.placement.mainParticipatesInCapture !== false ||
        receipt.placement.mainBinaryRole !==
            'identity_chain_reference_only' ||
        receipt.placement.childDocumentWrapperApplied !== false ||
        receipt.placement.exportedSymbolRootTy !== 0 ||
        receipt.placement.mainPlacementY !== 512 ||
        JSON.stringify(receipt.placement.canvas) !==
            JSON.stringify([viewport.width, viewport.height])) {
        fail('Flash candidate receipt placement boundary drifted.');
    }
    assertExactKeys(
        receipt.manifest, ['path', 'schema', 'sha256'],
        'Flash candidate receipt manifest');
    if (receipt.manifest.path !== 'oracle-manifest.json' ||
        receipt.manifest.schema !==
            'cf7.player_info.flash_oracle_manifest.v2' ||
        assertSha(
            receipt.manifest.sha256,
            'Flash candidate receipt manifest SHA-256') !==
            flashInput.sha256) {
        fail('Flash candidate receipt does not bind the input manifest.');
    }
    assertExactKeys(receipt.derivedSwf, [
        'targetPath',
        'original',
        'compiled',
        'restored',
        'recoveryArtifactsCleared'
    ], 'Flash receipt derivedSwf');
    if (receipt.derivedSwf.targetPath !== 'scripts/TestLoader.swf' ||
        receipt.derivedSwf.recoveryArtifactsCleared !== true) {
        fail('Flash candidate receipt derived-SWF boundary drifted.');
    }
    const receiptOriginal = validateDerivedIdentity(
        receipt.derivedSwf.original,
        'Flash receipt derivedSwf.original');
    const receiptCompiled = validateDerivedIdentity(
        receipt.derivedSwf.compiled,
        'Flash receipt derivedSwf.compiled',
        {requireExists:true});
    const receiptRestored = validateRestoredDerivedIdentity(
        receipt.derivedSwf.restored,
        'Flash receipt derivedSwf.restored');
    for (const [receiptValue, manifestValue, label] of [
        [receiptOriginal, original, 'original'],
        [receiptCompiled, compiled, 'compiled'],
        [receiptRestored, restored, 'restored']
    ]) {
        if (receiptValue.exists !== manifestValue.exists ||
            receiptValue.bytes !== manifestValue.bytes ||
            receiptValue.sha256 !== manifestValue.sha256 ||
            receiptValue.lastWriteUtc !== manifestValue.lastWriteUtc) {
            fail(`Flash receipt ${label} identity differs from manifest.`);
        }
    }
    return {
        path:repoRelative(receiptPath),
        bytes:receiptInput.bytes.length,
        sha256:receiptInput.sha256,
        schema:receipt.schema,
        status:receipt.status,
        placement:receipt.placement,
        requiresHumanReview:true
    };
}

function validateFlashManifest(
    flashInput,
    flashReportPath,
    tracker) {
    const flash = flashInput.value;
    const reportRoot = path.dirname(flashReportPath);
    assertExactKeys(flash, [
        'schema',
        'status',
        'runId',
        'capturedUtc',
        'requiresHumanReview',
        'source',
        'captureTooling',
        'runtime',
        'capture',
        'transaction',
        'humanReview'
    ], 'Flash oracle manifest');
    if (flash.schema !==
            'cf7.player_info.flash_oracle_manifest.v2' ||
        flash.status !== 'candidate' ||
        flash.requiresHumanReview !== true) {
        fail('Flash input is not a candidate requiring human review.');
    }
    assertNonEmptyString(flash.runId, 'Flash runId');
    assertNonEmptyString(flash.capturedUtc, 'Flash capturedUtc');

    assertExactKeys(flash.humanReview, [
        'status', 'reviewer', 'checks', 'promotionBoundary'
    ], 'Flash humanReview');
    assertExactKeys(flash.humanReview.checks, [
        'stateCorrect',
        'noOtherHudLayers',
        'cropDoesNotEatEdges',
        'visualAestheticsAccepted'
    ], 'Flash humanReview.checks');
    if (flash.humanReview.status !== 'required' ||
        flash.humanReview.reviewer !== null ||
        Object.values(flash.humanReview.checks)
            .some(value => value !== null)) {
        fail('Flash human review is not in the untouched pending state.');
    }
    assertNonEmptyString(
        flash.humanReview.promotionBoundary,
        'Flash humanReview.promotionBoundary');

    assertExactKeys(flash.source, [
        'placementClosure',
        'sourceBinaryChain',
        'formula',
        'uiSwf',
        'mainSwf',
        'loaderSwf',
        'childRuntimeBinding',
        'captureLoaderContract',
        'compile'
    ], 'Flash source');
    assertExactKeys(flash.source.placementClosure, [
        'path',
        'evidenceRevision',
        'closureDigest',
        'placementCardinality',
        'capturedPlacementProfile',
        'referencePlacementProfile',
        'mainRslPlacementEquivalent',
        'extractionMode',
        'mainParticipatesInCapture',
        'mainBinaryRole',
        'childDocumentWrapperApplied',
        'exportedSymbolRootTy',
        'mainPlacementY',
        'standaloneDocumentWrapperMatrix',
        'mainRslReference',
        'snapshot'
    ], 'Flash source.placementClosure');
    if (flash.source.placementClosure.capturedPlacementProfile !==
            'main_rsl_exported_symbol_equivalent' ||
        flash.source.placementClosure.referencePlacementProfile !==
            'main_rsl_exported_symbol' ||
        flash.source.placementClosure.mainRslPlacementEquivalent !== true ||
        flash.source.placementClosure.extractionMode !==
            'loaded_child_exported_symbol_instance' ||
        flash.source.placementClosure.mainParticipatesInCapture !== false ||
        flash.source.placementClosure.mainBinaryRole !==
            'identity_chain_reference_only' ||
        flash.source.placementClosure.childDocumentWrapperApplied !== false ||
        flash.source.placementClosure.exportedSymbolRootTy !== 0 ||
        flash.source.placementClosure.mainPlacementY !== 512 ||
        JSON.stringify(
            flash.source.placementClosure.standaloneDocumentWrapperMatrix) !==
            JSON.stringify([1, 0, 0, 1, 0, 3])) {
        fail('Flash placement-closure capture profile drifted.');
    }
    if (flash.source.placementClosure.path !==
            'tools/player-info-hud/evidence/b0-01/closure.json' ||
        flash.source.placementClosure.evidenceRevision !== 'b0-01a-r4') {
        fail('Flash placement-closure evidence identity drifted.');
    }
    assertExactKeys(
        flash.source.placementClosure.placementCardinality,
        ['authoredDefinitionEdges', 'pathExpandedRuntimeEdges'],
        'Flash source.placementClosure.placementCardinality');
    if (flash.source.placementClosure.placementCardinality
            .authoredDefinitionEdges !== 17 ||
        flash.source.placementClosure.placementCardinality
            .pathExpandedRuntimeEdges !== 18) {
        fail('Flash placement-closure cardinality drifted.');
    }
    if (assertSha(
            flash.source.placementClosure.closureDigest,
            'Flash source.placementClosure.closureDigest') !==
        '6f4bf9f36563c1bd16993c7472c4ebf49321852ab19eebb0bdf6b58df9264368') {
        fail('Flash placement-closure digest drifted.');
    }
    assertExactKeys(flash.source.placementClosure.mainRslReference, [
        'placementProfile',
        'exportedSymbolRootMatrix',
        'hpRelativeMatrix',
        'mpRelativeMatrix'
    ], 'Flash source.placementClosure.mainRslReference');
    if (flash.source.placementClosure.mainRslReference.placementProfile !==
            'main_rsl_exported_symbol' ||
        JSON.stringify(
            flash.source.placementClosure.mainRslReference
                .exportedSymbolRootMatrix) !==
            JSON.stringify([1, 0, 0, 1, 0, 0]) ||
        JSON.stringify(
            flash.source.placementClosure.mainRslReference
                .hpRelativeMatrix) !==
            JSON.stringify([
                0.847213745117188,
                0,
                0,
                0.847213745117188,
                37.75,
                2.65
            ]) ||
        JSON.stringify(
            flash.source.placementClosure.mainRslReference
                .mpRelativeMatrix) !==
            JSON.stringify([
                1.0810546875,
                0,
                0,
                1.0810546875,
                90.1,
                -4.3
            ])) {
        fail('Flash main-RSL reference profile drifted.');
    }
    assertExactKeys(
        flash.source.uiSwf,
        ['path', 'sha256', 'executionRole', 'snapshot'],
        'Flash source.uiSwf');
    assertExactKeys(
        flash.source.mainSwf,
        [
            'path',
            'sha256',
            'executionRole',
            'mainParticipatesInCapture',
            'snapshot'
        ],
        'Flash source.mainSwf');
    assertExactKeys(
        flash.source.loaderSwf, ['path', 'sha256', 'snapshot'],
        'Flash source.loaderSwf');
    const childSha = assertSha(
        flash.source.uiSwf.sha256, 'Flash UI SWF SHA-256');
    const loaderSha = assertSha(
        flash.source.loaderSwf.sha256,
        'Flash loader SWF SHA-256');
    if (flash.source.uiSwf.path !==
            'flashswf/UI/玩家信息界面.swf' ||
        flash.source.uiSwf.executionRole !==
            'loaded_exported_symbol_source' ||
        flash.source.mainSwf.path !==
            'CRAZYFLASHER7MercenaryEmpire.swf' ||
        flash.source.mainSwf.executionRole !==
            'identity_chain_reference_only' ||
        flash.source.mainSwf.mainParticipatesInCapture !== false ||
        flash.source.loaderSwf.path !== 'scripts/TestLoader.swf') {
        fail('Flash child/main-reference/candidate-loader roles drifted.');
    }
    const mainSha = assertSha(
        flash.source.mainSwf.sha256, 'Flash main SWF SHA-256');

    assertExactKeys(flash.source.sourceBinaryChain, [
        'path',
        'evidenceRevision',
        'childSha256',
        'mainSha256',
        'captureContractRole',
        'snapshot'
    ], 'Flash sourceBinaryChain');
    if (assertSha(
        flash.source.sourceBinaryChain.childSha256,
        'Flash sourceBinaryChain.childSha256') !== childSha ||
        assertSha(
            flash.source.sourceBinaryChain.mainSha256,
            'Flash sourceBinaryChain.mainSha256') !== mainSha ||
        flash.source.sourceBinaryChain.captureContractRole !==
            'historical_pre_v2_plan_and_identity_chain_only') {
        fail('Flash source binary chain does not bind child/main roles.');
    }
    if (flash.source.sourceBinaryChain.path !==
            'tools/player-info-hud/evidence/b0-01/source-binary-chain.json' ||
        flash.source.sourceBinaryChain.evidenceRevision !== 'b0-01a-r4') {
        fail('Flash source binary chain evidence identity drifted.');
    }
    const placementEvidence = validateRepoBoundSnapshot(
        flash.source.placementClosure.path,
        flash.source.placementClosure.snapshot,
        reportRoot,
        tracker,
        'Flash placement closure');
    const sourceBinaryEvidence = validateRepoBoundSnapshot(
        flash.source.sourceBinaryChain.path,
        flash.source.sourceBinaryChain.snapshot,
        reportRoot,
        tracker,
        'Flash source binary chain');
    assertExactKeys(
        flash.source.formula,
        ['path', 'snapshot'],
        'Flash source.formula');
    if (flash.source.formula.path !==
            'scripts/展现/UI交互/UI交互_fs_玩家信息界面.as') {
        fail('Flash display formula path drifted.');
    }
    const formulaEvidence = validateRepoBoundSnapshot(
        flash.source.formula.path,
        flash.source.formula.snapshot,
        reportRoot,
        tracker,
        'Flash display formula');
    assertExactKeys(flash.source.childRuntimeBinding, [
        'expectedRepoRelativePath',
        'exactCanonicalMatch',
        'escapedUrlSha256',
        'reportedUrlSha256',
        'canonicalPathSha256'
    ], 'Flash childRuntimeBinding');
    if (flash.source.childRuntimeBinding.expectedRepoRelativePath !==
            flash.source.uiSwf.path ||
        flash.source.childRuntimeBinding.exactCanonicalMatch !== true) {
        fail('Flash runtime child did not bind the canonical UI SWF.');
    }
    for (const key of [
        'escapedUrlSha256',
        'reportedUrlSha256',
        'canonicalPathSha256'
    ]) {
        assertSha(
            flash.source.childRuntimeBinding[key],
            `Flash childRuntimeBinding.${key}`);
    }

    assertExactKeys(flash.source.captureLoaderContract, [
        'actualCaptureLoaderVerified',
        'actualLoaderPath',
        'childPathVerified',
        'placementProfile',
        'referencePlacementProfile',
        'extractionMode',
        'mainRslPlacementEquivalent',
        'mainParticipatesInCapture',
        'mainBinaryRole',
        'asLoaderParticipatesInCapture',
        'childDocumentWrapperApplied',
        'exportedSymbolRootTy',
        'mainPlacementY'
    ], 'Flash captureLoaderContract');
    if (flash.source.captureLoaderContract
            .actualCaptureLoaderVerified !== true ||
        flash.source.captureLoaderContract.actualLoaderPath !==
            flash.source.loaderSwf.path ||
        flash.source.captureLoaderContract.childPathVerified !==
            flash.source.uiSwf.path ||
        flash.source.captureLoaderContract.placementProfile !==
            'main_rsl_exported_symbol_equivalent' ||
        flash.source.captureLoaderContract.referencePlacementProfile !==
            'main_rsl_exported_symbol' ||
        flash.source.captureLoaderContract.extractionMode !==
            'loaded_child_exported_symbol_instance' ||
        flash.source.captureLoaderContract
            .mainRslPlacementEquivalent !== true ||
        flash.source.captureLoaderContract
            .mainParticipatesInCapture !== false ||
        flash.source.captureLoaderContract.mainBinaryRole !==
            'identity_chain_reference_only' ||
        flash.source.captureLoaderContract
            .asLoaderParticipatesInCapture !== false ||
        flash.source.captureLoaderContract
            .childDocumentWrapperApplied !== false ||
        flash.source.captureLoaderContract.exportedSymbolRootTy !== 0 ||
        flash.source.captureLoaderContract.mainPlacementY !== 512) {
        fail('Flash capture loader/child boundary drifted.');
    }

    const childRepoPath = resolveInsideRepo(
        flash.source.uiSwf.path, 'Flash UI SWF path');
    const childRepo = tracker.read(childRepoPath, 'Flash canonical UI SWF');
    if (childRepo.identity.sha256 !== childSha) {
        fail('Flash canonical UI SWF bytes changed.');
    }
    const childSnapshot = validateSnapshot(
        flash.source.uiSwf.snapshot,
        reportRoot,
        tracker,
        childSha,
        'Flash UI SWF candidate snapshot');
    const mainRepoPath = resolveInsideRepo(
        flash.source.mainSwf.path, 'Flash main SWF path');
    const mainRepo = tracker.read(
        mainRepoPath, 'Flash main SWF identity-chain reference');
    if (mainRepo.identity.sha256 !== mainSha) {
        fail('Flash main SWF identity-chain reference bytes changed.');
    }
    const mainSnapshot = validateSnapshot(
        flash.source.mainSwf.snapshot,
        reportRoot,
        tracker,
        mainSha,
        'Flash main SWF identity-chain snapshot');
    const loaderSnapshot = validateSnapshot(
        flash.source.loaderSwf.snapshot,
        reportRoot,
        tracker,
        loaderSha,
        'Flash loader SWF candidate snapshot');

    assertExactKeys(flash.captureTooling, [
        'strictToolIdentity',
        'headCommit',
        'files'
    ], 'Flash captureTooling');
    if (flash.captureTooling.strictToolIdentity !==
            'head_index_clean_filter_equal') {
        fail('Flash capture tooling strict identity status drifted.');
    }
    const captureToolHead = assertHex(
        flash.captureTooling.headCommit,
        40,
        'Flash captureTooling.headCommit');
    const expectedCaptureTools = [
        {
            role:'capture_runner',
            path:'tools/player-info-hud/capture-flash-oracle.ps1'
        },
        {
            role:'protocol_helper',
            path:'tools/player-info-hud/flash-oracle-protocol.ps1'
        }
    ];
    if (!Array.isArray(flash.captureTooling.files) ||
        flash.captureTooling.files.length !== expectedCaptureTools.length) {
        fail('Flash capture tooling closure must contain exactly two files.');
    }
    const captureToolEvidence = expectedCaptureTools.map(
        (expected, index) => {
            const actual = flash.captureTooling.files[index];
            const label = `Flash captureTooling.files[${index}]`;
            assertExactKeys(actual, [
                'role',
                'path',
                'bytes',
                'sha256',
                'gitBlobOid',
                'gitBlobBytes',
                'gitBlobSha256',
                'snapshot'
            ], label);
            if (actual.role !== expected.role ||
                actual.path !== expected.path) {
                fail(`${label} role/path/order drifted.`);
            }
            assertPositiveSafeInteger(actual.bytes, `${label}.bytes`);
            assertPositiveSafeInteger(
                actual.gitBlobBytes,
                `${label}.gitBlobBytes`);
            const rawSha = assertSha(actual.sha256, `${label}.sha256`);
            const canonicalSha = assertSha(
                actual.gitBlobSha256,
                `${label}.gitBlobSha256`);
            const currentPath = resolveInsideRepo(
                actual.path, `${label}.path`);
            const current = tracker.read(currentPath, `${label} current`);
            if (current.identity.bytes !== actual.bytes ||
                current.identity.sha256 !== rawSha) {
                fail(`${label} current worktree bytes drifted.`);
            }
            const snapshot = validateSnapshot(
                actual.snapshot,
                reportRoot,
                tracker,
                rawSha,
                `${label}.snapshot`);
            if (snapshot.bytes !== actual.bytes) {
                fail(`${label} snapshot byte length drifted.`);
            }
            const gitBlob = readGitBlob(
                captureToolHead,
                actual.path,
                actual.gitBlobOid,
                label);
            if (gitBlob.identity.bytes !== actual.gitBlobBytes ||
                gitBlob.identity.sha256 !== canonicalSha) {
                fail(`${label} canonical Git blob identity drifted.`);
            }
            return {
                role:actual.role,
                path:actual.path,
                bytes:actual.bytes,
                sha256:rawSha,
                gitBlobOid:gitBlob.oid,
                gitBlobBytes:gitBlob.identity.bytes,
                gitBlobSha256:gitBlob.identity.sha256,
                snapshot
            };
        });

    assertExactKeys(flash.source.compile, [
        'command',
        'publishProfile',
        'compileOutput',
        'compilerErrors',
        'compiledTestLoaderSource',
        'template',
        'flashAuthoring'
    ], 'Flash source.compile');
    if (flash.source.compile.command !==
            'scripts/compile_test.ps1 -Target test -PublishOnly ' +
            '-VerifySwf scripts/TestLoader.swf') {
        fail('Flash capture compile command drifted.');
    }
    const publishProfileEvidence = validateRepoBoundSnapshot(
        'scripts/TestLoader/PublishSettings.xml',
        flash.source.compile.publishProfile,
        reportRoot,
        tracker,
        'Flash TestLoader publish profile');
    const templateEvidence = validateRepoBoundSnapshot(
        'scripts/test-runners/player-info-oracle/TestLoader.as.template',
        flash.source.compile.template,
        reportRoot,
        tracker,
        'Flash TestLoader template');
    const compileOutputSnapshot = validateSnapshot(
        flash.source.compile.compileOutput,
        reportRoot,
        tracker,
        null,
        'Flash compile output snapshot');
    const compilerErrorsSnapshot = validateSnapshot(
        flash.source.compile.compilerErrors,
        reportRoot,
        tracker,
        null,
        'Flash compiler errors snapshot');
    const compiledSourceSnapshot = validateSnapshot(
        flash.source.compile.compiledTestLoaderSource,
        reportRoot,
        tracker,
        null,
        'Flash compiled TestLoader source snapshot');
    assertExactKeys(flash.source.compile.flashAuthoring, [
        'fileName',
        'fileVersion',
        'productVersion',
        'sha256',
        'registeredTaskMatched'
    ], 'Flash source.compile.flashAuthoring');
    if (flash.source.compile.flashAuthoring.fileName !== 'Flash.exe' ||
        flash.source.compile.flashAuthoring.registeredTaskMatched !== true) {
        fail('Flash authoring identity contract drifted.');
    }
    assertNonEmptyString(
        flash.source.compile.flashAuthoring.fileVersion,
        'Flash source.compile.flashAuthoring.fileVersion');
    assertNonEmptyString(
        flash.source.compile.flashAuthoring.productVersion,
        'Flash source.compile.flashAuthoring.productVersion');
    assertSha(
        flash.source.compile.flashAuthoring.sha256,
        'Flash source.compile.flashAuthoring.sha256');

    assertExactKeys(
        flash.runtime, ['player', 'windows', 'flash', 'flashlog'],
        'Flash runtime');
    assertExactKeys(flash.runtime.player, [
        'path',
        'pathKind',
        'registeredTask',
        'registeredTaskPath',
        'registeredTaskActionMatched',
        'relativeToAuthoringRoot',
        'fileVersion',
        'productVersion',
        'bytes',
        'sha256',
        'authenticodeStatus',
        'signerThumbprint',
        'ownedProcessId',
        'naturalExit'
    ], 'Flash runtime.player');
    if (flash.runtime.player.pathKind !==
            'registered-task-relative' ||
        flash.runtime.player.registeredTaskActionMatched !== true ||
        flash.runtime.player.authenticodeStatus !== 'Valid' ||
        flash.runtime.player.naturalExit !== true) {
        fail('Flash Player runtime identity/natural-exit contract drifted.');
    }
    assertNonEmptyString(
        flash.runtime.player.path, 'Flash runtime.player.path');
    assertNonEmptyString(
        flash.runtime.player.fileVersion,
        'Flash runtime.player.fileVersion');
    assertPositiveSafeInteger(
        flash.runtime.player.bytes, 'Flash runtime.player.bytes');
    const playerSha = assertSha(
        flash.runtime.player.sha256, 'Flash Player SHA-256');
    assertHex(
        flash.runtime.player.signerThumbprint,
        40,
        'Flash Player signer thumbprint');

    assertExactKeys(flash.runtime.flashlog, [
        'watermark',
        'consumptionMode',
        'finalFullLength',
        'finalFullSha256',
        'stablePolls',
        'stabilityPollMilliseconds',
        'freshSnapshot',
        'exactRunBlock',
        'canonicalRunSummary',
        'canonicalRunSummaryRecordCount',
        'physicalRecordCount'
    ], 'Flash runtime.flashlog');
    assertExactKeys(flash.runtime.flashlog.watermark, [
        'exists', 'length', 'sha256', 'lastWriteUtc'
    ], 'Flash runtime.flashlog.watermark');
    if (flash.runtime.flashlog.watermark.exists !== true ||
        !Number.isSafeInteger(flash.runtime.flashlog.watermark.length) ||
        flash.runtime.flashlog.watermark.length < 0) {
        fail('Flash flashlog watermark identity drifted.');
    }
    assertSha(
        flash.runtime.flashlog.watermark.sha256,
        'Flash runtime.flashlog.watermark.sha256');
    assertNonEmptyString(
        flash.runtime.flashlog.watermark.lastWriteUtc,
        'Flash runtime.flashlog.watermark.lastWriteUtc');
    if (![
        'exact_prefix_tail',
        'post_launch_rewrite'
    ].includes(flash.runtime.flashlog.consumptionMode)) {
        fail('Flash flashlog consumption mode drifted.');
    }
    assertPositiveSafeInteger(
        flash.runtime.flashlog.finalFullLength,
        'Flash runtime.flashlog.finalFullLength');
    const finalFullSha = assertSha(
        flash.runtime.flashlog.finalFullSha256,
        'Flash runtime.flashlog.finalFullSha256');
    assertPositiveSafeInteger(
        flash.runtime.flashlog.stablePolls,
        'Flash runtime.flashlog.stablePolls');
    assertPositiveSafeInteger(
        flash.runtime.flashlog.stabilityPollMilliseconds,
        'Flash runtime.flashlog.stabilityPollMilliseconds');
    const freshFlashlogSnapshot = validateSnapshot(
        flash.runtime.flashlog.freshSnapshot,
        reportRoot,
        tracker,
        finalFullSha,
        'Flash fresh flashlog snapshot',
        ['localOnlyDoNotPromote', 'mayContainEscapedAbsolutePath']);
    if (flash.runtime.flashlog.freshSnapshot.localOnlyDoNotPromote !== true ||
        flash.runtime.flashlog.freshSnapshot
            .mayContainEscapedAbsolutePath !== true ||
        freshFlashlogSnapshot.bytes !==
            flash.runtime.flashlog.finalFullLength) {
        fail('Flash fresh flashlog snapshot policy/length drifted.');
    }
    const exactRunBlockSnapshot = validateSnapshot(
        flash.runtime.flashlog.exactRunBlock,
        reportRoot,
        tracker,
        null,
        'Flash exact oracle run-block snapshot',
        ['localOnlyDoNotPromote', 'mayContainEscapedAbsolutePath']);
    if (flash.runtime.flashlog.exactRunBlock.localOnlyDoNotPromote !== true ||
        flash.runtime.flashlog.exactRunBlock
            .mayContainEscapedAbsolutePath !== true) {
        fail('Flash exact run-block local-only policy drifted.');
    }
    const canonicalRunSummarySnapshot = validateSnapshot(
        flash.runtime.flashlog.canonicalRunSummary,
        reportRoot,
        tracker,
        null,
        'Flash canonical run summary snapshot',
        ['promotable']);
    if (flash.runtime.flashlog.canonicalRunSummary.promotable !== true ||
        flash.runtime.flashlog.canonicalRunSummaryRecordCount !== 14) {
        fail('Flash canonical run summary contract drifted.');
    }
    assertPositiveSafeInteger(
        flash.runtime.flashlog.physicalRecordCount,
        'Flash runtime.flashlog.physicalRecordCount');

    assertExactKeys(flash.capture, [
        'captureMethod', 'protocol', 'canvas', 'cases'
    ], 'Flash capture');
    assertExactKeys(flash.capture.canvas, [
        'width',
        'height',
        'matrix',
        'coordinateSpace',
        'contentViewport',
        'source',
        'sourceDocumentInstanceMatrix',
        'childDocumentWrapperApplied',
        'pixelFormat',
        'background',
        'compositeBackgroundId'
    ], 'Flash capture.canvas');
    if (flash.capture.captureMethod !== 'AVM1 BitmapData.draw' ||
        flash.capture.canvas.width !== viewport.width ||
        flash.capture.canvas.height !== viewport.height ||
        JSON.stringify(flash.capture.canvas.matrix) !==
            JSON.stringify([1, 0, 0, 1, 0, 512]) ||
        flash.capture.canvas.coordinateSpace !== 'main_stage' ||
        JSON.stringify(flash.capture.canvas.contentViewport) !==
            JSON.stringify([0, 0, viewport.width, viewport.height]) ||
        flash.capture.canvas.source !==
            'loaded_child_exported_symbol_instance' ||
        JSON.stringify(flash.capture.canvas.sourceDocumentInstanceMatrix) !==
            JSON.stringify([1, 0, 0, 1, 0, 3]) ||
        flash.capture.canvas.childDocumentWrapperApplied !== false ||
        flash.capture.canvas.pixelFormat !== 'straight_argb32' ||
        flash.capture.canvas.background !== 'transparent_argb_0' ||
        flash.capture.canvas.compositeBackgroundId !== null) {
        fail('Flash candidate capture canvas contract drifted.');
    }
    assertExactKeys(flash.capture.protocol, [
        'rowBytes',
        'rowsPerCase',
        'partPayloadChars',
        'partsPerRow',
        'zeroRowRecord',
        'zeroRowValue',
        'observedPartRecords',
        'observedClearRecords',
        'physicalRecordMaxChars',
        'caseOrder'
    ], 'Flash capture.protocol');
    if (flash.capture.protocol.rowBytes !== 4096 ||
        flash.capture.protocol.rowsPerCase !== viewport.height ||
        flash.capture.protocol.partPayloadChars !== 720 ||
        flash.capture.protocol.partsPerRow !== 8 ||
        flash.capture.protocol.zeroRowRecord !== 'CLEAR' ||
        flash.capture.protocol.zeroRowValue !== '00000000' ||
        !Number.isSafeInteger(
            flash.capture.protocol.observedPartRecords) ||
        flash.capture.protocol.observedPartRecords < 0 ||
        !Number.isSafeInteger(
            flash.capture.protocol.observedClearRecords) ||
        flash.capture.protocol.observedClearRecords < 0 ||
        flash.capture.protocol.physicalRecordMaxChars !== 1000) {
        fail('Flash capture protocol contract drifted.');
    }
    if (flash.capture.protocol.observedPartRecords % 8 !== 0 ||
        (flash.capture.protocol.observedPartRecords / 8) +
            flash.capture.protocol.observedClearRecords !==
            expectedCases.length * viewport.height ||
        flash.runtime.flashlog.physicalRecordCount !==
            flash.capture.protocol.observedPartRecords +
            flash.capture.protocol.observedClearRecords +
            flash.runtime.flashlog.canonicalRunSummaryRecordCount) {
        fail('Flash capture physical-record accounting drifted.');
    }
    assertJsonEqual(
        flash.capture.protocol.caseOrder,
        expectedCases.map(item => item.id),
        'Flash capture case order');
    if (!Array.isArray(flash.capture.cases) ||
        flash.capture.cases.length !== expectedCases.length) {
        fail('Flash candidate is not the exact 11-case corpus.');
    }
    const cases = expectedCases.map((expected, index) => {
        const actual = flash.capture.cases[index];
        const label = `Flash case ${expected.id}`;
        assertExactKeys(actual, [
            'caseId', 'state', 'rawArgbSha256', 'raw', 'crop'
        ], label);
        assertExactKeys(actual.raw, [
            'path', 'width', 'height', 'sha256'
        ], `${label}.raw`);
        if (actual.caseId !== expected.id ||
            actual.raw.path !== `${expected.id}.raw.png` ||
            actual.raw.width !== viewport.width ||
            actual.raw.height !== viewport.height) {
            fail(`${label} raw path/dimension contract drifted.`);
        }
        assertSha(actual.rawArgbSha256, `${label}.rawArgbSha256`);
        const state = actual.state;
        if (!isPlainObject(state) ||
            state.hpTargetFrame !== expected.hpFrame ||
            state.hpCurrentFrame !== expected.hpFrame ||
            state.mpTargetFrame !== expected.mpFrame ||
            state.mpCurrentFrame !== expected.mpFrame ||
            state.outOfScopeHidden !== true) {
            fail(`${label} state/frame contract drifted.`);
        }
        const verified = readVerifiedPng(
            tracker,
            reportRoot,
            actual.raw.path,
            null,
            actual.raw.sha256,
            `${label} raw PNG`);
        assertExactKeys(actual.crop, [
            'path', 'rectangle', 'sha256'
        ], `${label}.crop`);
        if (actual.crop.path !== `${expected.id}.crop.png`) {
            fail(`${label} crop path drifted.`);
        }
        assertRect(
            actual.crop.rectangle,
            null,
            `${label}.crop.rectangle`);
        const cropRectangle = actual.crop.rectangle;
        if (cropRectangle.x < 0 ||
            cropRectangle.y < 0 ||
            cropRectangle.x + cropRectangle.width > viewport.width ||
            cropRectangle.y + cropRectangle.height > viewport.height) {
            fail(
                `${label} crop escapes the raw ` +
                `${viewport.width}x${viewport.height} main-stage canvas.`);
        }
        const verifiedCrop = readVerifiedPng(
            tracker,
            reportRoot,
            actual.crop.path,
            null,
            actual.crop.sha256,
            `${label} crop PNG`,
            cropRectangle.width,
            cropRectangle.height);
        return {
            id:expected.id,
            hpFrame:expected.hpFrame,
            mpFrame:expected.mpFrame,
            path:verified.path,
            bytes:verified.bytes,
            identity:verified.identity,
            rawArgbSha256:
                assertSha(actual.rawArgbSha256, `${label}.rawArgbSha256`),
            crop: {
                rectangle:cropRectangle,
                identity:verifiedCrop.identity
            }
        };
    });

    assertExactKeys(flash.transaction, [
        'sourceScratch',
        'derivedSwf',
        'scratchRestoredByteExact',
        'restoredSwfIdentityVerifiedUnderMutex',
        'compileMutexReleasedBeforeCandidatePromotion'
    ], 'Flash transaction');
    if (flash.transaction.scratchRestoredByteExact !== true ||
        flash.transaction.restoredSwfIdentityVerifiedUnderMutex !== true ||
        flash.transaction
            .compileMutexReleasedBeforeCandidatePromotion !== true) {
        fail('Flash compile/restore transaction is incomplete.');
    }
    assertExactKeys(flash.transaction.sourceScratch, [
        'markerPath',
        'markerBodySha256',
        'originalExisted',
        'originalSha256',
        'installedSha256',
        'restoredByteExact'
    ], 'Flash transaction.sourceScratch');
    if (flash.transaction.sourceScratch.markerPath !==
            'scripts/testloader_scratch_inflight.marker' ||
        typeof flash.transaction.sourceScratch.originalExisted !== 'boolean' ||
        flash.transaction.sourceScratch.restoredByteExact !== true) {
        fail('Flash source-scratch transaction contract drifted.');
    }
    const sourceMarkerSha = assertSha(
        flash.transaction.sourceScratch.markerBodySha256,
        'Flash transaction.sourceScratch.markerBodySha256');
    let originalSourceSha = null;
    if (flash.transaction.sourceScratch.originalExisted) {
        originalSourceSha = assertSha(
            flash.transaction.sourceScratch.originalSha256,
            'Flash transaction.sourceScratch.originalSha256');
    } else if (flash.transaction.sourceScratch.originalSha256 !== null) {
        fail(
            'Flash transaction.sourceScratch.originalSha256 must be null ' +
            'when the original source did not exist.');
    }
    const installedSourceSha = assertSha(
        flash.transaction.sourceScratch.installedSha256,
        'Flash transaction.sourceScratch.installedSha256');
    assertExactKeys(flash.transaction.derivedSwf, [
        'schema',
        'token',
        'targetPath',
        'sourceMarkerSha256',
        'original',
        'compiled',
        'restored',
        'sidecarAndBackupClearedAfterSourceRestore'
    ], 'Flash transaction.derivedSwf');
    if (flash.transaction.derivedSwf.schema !==
            'cf7.player_info.derived_swf_transaction.v1' ||
        flash.transaction.derivedSwf.targetPath !==
            flash.source.loaderSwf.path ||
        flash.transaction.derivedSwf
            .sidecarAndBackupClearedAfterSourceRestore !== true) {
        fail('Flash derived-SWF transaction contract drifted.');
    }
    const original = validateDerivedIdentity(
        flash.transaction.derivedSwf.original,
        'Flash transaction derivedSwf.original');
    const compiled = validateDerivedIdentity(
        flash.transaction.derivedSwf.compiled,
        'Flash transaction derivedSwf.compiled',
        {requireExists:true});
    const restored = validateRestoredDerivedIdentity(
        flash.transaction.derivedSwf.restored,
        'Flash transaction derivedSwf.restored');
    if (original.exists !== restored.exists ||
        original.bytes !== restored.bytes ||
        original.sha256 !== restored.sha256 ||
        original.lastWriteUtc !== restored.lastWriteUtc ||
        compiled.bytes !== loaderSnapshot.bytes ||
        compiled.sha256 !== loaderSha) {
        fail('Flash candidate loader snapshot/restore identities disagree.');
    }

    const receiptPath = path.join(reportRoot, 'candidate-receipt.json');
    const receiptInput = readTrackedJson(
        tracker, receiptPath, 'Flash candidate receipt');
    const receipt = validateFlashReceipt(
        receiptInput,
        receiptPath,
        flashInput,
        flash,
        compiled,
        original,
        restored);
    assertExactKeys(receiptInput.value.sourceScratch, [
        'markerBodySha256',
        'originalSha256',
        'installedSha256',
        'restoredByteExact'
    ], 'Flash receipt sourceScratch');
    if (assertSha(
            receiptInput.value.sourceScratch.markerBodySha256,
            'Flash receipt sourceScratch.markerBodySha256') !==
            sourceMarkerSha ||
        (originalSourceSha === null
            ? receiptInput.value.sourceScratch.originalSha256 !== null
            : assertSha(
                receiptInput.value.sourceScratch.originalSha256,
                'Flash receipt sourceScratch.originalSha256') !==
                originalSourceSha) ||
        assertSha(
            receiptInput.value.sourceScratch.installedSha256,
            'Flash receipt sourceScratch.installedSha256') !==
            installedSourceSha ||
        receiptInput.value.sourceScratch.restoredByteExact !== true) {
        fail('Flash receipt source-scratch cross-binding drifted.');
    }
    assertJsonEqual(
        receiptInput.value.canonicalRunSummary,
        flash.runtime.flashlog.canonicalRunSummary,
        'Flash receipt canonicalRunSummary');

    const flashSnapshotRecords = [
        flash.source.placementClosure.snapshot,
        flash.source.sourceBinaryChain.snapshot,
        flash.source.formula.snapshot,
        flash.source.uiSwf.snapshot,
        flash.source.mainSwf.snapshot,
        flash.source.loaderSwf.snapshot,
        flash.source.compile.publishProfile,
        flash.source.compile.compileOutput,
        flash.source.compile.compilerErrors,
        flash.source.compile.compiledTestLoaderSource,
        flash.source.compile.template,
        ...flash.captureTooling.files.map(file => file.snapshot),
        flash.runtime.flashlog.freshSnapshot,
        flash.runtime.flashlog.exactRunBlock,
        flash.runtime.flashlog.canonicalRunSummary
    ];
    const flashExpectedPaths = [
        path.basename(flashReportPath),
        path.basename(receiptPath),
        ...flash.capture.cases.flatMap(item => [
            item.raw.path,
            item.crop.path
        ]),
        ...flashSnapshotRecords.map(snapshot => snapshot.path)
    ];
    if (new Set(flashExpectedPaths).size !== 40) {
        fail('Flash candidate exact closure must contain 40 unique files.');
    }
    assertExactDirectoryClosure(
        reportRoot,
        flashExpectedPaths,
        'Flash candidate root');

    return {
        runId:flash.runId,
        capturedUtc:flash.capturedUtc,
        requiresHumanReview:true,
        humanReviewStatus:flash.humanReview.status,
        child: {
            path:repoRelative(childRepoPath),
            bytes:childRepo.identity.bytes,
            sha256:childRepo.identity.sha256,
            snapshot:childSnapshot,
            exactCanonicalRuntimeBinding:true
        },
        provenance: {
            placementEvidence,
            sourceBinaryEvidence,
            formulaEvidence,
            captureToolHead,
            captureTools:captureToolEvidence,
            publishProfile:publishProfileEvidence,
            template:templateEvidence,
            compileOutput:compileOutputSnapshot,
            compilerErrors:compilerErrorsSnapshot,
            compiledSource:compiledSourceSnapshot,
            freshFlashlog:freshFlashlogSnapshot,
            exactRunBlock:exactRunBlockSnapshot,
            canonicalRunSummary:canonicalRunSummarySnapshot,
            exactDirectoryFileCount:flashExpectedPaths.length
        },
        mainReference: {
            path:repoRelative(mainRepoPath),
            bytes:mainRepo.identity.bytes,
            sha256:mainRepo.identity.sha256,
            snapshot:mainSnapshot,
            executionRole:'identity_chain_reference_only',
            mainParticipatesInCapture:false
        },
        loaderCandidate: {
            targetPath:flash.source.loaderSwf.path,
            bytes:compiled.bytes,
            sha256:compiled.sha256,
            snapshot:loaderSnapshot,
            restoredOriginal: {
                exists:restored.exists,
                bytes:restored.bytes,
                sha256:restored.sha256
            }
        },
        player: {
            version:flash.runtime.player.fileVersion,
            bytes:flash.runtime.player.bytes,
            sha256:playerSha,
            authenticodeStatus:flash.runtime.player.authenticodeStatus,
            naturalExit:true
        },
        receipt,
        selectedArtifactCount:cases.length,
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

function edgePath() {
    const candidates = [
        path.join(
            process.env['ProgramFiles(x86)'] ||
                'C:\\Program Files (x86)',
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
    return candidates.find(candidate =>
        candidate && fs.existsSync(candidate));
}

function normalizedBrowserIdentity(executablePath, version, tracker) {
    const executable = tracker.read(
        executablePath, 'Microsoft Edge executable');
    return {
        family:'Microsoft Edge via Playwright chromium',
        version,
        executableBytes:executable.identity.bytes,
        executableSha256:executable.identity.sha256
    };
}

function assertBrowserMatches(actual, expected, label) {
    if (actual.family !== expected.family ||
        actual.version !== expected.version ||
        actual.executableSha256 !==
            expected.executableSha256.toLowerCase() ||
        actual.executableBytes !== expected.executableBytes) {
        fail(`${label} browser identity differs from Web rendering.`);
    }
}

async function compareEdgeCase(
    page,
    leftCase,
    rightCase,
    includeMpHorizontalAlignment) {
    const payload = {
        width:viewport.width,
        height:viewport.height,
        leftImage:dataUrl(leftCase.bytes),
        rightImage:dataUrl(rightCase.bytes),
        darkBackgroundRgb8:darkBackground.rgb8,
        mpHorizontalAlignment:includeMpHorizontalAlignment
            ? mpHorizontalAlignmentContract
            : null
    };
    return page.evaluate(async input => {
        const loadImage = source => new Promise((resolve, reject) => {
            const image = new Image();
            image.onload = () => resolve(image);
            image.onerror = () =>
                reject(new Error('PNG decode failed.'));
            image.src = source;
        });
        const makeCanvas = (width = input.width) => {
            const canvas = document.createElement('canvas');
            canvas.width = width;
            canvas.height = input.height;
            return canvas;
        };
        const [leftImage, rightImage] = await Promise.all([
            loadImage(input.leftImage),
            loadImage(input.rightImage)
        ]);
        for (const [label, image] of [
            ['left', leftImage],
            ['right', rightImage]
        ]) {
            if (image.naturalWidth !== input.width ||
                image.naturalHeight !== input.height) {
                throw new Error(
                    `${label} image decoded at an unexpected size.`);
            }
        }
        const decode = image => {
            const canvas = makeCanvas();
            const context = canvas.getContext(
                '2d', {alpha:true, willReadFrequently:true});
            context.clearRect(0, 0, input.width, input.height);
            context.drawImage(image, 0, 0);
            return context.getImageData(
                0, 0, input.width, input.height);
        };
        const leftPixels = decode(leftImage);
        const rightPixels = decode(rightImage);
        const channelNamesRgba = ['red', 'green', 'blue', 'alpha'];
        const channelNamesRgb = ['red', 'green', 'blue'];

        const differenceMetrics = (
            left,
            right,
            channelNames,
            stride) => {
            const perChannel = Object.fromEntries(channelNames.map(
                name => [
                    name,
                    {
                        changedSampleCount:0,
                        sumAbsoluteError:0,
                        sumSquaredError:0,
                        maxAbsoluteError:0
                    }
                ]));
            let changedPixelCount = 0;
            let changedSampleCount = 0;
            let sumAbsoluteError = 0;
            let sumSquaredError = 0;
            let maxAbsoluteChannelError = 0;
            let changedLeft = input.width;
            let changedTop = input.height;
            let changedRight = -1;
            let changedBottom = -1;
            const totalPixels = input.width * input.height;
            for (let pixel = 0; pixel < totalPixels; pixel++) {
                const offset = pixel * stride;
                let pixelChanged = false;
                for (let channel = 0;
                    channel < channelNames.length;
                    channel++) {
                    const difference = Math.abs(
                        left[offset + channel] -
                        right[offset + channel]);
                    const accumulator =
                        perChannel[channelNames[channel]];
                    accumulator.sumAbsoluteError += difference;
                    accumulator.sumSquaredError +=
                        difference * difference;
                    accumulator.maxAbsoluteError = Math.max(
                        accumulator.maxAbsoluteError, difference);
                    sumAbsoluteError += difference;
                    sumSquaredError += difference * difference;
                    maxAbsoluteChannelError = Math.max(
                        maxAbsoluteChannelError, difference);
                    if (difference !== 0) {
                        accumulator.changedSampleCount++;
                        changedSampleCount++;
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
            }
            for (const accumulator of Object.values(perChannel)) {
                accumulator.meanAbsoluteError =
                    accumulator.sumAbsoluteError / totalPixels;
                accumulator.rootMeanSquaredError = Math.sqrt(
                    accumulator.sumSquaredError / totalPixels);
            }
            const totalSamples = totalPixels * channelNames.length;
            return {
                channelCount:channelNames.length,
                totalPixels,
                totalSamples,
                changedPixelCount,
                changedPixelFraction:
                    changedPixelCount / totalPixels,
                changedPixelBounds:changedRight < 0
                    ? null
                    : {
                        left:changedLeft,
                        top:changedTop,
                        rightInclusive:changedRight,
                        bottomInclusive:changedBottom,
                        width:changedRight - changedLeft + 1,
                        height:changedBottom - changedTop + 1
                    },
                changedSampleCount,
                sumAbsoluteError,
                sumSquaredError,
                meanAbsoluteError:
                    sumAbsoluteError / totalSamples,
                rootMeanSquaredError:
                    Math.sqrt(sumSquaredError / totalSamples),
                maxAbsoluteChannelError,
                perChannel
            };
        };

        const alphaProfile = data => {
            const totalPixels = input.width * input.height;
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
                totalPixels,
                nonZeroAlphaPixels,
                partialAlphaPixels,
                opaqueAlphaPixels,
                alphaSum,
                coverageFraction:nonZeroAlphaPixels / totalPixels,
                meanAlpha8:alphaSum / totalPixels,
                bounds:right < 0
                    ? null
                    : {
                        left,
                        top,
                        rightInclusive:right,
                        bottomInclusive:bottom,
                        width:right - left + 1,
                        height:bottom - top + 1
                    }
            };
        };

        const premultipliedOnTransparent = data => {
            let alphaZeroPixelCount = 0;
            let pixelsWithNonZeroRgbAtAlphaZero = 0;
            let nonZeroRgbChannelSampleCount = 0;
            let maxRgbValueAtAlphaZero = 0;
            let sumRgbValueAtAlphaZero = 0;
            for (let offset = 0; offset < data.length; offset += 4) {
                if (data[offset + 3] !== 0) {
                    continue;
                }
                alphaZeroPixelCount++;
                let pixelHasNonZeroRgb = false;
                for (let channel = 0; channel < 3; channel++) {
                    const value = data[offset + channel];
                    sumRgbValueAtAlphaZero += value;
                    maxRgbValueAtAlphaZero = Math.max(
                        maxRgbValueAtAlphaZero, value);
                    if (value !== 0) {
                        nonZeroRgbChannelSampleCount++;
                        pixelHasNonZeroRgb = true;
                    }
                }
                if (pixelHasNonZeroRgb) {
                    pixelsWithNonZeroRgbAtAlphaZero++;
                }
            }
            return {
                alphaZeroPixelCount,
                pixelsWithNonZeroRgbAtAlphaZero,
                nonZeroRgbChannelSampleCount,
                maxRgbValueAtAlphaZero,
                sumRgbValueAtAlphaZero
            };
        };

        const compositeOverDark = data => {
            const totalPixels = input.width * input.height;
            const result = new Uint8ClampedArray(totalPixels * 3);
            for (let pixel = 0; pixel < totalPixels; pixel++) {
                const sourceOffset = pixel * 4;
                const destinationOffset = pixel * 3;
                const alpha = data[sourceOffset + 3];
                for (let channel = 0; channel < 3; channel++) {
                    result[destinationOffset + channel] = Math.round(
                        (
                            data[sourceOffset + channel] * alpha +
                            input.darkBackgroundRgb8[channel] *
                                (255 - alpha)
                        ) / 255);
                }
            }
            return result;
        };

        const buildFilteredMask = (data, contract, roi) => {
            const coordinates = new Set();
            let left = input.width;
            let top = input.height;
            let right = -1;
            let bottom = -1;
            for (let y = roi.y; y < roi.y + roi.height; y++) {
                for (let x = roi.x; x < roi.x + roi.width; x++) {
                    const offset = ((y * input.width) + x) * 4;
                    const red = data[offset];
                    const green = data[offset + 1];
                    const blue = data[offset + 2];
                    const alpha = data[offset + 3];
                    if (alpha < contract.mask.alphaMinimum ||
                        green < contract.mask.greenMinimum ||
                        blue < contract.mask.blueMinimum ||
                        green - red <
                            contract.mask.greenMinusRedMinimum ||
                        blue - red <
                            contract.mask.blueMinusRedMinimum) {
                        continue;
                    }
                    coordinates.add(`${x},${y}`);
                    left = Math.min(left, x);
                    top = Math.min(top, y);
                    right = Math.max(right, x);
                    bottom = Math.max(bottom, y);
                }
            }
            return {
                coordinates,
                bounds:right < 0
                    ? null
                    : {
                        left,
                        top,
                        rightInclusive:right,
                        bottomInclusive:bottom,
                        width:right - left + 1,
                        height:bottom - top + 1
                    }
            };
        };

        const compareFractions = (left, right) => {
            if (left.union === 0 || right.union === 0) {
                if (left.union === 0 && right.union === 0) {
                    return 0;
                }
                return left.union === 0 ? -1 : 1;
            }
            const leftCross = left.intersection * right.union;
            const rightCross = right.intersection * left.union;
            return leftCross === rightCross
                ? 0
                : leftCross < rightCross
                    ? -1
                    : 1;
        };

        const horizontalAlignment = (
            leftData,
            rightData,
            contract) => {
            if (contract === null) {
                return null;
            }
            const fields = contract.fields.map(field => {
                const leftMask = buildFilteredMask(
                    leftData, contract, field.roi);
                const rightMask = buildFilteredMask(
                    rightData, contract, field.roi);
                const scores = [];
                for (let dx = contract.dxSearch.minimum;
                    dx <= contract.dxSearch.maximum;
                    dx++) {
                    let intersection = 0;
                    for (const coordinate of leftMask.coordinates) {
                        const separator = coordinate.indexOf(',');
                        const x = Number(
                            coordinate.slice(0, separator));
                        const y = coordinate.slice(separator + 1);
                        if (rightMask.coordinates.has(
                            `${x + dx},${y}`)) {
                            intersection++;
                        }
                    }
                    const union =
                        leftMask.coordinates.size +
                        rightMask.coordinates.size -
                        intersection;
                    scores.push({
                        dx,
                        intersection,
                        union,
                        jaccard:union === 0
                            ? 0
                            : intersection / union
                    });
                }
                let bestScores = [];
                for (const score of scores) {
                    if (bestScores.length === 0) {
                        bestScores = [score];
                        continue;
                    }
                    const comparison = compareFractions(
                        score, bestScores[0]);
                    if (comparison > 0) {
                        bestScores = [score];
                    } else if (comparison === 0) {
                        bestScores.push(score);
                    }
                }
                bestScores.sort((left, right) =>
                    Math.abs(left.dx) - Math.abs(right.dx) ||
                    left.dx - right.dx);
                const best = bestScores[0];
                const runners = scores
                    .filter(score => score.dx !== best.dx)
                    .sort((left, right) => {
                        const comparison = compareFractions(right, left);
                        return comparison ||
                            Math.abs(left.dx) - Math.abs(right.dx) ||
                            left.dx - right.dx;
                    });
                const runnerUp = runners[0];
                const sufficientPixels =
                    leftMask.coordinates.size >=
                        contract.minimumPixelCount &&
                    rightMask.coordinates.size >=
                        contract.minimumPixelCount;
                const sufficientSimilarity =
                    best.jaccard >= contract.minimumJaccard;
                const uniqueBest = bestScores.length === 1;
                const aligned =
                    sufficientPixels &&
                    sufficientSimilarity &&
                    uniqueBest &&
                    best.dx === 0;
                let status = 'aligned';
                if (!sufficientPixels) {
                    status = 'insufficient_pixels';
                } else if (!sufficientSimilarity) {
                    status = 'low_similarity';
                } else if (!uniqueBest) {
                    status = 'ambiguous';
                } else if (best.dx !== 0) {
                    status = 'offset';
                }
                return {
                    id:field.id,
                    roi:field.roi,
                    csharpPixelCount:leftMask.coordinates.size,
                    flashPixelCount:rightMask.coordinates.size,
                    csharpBounds:leftMask.bounds,
                    flashBounds:rightMask.bounds,
                    scores,
                    bestDx:best.dx,
                    bestDxCandidates:bestScores.map(score => score.dx),
                    bestJaccard:best.jaccard,
                    runnerUpDx:runnerUp.dx,
                    runnerUpJaccard:runnerUp.jaccard,
                    scoreMargin:
                        best.jaccard - runnerUp.jaccard,
                    status,
                    aligned
                };
            });
            return {
                caseId:'mp-p50-vf51',
                canvas:contract.canvas,
                mask:contract.mask,
                dxConvention:
                    'compare CSharp(x,y) with Flash(x+dx,y)',
                dxSearch:contract.dxSearch,
                minimumPixelCount:contract.minimumPixelCount,
                minimumJaccard:contract.minimumJaccard,
                fields,
                allFieldsAligned:
                    fields.every(field => field.aligned)
            };
        };

        const overlayPixels =
            new ImageData(input.width, input.height);
        const differencePixels =
            new ImageData(input.width, input.height);
        for (let offset = 0;
            offset < leftPixels.data.length;
            offset += 4) {
            const leftAlpha = leftPixels.data[offset + 3] / 255;
            const rightAlpha = rightPixels.data[offset + 3] / 255;
            const overlayAlpha = (leftAlpha + rightAlpha) / 2;
            const alphaDifference = Math.abs(
                leftPixels.data[offset + 3] -
                rightPixels.data[offset + 3]);
            for (let channel = 0; channel < 3; channel++) {
                const premultiplied =
                    (
                        leftPixels.data[offset + channel] * leftAlpha +
                        rightPixels.data[offset + channel] * rightAlpha
                    ) / 2;
                overlayPixels.data[offset + channel] =
                    overlayAlpha === 0
                        ? 0
                        : Math.round(premultiplied / overlayAlpha);
                const colorDifference = Math.abs(
                    leftPixels.data[offset + channel] -
                    rightPixels.data[offset + channel]);
                differencePixels.data[offset + channel] = Math.max(
                    colorDifference, alphaDifference);
            }
            overlayPixels.data[offset + 3] =
                Math.round(overlayAlpha * 255);
            differencePixels.data[offset + 3] = 255;
        }

        const overlayCanvas = makeCanvas();
        overlayCanvas.getContext('2d').putImageData(
            overlayPixels, 0, 0);
        const differenceCanvas = makeCanvas();
        differenceCanvas.getContext('2d').putImageData(
            differencePixels, 0, 0);
        const sideBySideCanvas = makeCanvas(input.width * 2);
        const sideBySideContext =
            sideBySideCanvas.getContext('2d', {alpha:true});
        sideBySideContext.clearRect(
            0, 0, input.width * 2, input.height);
        sideBySideContext.drawImage(leftImage, 0, 0);
        sideBySideContext.drawImage(
            rightImage, input.width, 0);

        const leftDark = compositeOverDark(leftPixels.data);
        const rightDark = compositeOverDark(rightPixels.data);
        return {
            artifacts: {
                sideBySidePng:
                    sideBySideCanvas.toDataURL('image/png'),
                overlay50_50Png:
                    overlayCanvas.toDataURL('image/png'),
                absoluteDiffPng:
                    differenceCanvas.toDataURL('image/png')
            },
            alpha: {
                left:alphaProfile(leftPixels.data),
                right:alphaProfile(rightPixels.data)
            },
            premultipliedOnTransparent: {
                left:premultipliedOnTransparent(leftPixels.data),
                right:premultipliedOnTransparent(rightPixels.data)
            },
            rawRgba8:differenceMetrics(
                leftPixels.data,
                rightPixels.data,
                channelNamesRgba,
                4),
            fixedDarkBackgroundRgb8:differenceMetrics(
                leftDark,
                rightDark,
                channelNamesRgb,
                3),
            mpHorizontalAlignment:horizontalAlignment(
                leftPixels.data,
                rightPixels.data,
                input.mpHorizontalAlignment)
        };
    }, payload);
}

function writePng(
    outputRoot,
    relativePath,
    bytes,
    expectedWidth,
    expectedHeight) {
    const outputPath = resolveBelow(
        outputRoot, relativePath, `output ${relativePath}`);
    if (fs.existsSync(outputPath)) {
        fail(`Output artifact unexpectedly exists: ${relativePath}`);
    }
    fs.mkdirSync(path.dirname(outputPath), {recursive:true});
    fs.writeFileSync(outputPath, bytes, {flag:'wx'});
    const actual = fs.readFileSync(outputPath);
    if (!actual.equals(bytes)) {
        fail(`Output artifact write was not byte-exact: ${relativePath}`);
    }
    assertPngSize(
        actual, expectedWidth, expectedHeight,
        `output ${relativePath}`);
    return {
        path:relativePath.replace(/\\/gu, '/'),
        width:expectedWidth,
        height:expectedHeight,
        bytes:actual.length,
        sha256:sha256(actual)
    };
}

function aggregateDifferenceMetrics(caseResults, metricKey) {
    if (caseResults.length === 0) {
        fail('Cannot aggregate an empty edge.');
    }
    const first = caseResults[0].metrics[metricKey];
    const channelNames = Object.keys(first.perChannel);
    const aggregate = {
        caseCount:caseResults.length,
        channelCount:first.channelCount,
        totalPixels:0,
        totalSamples:0,
        changedPixelCount:0,
        changedSampleCount:0,
        sumAbsoluteError:0,
        sumSquaredError:0,
        meanAbsoluteError:0,
        rootMeanSquaredError:0,
        maxAbsoluteChannelError:0,
        perChannel:Object.fromEntries(channelNames.map(name => [
            name,
            {
                changedSampleCount:0,
                sumAbsoluteError:0,
                sumSquaredError:0,
                maxAbsoluteError:0,
                meanAbsoluteError:0,
                rootMeanSquaredError:0
            }
        ]))
    };
    for (const item of caseResults) {
        const metric = item.metrics[metricKey];
        if (metric.channelCount !== aggregate.channelCount ||
            JSON.stringify(Object.keys(metric.perChannel)) !==
                JSON.stringify(channelNames)) {
            fail(`Cannot aggregate drifted ${metricKey} channel shape.`);
        }
        aggregate.totalPixels += metric.totalPixels;
        aggregate.totalSamples += metric.totalSamples;
        aggregate.changedPixelCount += metric.changedPixelCount;
        aggregate.changedSampleCount += metric.changedSampleCount;
        aggregate.sumAbsoluteError += metric.sumAbsoluteError;
        aggregate.sumSquaredError += metric.sumSquaredError;
        aggregate.maxAbsoluteChannelError = Math.max(
            aggregate.maxAbsoluteChannelError,
            metric.maxAbsoluteChannelError);
        for (const name of channelNames) {
            const source = metric.perChannel[name];
            const destination = aggregate.perChannel[name];
            destination.changedSampleCount +=
                source.changedSampleCount;
            destination.sumAbsoluteError +=
                source.sumAbsoluteError;
            destination.sumSquaredError +=
                source.sumSquaredError;
            destination.maxAbsoluteError = Math.max(
                destination.maxAbsoluteError,
                source.maxAbsoluteError);
        }
    }
    aggregate.changedPixelFraction =
        aggregate.changedPixelCount / aggregate.totalPixels;
    aggregate.meanAbsoluteError =
        aggregate.sumAbsoluteError / aggregate.totalSamples;
    aggregate.rootMeanSquaredError = Math.sqrt(
        aggregate.sumSquaredError / aggregate.totalSamples);
    const samplesPerChannel =
        aggregate.totalPixels;
    for (const destination of
        Object.values(aggregate.perChannel)) {
        destination.meanAbsoluteError =
            destination.sumAbsoluteError / samplesPerChannel;
        destination.rootMeanSquaredError = Math.sqrt(
            destination.sumSquaredError / samplesPerChannel);
    }
    return aggregate;
}

async function runDirectEdge(
    page,
    outputRoot,
    edgeId,
    leftId,
    rightId,
    leftCases,
    rightCases) {
    const caseResults = [];
    const artifacts = [];
    let mpHorizontalAlignment = null;
    for (let index = 0; index < expectedCases.length; index++) {
        const expected = expectedCases[index];
        const left = leftCases[index];
        const right = rightCases[index];
        if (left.id !== expected.id ||
            right.id !== expected.id ||
            left.hpFrame !== expected.hpFrame ||
            right.hpFrame !== expected.hpFrame ||
            left.mpFrame !== expected.mpFrame ||
            right.mpFrame !== expected.mpFrame) {
            fail(`${edgeId} case/frame mismatch at ${expected.id}.`);
        }
        const includeMpHorizontalAlignment =
            edgeId === 'csharp-flash' &&
            expected.id === mpHorizontalAlignmentContract.caseId;
        const compared = await compareEdgeCase(
            page,
            left,
            right,
            includeMpHorizontalAlignment);
        if (edgeId === 'csharp-flash') {
            const crop = right.crop && right.crop.rectangle;
            const bounds = compared.alpha.right.bounds;
            if (!crop || !bounds ||
                crop.x !== bounds.left ||
                crop.y !== bounds.top ||
                crop.width !== bounds.width ||
                crop.height !== bounds.height) {
                fail(
                    `${expected.id} Flash crop is not the decoded raw ` +
                    'alpha-tight bound.');
            }
            const canonicalTight =
                expectedViewportContracts[0].tight;
            if (crop.x < canonicalTight.x ||
                crop.y < canonicalTight.y ||
                crop.x + crop.width >
                    canonicalTight.x + canonicalTight.width ||
                crop.y + crop.height >
                    canonicalTight.y + canonicalTight.height) {
                fail(
                    `${expected.id} Flash alpha crop escapes the ` +
                    'canonical main-stage tight envelope.');
            }
        }
        let caseMpHorizontalAlignment = null;
        if (includeMpHorizontalAlignment) {
            if (compared.mpHorizontalAlignment === null ||
                mpHorizontalAlignment !== null) {
                fail(
                    'C#↔Flash MP horizontal alignment diagnostic ' +
                    'cardinality drifted.');
            }
            caseMpHorizontalAlignment = {
                ...compared.mpHorizontalAlignment,
                inputs: {
                    csharpPngSha256:left.identity.sha256,
                    flashPngSha256:right.identity.sha256
                }
            };
            mpHorizontalAlignment = caseMpHorizontalAlignment;
        } else if (compared.mpHorizontalAlignment !== null) {
            fail('Unexpected MP horizontal alignment diagnostic.');
        }
        const sideBySide = writePng(
            outputRoot,
            `${edgeId}/side-by-side/${expected.id}.png`,
            decodeDataUrl(
                compared.artifacts.sideBySidePng,
                `${edgeId} ${expected.id} side-by-side`),
            viewport.width * 2,
            viewport.height);
        const overlay = writePng(
            outputRoot,
            `${edgeId}/overlay-50-50/${expected.id}.png`,
            decodeDataUrl(
                compared.artifacts.overlay50_50Png,
                `${edgeId} ${expected.id} 50/50 overlay`),
            viewport.width,
            viewport.height);
        const absoluteDiff = writePng(
            outputRoot,
            `${edgeId}/absolute-diff/${expected.id}.png`,
            decodeDataUrl(
                compared.artifacts.absoluteDiffPng,
                `${edgeId} ${expected.id} absolute diff`),
            viewport.width,
            viewport.height);
        artifacts.push(sideBySide, overlay, absoluteDiff);
        caseResults.push({
            caseId:expected.id,
            hpVirtualFrame:expected.hpFrame,
            mpVirtualFrame:expected.mpFrame,
            inputs: {
                left: {
                    path:repoRelative(left.path),
                    bytes:left.identity.bytes,
                    sha256:left.identity.sha256
                },
                right: {
                    path:repoRelative(right.path),
                    bytes:right.identity.bytes,
                    sha256:right.identity.sha256
                }
            },
            artifacts: {
                sideBySideLeftThenRight:sideBySide,
                overlay50_50:overlay,
                absoluteDiff
            },
            metrics: {
                alpha:compared.alpha,
                premultipliedOnTransparent:
                    compared.premultipliedOnTransparent,
                rawRgba8:compared.rawRgba8,
                fixedDarkBackgroundRgb8:
                    compared.fixedDarkBackgroundRgb8
            },
            diagnostics: {
                mpHorizontalAlignment:
                    caseMpHorizontalAlignment
            }
        });
    }
    if (edgeId === 'csharp-flash' &&
        mpHorizontalAlignment === null) {
        fail('C#↔Flash MP horizontal alignment diagnostic is missing.');
    }
    if (edgeId !== 'csharp-flash' &&
        mpHorizontalAlignment !== null) {
        fail('Non-Flash edge produced an MP alignment diagnostic.');
    }
    return {
        report: {
            edgeId,
            left:leftId,
            right:rightId,
            caseCount:caseResults.length,
            aggregate: {
                rawRgba8:aggregateDifferenceMetrics(
                    caseResults, 'rawRgba8'),
                fixedDarkBackgroundRgb8:
                    aggregateDifferenceMetrics(
                        caseResults,
                        'fixedDarkBackgroundRgb8')
            },
            diagnostics: {
                mpHorizontalAlignment
            },
            cases:caseResults
        },
        artifacts
    };
}

function createOutputClosure(outputRoot, artifacts) {
    const ordered = [...artifacts].sort((left, right) =>
        compareUtf8(left.path, right.path));
    const digest = crypto.createHash('sha256');
    let totalBytes = 0;
    for (const artifact of ordered) {
        const artifactPath = resolveBelow(
            outputRoot, artifact.path, `output ${artifact.path}`);
        const bytes = fs.readFileSync(artifactPath);
        if (bytes.length !== artifact.bytes ||
            sha256(bytes) !== artifact.sha256) {
            fail(`Output artifact identity changed: ${artifact.path}`);
        }
        totalBytes += bytes.length;
        digest.update(Buffer.from(artifact.path, 'utf8'));
        digest.update(Buffer.from([0]));
        digest.update(bytes);
        digest.update(Buffer.from([0]));
    }
    return {
        fileCount:ordered.length,
        totalBytes,
        sha256:digest.digest('hex'),
        canonicalFormat:
            'sorted UTF-8 relative path + NUL + exact file bytes + NUL',
        excludesReportToAvoidSelfReference:true
    };
}

function stableValue(value) {
    if (Array.isArray(value)) {
        return value.map(stableValue);
    }
    if (isPlainObject(value)) {
        const result = {};
        for (const key of Object.keys(value).sort(compareUtf8)) {
            result[key] = stableValue(value[key]);
        }
        return result;
    }
    return value;
}

function canonicalJson(value) {
    return JSON.stringify(stableValue(value), null, 2) + '\n';
}

function writeCanonicalJson(outputPath, value) {
    const text = canonicalJson(value);
    const bytes = Buffer.from(text, 'utf8');
    if (bytes.subarray(0, 3).equals(
        Buffer.from([0xef, 0xbb, 0xbf])) ||
        bytes.includes(0x0d)) {
        fail('Canonical JSON must be UTF-8 without BOM and LF-only.');
    }
    fs.writeFileSync(outputPath, bytes, {flag:'wx'});
    const actual = fs.readFileSync(outputPath);
    if (!actual.equals(bytes)) {
        fail('Canonical report write was not byte-exact.');
    }
    JSON.parse(actual.toString('utf8'));
    return {
        path:outputPath,
        bytes:actual.length,
        sha256:sha256(actual)
    };
}

function verifyExactOutputFiles(outputRoot, artifactRecords, reportName) {
    const expected = artifactRecords
        .map(record => record.path)
        .concat(reportName)
        .sort(compareUtf8);
    const actual = [];
    const walk = directory => {
        for (const entry of fs.readdirSync(
            directory, {withFileTypes:true})) {
            const entryPath = path.join(directory, entry.name);
            if (entry.isDirectory()) {
                walk(entryPath);
            } else if (entry.isFile()) {
                actual.push(
                    path.relative(outputRoot, entryPath)
                        .replace(/\\/gu, '/'));
            } else {
                fail('Output closure contains a non-file/non-directory.');
            }
        }
    };
    walk(outputRoot);
    actual.sort(compareUtf8);
    if (JSON.stringify(actual) !== JSON.stringify(expected)) {
        fail('Output directory contains files outside the exact closure.');
    }
}

async function main() {
    if (!fs.existsSync(playwrightRoot)) {
        fail(
            'Missing repository Playwright at launcher/perf/node_modules/' +
            'playwright; no package installation is performed by this tool.');
    }
    const options = parseOptions();
    const csharpReportPath = resolveInsideRepo(
        options.csharp, 'csharp');
    const webReportPath = resolveInsideRepo(options.web, 'web');
    const flashReportPath = resolveInsideRepo(
        options.flash, 'flash');
    const outputRoot = resolveInsideRepo(options.output, 'output');
    if (new Set([
        csharpReportPath, webReportPath, flashReportPath
    ]).size !== 3) {
        fail('The three input report paths must be distinct.');
    }
    if (fs.existsSync(outputRoot)) {
        fail('Output directory already exists; use a new path.');
    }
    const outputParent = path.dirname(outputRoot);
    if (!fs.existsSync(outputParent) ||
        !fs.statSync(outputParent).isDirectory()) {
        fail('Output parent directory must already exist.');
    }
    for (const [inputRoot, label] of [
        [path.dirname(csharpReportPath), 'C# input/output'],
        [path.dirname(webReportPath), 'Web input/output'],
        [path.dirname(flashReportPath), 'Flash input/output']
    ]) {
        assertRootsDisjoint(inputRoot, outputRoot, label);
    }

    const tracker = newInputTracker();
    const comparisonTool = tracker.read(
        __filename, 'B0-06 comparison tool').identity;
    const csharpInput = readTrackedJson(
        tracker, csharpReportPath, 'C# B0-06 visual manifest');
    const webInput = readTrackedJson(
        tracker, webReportPath, 'Web canonical render report');
    const flashInput = readTrackedJson(
        tracker, flashReportPath, 'Flash oracle candidate manifest');
    const csharpValidated = validateCsharpManifest(
        csharpInput.value, csharpReportPath, tracker);
    const webValidated = validateWebReport(
        webInput.value, webReportPath, tracker);
    const flashValidated = validateFlashManifest(
        flashInput, flashReportPath, tracker);

    if (csharpValidated.assetSetId !==
            webValidated.manifestIdentity.assetSetId ||
        csharpValidated.assetSetRevision !==
            webValidated.manifestIdentity.assetSetRevision ||
        csharpValidated.exactManifestSha256 !==
            webValidated.manifestIdentity.sha256) {
        fail(
            'C# and Web inputs do not share the exact canonical ' +
            'manifest SHA and asset-set revision.');
    }
    for (let index = 0; index < expectedCases.length; index++) {
        const expected = expectedCases[index];
        for (const [label, actual] of [
            ['C#', csharpValidated.cases[index]],
            ['Web', webValidated.cases[index]],
            ['Flash', flashValidated.cases[index]]
        ]) {
            if (actual.id !== expected.id ||
                actual.hpFrame !== expected.hpFrame ||
                actual.mpFrame !== expected.mpFrame) {
                fail(`${label} cross-input case mismatch at ${expected.id}.`);
            }
        }
    }

    const installedEdge = edgePath();
    if (!installedEdge) {
        fail('Microsoft Edge executable was not found.');
    }
    const playwrightPackagePath = path.join(
        playwrightRoot, 'package.json');
    const playwrightPackage = readTrackedJson(
        tracker, playwrightPackagePath, 'Repository Playwright package');
    assertNonEmptyString(
        playwrightPackage.value.version,
        'Playwright package version');
    const playwrightIdentity = {
        path:repoRelative(playwrightPackagePath),
        version:playwrightPackage.value.version,
        bytes:playwrightPackage.bytes.length,
        sha256:playwrightPackage.sha256
    };

    const chromium = require(playwrightRoot).chromium;
    const browser = await chromium.launch({
        executablePath:installedEdge,
        headless:true
    });
    let comparisonBrowser;
    let csharpWeb;
    let csharpFlash;
    const pageErrors = [];
    try {
        comparisonBrowser = normalizedBrowserIdentity(
            installedEdge, browser.version(), tracker);
        assertBrowserMatches(
            comparisonBrowser,
            webInput.value.browser,
            'Comparison');
        const page = await browser.newPage({
            viewport,
            deviceScaleFactor:1,
            colorScheme:'dark',
            reducedMotion:'reduce'
        });
        page.on('pageerror', error =>
            pageErrors.push(error.message));
        await page.setContent(
            '<!doctype html><meta charset="utf-8">' +
            '<title>PlayerInfo B0-06 direct-edge diagnostic</title>',
            {waitUntil:'load'});
        fs.mkdirSync(outputRoot, {recursive:false});
        csharpWeb = await runDirectEdge(
            page,
            outputRoot,
            'csharp-web',
            'csharp-b0-06',
            'web-canonical-svg',
            csharpValidated.cases,
            webValidated.cases);
        csharpFlash = await runDirectEdge(
            page,
            outputRoot,
            'csharp-flash',
            'csharp-b0-06',
            'flash-candidate',
            csharpValidated.cases,
            flashValidated.cases);
        if (pageErrors.length !== 0) {
            fail(`Browser page errors: ${pageErrors.join(' | ')}`);
        }
    } finally {
        await browser.close();
    }

    tracker.verify();
    const browserAfter = normalizedBrowserIdentity(
        installedEdge, comparisonBrowser.version, tracker);
    assertBrowserMatches(
        browserAfter, comparisonBrowser, 'Post-comparison');
    assertBrowserMatches(
        browserAfter, webInput.value.browser, 'Post-comparison Web');
    tracker.verify();

    const artifacts = [
        ...csharpWeb.artifacts,
        ...csharpFlash.artifacts
    ];
    const outputClosure = createOutputClosure(
        outputRoot, artifacts);
    if (outputClosure.fileCount !==
        expectedCases.length * 2 * 3) {
        fail('Comparison output closure must contain exactly 66 PNGs.');
    }

    const report = {
        schema:
            'cf7.player_info.b0_06_csharp_web_flash_diagnostic.v2',
        schemaVersion:2,
        status:'diagnostic_awaiting_human_review',
        scope:comparisonScope,
        claims: {
            directEdges:['csharp-web', 'csharp-flash'],
            webFlashEdgeComputed:false,
            transitiveInferenceUsed:false,
            webCapturedLayerScope:
                webValidated.renderSemantics.capturedLayerScope,
            webCaptureIncludesCsharpProgrammaticDynamicText:
                webValidated.renderSemantics
                    .csharpProgrammaticDynamicTextIncluded,
            webCaptureIncludesCsharpProgrammaticGlow:
                webValidated.renderSemantics
                    .csharpProgrammaticGlowIncluded,
            csharpWebMetricsIncludeLayerScopeDifference:true,
            acceptanceThreshold:null,
            parityClaimed:false,
            flashOracleAccepted:false,
            humanReviewRequired:true,
            metricsOnly:true,
            limitation:
                'The Flash input remains an unaccepted candidate. ' +
                'The C#-to-Web edge compares the C# main-content-viewport ' +
                'fixture composite against canonical static SVG layers ' +
                'only, so ' +
                'its metrics include the scope difference from C# ' +
                'programmatic dynamic text and Glow. ' +
                'Metrics and images are diagnostic evidence only; no ' +
                'threshold, renderer-parity verdict, oracle acceptance, ' +
                'or transitive Web-to-Flash inference is applied.'
        },
        inputs: {
            identityStableBeforeAndAfter:true,
            exactCaseOrder:expectedCases.map(item => ({
                caseId:item.id,
                hpVirtualFrame:item.hpFrame,
                mpVirtualFrame:item.mpFrame
            })),
            csharp: {
                manifest: {
                    path:repoRelative(csharpReportPath),
                    bytes:csharpInput.bytes.length,
                    sha256:csharpInput.sha256,
                    schema:csharpInput.value.schema,
                    schemaVersion:csharpInput.value.schemaVersion,
                    status:csharpInput.value.status,
                    scope:csharpInput.value.scope
                },
                asset: {
                    assetSetId:csharpValidated.assetSetId,
                    revision:csharpValidated.assetSetRevision,
                    exactManifestSha256:
                        csharpValidated.exactManifestSha256,
                    renderer:csharpValidated.renderer
                },
                canvasContractPresent:
                    csharpValidated.canvasContractPresent,
                baselineGeometry:
                    csharpValidated.baselineGeometry,
                selectedArtifactCount:
                    csharpValidated.selectedArtifactCount
            },
            web: {
                report: {
                    path:repoRelative(webReportPath),
                    bytes:webInput.bytes.length,
                    sha256:webInput.sha256,
                    schema:webInput.value.schema,
                    status:webInput.value.status
                },
                manifest:webValidated.manifestIdentity,
                assets:webValidated.assets,
                renderSemantics:webValidated.renderSemantics,
                selectedArtifactCount:
                    webValidated.selectedArtifactCount
            },
            flash: {
                manifest: {
                    path:repoRelative(flashReportPath),
                    bytes:flashInput.bytes.length,
                    sha256:flashInput.sha256,
                    schema:flashInput.value.schema,
                    status:flashInput.value.status,
                    runId:flashValidated.runId,
                    capturedUtc:flashValidated.capturedUtc
                },
                requiresHumanReview:
                    flashValidated.requiresHumanReview,
                humanReviewStatus:
                    flashValidated.humanReviewStatus,
                provenance:flashValidated.provenance,
                child:flashValidated.child,
                mainReference:flashValidated.mainReference,
                loaderCandidate:flashValidated.loaderCandidate,
                player:flashValidated.player,
                receipt:flashValidated.receipt,
                selectedArtifactCount:
                    flashValidated.selectedArtifactCount
            },
            crossInput: {
                exactCaseIdsOrderAndFramesMatch:true,
                csharpAndWebAssetSetRevisionMatch:true,
                csharpAndWebExactManifestSha256Match:true,
                comparisonBrowserMatchesWebRenderBrowser:true
            }
        },
        execution: {
            viewport:[viewport.width, viewport.height],
            deviceScaleFactor:1,
            transparentCanvas:true,
            fixedDarkBackground:darkBackground,
            comparisonTool,
            browser:comparisonBrowser,
            playwright:playwrightIdentity,
            decoder:
                'Exact PNG bytes are decoded by the recorded Edge ' +
                'Canvas2D implementation into straight-alpha RGBA8.',
            networkUsed:false,
            packagesInstalled:false
        },
        metricDefinition: {
            threshold:null,
            rawRgba8:
                'Absolute differences on decoded straight-alpha RGBA8. ' +
                'A pixel changes when any included channel differs.',
            alpha:
                'Coverage counts alpha > 0; bounds use inclusive integer ' +
                'pixel coordinates.',
            premultipliedOnTransparent:
                'For decoded pixels with alpha == 0, records any non-zero ' +
                'RGB values that would violate the zero-premultiplied ' +
                'transparent-pixel invariant.',
            fixedDarkBackgroundRgb8: {
                background:darkBackground,
                composite:
                    'Opaque RGB = round((source RGB * alpha + background ' +
                    'RGB * (255 - alpha)) / 255), then direct RGB8 ' +
                    'difference metrics.'
            },
            changedPixelBounds:
                'Null when no pixel changes; otherwise inclusive bounds.',
            overlay50_50:
                'Equal-weight average in premultiplied-alpha space, then ' +
                'unpremultiplied.',
            absoluteDiff:
                'Opaque RGB; each output color channel is max(that color ' +
                'difference, alpha difference).',
            sideBySide:
                `${viewport.width * 2}x${viewport.height} transparent ` +
                'canvas in each edge declared ' +
                'left-then-right order.'
        },
        edges: {
            csharpWeb:csharpWeb.report,
            csharpFlash:csharpFlash.report
        },
        outputClosure
    };
    assertComparisonScopeClaims(report);
    const reportName =
        'csharp-web-flash-comparison-report.json';
    const reportIdentity = writeCanonicalJson(
        path.join(outputRoot, reportName), report);
    verifyExactOutputFiles(outputRoot, artifacts, reportName);
    tracker.verify();
    process.stdout.write(
        'PlayerInfo B0-06 direct-edge diagnostic: ' +
        `${expectedCases.length} cases, 2 edges, ` +
        `${outputClosure.fileCount} PNGs; ` +
        'status=diagnostic_awaiting_human_review; ' +
        'no threshold, parity, Flash-oracle acceptance, or transitive ' +
        `claim; report=${repoRelative(reportIdentity.path)}; ` +
        `reportSha256=${reportIdentity.sha256}\n`);
}

main().catch(error => {
    process.stderr.write(
        `${error && error.stack ? error.stack : error}\n`);
    process.exitCode = 1;
});
