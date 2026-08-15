import org.flashNight.gesh.tooltip.test.MockTooltipContainer;
import org.flashNight.gesh.tooltip.test.MockItemFactory;
import org.flashNight.gesh.tooltip.TooltipLayout;
import org.flashNight.gesh.tooltip.TooltipBridge;
import org.flashNight.gesh.tooltip.TooltipConstants;
import org.flashNight.gesh.tooltip.TooltipComposer;
import org.flashNight.gesh.string.StringUtils;
import org.flashNight.arki.item.ItemUtil;
import org.flashNight.arki.item.EquipmentUtil;
import org.flashNight.arki.item.BaseItem;
import org.flashNight.arki.item.equipment.TierSystem;
import org.flashNight.gesh.xml.LoadXml.EquipmentConfigLoader;
import org.flashNight.gesh.xml.LoadXml.ItemDataLoader;
import org.flashNight.gesh.xml.LoadXml.EquipModListLoader;

/**
 * TooltipCorpusDump — 审计 Web 注释布局所需的 AS2 权威物品语料。
 *
 * 主入口 runAllTests(runId) 逐层加载正式装备配置、物品表和插件表，输出：
 *   - 全部基础物品（装备为 0 插件真实 BaseItem；stack 按线上 null-baseItem 语义）；
 *   - 每件装备的全部合法 tier；
 *   - 每件装备一条合法 1 插件与 3 插件实例，用于宿主/堆叠形态覆盖；
 *   - 每个正式插件定义至少一条实际可安装路径（含最多 3 层前置依赖搜索）。
 *
 * 旧 runWithRealData() 几何 dump 入口保留为兼容诊断，但 Web 容量审计只消费
 * TC_ITEM / TC_TOTAL / TOOLTIP_CORPUS_DONE 协议。
 *
 * 为什么需要这个：
 *   - AS2 端 introBg / mainBg / icon / introText / mainText 各自的 width/height/x/y
 *     在源码里是公式分散 + applyIntroLayout / showTooltip / positionTooltip 串起来才能算出来；
 *   - 单读代码很容易漏关键事实（比如 icon Y=19~219 与 introText Y=210+ 重叠 9px，
 *     说明 icon 不是 flex column 在 intro text 上方，而是 absolute 锚定在 introBg 左上的独立层）；
 *   - 用真实物品全量 dump，把每一项的真值落地成 JSON，web 端按这份真值复刻几何，避免"读 AS2 → 推视觉"。
 *
 * 输出协议（trace 行级，给 compile_output.txt 抓）：
 *   GT_META|<k=v,k=v,...>      AS2 常量基线（BASE_NUM/INTRO_MAX_W/...）
 *   GT_HEAD|<colName1|colName2|...>     字段名声明
 *   GT_ITEM|name|use|...                每个 split item 一行
 *   GT_TOTAL|<n>                        dump 完毕的 item 数
 *
 * 字段宽度都按 AS2 公式现场算（不依赖完整 positionTooltip 链路，避免 icon 资产
 * 在 testMovie 下没法 attachMovie 的副作用）：
 *   introBg._height = introText.textHeight + BASE_NUM + BG_HEIGHT_OFFSET   （= textH + 220）
 *   mainBg._height  = mainText.textHeight + TEXT_PAD                       （= textH + 10）
 *   mainBg height floor （positionTooltip else 分支）= max(mainTextH, icon._height) + HEIGHT_ADJUST
 *   icon._height = BASE_NUM × ICON_SCALE/100                               （200 × 1.5 = 300）
 *
 * 现役用法：从仓库根运行 scripts/run-tooltip-corpus-audit.ps1；runner 会事务化替换并恢复 TestLoader。
 */
class org.flashNight.gesh.tooltip.test.TooltipCorpusDump {

