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
    if (!alignment ||
        alignment.caseId !== 'mp-p50-vf51' ||
        !Array.isArray(alignment.fields) ||
        alignment.fields.length !== 4 ||
        typeof alignment.allFieldsAligned !== 'boolean') {
        fail('Report has no complete MP horizontal-alignment diagnostic.');
    }
    let cases = edge.cases;
    if (caseId !== null) {
        cases = cases.filter(candidate => candidate.caseId === caseId);
        if (cases.length !== 1) {
            fail(`Report has no unique csharp-flash case ${caseId}.`);
        }
    }
    return { edge, cases, alignment };
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
