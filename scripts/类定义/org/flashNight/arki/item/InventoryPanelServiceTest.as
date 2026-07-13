import org.flashNight.arki.item.InventoryPanelService;
import org.flashNight.arki.item.ItemUtil;
import org.flashNight.arki.item.itemCollection.ArrayInventory;
import org.flashNight.arki.item.BaseItem;
import org.flashNight.neur.Event.LifecycleEventDispatcher;

/** Gate A2/A3：inventory-domain lease、原子事务、窗口化与整容器整理回归。 */
class org.flashNight.arki.item.InventoryPanelServiceTest {
    private static var _passed:Number = 0;
    private static var _failed:Number = 0;

    public static function runAllTests():Void {
        _passed = 0;
        _failed = 0;
        trace("=== InventoryPanelServiceTest start ===");

        testItemSetMetadataHydration();
        testWorkbenchPanelRequest();
        testRangeSnapshot();
        testStableReadLeaseAndMutationVersion();
        testFilteredSnapshot();
        testArrayInventoryMutationRevision();
        testFacetCacheInvalidation();
        testPresentationProjection();
        testTooltipLeaseAndInstance();
        testSourceAndTargetStale();
        testMergeCountStale();
        testDomainReject();
        testBattleboxAccessPolicy();
        testBattleboxTransfers();
        testAutoTransferAuthorityQueueAndFailure();
        testMoveMergeSwapAndReverse();
        testSameContainerTransfersAndRollback();
        testEventReentrancy();
        testCommitFailureRollback();
        testDiscardProjectionAndSuccess();
        testSortValidationMergeEpochAndLease();
        testBackpackAuthoritySort();
        testBattleboxAccessiblePrefixSort();
        testSortRejectsLossyPlan();
        testSortCommitFailureRollback();
        testSortEventReentrancy();
        testWindowPerformanceMatrix();
        testFullWarehouseSortPerformance();

        trace("InventoryPanelServiceTest Tests Passed: " + _passed);
        trace("InventoryPanelServiceTest Tests Failed: " + _failed);
        trace("=== InventoryPanelServiceTest end ===");
    }

    private static function resetInventories():Void {
        _root.物品栏 = {
            背包: new ArrayInventory(null, 50),
            仓库: new ArrayInventory(null, 1200),
            战备箱: new ArrayInventory(null, 400)
        };
        _root.主线任务进度 = 0;
        _root.task_chains_progress = {挑战: 0};
        _root.基建系统 = {infrastructure: {越野车: false}};
        _root.存档系统 = {dirtyMark: false};
        InventoryPanelService.testOnlyReset();
    }

    private static function item(name:String, value):Object {
        return {name: name, value: value, lastUpdate: 1};
    }

    private static function testItemSetMetadataHydration():Void {
        var fixture:Array = [{name:"中心表注入测试装备", setId:"test_center_set"}];
        fixture.itemSets = [{id:"test_center_set", name:"中心表注入测试套装", order:77}];
        ItemUtil.hydrateItemSetMetadata(fixture);
        assertTrue(fixture[0].setName == "中心表注入测试套装"
                && Number(fixture[0].setOrder) == 77,
            "ItemUtil hydrates setName/setOrder from item_sets metadata");
    }

    private static function testWorkbenchPanelRequest():Void {
        var previousServer:Object = _root.server;
        var captured:String = "";
        var sendCount:Number = 0;
        _root.server = {
            sendSocketMessage: function(message:String):Boolean {
                captured = message;
                sendCount++;
                return true;
            }
        };
        var opened:Boolean = InventoryPanelService.requestOpenWorkbench({
            profile: "warehouse",
            source: "dormitory"
        });
        assertTrue(opened && sendCount == 1, "宿舍仓库入口发送一次 panel_request");
        assertTrue(captured.indexOf('"task":"panel_request"') >= 0
            && captured.indexOf('"panel":"workbench"') >= 0
            && captured.indexOf('"profile":"warehouse"') >= 0
            && captured.indexOf('"source":"dormitory"') >= 0,
            "宿舍仓库入口只发送枚举 profile 与来源");
        var rejected:Boolean = InventoryPanelService.requestOpenWorkbench({profile: "仓库"});
        assertTrue(!rejected && sendCount == 1, "工作台入口拒绝非枚举 profile 且不发送消息");
        _root.server = previousServer;
    }

    private static function snapshot(backpackLimit:Number, warehouseLimit:Number):Object {
        return InventoryPanelService.execute("snapshot", {
            v: 1,
            requests: [
                {containerId: "背包", offset: 0, limit: backpackLimit},
                {containerId: "仓库", offset: 0, limit: warehouseLimit}
            ]
        });
    }

    private static function warehouseSnapshot(offset:Number, limit:Number):Object {
        return InventoryPanelService.execute("snapshot", {
            v: 1,
            requests: [{containerId: "仓库", offset: offset, limit: limit}]
        });
    }

    private static function battleboxSnapshot(offset:Number, limit:Number):Object {
        return InventoryPanelService.execute("snapshot", {
            v: 1,
            requests: [{containerId: "战备箱", offset: offset, limit: limit}]
        });
    }

    private static function filteredSnapshot(containerId:String, offset:Number, limit:Number, filterKey:String):Object {
        return InventoryPanelService.execute("snapshot", {
            v: 1,
            requests: [{containerId: containerId, offset: offset, limit: limit, filterKey: filterKey}]
        });
    }

    private static function structuredSnapshot(containerId:String, offset:Number, limit:Number, filterKey:String, filterSpec:Object):Object {
        return InventoryPanelService.execute("snapshot", {
            v: 1,
            requests: [{containerId: containerId, offset: offset, limit: limit, filterKey: filterKey, filterSpec: filterSpec}]
        });
    }

    private static function facetAt(nodes:Array, id:String):Object {
        for (var i:Number = 0; i < nodes.length; i++) if (String(nodes[i].id) == id) return nodes[i];
        return null;
    }

    private static function refFrom(response:Object, snapshotIndex:Number, slotIndex:Number):Object {
        var container:Object = response.snapshots[snapshotIndex];
        var slot:Object = container.slots[slotIndex];
        return {
            containerId: container.containerId,
            slot: slot.physicalSlot,
            expectedLease: slot.slotLease
        };
    }

    private static function assertTrue(condition:Boolean, message:String):Void {
        if (condition) {
            _passed++;
            trace("PASS: " + message);
        } else {
            _failed++;
            trace("FAIL: " + message);
        }
    }

    private static function installSortTestMetadata(names:Array):Object {
        var state:Object = {
            names: names,
            itemDictWasUndefined: org.flashNight.arki.item.ItemUtil.itemDataDict == undefined,
            equipmentDictWasUndefined: org.flashNight.arki.item.ItemUtil.equipmentDict == undefined,
            previous: {}
        };
        if (state.itemDictWasUndefined) org.flashNight.arki.item.ItemUtil.itemDataDict = {};
        if (state.equipmentDictWasUndefined) org.flashNight.arki.item.ItemUtil.equipmentDict = {};
        for (var i:Number = 0; i < names.length; i++) {
            var name:String = String(names[i]);
            state.previous[name] = org.flashNight.arki.item.ItemUtil.itemDataDict[name];
            org.flashNight.arki.item.ItemUtil.itemDataDict[name] = {
                type: "测试装备", use: "测试", price: i + 1, level: 1, id: 900000 + i
            };
        }
        return state;
    }

