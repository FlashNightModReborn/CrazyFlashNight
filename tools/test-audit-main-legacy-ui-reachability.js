#!/usr/bin/env node
'use strict';

const assert = require('assert');
const childProcess = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');

const gate = require('./audit-main-legacy-ui-reachability.js');

let passed = 0;
const cleanupRoots = [];

function write(root, relative, text) {
    const file = path.join(root, ...relative.split('/'));
    fs.mkdirSync(path.dirname(file), { recursive: true });
    fs.writeFileSync(file, text, 'utf8');
    return file;
}

function projectFixture(dom, libraryFiles) {
    const root = fs.mkdtempSync(path.join(os.tmpdir(), 'cf7-main-ui-gate-test-'));
    cleanupRoots.push(root);
    write(root, 'CRAZYFLASHER7MercenaryEmpire/DOMDocument.xml', dom);
    for (const [relative, text] of Object.entries(libraryFiles || {})) {
        write(root, 'CRAZYFLASHER7MercenaryEmpire/LIBRARY/' + relative, text);
    }
    return root;
}

function domXml(includes, rootElements) {
    return [
        '<?xml version="1.0" encoding="utf-8"?>',
        '<DOMDocument xmlns="http://ns.adobe.com/xfl/2008/">',
        '  <symbols>',
        includes.map(href => '    <Include href="' + href + '"/>').join('\n'),
        '  </symbols>',
        '  <timelines><DOMTimeline><layers><DOMLayer><frames><DOMFrame><elements>',
        rootElements || '',
        '  </elements></DOMFrame></frames></DOMLayer></layers></DOMTimeline></timelines>',
        '</DOMDocument>'
    ].join('\n');
}

function symbolXml(name, body, attributes) {
    return [
        '<DOMSymbolItem xmlns="http://ns.adobe.com/xfl/2008/" name="' + name + '"' +
            (attributes ? ' ' + attributes : '') + '>',
        '  <timeline><DOMTimeline><layers><DOMLayer><frames><DOMFrame><elements>',
        body || '',
        '  </elements></DOMFrame></frames></DOMLayer></layers></DOMTimeline></timeline>',
        '</DOMSymbolItem>'
    ].join('\n');
}

function codes(result) {
    return result.findings.map(item => item.code);
}

function tokens(result) {
    return result.findings.map(item => item.token);
}

function test(name, fn) {
    fn();
    passed++;
    process.stdout.write('ok ' + passed + ' - ' + name + '\n');
}

test('clean source closure ignores docs, CDATA, comments, and orphan library XML', () => {
    const root = projectFixture(
        domXml(
            ['safe/helper.xml', 'safe/panel.xml'],
            '<DOMSymbolInstance libraryItemName="safe/helper"/>'
        ),
        {
            'safe/helper.xml': symbolXml(
                'safe/helper',
                [
                    '<!-- <DOMSymbolInstance name="仓库界面" libraryItemName="retired"/> -->',
                    '<Actionscript><script><![CDATA[',
                    'var archived:String = "物品栏界面 物品改装界面.swf";',
                    ']]></script></Actionscript>',
                    '<DOMSymbolInstance libraryItemName="safe/panel"/>'
                ].join('\n')
            ),
            'safe/panel.xml': symbolXml('safe/panel', '<DOMShape/>'),
            'orphan/legacy.xml': symbolXml(
                'orphan/legacy',
                '<DOMSymbolInstance name="购买物品界面" libraryItemName="retired"/>',
                'linkageURL="flashswf/UI/物品与技能相关界面.swf"'
            )
        }
    );
    write(root, 'docs/history.md', '仓库界面、学习技能界面、物品改装界面.swf');

    const result = gate.scanXflSource(root, gate.DEFAULT_DOM);
    assert.deepStrictEqual(result.findings, []);
    assert.strictEqual(result.includedSymbols, 2);
    assert.strictEqual(result.reachableSymbols, 2);
});

