/**
 * TooltipCorpusContextLoader — TooltipCorpusDump.runAllTests 的 includeContext 可选扩展。
 *
 * 背景：fresh3706 语料中【升阶路线·升自/可升】与【获取方式】整块缺失，
 * 因为 dump 只装了装备配置 / 物品表 / 插件表，从未建立 BootSequencer S9 的
 * 合成与获取方式索引（_root.改装清单*、_root.shops、_root.kshop_list、
 * _root.竞技场掉落规则 → SynthesisIndex / ItemObtainIndex）。
 *
 * 本类在 TestLoader 内复刻 S9 的最小静态闭包：不启动 BootSequencer、不建
 * _root.preloaders / _root.loaders 队列、不读存档、不注入动态来源。
 *
 * 依赖路径与生产对齐：
 *   data/crafting/list.xml + 分类 JSON    → _root.改装清单 / 改装清单对象 / 改装分类顺序
 *   data/arena/arena_drop_rules.xml       → _root.竞技场掉落规则（归一化 catalog）
 *   data/shops/list.xml  + 子 JSON        → _root.shops / _root.shopLayouts
 *   data/kshop/list.xml  + 子 JSON        → _root.kshop_list
 *
 * 语义逐字对齐生产：
 *   - crafting 投影 = BootSequencer.applyCraftingData（name→配方 dict、value 默认 1）；
 *   - shops 合并 = 商店系统_兼容.as（npc-shop.v2 严格 schema / legacy 多店兜底 /
 *     "$"+id 去重 / catalog:{} 保留停用 NPC identity），任一违规 fail closed；
 *   - kshop 合并 = 商城系统_兼容.as（每个文件必须非空 Array，按 list.xml 序 concat）；
 *   - 非空闸 = S9（shops identity ≥1、kshop_list.length ≥1）；
 *   - buildIndex 参数 = S9（_root.改装清单, _root.shops, _root.kshop_list, _root.竞技场掉落规则）。
 *
 * 动态来源（drop:stage / enemy / quest）依赖实战与存档回放，fresh 会话不注入，
 * 与生产 fresh-session tooltip 一致，不伪造。
 *
 * 四路异步全部落定后才重建索引；任一路径失败只回调 onFail(reason)，
 * 绝不静默导出空上下文。
 */
import org.flashNight.gesh.json.LoadJson.CraftingListLoader;
import org.flashNight.gesh.xml.LoadXml.ArenaDropRulesLoader;
import org.flashNight.aven.Promise.ListLoader;
import org.flashNight.aven.Promise.LoaderPromise;
import org.flashNight.arki.item.synthesis.SynthesisIndex;
import org.flashNight.arki.item.obtain.ItemObtainIndex;

class org.flashNight.gesh.tooltip.test.TooltipCorpusContextLoader {

    private static var _pending:Number = 0;
    private static var _failed:Boolean = false;
    private static var _onReady:Function = null;
    private static var _onFail:Function = null;
    private static var _craftingData:Object = null;
    private static var _arenaCatalog:Object = null;
    private static var _shopAcc:Object = null;
    private static var _kshopAcc:Object = null;

    /**
     * 并发装载四路静态来源；全部成功后重建索引并回调 onReady()，
     * 任一路径失败回调 onFail(reason:String)。
     * 假定 PathManager.initialize() 已由调用方完成（runAllTests 首部已做）。
     */
    public static function load(onReady:Function, onFail:Function):Void {
        _onReady = onReady;
        _onFail = onFail;
        _failed = false;
        _pending = 4;
        _craftingData = null;
        _arenaCatalog = null;
        _shopAcc = null;
        _kshopAcc = null;

        CraftingListLoader.getInstance().loadCraftingList(
            onCraftingReady, onCraftingFail);
        ArenaDropRulesLoader.getInstance().loadArenaDropRules(
            onArenaReady, onArenaFail);
        loadShopCatalog();
        loadKShopCatalog();
    }

    // ================================================================
    // crafting / arena：领域单例 loader 直挂
    // ================================================================

    private static function onCraftingReady(data:Object):Void {
        _craftingData = data;
        stepDone();
    }

    private static function onCraftingFail():Void {
        stepFail("crafting_catalog_failed");
    }

    private static function onArenaReady(catalog:Object):Void {
        _arenaCatalog = catalog;
        stepDone();
    }

    private static function onArenaFail():Void {
        stepFail("arena_drop_rules_failed");
    }

    // ================================================================
    // shops：list.xml → 子 JSON 合并（复刻 商店系统_兼容.as 校验）
    // ================================================================