    private static function restoreSortTestMetadata(state:Object):Void {
        for (var i:Number = 0; i < state.names.length; i++) {
            var name:String = String(state.names[i]);
            if (state.previous[name] == undefined) delete org.flashNight.arki.item.ItemUtil.itemDataDict[name];
            else org.flashNight.arki.item.ItemUtil.itemDataDict[name] = state.previous[name];
        }
        if (state.itemDictWasUndefined) org.flashNight.arki.item.ItemUtil.itemDataDict = undefined;
        if (state.equipmentDictWasUndefined) org.flashNight.arki.item.ItemUtil.equipmentDict = undefined;
    }

    private static function testRangeSnapshot():Void {
        resetInventories();
        _root.物品栏.背包.add(0, item("药剂", 3));
        var response:Object = snapshot(50, 10);
        assertTrue(response.success && response.snapshots.length == 2, "range snapshot 返回两个容器窗口");
        assertTrue(response.snapshots[0].slots.length == 50 && response.snapshots[1].slots.length == 10,
            "range snapshot 严格按 limit 返回");
        assertTrue(response.snapshots[0].slots[0].occupied && response.snapshots[0].slots[1].occupied == false,
            "占用槽与空槽都获得可校验投影");
        assertTrue(String(response.snapshots[0].slots[1].slotLease).length > 0,
            "空目标槽也由 AS2 铸造 lease");
    }

    private static function testStableReadLeaseAndMutationVersion():Void {
        resetInventories();
        _root.物品栏.背包.add(0, item("稳定租约物品", 3));
        var first:Object = snapshot(10, 10);
        var firstRef:Object = refFrom(first, 0, 0);
        var second:Object = snapshot(10, 10);
        var secondRef:Object = refFrom(second, 0, 0);
        assertTrue(firstRef.expectedLease == secondRef.expectedLease
                && first.snapshots[0].containerVersion == second.snapshots[0].containerVersion,
            "相同容器版本的重复纯读复用槽位 lease");
        assertTrue(InventoryPanelService.validateExternalSlotRef(firstRef, true).success,
            "后续纯读不会使先前响应中的 lease 失效");

        _root.物品栏.背包.add(1, item("容器版本推进", 1));
        var stale:Object = InventoryPanelService.validateExternalSlotRef(firstRef, true);
        assertTrue(!stale.success && stale.error == "stale_state",
            "任一真实容器写入推进版本并拒绝旧 lease");

        resetInventories();
        var equipment:Object = item("原位变化装备", {level:1, mods:[]});
        _root.物品栏.背包.add(0, equipment);
        first = snapshot(10, 10);
        firstRef = refFrom(first, 0, 0);
        equipment.value.mods.push("新插件");
        stale = InventoryPanelService.validateExternalSlotRef(firstRef, false);
        assertTrue(!stale.success && stale.error == "stale_state",
            "同一对象引用的装备原位变化也由指纹拒绝旧 lease");
    }

    private static function testFilteredSnapshot():Void {
        resetInventories();
        var itemDictWasUndefined:Boolean = org.flashNight.arki.item.ItemUtil.itemDataDict == undefined;
        if (itemDictWasUndefined) org.flashNight.arki.item.ItemUtil.itemDataDict = {};
        var previousMaterial:Object = org.flashNight.arki.item.ItemUtil.itemDataDict["筛选材料"];
        var previousWeapon:Object = org.flashNight.arki.item.ItemUtil.itemDataDict["筛选武器"];
        org.flashNight.arki.item.ItemUtil.itemDataDict["筛选材料"] = {type: "收集品", use: "材料", price: 1};
        org.flashNight.arki.item.ItemUtil.itemDataDict["筛选武器"] = {type: "武器", use: "长枪", weapontype: "突击步枪",
            setId:"test_rifle", setName:"测试长枪套装", price: 2};
        for (var slot:Number = 0; slot < 51; slot++) {
            _root.物品栏.仓库.add(slot, new BaseItem("筛选材料", 1, slot + 1));
        }
        _root.物品栏.仓库.add(100, new BaseItem("筛选武器", {level: 1}, 1));

        var secondPage:Object = filteredSnapshot("仓库", 50, 50, "material");
        assertTrue(secondPage.success && secondPage.snapshots[0].filterKey == "material"
                && secondPage.snapshots[0].viewCapacity == 51
                && secondPage.snapshots[0].slots.length == 1
                && secondPage.snapshots[0].slots[0].physicalSlot == 50,
            "全容器分类筛选按匹配数量分页并保留真实 physicalSlot");
        var weapon:Object = filteredSnapshot("仓库", 0, 50, "weapon");
        assertTrue(weapon.success && weapon.snapshots[0].viewCapacity == 1
                && weapon.snapshots[0].slots[0].physicalSlot == 100,
            "分类筛选跨越未加载物理页查找匹配物品");
        var structured:Object = structuredSnapshot("仓库", 0, 50, "weapon", {
            major:"weapon", use:"长枪", subtype:"突击步枪"
        });
        var weaponFacet:Object = facetAt(structured.snapshots[0].filterFacets, "weapon");
        var longGunFacet:Object = weaponFacet == null ? null : facetAt(weaponFacet.children, "长枪");
        var rifleFacet:Object = longGunFacet == null ? null : facetAt(longGunFacet.children, "突击步枪");
        assertTrue(structured.success && structured.snapshots[0].viewCapacity == 1
                && structured.snapshots[0].filterSpec.subtype == "突击步枪"
                && structured.snapshots[0].filterItemCount == 52
                && rifleFacet != null && rifleFacet.count == 1,
            "结构化筛选由权威层匹配用途/子类并返回全容器 facet 数量");
        var setFiltered:Object = structuredSnapshot("仓库", 0, 50, "all", {branch:"set", setId:"test_rifle"});
        var setFacet:Object = facetAt(setFiltered.snapshots[0].setFacets, "test_rifle");
        assertTrue(setFiltered.success && setFiltered.snapshots[0].viewCapacity == 1
                && setFiltered.snapshots[0].slots[0].physicalSlot == 100
                && setFiltered.snapshots[0].filterSpec.setId == "test_rifle"
                && setFiltered.snapshots[0].setFilterItemCount == 1
                && setFacet != null && setFacet.label == "测试长枪套装" && setFacet.count == 1,
            "套装筛选跨物理页由权威层匹配并返回套装 facet");
        var allSets:Object = structuredSnapshot("仓库", 0, 50, "all", {branch:"set"});
        assertTrue(allSets.success && allSets.snapshots[0].viewCapacity == 1,
            "套装分支根节只显示已显式标注的物品");
        var invalidSpec:Object = structuredSnapshot("仓库", 0, 50, "weapon", {
            major:"weapon", subtype:"突击步枪"
        });
        assertTrue(!invalidSpec.success && invalidSpec.error == "unsupported_filter",
            "结构化筛选拒绝缺少用途的武器子类路径");
        var mismatchedSpec:Object = structuredSnapshot("仓库", 0, 50, "all", {major:"weapon"});
        assertTrue(!mismatchedSpec.success && mismatchedSpec.error == "unsupported_filter",
            "结构化筛选拒绝与 legacy filterKey 矛盾的路径");
        var clamped:Object = filteredSnapshot("仓库", 50, 50, "weapon");
        assertTrue(clamped.success && clamped.snapshots[0].offset == 0
                && clamped.snapshots[0].slots[0].physicalSlot == 100,
            "筛选结果缩减后把过期页码收敛到合法末页");
        var invalid:Object = filteredSnapshot("仓库", 0, 50, "unknown");
        assertTrue(!invalid.success && invalid.error == "unsupported_filter",
            "未知分类筛选在 AS2 权威层严格拒绝");

        if (previousMaterial == undefined) delete org.flashNight.arki.item.ItemUtil.itemDataDict["筛选材料"];
        else org.flashNight.arki.item.ItemUtil.itemDataDict["筛选材料"] = previousMaterial;
        if (previousWeapon == undefined) delete org.flashNight.arki.item.ItemUtil.itemDataDict["筛选武器"];
        else org.flashNight.arki.item.ItemUtil.itemDataDict["筛选武器"] = previousWeapon;
        if (itemDictWasUndefined) org.flashNight.arki.item.ItemUtil.itemDataDict = undefined;
    }

