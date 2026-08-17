import org.flashNight.arki.item.EquipmentUtil;
import org.flashNight.arki.item.ItemUtil;
import org.flashNight.arki.item.obtain.ItemObtainIndex;
import org.flashNight.arki.item.synthesis.SynthesisIndex;
import org.flashNight.gesh.object.ObjectUtil;

/**
 * 材料档案 v2 权威投影器。
 *
 * A2 只允许材料目录与详情 opt-in v2。目录调用冻结一个 AS2-owned
 * snapshot；详情必须回显同一 snapshotId。除商店价格/锁定态在详情时复用
 * NPCShop catalog projector 现场 join 外，目录与详情均只读同一 frozen state。
 */
class org.flashNight.arki.item.MaterialArchiveProjector {
    private static var _snapshot:Object = null;
    private static var _snapshotSeq:Number = 0;
    private static var _buildError:String = "";
    private static var _categoryRank:Object = {};

    private static var MAX_MATERIALS:Number = 4096;
    private static var MAX_SOURCES:Number = 512;
    private static var MAX_VARIANTS:Number = 128;
    private static var MAX_USES:Number = 1024;
    private static var MAX_RECIPE_INGREDIENTS:Number = 64;
    private static var MAX_DIRECT_PURPOSES:Number = 128;
    private static var MAX_TAXONOMY_ENTRIES:Number = 1024;
    private static var MAX_INFRASTRUCTURE_PROJECTS:Number = 256;
    private static var MAX_INFRASTRUCTURE_LEVELS:Number = 128;
    private static var MAX_SAFE_INTEGER:Number = 9007199254740991;
    private static var MAX_SHOP_CATALOG_INDEX:Number = 10000;
    private static var INFRASTRUCTURE_PURPOSE_ID:String =
        "system:infrastructure_upgrade";

    public static function executeMaterials():Object {
        // 任一次 catalog refresh 都先淘汰旧 snapshot；失败不能继续服务旧详情。
        _snapshot = null;
        _buildError = "";
        var built:Object = buildSnapshot(_root.材料档案目录, categoryOrder());
        if (built == null) return fail(_buildError == "" ? "invalid_catalog" : _buildError);
        _snapshot = built;
        return {
            success:true,
            v:2,
            view:"materials",
            snapshotId:String(built.snapshotId),
            navigationAccess:currentNavigationAccess(),
            taxonomy:cloneValue(built.taxonomy, 0),
            materials:cloneValue(built.materials, 0)
        };
    }

    public static function executeMaterialDetail(params:Object):Object {
        if (_snapshot == null) return fail("stale_snapshot");
        var snapshotId:String = params == null ? "" : String(params.snapshotId || "");
        var itemName:String = params == null ? "" : String(params.itemName || "");
        if (snapshotId == "" || snapshotId != String(_snapshot.snapshotId)) {
            return fail("stale_snapshot");
        }
        var frozen:Object = _snapshot.byName[itemName];
        if (frozen == null) return fail("item_not_found");
        var sources:Array = buildDetailSources(frozen.sources);
        if (sources == null) return fail(_buildError == "" ? "source_snapshot_failed" : _buildError);
        var response:Object = {
            success:true,
            v:2,
            view:"materials",
            snapshotId:snapshotId,
            material:cloneValue(frozen.material, 0),
            sourceCount:Number(frozen.catalog.sourceCount),
            dropVariantCount:Number(frozen.catalog.dropVariantCount),
            useCount:Number(frozen.catalog.useCount),
            structuredPurposeCount:Number(frozen.catalog.structuredPurposeCount),
            sources:sources,
            directPurposes:cloneValue(frozen.directPurposes, 0),
            uses:cloneValue(frozen.uses, 0)
        };
        if (frozen.infrastructureUses instanceof Array) {
            var infrastructureUses:Array = buildLiveInfrastructureUses(
                frozen.infrastructureUses, Number(frozen.material.owned));
            if (infrastructureUses == null) {
                return fail(_buildError == "" ? "invalid_infrastructure_state" : _buildError);
            }
            response.infrastructureUses = infrastructureUses;
        }
        return response;
    }

    /**
     * A4b 方案 2：点击时重新证明 frozen material source、current obtain
     * occurrence 与 live NPC catalog 是同一个 exact slot。调用方负责在最窄
     * dedicated handler 捕获 projector/catalog 异常；本方法不接入 Crafting busy。
     */
    public static function authorizeShopAccess(params:Object):Object {
        var callId:Number = params != null && typeof params.callId == "number"
            ? Number(params.callId) : 0;
        if (!validShopAccessRequest(params)) {
            return shopAccessFailure(callId, "deny", "invalid_payload");
        }

        var snapshotId:String = String(params.materialSnapshotId);
        var materialName:String = String(params.materialName);
        var shopId:String = String(params.shopId);
        var catalogIndex:Number = Number(params.catalogIndex);
        if (_snapshot == null || snapshotId != String(_snapshot.snapshotId)) {
            return shopAccessFailure(callId, "stale", "stale_snapshot");
        }
        if (!currentNavigationAccess().shop) {
            return shopAccessFailure(callId, "deny", "access_denied");
        }

        var frozen:Object = _snapshot.byName[materialName];
        if (frozen == null || countFrozenShopSources(
                frozen.sources, materialName, shopId, catalogIndex) != 1) {
            return shopAccessFailure(callId, "stale", "source_not_current");
        }

        var index:ItemObtainIndex = ItemObtainIndex.getInstance();
        if (index == null || index.isIndexBuilt() !== true) {
            return shopAccessFailure(callId, "deny", "authority_unavailable");
        }
        var currentRecords = index.getExactObtainRecords(materialName);
        if (!(currentRecords instanceof Array)) {
            return shopAccessFailure(callId, "deny", "authority_unavailable");
        }
        if (countCurrentShopSources(
                currentRecords, materialName, shopId, catalogIndex) != 1) {
            return shopAccessFailure(callId, "stale", "source_not_current");
        }

        if (_root.UI系统 == undefined
                || _root.UI系统.NPC商店WebView == undefined
                || typeof _root.UI系统.NPC商店WebView.buildCatalog != "function"
                || _root.shops == undefined || _root.shops == null) {
            return shopAccessFailure(callId, "deny", "authority_unavailable");
        }
        var rawShop:Object = _root.shops[shopId];
        if (rawShop == undefined || rawShop == null) {
            return shopAccessFailure(callId, "stale", "catalog_not_current");
        }
        if (rawShopItemName(rawShop, catalogIndex) != materialName) {
            return shopAccessFailure(callId, "stale", "catalog_not_current");
        }

        var catalog = _root.UI系统.NPC商店WebView.buildCatalog(shopId);
        if (!(catalog instanceof Array)) {
            return shopAccessFailure(callId, "deny", "authority_unavailable");
        }
        var live:Object = exactLiveCatalogEntry(catalog, catalogIndex);
        if (live == null || String(live.itemName) != materialName) {
            return shopAccessFailure(callId, "stale", "catalog_not_current");
        }
        return {
            task:"material_shop_access_response",
            callId:callId,
            success:true,
            v:1,
            decision:"allow",
            reason:"indexed_live_match",
            materialSnapshotId:snapshotId,
            materialName:materialName,
            shopId:shopId,
            catalogIndex:catalogIndex,
            itemName:materialName
        };
    }

    /** KShop 等价点击时门：frozen source、current index 与 live slot 必须完全一致。 */
    public static function authorizeKShopAccess(params:Object):Object {
        var callId:Number = params != null && typeof params.callId == "number"
            ? Number(params.callId) : 0;
        if (!validKShopAccessRequest(params)) {
            return shopAccessFailure(callId, "deny", "invalid_payload");
        }
        var snapshotId:String = String(params.materialSnapshotId);
        var materialName:String = String(params.materialName);
        var catalogIndex:Number = Number(params.catalogIndex);
        var entryId:String = String(params.entryId);
        var category:String = String(params.category);
        if (_snapshot == null || snapshotId != String(_snapshot.snapshotId)) {
            return shopAccessFailure(callId, "stale", "stale_snapshot");
        }
        if (!currentNavigationAccess().shop) {
            return shopAccessFailure(callId, "deny", "access_denied");
        }
        var frozen:Object = _snapshot.byName[materialName];
        if (frozen == null || countFrozenKShopSources(
                frozen.sources, catalogIndex, entryId, category) != 1) {
            return shopAccessFailure(callId, "stale", "source_not_current");
        }
        var index:ItemObtainIndex = ItemObtainIndex.getInstance();
        if (index == null || index.isIndexBuilt() !== true) {
            return shopAccessFailure(callId, "deny", "authority_unavailable");
        }
        var currentRecords = index.getExactObtainRecords(materialName);
        if (!(currentRecords instanceof Array)) {
            return shopAccessFailure(callId, "deny", "authority_unavailable");
        }
        if (countCurrentKShopSources(currentRecords, catalogIndex, entryId, category) != 1) {
            return shopAccessFailure(callId, "stale", "source_not_current");
        }
        var catalog:Array = _root.kshop_list instanceof Array ? _root.kshop_list : null;
        var live:Object = catalog == null ? null : catalog[catalogIndex];
        if (live == null || String(live.item || "") != materialName
                || String(live.id || "") != entryId
                || String(live.type || "") != category) {
            return shopAccessFailure(callId, "stale", "catalog_not_current");
        }
        return {task:"material_shop_access_response", callId:callId,
            success:true, v:1, decision:"allow", reason:"kshop_indexed_live_match",
            materialSnapshotId:snapshotId, materialName:materialName,
            catalogIndex:catalogIndex, entryId:entryId, category:category,
            itemName:materialName};
    }