    private static var _scratch:Object = {total: 0, maxLine: 0, lineCount: 0};
    private static var _recordSequence:Number = 0;
    private static var _baseCount:Number = 0;
    private static var _equipmentCount:Number = 0;
    private static var _tierCount:Number = 0;
    private static var _mod1Count:Number = 0;
    private static var _mod3Count:Number = 0;
    private static var _modCoverageRecordCount:Number = 0;
    private static var _modDefinitionCount:Number = 0;
    private static var _coveredModCount:Number = 0;
    private static var _coveredModDict:Object = {};
    private static var _composeFailures:Number = 0;

    /** 全量语料入口；完成标记携带 runId，供异步 focused runner 精确截取。 */
    public static function runAllTests(runId:String):Void {
        if (runId == undefined || runId == null || runId.length == 0) runId = "manual";
        resetCorpusCounters();
        trace("TOOLTIP_CORPUS_BEGIN|" + escapeBar(runId));
        MockTooltipContainer.install();

        var equipLoader:EquipmentConfigLoader = EquipmentConfigLoader.getInstance();
        equipLoader.loadEquipmentConfig(function(configData:Object):Void {
            EquipmentUtil.loadEquipmentConfig(configData);
            var itemLoader:ItemDataLoader = ItemDataLoader.getInstance();
            itemLoader.loadItemData(function(combinedData):Void {
                ItemUtil.loadItemData(combinedData);
                var modLoader:EquipModListLoader = EquipModListLoader.getInstance();
                modLoader.loadModData(function(modEnvelope:Object):Void {
                    if (!modEnvelope || !(modEnvelope.mod instanceof Array)) {
                        finishCorpusFailure(runId, "mod_payload_invalid");
                        return;
                    }
                    EquipmentUtil.loadModData(modEnvelope.mod);
                    dumpTooltipCorpus(runId);
                }, function():Void {
                    finishCorpusFailure(runId, "mod_load_failed");
                });
            }, function():Void {
                finishCorpusFailure(runId, "item_load_failed");
            });
        }, function():Void {
            finishCorpusFailure(runId, "equipment_config_load_failed");
        });
    }

    private static function resetCorpusCounters():Void {
        _recordSequence = 0;
        _baseCount = 0;
        _equipmentCount = 0;
        _tierCount = 0;
        _mod1Count = 0;
        _mod3Count = 0;
        _modCoverageRecordCount = 0;
        _modDefinitionCount = 0;
        _coveredModCount = 0;
        _coveredModDict = {};
        _composeFailures = 0;
    }

    private static function finishCorpusFailure(runId:String, reason:String):Void {
        MockTooltipContainer.teardown();
        trace("TOOLTIP_CORPUS_FAILED|" + escapeBar(runId) + "|" + escapeBar(reason));
        trace("TOOLTIP_CORPUS_END|" + escapeBar(runId));
    }