    private static function testArrayInventoryMutationRevision():Void {
        var inventory:ArrayInventory = new ArrayInventory(null, 8);
        var holder:MovieClip = _root.createEmptyMovieClip("__inventoryRevisionTest", _root.getNextHighestDepth());
        var dispatcher:LifecycleEventDispatcher = new LifecycleEventDispatcher(holder);
        var addEventVersion:Number = -1;
        var valueEventVersion:Number = -1;
        var removeEventVersion:Number = -1;
        inventory.setDispatcher(dispatcher);
        dispatcher.subscribe("ItemAdded", function():Void {
            addEventVersion = inventory.getMutationRevision();
        });
        dispatcher.subscribe("ItemValueChanged", function():Void {
            valueEventVersion = inventory.getMutationRevision();
        });
        dispatcher.subscribe("ItemRemoved", function():Void {
            removeEventVersion = inventory.getMutationRevision();
        });
        var v0:Number = inventory.getMutationRevision();
        var added:Boolean = inventory.add(0, item("版本堆叠", 2));
        var v1:Number = inventory.getMutationRevision();
        inventory.addValue("0", 1);
        var v2:Number = inventory.getMutationRevision();
        inventory.addValue("0", -3);
        var v3:Number = inventory.getMutationRevision();
        var zeroRemoveEventVersion:Number = removeEventVersion;
        var readded:Boolean = inventory.add(0, item("版本重建", 1));
        var v4:Number = inventory.getMutationRevision();
        var wrote:Boolean = inventory.transactionWrite(1, item("事务单槽", 1));
        var v5:Number = inventory.getMutationRevision();
        var replacedAll:Boolean = inventory.transactionReplaceAll([
            item("整表一", 1), item("整表二", 2)
        ]);
        var v6:Number = inventory.getMutationRevision();
        var replacedPrefix:Boolean = inventory.transactionReplacePrefix([
            item("前缀一", 1)
        ], 4);
        var v7:Number = inventory.getMutationRevision();
        inventory.remove(0);
        var v8:Number = inventory.getMutationRevision();
        inventory.setItems({});
        var v9:Number = inventory.getMutationRevision();
        var failed:Boolean = inventory.add(99, item("越界写入", 1));
        var v10:Number = inventory.getMutationRevision();

        assertTrue(added && readded && wrote && replacedAll && replacedPrefix && !failed
                && v1 > v0 && v2 > v1 && v3 > v2 && v4 > v3 && v5 > v4
                && v6 > v5 && v7 > v6 && v8 > v7 && v9 > v8 && v10 == v9
                && addEventVersion == v4 && valueEventVersion == v2
                && zeroRemoveEventVersion == v3,
            "ArrayInventory 全部成功写入口在同步事件前推进单调版本，失败写入保持版本不变");
        inventory.setDispatcher(null);
        holder.removeMovieClip();
    }

    private static function testFacetCacheInvalidation():Void {
        resetInventories();
        var itemDictWasUndefined:Boolean = org.flashNight.arki.item.ItemUtil.itemDataDict == undefined;
        if (itemDictWasUndefined) org.flashNight.arki.item.ItemUtil.itemDataDict = {};
        var name:String = "Facet缓存移动武器";
        var previous:Object = org.flashNight.arki.item.ItemUtil.itemDataDict[name];
        org.flashNight.arki.item.ItemUtil.itemDataDict[name] = {
            type:"武器", use:"长枪", weapontype:"突击步枪", price:1
        };
        _root.物品栏.背包.add(0, new BaseItem(name, {level:1}, 1));

        // 首次 snapshot 同时建立背包与仓库 facet 缓存，再走正常跨容器写路径。
        var before:Object = snapshot(50, 50);
        var moved:Object = InventoryPanelService.execute("move", {
            v:1,
            source:refFrom(before, 0, 0),
            target:refFrom(before, 1, 0)
        });
        var backpackSnapshot:Object = moved.success ? moved.snapshots[0] : null;
        var warehouseAfterMove:Object = moved.success ? moved.snapshots[1] : null;
        var warehouseWeapon:Object = warehouseAfterMove == null
            ? null : facetAt(warehouseAfterMove.filterFacets, "weapon");
        assertTrue(moved.success
                && backpackSnapshot.filterItemCount == 0
                && facetAt(backpackSnapshot.filterFacets, "weapon") == null
                && warehouseAfterMove.filterItemCount == 1
                && warehouseWeapon != null && warehouseWeapon.count == 1,
            "跨容器写入后 facet 缓存立即反映来源移除与目标新增");

        // 普通游戏逻辑可直接走 ArrayInventory.add/remove，不会调用 inventory-domain 失效入口。
        var versionBeforeRemove:Number = _root.物品栏.仓库.getMutationRevision();
        _root.物品栏.仓库.remove(0);
        var afterExternalRemove:Object = warehouseSnapshot(0, 50);
        assertTrue(afterExternalRemove.success
                && _root.物品栏.仓库.getMutationRevision() > versionBeforeRemove
                && afterExternalRemove.snapshots[0].filterItemCount == 0
                && facetAt(afterExternalRemove.snapshots[0].filterFacets, "weapon") == null,
            "外部容器写入通过单调版本自动击穿 facet 缓存");

        if (previous == undefined) delete org.flashNight.arki.item.ItemUtil.itemDataDict[name];
        else org.flashNight.arki.item.ItemUtil.itemDataDict[name] = previous;
        if (itemDictWasUndefined) org.flashNight.arki.item.ItemUtil.itemDataDict = undefined;
    }

    private static function testTooltipLeaseAndInstance():Void {
        resetInventories();
        var name:String = "GateA3库存注释";
        var itemDictWasUndefined:Boolean = org.flashNight.arki.item.ItemUtil.itemDataDict == undefined;
        if (itemDictWasUndefined) org.flashNight.arki.item.ItemUtil.itemDataDict = {};
        var previousMeta:Object = org.flashNight.arki.item.ItemUtil.itemDataDict[name];
        org.flashNight.arki.item.ItemUtil.itemDataDict[name] = {
            name: name, displayname: name, type: "收集品", use: "材料", price: 1,
            description: "<FONT COLOR=\"#FF00FF\">库存实例注释测试</FONT>"
        };
        var owned:BaseItem = new BaseItem(name, 3, 1);
        _root.物品栏.背包.add(0, owned);
        var response:Object = snapshot(10, 10);
        var source:Object = refFrom(response, 0, 0);
        var tooltip:Object = InventoryPanelService.execute("tooltip", {v: 1, source: source});
        assertTrue(tooltip.success && tooltip.itemName == name
            && tooltip.introHTML != undefined && tooltip.descHTML != undefined
            && tooltip.descHTML.indexOf("&quot;") < 0
            && tooltip.descHTML.indexOf("COLOR='#FF00FF'") >= 0,
            "tooltip 按 lease 读取真实库存实例并返回 Web 可解析的富文本");

        _root.物品栏.背包.remove(0);
        _root.物品栏.背包.add(0, new BaseItem(name, 1, 2));
        var stale:Object = InventoryPanelService.execute("tooltip", {v: 1, source: source});
        assertTrue(!stale.success && stale.error == "stale_state",
            "tooltip 不接受已替换 occupant 的旧 lease");

        if (previousMeta == undefined) delete org.flashNight.arki.item.ItemUtil.itemDataDict[name];
        else org.flashNight.arki.item.ItemUtil.itemDataDict[name] = previousMeta;
        if (itemDictWasUndefined) org.flashNight.arki.item.ItemUtil.itemDataDict = undefined;
    }

