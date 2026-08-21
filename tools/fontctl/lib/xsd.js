'use strict';

const childProcess = require('child_process');
const path = require('path');

function validateWithXsd(catalogPath, schemaPath) {
    const helper = path.join(__dirname, 'validate_xsd.py');
    const configured = process.env.CF7_FONTCTL_PYTHON;
    const candidates = configured
        ? [{ command: configured, prefix: [] }]
        : [
            { command: 'python3', prefix: [] },
            { command: 'python', prefix: [] },
            { command: 'py', prefix: ['-3'] },
        ];
    const failures = [];

    for (const candidate of candidates) {
        const result = childProcess.spawnSync(
            candidate.command,
            [...candidate.prefix, helper, schemaPath, catalogPath],
            { encoding: 'utf8', windowsHide: true },
        );
        if (result.error && result.error.code === 'ENOENT') continue;
        if (result.error) {
            failures.push(`${candidate.command}: ${result.error.message}`);
            continue;
        }
        if (result.status !== 0) {
            failures.push(`${candidate.command}: exit ${result.status} ${String(result.stderr || '').trim()}`);
            continue;
        }
        try {
            const parsed = JSON.parse(result.stdout);
            if (Array.isArray(parsed.diagnostics)) return parsed.diagnostics;
            failures.push(`${candidate.command}: helper output missing diagnostics`);
        } catch (error) {
            failures.push(`${candidate.command}: invalid helper JSON (${error.message})`);
        }
    }

    return [{
        severity: 'error',
        code: 'XSD_VALIDATOR_UNAVAILABLE',
        message: `无法运行 Python/lxml XSD 校验器${failures.length ? `：${failures.join('；')}` : ''}`,
        file: catalogPath,
        line: 0,
        column: 0,
        schema: schemaPath,
    }];
}

module.exports = { validateWithXsd };