    private static function dumpTooltipCorpus(runId:String):Void {
        var allItems:Array = ItemUtil.itemDataArray;
        trace("TC_HEAD|id|variant|name|displayname|type|use|tier|mods|icon|modslot|tierOptions|authorChars|split|introHTML|descHTML");
        if (allItems == null || allItems.length == 0) {
            finishCorpusFailure(runId, "item_array_empty");
            return;
        }
        _modDefinitionCount = EquipmentUtil.modList instanceof Array
            ? EquipmentUtil.modList.length : 0;

        for (var i:Number = 0; i < allItems.length; i++) {
            var item:Object = allItems[i];
            if (!item || !item.name) continue;
            var isEquipment:Boolean = ItemUtil.isEquipment(item.name);
            var baseItem:BaseItem = isEquipment ? BaseItem.create(item.name, 1, 0) : null;
            emitCorpusRecord("base", item, baseItem, "", []);
            _baseCount++;

            if (!isEquipment || baseItem == null) continue;
            _equipmentCount++;

            var tierOptions:Array = TierSystem.getAllTierOptions(baseItem);
            for (var tierIndex:Number = 0; tierIndex < tierOptions.length; tierIndex++) {
                var option:Object = tierOptions[tierIndex];
                if (!option || option.available !== true) continue;
                var tierItem:BaseItem = BaseItem.create(item.name, 1, 0);
                if (tierItem == null) continue;
                tierItem.value.tier = String(option.name);
                emitCorpusRecord("tier", item, tierItem, String(option.name), []);
                _tierCount++;
            }

            var oneItem:BaseItem = BaseItem.create(item.name, 1, 0);
            var onePath:Array = emitDirectModCoverageAndGetFirst(item, oneItem);
            if (onePath != null && onePath.length == 1) {
                oneItem.value.mods = onePath.concat();
                emitCorpusRecord("mods-1", item, oneItem, "", onePath);
                _mod1Count++;
            }

            var threeItem:BaseItem = BaseItem.create(item.name, 1, 0);
            var threePath:Array = findLegalModPath(threeItem, 3);
            if (threePath != null && threePath.length == 3) {
                threeItem.value.mods = threePath.concat();
                emitCorpusRecord("mods-3", item, threeItem, "", threePath);
                _mod3Count++;
            }
        }

        var uncoveredMods:Array = emitModDefinitionCoverage(allItems);
        trace("TC_MOD_COVERAGE|definitions=" + _modDefinitionCount
            + "|covered=" + _coveredModCount
            + "|records=" + _modCoverageRecordCount
            + "|uncovered=" + uncoveredMods.length
            + "|names=" + escapeBar(uncoveredMods.join(",")));
        if (_modDefinitionCount <= 0 || uncoveredMods.length > 0) {
            finishCorpusFailure(runId, "mod_coverage_incomplete");
            return;
        }

        trace("TC_TOTAL|records=" + _recordSequence
            + "|base=" + _baseCount
            + "|equipment=" + _equipmentCount
            + "|tiers=" + _tierCount
            + "|mods1=" + _mod1Count
            + "|mods3=" + _mod3Count
            + "|modCoverage=" + _modCoverageRecordCount
            + "|modDefinitions=" + _modDefinitionCount
            + "|modsCovered=" + _coveredModCount
            + "|composeFailures=" + _composeFailures);
        MockTooltipContainer.teardown();
        trace("TOOLTIP_CORPUS_DONE|" + escapeBar(runId)
            + "|records=" + _recordSequence
            + "|composeFailures=" + _composeFailures);
        trace("TOOLTIP_CORPUS_END|" + escapeBar(runId));
    }

    /** 找到一条每一步都通过正式 isModMaterialAvailable 的安装链。 */
    private static function findLegalModPath(item:BaseItem, targetLength:Number):Array {
        if (item == null || targetLength <= 0) return [];
        if (!(item.value.mods instanceof Array)) item.value.mods = [];
        var rawItemData:Object = ItemUtil.getItemData(item.name);
        // 容量不足时提前结束。否则 modslot=1/2 的大量武器会穷举所有合法前缀，
        // 明知第三步必然被槽位门拒绝仍做 O(n^target) 搜索，阻塞 TestLoader 主帧。
        var modslot = rawItemData && rawItemData.data
            ? rawItemData.data.modslot : undefined;
        if (modslot !== undefined && Number(modslot) < targetLength) return null;
        return searchLegalModPath(item, rawItemData, targetLength);
    }

    private static function searchLegalModPath(item:BaseItem, rawItemData:Object, targetLength:Number):Array {
        var installed:Array = item.value.mods;
        if (installed.length >= targetLength) return installed.concat();
        var candidates:Array = EquipmentUtil.getAvailableModMaterials(item);
        if (!candidates || candidates.length == 0) return null;
        candidates.sort();
        for (var i:Number = 0; i < candidates.length; i++) {
            var modName:String = String(candidates[i]);
            if (EquipmentUtil.isModMaterialAvailable(item, rawItemData, modName) !== 1) continue;
            installed.push(modName);
            var found:Array = searchLegalModPath(item, rawItemData, targetLength);
            installed.pop();
            if (found != null) return found;
        }
        return null;
    }

