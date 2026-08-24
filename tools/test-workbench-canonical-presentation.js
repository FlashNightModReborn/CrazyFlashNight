'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');
const ROOT = path.resolve(__dirname, '..');
const Owned = require('../launcher/web/modules/inventory-workbench-owned-view.js');
const KShopTooltip = require('../launcher/web/modules/kshop-tooltip-presenter.js');
const CharacterProjection = require(
    '../launcher/web/modules/character-build/character-build-projection.js');

let passed = 0;
function test(name, fn) {
    fn();
    passed++;
    console.log('PASS ' + name);
}

function source(relativePath) {
    return fs.readFileSync(path.join(ROOT, relativePath), 'utf8');
}

const PRESENTATION_FILES = [
    'launcher/web/modules/inventory-ui.js',
    'launcher/web/modules/inventory-storage-workbench.js',
    'launcher/web/modules/inventory-workbench-owned-view.js',
    'launcher/web/modules/equipment-inspector.js',
    'launcher/web/modules/character-build/character-build-tuning.js',
    'launcher/web/modules/character-build/character-build-candidate-eligibility.js',
    'launcher/web/modules/character-build/character-build-projection.js',
    'launcher/web/modules/character-build/character-build-candidate-tooltip.js',
    'launcher/web/modules/character-build/character-build-loadout-presenter.js',
    'launcher/web/modules/loadout-picker/loadout-picker-candidate-pane.js',
    'launcher/web/modules/loot/loot-view.js',
    'launcher/web/modules/loot/loot-organizer.js',
    'launcher/web/modules/kshop-catalog-presenter.js',
    'launcher/web/modules/kshop-tooltip-presenter.js',
    'launcher/web/modules/kshop-owned-inventory-presenter.js',
    'launcher/web/modules/kshop-views.js',
    'launcher/web/modules/crafting-detail-presenter.js',
    'launcher/web/modules/crafting-materials.js',
    'launcher/web/modules/npcshop-secondary-pages.js'
];

// Each expression binds the presentation field and the internal identity to the
// same known object path. This intentionally does not match
// `projection.displayName || candidate.name`: candidate.name is already a
// player-facing view-model label, not a raw rule identity.
const RAW_IDENTITY_FALLBACKS = [
    {label:'item display', pattern:/\bitem\.displayName\s*\|\|\s*item\.name\b/,
        mutation:'item.displayName || item.name'},
    {label:'item icon', pattern:/\bitem\.icon\s*\|\|\s*item\.name\b/,
        mutation:'item.icon || item.name'},
    {label:'mod display', pattern:/\bmod\.displayName\s*\|\|\s*mod\.name\b/,
        mutation:'mod.displayName || mod.name'},
    {label:'mod icon', pattern:/\bmod\.icon\s*\|\|\s*mod\.name\b/,
        mutation:'mod.icon || mod.name'},
    {label:'projection display', pattern:/\bprojection\.displayName\s*\|\|\s*projection\.name\b/,
        mutation:'projection.displayName || projection.name'},
    {label:'projection icon', pattern:/\bprojection\.icon\s*\|\|\s*projection\.name\b/,
        mutation:'projection.icon || projection.name'},
    {label:'output display', pattern:/\boutput\.displayName\s*\|\|\s*output\.name\b/,
        mutation:'output.displayName || output.name'},
    {label:'output icon', pattern:/\boutput\.icon\s*\|\|\s*output\.name\b/,
        mutation:'output.icon || output.name'},
    {label:'slot item display', pattern:/\bslot\.item\.displayName\s*\|\|\s*slot\.item\.name\b/,
        mutation:'slot.item.displayName || slot.item.name'},
    {label:'slot item icon', pattern:/\bslot\.item\.icon\s*\|\|\s*slot\.item\.name\b/,
        mutation:'slot.item.icon || slot.item.name'},
    {label:'source slot display', pattern:/\bsourceSlot\.item\.displayName\s*\|\|\s*sourceSlot\.item\.name\b/,
        mutation:'sourceSlot.item.displayName || sourceSlot.item.name'},
    {label:'source slot icon', pattern:/\bsourceSlot\.item\.icon\s*\|\|\s*sourceSlot\.item\.name\b/,
        mutation:'sourceSlot.item.icon || sourceSlot.item.name'},
    {label:'legacy catalog display', pattern:/\bitem\.displayname\s*\|\|\s*item\.item\b/,
        mutation:'item.displayname || item.item'},
    {label:'legacy catalog icon', pattern:/\bitem\.icon\s*\|\|\s*item\.item\b/,
        mutation:'item.icon || item.item'},
    {label:'canonical line display', pattern:/\bline\.displayName\s*\|\|\s*line\.itemName\b/,
        mutation:'line.displayName || line.itemName'},
    {label:'canonical line icon', pattern:/\bline\.icon\s*\|\|\s*line\.itemName\b/,
        mutation:'line.icon || line.itemName'},
    {label:'tooltip display', pattern:/\bdata\.displayname\s*\|\|\s*data\.itemName\b/,
        mutation:'data.displayname || data.itemName'},
    {label:'tooltip icon', pattern:/\bdata\.iconName\s*\|\|\s*data\.itemName\b/,
        mutation:'data.iconName || data.itemName'}
];

