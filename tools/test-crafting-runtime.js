'use strict';

const assert = require('assert');
const Runtime = require('../launcher/web/modules/crafting-runtime.js');

let passed = 0;
function test(name, fn) {
    fn();
    passed++;
    console.log('PASS ' + name);
}

function triple(name) {
    return {name:name,displayName:name + ' 展示',icon:name + ' 图标'};
}

function clone(value) {
    return JSON.parse(JSON.stringify(value));
}

function envelope(cmd, body) {
    return Object.assign({
        type:'panel_resp', domain:'crafting', panel:'crafting',
        panelInstanceId:'crafting.test', cmd:cmd, callId:'craft.test.1'
    }, body);
}

function projectedItem(name, itemKind, quantity) {
    const stack = itemKind === 'stack';
    return {
        name:name, displayName:name + ' 展示', icon:name + ' 图标', itemKind:itemKind,
        value:stack ? quantity : 5, quantity:quantity, enhancementLevel:stack ? 0 : 5,
        majorType:stack ? '消耗品' : '武器', use:stack ? '药剂' : '刀',
        actionType:'', weaponType:stack ? '' : '刀', setId:'', setName:'', setOrder:0,
        requiredLevel:stack ? 1 : 12
    };
}

function projectedMaterial(name, storageKind, enough) {
    return {
        name:name, displayName:name + ' 展示', icon:name + ' 图标', itemKind:'stack',
        required:2, owned:enough ? 7 : 0, maxEnhancement:0, isQuantity:true, tier:'',
        consumed:true, enough:enough, storageKind:storageKind
    };
}

function outputDelivery(output, available) {
    return available
        ? {available:true, storageKind:'bag', mode:'insert', physicalSlot:3, quantity:output.quantity}
        : {available:false, storageKind:'unavailable', mode:'none', physicalSlot:-1, quantity:output.quantity};
}

function inventoryProjection(output) {
    const equipment = output.itemKind === 'equipment';
    const item = {
        name:output.name,displayName:output.displayName,icon:output.icon,
        majorType:output.majorType,use:output.use,actionType:output.actionType,
        weaponType:output.weaponType,setId:output.setId,setName:output.setName,
        setOrder:output.setOrder,itemKind:output.itemKind,quantity:output.quantity,
        enhancementLevel:output.enhancementLevel,maxEnhancementLevel:13,
        isMaxEnhancement:equipment && output.enhancementLevel >= 13,
        tierSlotAvailable:false,tierSlotUsed:false,modSlotCapacity:equipment ? 1 : 0,
        modSlotUsed:0,modSlots:[],modMeta:null,rarity:equipment ? 'rare' : ''
    };
    if (equipment) item.balanceSummary = {state:'confirmed',weightLayers:2,formula:1,
        level:output.enhancementLevel};
    return item;
}

function stableConfirm(item) {
    return {itemKind:item.itemKind,name:item.name,displayName:item.displayName,
        quantity:item.quantity,enhancementLevel:item.enhancementLevel,rarity:item.rarity,
        tier:'',modSignature:''};
}

function prototypeFor(output, delivery) {
    if (delivery.storageKind !== 'bag' && delivery.storageKind !== 'drug') return null;
    const item = inventoryProjection(output);
    return {item:item,confirmProjection:stableConfirm(item)};
}

function acceptedPlanFor(response) {
    return {category:response.category,recipeIndex:response.recipeIndex,
        craftCount:response.craftCount,output:clone(response.output),
        materials:clone(response.materials),outputDelivery:clone(response.outputDelivery),
        outputPrototype:prototypeFor(response.output,response.outputDelivery),cost:clone(response.cost)};
}

function receiptFor(plan) {
    if (!plan || !plan.outputPrototype) return null;
    const receipt = clone(plan.outputPrototype);
    if (plan.outputDelivery.mode === 'merge') receipt.item.quantity += 4;
    receipt.confirmProjection = stableConfirm(receipt.item);
    receipt.confirmProjection.lastUpdate = 123456789;
    return receipt;
}

const storageRouteMatrix = [
    {material:'information_collection', delivery:'information_collection', mode:'increment', slot:-1},
    {material:'bag', delivery:'bag', mode:'insert', slot:3},
    {material:'material_collection', delivery:'material_collection', mode:'increment', slot:-1},
    {material:'drug', delivery:'drug', mode:'merge', slot:4},
    {material:'bag_and_drug', delivery:'bag', mode:'merge', slot:5},
    {material:'unavailable', delivery:'unavailable', mode:'none', slot:-1, blocked:true}
];