test('source scan rejects retired Include aliases and root placements', () => {
    const root = projectFixture(
        domXml(
            ['import/UI组件/新版仓库界面.xml', 'sprite/Symbol 1779.xml'],
            [
                '<DOMSymbolInstance libraryItemName="import/UI组件/新版仓库界面" name="仓库界面"/>',
                '<DOMSymbolInstance libraryItemName="sprite/Symbol 1779" name="学习技能界面"/>'
            ].join('\n')
        ),
        {
            'import/UI组件/新版仓库界面.xml': symbolXml(
                'import/UI组件/新版仓库界面',
                '<DOMShape/>',
                'linkageImportForRS="true" linkageIdentifier="仓库界面" ' +
                    'linkageURL="flashswf/UI/物品与技能相关界面.swf"'
            ),
            'sprite/Symbol 1779.xml': symbolXml('sprite/Symbol 1779', '<DOMShape/>')
        }
    );

    const result = gate.scanXflSource(root, gate.DEFAULT_DOM);
    assert.ok(codes(result).includes('XFL_FORBIDDEN_INCLUDE'));
    assert.ok(codes(result).includes('XFL_FORBIDDEN_ROOT_PLACE'));
    assert.ok(codes(result).includes('XFL_FORBIDDEN_LINKAGE'));
    assert.ok(codes(result).includes('XFL_FORBIDDEN_EXTERNAL_SWF'));
    assert.ok(tokens(result).includes('学习技能界面'));
    assert.ok(tokens(result).includes('仓库界面'));
    assert.ok(tokens(result).includes('物品与技能相关界面.swf'));
});

test('source scan follows a reachable helper but ignores the same orphan helper', () => {
    const reachableRoot = projectFixture(
        domXml(
            ['safe/helper.xml', 'import/UI组件/资源箱界面.xml'],
            '<DOMSymbolInstance libraryItemName="safe/helper"/>'
        ),
        {
            'safe/helper.xml': symbolXml(
                'safe/helper',
                '<DOMSymbolInstance libraryItemName="import/UI组件/资源箱界面"/>'
            ),
            'import/UI组件/资源箱界面.xml': symbolXml(
                'import/UI组件/资源箱界面',
                '<DOMShape/>'
            )
        }
    );
    const reachable = gate.scanXflSource(reachableRoot, gate.DEFAULT_DOM);
    const helperFinding = reachable.findings.find(item =>
        item.code === 'XFL_FORBIDDEN_REACHABLE_PLACE'
    );
    assert.ok(helperFinding);
    assert.deepStrictEqual(
        helperFinding.route,
        ['<main timeline>', 'safe/helper', 'import/UI组件/资源箱界面']
    );

    const orphanRoot = projectFixture(
        domXml(['safe/helper.xml'], ''),
        {
            'safe/helper.xml': symbolXml(
                'safe/helper',
                '<DOMSymbolInstance name="资源箱界面" libraryItemName="unlisted/legacy"/>'
            )
        }
    );
    const orphan = gate.scanXflSource(orphanRoot, gate.DEFAULT_DOM);
    assert.deepStrictEqual(orphan.findings, []);
    assert.strictEqual(orphan.reachableSymbols, 0);
});

test('included RSL metadata is rejected even when it is not placed', () => {
    const root = projectFixture(
        domXml(['safe/opaque.xml'], ''),
        {
            'safe/opaque.xml': symbolXml(
                'safe/opaque',
                '<DOMShape/>',
                'linkageImportForRS="true" linkageIdentifier="购买物品界面" ' +
                    'linkageURL="flashswf/UI/物品与技能相关界面.swf"'
            )
        }
    );
    const result = gate.scanXflSource(root, gate.DEFAULT_DOM);
    assert.ok(codes(result).includes('XFL_FORBIDDEN_LINKAGE'));
    assert.ok(codes(result).includes('XFL_FORBIDDEN_EXTERNAL_SWF'));
});