test('canonical presentation ratchet owns an exact production presenter inventory', () => {
    assert.strictEqual(new Set(PRESENTATION_FILES).size,PRESENTATION_FILES.length);
    for (const file of PRESENTATION_FILES) {
        assert.strictEqual(fs.existsSync(path.join(ROOT,file)),true,file);
    }
});

test('each raw-identity fallback rule catches its mutation without catching projected aliases', () => {
    for (const rule of RAW_IDENTITY_FALLBACKS) {
        assert.match(rule.mutation,rule.pattern,rule.label);
        assert.doesNotMatch('projection.displayName || candidate.name',rule.pattern,rule.label);
    }
});

test('production presenters never alias a raw internal identity into display or icon fields', () => {
    for (const file of PRESENTATION_FILES) {
        const body=source(file);
        for (const rule of RAW_IDENTITY_FALLBACKS) {
            assert.doesNotMatch(body,rule.pattern,file + ': ' + rule.label);
        }
    }
});

test('owned tooltip uses fixed display fallback and canonical icon-to-icon fallback', () => {
    const internal = 'rule.internal';
    const basic = Owned.basicTooltip({name:internal}, value => String(value));
    assert.doesNotMatch(basic, new RegExp(internal));
    assert.match(basic, /未知物品/);
    let observed = null;
    const tooltip = {
        dynamicIconHtml:key => { observed = key; return ''; },
        staticIconUrl:key => key,
        buildItemRichHtml:value => value,
        inferLayoutType:() => ''
    };
    Owned.richTooltip({name:internal,icon:'icon.snapshot'}, {}, tooltip);
    assert.strictEqual(observed, 'icon.snapshot');
    Owned.richTooltip({name:internal}, {}, tooltip);
    assert.strictEqual(observed, '');
});

test('KShop optional tooltip icon stays within canonical icon fields', () => {
    const item = {name:'rule.internal',icon:'icon.snapshot'};
    assert.strictEqual(KShopTooltip.ownedRichIconKey(item, {}), 'icon.snapshot');
    assert.strictEqual(KShopTooltip.ownedRichIconKey(item, {iconName:'icon.tooltip'}), 'icon.tooltip');
    assert.strictEqual(KShopTooltip.ownedRichIconKey({name:'rule.internal'}, {}), '');
});

test('Character projection uses neutral copy instead of exposing a raw internal name', () => {
    const internal='rule.internal.secret';
    const snapshot=CharacterProjection.viewSnapshot({
        equipment:[{slotKey:'头部装备',occupied:true,item:{name:internal}}],
        drugs:[],portrait:{},stateHealth:'ok'
    });
    assert.strictEqual(snapshot.equipment['头部装备'].name,'未知物品');
    assert.doesNotMatch(snapshot.equipment['头部装备'].name,new RegExp(internal));
    const candidates=CharacterProjection.viewCandidates({candidates:[{
        physicalSlot:0,item:{name:internal},source:{expectedLease:'lease.test.1'}
    }]});
    assert.strictEqual(candidates[0].name,'未命名候选');
    assert.doesNotMatch(candidates[0].name,new RegExp(internal));
});

console.log('Workbench canonical presentation boundary ' + passed + '/' + passed + ' passed');