    /**
     * 复用每件装备原本就要做的 1 插件候选扫描：返回首条代表路径，同时把其余尚未
     * 覆盖的直接可安装插件立即落成 coverage record，避免结束后再全表扫描一遍。
     */
    private static function emitDirectModCoverageAndGetFirst(sourceItem:Object, item:BaseItem):Array {
        if (item == null) return null;
        var rawItemData:Object = ItemUtil.getItemData(item.name);
        var candidates:Array = EquipmentUtil.getAvailableModMaterials(item);
        if (!(candidates instanceof Array) || candidates.length == 0) return null;
        candidates.sort();
        var firstPath:Array = null;
        for (var candidateIndex:Number = 0; candidateIndex < candidates.length; candidateIndex++) {
            var candidateName:String = String(candidates[candidateIndex]);
            // 找到代表路径后，已覆盖定义无需再次执行完整 availability 复核。
            if (firstPath != null && _coveredModDict[candidateName]) continue;
            if (EquipmentUtil.isModMaterialAvailable(item, rawItemData, candidateName) !== 1) continue;
            if (firstPath == null) {
                firstPath = [candidateName];
                continue;
            }
            item.value.mods.push(candidateName);
            emitCorpusRecord("mods-cover", sourceItem, item, "", item.value.mods.concat());
            _modCoverageRecordCount++;
            item.value.mods.pop();
        }
        return firstPath;
    }

    /**
     * 为每个正式插件定义找到至少一条实际可安装路径。直接安装已随主循环覆盖；这里只为
     * 仍未覆盖的依赖插件搜索最多 3 槽状态，状态按已安装集合去重，避免排列爆炸。
     */
    private static function emitModDefinitionCoverage(allItems:Array):Array {
        var modList:Array = EquipmentUtil.modList;
        if (!(modList instanceof Array) || modList.length == 0) return [];

        var itemIndex:Number;
        // 只有依赖 tag/grantsUse 的插件会到这里。
        for (itemIndex = 0; itemIndex < allItems.length && _coveredModCount < _modDefinitionCount; itemIndex++) {
            var pathSource:Object = allItems[itemIndex];
            if (!pathSource || !pathSource.name || !ItemUtil.isEquipment(pathSource.name)) continue;
            var pathItem:BaseItem = BaseItem.create(pathSource.name, 1, 0);
            if (pathItem == null) continue;
            var pathData:Object = ItemUtil.getItemData(pathSource.name);
            var maxDepth:Number = 3;
            if (pathData && pathData.data && pathData.data.modslot != undefined) {
                var configuredDepth:Number = Math.floor(Number(pathData.data.modslot));
                if (!isNaN(configuredDepth) && configuredDepth > 0) maxDepth = configuredDepth;
            }
            if (maxDepth > 3) maxDepth = 3;
            exploreModCoveragePaths(pathSource, pathItem, pathData, 0, maxDepth, {});
        }

        var uncovered:Array = [];
        for (var modIndex:Number = 0; modIndex < modList.length; modIndex++) {
            var modName:String = String(modList[modIndex]);
            if (!_coveredModDict[modName]) uncovered.push(modName);
        }
        uncovered.sort();
        return uncovered;
    }