    /**
     * 配方采购不要求物品属于材料档案；它只复证当前 obtain index、原始目录、
     * live NPC catalog 与摩托车/越野车能力。稳定配方身份由调用层另行复证。
     */
    public static function authorizeRecipeShopAccess(callId:Number,
            itemName:String, shopId:String, catalogIndex:Number):Object {
        if (!validIntegerRange(callId, 1, 2147483647)
                || !validIdentity(itemName, 128)
                || !validIdentity(shopId, 80)
                || !validShopCatalogIndex(catalogIndex)) {
            return shopAccessFailure(callId, "deny", "invalid_payload");
        }
        if (!currentNavigationAccess().crafting) {
            return shopAccessFailure(callId, "deny", "access_denied");
        }
        var index:ItemObtainIndex = ItemObtainIndex.getInstance();
        if (index == null || index.isIndexBuilt() !== true) {
            return shopAccessFailure(callId, "deny", "authority_unavailable");
        }
        var records = index.getExactObtainRecords(itemName);
        if (!(records instanceof Array)) {
            return shopAccessFailure(callId, "deny", "authority_unavailable");
        }
        if (countCurrentShopSources(records, itemName, shopId, catalogIndex) != 1) {
            return shopAccessFailure(callId, "stale", "source_not_current");
        }
        if (_root.UI系统 == undefined
                || _root.UI系统.NPC商店WebView == undefined
                || typeof _root.UI系统.NPC商店WebView.buildCatalog != "function"
                || _root.shops == undefined || _root.shops == null) {
            return shopAccessFailure(callId, "deny", "authority_unavailable");
        }
        var rawShop:Object = _root.shops[shopId];
        if (rawShop == undefined || rawShop == null
                || rawShopItemName(rawShop, catalogIndex) != itemName) {
            return shopAccessFailure(callId, "stale", "catalog_not_current");
        }
        var catalog = _root.UI系统.NPC商店WebView.buildCatalog(shopId);
        if (!(catalog instanceof Array)) {
            return shopAccessFailure(callId, "deny", "authority_unavailable");
        }
        var live:Object = exactLiveCatalogEntry(catalog, catalogIndex);
        if (live == null || String(live.itemName) != itemName) {
            return shopAccessFailure(callId, "stale", "catalog_not_current");
        }
        return {task:"material_shop_access_response", callId:callId,
            success:true, v:1, decision:"allow", reason:"indexed_live_match",
            materialName:itemName, shopId:shopId, catalogIndex:catalogIndex,
            itemName:itemName};
    }

    /** KShop 的配方采购等价门；同样不依赖材料档案 snapshot。 */
    public static function authorizeRecipeKShopAccess(callId:Number,
            itemName:String, catalogIndex:Number, entryId:String,
            category:String):Object {
        if (!validIntegerRange(callId, 1, 2147483647)
                || !validIdentity(itemName, 128)
                || !validShopCatalogIndex(catalogIndex)
                || !validIdentity(entryId, 256)
                || !validIdentity(category, 512)) {
            return shopAccessFailure(callId, "deny", "invalid_payload");
        }
        if (!currentNavigationAccess().crafting) {
            return shopAccessFailure(callId, "deny", "access_denied");
        }
        var index:ItemObtainIndex = ItemObtainIndex.getInstance();
        if (index == null || index.isIndexBuilt() !== true) {
            return shopAccessFailure(callId, "deny", "authority_unavailable");
        }
        var records = index.getExactObtainRecords(itemName);
        if (!(records instanceof Array)) {
            return shopAccessFailure(callId, "deny", "authority_unavailable");
        }
        if (countCurrentKShopSources(records, catalogIndex, entryId, category) != 1) {
            return shopAccessFailure(callId, "stale", "source_not_current");
        }
        var catalog:Array = _root.kshop_list instanceof Array ? _root.kshop_list : null;
        var live:Object = catalog == null ? null : catalog[catalogIndex];
        if (live == null || String(live.item || "") != itemName
                || String(live.id || "") != entryId
                || String(live.type || "") != category) {
            return shopAccessFailure(callId, "stale", "catalog_not_current");
        }
        return {task:"material_shop_access_response", callId:callId,
            success:true, v:1, decision:"allow", reason:"kshop_indexed_live_match",
            materialName:itemName, catalogIndex:catalogIndex, entryId:entryId,
            category:category, itemName:itemName};
    }

    /**
     * 材料档案“前往合成”的点击时权威门。普通世界合成 snapshot
     * 不携 materialSnapshotId，因此不受这个远程导航门影响。
     */
    public static function authorizeCraftingAccess(materialSnapshotId):String {
        if (typeof materialSnapshotId != "string"
                || !validIdentity(String(materialSnapshotId), 256)) {
            return "invalid_payload";
        }
        if (_snapshot == null
                || String(materialSnapshotId) != String(_snapshot.snapshotId)) {
            return "stale_snapshot";
        }
        return currentNavigationAccess().crafting ? "" : "access_denied";
    }

    /** Tests and hot-reload teardown: retire every outstanding v2 snapshot. */
    public static function reset():Void {
        _snapshot = null;
        _buildError = "";
        _categoryRank = {};
    }

    /**
     * Test-only, read-only boundary probe. It never builds/retains a snapshot,
     * never projects wire data and rejects every unknown alias.
     */
    public static function testOnlyValidateBoundary(alias:String, value):Boolean {
        if (typeof alias != "string") return false;
        if (alias == "Name") {
            return typeof value == "string" && validIdentity(String(value), 128);
        }
        if (alias == "ShopId") {
            return typeof value == "string" && validIdentity(String(value), 80);
        }
        if (alias == "Id" || alias == "Display") {
            return typeof value == "string" && validIdentity(String(value), 256);
        }
        if (alias == "Label") {
            return typeof value == "string" && validIdentity(String(value), 512);
        }
        if (alias == "ShortText") {
            return typeof value == "string"
                && validSafeOptional(String(value), 512);
        }
        if (alias == "Description") {
            return typeof value == "string"
                && validSafeMultiline(String(value), 12000);
        }
        if (alias == "Summary") {
            return typeof value == "string"
                && validSafeMultiline(String(value), 20000);
        }
        if (alias == "Identity768") {
            return typeof value == "string" && validIdentity(String(value), 768);
        }
        if (alias == "NNI") {
            return typeof value == "number" && validNni(Number(value));
        }
        if (alias == "ShopCatalogIndex") {
            return typeof value == "number"
                && validShopCatalogIndex(Number(value));
        }
        if (alias == "PI") {
            return typeof value == "number" && validPi(Number(value));
        }
        if (alias == "RecipeIndex") {
            return typeof value == "number" && validRecipeIndex(Number(value));
        }
        if (alias == "NN") {
            return typeof value == "number" && validNonNegative(Number(value));
        }
        if (alias == "Bool") return value === true || value === false;
        if (alias == "Color") {
            return typeof value == "string" && validColor(String(value));
        }
        if (typeof value != "number") return false;
        var count:Number = Number(value);
        if (alias == "MaterialsCount") {
            return validCollectionCount(count, 1, MAX_MATERIALS);
        }
        if (alias == "SourcesCount") {
            return validCollectionCount(count, 0, MAX_SOURCES);
        }
        if (alias == "VariantsCount") {
            return validCollectionCount(count, 1, MAX_VARIANTS);
        }
        if (alias == "DirectPurposesCount") {
            return validCollectionCount(count, 0, MAX_DIRECT_PURPOSES);
        }
        if (alias == "UsesCount") {
            return validCollectionCount(count, 0, MAX_USES);
        }
        if (alias == "TaxonomyEntriesCount") {
            return validCollectionCount(count, 0, MAX_TAXONOMY_ENTRIES);
        }
        if (alias == "InfrastructureProjectsCount") {
            return validCollectionCount(count, 1, MAX_INFRASTRUCTURE_PROJECTS);
        }
        if (alias == "InfrastructureLevelsCount") {
            return validCollectionCount(count, 1, MAX_INFRASTRUCTURE_LEVELS);
        }
        return false;
    }

