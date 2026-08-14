/** Crafting request facade backed by the shared panel runtime. */
(function(root, factory) {
    'use strict';
    var shared = typeof module !== 'undefined' && module.exports
        ? require('./panel-runtime.js') : root && root.PanelRuntime;
    var inventory = typeof module !== 'undefined' && module.exports
        ? require('./inventory-runtime.js') : root && root.InventoryRuntime;
    var api = factory(shared, inventory);
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    if (root) root.CraftingRuntime = api;
})(typeof window !== 'undefined' ? window : globalThis, function(PanelRuntime, InventoryRuntime) {
    'use strict';
    if (!PanelRuntime || !PanelRuntime.PanelRequestMux) throw new Error('PanelRuntime is required');
    if (!InventoryRuntime || !InventoryRuntime.isValidItemProjection
            || !InventoryRuntime.isValidConfirmProjection
            || !InventoryRuntime.isValidStableConfirmProjection) {
        throw new Error('InventoryRuntime projection validators are required');
    }

    function containsC1Control(value) {
        if (typeof value !== 'string') return false;
        for (var index = 0; index < value.length; index++) {
            var code = value.charCodeAt(index);
            if (code >= 128 && code <= 159) return true;
        }
        return false;
    }

    function strictText(value) {
        if (containsC1Control(value)) return false;
        return typeof value === 'string' && value.length <= 256
            && value.trim().length > 0 && value.trim().toLowerCase() !== 'undefined'
            && !/[\u0000-\u001f\u007f]/.test(value);
    }

    function identityTriple(value, internalField) {
        return !!value && typeof value === 'object'
            && strictText(value[internalField])
            && strictText(value.displayName)
            && strictText(value.icon);
    }

    function identityArray(value, internalField) {
        return Array.isArray(value) && value.every(function(item) {
            return identityTriple(item, internalField);
        });
    }

    function own(value, key) {
        return Object.prototype.hasOwnProperty.call(value || {}, key);
    }

    function exactKeys(value, keys) {
        if (!value || typeof value !== 'object' || Array.isArray(value)) return false;
        var actual = Object.keys(value).sort();
        var expected = keys.slice().sort();
        return actual.length === expected.length && actual.every(function(key, index) {
            return key === expected[index];
        });
    }

    var MAX_SAFE_INTEGER = 9007199254740991;
    var SHOP_CATALOG_INDEX_MAX = 10000;
    var NAVIGATION_WATCHDOG_MS = 6500;
    var NAVIGATION_CALL_ID_PATTERN = /^[A-Za-z0-9._-]{1,96}$/;
    var PANEL_INSTANCE_PATTERN = /^[A-Za-z0-9._~-]{1,128}$/;
    var MATERIAL_SHOP_FAILURE_ERRORS = {
        invalid_payload:true, stale_source:true, navigation_unavailable:true,
        access_denied:true, source_not_settled:true, admission_failed:true,
        timeout:true, busy:true
    };
    var MATERIAL_LIMIT = 4096, SOURCE_LIMIT = 512, VARIANT_LIMIT = 128,
        USE_LIMIT = 1024, INGREDIENT_LIMIT = 64,
        DIRECT_PURPOSE_LIMIT = 128, TAXONOMY_LIMIT = 1024,
        INFRASTRUCTURE_PROJECT_LIMIT = 256, INFRASTRUCTURE_LEVEL_LIMIT = 128;
    var INFRASTRUCTURE_PURPOSE_ID = 'system:infrastructure_upgrade';

    function identityText(value, maxLength) {
        if (containsC1Control(value)) return false;
        return typeof value === 'string' && value.length >= 1 && value.length <= maxLength
            && value.trim().length > 0 && value.trim().toLowerCase() !== 'undefined'
            && !/[\u0000-\u001f\u007f]/.test(value);
    }

    function optionalText(value, maxLength) {
        if (containsC1Control(value)) return false;
        return typeof value === 'string' && value.length <= maxLength
            && !/[\u0000-\u001f\u007f]/.test(value);
    }

    function multilineText(value, maxLength) {
        if (containsC1Control(value)) return false;
        return typeof value === 'string' && value.length <= maxLength
            && !/[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f]/.test(value);
    }

    function safeInteger(value) {
        return Number.isInteger(value) && value >= 0 && value <= MAX_SAFE_INTEGER;
    }

    function shopCatalogIndex(value) {
        return Number.isInteger(value) && value >= 0 && value <= SHOP_CATALOG_INDEX_MAX;
    }

    function positiveInteger(value) {
        return Number.isInteger(value) && value >= 1 && value <= MAX_SAFE_INTEGER;
    }

    function recipeIndex(value) {
        return Number.isInteger(value) && value >= 0 && value <= 999;
    }

    function finiteNonNegativeNumber(value) {
        return typeof value === 'number' && isFinite(value) && value >= 0;
    }

    function businessKeys(data, keys) {
        var hasEnvelope = own(data, 'type') || own(data, 'panel') || own(data, 'callId');
        return exactKeys(data, hasEnvelope ? RESPONSE_ENVELOPE.concat(keys) : keys);
    }

    function distinct(values, keyOf) {
        var seen = Object.create(null);
        for (var index = 0; index < values.length; index++) {
            var raw = keyOf(values[index], index), textValue = String(raw);
            var key = typeof raw + ':' + textValue.length + ':' + textValue;
            if (seen[key]) return false;
            seen[key] = true;
        }
        return true;
    }

    function continuousOrder(values) {
        return values.every(function(value, index) { return value.order === index; });
    }

    function same(left, right) {
        if (left === right) return true;
        if (Array.isArray(left) || Array.isArray(right)) {
            return Array.isArray(left) && Array.isArray(right)
                && left.length === right.length && left.every(function(value, index) {
                    return same(value, right[index]);
                });
        }
        if (!left || !right || typeof left !== 'object' || typeof right !== 'object') return false;
        var leftKeys = Object.keys(left).sort(), rightKeys = Object.keys(right).sort();
        return leftKeys.length === rightKeys.length
            && leftKeys.every(function(key, index) {
                return key === rightKeys[index] && same(left[key], right[key]);
            });
    }

    var RESPONSE_ENVELOPE = ['type', 'domain', 'panel', 'panelInstanceId', 'cmd', 'callId'];
    var ITEM_KEYS = ['name', 'displayName', 'icon', 'itemKind', 'value', 'quantity',
        'enhancementLevel', 'majorType', 'use', 'actionType', 'weaponType',
        'setId', 'setName', 'setOrder', 'requiredLevel'];
    var MATERIAL_KEYS = ['name', 'displayName', 'icon', 'itemKind', 'required', 'owned',
        'maxEnhancement', 'isQuantity', 'tier', 'consumed', 'enough', 'storageKind'];
    var STORAGE_KINDS = ['bag', 'drug', 'bag_and_drug', 'material_collection',
        'information_collection', 'unavailable'];

    function finiteNonNegative(value) {
        return typeof value === 'number' && isFinite(value) && value >= 0;
    }

    function validProjectedItem(value) {
        var valid = exactKeys(value, ITEM_KEYS) && identityTriple(value, 'name')
            && (value.itemKind === 'equipment' || value.itemKind === 'stack')
            && finiteNonNegative(value.value) && finiteNonNegative(value.quantity)
            && finiteNonNegative(value.enhancementLevel) && finiteNonNegative(value.requiredLevel)
            && typeof value.majorType === 'string' && typeof value.use === 'string'
            && typeof value.actionType === 'string' && typeof value.weaponType === 'string'
            && typeof value.setId === 'string' && typeof value.setName === 'string'
            && Number.isInteger(value.setOrder) && Number.isInteger(value.value)
            && Number.isInteger(value.quantity) && Number.isInteger(value.enhancementLevel)
            && value.value > 0 && value.quantity > 0;
        if (!valid) return false;
        return value.itemKind === 'equipment'
            ? value.quantity === 1 && value.enhancementLevel === value.value
            : value.enhancementLevel === 0 && value.quantity === value.value;
    }

    function validMaterial(value) {
        return exactKeys(value, MATERIAL_KEYS) && identityTriple(value, 'name')
            && (value.itemKind === 'equipment' || value.itemKind === 'stack')
            && finiteNonNegative(value.required) && finiteNonNegative(value.owned)
            && finiteNonNegative(value.maxEnhancement) && typeof value.isQuantity === 'boolean'
            && typeof value.tier === 'string' && typeof value.consumed === 'boolean'
            && typeof value.enough === 'boolean' && STORAGE_KINDS.indexOf(value.storageKind) >= 0;
    }

    function validCost(value) {
        return exactKeys(value, ['money', 'kpoints'])
            && finiteNonNegative(value.money) && finiteNonNegative(value.kpoints);
    }

    function validOutputDelivery(value, output) {
        if (!exactKeys(value, ['available', 'storageKind', 'mode', 'physicalSlot', 'quantity'])
                || typeof value.available !== 'boolean'
                || STORAGE_KINDS.indexOf(value.storageKind) < 0
                || !Number.isInteger(value.physicalSlot) || !finiteNonNegative(value.quantity)
                || value.quantity !== output.quantity) return false;
        if (!value.available) return value.storageKind === 'unavailable'
            && value.mode === 'none' && value.physicalSlot === -1;
        if (value.storageKind === 'bag') return (value.mode === 'insert'
                || value.mode === 'merge' && output.itemKind === 'stack')
            && value.physicalSlot >= 0 && value.physicalSlot < 50;
        if (value.storageKind === 'drug') return output.itemKind === 'stack'
            && value.mode === 'merge' && value.physicalSlot >= 0;
        return (value.storageKind === 'material_collection'
                || value.storageKind === 'information_collection')
            && output.itemKind === 'stack'
            && value.mode === 'increment' && value.physicalSlot === -1;
    }

    function validAcceptedPlan(plan, response, outputField) {
        return exactKeys(plan, ['category', 'recipeIndex', 'craftCount', 'output', 'materials',
            'outputDelivery', 'outputPrototype', 'cost'])
            && plan.category === response.category
            && plan.recipeIndex === response.recipeIndex
            && plan.craftCount === response.craftCount
            && same(plan.output, response[outputField])
            && Array.isArray(plan.materials) && plan.materials.every(validMaterial)
            && validProjectedItem(plan.output) && validCost(plan.cost)
            && validOutputDelivery(plan.outputDelivery, plan.output)
            && validOutputPrototype(plan.outputPrototype, plan.output, plan.outputDelivery);
    }

    function hasPhysicalReceipt(delivery) {
        return !!delivery && delivery.available === true
            && (delivery.storageKind === 'bag' || delivery.storageKind === 'drug');
    }

    function validOutputPrototype(value, output, delivery) {
        if (!hasPhysicalReceipt(delivery)) {
            return value === null && (delivery.storageKind === 'material_collection'
                || delivery.storageKind === 'information_collection');
        }
        if (!exactKeys(value, ['item', 'confirmProjection'])
                || !InventoryRuntime.isValidItemProjection(value.item)
                || !InventoryRuntime.isValidStableConfirmProjection(
                    value.confirmProjection, value.item)) return false;
        return value.item.name === output.name
            && value.item.displayName === output.displayName
            && value.item.icon === output.icon
            && value.item.itemKind === output.itemKind
            && value.item.quantity === output.quantity
            && value.item.enhancementLevel === output.enhancementLevel
            && value.item.quantity === delivery.quantity;
    }

    function validOutputReceipt(value, acceptedPlan, crafted) {
        var delivery = acceptedPlan && acceptedPlan.outputDelivery;
        if (!hasPhysicalReceipt(delivery)) {
            return value === null && delivery
                && (delivery.storageKind === 'material_collection'
                    || delivery.storageKind === 'information_collection');
        }
        var prototype = acceptedPlan.outputPrototype;
        if (!exactKeys(value, ['item', 'confirmProjection'])
                || !prototype || !prototype.item || !prototype.confirmProjection
                || !InventoryRuntime.isValidItemProjection(value.item)
                || !InventoryRuntime.isValidConfirmProjection(
                    value.confirmProjection, value.item)
                || !Number.isInteger(value.item.quantity)
                || value.item.quantity < 1) return false;
        if (delivery.mode === 'insert') {
            if (value.item.quantity !== crafted.quantity) return false;
        } else if (delivery.mode !== 'merge' || value.item.quantity < crafted.quantity) {
            return false;
        }
        var normalizedItem = JSON.parse(JSON.stringify(value.item));
        normalizedItem.quantity = prototype.item.quantity;
        var normalizedConfirm = JSON.parse(JSON.stringify(value.confirmProjection));
        delete normalizedConfirm.lastUpdate;
        normalizedConfirm.quantity = prototype.confirmProjection.quantity;
        return same(normalizedItem, prototype.item)
            && same(normalizedConfirm, prototype.confirmProjection);
    }

    function validSourceLabels(value) {
        return Array.isArray(value) && value.every(function(source) {
            if (!source || typeof source !== 'object') return false;
            if (source.kind === 'enemy') {
                return strictText(source.displayName)
                    && typeof source.enemyType === 'string';
            }
            if (source.kind === 'quest') {
                return strictText(source.title)
                    && typeof source.questId === 'string';
            }
            return true;
        });
    }

    var V1_CATALOG_KEYS = ['name', 'displayName', 'icon', 'owned', 'sourceCount',
        'useCount', 'hasSourceSummary'];
    var V1_DETAIL_MATERIAL_KEYS = ['name', 'displayName', 'icon', 'description',
        'owned', 'sourceSummary'];
    var V1_USE_KEYS = ['name', 'displayName', 'icon', 'itemKind', 'category', 'required'];
    var SOURCE_KINDS = ['craft', 'shop', 'kshop', 'quest', 'stage', 'enemy'];

    function validV1CatalogMaterial(value) {
        return exactKeys(value, V1_CATALOG_KEYS) && identityText(value.name, 128)
            && identityText(value.displayName, 256) && identityText(value.icon, 256)
            && safeInteger(value.owned) && safeInteger(value.sourceCount)
            && safeInteger(value.useCount) && typeof value.hasSourceSummary === 'boolean';
    }

    function validV1Use(value) {
        return exactKeys(value, V1_USE_KEYS) && identityText(value.name, 128)
            && identityText(value.displayName, 256) && identityText(value.icon, 256)
            && (value.itemKind === 'equipment' || value.itemKind === 'stack')
            && optionalText(value.category, 256) && finiteNonNegativeNumber(value.required);
    }

    function validV1Source(source) {
        if (!source || SOURCE_KINDS.indexOf(source.kind) < 0) return false;
        if (source.kind === 'craft') {
            return exactKeys(source, ['kind', 'category', 'price', 'kpoints'])
                && identityText(source.category, 256)
                && finiteNonNegativeNumber(source.price)
                && finiteNonNegativeNumber(source.kpoints);
        }
        if (source.kind === 'shop') {
            return exactKeys(source, ['kind', 'npc', 'requirement'])
                && identityText(source.npc, 80) && optionalText(source.requirement, 512);
        }
        if (source.kind === 'kshop') {
            return exactKeys(source, ['kind', 'category', 'priceK'])
                && optionalText(source.category, 512)
                && finiteNonNegativeNumber(source.priceK);
        }
        if (source.kind === 'quest') {
            return exactKeys(source, ['kind', 'questId', 'title', 'quantity'])
                && identityText(source.questId, 256) && identityText(source.title, 512)
                && finiteNonNegativeNumber(source.quantity);
        }
        if (source.kind === 'stage') {
            return exactKeys(source, ['kind', 'stageName', 'probability', 'quantityMax'])
                && identityText(source.stageName, 256)
                && finiteNonNegativeNumber(source.probability)
                && finiteNonNegativeNumber(source.quantityMax);
        }
        return exactKeys(source,
            ['kind', 'enemyType', 'displayName', 'probability', 'minLevel', 'maxLevel'])
            && identityText(source.enemyType, 256) && identityText(source.displayName, 256)
            && finiteNonNegativeNumber(source.probability)
            && finiteNonNegativeNumber(source.minLevel)
            && finiteNonNegativeNumber(source.maxLevel);
    }

    function validV1Materials(data) {
        return businessKeys(data, ['success', 'v', 'view', 'materials'])
            && data.v === 1 && data.view === 'materials'
            && Array.isArray(data.materials) && data.materials.length <= MATERIAL_LIMIT
            && data.materials.every(validV1CatalogMaterial)
            && distinct(data.materials, function(item) { return item.name; });
    }

    function validV1MaterialDetail(data, payload) {
        return businessKeys(data, ['success', 'v', 'view', 'material', 'sources', 'uses'])
            && data.v === 1 && data.view === 'materials'
            && exactKeys(data.material, V1_DETAIL_MATERIAL_KEYS)
            && identityText(data.material.name, 128)
            && identityText(data.material.displayName, 256)
            && identityText(data.material.icon, 256)
            && multilineText(data.material.description, 12000)
            && safeInteger(data.material.owned)
            && multilineText(data.material.sourceSummary, 20000)
            && identityText(payload.itemName, 128)
            && data.material.name === payload.itemName
            && Array.isArray(data.sources) && data.sources.length <= SOURCE_LIMIT
            && data.sources.every(validV1Source)
            && Array.isArray(data.uses) && data.uses.length <= USE_LIMIT
            && data.uses.every(validV1Use);
    }

    function validRegistryEntry(value) {
        return exactKeys(value, ['id', 'label', 'order'])
            && identityText(value.id, 256) && identityText(value.label, 512)
            && safeInteger(value.order);
    }

    function validOrderedRegistry(values, limit) {
        return Array.isArray(values) && values.length >= 1 && values.length <= limit
            && values.every(validRegistryEntry) && continuousOrder(values)
            && distinct(values, function(value) { return value.id; });
    }

    function exactRegistry(values, ids) {
        return validOrderedRegistry(values, ids.length)
            && values.length === ids.length
            && values.every(function(value, index) {
                return value.id === ids[index] && value.order === index;
            });
    }

    var AXIS_IDS = {
        grade:['low', 'medium', 'high', 'special'],
        scope:['armor', 'firearm', 'blade', 'fist', 'universal', 'underbarrel'],
        role:['firepower', 'precision', 'stability', 'sustain', 'utility', 'mechanism']
    };
    var ROLE_SYMBOLS = ['triangle-solid', 'triangle-outline', 'square-outline',
        'circle-outline', 'diamond-outline', 'star-solid'];

    function validAxisValue(axisId, value, index) {
        var keys = axisId === 'grade' ? ['id', 'label', 'order', 'color']
            : axisId === 'role' ? ['id', 'label', 'order', 'symbol']
                : ['id', 'label', 'order'];
        if (!exactKeys(value, keys) || value.id !== AXIS_IDS[axisId][index]
                || !identityText(value.label, 512) || value.order !== index) return false;
        if (axisId === 'grade') return /^#[0-9A-Fa-f]{6}$/.test(value.color);
        if (axisId === 'role') return value.symbol === ROLE_SYMBOLS[index];
        return true;
    }

    function validModAxis(axis, index) {
        var id = ['grade', 'scope', 'role'][index];
        return exactKeys(axis, ['id', 'label', 'order', 'values'])
            && axis.id === id && identityText(axis.label, 512) && axis.order === index
            && Array.isArray(axis.values) && axis.values.length === AXIS_IDS[id].length
            && axis.values.every(function(value, valueIndex) {
                return validAxisValue(id, value, valueIndex);
            });
    }

    function validTaxonomy(value) {
        if (!exactKeys(value,
                ['version', 'roots', 'types', 'modAxes', 'recipePurposes',
                    'directPurposes', 'fallback']) || value.version !== 1
                || !exactRegistry(value.roots, ['type', 'purpose'])
                || !exactRegistry(value.types, ['equipment_mod', 'food', 'general'])
                || !Array.isArray(value.modAxes) || value.modAxes.length !== 3
                || !value.modAxes.every(validModAxis)
                || !validOrderedRegistry(value.recipePurposes, TAXONOMY_LIMIT)
                || !validOrderedRegistry(value.directPurposes, TAXONOMY_LIMIT)
                || !exactKeys(value.fallback, ['id', 'label', 'order'])
                || value.fallback.id !== 'unstructured'
                || value.fallback.label !== '尚未结构化用途'
                || value.fallback.order !== 2147483647) return false;
        var entryCount = value.roots.length + value.types.length
            + value.recipePurposes.length + value.directPurposes.length + 1;
        value.modAxes.forEach(function(axis) { entryCount += 1 + axis.values.length; });
        if (entryCount > TAXONOMY_LIMIT) return false;
        return value.recipePurposes.every(function(entry) {
            return entry.id === 'recipe:' + entry.label;
        });
    }

    function registryMap(values) {
        var result = Object.create(null);
        for (var index = 0; index < values.length; index++) result[values[index].id] = values[index];
        return result;
    }

    function orderedReferences(ids, registry) {
        if (!Array.isArray(ids) || !distinct(ids, function(id) { return id; })) return false;
        var previous = -1;
        for (var index = 0; index < ids.length; index++) {
            if (!identityText(ids[index], 256) || !registry[ids[index]]
                    || registry[ids[index]].order <= previous) return false;
            previous = registry[ids[index]].order;
        }
        return true;
    }

    function validModFacets(value, taxonomy) {
        if (!exactKeys(value, ['grade', 'scope', 'role'])) return false;
        for (var index = 0; index < taxonomy.modAxes.length; index++) {
            var axis = taxonomy.modAxes[index], found = false;
            for (var valueIndex = 0; valueIndex < axis.values.length; valueIndex++) {
                if (axis.values[valueIndex].id === value[axis.id]) { found = true; break; }
            }
            if (!found) return false;
        }
        return true;
    }

    function validV2CatalogMaterial(value, taxonomy) {
        var keys = ['name', 'displayName', 'icon', 'owned', 'archiveOrder', 'typeId',
            'recipePurposeIds', 'directPurposeIds', 'structuredPurposeCount',
            'sourceCount', 'dropVariantCount', 'useCount', 'hasSourceSummary'];
        if (value && value.typeId === 'equipment_mod') keys.push('modFacetIds');
        if (!exactKeys(value, keys) || !identityText(value.name, 128)
                || !identityText(value.displayName, 256) || !identityText(value.icon, 256)
                || !safeInteger(value.owned) || !safeInteger(value.archiveOrder)
                || !safeInteger(value.structuredPurposeCount) || !safeInteger(value.sourceCount)
                || !safeInteger(value.dropVariantCount) || !safeInteger(value.useCount)
                || typeof value.hasSourceSummary !== 'boolean') return false;
        var typeRegistry = registryMap(taxonomy.types);
        if (!typeRegistry[value.typeId]) return false;
        if (value.typeId === 'equipment_mod') {
            if (!validModFacets(value.modFacetIds, taxonomy)) return false;
        } else if (own(value, 'modFacetIds')) return false;
        var recipeRegistry = registryMap(taxonomy.recipePurposes);
        var directRegistry = registryMap(taxonomy.directPurposes);
        return orderedReferences(value.recipePurposeIds, recipeRegistry)
            && Array.isArray(value.directPurposeIds)
            && value.directPurposeIds.length <= DIRECT_PURPOSE_LIMIT
            && orderedReferences(value.directPurposeIds, directRegistry)
            && value.structuredPurposeCount === value.useCount + value.directPurposeIds.length;
    }

    function validV2Materials(data) {
        if (!businessKeys(data, ['success', 'v', 'view', 'snapshotId',
                'navigationAccess', 'taxonomy', 'materials'])
                || data.v !== 2 || data.view !== 'materials'
                || !identityText(data.snapshotId, 256)
                || !exactKeys(data.navigationAccess, ['shop', 'crafting'])
                || typeof data.navigationAccess.shop !== 'boolean'
                || typeof data.navigationAccess.crafting !== 'boolean'
                || !validTaxonomy(data.taxonomy)
                || !Array.isArray(data.materials) || data.materials.length > MATERIAL_LIMIT
                || !data.materials.every(function(item) {
                    return validV2CatalogMaterial(item, data.taxonomy);
                }) || !distinct(data.materials, function(item) { return item.name; })) return false;
        return data.materials.every(function(item, index) { return item.archiveOrder === index; });
    }

    function nullableSafeInteger(value) {
        return value === null || safeInteger(value);
    }

    function validQuantityBounds(value) {
        return positiveInteger(value.quantityMin) && positiveInteger(value.quantityMax)
            && value.quantityMin <= value.quantityMax;
    }

    function validEnemyVariant(value, index) {
        if (!exactKeys(value, ['occurrenceIndex', 'chanceRaw', 'chanceInputState',
                'nominalChancePercent', 'minReverseLevel', 'maxReverseLevel',
                'quantityMin', 'quantityMax']) || value.occurrenceIndex !== index
                || ['explicit', 'absent_defaulted', 'invalid_defaulted']
                    .indexOf(value.chanceInputState) < 0
                || !finiteNonNegativeNumber(value.nominalChancePercent)
                || value.nominalChancePercent > 100
                || !nullableSafeInteger(value.minReverseLevel)
                || !nullableSafeInteger(value.maxReverseLevel)
                || value.minReverseLevel !== null && value.maxReverseLevel !== null
                    && value.minReverseLevel > value.maxReverseLevel
                || !validQuantityBounds(value)) return false;
        if (value.chanceInputState === 'explicit') {
            return finiteNonNegativeNumber(value.chanceRaw) && value.chanceRaw <= 100
                && value.nominalChancePercent === value.chanceRaw;
        }
        return value.chanceRaw === null && value.nominalChancePercent === 100;
    }

    function validStageVariant(value, index) {
        if (!exactKeys(value, ['occurrenceIndex', 'rollDivisor',
                'defaultBranchChancePercent', 'quantityMin', 'quantityMax'])
                || value.occurrenceIndex !== index || !positiveInteger(value.rollDivisor)
                || !finiteNonNegativeNumber(value.defaultBranchChancePercent)
                || value.defaultBranchChancePercent > 100 || !validQuantityBounds(value)) return false;
        var expected = Math.round(100 / value.rollDivisor * 1000000) / 1000000;
        return Math.abs(value.defaultBranchChancePercent - expected) <= 0.0000005;
    }

    function validVariants(values, validator) {
        return Array.isArray(values) && values.length >= 1 && values.length <= VARIANT_LIMIT
            && values.every(validator);
    }

    function validV2Source(source, index, requestedItemName) {
        if (!source || SOURCE_KINDS.indexOf(source.kind) < 0
                || !identityText(source.sourceKey, 768) || source.sourceOrder !== index) return false;
        if (source.kind === 'craft') {
            return exactKeys(source, ['kind', 'sourceKey', 'sourceOrder', 'category',
                'recipeIndex', 'productName', 'price', 'kpoints'])
                && identityText(source.category, 256) && recipeIndex(source.recipeIndex)
                && identityText(source.productName, 128)
                && source.productName === requestedItemName
                && finiteNonNegativeNumber(source.price)
                && finiteNonNegativeNumber(source.kpoints);
        }
        if (source.kind === 'shop') {
            return exactKeys(source, ['kind', 'sourceKey', 'sourceOrder', 'shopId',
                'catalogIndex', 'itemName', 'basePrice', 'unitPriceAtSnapshot',
                'requiredInfo', 'locked', 'shopAccessMode', 'shopAccessReason'])
                && identityText(source.shopId, 80) && shopCatalogIndex(source.catalogIndex)
                && identityText(source.itemName, 128) && source.itemName === requestedItemName
                && finiteNonNegativeNumber(source.basePrice)
                && finiteNonNegativeNumber(source.unitPriceAtSnapshot)
                && optionalText(source.requiredInfo, 512) && typeof source.locked === 'boolean'
                && (source.shopAccessMode === 'full'
                        && source.shopAccessReason === 'indexed_live_match'
                    || source.shopAccessMode === 'unavailable'
                        && source.shopAccessReason === 'no_authoritative_remote_access_capability');
        }
        if (source.kind === 'kshop') {
            return exactKeys(source, ['kind', 'sourceKey', 'sourceOrder', 'catalogIndex',
                'entryId', 'category', 'priceK']) && safeInteger(source.catalogIndex)
                && identityText(source.entryId, 256) && optionalText(source.category, 512)
                && finiteNonNegativeNumber(source.priceK);
        }
        if (source.kind === 'quest') {
            return exactKeys(source, ['kind', 'sourceKey', 'sourceOrder', 'questId',
                'rewardSet', 'authoredIndex', 'title', 'quantity'])
                && identityText(source.questId, 256)
                && (source.rewardSet === 'base' || source.rewardSet === 'challenge')
                && safeInteger(source.authoredIndex) && identityText(source.title, 512)
                && positiveInteger(source.quantity);
        }
        if (source.kind === 'stage') {
            return exactKeys(source, ['kind', 'sourceKey', 'sourceOrder', 'stageName',
                'chanceModel', 'legacyConditionId', 'variants'])
                && identityText(source.stageName, 256)
                && source.chanceModel === 'stage_roll_divisor_with_legacy_domain_branch'
                && source.legacyConditionId === 'andylaw_domain_bonus'
                && validVariants(source.variants, validStageVariant);
        }
        return exactKeys(source, ['kind', 'sourceKey', 'sourceOrder', 'enemyType',
            'displayName', 'chanceModel', 'variants'])
            && identityText(source.enemyType, 256) && source.enemyType.indexOf('敌人-') === 0
            && identityText(source.displayName, 512)
            && source.chanceModel === 'enemy_prd_with_reverse_bonus'
            && validVariants(source.variants, validEnemyVariant);
    }

    function validDirectPurpose(value) {
        return validRegistryEntry(value);
    }

    function validV2Ingredients(value, materialName, expectedRequired) {
        if (!Array.isArray(value) || value.length < 1 || value.length > INGREDIENT_LIMIT) return false;
        var selectedRequired = 0;
        for (var index = 0; index < value.length; index++) {
            var ingredient = value[index];
            if (!exactKeys(ingredient, ['name', 'displayName', 'icon', 'required', 'isQuantity'])
                    || !identityText(ingredient.name, 128)
                    || !identityText(ingredient.displayName, 256)
                    || !identityText(ingredient.icon, 256)
                    || !positiveInteger(ingredient.required)
                    || typeof ingredient.isQuantity !== 'boolean') return false;
            if (ingredient.name === materialName) selectedRequired += ingredient.required;
            if (!safeInteger(selectedRequired)) return false;
        }
        return selectedRequired === expectedRequired;
    }

    function validV2Use(value, materialName) {
        var hasIngredients = !!value && Object.prototype.hasOwnProperty.call(value, 'ingredients');
        var keys = ['category', 'recipeIndex', 'productName', 'displayName',
            'icon', 'itemKind', 'required'];
        if (hasIngredients) keys.push('ingredients');
        return exactKeys(value, keys) && identityText(value.category, 256)
            && recipeIndex(value.recipeIndex) && identityText(value.productName, 128)
            && identityText(value.displayName, 256) && identityText(value.icon, 256)
            && (value.itemKind === 'equipment' || value.itemKind === 'stack')
            && positiveInteger(value.required)
            && (!hasIngredients || validV2Ingredients(
                value.ingredients, materialName, value.required));
    }

    function hasInfrastructurePurpose(values) {
        return Array.isArray(values) && values.some(function(value) {
            return value && value.id === INFRASTRUCTURE_PURPOSE_ID;
        });
    }

    function validInfrastructureUses(projects, catalogOwned) {
        if (!Array.isArray(projects) || projects.length > INFRASTRUCTURE_PROJECT_LIMIT) {
            return false;
        }
        var names = Object.create(null), previousProjectOrder = -1;
        for (var projectIndex = 0; projectIndex < projects.length; projectIndex++) {
            var project = projects[projectIndex];
            if (!exactKeys(project, ['infrastructureName', 'projectOrder', 'currentLevel',
                    'maximumLevel', 'levels'])
                    || !identityText(project.infrastructureName, 128)
                    || names[project.infrastructureName]
                    || !Number.isInteger(project.projectOrder) || project.projectOrder < 0
                    || project.projectOrder >= INFRASTRUCTURE_PROJECT_LIMIT
                    || project.projectOrder <= previousProjectOrder
                    || !Number.isInteger(project.maximumLevel) || project.maximumLevel < 1
                    || project.maximumLevel > INFRASTRUCTURE_LEVEL_LIMIT
                    || !Number.isInteger(project.currentLevel) || project.currentLevel < 0
                    || project.currentLevel > project.maximumLevel
                    || !Array.isArray(project.levels) || project.levels.length < 1
                    || project.levels.length > INFRASTRUCTURE_LEVEL_LIMIT) return false;
            names[project.infrastructureName] = true;
            previousProjectOrder = project.projectOrder;
            var previousLevelIndex = -1;
            for (var levelOffset = 0; levelOffset < project.levels.length; levelOffset++) {
                var level = project.levels[levelOffset];
                if (!exactKeys(level, ['levelIndex', 'targetLevel', 'required', 'owned',
                        'missing', 'status'])
                        || !Number.isInteger(level.levelIndex) || level.levelIndex < 0
                        || level.levelIndex >= project.maximumLevel
                        || level.levelIndex <= previousLevelIndex
                        || !Number.isInteger(level.targetLevel)
                        || level.targetLevel !== level.levelIndex + 1
                        || level.targetLevel > project.maximumLevel
                        || !positiveInteger(level.required)
                        || !safeInteger(level.owned) || level.owned !== catalogOwned
                        || !safeInteger(level.missing)) return false;
                var expectedStatus = project.currentLevel > level.levelIndex
                    ? 'completed' : project.currentLevel === level.levelIndex
                        ? 'current' : 'future';
                var expectedMissing = expectedStatus === 'completed'
                    ? 0 : Math.max(level.required - level.owned, 0);
                if (level.status !== expectedStatus || level.missing !== expectedMissing) {
                    return false;
                }
                previousLevelIndex = level.levelIndex;
            }
        }
        return true;
    }

    function validV2MaterialDetail(data, payload) {
        var infrastructureExpected = hasInfrastructurePurpose(data && data.directPurposes);
        var detailKeys = ['success', 'v', 'view', 'snapshotId', 'material',
                'sourceCount', 'dropVariantCount', 'useCount', 'structuredPurposeCount',
                'sources', 'directPurposes', 'uses'];
        if (infrastructureExpected) detailKeys.push('infrastructureUses');
        if (!businessKeys(data, detailKeys) || data.v !== 2
                || data.view !== 'materials' || !identityText(data.snapshotId, 256)
                || data.snapshotId !== payload.snapshotId || !identityText(payload.itemName, 128)
                || !exactKeys(data.material, V1_DETAIL_MATERIAL_KEYS)
                || data.material.name !== payload.itemName
                || !identityText(data.material.name, 128)
                || !identityText(data.material.displayName, 256)
                || !identityText(data.material.icon, 256)
                || !multilineText(data.material.description, 12000)
                || !safeInteger(data.material.owned)
                || !multilineText(data.material.sourceSummary, 20000)
                || !safeInteger(data.sourceCount) || !safeInteger(data.dropVariantCount)
                || !safeInteger(data.useCount) || !safeInteger(data.structuredPurposeCount)
                || !Array.isArray(data.sources) || data.sources.length > SOURCE_LIMIT
                || !data.sources.every(function(source, index) {
                    return validV2Source(source, index, payload.itemName);
                })
                || !distinct(data.sources, function(source) { return source.sourceKey; })
                || !Array.isArray(data.directPurposes)
                || data.directPurposes.length > DIRECT_PURPOSE_LIMIT
                || !data.directPurposes.every(validDirectPurpose)
                || !distinct(data.directPurposes, function(purpose) { return purpose.id; })
                || !Array.isArray(data.uses) || data.uses.length > USE_LIMIT
                || !data.uses.every(function(use) {
                    return validV2Use(use, payload.itemName);
                })
                || !distinct(data.uses, function(use) {
                    return use.category + '\u0000' + use.recipeIndex;
                })
                || infrastructureExpected
                    && !validInfrastructureUses(
                        data.infrastructureUses, data.material.owned)) return false;
        var variantCount = 0;
        for (var index = 0; index < data.sources.length; index++) {
            if (data.sources[index].kind === 'stage' || data.sources[index].kind === 'enemy') {
                variantCount += data.sources[index].variants.length;
            }
        }
        return data.sourceCount === data.sources.length
            && data.dropVariantCount === variantCount && data.useCount === data.uses.length
            && data.structuredPurposeCount === data.useCount + data.directPurposes.length;
    }

    // Crafting owns several distinct response shapes. Keep their identity-leaf
    // validation here instead of teaching a shared primitive to guess aliases.
    function validateBusinessResponse(data, entry) {
        var cmd = entry && entry.cmd;
        var payload = entry && entry.metadata && entry.metadata.payload || {};
        if (!data || data.success !== true) {
            if (!data || data.success !== false) return false;
            if (cmd === 'materials' || cmd === 'materialDetail') {
                if (!businessKeys(data, ['success', 'error'])
                        || !identityText(data.error, 128)) return false;
                if (data.error === 'stale_snapshot') {
                    return cmd === 'materialDetail' && payload.v === 2;
                }
                return true;
            }
            return true;
        }
        if (cmd === 'snapshot') {
            return Array.isArray(data.recipes) && data.recipes.every(function(recipe) {
                return !!recipe && identityTriple(recipe.output, 'name');
            });
        }
        if (cmd === 'materials') {
            if (payload.v !== 1 && payload.v !== 2) return false;
            if (data.v === 1) return validV1Materials(data);
            return payload.v === 2 && data.v === 2 && validV2Materials(data);
        }
        if (cmd === 'materialDetail') {
            if (payload.v === 1) return validV1MaterialDetail(data, payload);
            return payload.v === 2 && validV2MaterialDetail(data, payload);
        }
        if (cmd === 'preview') {
            var previewKeys = RESPONSE_ENVELOPE.concat(['success', 'v', 'category', 'recipeIndex',
                'craftCount', 'batchEligible', 'maxCraftCount', 'output', 'materials', 'cost',
                'balance', 'skills', 'levelAllowed', 'enoughMaterials', 'enoughMoney',
                'enoughKpoints', 'enoughSpace', 'canCommit', 'blockingError', 'outputDelivery']);
            if (data.canCommit === true) previewKeys.push('craftToken', 'acceptedPlan');
            return exactKeys(data, previewKeys)
                && validProjectedItem(data.output) && Array.isArray(data.materials)
                && data.materials.every(validMaterial)
                && validOutputDelivery(data.outputDelivery, data.output)
                && data.outputDelivery.available === data.enoughSpace
                && (data.canCommit !== true || data.materials.every(function(material) {
                    return material.storageKind !== 'unavailable';
                }))
                && (data.canCommit !== true || strictText(data.craftToken)
                    && validAcceptedPlan(data.acceptedPlan, data, 'output')
                    && same(data.acceptedPlan.materials, data.materials)
                    && same(data.acceptedPlan.outputDelivery, data.outputDelivery)
                    && same(data.acceptedPlan.cost, data.cost));
        }
        if (cmd === 'commit') {
            return exactKeys(data, RESPONSE_ENVELOPE.concat(['success', 'v', 'operation',
                'category', 'recipeIndex', 'craftCount', 'crafted', 'acceptedPlan',
                'outputReceipt', 'balance']))
                && data.operation === 'commit' && validProjectedItem(data.crafted)
                && validAcceptedPlan(data.acceptedPlan, data, 'crafted')
                && validOutputReceipt(data.outputReceipt, data.acceptedPlan, data.crafted);
        }
        if (cmd === 'tooltip') {
            // Host has already translated the one allowed legacy displayname
            // profile. Web accepts only the canonical post-Host spelling.
            return strictText(data.itemName) && strictText(data.displayName)
                && strictText(payload.itemName) && data.itemName === payload.itemName;
        }
        return false;
    }

    function RequestMux(options) {
        options = options || {};
        this._mux = new PanelRuntime.PanelRequestMux({
            send:options.send,
            timeoutMs:options.timeoutMs,
            sessionNonce:options.sessionNonce,
            setTimer:options.setTimer,
            clearTimer:options.clearTimer,
            callPrefix:'craft',
            router:options.router || PanelRuntime.sharedResponseRouter,
            validateSession:function(session) {
                return !!session && session.ownerPanel === 'crafting'
                    && /^[A-Za-z0-9._~-]{1,128}$/.test(String(session.panelInstanceId || ''));
            },
            createMessage:function(context) {
                return {type:'panel', domain:'crafting', panel:'crafting', cmd:context.entry.cmd,
                    panelInstanceId:context.session.panelInstanceId,
                    callId:context.entry.callId, payload:context.payload || {}};
            },
            validateResponse:function(data, entry) {
                return data && data.type === 'panel_resp' && data.domain === 'crafting'
                    && data.panel === 'crafting'
                    && data.panelInstanceId === entry.session.panelInstanceId
                    && data.callId === entry.callId && data.cmd === entry.cmd
                    && validateBusinessResponse(data, entry);
            },
            createSynthetic:function(context) {
                return {type:'panel_resp', domain:'crafting', panel:'crafting',
                    panelInstanceId:context.session.panelInstanceId, cmd:context.entry.cmd,
                    callId:context.entry.callId, success:false, error:context.error,
                    clientSynthetic:true};
            }
        });
    }

    RequestMux.prototype.openSession = function(session) { return this._mux.openSession(session || {}); };
    RequestMux.prototype.closeSession = function() { this._mux.closeSession(); };
    RequestMux.prototype.request = function(cmd, payload, callback) {
        var frozenPayload;
        try { frozenPayload = JSON.parse(JSON.stringify(payload || {})); }
        catch (_) { return null; }
        return this._mux.request(cmd, payload, {sendError:'disconnected',
            metadata:{payload:frozenPayload}}, callback);
    };
    RequestMux.prototype.handleResponse = function(data) { return this._mux.handleResponse(data); };
    RequestMux.prototype.cancel = function(callId) { return this._mux.cancel(callId); };
    RequestMux.prototype.destroy = function() { this._mux.destroy(); };
    RequestMux.prototype.debugState = function() {
        var state = this._mux.debugState();
        return {generation:state.generation, sequence:state.sequence, active:state.active,
            pendingCount:state.pendingCount};
    };

    function createMaterialShopNavigationMessage(input) {
        input = input || {};
        if (!NAVIGATION_CALL_ID_PATTERN.test(String(input.callId || ''))
                || !PANEL_INSTANCE_PATTERN.test(String(input.panelInstanceId || ''))
                || !identityText(input.materialSnapshotId, 256)
                || !identityText(input.materialName, 128)
                || !identityText(input.shopId, 80)
                || !shopCatalogIndex(input.catalogIndex)) return null;
        return {
            type:'panel',
            panel:'crafting',
            cmd:'open_npc_shop',
            callId:String(input.callId),
            panelInstanceId:String(input.panelInstanceId),
            source:'crafting_materials',
            materialSnapshotId:String(input.materialSnapshotId),
            materialName:String(input.materialName),
            shopId:String(input.shopId),
            catalogIndex:Number(input.catalogIndex)
        };
    }

    function validateMaterialShopNavigationFailure(data, expected) {
        expected = expected || {};
        return exactKeys(data, ['type', 'panel', 'cmd', 'callId',
                'panelInstanceId', 'success', 'error'])
            && data.type === 'panel_resp'
            && data.panel === 'crafting'
            && data.cmd === 'open_npc_shop'
            && data.success === false
            && NAVIGATION_CALL_ID_PATTERN.test(String(data.callId || ''))
            && PANEL_INSTANCE_PATTERN.test(String(data.panelInstanceId || ''))
            && !!MATERIAL_SHOP_FAILURE_ERRORS[String(data.error || '')]
            && (!expected.callId || data.callId === expected.callId)
            && (!expected.panelInstanceId
                || data.panelInstanceId === expected.panelInstanceId);
    }

    return {RequestMux:RequestMux, validateBusinessResponse:validateBusinessResponse,
        identityTriple:identityTriple,
        SHOP_CATALOG_INDEX_MAX:SHOP_CATALOG_INDEX_MAX,
        NAVIGATION_WATCHDOG_MS:NAVIGATION_WATCHDOG_MS,
        isShopCatalogIndex:shopCatalogIndex,
        isNavigationCallId:function(value) {
            return typeof value === 'string' && NAVIGATION_CALL_ID_PATTERN.test(value);
        },
        createMaterialShopNavigationMessage:createMaterialShopNavigationMessage,
        validateMaterialShopNavigationFailure:validateMaterialShopNavigationFailure};
});