test('FFDec XML scan rejects only structured import/linkage/place records', () => {
    const xml = [
        '<swf><tags>',
        '  <item type="DoActionTag">',
        '    <constantPool><item>仓库界面</item></constantPool>',
        '    <script><![CDATA[var history = "学习技能界面";]]></script>',
        '  </item>',
        '  <item type="ImportAssets2Tag" url="flashswf/UI/物品与技能相关界面.swf">',
        '    <tags><item>382</item></tags>',
        '    <names><item>仓库界面</item></names>',
        '  </item>',
        '  <item type="ImportAssetsTag" url="flashswf/UI/物品改装界面.swf">',
        '    <tags><item>161</item></tags>',
        '    <names><item>物品改装界面</item></names>',
        '  </item>',
        '  <item type="PlaceObject2Tag" characterId="382" depth="82" name="仓库界面"/>',
        '  <item type="ExportAssetsTag">',
        '    <tags><item>500</item></tags>',
        '    <names><item>资源箱界面</item></names>',
        '  </item>',
        '</tags></swf>'
    ].join('\n');
    const result = gate.scanSwfXmlText(xml, 'fixture.swf.xml');

    assert.ok(codes(result).includes('SWF_FORBIDDEN_IMPORT_URL'));
    assert.ok(codes(result).includes('SWF_FORBIDDEN_IMPORT_NAME'));
    assert.ok(codes(result).includes('SWF_FORBIDDEN_PLACE_OBJECT'));
    assert.ok(codes(result).includes('SWF_FORBIDDEN_EXPORTED_LINKAGE'));
    assert.strictEqual(
        result.findings.filter(item => item.code === 'SWF_FORBIDDEN_PLACE_OBJECT').length,
        1
    );
    assert.ok(!result.findings.some(item =>
        item.line === 3 && item.token === '仓库界面'
    ));
});

test('clean FFDec XML permits retired words in non-structural action data', () => {
    const xml = [
        '<swf><tags>',
        '  <item type="DoActionTag">',
        '    <constantPool><item>物品栏界面</item><item>购买物品界面</item></constantPool>',
        '    <script><![CDATA[_root.学习技能界面.关闭();]]></script>',
        '  </item>',
        '  <item type="PlaceObject2Tag" characterId="1" depth="1" name="safePanel"/>',
        '</tags></swf>'
    ].join('\n');
    const result = gate.scanSwfXmlText(xml, 'clean.swf.xml');
    assert.deepStrictEqual(result.findings, []);
});

test('CLI exit code is deterministic for clean source and bad supplied FFDec XML', () => {
    const root = projectFixture(
        domXml(['safe/panel.xml'], '<DOMSymbolInstance libraryItemName="safe/panel"/>'),
        {'safe/panel.xml': symbolXml('safe/panel', '<DOMShape/>')}
    );
    const badXml = write(root, 'tmp/bad-main.xml', [
        '<swf><tags>',
        '  <item type="PlaceObject3Tag" characterId="9" depth="9" name="学习技能界面"/>',
        '</tags></swf>'
    ].join('\n'));
    const script = path.join(__dirname, 'audit-main-legacy-ui-reachability.js');

    const clean = childProcess.spawnSync(
        process.execPath,
        [script, '--project-root', root, '--source-only', '--json'],
        { encoding: 'utf8' }
    );
    assert.strictEqual(clean.status, 0, clean.stderr);
    assert.strictEqual(JSON.parse(clean.stdout).status, 'passed');

    const bad = childProcess.spawnSync(
        process.execPath,
        [
            script,
            '--project-root', root,
            '--swf-xml', badXml,
            '--json'
        ],
        { encoding: 'utf8' }
    );
    assert.strictEqual(bad.status, 1, bad.stderr);
    const report = JSON.parse(bad.stdout);
    assert.strictEqual(report.status, 'failed');
    assert.ok(report.findings.some(item =>
        item.code === 'SWF_FORBIDDEN_PLACE_OBJECT' &&
        item.token === '学习技能界面'
    ));
});

for (const root of cleanupRoots) {
    if (root.startsWith(path.join(os.tmpdir(), 'cf7-main-ui-gate-test-'))) {
        fs.rmSync(root, { recursive: true, force: true });
    }
}

process.stdout.write(
    'All main legacy UI reachability gate tests passed (' + passed + '/' + passed + ').\n'
);