    private static function buildSnapshot(rawCatalog:Object, categories:Array):Object {
        var normalized:Object = normalizeCatalog(rawCatalog, categories);
        if (normalized == null) return null;
        var taxonomy:Object = buildTaxonomy(categories, normalized.directPurposes);
        if (taxonomy == null) return null;
        var infrastructureByMaterial:Object = null;
        if (normalized.directPurposeById[INFRASTRUCTURE_PURPOSE_ID] != undefined) {
            infrastructureByMaterial = buildInfrastructureIndex();
            if (infrastructureByMaterial == null) return null;
        }

        _snapshotSeq++;
        var snapshotId:String = "materials.snapshot." + getTimer() + "." + _snapshotSeq;
        var result:Object = {
            snapshotId:snapshotId,
            taxonomy:taxonomy,
            materials:[],
            byName:{}
        };
        var index:ItemObtainIndex = ItemObtainIndex.getInstance();
        for (var archiveOrder:Number = 0;
                archiveOrder < normalized.materials.length; archiveOrder++) {
            var authored:Object = normalized.materials[archiveOrder];
            var name:String = String(authored.Name);
            var data:Object = ItemUtil.getRawItemData(name);
            if (data == null || !ItemUtil.isMaterial(name)) return invalid("invalid_catalog_item");

            var uses:Array = buildUses(name, categories);
            if (uses == null) return null;
            var directPurposes:Array = buildDirectPurposes(name, authored,
                normalized.directPurposeById, normalized.directPurposes);
            if (directPurposes == null) return null;
            var sources:Array = buildSources(name, index, categories);
            if (sources == null) return null;

            var recipePurposeIds:Array = recipePurposeIdsFor(uses, categories);
            var directPurposeIds:Array = [];
            for (var dp:Number = 0; dp < directPurposes.length; dp++) {
                directPurposeIds.push(String(directPurposes[dp].id));
            }
            var hasInfrastructurePurpose:Boolean = contains(
                directPurposeIds, INFRASTRUCTURE_PURPOSE_ID);
            var infrastructureUses:Array = infrastructureByMaterial == null
                || !(infrastructureByMaterial[name] instanceof Array)
                ? [] : infrastructureByMaterial[name];
            if (hasInfrastructurePurpose != (infrastructureUses.length > 0)) {
                return invalid("invalid_infrastructure_catalog_closure");
            }
            var dropVariantCount:Number = countDropVariants(sources);
            var sourceSummary:String = authored.legacyVisible === true
                ? String(authored.legacyInformation) : "";
            var owned:Number = ownedQuantity(name);
            var displayName:String = presentation(data.displayname, name, 256);
            var icon:String = presentation(data.icon, name, 256);
            var description:String = String(data.description || "");
            if (!validNni(owned) || displayName == null || icon == null
                    || !validSafeMultiline(description, 12000)) {
                return invalid("invalid_material_projection");
            }
            var catalogEntry:Object = {
                name:name,
                displayName:displayName,
                icon:icon,
                owned:owned,
                archiveOrder:archiveOrder,
                typeId:String(authored.typeId),
                recipePurposeIds:recipePurposeIds,
                directPurposeIds:directPurposeIds,
                structuredPurposeCount:uses.length + directPurposes.length,
                sourceCount:sources.length,
                dropVariantCount:dropVariantCount,
                useCount:uses.length,
                hasSourceSummary:sourceSummary.length > 0
            };
            if (catalogEntry.typeId == "equipment_mod") {
                var modFacets:Object = buildModFacets(name);
                if (modFacets == null) return null;
                catalogEntry.modFacetIds = modFacets;
            }
            var detailMaterial:Object = {
                name:name,
                displayName:String(catalogEntry.displayName),
                icon:String(catalogEntry.icon),
                description:description,
                owned:owned,
                sourceSummary:sourceSummary
            };
            result.materials.push(catalogEntry);
            var frozenDetail:Object = {
                catalog:catalogEntry,
                material:detailMaterial,
                sources:sources,
                directPurposes:directPurposes,
                uses:uses
            };
            if (hasInfrastructurePurpose) {
                frozenDetail.infrastructureUses = cloneValue(infrastructureUses, 0);
            }
            result.byName[name] = frozenDetail;
        }
        return result;
    }

    private static function normalizeCatalog(raw:Object, categories:Array):Object {
        if (raw == null || Number(raw.schemaVersion) != 1
                || !hasOnlyKeys(raw, {schemaVersion:true, DirectPurpose:true, Material:true})) {
            return invalid("invalid_catalog");
        }
        var materials:Array = asArray(raw.Material);
        var directPurposes:Array = asArray(raw.DirectPurpose);
        if (!validCollectionCount(materials.length, 1, MAX_MATERIALS)
                || !validCollectionCount(
                    directPurposes.length, 1, MAX_TAXONOMY_ENTRIES)) {
            return invalid("invalid_catalog");
        }
        var purposeById:Object = {};
        var normalizedPurposes:Array = [];
        for (var p:Number = 0; p < directPurposes.length; p++) {
            var purpose:Object = directPurposes[p];
            if (!hasOnlyKeys(purpose,
                    {id:true,label:true,order:true,consumerEvidence:true})) {
                return invalid("invalid_purpose_registry");
            }
            var purposeId:String = String(purpose.id || "");
            var label:String = String(purpose.label || "");
            if (!validIdentity(purposeId, 256) || !validIdentity(label, 512)
                    || Number(purpose.order) != p || purposeById[purposeId] != undefined
                    || !validIdentity(String(purpose.consumerEvidence || ""), 256)) {
                return invalid("invalid_purpose_registry");
            }
            var projected:Object = {id:purposeId, label:label, order:p};
            normalizedPurposes.push(projected);
            purposeById[purposeId] = projected;
        }

        var materialByName:Object = {};
        var normalizedMaterials:Array = [];
        for (var i:Number = 0; i < materials.length; i++) {
            var row:Object = materials[i];
            if (!hasOnlyKeys(row, {Name:true,typeId:true,legacyVisible:true,
                    legacyInformation:true,authoredDirectPurposeId:true})) {
                return invalid("invalid_catalog_item");
            }
            var name:String = String(row.Name || "");
            var typeId:String = String(row.typeId || "");
            if (!validIdentity(name, 128) || materialByName[name] != undefined
                    || !ItemUtil.isMaterial(name)
                    || (typeId != "equipment_mod" && typeId != "food" && typeId != "general")
                    || (row.legacyVisible !== true && row.legacyVisible !== false)) {
                return invalid("invalid_catalog_item");
            }
            if (row.legacyVisible === true) {
                if (typeof row.legacyInformation != "string"
                        || String(row.legacyInformation).length == 0
                        || !validSafeMultiline(String(row.legacyInformation), 20000)) {
                    return invalid("invalid_catalog_item");
                }
            } else if (row.legacyInformation != undefined) {
                return invalid("invalid_catalog_item");
            }
            var authoredIds:Array = row.authoredDirectPurposeId == undefined
                ? [] : asArray(row.authoredDirectPurposeId);
            if (!validCollectionCount(
                    authoredIds.length, 0, MAX_DIRECT_PURPOSES)) {
                return invalid("too_many_direct_purposes");
            }
            var seenPurpose:Object = {};
            for (var ap:Number = 0; ap < authoredIds.length; ap++) {
                var authoredId:String = String(authoredIds[ap] || "");
                if (purposeById[authoredId] == undefined || seenPurpose[authoredId]) {
                    return invalid("invalid_catalog_item");
                }
                seenPurpose[authoredId] = true;
            }
            var normalizedRow:Object = {
                Name:name,
                typeId:typeId,
                legacyVisible:row.legacyVisible,
                authoredDirectPurposeId:authoredIds.slice(0)
            };
            if (row.legacyVisible === true) {
                normalizedRow.legacyInformation = String(row.legacyInformation);
            }
            normalizedMaterials.push(normalizedRow);
            materialByName[name] = normalizedRow;
        }
        var materialCount:Number = 0;
        for (var materialName:String in ItemUtil.materialDict) {
            if (ObjectUtil.isInternalKey(materialName)) continue;
            materialCount++;
            if (materialByName[materialName] == undefined) {
                return invalid("material_catalog_incomplete");
            }
        }
        if (materialCount != normalizedMaterials.length) {
            return invalid("material_catalog_incomplete");
        }
        if (!validateModCatalogClosure(materialByName)) return null;
        if (!validateCategoryClosure(categories)) return null;
        return {materials:normalizedMaterials, directPurposes:normalizedPurposes,
            directPurposeById:purposeById};
    }

    /**
     * equipment mod 的三个运行时注册面必须构成同一个精确集合：
     * ordered modList、modDict 自有键、以及 catalog 中 typeId=equipment_mod 的行。
     * 任一侧额外、重复或缺失都会让整个 v2 snapshot fail closed。
     */
    private static function validateModCatalogClosure(materialByName:Object):Boolean {
        var modList:Array = EquipmentUtil.modList;
        var modDict:Object = EquipmentUtil.modDict;
        var materialDict:Object = ItemUtil.materialDict;
        if (!(modList instanceof Array) || modDict == null
                || typeof modDict != "object" || materialDict == null
                || typeof materialDict != "object") {
            invalid("invalid_mod_catalog_closure");
            return false;
        }

        var listByName:Object = {};
        for (var i:Number = 0; i < modList.length; i++) {
            var rawName = modList[i];
            if (typeof rawName != "string") {
                invalid("invalid_mod_catalog_closure");
                return false;
            }
            var name:String = String(rawName);
            var catalogRow:Object = materialByName[name];
            if (!validIdentity(name, 128) || listByName[name] === true
                    || !owns(modDict, name) || modDict[name] == null
                    || !owns(materialByName, name) || catalogRow == null
                    || String(catalogRow.typeId) != "equipment_mod"
                    || !owns(materialDict, name) || materialDict[name] !== true) {
                invalid("invalid_mod_catalog_closure");
                return false;
            }
            listByName[name] = true;
        }

        var dictCount:Number = 0;
        for (var dictName:String in modDict) {
            if (!owns(modDict, dictName)) continue;
            dictCount++;
            var dictCatalogRow:Object = materialByName[dictName];
            if (!validIdentity(dictName, 128) || modDict[dictName] == null
                    || listByName[dictName] !== true
                    || !owns(materialByName, dictName) || dictCatalogRow == null
                    || String(dictCatalogRow.typeId) != "equipment_mod"
                    || !owns(materialDict, dictName)
                    || materialDict[dictName] !== true) {
                invalid("invalid_mod_catalog_closure");
                return false;
            }
        }

        var catalogModCount:Number = 0;
        for (var catalogName:String in materialByName) {
            if (!owns(materialByName, catalogName)) continue;
            var row:Object = materialByName[catalogName];
            if (String(row.typeId) != "equipment_mod") continue;
            catalogModCount++;
            if (listByName[catalogName] !== true || !owns(modDict, catalogName)
                    || modDict[catalogName] == null
                    || !owns(materialDict, catalogName)
                    || materialDict[catalogName] !== true) {
                invalid("invalid_mod_catalog_closure");
                return false;
            }
        }
        if (modList.length != dictCount || modList.length != catalogModCount) {
            invalid("invalid_mod_catalog_closure");
            return false;
        }
        return true;
    }