    private static function testPresentationProjection():Void {
        resetInventories();
        var name:String = "GateA3槽位展示装备";
        var itemDictWasUndefined:Boolean = org.flashNight.arki.item.ItemUtil.itemDataDict == undefined;
        if (itemDictWasUndefined) org.flashNight.arki.item.ItemUtil.itemDataDict = {};
        var previousMeta:Object = org.flashNight.arki.item.ItemUtil.itemDataDict[name];
        var previousModDict:Object = org.flashNight.arki.item.EquipmentUtil.modDict;
        org.flashNight.arki.item.ItemUtil.itemDataDict[name] = {
            name: name, displayname: "GateA3展示名称", type: "武器", use: "手枪", price: 1,
            data: {level: 1, modslot: 3}, data_2: {level: 2}
        };
        org.flashNight.arki.item.EquipmentUtil.modDict = {
            插件A: {
                uiGrade: "medium", uiGradeLabel: "中等", uiGradeColor: "#996600",
                uiRole: "precision", uiRoleLabel: "精准与操控", uiSymbol: "triangle-outline"
            },
            插件B: {
                uiGrade: "special", uiGradeLabel: "特殊", uiGradeColor: "#FFFF00",
                uiRole: "mechanism", uiRoleLabel: "特殊机制", uiSymbol: "star-solid"
            }
        };
        var equipment:Object = {
            name: name,
            value: {level: org.flashNight.arki.item.EquipmentUtil.getMaxLevel(), tier: "二阶", mods: ["插件A", "插件B"]},
            lastUpdate: 1,
            getData: function():Object {
                return {name: name, displayname: "GateA3展示名称", type: "武器", use: "手枪", icon: name, data: {modslot: 3}};
            }
        };
        _root.物品栏.背包.add(0, equipment);
        _root.物品栏.背包.add(1, item("大堆叠材料", 12345));
        var response:Object = snapshot(10, 10);
        var equipmentProjection:Object = response.snapshots[0].slots[0].item;
        var stackProjection:Object = response.snapshots[0].slots[1].item;
        assertTrue(equipmentProjection.isMaxEnhancement
            && equipmentProjection.maxEnhancementLevel == org.flashNight.arki.item.EquipmentUtil.getMaxLevel()
            && equipmentProjection.tierSlotAvailable && equipmentProjection.tierSlotUsed
            && equipmentProjection.modSlotCapacity == 3 && equipmentProjection.modSlotUsed == 2
            && equipmentProjection.modSlots.length == 2
            && equipmentProjection.name == name && equipmentProjection.displayName == "GateA3展示名称"
            && equipmentProjection.modSlots[0].grade == "medium"
            && equipmentProjection.modSlots[0].symbol == "triangle-outline"
            && equipmentProjection.modSlots[1].gradeColor == "#FFFF00"
            && equipmentProjection.modSlots[1].symbol == "star-solid",
            "装备投影优先 displayname，并提供动态满级、独立升阶状态与插件档级/角色符号");
        assertTrue(stackProjection.itemKind == "stack" && stackProjection.quantity == 12345
            && !stackProjection.isMaxEnhancement && stackProjection.modSlotCapacity == 0,
            "非装备投影只保留精确数量且不伪造装备槽状态");

        if (previousMeta == undefined) delete org.flashNight.arki.item.ItemUtil.itemDataDict[name];
        else org.flashNight.arki.item.ItemUtil.itemDataDict[name] = previousMeta;
        org.flashNight.arki.item.EquipmentUtil.modDict = previousModDict;
        if (itemDictWasUndefined) org.flashNight.arki.item.ItemUtil.itemDataDict = undefined;
    }

    private static function testSourceAndTargetStale():Void {
        resetInventories();
        _root.物品栏.背包.add(0, item("药剂", 3));
        var response:Object = snapshot(10, 10);
        var source:Object = refFrom(response, 0, 0);
        var target:Object = refFrom(response, 1, 0);
        _root.物品栏.背包.remove(0);
        _root.物品栏.背包.add(0, item("另一物品", 1));
        var staleSource:Object = InventoryPanelService.execute("move", {v: 1, source: source, target: target});
        assertTrue(!staleSource.success && staleSource.error == "stale_state", "source occupant 被替换后拒绝旧 lease");

        resetInventories();
        _root.物品栏.背包.add(0, item("药剂", 3));
        response = snapshot(10, 10);
        source = refFrom(response, 0, 0);
        target = refFrom(response, 1, 0);
        _root.物品栏.仓库.add(0, item("抢占目标", 1));
        var staleTarget:Object = InventoryPanelService.execute("move", {v: 1, source: source, target: target});
        assertTrue(!staleTarget.success && staleTarget.error == "stale_state", "空 target 变 occupied 后拒绝旧 lease");
    }

    private static function testMergeCountStale():Void {
        resetInventories();
        _root.物品栏.背包.add(0, item("药剂", 3));
        _root.物品栏.仓库.add(0, item("药剂", 4));
        var response:Object = snapshot(10, 10);
        var source:Object = refFrom(response, 0, 0);
        var target:Object = refFrom(response, 1, 0);
        _root.物品栏.仓库.addValue("0", 1);
        var result:Object = InventoryPanelService.execute("merge", {v: 1, source: source, target: target});
        assertTrue(!result.success && result.error == "stale_state", "merge 目标数量变化后双端 count lease 拒绝");
    }

    private static function testDomainReject():Void {
        resetInventories();
        var result:Object = InventoryPanelService.execute("snapshot", {
            v: 1,
            requests: [{containerId: "未开放容器", offset: 0, limit: 10}]
        });
        assertTrue(!result.success && result.error == "unsupported_container", "AS2 容器白名单最终拒绝未知领域");
    }

    private static function testBattleboxAccessPolicy():Void {
        resetInventories();
        var result:Object = battleboxSnapshot(0, 40);
        assertTrue(result.success && result.snapshots[0].capacity == 400
                && result.snapshots[0].accessibleCapacity == 0
                && result.snapshots[0].pageSizeHint == 40
                && result.snapshots[0].locked && result.snapshots[0].slots.length == 0,
            "未解锁战备箱保留物理容量但返回零可访问容量与锁定快照");

        _root.主线任务进度 = 14;
        assertTrue(InventoryPanelService.getAccessibleCapacity("战备箱") == 40,
            "主线越过初始门槛后开放战备箱第一页");
        _root.task_chains_progress.挑战 = 3;
        assertTrue(InventoryPanelService.getAccessibleCapacity("战备箱") == 120,
            "挑战进度最多追加两页战备箱容量");
        _root.主线任务进度 = 78;
        assertTrue(InventoryPanelService.getAccessibleCapacity("战备箱") == 200,
            "后期主线追加两页战备箱容量");
        _root.基建系统.infrastructure.越野车 = true;
        assertTrue(InventoryPanelService.getAccessibleCapacity("战备箱") == 240,
            "越野车基建追加最终一页且不暴露存档保留槽位");

        result = battleboxSnapshot(240, 40);
        assertTrue(!result.success && result.error == "slot_locked",
            "range snapshot 拒绝越过剧情可访问容量的窗口");

        _root.主线任务进度 = 14;
        _root.task_chains_progress.挑战 = 0;
        _root.基建系统.infrastructure.越野车 = false;
        result = InventoryPanelService.execute("move", {
            v: 1,
            source: {containerId: "战备箱", slot: 40, expectedLease: "fake"},
            target: {containerId: "背包", slot: 0, expectedLease: "fake"}
        });
        assertTrue(!result.success && result.error == "slot_locked",
            "写操作在 lease 校验前拒绝战备箱未解锁槽位");
    }

