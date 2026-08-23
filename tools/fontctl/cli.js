#!/usr/bin/env node
'use strict';

const path = require('path');
const {
    diagnostic,
    loadCatalog,
    sortDiagnostics,
    validateCatalog,
} = require('./lib/catalog');
const { validateWithXsd } = require('./lib/xsd');
const { validateManifestParity } = require('./lib/manifest');
const { validatePermanentAssets } = require('./lib/permanent');
const { scanFontDirectories } = require('./lib/scan');
const { resolveRole } = require('./lib/resolver');
const { auditUsage } = require('./lib/usage-audit');
const { generateCatalog } = require('./lib/generator');
const { syncAssets } = require('./lib/sync');

const COMMANDS = new Set(['validate', 'scan', 'resolve', 'audit-usage', 'generate', 'sync']);
const VALUE_OPTIONS = new Set(['catalog', 'schema', 'project-root', 'font-root', 'role', 'preset', 'output-root', 'asset', 'group']);
const BOOLEAN_OPTIONS = new Set(['json', 'explain', 'check']);

function parseArguments(argv) {
    if (!argv.length || argv[0].startsWith('-') || !COMMANDS.has(argv[0])) {
        const error = new Error('usage');
        error.usageMessage = '用法：fontctl <validate|scan|resolve|audit-usage|generate|sync> [--json] [--catalog PATH]';
        throw error;
    }
    const command = argv[0];
    const options = Object.create(null);
    for (let index = 1; index < argv.length; index += 1) {
        const token = argv[index];
        if (!token.startsWith('--')) {
            const error = new Error('usage');
            error.usageMessage = `无法识别的位置参数：${token}`;
            throw error;
        }
        const name = token.slice(2);
        if (Object.prototype.hasOwnProperty.call(options, name)) {
            const error = new Error('usage');
            error.usageMessage = `参数不得重复：--${name}`;
            throw error;
        }
        if (BOOLEAN_OPTIONS.has(name)) {
            options[name] = true;
            continue;
        }
        if (!VALUE_OPTIONS.has(name) || index + 1 >= argv.length || argv[index + 1].startsWith('--')) {
            const error = new Error('usage');
            error.usageMessage = VALUE_OPTIONS.has(name) ? `参数 --${name} 缺少值` : `未知参数：--${name}`;
            throw error;
        }
        options[name] = argv[index + 1];
        index += 1;
    }
    if (command === 'resolve' && !options.role) {
        const error = new Error('usage');
        error.usageMessage = 'resolve 必须提供 --role ID';
        throw error;
    }
    if (options.preset && command !== 'resolve') {
        const error = new Error('usage');
        error.usageMessage = '--preset 只适用于 resolve';
        throw error;
    }
    if (options.explain && command !== 'resolve') {
        const error = new Error('usage');
        error.usageMessage = '--explain 只适用于 resolve';
        throw error;
    }
    if (options.check && !['generate', 'sync'].includes(command)) {
        const error = new Error('usage');
        error.usageMessage = '--check 只适用于 generate / sync';
        throw error;
    }
    if ((options.asset || options.group) && command !== 'sync') {
        const error = new Error('usage');
        error.usageMessage = '--asset / --group 只适用于 sync';
        throw error;
    }
    if (options['output-root'] && command !== 'generate') {
        const error = new Error('usage');
        error.usageMessage = '--output-root 只适用于 generate';
        throw error;
    }
    return { command, options };
}

function partitionDiagnostics(diagnostics) {
    const sorted = sortDiagnostics(diagnostics);
    return {
        errors: sorted.filter((item) => item.severity === 'error'),
        warnings: sorted.filter((item) => item.severity === 'warning'),
        pilotDebt: sorted.filter((item) => item.severity === 'pilot-debt'),
    };
}