    private static function loadShopCatalog():Void {
        LoaderPromise.loadXML("data/shops/list.xml").then(function(listData:Object):Object {
            var entries:Array = ListLoader.normalizeToArray(
                (listData != null) ? listData.shops : null);
            if (entries.length < 1) {
                TooltipCorpusContextLoader.stepFail("shop_list_empty");
                return null;
            }
            return ListLoader.loadChildren({
                entries:entries,
                basePath:"data/shops/",
                childType:"json",
                parseType:"LiteJSON",
                mergeFn:TooltipCorpusContextLoader.mergeShopFile,
                initialValue:{shops:{}, shopLayouts:{}, seen:{}, count:0, failed:false}
            }).then(function(acc:Object):Object {
                if (acc == null || acc.failed === true || acc.count < 1) {
                    TooltipCorpusContextLoader.stepFail("shop_catalog_failed");
                    return null;
                }
                TooltipCorpusContextLoader._shopAcc = acc;
                TooltipCorpusContextLoader.stepDone();
                return null;
            });
        }).onCatch(function(reason:Object):Void {
            TooltipCorpusContextLoader.stepFail("shop_catalog_failed");
        });
    }

    /**
     * 与 商店系统_兼容.as loader 段同语义：
     * schema 存在 → 必须是完整 npc-shop.v2（string schema / 非空 shopId /
     * 对象 catalog；catalog:{} 合法表示停用 NPC 目录）；schema 缺失 → legacy
     * 多店对象，每个 key 一个店且 catalog 必须是含 ≥1 键的对象；
     * "$"+id 跨文件去重；任何违规 acc.failed=true（上层 fail closed）。
     */
    private static function mergeShopFile(acc:Object, parsed:Object,
                                          index:Number, entry:String):Object {
        if (parsed == null || typeof parsed != "object" || parsed instanceof Array) {
            acc.failed = true;
            return acc;
        }
        if (parsed.schema !== undefined) {
            if (typeof parsed.schema != "string"
                    || parsed.schema !== "npc-shop.v2"
                    || typeof parsed.shopId != "string"
                    || parsed.shopId.length < 1) {
                acc.failed = true;
                return acc;
            }
            var shopId:String = parsed.shopId;
            var shopCatalog:Object = parsed.catalog;
            if (shopCatalog == null || typeof shopCatalog != "object"
                    || shopCatalog instanceof Array) {
                acc.failed = true;
                return acc;
            }
            var shopIdentityKey:String = "$" + shopId;
            if (acc.seen[shopIdentityKey] === true) {
                acc.failed = true;
                return acc;
            }
            acc.seen[shopIdentityKey] = true;
            acc.shops[shopId] = shopCatalog;
            acc.shopLayouts[shopId] = {
                title:parsed.title == undefined ? shopId : String(parsed.title),
                defaultSection:parsed.defaultSection == undefined
                    ? "" : String(parsed.defaultSection),
                sections:parsed.sections instanceof Array ? parsed.sections : []
            };
            acc.count++;
            return acc;
        }
        var entryCount:Number = 0;
        for (var key:String in parsed) {
            var legacyShopId:String = String(key);
            var legacyCatalog:Object = parsed[key];
            var legacyIdentityKey:String = "$" + legacyShopId;
            var legacyCatalogEntryCount:Number = 0;
            if (legacyCatalog != null && typeof legacyCatalog == "object"
                    && !(legacyCatalog instanceof Array)) {
                for (var legacyCatalogKey:String in legacyCatalog) {
                    legacyCatalogEntryCount++;
                }
            }
            if (legacyShopId.length < 1 || legacyCatalogEntryCount < 1
                    || acc.seen[legacyIdentityKey] === true) {
                acc.failed = true;
                return acc;
            }
            acc.seen[legacyIdentityKey] = true;
            acc.shops[legacyShopId] = legacyCatalog;
            entryCount++;
        }
        if (entryCount < 1) {
            acc.failed = true;
            return acc;
        }
        acc.count += entryCount;
        return acc;
    }

    // ================================================================
    // kshop：list.xml → 子 JSON 数组合并（复刻 商城系统_兼容.as 校验）
    // ================================================================