    private static function testBattleboxTransfers():Void {
        resetInventories();
        _root.主线任务进度 = 78;
        _root.task_chains_progress.挑战 = 3;
        _root.基建系统.infrastructure.越野车 = true;
        var moving:Object = item("战备物资", 2);
        _root.物品栏.背包.add(0, moving);
        var response:Object = InventoryPanelService.execute("snapshot", {
            v: 1,
            requests: [
                {containerId: "背包", offset: 0, limit: 50},
                {containerId: "战备箱", offset: 0, limit: 40}
            ]
        });
        var result:Object = InventoryPanelService.execute("move", {
            v: 1, source: refFrom(response, 0, 0), target: refFrom(response, 1, 0)
        });
        assertTrue(result.success && _root.物品栏.战备箱.getItem("0") === moving
                && result.snapshots[0].pageSizeHint == 50
                && result.snapshots[1].pageSizeHint == 40
                && result.snapshots[1].slots.length == 40,
            "背包→战备箱 whole-slot move 返回两端各自的权威页大小");

        result = InventoryPanelService.execute("move", {
            v: 1, source: refFrom(result, 1, 0), target: refFrom(result, 0, 1)
        });
        assertTrue(result.success && _root.物品栏.背包.getItem("1") === moving
                && _root.物品栏.战备箱.getItem("0") == null,
            "战备箱→背包反向移动复用同一事务协议");
    }

    private static function testAutoTransferAuthorityQueueAndFailure():Void {
        resetInventories();
        var firstSource:Object = item("快速材料", 3);
        var secondSource:Object = item("快速装备", {level: 2});
        _root.物品栏.背包.add(0, firstSource);
        _root.物品栏.背包.add(1, secondSource);
        _root.物品栏.仓库.add(100, item("快速材料", 4));
        var response:Object = snapshot(10, 10);
        var windows:Array = [
            {containerId: "背包", offset: 0, limit: 10, filterKey: "all"},
            {containerId: "仓库", offset: 0, limit: 10, filterKey: "all"}
        ];
        var result:Object = InventoryPanelService.execute("autoTransfer", {
            v: 1,
            source: refFrom(response, 0, 0),
            targetContainerId: "仓库",
            policy: "mergeThenEmpty",
            windows: windows
        });
        assertTrue(result.success && result.operation == "merge"
                && result.destination.containerId == "仓库" && result.destination.slot == 100
                && _root.物品栏.仓库.getItem("100").value == 7,
            "autoTransfer 跨未加载页优先合并同名堆叠");
        assertTrue(result.snapshots[1].offset == 0 && result.snapshots[1].slots[0].physicalSlot == 0,
            "autoTransfer 按 Web 原窗口重铸 lease 且不跳到真实落位页");

        result = InventoryPanelService.execute("autoTransfer", {
            v: 1,
            source: refFrom(result, 0, 1),
            targetContainerId: "仓库",
            policy: "mergeThenEmpty",
            windows: windows
        });
        assertTrue(result.success && result.operation == "move" && result.destination.slot == 0
                && _root.物品栏.仓库.getItem("0") === secondSource
                && _root.物品栏.仓库.getItem("100").value == 7,
            "连续快速转移使用上一回包新 lease，并只占首个空槽不交换其他物品");

        response = snapshot(10, 10);
        var badPolicy:Object = InventoryPanelService.execute("autoTransfer", {
            v: 1,
            source: refFrom(response, 1, 0),
            targetContainerId: "背包",
            policy: "swapThenEmpty",
            windows: windows
        });
        assertTrue(!badPolicy.success && badPolicy.error == "unsupported_policy",
            "autoTransfer 拒绝可诱发自动交换的未知策略");
        var badPair:Object = InventoryPanelService.execute("autoTransfer", {
            v: 1,
            source: refFrom(response, 1, 0),
            targetContainerId: "仓库",
            policy: "mergeThenEmpty",
            windows: windows
        });
        assertTrue(!badPair.success && badPair.error == "transfer_forbidden",
            "autoTransfer 只允许背包与仓库或战备箱成对传输");

        resetInventories();
        _root.主线任务进度 = 14;
        var blockedSource:Object = item("无法转移", {level: 1});
        _root.物品栏.背包.add(0, blockedSource);
        for (var slot:Number = 0; slot < 40; slot++) {
            _root.物品栏.战备箱.add(slot, item("占位装备" + slot, {level: 1}));
        }
        response = InventoryPanelService.execute("snapshot", {
            v: 1,
            requests: [
                {containerId: "背包", offset: 0, limit: 50},
                {containerId: "战备箱", offset: 0, limit: 40}
            ]
        });
        result = InventoryPanelService.execute("autoTransfer", {
            v: 1,
            source: refFrom(response, 0, 0),
            targetContainerId: "战备箱",
            policy: "mergeThenEmpty",
            windows: [
                {containerId: "背包", offset: 0, limit: 50, filterKey: "all"},
                {containerId: "战备箱", offset: 0, limit: 40, filterKey: "all"}
            ]
        });
        assertTrue(!result.success && result.error == "target_full"
                && _root.物品栏.背包.getItem("0") === blockedSource
                && !_root.存档系统.dirtyMark,
            "autoTransfer 目标已满时来源与 dirty 状态保持不变");

        resetInventories();
        var rollbackSource:Object = item("回滚装备", {level: 3});
        _root.物品栏.背包.add(0, rollbackSource);
        response = snapshot(10, 10);
        InventoryPanelService.testOnlyFailNextCommit("仓库", 0);
        result = InventoryPanelService.execute("autoTransfer", {
            v: 1,
            source: refFrom(response, 0, 0),
            targetContainerId: "仓库",
            policy: "mergeThenEmpty",
            windows: windows
        });
        assertTrue(!result.success && result.error == "commit_failed"
                && _root.物品栏.背包.getItem("0") === rollbackSource
                && _root.物品栏.仓库.getItem("0") == null
                && !_root.存档系统.dirtyMark,
            "autoTransfer 目标提交失败时原子回滚且不发布 dirty");
    }

