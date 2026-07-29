'use strict';

const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

const repoRoot = path.resolve(__dirname, '..', '..');
const templatePath = path.join(
    __dirname, 'visual-diagnostic-viewer.html');
const templateMarker = '__CF7_VISUAL_DIAGNOSTIC_DATA__';
const expectedReportSchema =
    'cf7.player_info.b0_06_csharp_web_flash_diagnostic.v2';
const expectedMpHorizontalAlignmentContract = {
    caseId:'mp-p50-vf51',
    canvas:{width:1024, height:576, yNormalization:0},
    dxConvention:'compare CSharp(x,y) with Flash(x+dx,y)',
    dxSearch:{minimum:-8, maximum:8, fixedDy:0},
    requiredAnchorEdgeDx:0,
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
        {
            id:'label',
            anchorEdge:'leading',
            roi:{x:91, y:514, width:30, height:16}
        },
        {
            id:'current',
            anchorEdge:'trailing',
            roi:{x:126, y:516, width:50, height:14}
        },
        {
            id:'maximum',
            anchorEdge:'leading',
            roi:{x:176, y:516, width:50, height:14}
        },
        {
            id:'percent',
            anchorEdge:'leading',
            roi:{x:86, y:530, width:31, height:13}
        }
    ]
};

function fail(message) {
    throw new Error(message);
}

function sha256(bytes) {
    return crypto.createHash('sha256').update(bytes).digest('hex');
}

function usage() {
    return [
        'Usage:',
        '  node tools/player-info-hud/build-visual-diagnostic-viewer.js',
        '    --report <csharp-web-flash-comparison-report.json>',
        '    --output <visual-diagnostic.html>',
        '    [--input-root <report repo/worktree root>]',
        '    [--case <caseId>]',
        '',
        'The output is a self-contained diagnostic review page. Keep it',
        'outside a frozen comparison output closure.'
    ].join('\n');
}

function parseArguments(argv) {
    const result = {
        report: null,
        output: null,
        inputRoot: repoRoot,
        caseId: null
    };
    for (let index = 0; index < argv.length; index++) {
        const argument = argv[index];
        if (argument === '--help' || argument === '-h') {
            process.stdout.write(`${usage()}\n`);
            process.exit(0);
        }
        const equalsIndex = argument.indexOf('=');
        const option = equalsIndex > 0
            ? argument.slice(0, equalsIndex)
            : argument;
        let value;
        if (equalsIndex > 0) {
            value = argument.slice(equalsIndex + 1);
        } else {
            value = argv[index + 1];
            index++;
        }
        if (!value || value.startsWith('--')) {
            fail(`Missing value for ${argument}.\n${usage()}`);
        }
        switch (option) {
        case '--report':
            result.report = path.resolve(value);
            break;
        case '--output':
            result.output = path.resolve(value);
            break;
        case '--input-root':
            result.inputRoot = path.resolve(value);
            break;
        case '--case':
            result.caseId = value;
            break;
        default:
            fail(`Unknown argument: ${argument}\n${usage()}`);
        }
    }
    if (!result.report || !result.output) {
        fail(`--report and --output are required.\n${usage()}`);
    }
    return result;
}

function readJson(filePath, label) {
    let bytes;
    try {
        bytes = fs.readFileSync(filePath);
    } catch (error) {
        fail(`Cannot read ${label} ${filePath}: ${error.message}`);
    }
    let value;
    try {
        value = JSON.parse(bytes.toString('utf8'));
    } catch (error) {
        fail(`Cannot parse ${label} ${filePath}: ${error.message}`);
    }
    return { bytes, value, sha256: sha256(bytes) };
}

function assertSafeInteger(value, label) {
    if (!Number.isSafeInteger(value) || value <= 0) {
        fail(`${label} must be a positive safe integer.`);
    }
}

function assertSha(value, label) {
    if (typeof value !== 'string' ||
        !/^[0-9a-f]{64}$/u.test(value)) {
        fail(`${label} must be a lowercase SHA-256.`);
    }
}