function writeResult(command, data, diagnostics, json) {
    const parts = partitionDiagnostics(diagnostics);
    const result = {
        schemaVersion: 1,
        command,
        ok: parts.errors.length === 0,
        errors: parts.errors,
        warnings: parts.warnings,
        pilotDebt: parts.pilotDebt,
        data,
    };
    if (json) {
        process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
    } else {
        const status = result.ok ? '通过' : `失败（${parts.errors.length} 项错误）`;
        process.stdout.write(`fontctl ${command}：${status}\n`);
        for (const item of [...parts.errors, ...parts.warnings, ...parts.pilotDebt]) {
            const location = item.line ? `${item.file}:${item.line}` : item.file;
            process.stdout.write(`[${item.severity}/${item.code}] ${location} ${item.message}\n`);
        }
        if (data && data.summary) process.stdout.write(`${data.summary}\n`);
    }
    process.exitCode = result.ok ? 0 : 2;
}

function resolvePath(projectRoot, value, fallback) {
    return path.resolve(projectRoot, value || fallback);
}

async function main() {
    let parsed;
    try {
        parsed = parseArguments(process.argv.slice(2));
    } catch (error) {
        const message = error.usageMessage || error.message;
        const result = {
            schemaVersion: 1,
            command: 'help',
            ok: false,
            errors: [diagnostic('USAGE', message, 'fontctl', { line: 0, column: 0 })],
            warnings: [],
            pilotDebt: [],
            data: null,
        };
        const wantsJson = process.argv.includes('--json');
        if (wantsJson) process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
        else process.stderr.write(`${message}\n`);
        process.exitCode = 64;
        return;
    }

    const { command, options } = parsed;
    const defaultProjectRoot = path.resolve(__dirname, '../..');
    const projectRoot = options['project-root']
        ? path.resolve(process.cwd(), options['project-root'])
        : defaultProjectRoot;
    const catalogFile = resolvePath(projectRoot, options.catalog, 'fonts/fonts.xml');
    const schemaFile = resolvePath(projectRoot, options.schema, 'fonts/fonts.xsd');
    const fontRoot = resolvePath(projectRoot, options['font-root'], 'fonts');
    const diagnostics = [];

    let catalog;
    try {
        catalog = loadCatalog(catalogFile);
    } catch (error) {
        diagnostics.push(error.diagnostic || diagnostic('XML_READ', `无法读取字体目录：${error.message}`, catalogFile));
        writeResult(command, null, diagnostics, Boolean(options.json));
        return;
    }

    diagnostics.push(...validateWithXsd(catalogFile, schemaFile));
    const semantic = validateCatalog(catalog);
    diagnostics.push(...semantic.diagnostics);

    let data = null;
    if (command === 'validate') {
        if (catalogFile === path.join(defaultProjectRoot, 'fonts', 'fonts.xml')) {
            const manifestFile = path.join(defaultProjectRoot, 'launcher', 'web', 'assets', 'fonts', 'font-pack-manifest.json');
            const assetDirectory = path.join(defaultProjectRoot, 'fonts', 'permanent', 'runtime');
            diagnostics.push(...validateManifestParity(catalog, manifestFile, assetDirectory));
            diagnostics.push(...validatePermanentAssets(catalog, fontRoot));
        }
        data = {
            catalog: catalogFile,
            schema: schemaFile,
            assetCount: catalog.fonts.length,
            faceCount: catalog.fonts.reduce((count, asset) => count + asset.faces.length, 0),
            roleCount: catalog.roles.length,
            presetCount: catalog.presets.length,
            declaredBytes: catalog.fonts.reduce((count, asset) => count + (asset.downloads[0] ? asset.downloads[0].bytes : 0), 0),
            shippedFallbackCount: catalog.fonts.filter((asset) => asset.shippedFallback).length,
            permanentAssetCount: catalog.fonts.filter((asset) => asset.residency === 'permanent').length,
            allowedHosts: catalog.allowedHosts.map((item) => item.name),
            summary: `${catalog.fonts.length} assets，${catalog.roles.length} roles，${catalog.presets.length} presets`,
        };
    } else if (diagnostics.some((item) => item.severity === 'error')) {
        data = { summary: '目录结构或语义无效，命令已失败关闭' };
    } else if (command === 'scan') {
        const scan = scanFontDirectories(catalog, fontRoot);
        diagnostics.push(...scan.diagnostics);
        data = {
            fontRoot,
            files: scan.files.map((item) => ({
                source: item.source,
                relative: item.relative,
                file: item.file,
                bytes: item.bytes,
                sha256: item.sha256,
                declared: item.declared,
                assetId: item.assetId,
                validFont: item.validFont,
                metadata: item.metadata,
            })),
            summary: `发现 ${scan.files.length} 个本地字体文件`,
        };
    } else if (command === 'resolve') {
        const resolution = resolveRole(catalog, semantic.maps, fontRoot, options.role, options.preset || null);
        diagnostics.push(...resolution.diagnostics);
        data = {
            role: options.role,
            preset: options.preset || null,
            candidates: resolution.candidates,
            selected: resolution.selected,
            candidateOrder: resolution.candidateOrder,
            selectionAuthority: resolution.selectionAuthority,
            parityScope: resolution.parityScope,
            authoritative: resolution.authoritative,
            hostExactSelection: resolution.hostExactSelection,
            runtimeProbePending: resolution.runtimeProbePending,
            systemAvailabilityPending: resolution.systemAvailabilityPending,
            summary: resolution.selected
                ? (!resolution.authoritative
                    ? resolution.runtimeProbePending
                        ? `${options.role} Node 暂定 fallback：${resolution.selected.source}；Host 仍须裁决 custom`
                        : `${options.role} Node 暂定 system fallback；未探测本机 family 可用性`
                    : `${options.role} Node face-major 静态首个可用候选：${resolution.selected.source}`)
                : `${options.role} 没有可用候选`,
        };
    } else if (command === 'audit-usage') {
        const audit = auditUsage(catalog, semantic.maps, projectRoot);
        diagnostics.push(...audit.diagnostics);
        data = {
            scannedFileCount: audit.files.length,
            usage: audit.usages,
            dynamicSites: audit.dynamicSites,
            catalogBoundDynamicSites: audit.catalogBoundDynamicSites,
            classificationCounts: Object.fromEntries(Object.entries(audit.classificationCounts).sort(([left], [right]) => left.localeCompare(right, 'en'))),
            excluded: audit.excluded,
            summary: `审计 ${audit.files.length} 个 C#/Web/运行时数据文件，记录 ${audit.usages.length} 个裸 family/path-glyph 引用`,
        };
    } else if (command === 'generate') {
        const outputRoot = resolvePath(projectRoot, options['output-root'], 'launcher/web/generated');
        const canonicalCatalog = path.join(projectRoot, 'fonts', 'fonts.xml');
        const compatibilityManifestPath = catalogFile === canonicalCatalog
            ? path.join(projectRoot, 'launcher', 'web', 'assets', 'fonts', 'font-pack-manifest.json')
            : null;
        const generated = generateCatalog(catalog, semantic.maps, outputRoot, Boolean(options.check), compatibilityManifestPath);
        diagnostics.push(...generated.diagnostics);
        data = {
            outputRoot,
            files: generated.files,
            sourceSha256: generated.projection.sourceSha256,
            checked: Boolean(options.check),
            summary: options.check ? '生成物与 fonts.xml 一致' : `已生成 ${generated.files.length} 个 runtime projection`,
        };
    } else if (command === 'sync') {
        const split = (value) => String(value || '').split(',').map((item) => item.trim()).filter(Boolean);
        const synced = await syncAssets(catalog, fontRoot, {
            assetIds: split(options.asset),
            groups: split(options.group),
        }, { checkOnly: Boolean(options.check) });
        diagnostics.push(...synced.diagnostics);
        data = {
            fontRoot,
            assets: synced.assets,
            checked: Boolean(options.check),
            summary: `${options.check ? '检查' : '同步'} ${synced.assets.length} 个 asset`,
        };
    }
    writeResult(command, data, diagnostics, Boolean(options.json));
}

main().catch((error) => {
    const wantsJson = process.argv.includes('--json');
    const result = {
        schemaVersion: 1,
        command: process.argv[2] || 'unknown',
        ok: false,
        errors: [diagnostic('UNEXPECTED', error && error.stack ? error.stack : String(error), 'fontctl')],
        warnings: [],
        pilotDebt: [],
        data: null,
    };
    if (wantsJson) process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
    else process.stderr.write(`${result.errors[0].message}\n`);
    process.exitCode = 70;
});
