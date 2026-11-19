'use strict';
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const crypto = require('node:crypto');

const repo = path.resolve(__dirname, '..');
const compilerPath = 'launcher/scripts/dist/tooltip-catalog-compiler.js';
const catalogPath = 'data/tooltip/tooltip-catalog.json';
const receiptPath = 'data/tooltip/tooltip-catalog.manifest.json';
const archivePath = 'launcher/web/generated/archive-equipment.json';
const hash = (text) => crypto.createHash('sha256').update(text).digest('hex');
function loadCompiler(compilerRoot = repo) {
    const context = vm.createContext({});
    vm.runInContext(fs.readFileSync(path.join(compilerRoot, compilerPath), 'utf8'), context, {
        filename: compilerPath
    });
    return context.TooltipCatalog;
}
function compile(root = repo, included) {
    const realRoot = fs.realpathSync(root);
    let compilerRoot = repo;
    if (included) {
        if (!included.has(compilerPath)) throw Error('Missing packaged Tooltip compiler: ' + compilerPath);
        const compilerFile = fs.realpathSync(path.join(root, compilerPath));
        const relative = path.relative(realRoot, compilerFile);
        if (relative === '..' || relative.startsWith('..' + path.sep) || path.isAbsolute(relative))
            throw Error('Tooltip compiler escapes project: ' + compilerPath);
        compilerRoot = root;
    } else if (fs.existsSync(path.join(root, compilerPath))) {
        compilerRoot = root;
    }
    const compiler = loadCompiler(compilerRoot);
    const sources = Object.create(null);
    const packagedHashes = Object.create(null);
    const decoder = new TextDecoder('utf-8', { fatal: true });
    let characters = 0;
    function read(file) {
        if (Object.hasOwn(sources, file)) return;
        if (
            !file.startsWith('data/') ||
            file.split('/').some((segment) => !segment || segment === '.' || segment === '..') ||
            /[\\:\x00-\x1f]/.test(file)
        )
            throw Error('Invalid Tooltip source path: ' + file);
        if (included && !included.has(file)) throw Error('Missing packaged Tooltip input: ' + file);
        const source = fs.realpathSync(path.join(root, file));
        const relative = path.relative(realRoot, source);
        if (relative === '..' || relative.startsWith('..' + path.sep) || path.isAbsolute(relative))
            throw Error('Tooltip source escapes project: ' + file);
        if (fs.statSync(source).size > 16 * 1024 * 1024) throw Error('Tooltip source too large: ' + file);
        try {
            const bytes = fs.readFileSync(source);
            sources[file] = decoder.decode(bytes);
            if (included) packagedHashes[file] = hash(bytes);
        } catch (error) {
            throw Error(file + ': ' + error.message);
        }
        characters += sources[file].length;
        if (characters > 128 * 1024 * 1024 || Object.keys(sources).length > 4096)
            throw Error('Tooltip sources too large');
    }
    for (const file of compiler.lists) read(file);
    const inputs = compiler.sourcePaths(sources);
    for (const file of inputs) read(file);
    const { payload, duplicateItems } = compiler.compile(sources);
    const body = JSON.stringify(payload);
    const digest = hash(body);
    const catalog = compiler.serialize(body, digest);
    const counts = Object.fromEntries(
        ['items', 'mods', 'recipes', 'enemyNames'].map((k) => [k, Object.keys(payload[k]).length])
    );
    const receipt = {
        version: 1,
        output: catalogPath,
        outputSha256: hash(catalog),
        contentVersion: 'sha256:' + digest,
        counts,
        duplicateItems
    };
    // A package may still carry the previous signed host. Its receipt describes
    // the exact bytes copied to staging. Neither these hashes nor this receipt
    // participate in checkout initialization or the semantic content version.
    if (included) receipt.sourceFiles = packagedHashes;
    return { catalog, receipt, inputs, archive: compiler.archive(payload.items) };
}
function assets(result) {
    // The receipt is installed last, after the files it describes.
    return {
        [catalogPath]: result.catalog,
        [archivePath]: result.archive,
        [receiptPath]: JSON.stringify(result.receipt) + '\n'
    };
}
function preparePackage(root, included) {
    if (!included || path.resolve(root) === repo)
        throw Error('Prepare Tooltip artifacts in a selected package output directory');
    const result = compile(root, included);
    for (const [file, text] of Object.entries(assets(result))) {
        const target = path.join(root, file);
        if (fs.existsSync(target) && fs.readFileSync(target, 'utf8') === text) continue;
        fs.mkdirSync(path.dirname(target), { recursive: true });
        const temporary = target + '.' + crypto.randomUUID() + '.tmp';
        try {
            fs.writeFileSync(temporary, text, { encoding: 'utf8', flag: 'wx' });
            fs.renameSync(temporary, target);
        } finally {
            fs.rmSync(temporary, { force: true });
        }
    }
    return result;
}
if (require.main === module) {
    try {
        const args = process.argv.slice(2);
        if (args.length > 1 || (args.length && !['--check', '--help'].includes(args[0])))
            throw Error('Usage: node tools/tooltip-catalog.cjs [--check]');
        if (args[0] === '--help') {
            console.log('Validate current Tooltip sources. The packer owns prepared distribution files.');
        } else {
            const result = compile(repo);
            console.log(
                JSON.stringify({
                    ok: true,
                    mode: 'source-check',
                    filesWritten: 0,
                    ...result.receipt.counts,
                    contentVersion: result.receipt.contentVersion
                })
            );
        }
    } catch (error) {
        console.error(error.message);
        process.exitCode = 1;
    }
}
module.exports = {
    compile,
    assets,
    preparePackage,
    loadCompiler,
    compilerPath,
    catalogPath,
    receiptPath,
    archivePath
};