    private static function testMoveMergeSwapAndReverse():Void {
        resetInventories();
        var moving:Object = item("武器", {level: 2});
        _root.物品栏.背包.add(0, moving);
        var response:Object = snapshot(10, 10);
        var result:Object = InventoryPanelService.execute("move", {
            v: 1, source: refFrom(response, 0, 0), target: refFrom(response, 1, 0)
        });
        assertTrue(result.success && _root.物品栏.仓库.getItem("0") === moving && _root.物品栏.背包.getItem("0") == null,
            "whole-slot move 保持 BaseItem 外壳引用并提交两端");
        assertTrue(_root.存档系统.dirtyMark == true, "成功 move 设置 dirtyMark");

        resetInventories();
        _root.物品栏.背包.add(0, item("药剂", 3));
        var mergeTarget:Object = item("药剂", 4);
        _root.物品栏.仓库.add(0, mergeTarget);
        response = snapshot(10, 10);
        result = InventoryPanelService.execute("merge", {
            v: 1, source: refFrom(response, 0, 0), target: refFrom(response, 1, 0)
        });
        assertTrue(result.success && mergeTarget.value == 7 && _root.物品栏.背包.getItem("0") == null,
            "whole-stack merge 原地更新目标并清源");

        resetInventories();
        var left:Object = item("左物品", {level: 1});
        var right:Object = item("右物品", {level: 1});
        _root.物品栏.背包.add(0, left);
        _root.物品栏.仓库.add(0, right);
        response = snapshot(10, 10);
        result = InventoryPanelService.execute("swap", {
            v: 1, source: refFrom(response, 0, 0), target: refFrom(response, 1, 0)
        });
        assertTrue(result.success && _root.物品栏.背包.getItem("0") === right && _root.物品栏.仓库.getItem("0") === left,
            "whole-slot swap 原子交换两端引用");

        resetInventories();
        var reverseItem:Object = item("反向物品", 2);
        _root.物品栏.仓库.add(0, reverseItem);
        response = snapshot(10, 10);
        result = InventoryPanelService.execute("move", {
            v: 1, source: refFrom(response, 1, 0), target: refFrom(response, 0, 0)
        });
        assertTrue(result.success && result.operation == "move" && _root.物品栏.背包.getItem("0") === reverseItem,
            "仓库→背包反向仍调用同一 move operation");
    }

    private static function testSameContainerTransfersAndRollback():Void {
        resetInventories();
        var moving:Object = item("背包内移动", {level: 2});
        _root.物品栏.背包.add(0, moving);
        var response:Object = snapshot(10, 10);
        var result:Object = InventoryPanelService.execute("move", {
            v: 1, source: refFrom(response, 0, 0), target: refFrom(response, 0, 2)
        });
        assertTrue(result.success && _root.物品栏.背包.getItem("2") === moving
                && _root.物品栏.背包.getItem("0") == null,
            "背包内 whole-slot move 保持引用并移动 physicalSlot");
        assertTrue(result.snapshots.length == 1 && result.snapshots[0].containerId == "背包",
            "同容器同窗口 transfer 只返回一个去重 snapshot");

        resetInventories();
        _root.物品栏.背包.add(0, item("背包药剂", 3));
        var mergeTarget:Object = item("背包药剂", 4);
        _root.物品栏.背包.add(1, mergeTarget);
        response = snapshot(10, 10);
        result = InventoryPanelService.execute("merge", {
            v: 1, source: refFrom(response, 0, 0), target: refFrom(response, 0, 1)
        });
        assertTrue(result.success && mergeTarget.value == 7 && _root.物品栏.背包.getItem("0") == null,
            "背包内同名 stack whole-stack merge 成立");

        resetInventories();
        var warehouseLeft:Object = item("仓库左物品", {level: 1});
        var warehouseRight:Object = item("仓库右物品", {level: 1});
        _root.物品栏.仓库.add(0, warehouseLeft);
        _root.物品栏.仓库.add(1, warehouseRight);
        response = snapshot(10, 10);
        result = InventoryPanelService.execute("swap", {
            v: 1, source: refFrom(response, 1, 0), target: refFrom(response, 1, 1)
        });
        assertTrue(result.success && _root.物品栏.仓库.getItem("0") === warehouseRight
                && _root.物品栏.仓库.getItem("1") === warehouseLeft,
            "仓库内异类 whole-slot swap 原子换位");

        resetInventories();
        var selfStack:Object = item("同槽保护", 5);
        _root.物品栏.背包.add(0, selfStack);
        response = snapshot(10, 10);
        var selfRef:Object = refFrom(response, 0, 0);
        result = InventoryPanelService.execute("merge", {v: 1, source: selfRef, target: selfRef});
        assertTrue(!result.success && result.error == "same_slot" && selfStack.value == 5
                && _root.物品栏.背包.getItem("0") === selfStack,
            "同 physicalSlot 在提交前拒绝，避免自 merge 数据损坏");

        resetInventories();
        var rollbackItem:Object = item("同容器回滚", 2);
        _root.物品栏.背包.add(0, rollbackItem);
        response = snapshot(10, 10);
        InventoryPanelService.testOnlyFailNextCommit("背包", 1);
        result = InventoryPanelService.execute("move", {
            v: 1, source: refFrom(response, 0, 0), target: refFrom(response, 0, 1)
        });
        assertTrue(!result.success && result.error == "commit_failed",
            "同容器第二槽提交失败返回 commit_failed");
        assertTrue(_root.物品栏.背包.getItem("0") === rollbackItem
                && _root.物品栏.背包.getItem("1") == null && _root.存档系统.dirtyMark == false,
            "同容器第二槽失败完整回滚且不标脏");
    }

    private static function testEventReentrancy():Void {
        resetInventories();
        _root.物品栏.背包.add(0, item("药剂", 2));
        var holder:MovieClip = _root.createEmptyMovieClip("__inventoryPanelServiceTest", _root.getNextHighestDepth());
        var dispatcher:LifecycleEventDispatcher = new LifecycleEventDispatcher(holder);
        _root.物品栏.背包.setDispatcher(dispatcher);
        var reentryResult:Object = null;
        dispatcher.subscribe("ItemRemoved", function():Void {
            reentryResult = InventoryPanelService.execute("snapshot", {
                v: 1, requests: [{containerId: "背包", offset: 0, limit: 10}]
            });
        });

        var response:Object = snapshot(10, 10);
        var result:Object = InventoryPanelService.execute("move", {
            v: 1, source: refFrom(response, 0, 0), target: refFrom(response, 1, 0)
        });
        assertTrue(result.success && reentryResult != null && reentryResult.error == "busy",
            "生命周期事件同步重入被事务守卫拒绝");
        _root.物品栏.背包.setDispatcher(null);
        holder.removeMovieClip();
    }

    private static function testCommitFailureRollback():Void {
        resetInventories();
        var sourceItem:Object = item("药剂", 2);
        _root.物品栏.背包.add(0, sourceItem);
        var response:Object = snapshot(10, 10);
        InventoryPanelService.testOnlyFailNextCommit("仓库", 0);
        var result:Object = InventoryPanelService.execute("move", {
            v: 1, source: refFrom(response, 0, 0), target: refFrom(response, 1, 0)
        });
        assertTrue(!result.success && result.error == "commit_failed", "提交段失败返回 commit_failed");
        assertTrue(_root.物品栏.背包.getItem("0") === sourceItem && _root.物品栏.仓库.getItem("0") == null,
            "第二端提交失败后第一端完整回滚，无部分写");
        assertTrue(_root.存档系统.dirtyMark == false, "回滚路径不设置 dirtyMark");
    }