    private static function buildTaxonomy(categories:Array,
                                           directPurposes:Array):Object {
        var recipePurposes:Array = [];
        for (var i:Number = 0; i < categories.length; i++) {
            var category:String = String(categories[i]);
            if (!validIdentity(category, 256)
                    || !validIdentity("recipe:" + category, 256)) {
                return invalid("invalid_recipe_category");
            }
            recipePurposes.push({id:"recipe:" + category, label:category, order:i});
        }
        var gradeValues:Array = buildModTaxonomyValues(
            "grade", ["low","medium","high","special"]);
        var scopeValues:Array = buildModTaxonomyValues(
            "scope", ["armor","firearm","blade","fist","universal","underbarrel"]);
        var roleValues:Array = buildModTaxonomyValues(
            "role", ["firepower","precision","stability","sustain","utility","mechanism"]);
        if (gradeValues == null || scopeValues == null || roleValues == null) return null;
        var taxonomy:Object = {
            version:1,
            roots:[
                {id:"type", label:"类型", order:0},
                {id:"purpose", label:"用途", order:1}
            ],
            types:[
                {id:"equipment_mod", label:"改装材料", order:0},
                {id:"food", label:"食材", order:1},
                {id:"general", label:"通用材料", order:2}
            ],
            modAxes:[
                {id:"grade", label:"档级", order:0, values:gradeValues},
                {id:"scope", label:"适用范围", order:1, values:scopeValues},
                {id:"role", label:"定位", order:2, values:roleValues}
            ],
            recipePurposes:recipePurposes,
            directPurposes:cloneValue(directPurposes, 0),
            fallback:{id:"unstructured", label:"尚未结构化用途", order:2147483647}
        };
        var entryCount:Number = taxonomy.roots.length + taxonomy.types.length
            + taxonomy.recipePurposes.length + taxonomy.directPurposes.length + 1;
        for (var axis:Number = 0; axis < taxonomy.modAxes.length; axis++) {
            entryCount += 1 + taxonomy.modAxes[axis].values.length;
        }
        if (!validCollectionCount(
                entryCount, 0, MAX_TAXONOMY_ENTRIES)) {
            return invalid("too_many_taxonomy_entries");
        }
        return taxonomy;
    }

    /**
     * 标签、颜色与符号只从 EquipModListLoader 已应用到 modList 的展示数据派生；
     * 本投影器仅冻结协议要求的 axis/id/order，不复制 ui_presentation.xml 文案。
     */
    private static function buildModTaxonomyValues(axis:String, ids:Array):Array {
        if (!(EquipmentUtil.modList instanceof Array)) {
            return invalid("mod_presentation_unavailable");
        }
        var result:Array = [];
        for (var order:Number = 0; order < ids.length; order++) {
            var id:String = String(ids[order]);
            var projected:Object = null;
            for (var i:Number = 0; i < EquipmentUtil.modList.length; i++) {
                var modName:String = String(EquipmentUtil.modList[i] || "");
                if (!validIdentity(modName, 128) || EquipmentUtil.modDict == undefined) {
                    return invalid("invalid_mod_presentation_source");
                }
                var mod:Object = EquipmentUtil.modDict[modName];
                if (mod == null) return invalid("invalid_mod_presentation_source");
                var matches:Boolean = axis == "grade" ? String(mod.modGrade) == id
                    : axis == "scope" ? String(mod.catalogScope) == id
                    : String(mod.uiRole) == id;
                if (!matches) continue;
                var label:String = axis == "grade" ? String(mod.uiGradeLabel || "")
                    : axis == "scope" ? String(mod.uiScopeLabel || "")
                    : String(mod.uiRoleLabel || "");
                if (!validIdentity(label, 512)) return invalid("invalid_mod_presentation");
                var current:Object = {id:id, label:label, order:order};
                if (axis == "grade") {
                    current.color = String(mod.uiGradeColor || "");
                    if (!validColor(current.color)) return invalid("invalid_mod_presentation");
                } else if (axis == "role") {
                    current.symbol = String(mod.uiSymbol || "");
                    if (!contains(["triangle-solid","triangle-outline","square-outline",
                            "circle-outline","diamond-outline","star-solid"], current.symbol)) {
                        return invalid("invalid_mod_presentation");
                    }
                }
                if (projected == null) {
                    projected = current;
                } else if (projected.label != current.label
                        || (axis == "grade" && projected.color != current.color)
                        || (axis == "role" && projected.symbol != current.symbol)) {
                    return invalid("inconsistent_mod_presentation");
                }
            }
            if (projected == null) return invalid("incomplete_mod_presentation");
            result.push(projected);
        }
        return result;
    }

    private static function buildModFacets(name:String):Object {
        var modData:Object = EquipmentUtil.modDict == undefined
            ? null : EquipmentUtil.modDict[name];
        if (modData == null) return invalid("invalid_mod_catalog_closure");
        var grade:String = String(modData.modGrade || "");
        var scope:String = String(modData.catalogScope || "");
        var role:String = String(modData.uiRole || "utility");
        if (!contains(["low","medium","high","special"], grade)
                || !contains(["armor","firearm","blade","fist","universal","underbarrel"], scope)
                || !contains(["firepower","precision","stability","sustain","utility","mechanism"], role)) {
            return invalid("invalid_mod_taxonomy");
        }
        return {grade:grade, scope:scope, role:role};
    }

    private static function buildDirectPurposes(name:String, authored:Object,
            purposeById:Object, purposeRegistry:Array):Array {
        var ids:Object = {};
        if (EquipmentUtil.modDict != undefined && EquipmentUtil.modDict[name] != null) {
            ids["system:equipment_tuning"] = true;
        }
        var authoredIds:Array = authored.authoredDirectPurposeId;
        for (var i:Number = 0; i < authoredIds.length; i++) {
            ids[String(authoredIds[i])] = true;
        }
        var result:Array = [];
        for (var p:Number = 0; p < purposeRegistry.length; p++) {
            var purpose:Object = purposeRegistry[p];
            if (ids[String(purpose.id)] === true) {
                result.push({id:String(purpose.id), label:String(purpose.label),
                    order:Number(purpose.order)});
                delete ids[String(purpose.id)];
            }
        }
        for (var unknown:String in ids) return invalid("unknown_direct_purpose");
        if (!validCollectionCount(
                result.length, 0, MAX_DIRECT_PURPOSES)) {
            return invalid("too_many_direct_purposes");
        }
        return result;
    }

    private static function buildUses(inputName:String, categories:Array):Array {
        var indexedUses = SynthesisIndex.getRecipeUses(inputName);
        if (!(indexedUses instanceof Array)) return invalid("invalid_recipe_uses");
        var raw:Array = indexedUses.slice(0);
        if (!validCollectionCount(raw.length, 0, MAX_USES)) {
            return invalid("too_many_uses");
        }
        raw.sort(compareUses);
        var result:Array = [];
        var seen:Object = {};
        for (var i:Number = 0; i < raw.length; i++) {
            var ref:Object = raw[i];
            var category:String = String(ref.category || "");
            var recipeIndex:Number = Number(ref.recipeIndex);
            var productName:String = String(ref.productName || "");
            if (_categoryRank[category] == undefined || !validRecipeIndex(recipeIndex)
                    || !validIdentity(productName, 128)) {
                return invalid("invalid_recipe_use");
            }
            var identity:String = category.length + ":" + category + "|" + recipeIndex;
            if (seen[identity]) return invalid("duplicate_recipe_use");
            seen[identity] = true;
            var recipes:Array = _root.改装清单[category];
            var recipe:Object = recipes == null ? null : recipes[recipeIndex];
            if (recipe == null || String(recipe.name || "") != productName
                    || !(recipe.materials instanceof Array)) {
                return invalid("stale_recipe_use");
            }
            var required:Number = requiredQuantity(recipe, inputName);
            var ingredients:Array = buildIngredients(recipe);
            if (ingredients == null) return null;
            var data:Object = ItemUtil.getRawItemData(productName);
            var displayName:String = data == null ? null
                : presentation(data.displayname, productName, 256);
            var icon:String = data == null ? null
                : presentation(data.icon, productName, 256);
            if (!validPi(required) || data == null
                    || displayName == null || icon == null) {
                return invalid("invalid_recipe_use");
            }
            result.push({
                category:category,
                recipeIndex:recipeIndex,
                productName:productName,
                displayName:displayName,
                icon:icon,
                itemKind:ItemUtil.isEquipment(productName) ? "equipment" : "stack",
                required:required,
                ingredients:ingredients
            });
        }
        return result;
    }

    private static function buildIngredients(recipe:Object):Array {
        var requirements:Array = ItemUtil.getRequirementFromTask(recipe.materials || []);
        if (!(requirements instanceof Array)
                || !validCollectionCount(requirements.length, 1, MAX_RECIPE_INGREDIENTS)) {
            return invalid("invalid_recipe_ingredients");
        }
        var result:Array = [];
        for (var i:Number = 0; i < requirements.length; i++) {
            var requirement:Object = requirements[i];
            var name:String = String(requirement == null ? "" : requirement.name || "");
            var data:Object = ItemUtil.getRawItemData(name);
            var required:Number = Number(requirement == null ? 0 : requirement.value);
            if (isNaN(required) || required <= 0) required = 1;
            var displayName:String = data == null ? null
                : presentation(data.displayname, name, 256);
            var icon:String = data == null ? null
                : presentation(data.icon, name, 256);
            if (!validIdentity(name, 128) || data == null || displayName == null
                    || icon == null || !validPi(required)) {
                return invalid("invalid_recipe_ingredient");
            }
            result.push({
                name:name,
                displayName:displayName,
                icon:icon,
                required:required,
                isQuantity:requirement.isQuantity === true || !ItemUtil.isEquipment(name)
            });
        }
        return result;
    }

