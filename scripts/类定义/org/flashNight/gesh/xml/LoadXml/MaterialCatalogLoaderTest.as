import org.flashNight.gesh.xml.LoadXml.MaterialCatalogLoader;
import org.flashNight.gesh.xml.LoadXml.MaterialDictionaryLoader;

/**
 * material_catalog.xml 真文件异步 loader gate。
 *
 * runActualFiles() 同时调用两个 singleton loader 的 reload()。只有
 * 实际 XML 都完成且全部断言通过时才输出 Complete；任一失败
 * 都输出显式 [TEST_FAIL] + Failed 终态，永不输出 Complete。
 */
class org.flashNight.gesh.xml.LoadXml.MaterialCatalogLoaderTest {
    private static var EXPECTED_CATALOG_COUNT:Number = 224;
    private static var EXPECTED_LEGACY_COUNT:Number = 58;
    private static var EXPECTED_NON_LEGACY_COUNT:Number = 166;
    private static var EXPECTED_DIRECT_PURPOSE_COUNT:Number = 2;
    private static var EXPECTED_EQUIPMENT_MOD_COUNT:Number = 105;
    private static var EXPECTED_GENERAL_COUNT:Number = 74;
    private static var EXPECTED_FOOD_COUNT:Number = 45;
    private static var EXPECTED_AUTHORED_PURPOSE_REFS:Number = 27;
    private static var EXPECTED_TUNING_PURPOSE_REFS:Number = 6;
    private static var EXPECTED_INFRASTRUCTURE_PURPOSE_REFS:Number = 21;
    private static var TIMEOUT_MS:Number = 30000;

    private static var _runId:String = "";
    private static var _started:Boolean = false;
    private static var _terminal:Boolean = false;
    private static var _catalogLoaded:Boolean = false;
    private static var _legacyLoaded:Boolean = false;
    private static var _catalogData:Object = null;
    private static var _legacyData:Object = null;
    private static var _startedAt:Number = 0;
    private static var _timerClip:MovieClip = null;

    /** 由 tracked TestLoader template 唯一调用。 */
    public static function runActualFiles(runId:String):Void {
        if (_started) {
            fail("duplicate runActualFiles invocation");
            return;
        }
        _started = true;
        _terminal = false;
        _runId = String(runId);
        _catalogLoaded = false;
        _legacyLoaded = false;
        _catalogData = null;
        _legacyData = null;
        _startedAt = getTimer();

        if (_runId.length != 32) {
            fail("runId must be the 32-character runner nonce");
            return;
        }

        installTimeoutClock();
        MaterialCatalogLoader.getInstance().reload(
            function(data:Object):Void {
                MaterialCatalogLoaderTest.onCatalogLoaded(data);
            },
            function():Void {
                MaterialCatalogLoaderTest.fail("material_catalog.xml reload error");
            }
        );
        if (_terminal) return;

        MaterialDictionaryLoader.getInstance().reload(
            function(data:Object):Void {
                MaterialCatalogLoaderTest.onLegacyLoaded(data);
            },
            function():Void {
                MaterialCatalogLoaderTest.fail("material_dictionary.xml reload error");
            }
        );
    }

    /** loader 异步回调入口；公开仅为 AVM1 closure 稳定解析。 */
    public static function onCatalogLoaded(data:Object):Void {
        if (_terminal) return;
        if (_catalogLoaded) {
            fail("material catalog callback fired more than once");
            return;
        }
        _catalogLoaded = true;
        _catalogData = data;
        finishWhenJoined();
    }

    /** loader 异步回调入口；公开仅为 AVM1 closure 稳定解析。 */
    public static function onLegacyLoaded(data:Object):Void {
        if (_terminal) return;
        if (_legacyLoaded) {
            fail("legacy dictionary callback fired more than once");
            return;
        }
        _legacyLoaded = true;
        _legacyData = data;
        finishWhenJoined();
    }

    /** 帧计时器回调，防止 loader 丢回调时只留下模糊超时。 */
    public static function onTimeoutTick():Void {
        if (_terminal) return;
        if (getTimer() - _startedAt > TIMEOUT_MS) {
            fail("async reload timeout; catalog=" + _catalogLoaded
                + ", legacy=" + _legacyLoaded);
        }
    }

    /** 失败终态：显式 trace，不发 Complete marker。 */
    public static function fail(reason:String):Void {
        if (_terminal) return;
        _terminal = true;
        removeTimeoutClock();
        trace("[TEST_FAIL] MaterialCatalogLoaderTest runId=" + _runId
            + " reason=" + reason);
        trace("FocusedTestRunId material-catalog-loader Failed: " + _runId);
    }

    private static function installTimeoutClock():Void {
        var depth:Number = _root.getNextHighestDepth();
        _timerClip = _root.createEmptyMovieClip(
            "__materialCatalogLoaderTestClock", depth);
        _timerClip.onEnterFrame = function():Void {
            MaterialCatalogLoaderTest.onTimeoutTick();
        };
    }

