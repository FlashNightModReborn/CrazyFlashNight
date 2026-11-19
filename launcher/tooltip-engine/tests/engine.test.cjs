'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { load, catalog, input, plain, docText, deepFreeze, repo } = require('./helpers.cjs');
const { catalogText } = require('../fixtures.cjs');
const E = load();

test('document port runs the existing source-defined historical JS assertions (not fresh AVM1 evidence)', () => {
    const source = fs.readFileSync(path.join(repo, 'tools/tooltip-parity-corpus.test.js'), 'utf8');
    const messages = [];
    const rootFile = file => path.isAbsolute(file) ? file : path.join(repo, file);
    const corpusFs = { ...fs, existsSync: file => fs.existsSync(rootFile(file)),
        readFileSync: (file, encoding) => fs.readFileSync(rootFile(file), encoding) };
    vm.runInNewContext(source, {
        require(name) { return name === './tooltip-parity-corpus.js' ? { Doc: E.NativeTooltipDocument }
            : name === 'fs' ? corpusFs : require(name); },
        console: { log: x => messages.push(x), error: x => messages.push(x) },
        process: { exit(code) { assert.equal(code, 0, messages.join('\n')); } }
    }, { filename: 'existing-document-assertions.js' });
    assert.ok(messages.some(x => /0 failed/.test(x)));
    if (!corpusFs.existsSync('tmp/native-interaction-migration-20260912/parity-corpus/samples.json')) {
        assert.ok(messages.some(x => /SKIP.*samples.json/.test(x)), 'fresh corpus absence must remain visible');
    }
});

test('AVM1 numeric conversion and non-strict comparison semantics are explicit', () => {
    for (const x of [undefined, null, '', ' ', '\t\n', NaN, {}, []]) assert.ok(Number.isNaN(E.as2Number(x)), String(x));
    assert.equal(E.as2Number(false), 0);
    assert.equal(E.as2Number('0'), 0);
    assert.equal(E.as2Number(' 12.5 '), 12.5);
    assert.equal(E.as2IsNaN(null), true);
    assert.equal(E.as2IsFinite(null), false);
    assert.equal(E.as2GreaterEqual(NaN, 3), true);
    assert.equal(E.as2LessEqual(NaN, 3), true);
    assert.equal(E.as2Less(null, 3), false);
    assert.equal(E.as2Equal(NaN, NaN), true, 'documented reflexive behavior; register provenance remains oracle gap');
});

test('source-defined formatter assertions keep null, zero and float-tail distinctions', () => {
    for (const x of [null, undefined, '', '0', 0]) {
        const out = []; E.TooltipFormatter.numLine(out, '标签', x, '%'); assert.equal(out.length, 0);
    }
    for (const [base, final, expected] of [[30, 30.2, '(30 + 0.2)'], [30.2, 30, '(30.2 - 0.2)']]) {
        const out = []; E.TooltipFormatter.upgradeLine(out, { weight: base }, { weight: final }, 'weight', '重量', 'kg');
        assert.ok(out.join('').includes(expected)); assert.ok(!out.join('').includes('99999'));
    }
    const out = []; E.TooltipFormatter.upgradeLine(out, { weight: .3 }, { weight: .1 + .2 }, 'weight', '重量', 'kg');
    assert.equal(out.join(''), '重量：0.3kg<BR>');
    const small = []; E.TooltipFormatter.upgradeLine(small, { weight: .01 }, null, 'weight', '重量', 'kg');
    assert.equal(small.join(''), '重量：0.01kg<BR>');
});

test('effective instance values, title and icon remain separate from base catalog', () => {
    const c = catalog(); const i = input(c, 'gun', { value: { level: 2, tier: '冷凝' }, projection: {
        calculated: { ...c.items.gun, displayname: '实际涂装枪', icon: '涂装图标', data: { ...c.items.gun.data, power: 151, weight: 30.2 } }, levelMultiplier: 1.5
    }});
    const r = E.buildProjection(i, c);
    assert.equal(r.document.title, '[冷凝]实际涂装枪');
    assert.equal(r.document.icon.name, '涂装图标');
    assert.match(r.introHTML, /151/); assert.match(r.introHTML, /100 \+ 51/); assert.match(r.introHTML, /\+50%/);
    assert.equal(c.items.gun.data.power, 100);
});