function pngDimensions(bytes, label) {
    const signature = Buffer.from([
        0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a
    ]);
    if (bytes.length < 24 ||
        !bytes.subarray(0, 8).equals(signature) ||
        bytes.toString('ascii', 12, 16) !== 'IHDR') {
        fail(`${label} is not a PNG with an IHDR header.`);
    }
    const width = bytes.readUInt32BE(16);
    const height = bytes.readUInt32BE(20);
    assertSafeInteger(width, `${label} width`);
    assertSafeInteger(height, `${label} height`);
    return { width, height };
}

function resolveInput(inputRoot, input, label, expectedCanvas) {
    if (!input || typeof input !== 'object' ||
        typeof input.path !== 'string' || input.path.length === 0) {
        fail(`${label} input identity is missing.`);
    }
    assertSafeInteger(input.bytes, `${label} bytes`);
    assertSha(input.sha256, `${label} SHA-256`);
    if (path.isAbsolute(input.path)) {
        fail(`${label} path must be relative to --input-root.`);
    }
    const absolutePath = path.resolve(
        inputRoot, input.path.replaceAll('/', path.sep));
    const relative = path.relative(inputRoot, absolutePath);
    if (relative === '..' || relative.startsWith(`..${path.sep}`) ||
        path.isAbsolute(relative)) {
        fail(`${label} path escapes --input-root: ${input.path}`);
    }
    let bytes;
    try {
        bytes = fs.readFileSync(absolutePath);
    } catch (error) {
        fail(`Cannot read ${label} ${absolutePath}: ${error.message}`);
    }
    if (bytes.length !== input.bytes) {
        fail(`${label} byte length changed: ${bytes.length} != ` +
            `${input.bytes}.`);
    }
    const actualSha = sha256(bytes);
    if (actualSha !== input.sha256) {
        fail(`${label} SHA-256 changed: ${actualSha} != ${input.sha256}.`);
    }
    const dimensions = pngDimensions(bytes, label);
    if (dimensions.width !== expectedCanvas.width ||
        dimensions.height !== expectedCanvas.height) {
        fail(`${label} canvas changed: ${dimensions.width}x` +
            `${dimensions.height} != ${expectedCanvas.width}x` +
            `${expectedCanvas.height}.`);
    }
    return {
        path: input.path,
        bytes: bytes.length,
        sha256: actualSha,
        dataUrl: `data:image/png;base64,${bytes.toString('base64')}`
    };
}

function sameExactObject(actual, expected) {
    if (!actual || typeof actual !== 'object') {
        return false;
    }
    return Object.keys(actual).length === Object.keys(expected).length &&
        Object.entries(expected).every(
            ([key, value]) => actual[key] === value);
}

function compareFractions(left, right) {
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
}