function previewResponse(canCommit) {
    const output = projectedItem('预览产物', 'equipment', 1);
    const materials = [projectedMaterial('需求', canCommit ? 'bag' : 'unavailable', canCommit)];
    const cost = {money:90,kpoints:0};
    const delivery = outputDelivery(output, canCommit);
    const result = envelope('preview', {
        success:true, v:1, category:'武器合成', recipeIndex:0, craftCount:1,
        batchEligible:false, maxCraftCount:1, output:output, materials:materials, cost:cost,
        balance:{money:1000,kpoints:100}, skills:{reverseLevel:2,smithEnabled:true,smithLevel:2},
        levelAllowed:true, enoughMaterials:canCommit, enoughMoney:true, enoughKpoints:true,
        enoughSpace:canCommit, canCommit:canCommit,
        blockingError:canCommit ? '' : 'material_missing', outputDelivery:delivery
    });
    if (canCommit) {
        result.craftToken = 'craft.test.token';
        result.acceptedPlan = acceptedPlanFor(result);
    }
    return result;
}

function routedPreviewResponse(route) {
    const preview = previewResponse(!route.blocked);
    if (route.delivery !== 'bag' || route.mode === 'merge') {
        preview.output = projectedItem('测试药剂', 'stack', 1);
    }
    preview.materials[0].storageKind = route.material;
    preview.outputDelivery = {
        available:!route.blocked, storageKind:route.delivery, mode:route.mode,
        physicalSlot:route.slot, quantity:preview.output.quantity
    };
    preview.enoughSpace = !route.blocked;
    preview.enoughMaterials = !route.blocked;
    preview.canCommit = !route.blocked;
    preview.blockingError = route.blocked ? 'material_missing' : '';
    if (!route.blocked) {
        preview.acceptedPlan = acceptedPlanFor(preview);
    }
    return preview;
}

function commitResponse(authoritativePreview) {
    const preview = authoritativePreview || previewResponse(true);
    return envelope('commit', {
        success:true, v:1, operation:'commit', category:preview.category,
        recipeIndex:preview.recipeIndex, craftCount:preview.craftCount,
        crafted:clone(preview.output),
        acceptedPlan:preview.acceptedPlan ? clone(preview.acceptedPlan) : null,
        outputReceipt:preview.acceptedPlan ? receiptFor(preview.acceptedPlan) : null,
        balance:{money:910,kpoints:100}
    });
}

const cases = [
    {cmd:'snapshot', response:{success:true,recipes:[{output:triple('产物')}]} , leaves:[['recipes',0,'output']]},
    {cmd:'materials', response:{success:true,materials:[triple('材料')]} , leaves:[['materials',0]]},
    {cmd:'materialDetail', payload:{itemName:'当前材料'}, response:{success:true,material:triple('当前材料'),
        sources:[{kind:'enemy',enemyType:'enemy.internal',displayName:'敌人展示名'},
            {kind:'quest',questId:'quest.internal',title:'任务展示名'}],uses:[triple('用途')]} ,
        leaves:[['material'],['uses',0]]},
    {cmd:'preview', response:previewResponse(true),
        leaves:[['output'],['materials',0]]},
    {cmd:'commit', response:commitResponse(), leaves:[['crafted']]}
];

function atPath(value, path) {
    return path.reduce((current, key) => current[key], value);
}

test('Crafting accepts complete canonical identity leaves for every item response', () => {
    for (const item of cases) {
        assert.strictEqual(Runtime.validateBusinessResponse(item.response,
            {cmd:item.cmd,metadata:{payload:item.payload || {}}}),true,item.cmd);
    }
});

test('Crafting rejects every missing canonical display or icon field', () => {
    for (const item of cases) {
        for (const path of item.leaves) {
            for (const field of ['displayName','icon']) {
                const malformed = clone(item.response);
                delete atPath(malformed,path)[field];
                assert.strictEqual(Runtime.validateBusinessResponse(malformed,
                    {cmd:item.cmd,metadata:{payload:item.payload || {}}}),false,
                    item.cmd + ':' + path.join('.') + ':' + field);
            }
        }
    }
});

test('Crafting rejects empty, whitespace and wrapped-case undefined identity projections', () => {
    for (const field of ['name','displayName','icon']) {
        for (const value of ['', '   ', ' Undefined ']) {
            const malformed = {success:true,materials:[triple('材料')]};
            malformed.materials[0][field] = value;
            assert.strictEqual(Runtime.validateBusinessResponse(malformed,{cmd:'materials'}),false,
                field + ':' + JSON.stringify(value));
        }
    }
});

