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

function v1CatalogMaterial(name) {
    return Object.assign(triple(name), {owned:7,sourceCount:1,useCount:1,hasSourceSummary:true});
}

function v1Use(name) {
    return Object.assign(triple(name), {
        itemKind:'stack',category:'武器合成',required:1
    });
}

function v1Detail(name) {
    return {success:true,v:1,view:'materials',
        material:Object.assign(triple(name), {description:'说明',owned:7,sourceSummary:'摘要'}),
        sources:[{kind:'enemy',enemyType:'敌人-测试',displayName:'测试敌人',
            probability:3,minLevel:0,maxLevel:2}],uses:[v1Use('用途')]};
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

function materialTaxonomy() {
    const registry = (labels, prefix) => labels.map((label, order) => ({
        id:(prefix || '') + label,label,order
    }));
    return {version:1,
        roots:[{id:'type',label:'类型',order:0},{id:'purpose',label:'用途',order:1}],
        types:[{id:'equipment_mod',label:'改装材料',order:0},
            {id:'food',label:'食材',order:1},{id:'general',label:'通用材料',order:2}],
        modAxes:[
            {id:'grade',label:'档级',order:0,values:[
                {id:'low',label:'低级',order:0,color:'#006600'},
                {id:'medium',label:'中等',order:1,color:'#996600'},
                {id:'high',label:'高等',order:2,color:'#0099FF'},
                {id:'special',label:'特殊',order:3,color:'#FFFF00'}]},
            {id:'scope',label:'适用范围',order:1,values:registry(
                ['armor','firearm','blade','fist','universal','underbarrel']).map((entry, order) => ({
                    id:entry.id,label:['防具','枪械','刀具','拳套','通用','下挂武器'][order],order
                }))},
            {id:'role',label:'定位',order:2,values:registry(
                ['firepower','precision','stability','sustain','utility','mechanism']).map((entry, order) => ({
                    id:entry.id,label:['火力','精准与操控','稳定与防护','续航','结构与功能','特殊机制'][order],order,
                    symbol:['triangle-solid','triangle-outline','square-outline','circle-outline','diamond-outline','star-solid'][order]
                }))}
        ],
        recipePurposes:registry(['铁枪会','属性武器','烹饪','化学生产','武器合成','饰品合成',
            '进阶防具','基础防具','公社防具','黑白契约','插件合成','大学装备'],'recipe:'),
        directPurposes:[{id:'system:equipment_tuning',label:'装备改装',order:0}],
        fallback:{id:'unstructured',label:'尚未结构化用途',order:2147483647}};
}

function enemyVariant(occurrenceIndex, chanceRaw, minReverseLevel, maxReverseLevel) {
    return {occurrenceIndex,chanceRaw,chanceInputState:'explicit',
        nominalChancePercent:chanceRaw,minReverseLevel,maxReverseLevel,
        quantityMin:1,quantityMax:1};
}

function v2Sources(itemName) {
    return [
        {kind:'craft',sourceKey:'source.craft',sourceOrder:0,category:'武器合成',recipeIndex:7,
            productName:itemName,price:100,kpoints:0},
        {kind:'shop',sourceKey:'source.shop',sourceOrder:1,shopId:'迷之盔甲君',catalogIndex:57,
            itemName,basePrice:50000,unitPriceAtSnapshot:45000,requiredInfo:'需要情报',locked:false,
            shopAccessMode:'unavailable',shopAccessReason:'no_authoritative_remote_access_capability'},
        {kind:'kshop',sourceKey:'source.kshop',sourceOrder:2,catalogIndex:3,entryId:'entry.test',
            category:'材料',priceK:12},
        {kind:'quest',sourceKey:'source.quest',sourceOrder:3,questId:'quest.test',rewardSet:'base',
            authoredIndex:0,title:'测试任务',quantity:2},
        {kind:'stage',sourceKey:'source.stage',sourceOrder:4,stageName:'测试关卡',
            chanceModel:'stage_roll_divisor_with_legacy_domain_branch',legacyConditionId:'andylaw_domain_bonus',
            variants:[
                {occurrenceIndex:0,rollDivisor:2,defaultBranchChancePercent:50,quantityMin:1,quantityMax:2},
                {occurrenceIndex:1,rollDivisor:8,defaultBranchChancePercent:12.5,quantityMin:1,quantityMax:1}
            ]},
        {kind:'enemy',sourceKey:'source.enemy',sourceOrder:5,enemyType:'敌人-测试',displayName:'测试敌人',
            chanceModel:'enemy_prd_with_reverse_bonus',variants:[
                enemyVariant(0,3,null,2),enemyVariant(1,5,3,null)
            ]}
    ];
}

function v2CatalogResponse(name) {
    return {success:true,v:2,view:'materials',snapshotId:'materials.snapshot.test',
        navigationAccess:{shop:true,crafting:true},taxonomy:materialTaxonomy(),materials:[{
            name,displayName:name + ' 展示',icon:name + ' 图标',owned:7,archiveOrder:0,
            typeId:'equipment_mod',modFacetIds:{grade:'high',scope:'firearm',role:'mechanism'},
            recipePurposeIds:['recipe:武器合成'],directPurposeIds:['system:equipment_tuning'],
            structuredPurposeCount:2,sourceCount:6,dropVariantCount:4,useCount:1,
            hasSourceSummary:true
        }]};
}

function v2DetailResponse(name) {
    return {success:true,v:2,view:'materials',snapshotId:'materials.snapshot.test',
        material:{name,displayName:name + ' 展示',icon:name + ' 图标',description:'说明\n第二行',
            owned:7,sourceSummary:'摘要\t可核验'},
        sourceCount:6,dropVariantCount:4,useCount:1,structuredPurposeCount:2,
        sources:v2Sources(name),
        directPurposes:[{id:'system:equipment_tuning',label:'装备改装',order:0}],
        uses:[{category:'武器合成',recipeIndex:7,productName:'测试产物',displayName:'测试产物展示',
            icon:'测试产物图标',itemKind:'equipment',required:2,
            ingredients:[
                {name,displayName:name + ' 展示',icon:name + ' 图标',required:2,isQuantity:true},
                {name:'辅助材料',displayName:'辅助材料',icon:'辅助材料图标',required:1,isQuantity:true}
            ]}]};
}

function infrastructureProject(name, projectOrder, currentLevel, maximumLevel, requiredValues) {
    return {infrastructureName:name,projectOrder,currentLevel,maximumLevel,
        levels:requiredValues.map((required, levelIndex) => {
            const status = currentLevel > levelIndex ? 'completed'
                : currentLevel === levelIndex ? 'current' : 'future';
            return {levelIndex,targetLevel:levelIndex + 1,required,owned:7,
                missing:status === 'completed' ? 0 : Math.max(required - 7, 0),status};
        })};
}

function v2InfrastructureDetailResponse(name) {
    const detail = v2DetailResponse(name);
    detail.directPurposes = [
        {id:'system:infrastructure_upgrade',label:'基建升级',order:1}
    ];
    detail.infrastructureUses = [
        infrastructureProject('测试基建甲',0,1,3,[20,10,5]),
        {infrastructureName:'测试基建丙',projectOrder:2,currentLevel:0,maximumLevel:2,
            levels:[{levelIndex:1,targetLevel:2,required:9,owned:7,missing:2,status:'future'}]}
    ];
    return detail;
}

const cases = [
    {cmd:'snapshot', response:{success:true,recipes:[{output:triple('产物')}]} , leaves:[['recipes',0,'output']]},
    {cmd:'materials', payload:{v:1},
        response:{success:true,v:1,view:'materials',materials:[v1CatalogMaterial('材料')]} ,
        leaves:[['materials',0]]},
    {cmd:'materialDetail', payload:{v:1,itemName:'当前材料'}, response:v1Detail('当前材料'),
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
            const malformed = {success:true,v:1,view:'materials',materials:[v1CatalogMaterial('材料')]};
            malformed.materials[0][field] = value;
            assert.strictEqual(Runtime.validateBusinessResponse(malformed,{cmd:'materials',metadata:{payload:{v:1}}}),false,
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
    const detail = v1Detail('当前材料');
    assert.strictEqual(Runtime.validateBusinessResponse(detail,
        {cmd:'materialDetail',metadata:{payload:{v:1,itemName:'伪造材料'}}}),false);
    assert.strictEqual(Runtime.validateBusinessResponse(
        {success:true,itemName:'当前材料',displayName:'当前材料展示'},
        {cmd:'tooltip',metadata:{payload:{itemName:'伪造材料'}}}),false);
});

test('Crafting source labels accept explicit equality and reject malformed labels', () => {
    const entry = {cmd:'materialDetail',metadata:{payload:{v:1,itemName:'当前材料'}}};
    const base = v1Detail('当前材料');
    base.sources.push({kind:'quest',questId:'quest.internal',title:'任务展示名',quantity:1});
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

test('Crafting materials negotiates one complete v2 catalog or one exact v1 downgrade', () => {
    const v2 = v2CatalogResponse('战术握把');
    assert.strictEqual(Runtime.validateBusinessResponse(v2,
        {cmd:'materials',metadata:{payload:{v:2}}}),true);
    const v1 = {success:true,v:1,view:'materials',materials:[v1CatalogMaterial('旧材料')]};
    assert.strictEqual(Runtime.validateBusinessResponse(v1,
        {cmd:'materials',metadata:{payload:{v:2}}}),true);
    assert.strictEqual(Runtime.validateBusinessResponse(v2,
        {cmd:'materials',metadata:{payload:{v:1}}}),false);
    assert.strictEqual(Runtime.validateBusinessResponse(v2,
        {cmd:'materials',metadata:{payload:{v:3}}}),false);
    const downgradedDetail = v1Detail('旧材料');
    downgradedDetail.sources = [{kind:'kshop',category:'',priceK:12}];
    assert.strictEqual(Runtime.validateBusinessResponse(downgradedDetail,
        {cmd:'materialDetail',metadata:{payload:{v:1,itemName:'旧材料'}}}),true);
    const downgradedCategory512 = clone(downgradedDetail);
    downgradedCategory512.sources[0].category = '类'.repeat(512);
    assert.strictEqual(Runtime.validateBusinessResponse(downgradedCategory512,
        {cmd:'materialDetail',metadata:{payload:{v:1,itemName:'旧材料'}}}),true);
    const downgradedCategory513 = clone(downgradedDetail);
    downgradedCategory513.sources[0].category = '类'.repeat(513);
    assert.strictEqual(Runtime.validateBusinessResponse(downgradedCategory513,
        {cmd:'materialDetail',metadata:{payload:{v:1,itemName:'旧材料'}}}),false);
});

test('Crafting v2 catalog enforces taxonomy closure, archive order and purpose counts', () => {
    const entry = {cmd:'materials',metadata:{payload:{v:2}}};
    const missing = v2CatalogResponse('战术握把');
    delete missing.materials[0].archiveOrder;
    assert.strictEqual(Runtime.validateBusinessResponse(missing,entry),false);
    const extra = v2CatalogResponse('战术握把');
    extra.materials[0].legacyGuess = true;
    assert.strictEqual(Runtime.validateBusinessResponse(extra,entry),false);
    const unknownFacet = v2CatalogResponse('战术握把');
    unknownFacet.materials[0].modFacetIds.role = 'unknown';
    assert.strictEqual(Runtime.validateBusinessResponse(unknownFacet,entry),false);
    const purposeDrift = v2CatalogResponse('战术握把');
    purposeDrift.materials[0].structuredPurposeCount = 3;
    assert.strictEqual(Runtime.validateBusinessResponse(purposeDrift,entry),false);
    const archiveDrift = v2CatalogResponse('战术握把');
    archiveDrift.materials[0].archiveOrder = 1;
    assert.strictEqual(Runtime.validateBusinessResponse(archiveDrift,entry),false);
    const missingAccess = v2CatalogResponse('战术握把');
    delete missingAccess.navigationAccess;
    assert.strictEqual(Runtime.validateBusinessResponse(missingAccess,entry),false);
    const malformedAccess = v2CatalogResponse('战术握把');
    malformedAccess.navigationAccess.crafting = 1;
    assert.strictEqual(Runtime.validateBusinessResponse(malformedAccess,entry),false);
    const extraAccess = v2CatalogResponse('战术握把');
    extraAccess.navigationAccess.vehicleTier = 2;
    assert.strictEqual(Runtime.validateBusinessResponse(extraAccess,entry),false);

    function directRegistry(count) {
        return Array.from({length:count}, (_, order) => ({
            id:order === 0 ? 'system:equipment_tuning' : 'system:test:' + order,
            label:order === 0 ? '装备改装' : '测试用途 ' + order,
            order
        }));
    }
    const taxonomy1024 = v2CatalogResponse('战术握把');
    taxonomy1024.taxonomy.directPurposes = directRegistry(987);
    assert.strictEqual(Runtime.validateBusinessResponse(taxonomy1024,entry),true);
    const taxonomy1025 = v2CatalogResponse('战术握把');
    taxonomy1025.taxonomy.directPurposes = directRegistry(988);
    assert.strictEqual(Runtime.validateBusinessResponse(taxonomy1025,entry),false);

    const direct128 = v2CatalogResponse('战术握把');
    direct128.taxonomy.directPurposes = directRegistry(128);
    direct128.materials[0].directPurposeIds = direct128.taxonomy.directPurposes
        .map(value => value.id);
    direct128.materials[0].structuredPurposeCount = 129;
    assert.strictEqual(Runtime.validateBusinessResponse(direct128,entry),true);
    const direct129 = v2CatalogResponse('战术握把');
    direct129.taxonomy.directPurposes = directRegistry(129);
    direct129.materials[0].directPurposeIds = direct129.taxonomy.directPurposes
        .map(value => value.id);
    direct129.materials[0].structuredPurposeCount = 130;
    assert.strictEqual(Runtime.validateBusinessResponse(direct129,entry),false);
    const directMalformed = v2CatalogResponse('战术握把');
    directMalformed.materials[0].directPurposeIds = null;
    assert.strictEqual(Runtime.validateBusinessResponse(directMalformed,entry),false);
});

test('Crafting v2 detail accepts all source variants and exact occurrence identities', () => {
    const detail = v2DetailResponse('战术握把');
    const entry = {cmd:'materialDetail',metadata:{payload:{v:2,itemName:'战术握把',
        snapshotId:'materials.snapshot.test'}}};
    assert.strictEqual(Runtime.validateBusinessResponse(detail,entry),true);
    const occurrenceDrift = clone(detail);
    occurrenceDrift.sources[5].variants[1].occurrenceIndex = 0;
    assert.strictEqual(Runtime.validateBusinessResponse(occurrenceDrift,entry),false);
    const sourceOrderDrift = clone(detail);
    sourceOrderDrift.sources[5].sourceOrder = 4;
    assert.strictEqual(Runtime.validateBusinessResponse(sourceOrderDrift,entry),false);
    const duplicateKey = clone(detail);
    duplicateKey.sources[5].sourceKey = duplicateKey.sources[4].sourceKey;
    assert.strictEqual(Runtime.validateBusinessResponse(duplicateKey,entry),false);
    const guessedModel = clone(detail);
    guessedModel.sources[4].chanceModel = 'simple_percent';
    assert.strictEqual(Runtime.validateBusinessResponse(guessedModel,entry),false);
    const remoteShopExpansion = clone(detail);
    remoteShopExpansion.sources[1].shopAccessMode = 'full';
    assert.strictEqual(Runtime.validateBusinessResponse(remoteShopExpansion,entry),false);
    const shopItemDrift = clone(detail);
    shopItemDrift.sources[1].itemName = '另一种材料';
    assert.strictEqual(Runtime.validateBusinessResponse(shopItemDrift,entry),false);
    const foreignCraft = clone(detail);
    foreignCraft.sources[0].productName = '另一种材料';
    assert.strictEqual(Runtime.validateBusinessResponse(foreignCraft,entry),false);
    const strippedEnemyType = clone(detail);
    strippedEnemyType.sources[5].enemyType = '测试';
    assert.strictEqual(Runtime.validateBusinessResponse(strippedEnemyType,entry),false);
    const optionalKshopCategory = clone(detail);
    optionalKshopCategory.sources[2].category = '';
    assert.strictEqual(Runtime.validateBusinessResponse(optionalKshopCategory,entry),true);
    const maxEnemyLabel = clone(detail);
    maxEnemyLabel.sources[5].displayName = '敌'.repeat(512);
    assert.strictEqual(Runtime.validateBusinessResponse(maxEnemyLabel,entry),true);
    const overlongEnemyLabel = clone(detail);
    overlongEnemyLabel.sources[5].displayName = '敌'.repeat(513);
    assert.strictEqual(Runtime.validateBusinessResponse(overlongEnemyLabel,entry),false);
});

test('Crafting v2 detail binds snapshot, selector and all derived counts', () => {
    const entry = {cmd:'materialDetail',metadata:{payload:{v:2,itemName:'战术握把',
        snapshotId:'materials.snapshot.test'}}};
    const stale = v2DetailResponse('战术握把');
    stale.snapshotId = 'materials.snapshot.old';
    assert.strictEqual(Runtime.validateBusinessResponse(stale,entry),false);
    const countDrift = v2DetailResponse('战术握把');
    countDrift.dropVariantCount = 3;
    assert.strictEqual(Runtime.validateBusinessResponse(countDrift,entry),false);
    const recipeDrift = v2DetailResponse('战术握把');
    recipeDrift.uses[0].recipeIndex = 1000;
    assert.strictEqual(Runtime.validateBusinessResponse(recipeDrift,entry),false);
    const ingredientDrift = v2DetailResponse('战术握把');
    ingredientDrift.uses[0].ingredients[0].required = 3;
    assert.strictEqual(Runtime.validateBusinessResponse(ingredientDrift,entry),false);
    const ingredientIconMissing = v2DetailResponse('战术握把');
    delete ingredientIconMissing.uses[0].ingredients[0].icon;
    assert.strictEqual(Runtime.validateBusinessResponse(ingredientIconMissing,entry),false);
    const legacyUse = v2DetailResponse('战术握把');
    delete legacyUse.uses[0].ingredients;
    assert.strictEqual(Runtime.validateBusinessResponse(legacyUse,entry),true);
    const nonFinite = v2DetailResponse('战术握把');
    nonFinite.sources[1].unitPriceAtSnapshot = Infinity;
    assert.strictEqual(Runtime.validateBusinessResponse(nonFinite,entry),false);
    const v1DetailOnV2 = v1Detail('战术握把');
    assert.strictEqual(Runtime.validateBusinessResponse(v1DetailOnV2,entry),false);
});

test('Crafting v2 infrastructure uses are conditional and exact', () => {
    const entry = {cmd:'materialDetail',metadata:{payload:{v:2,itemName:'战术握把',
        snapshotId:'materials.snapshot.test'}}};
    const valid = v2InfrastructureDetailResponse('战术握把');
    assert.strictEqual(Runtime.validateBusinessResponse(valid,entry),true);

    const historicalExtra = v2DetailResponse('战术握把');
    historicalExtra.infrastructureUses = [];
    assert.strictEqual(Runtime.validateBusinessResponse(historicalExtra,entry),false);
    const missingConditional = clone(valid);
    delete missingConditional.infrastructureUses;
    assert.strictEqual(Runtime.validateBusinessResponse(missingConditional,entry),false);

    const mutations = [
        value => { value.infrastructureUses[0].legacyId = 1; },
        value => { value.infrastructureUses[1].projectOrder = 0; },
        value => { value.infrastructureUses[0].currentLevel = 4; },
        value => { value.infrastructureUses[0].levels[1].targetLevel = 3; },
        value => { value.infrastructureUses[0].levels[1].status = 'future'; },
        value => { value.infrastructureUses[0].levels[0].missing = 13; },
        value => { value.infrastructureUses[0].levels[1].missing = 2; },
        value => { value.infrastructureUses[0].levels[1].owned = 8; },
        value => { value.infrastructureUses[0].levels[2].levelIndex = 1; }
    ];
    for (const mutate of mutations) {
        const malformed = clone(valid);
        mutate(malformed);
        assert.strictEqual(Runtime.validateBusinessResponse(malformed,entry),false);
    }
});

test('Crafting v2 infrastructure uses enforce project and level caps', () => {
    const entry = {cmd:'materialDetail',metadata:{payload:{v:2,itemName:'战术握把',
        snapshotId:'materials.snapshot.test'}}};
    const projectsAtCap = v2InfrastructureDetailResponse('战术握把');
    projectsAtCap.infrastructureUses = Array.from({length:256}, (_, index) =>
        infrastructureProject('测试基建' + index,index,0,1,[8]));
    assert.strictEqual(Runtime.validateBusinessResponse(projectsAtCap,entry),true);
    const projectsOverCap = clone(projectsAtCap);
    projectsOverCap.infrastructureUses.push(
        infrastructureProject('测试基建256',256,0,1,[8]));
    assert.strictEqual(Runtime.validateBusinessResponse(projectsOverCap,entry),false);

    const levelsAtCap = v2InfrastructureDetailResponse('战术握把');
    levelsAtCap.infrastructureUses = [
        infrastructureProject('测试基建',0,0,128,Array(128).fill(8))
    ];
    assert.strictEqual(Runtime.validateBusinessResponse(levelsAtCap,entry),true);
    const levelsOverCap = v2InfrastructureDetailResponse('战术握把');
    levelsOverCap.infrastructureUses = [
        infrastructureProject('测试基建',0,0,129,Array(129).fill(8))
    ];
    assert.strictEqual(Runtime.validateBusinessResponse(levelsOverCap,entry),false);
});

test('Crafting v2 shop access accepts only the two frozen pairs and bounds NPC catalog indices', () => {
    const entry = {cmd:'materialDetail',metadata:{payload:{v:2,itemName:'战术握把',
        snapshotId:'materials.snapshot.test'}}};
    const full = v2DetailResponse('战术握把');
    full.sources[1].shopAccessMode = 'full';
    full.sources[1].shopAccessReason = 'indexed_live_match';
    full.sources[1].catalogIndex = Runtime.SHOP_CATALOG_INDEX_MAX;
    assert.strictEqual(Runtime.validateBusinessResponse(full,entry),true);

    const overflow = clone(full);
    overflow.sources[1].catalogIndex = Runtime.SHOP_CATALOG_INDEX_MAX + 1;
    assert.strictEqual(Runtime.validateBusinessResponse(overflow,entry),false);
    const crossedPair = clone(full);
    crossedPair.sources[1].shopAccessReason = 'no_authoritative_remote_access_capability';
    assert.strictEqual(Runtime.validateBusinessResponse(crossedPair,entry),false);

    const kshopUnchanged = clone(full);
    kshopUnchanged.sources[2].catalogIndex = Runtime.SHOP_CATALOG_INDEX_MAX + 1;
    assert.strictEqual(Runtime.validateBusinessResponse(kshopUnchanged,entry),true);
});

test('Crafting material-to-shop navigation emits the exact ten-key envelope', () => {
    const input = {callId:'material-nav.test-1',panelInstanceId:'crafting.test~1',
        materialSnapshotId:'materials.snapshot.test',materialName:'战术握把',
        shopId:'迷之盔甲君',catalogIndex:57};
    assert.deepStrictEqual(Runtime.createMaterialShopNavigationMessage(input),{
        type:'panel',panel:'crafting',cmd:'open_npc_shop',callId:'material-nav.test-1',
        panelInstanceId:'crafting.test~1',source:'crafting_materials',
        materialSnapshotId:'materials.snapshot.test',materialName:'战术握把',
        shopId:'迷之盔甲君',catalogIndex:57
    });
    for (const malformed of [
        Object.assign({},input,{callId:'bad call'}),
        Object.assign({},input,{panelInstanceId:'bad instance'}),
        Object.assign({},input,{materialSnapshotId:''}),
        Object.assign({},input,{materialName:' Undefined '}),
        Object.assign({},input,{shopId:'商'.repeat(81)}),
        Object.assign({},input,{catalogIndex:10001})
    ]) assert.strictEqual(Runtime.createMaterialShopNavigationMessage(malformed),null);
    assert.strictEqual(Runtime.NAVIGATION_WATCHDOG_MS,6500);
});

test('Crafting material-to-shop public failure is exact, enumerated and correlated', () => {
    const expected = {callId:'material-nav.test-1',panelInstanceId:'crafting.test~1'};
    const failure = {type:'panel_resp',panel:'crafting',cmd:'open_npc_shop',
        callId:expected.callId,panelInstanceId:expected.panelInstanceId,
        success:false,error:'stale_source'};
    assert.strictEqual(Runtime.validateMaterialShopNavigationFailure(failure,expected),true);
    for (const mutate of [
        value => { value.extra = true; },
        value => { value.success = true; },
        value => { value.error = 'catalog_not_current'; },
        value => { value.callId = 'material-nav.foreign'; },
        value => { value.panelInstanceId = 'crafting.foreign'; },
        value => { value.panel = 'npcshop'; }
    ]) {
        const malformed = clone(failure);
        mutate(malformed);
        assert.strictEqual(Runtime.validateMaterialShopNavigationFailure(malformed,expected),false);
    }
});

test('Crafting material identities and multiline fields enforce UTF-16 and control boundaries', () => {
    const catalogEntry = {cmd:'materials',metadata:{payload:{v:2}}};
    const maxName = '材'.repeat(128), valid = v2CatalogResponse(maxName);
    assert.strictEqual(Runtime.validateBusinessResponse(valid,catalogEntry),true);
    const tooLong = v2CatalogResponse('材'.repeat(129));
    assert.strictEqual(Runtime.validateBusinessResponse(tooLong,catalogEntry),false);
    for (const invalidName of [' Undefined ', '材料\u0001',
        '材料' + String.fromCharCode(128)]) {
        assert.strictEqual(Runtime.validateBusinessResponse(
            v2CatalogResponse(invalidName),catalogEntry),false);
    }
    const detailEntry = {cmd:'materialDetail',metadata:{payload:{v:2,itemName:'战术握把',
        snapshotId:'materials.snapshot.test'}}};
    const allowed = v2DetailResponse('战术握把');
    allowed.material.description = '第一行\r\n第二行\t说明';
    assert.strictEqual(Runtime.validateBusinessResponse(allowed,detailEntry),true);
    const control = v2DetailResponse('战术握把');
    control.material.sourceSummary = '摘要\u000b非法';
    assert.strictEqual(Runtime.validateBusinessResponse(control,detailEntry),false);
    const c1Control = v2DetailResponse('战术握把');
    c1Control.material.sourceSummary = '摘要' + String.fromCharCode(159) + '非法';
    assert.strictEqual(Runtime.validateBusinessResponse(c1Control,detailEntry),false);
});

test('Crafting material failures remain versionless exact business results', () => {
    const entry = {cmd:'materialDetail',metadata:{payload:{v:2,itemName:'战术握把',
        snapshotId:'materials.snapshot.test'}}};
    assert.strictEqual(Runtime.validateBusinessResponse(
        {success:false,error:'stale_snapshot'},entry),true);
    assert.strictEqual(Runtime.validateBusinessResponse(
        {success:false,error:'stale_snapshot',v:2},entry),false);
    assert.strictEqual(Runtime.validateBusinessResponse(
        {success:false,error:'stale_snapshot',extra:true},entry),false);
    assert.strictEqual(Runtime.validateBusinessResponse(
        {success:false,error:'stale_snapshot'},
        {cmd:'materials',metadata:{payload:{v:2}}}),false);
    assert.strictEqual(Runtime.validateBusinessResponse(
        {success:false,error:'stale_snapshot'},
        {cmd:'materialDetail',metadata:{payload:{v:1,itemName:'战术握把'}}}),false);
});

test('Crafting still delivers explicit failure responses without adopting identity data', () => {
    assert.strictEqual(Runtime.validateBusinessResponse({success:false,error:'stale_state'},{cmd:'snapshot'}),true);
    assert.strictEqual(Runtime.validateBusinessResponse({error:'stale_state'},{cmd:'snapshot'}),false);
});

test('Crafting RequestMux cancel delegates exact call retirement and suppresses its late response', () => {
    const sent = [];
    let callbackCount = 0;
    const mux = new Runtime.RequestMux({
        send:message => { sent.push(clone(message)); return true; },
        sessionNonce:'cancel-test',timeoutMs:1000,
        setTimer:() => 17,clearTimer:() => {}
    });
    assert.strictEqual(mux.openSession({ownerPanel:'crafting',
        panelInstanceId:'crafting.test'}),true);
    const callId = mux.request('snapshot',{v:1,category:'武器合成'},() => {
        callbackCount++;
    });
    assert.ok(callId);
    assert.strictEqual(sent.length,1);
    assert.strictEqual(mux.debugState().pendingCount,1);
    assert.strictEqual(mux.cancel(callId),true);
    assert.strictEqual(mux.cancel(callId),false);
    assert.strictEqual(mux.debugState().pendingCount,0);
    assert.strictEqual(mux.handleResponse({
        type:'panel_resp',domain:'crafting',panel:'crafting',
        panelInstanceId:'crafting.test',cmd:'snapshot',callId,
        success:true,v:1,category:'武器合成',recipes:[{output:triple('迟到产物')}]
    }),false);
    assert.strictEqual(callbackCount,0);
    mux.destroy();
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