    private static function requiredQuantity(recipe:Object, inputName:String):Number {
        var requirements:Array = ItemUtil.getRequirementFromTask(recipe.materials || []);
        var required:Number = 0;
        for (var i:Number = 0; i < requirements.length; i++) {
            if (String(requirements[i].name) == inputName) {
                required += Number(requirements[i].value);
            }
        }
        return required;
    }

    private static function recipePurposeIdsFor(uses:Array, categories:Array):Array {
        var seen:Object = {};
        for (var i:Number = 0; i < uses.length; i++) {
            seen[String(uses[i].category)] = true;
        }
        var result:Array = [];
        for (var c:Number = 0; c < categories.length; c++) {
            var category:String = String(categories[c]);
            if (seen[category]) result.push("recipe:" + category);
        }
        return result;
    }

    private static function buildSources(itemName:String, index:ItemObtainIndex,
                                         categories:Array):Array {
        var exactRecords = index.getExactObtainRecords(itemName);
        if (!(exactRecords instanceof Array)) return invalid("invalid_sources");
        var raw:Array = exactRecords.slice(0);
        raw.sort(compareSourceRecords);
        if (!validCollectionCount(raw.length, 0, MAX_SOURCES)) {
            return invalid("too_many_sources");
        }
        var result:Array = [];
        var sourceKeys:Object = {};
        for (var i:Number = 0; i < raw.length; i++) {
            var projected:Object = projectSource(raw[i], i, itemName);
            if (projected == null) return null;
            if (sourceKeys[String(projected.sourceKey)] === true) {
                return invalid("duplicate_source_identity");
            }
            sourceKeys[String(projected.sourceKey)] = true;
            result.push(projected);
        }
        return result;
    }

    private static function projectSource(record:Object, sourceOrder:Number,
                                          expectedItemName:String):Object {
        if (record == null) return invalid("invalid_source");
        var kind:String = normalizedKind(record);
        if (kind == "craft") return projectCraftSource(record, sourceOrder, expectedItemName);
        if (kind == "shop") return projectShopSource(record, sourceOrder, expectedItemName);
        if (kind == "kshop") return projectKShopSource(record, sourceOrder);
        if (kind == "quest") return projectQuestSource(record, sourceOrder);
        if (kind == "stage") return projectStageSource(record, sourceOrder);
        if (kind == "enemy") return projectEnemySource(record, sourceOrder);
        return invalid("unsupported_source_kind");
    }

    private static function projectCraftSource(record:Object, sourceOrder:Number,
                                               expectedItemName:String):Object {
        var category:String = String(record.category || "");
        var recipeIndex:Number = Number(record.recipeIndex);
        var productName:String = String(record.productName || "");
        var price:Number = Number(record.price);
        var kpoints:Number = Number(record.kprice);
        if (_categoryRank[category] == undefined || !validRecipeIndex(recipeIndex)
                || !validIdentity(productName, 128) || productName != expectedItemName
                || !validNonNegative(price)
                || !validNonNegative(kpoints)) return invalid("invalid_craft_source");
        var key:String = sourceKey(["craft",category,String(recipeIndex)]);
        if (key == null) return invalid("invalid_source_key");
        return {kind:"craft", sourceKey:key,
            sourceOrder:sourceOrder, category:category, recipeIndex:recipeIndex,
            productName:productName, price:price, kpoints:kpoints};
    }

    private static function projectShopSource(record:Object, sourceOrder:Number,
                                              expectedItemName:String):Object {
        var shopId:String = String(record.shopId || "");
        var catalogIndex:Number = Number(record.catalogIndex);
        var itemName:String = String(record.itemName || "");
        if (!validIdentity(shopId, 80) || !validShopCatalogIndex(catalogIndex)
                || !validIdentity(itemName, 128) || itemName != expectedItemName) {
            return invalid("invalid_shop_source");
        }
        // Dynamic fields are joined from NPCShop.buildCatalog on detail request.
        var key:String = sourceKey(["shop",shopId,String(catalogIndex)]);
        if (key == null) return invalid("invalid_source_key");
        return {kind:"shop", sourceKey:key,
            sourceOrder:sourceOrder, shopId:shopId, catalogIndex:catalogIndex,
            itemName:itemName};
    }

    private static function projectKShopSource(record:Object, sourceOrder:Number):Object {
        var catalogIndex:Number = Number(record.catalogIndex);
        var entryId:String = String(record.entryId || "");
        var category:String = String(record.type || "");
        var priceK:Number = Number(record.priceK);
        if (!validNni(catalogIndex) || !validIdentity(entryId, 256)
                || !validSafeOptional(category, 512)
                || !validNonNegative(priceK)) return invalid("invalid_kshop_source");
        var key:String = sourceKey(["kshop",String(catalogIndex)]);
        if (key == null) return invalid("invalid_source_key");
        return {kind:"kshop", sourceKey:key,
            sourceOrder:sourceOrder, catalogIndex:catalogIndex, entryId:entryId,
            category:category, priceK:priceK};
    }

    private static function projectQuestSource(record:Object, sourceOrder:Number):Object {
        var questId:String = String(record.questId || "");
        var rewardSet:String = String(record.rewardSet || "");
        var authoredIndex:Number = Number(record.authoredIndex);
        var quantity:Number = Number(record.quantity);
        var title:String = visibleLabel(record.questTitle, "未知任务", 512);
        if (!validIdentity(questId, 256) || (rewardSet != "base" && rewardSet != "challenge")
                || !validNni(authoredIndex) || !validPi(quantity)
                || title == null) return invalid("invalid_quest_source");
        var key:String = sourceKey(["quest",questId,rewardSet,String(authoredIndex)]);
        if (key == null) return invalid("invalid_source_key");
        return {kind:"quest", sourceKey:key, sourceOrder:sourceOrder, questId:questId,
            rewardSet:rewardSet, authoredIndex:authoredIndex,
            title:title, quantity:quantity};
    }

    private static function projectStageSource(record:Object, sourceOrder:Number):Object {
        var stageName:String = String(record.stageName || "");
        var variants:Array = record.variants instanceof Array ? record.variants : [];
        if (!validIdentity(stageName, 256)
                || !validCollectionCount(variants.length, 1, MAX_VARIANTS)
                || String(record.chanceModel) != "stage_roll_divisor_with_legacy_domain_branch"
                || String(record.legacyConditionId) != "andylaw_domain_bonus") {
            return invalid("invalid_stage_source");
        }
        var projected:Array = [];
        for (var i:Number = 0; i < variants.length; i++) {
            var variant:Object = variants[i];
            var divisor:Number = Number(variant.rollDivisor);
            var chance:Number = Number(variant.defaultBranchChancePercent);
            var quantityMin:Number = Number(variant.quantityMin);
            var quantityMax:Number = Number(variant.quantityMax);
            if (Number(variant.occurrenceIndex) != i || !validPi(divisor)
                    || !validNonNegative(chance) || chance > 100
                    || Math.abs(chance - round6(100 / divisor)) > 0.0000005
                    || !validPi(quantityMin)
                    || !validPi(quantityMax) || quantityMin > quantityMax) {
                return invalid("invalid_stage_variant");
            }
            projected.push({occurrenceIndex:i, rollDivisor:divisor,
                defaultBranchChancePercent:chance, quantityMin:quantityMin,
                quantityMax:quantityMax});
        }
        var key:String = sourceKey(["stage",stageName]);
        if (key == null) return invalid("invalid_source_key");
        return {kind:"stage", sourceKey:key,
            sourceOrder:sourceOrder, stageName:stageName,
            chanceModel:"stage_roll_divisor_with_legacy_domain_branch",
            legacyConditionId:"andylaw_domain_bonus", variants:projected};
    }

    private static function projectEnemySource(record:Object, sourceOrder:Number):Object {
        var enemyType:String = String(record.enemyType || "");
        var variants:Array = record.variants instanceof Array ? record.variants : [];
        var properties:Object = _root.敌人属性表 == undefined
            ? null : _root.敌人属性表[enemyType];
        if (!validIdentity(enemyType, 256) || enemyType.indexOf("敌人-") != 0
                || properties == null
                || !validCollectionCount(variants.length, 1, MAX_VARIANTS)
                || String(record.chanceModel) != "enemy_prd_with_reverse_bonus") {
            return invalid("invalid_enemy_source");
        }
        var projected:Array = [];
        for (var i:Number = 0; i < variants.length; i++) {
            var variant:Object = variants[i];
            var state:String = String(variant.chanceInputState || "");
            var chanceRaw = variant.chanceRaw;
            var nominal:Number = Number(variant.nominalChancePercent);
            var minLevel = variant.minReverseLevel;
            var maxLevel = variant.maxReverseLevel;
            var quantityMin:Number = Number(variant.quantityMin);
            var quantityMax:Number = Number(variant.quantityMax);
            var validChance:Boolean = state == "explicit"
                ? validNonNegative(Number(chanceRaw)) && Number(chanceRaw) <= 100
                    && nominal === Number(chanceRaw)
                : (state == "absent_defaulted" || state == "invalid_defaulted")
                    && chanceRaw == null && nominal === 100;
            if (Number(variant.occurrenceIndex) != i || !validChance
                    || !validNullableBound(minLevel) || !validNullableBound(maxLevel)
                    || (minLevel != null && maxLevel != null
                        && Number(minLevel) > Number(maxLevel))
                    || !validPi(quantityMin)
                    || !validPi(quantityMax) || quantityMin > quantityMax) {
                return invalid("invalid_enemy_variant");
            }
            projected.push({occurrenceIndex:i,
                chanceRaw:state == "explicit" ? Number(chanceRaw) : null,
                chanceInputState:state, nominalChancePercent:nominal,
                minReverseLevel:minLevel == null ? null : Number(minLevel),
                maxReverseLevel:maxLevel == null ? null : Number(maxLevel),
                quantityMin:quantityMin, quantityMax:quantityMax});
        }
        var displayName:String = visibleLabel(properties.displayname, "未知敌人", 512);
        var key:String = sourceKey(["enemy",enemyType]);
        if (displayName == null || key == null) return invalid("invalid_enemy_source");
        return {kind:"enemy", sourceKey:key,
            sourceOrder:sourceOrder, enemyType:enemyType,
            displayName:displayName,
            chanceModel:"enemy_prd_with_reverse_bonus", variants:projected};
    }

