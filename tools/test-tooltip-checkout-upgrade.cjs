#!/usr/bin/env node
// A contributor edits one source and pushes without a prepare/check step. A separate
// checkout pulls and requests a normal inventory document from the production host.
'use strict';
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const assert = require('node:assert/strict');
const { execFileSync } = require('node:child_process');
const producer = require('./tooltip-catalog.cjs');
const { itemInput } = require('../launcher/tooltip-engine/fixtures.cjs');
const root = path.resolve(__dirname, '..');
const scratch = fs.mkdtempSync(path.join(os.tmpdir(), 'cf7-tooltip-upgrade-'));
const author = path.join(scratch, 'author'),
    tester = path.join(scratch, 'tester');
const recipe = 'data/crafting/upgrade-fixture.json';
const git = (cwd, ...args) =>
    execFileSync('git', args, { cwd, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }).trim();
const write = (dir, name, text) => {
    const file = path.join(dir, name);
    fs.mkdirSync(path.dirname(file), { recursive: true });
    fs.writeFileSync(file, text);
};
try {
    const result = producer.compile(root);
    const catalog = JSON.parse(result.catalog);
    const product = Object.keys(catalog.items).find(
        (n) => catalog.items[n].type === '防具' && catalog.items[n].data
    );
    const material = Object.keys(catalog.items).find(
        (n) => n !== product && catalog.items[n].type === '收集品'
    );
    const materialLabel = catalog.items[material].displayname || material;
    const format = (name, value) =>
        JSON.stringify(
            [{ recipeId: 'test.upgrade', name: product, materials: [name + '##' + value] }],
            null,
            2
        ) + '\n';
    fs.mkdirSync(author);
    for (const file of [...result.inputs, producer.compilerPath, 'launcher/scripts/dist/tooltip-bundle.js'])
        write(author, file, fs.readFileSync(path.join(root, file)));
    for (const file of [
        'tools/tooltip-catalog.cjs',
        'tools/build-tooltip-catalog.py',
        'tools/build-bootstrap-equipment-reference.js'
    ])
        write(author, file, fs.readFileSync(path.join(root, file)));
    write(author, 'data/crafting/list.xml', '<root><list>upgrade-fixture</list></root>\n');
    write(author, recipe, format(material, 2));
    // A checkout must also work with a missing or obsolete prepared catalog.
    write(author, producer.catalogPath, '{}\n');
    git(author, 'init', '-qb', 'main');
    git(author, 'config', 'user.name', 'Tooltip regression');
    git(author, 'config', 'user.email', 'fixture@localhost');
    git(author, 'config', 'commit.gpgsign', 'false');
    git(author, 'add', '.');
    git(author, 'commit', '-qm', 'baseline');
    const remote = path.join(scratch, 'remote.git');
    git(scratch, 'clone', '-q', '--bare', author, remote);
    git(author, 'remote', 'add', 'origin', remote);
    git(scratch, '-c', 'core.autocrlf=true', 'clone', '-q', remote, tester);
    const input = path.join(scratch, 'inventory.jsonl');
    fs.writeFileSync(input, JSON.stringify(itemInput(catalog, product, { presentation: 'inventory' })) + '\n');
    const hostDir = path.join(root, 'launcher/tests/TooltipService.Host');
    execFileSync(
        'dotnet',
        [
            'build',
            path.join(hostDir, 'TooltipService.Host.csproj'),
            '-c',
            'Release',
            '-p:RestoreLockedMode=true',
            '--nologo',
            '-v:q'
        ],
        { cwd: root }
    );
    const host = path.join(hostDir, 'bin/Release/net10.0/TooltipService.Host.dll');
    const card = () =>
        JSON.parse(execFileSync('dotnet', [host, '--evaluate', tester, input], { encoding: 'utf8', cwd: root }))
            .document;
    const hasCount = (doc, value) => JSON.stringify(doc).includes(materialLabel + ' x' + value);
    assert.ok(hasCount(card(), 2), 'initial inventory quantity');
    function publish(text) {
        write(author, recipe, text);
        git(author, 'add', '--', recipe);
        git(author, 'commit', '-qm', 'change only recipe');
        assert.equal(git(author, 'diff', '--name-only', 'HEAD^', 'HEAD'), recipe);
        git(author, 'push', '-q', 'origin', 'main');
        git(tester, 'pull', '-q', '--ff-only');
    }
    publish(format(material, 3));
    const updated = card();
    assert.ok(hasCount(updated, 3) && !hasCount(updated, 2), 'inventory quantity after pull');
    // Helpers found in older guides must also be harmless on an ordinary contribution.
    for (const args of [
        ['tools/tooltip-catalog.cjs'],
        ['tools/tooltip-catalog.cjs', '--check'],
        ['tools/build-bootstrap-equipment-reference.js']
    ])
        execFileSync(process.execPath, args, { cwd: tester });
    assert.equal(git(tester, 'status', '--porcelain'), '', 'ordinary validation modified the checkout');
    publish(format('unknown-ingredient-for-test', 4));
    assert.throws(
        () => producer.compile(tester),
        /upgrade-fixture\.json.*test\.upgrade.*materials\[0\].*unknown-ingredient/
    );
    const unavailable = card();
    assert.equal(unavailable.title, updated.title);
    assert.ok(JSON.stringify(unavailable).includes('合成材料暂不可用'));
    console.log(
        'PASS: source-only commit and pull, inventory 2 -> 3, bad reference identified, item still visible.'
    );
} finally {
    fs.rmSync(scratch, { recursive: true, force: true });
}