test('Crafting tooltip accepts only the canonical post-Host display spelling', () => {
    const valid = {success:true,itemName:'材料',displayName:'材料展示'};
    const entry = {cmd:'tooltip',metadata:{payload:{itemName:'材料'}}};
    assert.strictEqual(Runtime.validateBusinessResponse(valid,entry),true);
    const legacy = {success:true,itemName:'材料',displayname:'材料展示'};
    assert.strictEqual(Runtime.validateBusinessResponse(legacy,entry),false);
    const missing = {success:true,itemName:'材料'};
    assert.strictEqual(Runtime.validateBusinessResponse(missing,entry),false);
});

test('Crafting material detail and tooltip bind the exact requested internal selector', () => {
    const detail = {success:true,material:triple('当前材料'),sources:[],uses:[triple('用途')]};
    assert.strictEqual(Runtime.validateBusinessResponse(detail,
        {cmd:'materialDetail',metadata:{payload:{itemName:'伪造材料'}}}),false);
    assert.strictEqual(Runtime.validateBusinessResponse(
        {success:true,itemName:'当前材料',displayName:'当前材料展示'},
        {cmd:'tooltip',metadata:{payload:{itemName:'伪造材料'}}}),false);
});

test('Crafting source labels accept explicit equality and reject malformed labels', () => {
    const entry = {cmd:'materialDetail',metadata:{payload:{itemName:'当前材料'}}};
    const base = {success:true,material:triple('当前材料'),uses:[],sources:[
        {kind:'enemy',enemyType:'enemy.internal',displayName:'敌人展示名'},
        {kind:'quest',questId:'quest.internal',title:'任务展示名'}
    ]};
    assert.strictEqual(Runtime.validateBusinessResponse(base,entry),true);
    const equalLabels = clone(base);
    equalLabels.sources[0].displayName = equalLabels.sources[0].enemyType;
    equalLabels.sources[1].title = equalLabels.sources[1].questId;
    assert.strictEqual(Runtime.validateBusinessResponse(equalLabels,entry),true);
    for (const [index, field] of [[0,'displayName'],[1,'title']]) {
        for (const value of [undefined,null,17,{legacy:'bad'},'   ',' Undefined ']) {
            const malformed = clone(base);
            if (value === undefined) delete malformed.sources[index][field];
            else malformed.sources[index][field] = value;
            assert.strictEqual(Runtime.validateBusinessResponse(malformed,entry),false);
        }
    }
});

test('Crafting still delivers explicit failure responses without adopting identity data', () => {
    assert.strictEqual(Runtime.validateBusinessResponse({success:false,error:'stale_state'},{cmd:'snapshot'}),true);
    assert.strictEqual(Runtime.validateBusinessResponse({error:'stale_state'},{cmd:'snapshot'}),false);
});

test('Crafting preview requires exact storage, delivery and accepted-plan authority', () => {
    const entry = {cmd:'preview',metadata:{payload:{recipeIndex:0,craftCount:1}}};
    const valid = previewResponse(true);
    assert.strictEqual(Runtime.validateBusinessResponse(valid,entry),true);

    const noRoute = clone(valid);
    delete noRoute.materials[0].storageKind;
    assert.strictEqual(Runtime.validateBusinessResponse(noRoute,entry),false);

    const invalidDelivery = clone(valid);
    invalidDelivery.outputDelivery.mode = 'none';
    assert.strictEqual(Runtime.validateBusinessResponse(invalidDelivery,entry),false);

    const availabilityDrift = clone(valid);
    availabilityDrift.enoughSpace = false;
    assert.strictEqual(Runtime.validateBusinessResponse(availabilityDrift,entry),false);

    const planRouteDrift = clone(valid);
    planRouteDrift.acceptedPlan.materials[0].storageKind = 'drug';
    assert.strictEqual(Runtime.validateBusinessResponse(planRouteDrift,entry),false);

    const planCostDrift = clone(valid);
    planCostDrift.acceptedPlan.cost.money = 89;
    assert.strictEqual(Runtime.validateBusinessResponse(planCostDrift,entry),false);
});

test('Crafting blocked preview omits commit authority and fails closed on unobserved routes', () => {
    const blocked = previewResponse(false);
    assert.strictEqual(Object.prototype.hasOwnProperty.call(blocked,'craftToken'),false);
    assert.strictEqual(Object.prototype.hasOwnProperty.call(blocked,'acceptedPlan'),false);
    assert.strictEqual(Runtime.validateBusinessResponse(blocked,{cmd:'preview'}),true);

    const illegallyAuthorized = clone(blocked);
    illegallyAuthorized.canCommit = true;
    illegallyAuthorized.craftToken = 'craft.illegal';
    illegallyAuthorized.acceptedPlan = {
        category:illegallyAuthorized.category, recipeIndex:0, craftCount:1,
        output:clone(illegallyAuthorized.output), materials:clone(illegallyAuthorized.materials),
        outputDelivery:clone(illegallyAuthorized.outputDelivery),outputPrototype:null,
        cost:clone(illegallyAuthorized.cost)
    };
    assert.strictEqual(Runtime.validateBusinessResponse(illegallyAuthorized,{cmd:'preview'}),false);
});