function validateReport(report, caseId) {
    if (!report || report.schema !== expectedReportSchema ||
        report.schemaVersion !== 2) {
        fail(`Expected ${expectedReportSchema} schemaVersion 2.`);
    }
    const edge = report.edges && report.edges.csharpFlash;
    if (!edge || edge.edgeId !== 'csharp-flash' ||
        !Array.isArray(edge.cases) || edge.cases.length === 0) {
        fail('Report has no csharp-flash comparison cases.');
    }
    const alignment = edge.diagnostics &&
        edge.diagnostics.mpHorizontalAlignment;
    const contract = expectedMpHorizontalAlignmentContract;
    if (!alignment ||
        alignment.caseId !== contract.caseId ||
        !sameExactObject(alignment.canvas, contract.canvas) ||
        alignment.dxConvention !== contract.dxConvention ||
        !sameExactObject(alignment.dxSearch, contract.dxSearch) ||
        !sameExactObject(alignment.mask, contract.mask) ||
        !Array.isArray(alignment.fields) ||
        alignment.fields.length !== contract.fields.length ||
        alignment.requiredAnchorEdgeDx !== contract.requiredAnchorEdgeDx ||
        alignment.minimumPixelCount !== contract.minimumPixelCount ||
        alignment.minimumJaccard !== contract.minimumJaccard ||
        typeof alignment.allFieldsAligned !== 'boolean') {
        fail('Report has no complete MP horizontal-alignment diagnostic.');
    }
    const integerOrNull = value =>
        value === null || Number.isSafeInteger(value);
    const finiteOrNull = value =>
        value === null || Number.isFinite(value);
    const nearlyEqual = (left, right) =>
        Math.abs(left - right) <=
            Number.EPSILON * Math.max(1, Math.abs(left), Math.abs(right)) * 8;
    const validBounds = (value, roi) => {
        if (!value || typeof value !== 'object' ||
            Object.keys(value).length !== 6 ||
            !Number.isSafeInteger(value.left) ||
            !Number.isSafeInteger(value.top) ||
            !Number.isSafeInteger(value.rightInclusive) ||
            !Number.isSafeInteger(value.bottomInclusive) ||
            !Number.isSafeInteger(value.width) ||
            !Number.isSafeInteger(value.height) ||
            value.rightInclusive < value.left ||
            value.bottomInclusive < value.top ||
            value.width !== value.rightInclusive - value.left + 1 ||
            value.height !== value.bottomInclusive - value.top + 1) {
            return false;
        }
        return value.left >= roi.x &&
            value.top >= roi.y &&
            value.rightInclusive < roi.x + roi.width &&
            value.bottomInclusive < roi.y + roi.height;
    };
    const validateMaskGeometry = (
        expected,
        side,
        pixelCount,
        bounds,
        centroid) => {
        if (!Number.isSafeInteger(pixelCount) ||
            pixelCount < 0 ||
            pixelCount > expected.roi.width * expected.roi.height) {
            fail(
                `MP field ${expected.id} ${side} pixel count is invalid.`);
        }
        if (pixelCount === 0) {
            if (bounds !== null || centroid !== null) {
                fail(
                    `MP field ${expected.id} ${side} empty mask must have ` +
                    'null bounds and centroid.');
            }
            return;
        }
        if (!validBounds(bounds, expected.roi) ||
            !Number.isFinite(centroid) ||
            centroid < bounds.left ||
            centroid > bounds.rightInclusive ||
            pixelCount > bounds.width * bounds.height) {
            fail(
                `MP field ${expected.id} ${side} non-empty mask geometry ` +
                'is inconsistent.');
        }
    };
    for (let index = 0; index < contract.fields.length; index++) {
        const field = alignment.fields[index];
        const expected = contract.fields[index];
        if (!field || field.id !== expected.id ||
            field.anchorEdge !== expected.anchorEdge ||
            !sameExactObject(field.roi, expected.roi) ||
            !integerOrNull(field.leadingEdgeDx) ||
            !integerOrNull(field.trailingEdgeDx) ||
            !integerOrNull(field.anchorEdgeDx) ||
            typeof field.anchorEdgeAligned !== 'boolean' ||
            typeof field.aligned !== 'boolean' ||
            !Number.isSafeInteger(field.bestDx) ||
            !Array.isArray(field.bestDxCandidates) ||
            !field.bestDxCandidates.every(
                candidate => Number.isSafeInteger(candidate)) ||
            !field.bestDxCandidates.includes(field.bestDx) ||
            new Set(field.bestDxCandidates).size !==
                field.bestDxCandidates.length ||
            !Number.isFinite(field.bestJaccard) ||
            !finiteOrNull(field.csharpWeightedCyanCentroidX) ||
            !finiteOrNull(field.flashWeightedCyanCentroidX) ||
            !finiteOrNull(field.weightedCyanCentroidDx) ||
            !Array.isArray(field.scores) ||
            field.scores.length !==
                contract.dxSearch.maximum -
                contract.dxSearch.minimum + 1) {
            fail(`MP field ${expected.id} has an invalid diagnostic shape.`);
        }
        validateMaskGeometry(
            expected,
            'C#',
            field.csharpPixelCount,
            field.csharpBounds,
            field.csharpWeightedCyanCentroidX);
        validateMaskGeometry(
            expected,
            'Flash',
            field.flashPixelCount,
            field.flashBounds,
            field.flashWeightedCyanCentroidX);
        const scores = field.scores.map((score, scoreIndex) => {
            const expectedDx =
                contract.dxSearch.minimum + scoreIndex;
            if (!score ||
                score.dx !== expectedDx ||
                !Number.isSafeInteger(score.intersection) ||
                score.intersection < 0 ||
                !Number.isSafeInteger(score.union) ||
                score.union < 0 ||
                score.intersection >
                    Math.min(
                        field.csharpPixelCount,
                        field.flashPixelCount) ||
                score.union !==
                    field.csharpPixelCount +
                    field.flashPixelCount -
                    score.intersection ||
                !Number.isFinite(score.jaccard) ||
                score.jaccard < 0 ||
                score.jaccard > 1) {
                fail(
                    `MP field ${expected.id} score dx=${expectedDx} ` +
                    'is invalid.');
            }
            const expectedJaccard = score.union === 0
                ? 0
                : score.intersection / score.union;
            if (!nearlyEqual(score.jaccard, expectedJaccard)) {
                fail(
                    `MP field ${expected.id} score dx=${expectedDx} ` +
                    'has inconsistent Jaccard data.');
            }
            return {
                dx:score.dx,
                intersection:score.intersection,
                union:score.union,
                jaccard:expectedJaccard
            };
        });
        let bestScores = [];
        for (const score of scores) {
            if (bestScores.length === 0) {
                bestScores = [score];
                continue;
            }
            const comparison = compareFractions(score, bestScores[0]);
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
        const expectedBestCandidates =
            bestScores.map(score => score.dx);
        const runners = scores
            .filter(score => score.dx !== best.dx)
            .sort((left, right) => {
                const comparison = compareFractions(right, left);
                return comparison ||
                    Math.abs(left.dx) - Math.abs(right.dx) ||
                    left.dx - right.dx;
            });
        const runnerUp = runners[0];
        if (field.bestDx !== best.dx ||
            field.bestDxCandidates.length !==
                expectedBestCandidates.length ||
            !field.bestDxCandidates.every(
                (candidate, candidateIndex) =>
                    candidate ===
                        expectedBestCandidates[candidateIndex]) ||
            !nearlyEqual(field.bestJaccard, best.jaccard) ||
            field.runnerUpDx !== runnerUp.dx ||
            !Number.isFinite(field.runnerUpJaccard) ||
            !nearlyEqual(field.runnerUpJaccard, runnerUp.jaccard) ||
            !Number.isFinite(field.scoreMargin) ||
            !nearlyEqual(
                field.scoreMargin,
                best.jaccard - runnerUp.jaccard)) {
            fail(`MP field ${expected.id} has inconsistent score summary.`);
        }
        const hasBothBounds =
            field.csharpBounds !== null &&
            field.flashBounds !== null;
        const expectedLeadingEdgeDx = hasBothBounds
            ? field.flashBounds.left - field.csharpBounds.left
            : null;
        const expectedTrailingEdgeDx = hasBothBounds
            ? field.flashBounds.rightInclusive -
                field.csharpBounds.rightInclusive
            : null;
        if (field.leadingEdgeDx !== expectedLeadingEdgeDx ||
            field.trailingEdgeDx !== expectedTrailingEdgeDx) {
            fail(`MP field ${expected.id} has inconsistent edge deltas.`);
        }
        const expectedAnchorEdgeDx = field.anchorEdge === 'leading'
            ? field.leadingEdgeDx
            : field.trailingEdgeDx;
        if (field.anchorEdgeDx !== expectedAnchorEdgeDx ||
            field.anchorEdgeAligned !==
                (field.anchorEdgeDx === alignment.requiredAnchorEdgeDx)) {
            fail(`MP field ${expected.id} has inconsistent anchor-edge data.`);
        }
        const hasBothCentroids =
            field.csharpWeightedCyanCentroidX !== null &&
            field.flashWeightedCyanCentroidX !== null;
        if (hasBothCentroids) {
            const expectedCentroidDx =
                field.flashWeightedCyanCentroidX -
                field.csharpWeightedCyanCentroidX;
            if (field.weightedCyanCentroidDx === null ||
                !nearlyEqual(
                    field.weightedCyanCentroidDx,
                    expectedCentroidDx)) {
                fail(
                    `MP field ${expected.id} has inconsistent centroid data.`);
            }
        } else if (field.weightedCyanCentroidDx !== null) {
            fail(`MP field ${expected.id} must use null centroid delta.`);
        }
        const sufficientPixels =
            field.csharpPixelCount >= contract.minimumPixelCount &&
            field.flashPixelCount >= contract.minimumPixelCount;
        const sufficientSimilarity =
            best.jaccard >= contract.minimumJaccard;
        const uniqueBest = bestScores.length === 1;
        const expectedAligned =
            sufficientPixels &&
            sufficientSimilarity &&
            uniqueBest &&
            field.anchorEdgeAligned &&
            best.dx === 0;
        let expectedStatus = 'aligned';
        if (!sufficientPixels) {
            expectedStatus = 'insufficient_pixels';
        } else if (!sufficientSimilarity) {
            expectedStatus = 'low_similarity';
        } else if (!uniqueBest) {
            expectedStatus = 'ambiguous';
        } else if (!field.anchorEdgeAligned) {
            expectedStatus = 'anchor_edge_offset';
        } else if (best.dx !== 0) {
            expectedStatus = 'offset';
        }
        if (field.aligned !== expectedAligned ||
            field.status !== expectedStatus) {
            fail(`MP field ${expected.id} has inconsistent alignment state.`);
        }
    }
    if (alignment.allFieldsAligned !==
        alignment.fields.every(field => field.aligned)) {
        fail('MP allFieldsAligned is inconsistent with its four fields.');
    }
    const alignmentCase = edge.cases.find(
        candidate => candidate.caseId === 'p50');
    if (!alignmentCase || !alignmentCase.inputs ||
        !alignmentCase.inputs.left || !alignmentCase.inputs.right ||
        !alignment.inputs ||
        alignment.inputs.csharpPngSha256 !==
            alignmentCase.inputs.left.sha256 ||
        alignment.inputs.flashPngSha256 !==
            alignmentCase.inputs.right.sha256) {
        fail('MP alignment input identity is not bound to the p50 pair.');
    }
    let cases = edge.cases;
    if (caseId !== null) {
        cases = cases.filter(candidate => candidate.caseId === caseId);
        if (cases.length !== 1) {
            fail(`Report has no unique csharp-flash case ${caseId}.`);
        }
    }
    return { edge, cases, alignment, alignmentCase };
}

function canvasFromCase(comparisonCase) {
    const artifact = comparisonCase &&
        comparisonCase.artifacts &&
        comparisonCase.artifacts.absoluteDiff;
    if (!artifact) {
        fail(`${comparisonCase.caseId} absolute-diff artifact is missing.`);
    }
    assertSafeInteger(
        artifact.width, `${comparisonCase.caseId} artifact width`);
    assertSafeInteger(
        artifact.height, `${comparisonCase.caseId} artifact height`);
    return { width: artifact.width, height: artifact.height };
}

function escapeEmbeddedJson(value) {
    return JSON.stringify(value)
        .replaceAll('<', '\\u003c')
        .replaceAll('&', '\\u0026')
        .replaceAll('\u2028', '\\u2028')
        .replaceAll('\u2029', '\\u2029');
}

function placementNormalization(report) {
    const edge = report.edges && report.edges.csharpFlash;
    if (!edge || edge.right !== 'flash-candidate') {
        fail('Report csharp-flash right input must be flash-candidate.');
    }
    return {
        id: 'native-main-stage',
        flashOffsetPixels: { x: 0, y: 0 },
        diagnosticOnly: true,
        label: 'C# / Flash 原生主舞台坐标（无平移归一化）',
        semantics:
            'Both inputs are already captured in the 1024×576 main-content ' +
            'viewport. No diagnostic translation is permitted.'
    };
}

function main() {
    const options = parseArguments(process.argv.slice(2));
    const reportInput = readJson(options.report, 'comparison report');
    const validated = validateReport(reportInput.value, options.caseId);
    const canvas = canvasFromCase(validated.cases[0]);
    const alignmentCanvas = canvasFromCase(validated.alignmentCase);
    if (alignmentCanvas.width !== canvas.width ||
        alignmentCanvas.height !== canvas.height) {
        fail('MP alignment p50 canvas differs from the selected cases.');
    }
    const alignmentCsharp = resolveInput(
        options.inputRoot,
        validated.alignmentCase.inputs.left,
        'MP alignment p50 C#',
        alignmentCanvas);
    const alignmentFlash = resolveInput(
        options.inputRoot,
        validated.alignmentCase.inputs.right,
        'MP alignment p50 Flash',
        alignmentCanvas);
    if (validated.alignment.inputs.csharpPngSha256 !==
            alignmentCsharp.sha256 ||
        validated.alignment.inputs.flashPngSha256 !==
            alignmentFlash.sha256) {
        fail('MP alignment SHA-256 values do not match the p50 PNG files.');
    }
    const caseIds = new Set();
    const cases = validated.cases.map(comparisonCase => {
        if (typeof comparisonCase.caseId !== 'string' ||
            comparisonCase.caseId.length === 0 ||
            caseIds.has(comparisonCase.caseId)) {
            fail('Comparison case IDs must be unique non-empty strings.');
        }
        caseIds.add(comparisonCase.caseId);
        const candidateCanvas = canvasFromCase(comparisonCase);
        if (candidateCanvas.width !== canvas.width ||
            candidateCanvas.height !== canvas.height) {
            fail(`${comparisonCase.caseId} canvas differs from the first ` +
                'case.');
        }
        if (!comparisonCase.inputs ||
            !comparisonCase.inputs.left ||
            !comparisonCase.inputs.right) {
            fail(`${comparisonCase.caseId} input pair is missing.`);
        }
        return {
            caseId: comparisonCase.caseId,
            hpVirtualFrame: comparisonCase.hpVirtualFrame,
            mpVirtualFrame: comparisonCase.mpVirtualFrame,
            csharp: resolveInput(
                options.inputRoot,
                comparisonCase.inputs.left,
                `${comparisonCase.caseId} C#`,
                canvas),
            flash: resolveInput(
                options.inputRoot,
                comparisonCase.inputs.right,
                `${comparisonCase.caseId} Flash`,
                canvas)
        };
    });

    const template = fs.readFileSync(templatePath, 'utf8');
    const markerCount = template.split(templateMarker).length - 1;
    if (markerCount !== 1) {
        fail(`Viewer template must contain exactly one ${templateMarker}.`);
    }
    const payload = {
        schema: 'cf7.player_info.visual_diagnostic_viewer.v2',
        canvas,
        placementNormalization: placementNormalization(reportInput.value),
        source: {
            reportPath: path.relative(options.inputRoot, options.report)
                .split(path.sep).join('/'),
            reportBytes: reportInput.bytes.length,
            reportSha256: reportInput.sha256,
            reportSchema: reportInput.value.schema,
            edgeId: validated.edge.edgeId,
            left: validated.edge.left,
            right: validated.edge.right
        },
        mpHorizontalAlignment:validated.alignment,
        defaults: {
            mode: 'blink',
            blinkHz: 2.5,
            wipeFraction: 0.5,
            zoom: 2
        },
        cases
    };
    const outputBytes = Buffer.from(
        template.replace(templateMarker, escapeEmbeddedJson(payload)),
        'utf8');
    if (options.output === templatePath ||
        options.output === options.report) {
        fail('Output must not overwrite the template or input report.');
    }
    if (fs.existsSync(options.output)) {
        fail(`Output already exists: ${options.output}`);
    }
    fs.mkdirSync(path.dirname(options.output), { recursive: true });
    fs.writeFileSync(options.output, outputBytes);
    process.stdout.write(
        `PlayerInfo visual diagnostic ${cases.length}/${cases.length} ` +
        `cases -> ${options.output}\n` +
        `bytes=${outputBytes.length} sha256=${sha256(outputBytes)}\n`);
}

try {
    main();
} catch (error) {
    process.stderr.write(`${error.stack || error.message}\n`);
    process.exitCode = 1;
}