    private static function exploreModCoveragePaths(sourceItem:Object, item:BaseItem,
            rawItemData:Object, depth:Number, maxDepth:Number, visited:Object):Void {
        if (_coveredModCount >= _modDefinitionCount || depth >= maxDepth) return;
        var signatureParts:Array = item.value.mods.concat();
        signatureParts.sort();
        var signature:String = signatureParts.join("\u001f");
        if (visited[signature]) return;
        visited[signature] = true;

        var candidates:Array = EquipmentUtil.getAvailableModMaterials(item);
        if (!(candidates instanceof Array)) return;
        candidates.sort();
        for (var candidateIndex:Number = 0;
                candidateIndex < candidates.length && _coveredModCount < _modDefinitionCount;
                candidateIndex++) {
            var candidateName:String = String(candidates[candidateIndex]);
            if (EquipmentUtil.isModMaterialAvailable(item, rawItemData, candidateName) !== 1) continue;
            item.value.mods.push(candidateName);
            if (!_coveredModDict[candidateName]) {
                emitCorpusRecord("mods-cover", sourceItem, item, "", item.value.mods.concat());
                _modCoverageRecordCount++;
            }
            exploreModCoveragePaths(sourceItem, item, rawItemData, depth + 1, maxDepth, visited);
            item.value.mods.pop();
        }
    }

    private static function markCoveredMods(mods:Array):Void {
        if (!(mods instanceof Array)) return;
        for (var modIndex:Number = 0; modIndex < mods.length; modIndex++) {
            var modName:String = String(mods[modIndex]);
            if (!modName || _coveredModDict[modName] || EquipmentUtil.modDict[modName] == undefined) continue;
            _coveredModDict[modName] = true;
            _coveredModCount++;
        }
    }

    private static function emitCorpusRecord(variant:String, sourceItem:Object,
            baseItem:BaseItem, tier:String, mods:Array):Void {
        var itemData:Object = ItemUtil.getItemData(sourceItem.name);
        if (!itemData) {
            _composeFailures++;
            return;
        }
        var value:Object = baseItem != null ? baseItem.value : {level: 1};
        var descText:String;
        var introText:String;
        try {
            descText = TooltipComposer.generateItemDescriptionText(itemData, baseItem);
            introText = TooltipComposer.generateIntroPanelContent(baseItem, itemData, value);
        } catch (error) {
            _composeFailures++;
            trace("TC_COMPOSE_ERROR|" + escapeBar(String(sourceItem.name))
                + "|" + escapeBar(variant) + "|" + escapeBar(String(error)));
            return;
        }

        markCoveredMods(mods);

        _recordSequence++;
        var rawData:Object = itemData.data;
        var modslot:String = rawData && rawData.modslot != undefined
            ? String(rawData.modslot) : "";
        var tierOptions:Array = baseItem != null ? TierSystem.getAllTierOptions(baseItem) : [];
        var availableTiers:Number = 0;
        for (var tierIndex:Number = 0; tierIndex < tierOptions.length; tierIndex++) {
            if (tierOptions[tierIndex] && tierOptions[tierIndex].available === true) availableTiers++;
        }
        var authorText:String = itemData.description == undefined ? "" : String(itemData.description);
        var split:Boolean = TooltipLayout.shouldSplitSmart(descText, introText, null);
        trace("TC_ITEM|" + _recordSequence
            + "|" + escapeBar(variant)
            + "|" + escapeBar(String(itemData.name))
            + "|" + escapeBar(String(itemData.displayname || itemData.name))
            + "|" + escapeBar(String(itemData.type))
            + "|" + escapeBar(String(itemData.use))
            + "|" + escapeBar(tier)
            + "|" + escapeBar(mods ? mods.join(",") : "")
            + "|" + escapeBar(String(itemData.icon || ""))
            + "|" + modslot
            + "|" + availableTiers
            + "|" + authorText.length
            + "|" + (split ? "1" : "0")
            + "|" + escapeForLine(introText)
            + "|" + escapeForLine(descText));
    }