    private static function loadKShopCatalog():Void {
        LoaderPromise.loadXML("data/kshop/list.xml").then(function(listData:Object):Object {
            var entries:Array = ListLoader.normalizeToArray(
                (listData != null) ? listData.kshop : null);
            if (entries.length < 1) {
                TooltipCorpusContextLoader.stepFail("kshop_list_empty");
                return null;
            }
            return ListLoader.loadChildren({
                entries:entries,
                basePath:"data/kshop/",
                childType:"json",
                parseType:"LiteJSON",
                mergeFn:TooltipCorpusContextLoader.mergeKShopFile,
                initialValue:{list:[], count:0, failed:false}
            }).then(function(acc:Object):Object {
                if (acc == null || acc.failed === true || acc.count < 1
                        || !(acc.list instanceof Array) || acc.list.length < 1) {
                    TooltipCorpusContextLoader.stepFail("kshop_catalog_failed");
                    return null;
                }
                TooltipCorpusContextLoader._kshopAcc = acc;
                TooltipCorpusContextLoader.stepDone();
                return null;
            });
        }).onCatch(function(reason:Object):Void {
            TooltipCorpusContextLoader.stepFail("kshop_catalog_failed");
        });
    }

    /**
     * 与 商城系统_兼容.as loader 段同语义：每个文件必须解析为非空 Array，
     * 按 list.xml 条目序 concat（ListLoader 分批链式合并保序）。
     */
    private static function mergeKShopFile(acc:Object, parsed:Object,
                                           index:Number, entry:String):Object {
        if (!(parsed instanceof Array) || parsed.length < 1) {
            acc.failed = true;
            return acc;
        }
        acc.list = acc.list.concat(parsed);
        acc.count++;
        return acc;
    }

    // ================================================================
    // 汇聚：四路全到 → 落 _root → 重建索引 → onReady
    // ================================================================

    private static function stepDone():Void {
        if (_failed) return;
        _pending--;
        if (_pending > 0) return;
        var reason:String = installContext();
        if (reason != null) {
            stepFail(reason);
            return;
        }
        var cb:Function = _onReady;
        _onReady = null;
        _onFail = null;
        if (cb != null) cb();
    }

    private static function stepFail(reason:String):Void {
        if (_failed) return;
        _failed = true;
        var cb:Function = _onFail;
        _onReady = null;
        _onFail = null;
        if (cb != null) cb(reason);
    }

    /**
     * 四路数据落 _root 全局并按 S9 顺序重建索引。
     * @return null 成功；否则失败 reason（由 stepFail 统一回调）。
     */
    private static function installContext():String {
        // crafting 投影 = BootSequencer.applyCraftingData
        if (_craftingData == null) return "crafting_catalog_empty";
        var craftingDict = {};
        var recipeCount:Number = 0;
        for (var category in _craftingData) {
            var list = _craftingData[category];
            for (var i = 0; i < list.length; i++) {
                var item = list[i];
                craftingDict[item.name] = item;
                if (isNaN(item.value)) item.value = 1;
                recipeCount++;
            }
        }
        if (recipeCount < 1) return "crafting_catalog_empty";
        _root.改装清单 = _craftingData;
        _root.改装清单对象 = craftingDict;
        _root.改装分类顺序 = CraftingListLoader.getInstance().getCategoryOrder();
        SynthesisIndex.reset();

        if (_arenaCatalog == null) return "arena_drop_rules_empty";
        _root.竞技场掉落规则 = _arenaCatalog;

        // 非空闸 = S9
        var shopCatalogCount:Number = 0;
        if (_shopAcc != null && _shopAcc.shops != null
                && typeof _shopAcc.shops == "object"
                && !(_shopAcc.shops instanceof Array)) {
            for (var shopId:String in _shopAcc.shops) {
                shopCatalogCount++;
            }
        }
        if (shopCatalogCount < 1) return "shop_catalog_empty";
        _root.shops = _shopAcc.shops;
        _root.shopLayouts = _shopAcc.shopLayouts;

        if (_kshopAcc == null || !(_kshopAcc.list instanceof Array)
                || _kshopAcc.list.length < 1) return "kshop_catalog_empty";
        _root.kshop_list = _kshopAcc.list;

        // 索引构建参数 = S9；reset(true) 使同 SWF 会话内重复调用幂等
        var obtainIndex:ItemObtainIndex = ItemObtainIndex.getInstance();
        obtainIndex.reset(true);
        obtainIndex.buildIndex(_root.改装清单, _root.shops,
            _root.kshop_list, _root.竞技场掉落规则);
        obtainIndex.rehydrateDiscoveredRecordsFromCurrentConfig();

        trace("TooltipCorpusContextLoader: context installed (recipes="
            + recipeCount + " shops=" + shopCatalogCount
            + " kshops=" + _kshopAcc.list.length + ")");
        return null;
    }
}