    private static function buildDetailSources(frozenSources:Array):Array {
        _buildError = "";
        var result:Array = [];
        var shopCatalogs:Object = {};
        for (var i:Number = 0; i < frozenSources.length; i++) {
            var source:Object = frozenSources[i];
            if (String(source.kind) != "shop") {
                result.push(cloneValue(source, 0));
                continue;
            }
            var shopId:String = String(source.shopId);
            var catalog:Array = shopCatalogs[shopId];
            if (catalog == undefined) {
                var npcService:Object = _root.UI系统 == undefined
                    ? null : _root.UI系统.NPC商店WebView;
                if (npcService == null || typeof npcService.buildCatalog != "function") {
                    return invalid("shop_snapshot_unavailable");
                }
                catalog = npcService.buildCatalog(shopId);
                shopCatalogs[shopId] = catalog;
            }
            var liveEntry:Object = findCatalogEntry(catalog, Number(source.catalogIndex));
            var requiredInfo:String = liveEntry == null
                ? "" : String(liveEntry.requiredInfo || "");
            if (liveEntry == null || String(liveEntry.itemName) != String(source.itemName)
                    || !validNonNegative(Number(liveEntry.basePrice))
                    || !validNonNegative(Number(liveEntry.unitPrice))
                    || !validSafeOptional(requiredInfo, 512)
                    || (liveEntry.locked !== true && liveEntry.locked !== false)) {
                return invalid("shop_snapshot_mismatch");
            }
            var fullAccess:Boolean = canProjectFullShopAccess(source, catalog);
            result.push({
                kind:"shop",
                sourceKey:String(source.sourceKey),
                sourceOrder:Number(source.sourceOrder),
                shopId:shopId,
                catalogIndex:Number(source.catalogIndex),
                itemName:String(source.itemName),
                basePrice:Number(liveEntry.basePrice),
                unitPriceAtSnapshot:Number(liveEntry.unitPrice),
                requiredInfo:requiredInfo,
                locked:liveEntry.locked === true,
                shopAccessMode:fullAccess ? "full" : "unavailable",
                shopAccessReason:fullAccess ? "indexed_live_match"
                    : "no_authoritative_remote_access_capability"
            });
        }
        return result;
    }

    private static function findCatalogEntry(catalog:Array, catalogIndex:Number):Object {
        if (!(catalog instanceof Array)) return null;
        for (var i:Number = 0; i < catalog.length; i++) {
            if (Number(catalog[i].catalogIndex) == catalogIndex) return catalog[i];
        }
        return null;
    }

    private static function validShopAccessRequest(params:Object):Boolean {
        if (params == null || typeof params != "object"
                || !hasOnlyKeys(params, {task:true,action:true,callId:true,v:true,
                    materialSnapshotId:true,materialName:true,shopId:true,
                    catalogIndex:true})
                || !owns(params, "task") || !owns(params, "action")
                || !owns(params, "callId") || !owns(params, "v")
                || !owns(params, "materialSnapshotId")
                || !owns(params, "materialName") || !owns(params, "shopId")
                || !owns(params, "catalogIndex")) return false;
        return typeof params.task == "string" && params.task === "cmd"
            && typeof params.action == "string"
            && params.action === "craftingMaterialShopAuthorize"
            && typeof params.callId == "number"
            && validIntegerRange(Number(params.callId), 1, 2147483647)
            && typeof params.v == "number" && params.v === 1
            && typeof params.materialSnapshotId == "string"
            && validIdentity(String(params.materialSnapshotId), 256)
            && typeof params.materialName == "string"
            && validIdentity(String(params.materialName), 128)
            && typeof params.shopId == "string"
            && validIdentity(String(params.shopId), 80)
            && typeof params.catalogIndex == "number"
            && validShopCatalogIndex(Number(params.catalogIndex));
    }

    private static function validKShopAccessRequest(params:Object):Boolean {
        if (params == null || typeof params != "object"
                || !hasOnlyKeys(params, {task:true,action:true,callId:true,v:true,
                    materialSnapshotId:true,materialName:true,catalogIndex:true,
                    entryId:true,category:true})
                || !owns(params, "task") || !owns(params, "action")
                || !owns(params, "callId") || !owns(params, "v")
                || !owns(params, "materialSnapshotId") || !owns(params, "materialName")
                || !owns(params, "catalogIndex") || !owns(params, "entryId")
                || !owns(params, "category")) return false;
        return typeof params.task == "string" && params.task === "cmd"
            && typeof params.action == "string"
            && params.action === "craftingMaterialKShopAuthorize"
            && typeof params.callId == "number"
            && validIntegerRange(Number(params.callId), 1, 2147483647)
            && typeof params.v == "number" && params.v === 1
            && typeof params.materialSnapshotId == "string"
            && validIdentity(String(params.materialSnapshotId), 256)
            && typeof params.materialName == "string"
            && validIdentity(String(params.materialName), 128)
            && typeof params.catalogIndex == "number"
            && validShopCatalogIndex(Number(params.catalogIndex))
            && typeof params.entryId == "string"
            && validIdentity(String(params.entryId), 256)
            && typeof params.category == "string"
            && validIdentity(String(params.category), 512);
    }

    private static function countFrozenShopSources(sources:Array,
            materialName:String, shopId:String, catalogIndex:Number):Number {
        if (!(sources instanceof Array)) return 0;
        var count:Number = 0;
        for (var i:Number = 0; i < sources.length; i++) {
            var source:Object = sources[i];
            if (source != null && String(source.kind) == "shop"
                    && String(source.shopId) == shopId
                    && typeof source.catalogIndex == "number"
                    && Number(source.catalogIndex) === catalogIndex
                    && String(source.itemName) == materialName) count++;
        }
        return count;
    }

    private static function countCurrentShopSources(records:Array,
            materialName:String, shopId:String, catalogIndex:Number):Number {
        var count:Number = 0;
        for (var i:Number = 0; i < records.length; i++) {
            var record:Object = records[i];
            if (record != null && normalizedKind(record) == "shop"
                    && String(record.shopId) == shopId
                    && typeof record.catalogIndex == "number"
                    && Number(record.catalogIndex) === catalogIndex
                    && String(record.itemName) == materialName) count++;
        }
        return count;
    }

    private static function countFrozenKShopSources(sources:Array,
            catalogIndex:Number, entryId:String, category:String):Number {
        if (!(sources instanceof Array)) return 0;
        var count:Number = 0;
        for (var i:Number = 0; i < sources.length; i++) {
            var source:Object = sources[i];
            if (source != null && String(source.kind) == "kshop"
                    && typeof source.catalogIndex == "number"
                    && Number(source.catalogIndex) === catalogIndex
                    && String(source.entryId) == entryId
                    && String(source.category) == category) count++;
        }
        return count;
    }

    private static function countCurrentKShopSources(records:Array,
            catalogIndex:Number, entryId:String, category:String):Number {
        var count:Number = 0;
        for (var i:Number = 0; i < records.length; i++) {
            var record:Object = records[i];
            if (record != null && normalizedKind(record) == "kshop"
                    && typeof record.catalogIndex == "number"
                    && Number(record.catalogIndex) === catalogIndex
                    && String(record.entryId || "") == entryId
                    && String(record.type || "") == category) count++;
        }
        return count;
    }

    private static function rawShopItemName(shop:Object,
            catalogIndex:Number):String {
        var raw = shop[String(catalogIndex)];
        if (raw == undefined) raw = shop[catalogIndex];
        if (typeof raw == "string") return String(raw);
        if (raw != null && typeof raw == "object"
                && typeof raw.name == "string") return String(raw.name);
        return null;
    }

    /** Exactly one live slot is required; another same-name slot cannot rescue it. */
    private static function exactLiveCatalogEntry(catalog:Array,
            catalogIndex:Number):Object {
        var matched:Object = null;
        var count:Number = 0;
        for (var i:Number = 0; i < catalog.length; i++) {
            var entry:Object = catalog[i];
            if (entry != null && typeof entry.catalogIndex == "number"
                    && Number(entry.catalogIndex) === catalogIndex) {
                count++;
                matched = entry;
            }
        }
        return count == 1 ? matched : null;
    }