    public static function runWithRealData():Void {
        trace("=== TooltipGroundTruthDump (Real Data Mode) ===");
        MockTooltipContainer.install();

        var equipLoader:EquipmentConfigLoader = EquipmentConfigLoader.getInstance();
        equipLoader.loadEquipmentConfig(function(configData:Object):Void {
            trace("  EquipmentConfig loaded OK");
            EquipmentUtil.loadEquipmentConfig(configData);

            var itemLoader:ItemDataLoader = ItemDataLoader.getInstance();
            itemLoader.loadItemData(function(combinedData):Void {
                trace("  ItemData loaded OK, count=" + combinedData.length);
                ItemUtil.loadItemData(combinedData);

                dumpConstants();
                dumpAllSplitItems();

                MockTooltipContainer.teardown();
                trace("=== END TooltipGroundTruthDump ===");
            }, function():Void {
                trace("  [ERROR] ItemData load failed!");
                MockTooltipContainer.teardown();
            });
        }, function():Void {
            trace("  [ERROR] EquipmentConfig load failed!");
            MockTooltipContainer.teardown();
        });
    }

    private static function dumpConstants():Void {
        // icon 实际像素（AS2 库资产 BASE_NUM × ICON_SCALE 缩放）
        var iconH:Number = TooltipConstants.BASE_NUM * (TooltipConstants.ICON_SCALE / 100);
        trace("GT_META|BASE_NUM=" + TooltipConstants.BASE_NUM
            + ",INTRO_MAX_W=" + TooltipConstants.INTRO_MAX_W
            + ",MIN_W=" + TooltipConstants.MIN_W
            + ",MAX_W=" + TooltipConstants.MAX_W
            + ",TEXT_PAD=" + TooltipConstants.TEXT_PAD
            + ",BG_HEIGHT_OFFSET=" + TooltipConstants.BG_HEIGHT_OFFSET
            + ",TEXT_Y_EQUIPMENT=" + TooltipConstants.TEXT_Y_EQUIPMENT
            + ",TEXT_Y_BASE=" + TooltipConstants.TEXT_Y_BASE
            + ",MOUSE_OFFSET=" + TooltipConstants.MOUSE_OFFSET
            + ",HEIGHT_ADJUST=" + TooltipConstants.HEIGHT_ADJUST
            + ",ICON_SCALE=" + TooltipConstants.ICON_SCALE
            + ",ICON_OFFSET=" + TooltipConstants.ICON_OFFSET
            + ",BASE_SCALE=" + TooltipConstants.BASE_SCALE
            + ",BASE_OFFSET=" + TooltipConstants.BASE_OFFSET
            + ",ICON_H_PX=" + iconH
            + ",DUAL_PANEL_MARGIN=" + TooltipConstants.DUAL_PANEL_MARGIN
            + ",STAGE_W=" + Stage.width
            + ",STAGE_H=" + Stage.height);
    }

    /**
     * 真实复刻 TooltipLayout.positionTooltip 的双面板分支算法，给定 (introBgH, mainBgH, mainTH, iconH, mouseY)
     * 返回 (rightBg_y, rightBg_h_final, tips_y, branch) — 不依赖 MovieClip，纯函数。
     */
    private static function simulatePose(introBgH:Number, mainBgH:Number, mainTH:Number, iconH:Number, mouseY:Number, stageH:Number):Object {
        // tips._height = max(introBgH, mainBgH)（mainBgH 是 base = textH+10，不含 floor）
        var tipsH:Number = Math.max(introBgH, mainBgH);
        var tipsY:Number = Math.min(stageH - tipsH, Math.max(0, mouseY - tipsH - TooltipConstants.MOUSE_OFFSET));
        var rightBottomH:Number = tipsY + mainBgH;
        var offset:Number = mouseY - rightBottomH - TooltipConstants.MOUSE_OFFSET;

        var rightBgY:Number;   // rightBg 在 tips 内的 y（相对，不是 stage）
        var rightBgH:Number;
        var branch:String;
        if (offset > 0) {
            // IF 分支：mainBg 整块下移 offset，高度不变
            rightBgY = offset;
            rightBgH = mainBgH;
            branch = "IF";
        } else {
            // ELSE 分支：mainBg 高度被 max(textH, iconH)+10 顶起
            rightBgY = 0;
            rightBgH = Math.max(mainTH, iconH) + TooltipConstants.HEIGHT_ADJUST;
            branch = "ELSE";
        }
        return {rightBgY: rightBgY, rightBgH: rightBgH, tipsY: tipsY, branch: branch, offset: offset};
    }

