#!/usr/bin/env node
'use strict';
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const compiler = path.resolve(__dirname, '../scripts/node_modules/typescript/bin/tsc');
if (!fs.existsSync(compiler)) throw new Error('Run npm ci --ignore-scripts --prefix launcher/scripts first (uses the existing locked TypeScript).');
const config = path.join(__dirname, 'tsconfig.json');
const destination = path.resolve(__dirname, '../scripts/dist/tooltip-bundle.js');
const check = process.argv.includes('--check');
const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'cf7-tooltip-build-'));
const candidate = path.join(temp, 'tooltip-bundle.js');
try {
    const built = spawnSync(process.execPath, [compiler, '-p', config, '--outFile', candidate], { stdio: 'inherit' });
    if (built.status !== 0) process.exitCode = built.status || 1;
    else {
        const content = fs.readFileSync(candidate);
        if (check) {
            if (!fs.existsSync(destination) || !fs.readFileSync(destination).equals(content)) {
                throw new Error('tooltip-bundle.js is stale; run node launcher/tooltip-engine/build.cjs');
            }
            console.log(`Tooltip bundle current: ${content.length} bytes`);
        } else {
            fs.mkdirSync(path.dirname(destination), { recursive: true });
            fs.writeFileSync(destination, content);
            console.log(`Tooltip bundle built: ${content.length} bytes`);
        }
    }
} finally { fs.rmSync(temp, { recursive: true, force: true }); }