    private static function testDiscardProjectionAndSuccess():Void {
        resetInventories();
        var stack:Object = item("药剂", 2);
        _root.物品栏.背包.add(0, stack);
        var response:Object = snapshot(10, 10);
        var source:Object = refFrom(response, 0, 0);
        stack.value = 3;
        var stale:Object = InventoryPanelService.execute("discard", {v: 1, source: source});
        assertTrue(!stale.success && stale.error == "stale_state", "确认框展示数量变化后 discard 要求重新确认");

        response = snapshot(10, 10);
        source = refFrom(response, 0, 0);
        var result:Object = InventoryPanelService.execute("discard", {v: 1, source: source});
        assertTrue(result.success && _root.物品栏.背包.getItem("0") == null && result.snapshots[0].slots[0].occupied == false,
            "discard 删除整槽、标脏并在同一回包刷新背包");
    }

    private static function testSortValidationMergeEpochAndLease():Void {
        resetInventories();
        var itemDictWasUndefined:Boolean = org.flashNight.arki.item.ItemUtil.itemDataDict == undefined;
        var equipmentDictWasUndefined:Boolean = org.flashNight.arki.item.ItemUtil.equipmentDict == undefined;
        if (itemDictWasUndefined) org.flashNight.arki.item.ItemUtil.itemDataDict = {};
        if (equipmentDictWasUndefined) org.flashNight.arki.item.ItemUtil.equipmentDict = {};
        var previousMeta:Object = org.flashNight.arki.item.ItemUtil.itemDataDict["强化石"];
        var previousAlphaMeta:Object = org.flashNight.arki.item.ItemUtil.itemDataDict["Alpha"];
        var previousZuluMeta:Object = org.flashNight.arki.item.ItemUtil.itemDataDict["Zulu"];
        // 对齐 data/items 正式 schema：材料是 type=收集品 + use=材料。
        // 禁止用不存在的 type=材料 夹具把 ItemSortUtil 的分类错误遮住。
        org.flashNight.arki.item.ItemUtil.itemDataDict["强化石"] = {type: "收集品", use: "材料", price: 1, level: 0, id: 1};
        org.flashNight.arki.item.ItemUtil.itemDataDict["Alpha"] = {type: "测试装备", use: "测试", price: 2, level: 1, id: 2};
        org.flashNight.arki.item.ItemUtil.itemDataDict["Zulu"] = {type: "测试装备", use: "测试", price: 3, level: 1, id: 3};
        _root.物品栏.仓库.add(50, item("强化石", 2));
        _root.物品栏.仓库.add(51, item("强化石", 3));
        _root.物品栏.仓库.add(52, item("Zulu", {level: 1}));
        _root.物品栏.仓库.add(53, item("Alpha", {level: 1}));
        var before:Object = warehouseSnapshot(50, 50);
        var oldLease:Object = refFrom(before, 0, 0);
        var invalid:Object = InventoryPanelService.execute("sortAndMerge", {
            v: 1, container: {containerId: "仓库", offset: 50, limit: 50}, methodName: "unknown"
        });
        assertTrue(!invalid.success && invalid.error == "unsupported_sort_method" && _root.存档系统.dirtyMark == false,
            "未知整理策略严格拒绝且不写入");

        var result:Object = InventoryPanelService.execute("sortAndMerge", {
            v: 1, container: {containerId: "仓库", offset: 50, limit: 50}, methodName: "byName"
        });
        assertTrue(result.success && result.snapshots[0].offset == 50 && result.snapshots[0].containerEpoch == 2,
            "sortAndMerge 保持当前窗口并递增整容器 epoch");
        var mergedFound:Boolean = false;
        var alphaSlot:Number = -1;
        var zuluSlot:Number = -1;
        for (var sortedSlot:Number = 0; sortedSlot < _root.物品栏.仓库.capacity; sortedSlot++) {
            var sortedItem:Object = _root.物品栏.仓库.getItem(String(sortedSlot));
            if (sortedItem == null) continue;
            if (sortedSlot < 8) trace("[InventoryPanelService SORT] slot=" + sortedSlot + " name=" + sortedItem.name + " value=" + sortedItem.value);
            if (sortedItem.name == "强化石" && Number(sortedItem.value) == 5) mergedFound = true;
            if (sortedItem.name == "Alpha") alphaSlot = sortedSlot;
            if (sortedItem.name == "Zulu") zuluSlot = sortedSlot;
        }
        trace("[InventoryPanelService SORT] size=" + _root.物品栏.仓库.size() + " merged=" + mergedFound
            + " alphaSlot=" + alphaSlot + " zuluSlot=" + zuluSlot);
        assertTrue(_root.物品栏.仓库.size() == 3 && mergedFound && alphaSlot >= 0 && zuluSlot > alphaSlot,
            "权威整理按名称重排并合并可堆叠物品");
        assertTrue(_root.存档系统.dirtyMark == true, "成功整理显式 dirtyMark");
        var stale:Object = InventoryPanelService.execute("move", {
            v: 1,
            source: oldLease,
            target: {containerId: "背包", slot: 0, expectedLease: "old"}
        });
        assertTrue(!stale.success && stale.error == "stale_state", "整容器整理后旧仓库 page lease 全部失效");
        if (previousMeta == undefined) delete org.flashNight.arki.item.ItemUtil.itemDataDict["强化石"];
        else org.flashNight.arki.item.ItemUtil.itemDataDict["强化石"] = previousMeta;
        if (previousAlphaMeta == undefined) delete org.flashNight.arki.item.ItemUtil.itemDataDict["Alpha"];
        else org.flashNight.arki.item.ItemUtil.itemDataDict["Alpha"] = previousAlphaMeta;
        if (previousZuluMeta == undefined) delete org.flashNight.arki.item.ItemUtil.itemDataDict["Zulu"];
        else org.flashNight.arki.item.ItemUtil.itemDataDict["Zulu"] = previousZuluMeta;
        if (itemDictWasUndefined) org.flashNight.arki.item.ItemUtil.itemDataDict = undefined;
        if (equipmentDictWasUndefined) org.flashNight.arki.item.ItemUtil.equipmentDict = undefined;
    }

    private static function testBackpackAuthoritySort():Void {
        resetInventories();
        var metadata:Object = installSortTestMetadata(["Alpha", "Zulu"]);
        _root.物品栏.背包.add(2, item("Zulu", {level: 1}));
        _root.物品栏.背包.add(40, item("Alpha", {level: 1}));
        var result:Object = InventoryPanelService.execute("sortAndMerge", {
            v: 1,
            container: {containerId: "背包", offset: 0, limit: 50, filterKey: "all"},
            methodName: "byName"
        });
        assertTrue(result.success && result.sortedCapacity == 50
                && _root.物品栏.背包.getItem("0").name == "Alpha"
                && _root.物品栏.背包.getItem("1").name == "Zulu"
                && result.snapshots[0].containerEpoch == 2,
            "背包复用事务化权威整理并重铸整容器 epoch");
        assertTrue(_root.存档系统.dirtyMark == true,
            "背包权威整理成功后显式标脏");
        restoreSortTestMetadata(metadata);
    }