test('Inventory explicit display identity preserves the prior no-dedupe edge', () => {
    const c = catalog(); const i = input(c, 'gun', { projection: { displayName: '裸对象身份', iconName: '真实图标' } });
    const r = E.buildProjection(i, c);
    assert.equal(r.document.title, '裸对象身份'); assert.equal(r.document.icon.name, '真实图标');
    assert.match(r.introHTML, /测试枪/); assert.match(docText(r.document), /测试枪/);
});

test('stackable consumable quantity remains complete in the item and HUD drug intro', () => {
    const c = catalog();
    for (const hud of [undefined, {kind:'drug',count:41006,slot:0,key:'Q'}]) {
        const r = E.buildProjection(input(c, 'drug', {value:{level:1,count:41006},hud}), c);
        assert.ok(E.plainText(r.introHTML).includes('数量：41006'));
        assert.ok(docText(r.document).includes('41006'));
        if (hud) assert.ok(E.plainText(r.introHTML).includes('快捷栏：A组1号格（快捷键：Q）'));
    }
});

test('native rails and magazine replace only their repeated introductory lines', () => {
    const c = catalog(); const r = E.buildProjection(input(c, 'gun', { presentation: 'native' }), c);
    assert.deepEqual(plain(r.document.rail), ['长枪', '突击步枪']);
    assert.deepEqual(plain(r.document.magazine), { name: '测试弹药', icon: '弹药图标', ammo: '普通子弹' });
    const intro = r.document.sections.find(s => s.role === 'intro').runs.map(x => x.text).join('');
    assert.ok(!intro.includes('使用弹夹') && !intro.includes('子弹类型'));
    assert.match(r.introHTML, /使用弹夹/);
    assert.ok(r.document.sections.some(s => s.role === 'sub' && s.runs.some(x => x.text.includes('夜视'))));
});

test('fire-rate truncation keeps one decimal without exposing a binary floating-point tail', () => {
    const c = catalog(); c.items.gun.data.interval = 90;
    const base = E.buildProjection(input(c),c);
    assert.ok(base.introHTML.includes('射速：11.1发/秒'));
    const changed = E.buildProjection(input(c,'gun',{value:{level:2},projection:{levelMultiplier:1.1,calculated:{
        ...c.items.gun,data:{...c.items.gun.data,interval:70}
    }}}),c);
    assert.ok(changed.introHTML.includes("14.2</FONT> (11.1 + 3.1)发/秒"));
    assert.ok(!changed.details.includes('0000000000'));
});

test('blade count is the AS2 projection; no asset-name inference or Flash emulation', () => {
    const c = catalog(); c.items.gun.use = '刀'; delete c.items.gun.weapontype;
    const r = E.buildProjection(input(c, 'gun', { projection: { bladeCount: 4 } }), c);
    assert.match(r.introHTML, /判定数：4/);
    assert.deepEqual(plain(r.document.rail), ['刀', '默认']);
});

test('installed mod summaries consume exactly the matched branch projection', () => {
    const c = catalog();
    const branch = { name: 'weapontype:手枪', percentage: { power: .3 } };
    c.mods.mod = { name: 'mod', stats: { useSwitch: { useCases: [{ name: 'weapontype:长枪', percentage: { power: .8 } }, branch] } } };
    const i = input(c, 'gun', { value: { level: 1, mods: ['mod'] }, projection: { calculated: c.items.gun,
        mods: { mod: { present: true, useCases: [branch], bulletCases: [], skill: null } } } });
    const r = E.buildProjection(i, c), rows = r.document.sections.find(s => s.kind === 'attachments').rows;
    const txt = rows[0].runs.map(x => x.text).join('');
    assert.match(txt, /30%/); assert.ok(!txt.includes('80%')); assert.equal(rows[0].icon, '插件图标');
});

test('rejected standalone and installed mod definitions cannot be re-enabled by catalog data', () => {
    const c = catalog(); c.mods.mod = { name: 'mod', stats: { percentage: { power: .5 } } };
    const standalone = E.buildProjection(input(c, 'mod', { projection: { registeredModName: null } }), c);
    assert.ok(!standalone.descHTML.includes('50%'));
    const installed = E.buildProjection(input(c, 'gun', { value: { level: 1, mods: ['mod'] }, projection: { calculated: c.items.gun,
        mods: { mod: { present: false, useCases: [], bulletCases: [], skill: null } } } }), c);
    const row = installed.document.sections.find(s => s.kind === 'attachments').rows[0];
    assert.equal(row.name, 'mod'); assert.equal(row.runs.length, 0);
    const unqualified = input(c, 'gun', { value: { level: 1, mods: ['mod'] }, projection: { calculated: c.items.gun,
        mods: { mod: { useCases: [], bulletCases: [], skill: null } } } });
    assert.throws(() => E.buildTooltip(unqualified, c), /invalid_mod_projection/);
});