    private static function dumpAllSplitItems():Void {
        var allItems:Array = ItemUtil.itemDataArray;
        if (allItems == null || allItems.length == 0) {
            trace("  [WARN] No items loaded!");
            return;
        }

        // 字段说明：
        //   name        item.name
        //   type/use    item.type "/" item.use（用于按物品种类筛 fixture）
        //   dT/dM/dL    desc total / maxLine / lineCount score
        //   iT/iM/iL    intro 同上
        //   introW      AS2 算出的 intro 宽度
        //   mainW       AS2 算出的 main 宽度（含 balanceWidth 二分搜索后）
        //   introTH     introText.textHeight @introW
        //   mainTH      mainText.textHeight @mainW
        //   introBgH    introBg 高度 = introTH + 220
        //   mainBgH     mainBg 高度（基础） = mainTH + 10
        //   mainBgFlr   mainBg 高度下限（positionTooltip else 分支） = max(mainTH, iconH) + 10
        trace("GT_HEAD|name|type|use|dT|dM|dL|iT|iM|iL|introW|mainW|introTH|mainTH|introBgH|mainBgH|mainBgFlr");
        // GT_POSE 行：模拟 positionTooltip 在不同 mouseY 下的 desc 实际位置
        // 字段：name|mouseY|branch|tipsY|rightBgY|rightBgH|offset
        // 解读：rightBgY 是 desc 面板在 tips 内的相对 y（相对 tips 顶部），rightBgH 是 desc 面板实际高度
        trace("GT_POSE_HEAD|name|mouseY|branch|tipsY|rightBgY|rightBgH|offset");

        var bi = MockItemFactory.mockBaseItem();
        var introTf:Object = TooltipBridge.getIntroTextBox();
        var mainTf:Object = TooltipBridge.getMainTextBox();
        var iconH:Number = TooltipConstants.BASE_NUM * (TooltipConstants.ICON_SCALE / 100);
        var stageH:Number = Stage.height;
        // mouseY sweep: 鼠标从顶到底覆盖 stage 全程，间隔 ~stageH/8（共 9 个采样点）
        var mouseSweep:Array = [];
        var ms:Number = 8;
        for (var sm:Number = 0; sm <= ms; sm++) {
            mouseSweep.push(Math.round(sm * stageH / ms));
        }
        var dumped:Number = 0;

        for (var i:Number = 0; i < allItems.length; i++) {
            var item:Object = allItems[i];
            if (item == null) continue;

            var descText:String = TooltipComposer.generateItemDescriptionText(item, bi);
            var introText:String = TooltipComposer.generateIntroPanelContent(bi, item, bi.value);

            // 只 dump split 模式物品（merge 模式只有单面板，几何简单）
            if (!TooltipLayout.shouldSplitSmart(descText, introText, null)) continue;

            var descSc:Object = StringUtils.htmlScoresBoth(descText, null, _scratch);
            var dT:Number = descSc.total;
            var dM:Number = descSc.maxLine;
            var dL:Number = descSc.lineCount;
            // htmlScoresBoth 复用 scratch，第二次 call 会覆盖第一次结果，所以这里再开一个对象
            var introScScratch:Object = {total: 0, maxLine: 0, lineCount: 0};
            var introSc:Object = StringUtils.htmlScoresBoth(introText, null, introScScratch);
            var iT:Number = introSc.total;
            var iM:Number = introSc.maxLine;
            var iL:Number = introSc.lineCount;

            // intro 宽：AS2 端 TooltipComposer.renderItemIcon R2 注释明确写道：
            //   "简介面板始终使用固定宽度，不随内容自适应——避免图标左移导致的视觉断裂；
            //    换行损失由条目压缩 (R1) 补偿"
            //   measuredIntroW = BASE_NUM = 200
            // 也就是说 runtime 永远走 customWidth=BASE_NUM 这条分支，applyIntroLayout 内部
            // w = (customWidth > BASE_NUM ? min(customWidth, INTRO_MAX_W) : BASE_NUM) = 200。
            // 旧 dump 用 estimateWidth(...) 估算导致 introW 字段在 [150, 300] 漂移，
            // 跟运行时实际锁宽不一致。修正：直接输出 BASE_NUM。
            var introW:Number = TooltipConstants.BASE_NUM;
            // main 宽：先用 estimateMainWidth 估算 + balanceWidth 二分搜索 shrink-to-fit
            var initMainW:Number = TooltipLayout.estimateMainWidth(descText,
                TooltipConstants.MIN_W, TooltipConstants.MAX_W);
            var mainW:Number = TooltipLayout.balanceWidth(initMainW, descText,
                TooltipConstants.MAX_W);

            // 测 introText textHeight @ introW
            introTf.wordWrap = true;
            introTf._width = introW;
            introTf.htmlText = introText;
            var introTH:Number = introTf.textHeight;

            // 测 mainText textHeight @ mainW
            mainTf.wordWrap = true;
            mainTf._width = mainW;
            mainTf.htmlText = descText;
            var mainTH:Number = mainTf.textHeight;

            // AS2 公式计算面板高度
            var introBgH:Number = introTH + TooltipConstants.BASE_NUM + TooltipConstants.BG_HEIGHT_OFFSET;
            var mainBgH:Number = mainTH + TooltipConstants.TEXT_PAD;
            var mainBgFlr:Number = Math.max(mainTH, iconH) + TooltipConstants.HEIGHT_ADJUST;

            trace("GT_ITEM|" + escapeBar(item.name)
                + "|" + escapeBar(String(item.type))
                + "|" + escapeBar(String(item.use))
                + "|" + dT + "|" + dM + "|" + dL
                + "|" + iT + "|" + iM + "|" + iL
                + "|" + introW + "|" + mainW
                + "|" + introTH + "|" + mainTH
                + "|" + introBgH + "|" + mainBgH + "|" + mainBgFlr);

            // HTML 内容（给 web fixture 重新渲染做 box-model diff 用）
            // 换行/竖线在 escapeForLine 里替换为 ¶ / _，python 解析时再还原
            trace("GT_HTML_INTRO|" + escapeBar(item.name) + "|" + escapeForLine(introText));
            trace("GT_HTML_DESC|" + escapeBar(item.name) + "|" + escapeForLine(descText));

            // 该 item 在不同 mouseY 下的 pose（模拟 positionTooltip）
            for (var mi:Number = 0; mi < mouseSweep.length; mi++) {
                var mY:Number = mouseSweep[mi];
                var pose:Object = simulatePose(introBgH, mainBgH, mainTH, iconH, mY, stageH);
                trace("GT_POSE|" + escapeBar(item.name)
                    + "|" + mY + "|" + pose.branch
                    + "|" + pose.tipsY + "|" + pose.rightBgY
                    + "|" + pose.rightBgH + "|" + pose.offset);
            }
            dumped++;
        }
        trace("GT_TOTAL|" + dumped);
    }

    /** 把 | 替换成 _ 避免破坏 GT 行的列分隔 */
    private static function escapeBar(s:String):String {
        if (s == null) return "";
        return s.split("|").join("_");
    }

    /** 整行内容转义：竖线 → _，换行 → ¶ (U+00B6)，回车 → ¤
     *  目的是把多行 HTML 塞进单行 trace；python 端解析时反向替换 */
    private static function escapeForLine(s:String):String {
        if (s == null) return "";
        var r:String = s.split("|").join("_");
        r = r.split("\n").join("¶");
        r = r.split("\r").join("¤");
        return r;
    }
}