for (const route of storageRouteMatrix) {
    test('Crafting route matrix validates exact preview-to-commit echo for ' + route.material, () => {
        const preview = routedPreviewResponse(route);
        const previewEntry = {cmd:'preview',metadata:{payload:{recipeIndex:0,craftCount:1}}};
        assert.strictEqual(Runtime.validateBusinessResponse(preview,previewEntry),true);
        assert.strictEqual(preview.materials[0].storageKind,route.material);
        assert.strictEqual(preview.outputDelivery.storageKind,route.delivery);
        if (route.blocked) {
            assert.strictEqual(Object.prototype.hasOwnProperty.call(preview,'craftToken'),false);
            assert.strictEqual(Object.prototype.hasOwnProperty.call(preview,'acceptedPlan'),false);
            const unadmittedCommit = commitResponse(preview);
            assert.strictEqual(Runtime.validateBusinessResponse(unadmittedCommit,{cmd:'commit'}),false);
            return;
        }
        assert.deepStrictEqual(preview.acceptedPlan.materials,preview.materials);
        assert.deepStrictEqual(preview.acceptedPlan.outputDelivery,preview.outputDelivery);
        const commit = commitResponse(preview);
        assert.strictEqual(Runtime.validateBusinessResponse(commit,{cmd:'commit'}),true);
        assert.deepStrictEqual(commit.acceptedPlan,preview.acceptedPlan);
        assert.deepStrictEqual(commit.crafted,preview.output);
    });
}

for (const variant of ['missing','mismatch','extra']) {
    test('Crafting route contracts reject ' + variant + ' delivery evidence', () => {
        const preview = routedPreviewResponse(storageRouteMatrix[1]);
        if (variant === 'missing') delete preview.outputDelivery.storageKind;
        if (variant === 'mismatch') preview.acceptedPlan.outputDelivery.mode = 'merge';
        if (variant === 'extra') preview.outputDelivery.legacyRoute = true;
        assert.strictEqual(Runtime.validateBusinessResponse(preview,
            {cmd:'preview',metadata:{payload:{recipeIndex:0,craftCount:1}}}),false);
    });
}

test('Crafting commit accepts only the exact plan echoed with the crafted projection', () => {
    const valid = commitResponse();
    assert.strictEqual(Runtime.validateBusinessResponse(valid,{cmd:'commit'}),true);

    const outputDrift = clone(valid);
    outputDrift.acceptedPlan.output.quantity = 2;
    assert.strictEqual(Runtime.validateBusinessResponse(outputDrift,{cmd:'commit'}),false);

    const routeDrift = clone(valid);
    routeDrift.acceptedPlan.outputDelivery.physicalSlot = 50;
    assert.strictEqual(Runtime.validateBusinessResponse(routeDrift,{cmd:'commit'}),false);

    const extraField = clone(valid);
    extraField.legacyAccepted = true;
    assert.strictEqual(Runtime.validateBusinessResponse(extraField,{cmd:'commit'}),false);
});

test('Crafting commit binds every equipment receipt field to the frozen prototype', () => {
    const mutations = [
        value => { value.outputReceipt.item.rarity = 'legendary'; },
        value => { value.outputReceipt.item.maxEnhancementLevel = 14; },
        value => { value.outputReceipt.item.modMeta = {name:'测试插件',displayName:'测试插件',
            icon:'测试插件',grade:'a',gradeLabel:'A',gradeColor:'#fff',role:'utility',
            roleLabel:'功能',symbol:'diamond',scope:'equipment'}; },
        value => { value.outputReceipt.confirmProjection.modSignature = '1:x;'; },
        value => { delete value.outputReceipt.item.balanceSummary; },
        value => { value.outputReceipt.item.balanceSummary.weightLayers = 3; }
    ];
    for (const mutate of mutations) {
        const malformed = commitResponse();
        mutate(malformed);
        assert.strictEqual(Runtime.validateBusinessResponse(malformed,{cmd:'commit'}),false);
    }
});

console.log('Crafting runtime identity boundary ' + passed + '/' + passed + ' passed');