test('current grayGooEtch content meets the pre-existing AS2 source assertions', () => {
    const c = catalog();
    const behavior = { type: 'grayGooEtch', stackGroup: 'grayGooShotgunEtch', profileId: 'shotgunBase', delayFrames: 54, detonationCrumble: 1 };
    c.mods.mod = { name: 'mod', use: '手枪,长枪', weapontype: '霰弹枪', tagValue: '弹药', stats: { merge: { rout: .1 }, flat: { accuracy: -20 }, percentage: { power: .05 }, override: { hitBehavior: behavior } } };
    const r = E.buildProjection(input(c, 'mod', { projection: { registeredModName: 'mod' } }), c);
    assert.match(r.descHTML, /延迟1.8秒引爆贴身满伤；引爆击溃1%/);
    assert.match(r.descHTML, /蚀刻未引爆期间不叠加不刷新；目标提前阵亡不触发/);
    assert.ok(!r.descHTML.includes('[object Object]'));
});

test('registered standalone mods retain authored installation-condition text and nested groups', () => {
    const c = catalog();
    c.mods.mod = {name:'mod',use:'长枪',stats:{},installCondition:{cond:[
        {op:'is',path:'data.damagetype',value:'魔法'},
        {op:'above',path:'data.interval',value:200},
        {op:'is',path:'data.split',value:1}
    ],group:{mode:'any',cond:{op:'range',path:'data.power',min:100,max:200}}}};
    const before = JSON.stringify(c.mods.mod);
    const r = E.buildProjection(input(c,'mod',{projection:{registeredModName:'mod'}}),c);
    assert.ok(r.descHTML.includes('安装条件：'));
    assert.ok(r.descHTML.includes('伤害类型 为 属性'));
    assert.ok(r.descHTML.includes('射速 &lt; 5发/秒'));
    assert.ok(docText(r.document).includes('[任一满足]'));
    assert.equal(JSON.stringify(c.mods.mod),before);
    assert.ok(!E.buildProjection(input(c,'mod',{projection:{registeredModName:null}}),c).descHTML.includes('安装条件：'));
});

test('gray-goo primer branch summaries preserve profile-specific stacking rules', () => {
    const c = catalog(), i = input(c); const ctx = { input: i, catalog: c, projection: i.projection };
    const b = { type: 'grayGooPrimer', profileId: 'handgun', hitStacks: 3, breakStacks: 3, maxStacks: 18, damagePerStack: .01, crumblePerMilestone: .3, executeAtMax: 8, decayDelay: 150 };
    const text = E.UseSwitchStatsBuilder.buildHitBehaviorSummary(ctx, b);
    assert.match(text, /命中\/破韧\+3格/); assert.match(text, /节点击溃0.3%/); assert.match(text, /停火5秒后衰减/);
    assert.ok(!text.includes('上限18格'), 'branch does not redundantly restate the base profile');
});

test('drug effects are projected normalized records, with consumer-specific buff splitting', () => {
    const c = catalog(); const effects = [{ type: 'heal', hp: 20, scaleWithAlchemy: true }, { type: 'buff', property: 'damage', calc: 'add', value: 50, duration: 1800, scaleWithAlchemy: true }, { type: 'message', text: 'hidden' }];
    const i = input(c, 'drug', { projection: { drugEffects: effects } });
    const inventory = E.buildProjection(i, c), native = E.buildProjection({ ...i, presentation: 'native' }, c);
    assert.match(inventory.introHTML, /20/); assert.match(inventory.introHTML, /50/);
    assert.ok(!inventory.document.sections.some(s => s.role === 'sub'));
    assert.ok(native.document.sections.some(s => s.role === 'sub' && s.runs.some(x => /50/.test(x.text))));
    assert.ok(!docText(native.document).includes('hidden'));
});

test('authored restoreToughness effects retain their full-restoration line in both consumers', () => {
    const c = catalog();
    for (const presentation of ['inventory','web']) {
        const r = E.buildProjection(input(c,'drug',{presentation,projection:{drugEffects:[
            {type:'restoreToughness'},{type:'playEffect',name:'净化动画'}
        ]}}),c);
        assert.ok(r.introHTML.includes("<FONT COLOR='#FFCC00'>韧性：</FONT>立即恢复至满<BR>"));
        assert.ok(docText(r.document).includes('韧性：立即恢复至满'));
        assert.ok(r.details.includes('韧性：立即恢复至满'));
        assert.ok(!r.details.includes('净化动画'));
    }
});

