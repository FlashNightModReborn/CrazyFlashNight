#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');
const vm = require('vm');

const projectRoot = path.resolve(__dirname, '..');
const dataFile = path.join(projectRoot, 'launcher', 'web', 'modules', 'map-panel-data.js');

function parseArgs(argv) {
    const args = {
        page: '',
        output: '',
        summary: false
    };

    for (let i = 0; i < argv.length; i += 1) {
        const arg = argv[i];
        if (arg === '--page') {
            args.page = argv[i + 1] || '';
            i += 1;
            continue;
        }
        if (arg === '--output') {
            args.output = argv[i + 1] || '';
            i += 1;
            continue;
        }
        if (arg === '--summary') {
            args.summary = true;
            continue;
        }
        if (arg === '--help' || arg === '-h') {
            printHelp(0);
            return null;
        }
        printHelp(1, 'unknown arg: ' + arg);
        return null;
    }

    return args;
}

function printHelp(exitCode, error) {
    if (error) {
        console.error(error);
    }
    console.error('usage: node tools/export-map-manifest.js [--page <id>] [--output <file>] [--summary]');
    process.exit(exitCode);
}

function loadMapData() {
    const source = fs.readFileSync(dataFile, 'utf8');
    const sandbox = { console };
    vm.createContext(sandbox);
    vm.runInContext(source, sandbox, { filename: dataFile });
    if (!sandbox.MapPanelData) {
        throw new Error('MapPanelData not found in ' + dataFile);
    }
    return sandbox.MapPanelData;
}

function buildSummary(payload, pageId) {
    if (pageId) {
        return {
            type: 'page',
            pageId: payload.id,
            sceneNodes: (payload.sceneNodes || []).length,
            hotspots: (payload.hotspots || []).length,
            markers: (payload.markers || []).length,
            flashHints: (payload.flashHints || []).length
        };
    }

    const pageIds = payload.pageOrder || [];
    let hotspotCount = 0;
    for (let i = 0; i < pageIds.length; i += 1) {
        hotspotCount += ((payload.pages[pageIds[i]] || {}).hotspots || []).length;
    }
    return {
        type: 'manifest',
        version: payload.version,
        schema: payload.schema,
        pages: pageIds.length,
        hotspots: hotspotCount
    };
}

function main() {
    const args = parseArgs(process.argv.slice(2));
    if (!args) return;

    const mapData = loadMapData();
    const pageId = args.page ? mapData.resolvePageId(args.page) : '';
    const payload = pageId ? mapData.exportPage(pageId) : mapData.exportManifest();
    const json = JSON.stringify(payload, null, 2) + '\n';

    if (args.output) {
        const outputPath = path.resolve(projectRoot, args.output);
        fs.mkdirSync(path.dirname(outputPath), { recursive: true });
        fs.writeFileSync(outputPath, json, 'utf8');
        console.error('[map-manifest] wrote ' + path.relative(projectRoot, outputPath));
    } else {
        process.stdout.write(json);
    }

    if (args.summary) {
        console.error('[map-manifest] summary ' + JSON.stringify(buildSummary(payload, pageId)));
    }
}

main();