    private static function canProjectFullShopAccess(source:Object,
                                                      catalog:Array):Boolean {
        if (_snapshot == null || source == null || !(catalog instanceof Array)
                || _root.shops == undefined || _root.shops == null) return false;
        var materialName:String = String(source.itemName);
        var shopId:String = String(source.shopId);
        var catalogIndex:Number = Number(source.catalogIndex);
        var index:ItemObtainIndex = ItemObtainIndex.getInstance();
        if (index == null || index.isIndexBuilt() !== true) return false;
        var records = index.getExactObtainRecords(materialName);
        if (!(records instanceof Array)
                || countCurrentShopSources(records, materialName, shopId,
                    catalogIndex) != 1) return false;
        var shop:Object = _root.shops[shopId];
        if (shop == undefined || shop == null
                || rawShopItemName(shop, catalogIndex) != materialName) return false;
        var live:Object = exactLiveCatalogEntry(catalog, catalogIndex);
        return live != null && String(live.itemName) == materialName;
    }

    private static function shopAccessFailure(callId:Number, decision:String,
                                              errorCode:String):Object {
        return {task:"material_shop_access_response", callId:callId,
            success:false, v:1, decision:decision, error:errorCode};
    }

    /**
     * 复用车库/地图现役基建存档语义：更高级载具自然满足低档出行。
     * 只投影两个业务能力，不把原始存档标志交给 Web 重新解释。
     */
    private static function currentNavigationAccess():Object {
        var infra:Object = _root.基建系统 == undefined
            ? null : _root.基建系统.infrastructure;
        var bicycle:Boolean = infrastructureUnlocked(infra, "自行车");
        var motorcycle:Boolean = infrastructureUnlocked(infra, "摩托车");
        var offroad:Boolean = infrastructureUnlocked(infra, "越野车");
        return {
            shop:bicycle || motorcycle || offroad,
            crafting:motorcycle || offroad
        };
    }

    private static function infrastructureUnlocked(infra:Object, key:String):Boolean {
        if (infra == null || infra[key] == undefined || infra[key] == null) return false;
        return Number(infra[key]) >= 1;
    }

    /**
     * Freeze the normalized infrastructure material requirements once per
     * material catalog snapshot. Level array position is the upgrade identity;
     * the XML id attribute is intentionally not projected.
     */
    private static function buildInfrastructureIndex():Object {
        var system:Object = _root.基建系统;
        var projects:Array = system == null ? null : system.nameList;
        var projectDict:Object = system == null ? null : system.dict;
        if (!(projects instanceof Array) || projectDict == null
                || typeof projectDict != "object"
                || !validCollectionCount(projects.length, 1,
                    MAX_INFRASTRUCTURE_PROJECTS)) {
            return invalid("infrastructure_unavailable");
        }

        var result:Object = {};
        var seenProjects:Object = {};
        for (var projectOrder:Number = 0;
                projectOrder < projects.length; projectOrder++) {
            var project:Object = projects[projectOrder];
            var infrastructureName:String = project == null
                ? "" : String(project.Name || "");
            var levels:Array = project == null ? null : project.Level;
            if (!validIdentity(infrastructureName, 128)
                    || owns(seenProjects, infrastructureName)
                    || !owns(projectDict, infrastructureName)
                    || projectDict[infrastructureName] !== project
                    || !(levels instanceof Array)
                    || !validCollectionCount(levels.length, 2,
                        MAX_INFRASTRUCTURE_LEVELS + 1)) {
                return invalid("invalid_infrastructure_catalog");
            }
            seenProjects[infrastructureName] = true;
            var maximumLevel:Number = levels.length - 1;
            for (var levelIndex:Number = 0;
                    levelIndex < levels.length; levelIndex++) {
                var level:Object = levels[levelIndex];
                if (level == null || typeof level != "object") {
                    return invalid("invalid_infrastructure_catalog");
                }
                var requirements:Array = asArray(level.Material);
                if (levelIndex == maximumLevel && requirements.length > 0) {
                    return invalid("invalid_infrastructure_catalog");
                }
                var seenMaterials:Object = {};
                for (var requirementIndex:Number = 0;
                        requirementIndex < requirements.length; requirementIndex++) {
                    var requirement:Object = requirements[requirementIndex];
                    var materialName:String = requirement == null
                        ? "" : String(requirement.Name || "");
                    var rawRequired = requirement == null ? undefined : requirement.Value;
                    var required:Number = Number(rawRequired);
                    if (!hasOnlyKeys(requirement, {Name:true, Value:true})
                            || !validIdentity(materialName, 128)
                            || !ItemUtil.isMaterial(materialName)
                            || owns(seenMaterials, materialName)
                            || (typeof rawRequired != "number"
                                && typeof rawRequired != "string")
                            || !validPi(required)) {
                        return invalid("invalid_infrastructure_catalog");
                    }
                    seenMaterials[materialName] = true;
                    var materialProjects:Array = result[materialName];
                    if (!(materialProjects instanceof Array)) {
                        materialProjects = [];
                        result[materialName] = materialProjects;
                    }
                    var materialProject:Object = materialProjects.length == 0
                        ? null : materialProjects[materialProjects.length - 1];
                    if (materialProject == null
                            || Number(materialProject.projectOrder) != projectOrder) {
                        materialProject = {
                            infrastructureName:infrastructureName,
                            projectOrder:projectOrder,
                            maximumLevel:maximumLevel,
                            levels:[]
                        };
                        materialProjects.push(materialProject);
                    }
                    materialProject.levels.push({
                        levelIndex:levelIndex,
                        targetLevel:levelIndex + 1,
                        required:required
                    });
                }
            }
        }

        var dictionaryCount:Number = 0;
        for (var dictionaryName:String in projectDict) {
            if (ObjectUtil.isInternalKey(dictionaryName)
                    || !owns(projectDict, dictionaryName)) continue;
            dictionaryCount++;
            if (!owns(seenProjects, dictionaryName)) {
                return invalid("invalid_infrastructure_catalog");
            }
        }
        if (dictionaryCount != projects.length) {
            return invalid("invalid_infrastructure_catalog");
        }
        return result;
    }

    /**
     * Discovery and current level remain live save state. Requirements and
     * owned quantity stay bound to the frozen material catalog snapshot.
     */
    private static function buildLiveInfrastructureUses(
            frozenProjects:Array, owned:Number):Array {
        var system:Object = _root.基建系统;
        var infrastructure:Object = system == null ? null : system.infrastructure;
        if (infrastructure == null || typeof infrastructure != "object") {
            return invalid("infrastructure_unavailable");
        }
        var result:Array = [];
        for (var projectIndex:Number = 0;
                projectIndex < frozenProjects.length; projectIndex++) {
            var frozenProject:Object = frozenProjects[projectIndex];
            var infrastructureName:String = String(
                frozenProject.infrastructureName || "");
            if (!owns(infrastructure, infrastructureName)) continue;
            var rawCurrent = infrastructure[infrastructureName];
            // Missing save keys are undiscovered projects and intentionally omitted.
            if (rawCurrent == undefined || rawCurrent == null) continue;
            var currentLevel:Number = Number(rawCurrent);
            var maximumLevel:Number = Number(frozenProject.maximumLevel);
            if (typeof rawCurrent != "number"
                    || !validIntegerRange(currentLevel, 0, maximumLevel)) {
                return invalid("invalid_infrastructure_state");
            }
            var projectedLevels:Array = [];
            var frozenLevels:Array = frozenProject.levels;
            for (var levelOffset:Number = 0;
                    levelOffset < frozenLevels.length; levelOffset++) {
                var frozenLevel:Object = frozenLevels[levelOffset];
                var levelIndex:Number = Number(frozenLevel.levelIndex);
                var required:Number = Number(frozenLevel.required);
                var completed:Boolean = currentLevel > levelIndex;
                var status:String = completed ? "completed"
                    : (currentLevel == levelIndex ? "current" : "future");
                projectedLevels.push({
                    levelIndex:levelIndex,
                    targetLevel:Number(frozenLevel.targetLevel),
                    required:required,
                    owned:owned,
                    missing:completed ? 0 : Math.max(required - owned, 0),
                    status:status
                });
            }
            result.push({
                infrastructureName:infrastructureName,
                projectOrder:Number(frozenProject.projectOrder),
                currentLevel:currentLevel,
                maximumLevel:maximumLevel,
                levels:projectedLevels
            });
        }
        return result;
    }

    private static function countDropVariants(sources:Array):Number {
        var count:Number = 0;
        for (var i:Number = 0; i < sources.length; i++) {
            if (sources[i].kind == "stage" || sources[i].kind == "enemy") {
                count += sources[i].variants.length;
            }
        }
        return count;
    }

    private static function categoryOrder():Array {
        return _root.改装分类顺序 instanceof Array
            ? _root.改装分类顺序.slice(0) : [];
    }

    private static function validateCategoryClosure(categories:Array):Boolean {
        if (!(categories instanceof Array) || categories.length < 1
                || categories.length > 1024 || _root.改装清单 == undefined) {
            invalid("invalid_category_registry");
            return false;
        }
        _categoryRank = {};
        for (var i:Number = 0; i < categories.length; i++) {
            var category:String = String(categories[i] || "");
            if (!validIdentity(category, 256)
                    || !validIdentity("recipe:" + category, 256)
                    || _categoryRank[category] != undefined
                    || !(_root.改装清单[category] instanceof Array)) {
                invalid("invalid_category_registry");
                return false;
            }
            _categoryRank[category] = i;
        }
        var count:Number = 0;
        for (var existing:String in _root.改装清单) {
            if (ObjectUtil.isInternalKey(existing)) continue;
            count++;
            if (_categoryRank[existing] == undefined) {
                invalid("invalid_category_registry");
                return false;
            }
        }
        if (count != categories.length) {
            invalid("invalid_category_registry");
            return false;
        }
        return true;
    }