test('source discovery records and enemy display names are authoritative per input', () => {
    const c = catalog(); c.enemyNames.secret = '不可泄漏';
    const i = input(c, 'material', { projection: { obtainRecords: [{ kind: 'shop', npc: '商人' }, { kind: 'drop', dropType: 'enemy', enemyType: 'enemy', enemyDisplayName: '已知敌人' }] } });
    const r = E.buildProjection(i, c); assert.match(r.descHTML, /商人/); assert.match(r.descHTML, /已知敌人/); assert.ok(!r.descHTML.includes('不可泄漏'));
    const empty = E.buildProjection(input(c, 'material'), c); assert.ok(!empty.document.sections.some(s => s.kind === 'acquisition'));
});

test('upgrade paths use projected available tiers and structured recipe rows', () => {
    const c = catalog(); c.items.gun.synthesis = 'recipe'; c.recipes.recipe = { materials: [{ name: 'material', value: 4, isQuantity: true }] };
    c.recipesUsing.gun = ['ammo'];
    const r = E.buildProjection(input(c, 'gun', { value: { level: 1, tier: '二阶' }, projection: { calculated: c.items.gun,
        tierOptions: [{ name: '二阶', available: true, material: 'material' }, { name: '三阶', available: false }] } }), c);
    const rows = r.document.sections.find(s => s.kind === 'upgrades').rows;
    assert.ok(rows.some(x => x.name === '测试材料 x4')); assert.ok(rows.some(x => /二阶.*当前/.test(x.name)));
    assert.ok(!rows.some(x => x.name.includes('三阶')));
});

test('electric lighting bonus reads the provided tag result, not a second tag engine', () => {
    const c = catalog(); c.items.gun.lifecycle = { lamp: { init: { initRoutines: '装备光源初始化', initParam: { kind: 'flashlight', evasionBonus: 5, electricEvasionBonus: 3, builtinDefense: true } } } };
    const a = E.buildProjection(input(c, 'gun', { projection: { electric: true } }), c);
    const b = E.buildProjection(input(c, 'gun', { projection: { electric: false } }), c);
    assert.match(a.descHTML, /闪避加成 \+8（电力适配）/); assert.match(b.descHTML, /闪避加成 \+5/);
});

test('non-finite and undefined transport markers preserve a controlled distinction from null', () => {
    const c = catalog(); const i = input(c, 'gun', { value: { level: 2 }, projection: {
        calculated: { ...c.items.gun, data: { ...c.items.gun.data, power: { __tooltipNumber: 'NaN' }, weight: { __tooltipUndefined: true } } }
    }});
    const r = E.buildProjection(i, c); assert.match(r.introHTML, /NaN/); assert.match(r.introHTML, /undefined/);
    i.projection.calculated.data.power = { __tooltipNumber: 'NaN', forged: true };
    assert.throws(() => E.buildProjection(i, c), /invalid_number_marker/);
    const skill = E.buildProjection({ version: 1, kind: 'skill', mode: 'loadout', skillName: '边界技能',
        skillData: { Name: '边界技能', Type: '主动', MP: { __tooltipNumber: 'Infinity' }, CD: { __tooltipNumber: 'NaN' } },
        state: { level: 1 } }, c);
    assert.match(skill.introHTML, /MP消耗：Infinity/);
    assert.match(skill.introHTML, /冷却秒数：NaN/);
});

test('array holes in effect projections produce no text and do not crash', () => {
    const c = catalog(); const effects = new Array(3); effects[1] = { type: 'heal', hp: 10 };
    const r = E.buildProjection(input(c, 'drug', { projection: { drugEffects: effects } }), c);
    assert.match(r.introHTML, /10/); assert.ok(!r.introHTML.includes('undefined'));
});

test('captured AVM1 skill arrays retain undefined and null in text and document', () => {
    const fixture = JSON.parse(fs.readFileSync(path.join(__dirname, 'fixtures/avm1-skill-array-text.json'), 'utf8'));
    const r = E.buildProjection(fixture.record.input, catalog());
    assert.equal(r.introHTML, fixture.record.expectedIntroHTML);
    assert.equal(r.descHTML, fixture.record.expectedDescHTML);
    assert.deepEqual(JSON.parse(JSON.stringify(r.document)), fixture.record.expectedDocument);
});