    private static function removeTimeoutClock():Void {
        if (_timerClip == null) return;
        _timerClip.onEnterFrame = null;
        _timerClip.removeMovieClip();
        _timerClip = null;
    }

    private static function finishWhenJoined():Void {
        if (_terminal || !_catalogLoaded || !_legacyLoaded) return;
        try {
            validateJoinedData();
        } catch (e) {
            fail("unexpected assertion exception: " + String(e));
        }
    }

    private static function validateJoinedData():Void {
        if (!expect(_catalogData != null && typeof _catalogData == "object",
                "catalog callback payload must be an object")) return;
        if (!expect(_legacyData != null && typeof _legacyData == "object",
                "legacy callback payload must be an object")) return;
        if (!expect(_catalogData.schemaVersion === 1,
                "catalog schemaVersion must be exact Number 1")) return;
        if (!expect(_catalogData.Material instanceof Array,
                "catalog Material must be an Array after real XML parse")) return;
        if (!expect(_legacyData.Material instanceof Array,
                "legacy Material must be an Array after real XML parse")) return;

        var materials:Array = _catalogData.Material;
        var legacyMaterials:Array = _legacyData.Material;
        var directPurposes:Array = asArray(_catalogData.DirectPurpose);
        if (!expect(materials.length == EXPECTED_CATALOG_COUNT,
                "catalog Material count expected 224, actual " + materials.length)) return;
        if (!expect(legacyMaterials.length == EXPECTED_LEGACY_COUNT,
                "legacy Material count expected 58, actual " + legacyMaterials.length)) return;
        if (!expect(materials.length - legacyMaterials.length
                    == EXPECTED_NON_LEGACY_COUNT,
                "non-legacy omission count expected 166, actual "
                + (materials.length - legacyMaterials.length))) return;
        if (!expect(directPurposes.length == EXPECTED_DIRECT_PURPOSE_COUNT,
                "DirectPurpose registry count expected 2, actual "
                + directPurposes.length)) return;

        var purpose:Object = directPurposes[0];
        if (!expect(purpose != null && typeof purpose == "object"
                && hasOnlyKeys(purpose,
                    {id:true, label:true, order:true, consumerEvidence:true})
                && purpose.id === "system:equipment_tuning"
                && purpose.label === "装备改装"
                && purpose.order === 0
                && purpose.consumerEvidence === "EquipmentTuningService",
                "DirectPurpose[0] registry row is not the exact authored contract")) return;
        purpose = directPurposes[1];
        if (!expect(purpose != null && typeof purpose == "object"
                && hasOnlyKeys(purpose,
                    {id:true, label:true, order:true, consumerEvidence:true})
                && purpose.id === "system:infrastructure_upgrade"
                && purpose.label === "基建升级"
                && purpose.order === 1
                && purpose.consumerEvidence === "InfrastructureUpgradeUI",
                "DirectPurpose[1] registry row is not the exact authored contract")) return;

        if (!expectAnchor(materials, 0, "军用帆布", "equipment_mod", true)) return;
        if (!expectAnchor(materials, 57, "毒素样本", "equipment_mod", true)) return;
        if (!expectAnchor(materials, 58, "神铁碎片", "general", false)) return;
        if (!expectAnchor(materials, 178, "等离子射线弹-强化", "equipment_mod", false)) return;
        if (!expectAnchor(materials, 179, "食用油", "food", false)) return;
        if (!expectAnchor(materials, 223, "蚝油", "food", false)) return;

        var seenNames:Object = {};
        seenNames.__proto__ = null;
        var equipmentModCount:Number = 0;
        var generalCount:Number = 0;
        var foodCount:Number = 0;
        var authoredPurposeRefs:Number = 0;
        var tuningPurposeRefs:Number = 0;
        var infrastructurePurposeRefs:Number = 0;
        var i:Number = 0;
        while (i < materials.length) {
            var row:Object = materials[i];
            if (!expect(row != null && typeof row == "object"
                    && hasOnlyKeys(row, {Name:true, typeId:true,
                        legacyVisible:true, legacyInformation:true,
                        authoredDirectPurposeId:true}),
                    "Material[" + i + "] has an invalid object/key shape")) return;

            var name:String = row.Name;
            if (!expect(typeof row.Name == "string" && name.length > 0,
                    "Material[" + i + "] Name must be a non-empty String")) return;
            if (!expect(seenNames[name] !== true,
                    "duplicate material Name at index " + i + ": " + name)) return;
            seenNames[name] = true;

            if (!expect(typeof row.typeId == "string"
                    && (row.typeId == "equipment_mod" || row.typeId == "general"
                        || row.typeId == "food"),
                    "Material[" + i + "] has invalid typeId: " + row.typeId)) return;
            if (row.typeId == "equipment_mod") equipmentModCount++;
            else if (row.typeId == "general") generalCount++;
            else foodCount++;

            if (!expect(typeof row.legacyVisible == "boolean",
                    "Material[" + i + "] legacyVisible must be Boolean")) return;
            var shouldBeLegacy:Boolean = i < EXPECTED_LEGACY_COUNT;
            if (!expect(row.legacyVisible === shouldBeLegacy,
                    "Material[" + i + "] legacyVisible breaks the 58-row prefix")) return;
            if (shouldBeLegacy) {
                if (!expect(typeof row.legacyInformation == "string"
                        && row.legacyInformation.length > 0,
                        "Material[" + i + "] requires legacyInformation")) return;
            } else if (!expect(row.legacyInformation === undefined,
                    "Material[" + i + "] must omit legacyInformation")) return;

            if (row.authoredDirectPurposeId !== undefined) {
                var purposeIds:Array = asArray(row.authoredDirectPurposeId);
                if (!expect(purposeIds.length > 0,
                        "Material[" + i + "] authoredDirectPurposeId is empty")) return;
                var p:Number = 0;
                while (p < purposeIds.length) {
                    if (purposeIds[p] === "system:equipment_tuning") {
                        tuningPurposeRefs++;
                    } else if (purposeIds[p] === "system:infrastructure_upgrade") {
                        infrastructurePurposeRefs++;
                    } else if (!expect(false,
                            "Material[" + i + "] references an unknown direct purpose")) return;
                    authoredPurposeRefs++;
                    p++;
                }
            }
            i++;
        }

        if (!expect(equipmentModCount == EXPECTED_EQUIPMENT_MOD_COUNT
                && generalCount == EXPECTED_GENERAL_COUNT
                && foodCount == EXPECTED_FOOD_COUNT,
                "type counts expected equipment_mod/general/food=105/74/45, actual "
                + equipmentModCount + "/" + generalCount + "/" + foodCount)) return;
        if (!expect(authoredPurposeRefs == EXPECTED_AUTHORED_PURPOSE_REFS,
                "authored direct-purpose refs expected 27, actual "
                + authoredPurposeRefs)) return;
        if (!expect(tuningPurposeRefs == EXPECTED_TUNING_PURPOSE_REFS
                    && infrastructurePurposeRefs
                        == EXPECTED_INFRASTRUCTURE_PURPOSE_REFS,
                "authored purpose refs expected tuning/infrastructure=6/21, actual "
                + tuningPurposeRefs + "/" + infrastructurePurposeRefs)) return;

        i = 0;
        while (i < legacyMaterials.length) {
            var legacyRow:Object = legacyMaterials[i];
            if (!expect(legacyRow != null && typeof legacyRow == "object"
                    && hasOnlyKeys(legacyRow, {Name:true, Information:true})
                    && typeof legacyRow.Name == "string"
                    && typeof legacyRow.Information == "string",
                    "legacy Material[" + i + "] has an invalid shape")) return;
            if (!expect(materials[i].Name === legacyRow.Name,
                    "legacy physical order mismatch at index " + i
                    + ": catalog=" + materials[i].Name
                    + ", legacy=" + legacyRow.Name)) return;
            if (!expect(materials[i].legacyInformation === legacyRow.Information,
                    "legacy Information projection mismatch at index " + i
                    + ": " + legacyRow.Name)) return;
            i++;
        }

        if (!expect(MaterialCatalogLoader.getInstance().getMaterialCatalogData()
                    === _catalogData,
                "catalog loader cache identity differs from callback payload")) return;
        if (!expect(MaterialDictionaryLoader.getInstance().getMaterialDictionaryData()
                    === _legacyData,
                "legacy loader cache identity differs from callback payload")) return;

        _terminal = true;
        removeTimeoutClock();
        trace("MaterialCatalogLoaderTest PASS: catalog=224, legacy=58, "
            + "nonLegacy=166, directPurposes=2, directPurposeOrder=0/1, "
            + "authoredPurposeRefs=6/21, types=105/74/45, legacyPrefix=58/58");
        trace("FocusedTestRunId material-catalog-loader Complete: " + _runId);
    }

    private static function expectAnchor(materials:Array, index:Number,
            name:String, typeId:String, legacyVisible:Boolean):Boolean {
        var row:Object = materials[index];
        return expect(row != null && row.Name === name && row.typeId === typeId
                && row.legacyVisible === legacyVisible,
            "archive anchor mismatch at index " + index + ": expected "
            + name + "/" + typeId + "/" + legacyVisible);
    }

    private static function expect(condition:Boolean, reason:String):Boolean {
        if (condition) return true;
        fail(reason);
        return false;
    }

    private static function asArray(value):Array {
        if (value instanceof Array) return value;
        if (value !== undefined && value !== null) return [value];
        return [];
    }

    private static function hasOnlyKeys(value:Object, allowed:Object):Boolean {
        for (var key:String in value) {
            if (allowed[key] !== true) return false;
        }
        return true;
    }
}