    private static function testBattleboxAccessiblePrefixSort():Void {
        resetInventories();
        _root.主线任务进度 = 14;
        var metadata:Object = installSortTestMetadata(["Alpha", "Zulu"]);
        _root.物品栏.战备箱.add(3, item("Zulu", {level: 1}));
        _root.物品栏.战备箱.add(35, item("Alpha", {level: 1}));
        var reservedA:Object = item("保留区A", {level: 1});
        var reservedB:Object = item("保留区B", {level: 1});
        _root.物品栏.战备箱.add(80, reservedA);
        _root.物品栏.战备箱.add(399, reservedB);

        var result:Object = InventoryPanelService.execute("sortAndMerge", {
            v: 1,
            container: {containerId: "战备箱", offset: 0, limit: 40, filterKey: "all"},
            methodName: "byName"
        });
        assertTrue(result.success && result.sortedCapacity == 40
                && _root.物品栏.战备箱.getItem("0").name == "Alpha"
                && _root.物品栏.战备箱.getItem("1").name == "Zulu",
            "战备箱权威整理只压缩当前剧情已解锁前缀");
        assertTrue(_root.物品栏.战备箱.getItem("80") === reservedA
                && _root.物品栏.战备箱.getItem("399") === reservedB,
            "战备箱400槽锁定保留区逐槽保持原 key 与对象引用");
        assertTrue(_root.存档系统.dirtyMark == true && result.snapshots[0].containerEpoch == 2,
            "战备箱前缀整理标脏并使可见 lease 失效");
        restoreSortTestMetadata(metadata);
    }

    private static function testSortCommitFailureRollback():Void {
        resetInventories();
        var metadata:Object = installSortTestMetadata(["Alpha", "Zulu"]);
        var first:Object = item("Zulu", {level: 1});
        var second:Object = item("Alpha", {level: 1});
        _root.物品栏.仓库.add(70, first);
        _root.物品栏.仓库.add(71, second);
        InventoryPanelService.testOnlyFailNextCommit("仓库", -1);
        var result:Object = InventoryPanelService.execute("sortAndMerge", {
            v: 1, container: {containerId: "仓库", offset: 50, limit: 50}, methodName: "byName"
        });
        assertTrue(!result.success && result.error == "commit_failed", "整容器提交失败返回 commit_failed");
        assertTrue(_root.物品栏.仓库.getItem("70") === first && _root.物品栏.仓库.getItem("71") === second,
            "整理计划隔离执行，提交失败保持所有 physicalSlot 原状");
        assertTrue(_root.存档系统.dirtyMark == false, "整理回滚路径不标脏");
        restoreSortTestMetadata(metadata);
    }

    private static function testSortRejectsLossyPlan():Void {
        resetInventories();
        var legacy:Object = item("未注册历史物品", 7);
        _root.物品栏.仓库.add(33, legacy);
        var result:Object = InventoryPanelService.execute("sortAndMerge", {
            v: 1, container: {containerId: "仓库", offset: 0, limit: 50}, methodName: "byName"
        });
        assertTrue(!result.success && result.error == "sort_failed"
                && _root.物品栏.仓库.getItem("33") === legacy && _root.存档系统.dirtyMark == false,
            "整理计划若过滤未知历史物品则拒绝提交，不静默丢物");
    }

    private static function testSortEventReentrancy():Void {
        resetInventories();
        var metadata:Object = installSortTestMetadata(["Alpha", "Zulu"]);
        _root.物品栏.仓库.add(0, item("Zulu", {level: 1}));
        _root.物品栏.仓库.add(1, item("Alpha", {level: 1}));
        var holder:MovieClip = _root.createEmptyMovieClip("__inventorySortServiceTest", _root.getNextHighestDepth());
        var dispatcher:LifecycleEventDispatcher = new LifecycleEventDispatcher(holder);
        _root.物品栏.仓库.setDispatcher(dispatcher);
        var reentry:Object = null;
        dispatcher.subscribe("ItemRemoved", function():Void {
            if (reentry == null) reentry = warehouseSnapshot(0, 50);
        });
        var result:Object = InventoryPanelService.execute("sortAndMerge", {
            v: 1, container: {containerId: "仓库", offset: 0, limit: 50}, methodName: "byName"
        });
        assertTrue(result.success && reentry != null && reentry.error == "busy",
            "整理提交后的生命周期事件仍处于事务重入守卫内");
        _root.物品栏.仓库.setDispatcher(null);
        holder.removeMovieClip();
        restoreSortTestMetadata(metadata);
    }

    private static function testWindowPerformanceMatrix():Void {
        var capacities:Array = [50, 400, 1200];
        var ratios:Array = [0, 0.5, 1];
        for (var c:Number = 0; c < capacities.length; c++) {
            for (var r:Number = 0; r < ratios.length; r++) {
                var capacity:Number = capacities[c];
                _root.物品栏 = {
                    背包: new ArrayInventory(null, 50),
                    仓库: new ArrayInventory(null, capacity)
                };
                _root.存档系统 = {dirtyMark: false};
                InventoryPanelService.testOnlyReset();
                var occupied:Number = Math.floor(capacity * Number(ratios[r]));
                for (var slot:Number = 0; slot < occupied; slot++) {
                    _root.物品栏.仓库.add(slot, item("Perf" + slot, 1));
                }
                var started:Number = getTimer();
                var response:Object = null;
                for (var iteration:Number = 0; iteration < 100; iteration++) {
                    response = warehouseSnapshot(0, Math.min(50, capacity));
                }
                var elapsed:Number = getTimer() - started;
                var payloadChars:Number = new LiteJSON().stringify(response).length;
                trace("[InventoryPanelService PERF] capacity=" + capacity + " occupancy=" + occupied
                    + " window=50 iterations=100 elapsedMs=" + elapsed + " payloadChars=" + payloadChars);
                assertTrue(response.success && response.snapshots[0].slots.length == Math.min(50, capacity)
                        && elapsed < 5000 && payloadChars < 100000,
                    "窗口快照性能门 " + capacity + " 槽 / " + Math.round(Number(ratios[r]) * 100) + "% 占用");
            }
        }
    }

    private static function testFullWarehouseSortPerformance():Void {
        resetInventories();
        var itemDictWasUndefined:Boolean = org.flashNight.arki.item.ItemUtil.itemDataDict == undefined;
        var equipmentDictWasUndefined:Boolean = org.flashNight.arki.item.ItemUtil.equipmentDict == undefined;
        if (itemDictWasUndefined) org.flashNight.arki.item.ItemUtil.itemDataDict = {};
        if (equipmentDictWasUndefined) org.flashNight.arki.item.ItemUtil.equipmentDict = {};
        var previousMeta:Object = org.flashNight.arki.item.ItemUtil.itemDataDict["GateA3性能堆叠"];
        org.flashNight.arki.item.ItemUtil.itemDataDict["GateA3性能堆叠"] = {
            type: "收集品", use: "材料", price: 1, level: 0, id: 999999
        };
        for (var slot:Number = 0; slot < 1200; slot++) {
            _root.物品栏.仓库.add(slot, item("GateA3性能堆叠", 1));
        }
        var started:Number = getTimer();
        var result:Object = InventoryPanelService.execute("sortAndMerge", {
            v: 1, container: {containerId: "仓库", offset: 0, limit: 50}, methodName: "byType"
        });
        var elapsed:Number = getTimer() - started;
        trace("[InventoryPanelService PERF] fullWarehouseSort capacity=1200 occupancy=1200 elapsedMs=" + elapsed);
        assertTrue(result.success && _root.物品栏.仓库.size() == 1
                && Number(_root.物品栏.仓库.getItem("0").value) == 1200 && elapsed < 5000,
            "1200/1200 满仓权威整理与合并性能门");
        if (previousMeta == undefined) delete org.flashNight.arki.item.ItemUtil.itemDataDict["GateA3性能堆叠"];
        else org.flashNight.arki.item.ItemUtil.itemDataDict["GateA3性能堆叠"] = previousMeta;
        if (itemDictWasUndefined) org.flashNight.arki.item.ItemUtil.itemDataDict = undefined;
        if (equipmentDictWasUndefined) org.flashNight.arki.item.ItemUtil.equipmentDict = undefined;
    }
}