test('plain text details keep intro-before-description, entity decoding, whitespace and length cap', () => {
    assert.equal(E.plainText('<B>甲</B><DIV>乙 &lt;b&gt; &nbsp;  丙</DIV>\r\n丁'), '甲\n乙 <b> 丙\n\n丁');
    const c = catalog(); c.items.material.description = '说明'.repeat(3000);
    const r = E.buildProjection(input(c, 'material'), c);
    assert.ok(r.details.startsWith('测试材料\n')); assert.equal(r.details.length, 4096);
});

test('ChoiceReward details keep original inline order and do not duplicate Web crit/buff subpanels', () => {
    // ChoiceRewardService.snapshot at baseline db6d3d2 calls full intro + full
    // generateItemDescriptionText, not Web物品注释HTML's reordered descHTML.
    const c = catalog(); c.items.gun.data.criticalhit = 12;
    c.items.gun.skill = { description: '战技说明标记', cd: 1000 };
    const native = E.buildProjection(input(c, 'gun'), c);
    const web = E.buildProjection(input(c, 'gun', { presentation: 'web', output: 'details' }), c);
    assert.equal(web.details, E.plainText(native.introHTML + native.descHTML).substr(0, 4096));
    assert.equal((web.details.match(/12%/g) || []).length, 1);
    assert.ok(web.details.indexOf('【夜视】测试') < web.details.indexOf('战技说明标记'));
    const drug = input(c, 'drug', { presentation: 'web', output: 'details', projection: {
        drugEffects: [{ type: 'buff', property: 'damage', calc: 'add', value: 50, duration: 1800 }]
    } });
    const drugDetails = E.buildProjection(drug, c).details;
    assert.equal((drugDetails.match(/50/g) || []).length, 1);
});

test('HUD descriptions retain resource state and exact vitals unavailable wording', () => {
    const c = catalog();
    const skill = E.buildTooltip({ version: 1, kind: 'skill', mode: 'loadout', skillName: '技能', skillData: { Name: '技能', Type: '主动', Equippable: true, CD: 1234, MP: 5 }, state: { level: 2, equipped: true }, resourceHint: { state: 'blocked', reason: 'mp' } }, c);
    assert.match(docText(skill), /已装备/); assert.match(docText(skill), /冷却秒数：1.2/); assert.match(docText(skill), /MP不足/);
    const vitals = E.buildTooltip({ version: 1, kind: 'hud', mode: 'resources', data: { hp: [0, 0], mp: [0, 0], shield: [0, 0], shieldReady: false, poise: .5, experience: [1, 0, 10], sp: 3 } }, c);
    assert.match(docText(vitals), /生命：0 \/ 0（未就绪）/); assert.match(docText(vitals), /本单位不使用此资源/);
});

test('reverse insertion enumeration preserves display order and filters internal attributes', () => {
    const c = catalog(), i = input(c); const ctx = { input: i, catalog: c, projection: i.projection };
    assert.deepEqual(plain(E.as2Keys({ first: 1, second: 2 })), ['second', 'first']);
    assert.equal(E.TooltipTextBuilder.quickBuildMagicDefence(ctx, { 热: 1, 冷: 2, __dictUID: 77 }, null), '抗性 -> 冷: 2, 热: 1<BR>');
});

test('structured subpanels preserve rows, depth, icon, runs and fallback runs', () => {
    const d = E.NativeTooltipDocument.buildItem('x', { type: '材料' }, null, '', '', [{ kind: 'modinfo', title: '说明', rows: [{ name: '父行' }, { depth: 1, effect: '<B>效果</B>', icon: 'i' }] }]);
    const s = d.sections[0]; assert.equal(s.kind, 'modinfo'); assert.equal(s.rows[1].depth, 1); assert.equal(s.rows[1].name, ''); assert.equal(s.rows[1].icon, 'i');
    assert.deepEqual(plain(s.rows[1].runs), [{ text: '效果', bold: true }]); assert.ok(s.runs.length > 2);
});

test('pure entry never mutates frozen inputs/catalogs and shared references are allowed', () => {
    const c = catalog(), i = input(c, 'gun', { projection: { calculated: c.items.gun } });
    const before = JSON.stringify({ c, i }); deepFreeze(c); deepFreeze(i);
    const first = E.buildTooltip(i, c), second = E.buildTooltip(i, c);
    assert.deepEqual(plain(first), plain(second)); assert.equal(JSON.stringify({ c, i }), before);
});