    private static function compareUses(left:Object, right:Object):Number {
        var leftRank:Number = Number(_categoryRank[String(left.category)]);
        var rightRank:Number = Number(_categoryRank[String(right.category)]);
        if (leftRank < rightRank) return -1;
        if (leftRank > rightRank) return 1;
        var leftIndex:Number = Number(left.recipeIndex);
        var rightIndex:Number = Number(right.recipeIndex);
        return leftIndex < rightIndex ? -1 : (leftIndex > rightIndex ? 1 : 0);
    }

    private static function compareSourceRecords(left:Object, right:Object):Number {
        var leftKind:String = normalizedKind(left);
        var rightKind:String = normalizedKind(right);
        var leftRank:Number = kindRank(leftKind);
        var rightRank:Number = kindRank(rightKind);
        if (leftRank != rightRank) return leftRank < rightRank ? -1 : 1;
        if (leftKind == "craft") {
            var lc:Number = Number(_categoryRank[String(left.category)]);
            var rc:Number = Number(_categoryRank[String(right.category)]);
            if (lc != rc) return lc < rc ? -1 : 1;
            return numberCompare(Number(left.recipeIndex), Number(right.recipeIndex));
        }
        if (leftKind == "shop") {
            var shopCompare:Number = stringCompare(String(left.shopId), String(right.shopId));
            return shopCompare != 0 ? shopCompare
                : numberCompare(Number(left.catalogIndex), Number(right.catalogIndex));
        }
        if (leftKind == "kshop") {
            return numberCompare(Number(left.catalogIndex), Number(right.catalogIndex));
        }
        if (leftKind == "quest") {
            var questCompare:Number = stringCompare(String(left.questId), String(right.questId));
            if (questCompare != 0) return questCompare;
            var leftSet:Number = String(left.rewardSet) == "base" ? 0 : 1;
            var rightSet:Number = String(right.rewardSet) == "base" ? 0 : 1;
            if (leftSet != rightSet) return leftSet < rightSet ? -1 : 1;
            return numberCompare(Number(left.authoredIndex), Number(right.authoredIndex));
        }
        if (leftKind == "stage") {
            return stringCompare(String(left.stageName), String(right.stageName));
        }
        return stringCompare(String(left.enemyType), String(right.enemyType));
    }

    private static function normalizedKind(record:Object):String {
        var kind:String = String(record == null ? "" : record.kind || "");
        if (kind != ItemObtainIndex.KIND_DROP) return kind;
        if (String(record.dropType) == ItemObtainIndex.DROP_TYPE_STAGE) return "stage";
        if (String(record.dropType) == ItemObtainIndex.DROP_TYPE_ENEMY) return "enemy";
        return "";
    }

    private static function kindRank(kind:String):Number {
        if (kind == "craft") return 0;
        if (kind == "shop") return 1;
        if (kind == "kshop") return 2;
        if (kind == "quest") return 3;
        if (kind == "stage") return 4;
        if (kind == "enemy") return 5;
        return 99;
    }

    private static function stringCompare(left:String, right:String):Number {
        return left < right ? -1 : (left > right ? 1 : 0);
    }

    private static function numberCompare(left:Number, right:Number):Number {
        return left < right ? -1 : (left > right ? 1 : 0);
    }

    private static function sourceKey(segments:Array):String {
        var result:String = "lp1";
        for (var i:Number = 0; i < segments.length; i++) {
            var segment:String = String(segments[i]);
            // AS2 String.length uses UTF-16 code units, matching the wire contract.
            result += "|" + segment.length + ":" + segment;
        }
        return validIdentity(result, 768) ? result : null;
    }

    private static function ownedQuantity(name:String):Number {
        if (_root.收集品栏 == undefined || _root.收集品栏.材料 == undefined) return 0;
        var value:Number = Number(_root.收集品栏.材料.getValue(name));
        return validNni(value) ? value : Number.NaN;
    }

    private static function presentation(value, fallback:String, max:Number):String {
        var text:String = typeof value == "string" ? String(value) : fallback;
        var trimmed:String = trimIdentityWhitespace(text);
        if (trimmed.length == 0 || trimmed.toLowerCase() == "undefined") text = fallback;
        return validIdentity(text, max) ? text : null;
    }

    private static function visibleLabel(value, fallback:String, max:Number):String {
        return presentation(value, fallback, max);
    }

    private static function asArray(value):Array {
        if (value instanceof Array) return value;
        return value == undefined || value == null ? [] : [value];
    }

    private static function hasOnlyKeys(value:Object, allowed:Object):Boolean {
        if (value == null || typeof value != "object") return false;
        for (var key:String in value) {
            if (typeof value.hasOwnProperty == "function" && !value.hasOwnProperty(key)) continue;
            if (allowed[key] !== true) return false;
        }
        return true;
    }

    private static function owns(value:Object, key:String):Boolean {
        return value != null && typeof value.hasOwnProperty == "function"
            && value.hasOwnProperty(key);
    }

    private static function validIdentity(value:String, max:Number):Boolean {
        if (value == null || value.length < 1 || value.length > max) return false;
        var trimmed:String = trimIdentityWhitespace(value);
        if (trimmed.length < 1 || trimmed.toLowerCase() == "undefined") return false;
        for (var i:Number = 0; i < value.length; i++) {
            var code:Number = value.charCodeAt(i);
            if (code < 32 || (code >= 127 && code <= 159)) return false;
        }
        return true;
    }

    /** Shared non-control Unicode whitespace set; C0/C1 stay validator failures. */
    private static function trimIdentityWhitespace(value:String):String {
        if (value == null || value.length == 0) return "";
        var start:Number = 0;
        var end:Number = value.length;
        while (start < end && isIdentityWhitespace(value.charCodeAt(start))) start++;
        while (end > start && isIdentityWhitespace(value.charCodeAt(end - 1))) end--;
        return value.substring(start, end);
    }

    private static function isIdentityWhitespace(code:Number):Boolean {
        return code == 32 || code == 160 || code == 5760
            || (code >= 8192 && code <= 8202)
            || code == 8232 || code == 8233 || code == 8239
            || code == 8287 || code == 12288;
    }

    private static function validSafeOptional(value:String, max:Number):Boolean {
        if (value == null || value.length > max) return false;
        for (var i:Number = 0; i < value.length; i++) {
            var code:Number = value.charCodeAt(i);
            if (code < 32 || (code >= 127 && code <= 159)) return false;
        }
        return true;
    }

    private static function validSafeMultiline(value:String, max:Number):Boolean {
        if (value == null || value.length > max) return false;
        for (var i:Number = 0; i < value.length; i++) {
            var code:Number = value.charCodeAt(i);
            if ((code < 32 && code != 9 && code != 10 && code != 13)
                    || (code >= 127 && code <= 159)) return false;
        }
        return true;
    }

    private static function validColor(value:String):Boolean {
        if (value == null || value.length != 7 || value.charAt(0) != "#") return false;
        for (var i:Number = 1; i < value.length; i++) {
            var code:Number = value.charCodeAt(i);
            var isDigit:Boolean = code >= 48 && code <= 57;
            var isUpper:Boolean = code >= 65 && code <= 70;
            var isLower:Boolean = code >= 97 && code <= 102;
            if (!isDigit && !isUpper && !isLower) return false;
        }
        return true;
    }

    private static function validNonNegative(value:Number):Boolean {
        return !isNaN(value) && (value - value) == 0 && value >= 0;
    }

    private static function validNni(value:Number):Boolean {
        return validNonNegative(value) && Math.floor(value) == value
            && value <= MAX_SAFE_INTEGER;
    }

    private static function validShopCatalogIndex(value:Number):Boolean {
        return validNni(value) && value <= MAX_SHOP_CATALOG_INDEX;
    }

    private static function validIntegerRange(value:Number, minimum:Number,
                                              maximum:Number):Boolean {
        return validNni(value) && value >= minimum && value <= maximum;
    }

    private static function validPi(value:Number):Boolean {
        return validNni(value) && value > 0;
    }

    private static function validRecipeIndex(value:Number):Boolean {
        return validNni(value) && value <= 999;
    }

    private static function validCollectionCount(value:Number,
            minimum:Number, maximum:Number):Boolean {
        return validNni(value) && value >= minimum && value <= maximum;
    }

    private static function validNullableBound(value):Boolean {
        return value == null || validNni(Number(value));
    }

    private static function contains(values:Array, expected:String):Boolean {
        for (var i:Number = 0; i < values.length; i++) {
            if (String(values[i]) == expected) return true;
        }
        return false;
    }

    private static function round6(value:Number):Number {
        return Math.round(value * 1000000) / 1000000;
    }

    private static function cloneValue(value, depth:Number) {
        if (value == null || typeof value != "object") return value;
        if (depth > 16) return null;
        if (value instanceof Array) {
            var arrayResult:Array = [];
            for (var i:Number = 0; i < value.length; i++) {
                arrayResult.push(cloneValue(value[i], depth + 1));
            }
            return arrayResult;
        }
        var objectResult:Object = {};
        for (var key:String in value) {
            if (typeof value.hasOwnProperty == "function" && !value.hasOwnProperty(key)) continue;
            objectResult[key] = cloneValue(value[key], depth + 1);
        }
        return objectResult;
    }

    private static function invalid(errorCode:String) {
        _buildError = errorCode;
        return null;
    }

    private static function fail(errorCode:String):Object {
        return {success:false, error:errorCode};
    }
}