test('invalid inputs fail predictably and cannot poison subsequent resident-engine requests', () => {
    const c = catalog(); E.initCatalog(JSON.stringify(c));
    const good = JSON.stringify(input(c)); const expected = E.buildJson(good);
    for (const bad of [{ version: 2, kind: 'item' }, { version: 1, kind: 'unknown' }, { version: 1, kind: 'item', itemName: 'gun' }, JSON.parse('{"version":1,"kind":"body","__proto__":{}}')]) {
        assert.throws(() => E.buildJson(JSON.stringify(bad)));
        assert.equal(E.buildJson(good), expected);
    }
    assert.throws(() => E.initCatalog('{"version":2}'));
    assert.equal(E.buildJson(good), expected, 'catalog update is atomic on validation failure');
    const cycle = { version: 1, kind: 'body' }; cycle.self = cycle;
    assert.throws(() => E.buildTooltip(cycle, c), /cyclic_input/);
});

test('256 KiB transport cap and recursion bound hold before content evaluation', () => {
    const c = catalog(); E.initCatalog(JSON.stringify(c));
    assert.throws(() => E.buildJson('x'.repeat(256 * 1024 + 1)), /input_too_large/);
    let data = {}; for (let x = 0; x < 30; x++) data = { data };
    assert.throws(() => E.buildTooltip({ version: 1, kind: 'body', data }, c), /input_too_large/);
});

test('NUL code points obey the documented AVM1 string behavior', () => {
    assert.equal(E.as2FromCharCode(65, 0, 66), 'AB');
    assert.equal(E.htmlToRuns('A&#0;B').map(x => x.text).join(''), 'AB');
});

test('production catalog baseline smoke covers every item without claiming instance/oracle parity', () => {
    const c = JSON.parse(catalogText());
    for (const name of Object.keys(c.items)) {
        const i = input(c, name, { projection: { registeredModName: c.mods[name] ? name : null } });
        const r = E.buildProjection(i, c);
        assert.equal(r.document.version, 1, name);
        assert.ok(Array.isArray(r.document.sections), name);
        assert.ok(r.details.length <= 4096, name);
    }
});

test('recipesUnavailable preserves tier upgrade options and avoids polluting unrelated items', () => {
    const c = catalog();
    c.recipesUnavailable = true;
    c.recipeTargets = { gun: true };
    c.items.knife = { name: 'knife', displayname: '测试刀', icon: '刀图标', type: '武器', use: '刀', price: 5, data: { level: 1 } };
    const gunRes = E.buildProjection(input(c, 'gun', { projection: {
        tierOptions: [{ name: '二阶', available: true, material: 'material' }] } }), c);
    const gunUpgrades = gunRes.document.sections.find(s => s.kind === 'upgrades');
    assert.ok(gunUpgrades, 'affected item should keep upgrades section');
    assert.ok(gunUpgrades.rows.some(x => x.name === '合成材料暂不可用'));
    assert.ok(gunUpgrades.rows.some(x => x.name === '二阶'));
    assert.ok(gunRes.descHTML.includes(E.TooltipConstants.LBL_UPGRADE_PATH));
    assert.ok(gunRes.descHTML.includes('合成材料暂不可用'));
    assert.ok(gunRes.descHTML.includes('二阶'));

    const knifeClean = E.buildProjection(input(c, 'knife'), c);
    assert.ok(!knifeClean.document.sections.some(s => s.kind === 'upgrades'));
    assert.ok(!knifeClean.descHTML.includes('合成材料暂不可用'));

    delete c.recipeTargets;
    const knifeFallback = E.buildProjection(input(c, 'knife', { projection: {
        tierOptions: [{ name: '二阶', available: true, material: 'material' }] } }), c);
    const fallbackUpgrades = knifeFallback.document.sections.find(s => s.kind === 'upgrades');
    assert.ok(fallbackUpgrades && fallbackUpgrades.rows.some(x => x.name === '合成材料暂不可用'));
    assert.ok(fallbackUpgrades.rows.some(x => x.name === '二阶'));
});

test('non-equipment data follows the legacy stats selector, including explicit-null transport', () => {
    const c = catalog();
    c.items.supply = { name: 'supply', displayname: '战场补给', type: '消耗品', use: '战场补给', data: { effects: { effect: { type: 'heal', hp: 300 } } } };
    const i = input(c, 'supply', { projection: { calculated: null, baselineData: c.items.supply.data } });
    assert.equal(E.buildTooltip(i, c).title, '战场补给');
    i.projection.baselineData = null;
    assert.throws(() => E.buildTooltip(i, c), /missing_baseline_data/);
});
