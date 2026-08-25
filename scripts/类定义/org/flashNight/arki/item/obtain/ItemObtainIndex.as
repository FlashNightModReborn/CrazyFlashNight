import org.flashNight.gesh.object.ObjectUtil;

/**
 * ItemObtainIndex - 物品来源/经济数据索引
 *
 * 职责：
 * - 在游戏启动时构建反向索引，将物品名映射到其所有获取方式
 * - 提供O(1)复杂度的查询接口
 * - 支持合成、NPC商店、K点商店与竞技场 authored 掉落四种静态来源
 * - 支持动态来源：关卡掉落、敌人掉落、任务奖励（运行时增量发现）
 * - 保留完整语义信息（如商店的解锁条件）
 *
 * 数据模型：
 * - 统一使用 ObtainRecord 格式，每条记录带 kind 标识类型
 * - 静态来源（craft/shop/kshop/drop:arena）：启动时一次性构建
 * - 动态来源（drop:stage/drop:enemy/quest）：运行时增量发现，存档持久化
 *
 * ===== 动态来源存档策略（v2重构） =====
 * 存档只保存"发现集合"（关卡名/兵种/任务ID），不保存具体掉落明细。
 * 重启时从最新配置数据重建明细，确保配置更新后玩家能看到最新信息。
 *
 * 存档结构（精简版）：
 * obtainCache = {
 *   version: 2,
 *   discoveredStages: ["关卡A", "关卡B"],     // 已发现的关卡名列表
 *   discoveredEnemies: ["兵种A", "兵种B"],    // 已发现的敌人兵种列表
 *   discoveredQuests: ["0", "1", "2"]         // 已发现的任务ID列表
 * }
 *
 * 重建时机：
 * - 敌人/任务：loadFromSave 时直接从 _root.敌人属性表 / TaskUtil.tasks 重建
 * - 关卡：仅标记已发现，进入关卡时按需重建（或等关卡XML加载完成）
 *
 * ObtainRecord 格式：
 * {
 *   kind: String,           // 来源类型："craft" | "shop" | "kshop" | "drop" | "quest"
 *   // 以下字段根据 kind 不同而存在
 *   category: String,       // [craft] 合成分类
 *   price: Number,          // [craft/kshop] 金币价格
 *   kprice: Number,         // [craft] K点价格
 *   npc: String,            // [shop] NPC名称
 *   requiredInfo: String,   // [shop] 解锁条件描述（可选）
 *   type: String,           // [kshop] K点商店分类
 *   priceK: Number,         // [kshop] K点价格
 *   id: String,             // [kshop] 商品ID
 *   // ===== 掉落来源字段 =====
 *   dropType: String,       // [drop] "stage" | "enemy" | "arena"
 *   stageName: String,      // [drop:stage] 关卡名称
 *   enemyType: String,      // [drop:enemy] 敌人兵种
 *   arenaId: String,        // [drop:arena] 竞技场稳定 ID
 *   ruleId: String,         // [drop:arena] authored 规则 ID
 *   carrierScope: String,   // [drop:arena] "carrier" | "specific_carrier"
 *   probability: Number,    // [drop] v1 兼容 scalar，镜像首个 variant
 *   quantityMax: Number,    // [drop:stage] v1 兼容 scalar
 *   minLevel: Number,       // [drop:enemy] v1 兼容 scalar（无下界时 0）
 *   maxLevel: Number,       // [drop:enemy] v1 兼容 scalar（无上界时 999）
 *   variants: Array,        // [drop] 同一逻辑来源的 XML occurrence，有序且不折叠
 *   questId: String,        // [quest] 任务ID
 *   questTitle: String,     // [quest] 任务标题
 *   quantity: Number        // [quest] 奖励数量
 * }
 *
 * 使用示例：
 * ```actionscript
 * var index:ItemObtainIndex = ItemObtainIndex.getInstance();
 * index.buildIndex(_root.改装清单, _root.shops, _root.kshop_list,
 *     _root.竞技场掉落规则);
 * index.loadFromSave(mysave.data.obtainCache); // 加载发现集合并从最新数据重建
 * var records:Array = index.getObtainRecords("SAPS12");
 * // records = [{kind:"craft", category:"武器合成", price:10000, kprice:0}]
 * ```
 *
 * 注意：
 * - getObtainRecords() 返回 v1 兼容视图；A2 producer 才使用 exact occurrence API
 * - 如需内部 exact occurrence，请使用 getExactObtainRecords() 且不得修改
 * - 动态来源需要调用 updateStageDrops/updateEnemyDrops/updateQuestRewards 更新
 */
class org.flashNight.arki.item.obtain.ItemObtainIndex {

    // ===== 来源类型常量 =====
    public static var KIND_CRAFT:String = "craft";
    public static var KIND_SHOP:String = "shop";
    public static var KIND_KSHOP:String = "kshop";
    // 预留扩展
    public static var KIND_DROP:String = "drop";
    public static var KIND_QUEST:String = "quest";

    // ===== 单例实例 =====
    private static var instance:ItemObtainIndex = null;

    // ===== 掉落子类型常量 =====
    public static var DROP_TYPE_STAGE:String = "stage";
    public static var DROP_TYPE_ENEMY:String = "enemy";
    public static var DROP_TYPE_ARENA:String = "arena";

    // ===== 存档版本 =====
    private static var CACHE_VERSION:Number = 2;  // v2: 只存发现集合，运行时重建明细

    // ===== 状态标记 =====
    private var _isBuilt:Boolean = false;

    // ===== 核心索引数据结构 =====
    /**
     * 统一索引（运行时查询用）
     * 键: 物品名称(String)
     * 值: Array<ObtainRecord>，包含该物品的所有获取方式
     */
    private var obtainIndex:Object;

    // ===== 发现集合（存档持久化用，只存ID不存明细） =====
    /**
     * 已发现的关卡名集合
     * 键: 关卡名称(String)
     * 值: true (仅用于快速查找)
     */
    private var discoveredStages:Object;

    /**
     * 已发现的敌人兵种集合
     * 键: 敌人兵种(String)
     * 值: true (仅用于快速查找)
     */
    private var discoveredEnemies:Object;

    /**
     * 已发现的任务ID集合
     * 键: 任务ID(String)
     * 值: true (仅用于快速查找)
     */
    private var discoveredQuests:Object;

    /**
     * 已完成挑战的任务ID集合（用于恢复挑战奖励来源）
     * 键: 任务ID(String)
     * 值: true (仅用于快速查找)
     * 注意：这个集合单独存储，因为 tasks_finished 不保存 challenge.finished 状态
     */
    private var completedChallengeQuests:Object;

    // ===== 运行时缓存（不持久化，每次从最新数据重建） =====
    /**
     * 关卡掉落运行时缓存（从最新配置重建）
     * 键: 关卡名称(String)
     * 值: Array<{name:物品名, prob:概率, qty:最大数量}>
     */
    private var stageDropCache:Object;

    /**
     * 敌人掉落运行时缓存（从最新配置重建）
     * 键: 敌人兵种(String)
     * 值: Array<{名字, 概率, 最小逆向等级, 最大逆向等级}>
     */
    private var enemyDropCache:Object;

    /**
     * 任务奖励运行时缓存（从最新配置重建）
     * 键: 任务ID(String)
     * 值: {title:任务标题, rewards:Array<{item:物品名, qty:数量}>}
     */
    private var questRewardCache:Object;

    // ===== 单例模式 =====

    /**
     * 获取单例实例
     */
    public static function getInstance():ItemObtainIndex {
        if (instance == null) {
            instance = new ItemObtainIndex();
        }
        return instance;
    }

    /**
     * 私有构造函数
     */
    private function ItemObtainIndex() {
        this.obtainIndex = {};
        // 发现集合（持久化）
        this.discoveredStages = {};
        this.discoveredEnemies = {};
        this.discoveredQuests = {};
        this.completedChallengeQuests = {};
        // 运行时缓存（不持久化）
        this.stageDropCache = {};
        this.enemyDropCache = {};
        this.questRewardCache = {};
    }

    // ===== 索引构建方法 =====

    /**
     * 构建全部索引
     * 支持部分数据缺失，任一数据源为null时仍构建其他索引
     *
     * @param craftingData   合成数据 (_root.改装清单)，结构为 {分类名: [{name, title, price, kprice, materials}, ...]}
     * @param shopData       商店数据 (_root.shops)，结构为 {NPC名: {序号: 物品名或{name:物品名, requiredInfo:...}}}
     * @param kshopData      K点商店数据 (_root.kshop_list)，结构为 [{id, item, type, price}, ...]
     * @param arenaDropCatalog ArenaDropRuleCatalog.parse() 的归一化结果（可选）
     */
    public function buildIndex(craftingData:Object, shopData:Object, kshopData:Array,
                               arenaDropCatalog:Object):Void {
        if (this._isBuilt) {
            trace("[ItemObtainIndex] 索引已构建，跳过重复构建");
            return;
        }

        var startTime:Number = getTimer();

        this.buildCraftingRecords(craftingData);
        this.buildShopRecords(shopData);
        this.buildKShopRecords(kshopData);
        this.buildArenaDropRecords(arenaDropCatalog);

        this._isBuilt = true;

        var endTime:Number = getTimer();
        trace("[ItemObtainIndex] 索引构建完成，耗时 " + (endTime - startTime) + "ms");
    }

    /**
     * 从 authored arena catalog 登记静态来源。来源项与运行时 EligibleItem
     * 同源生成，因此 tooltip 不维护第二份装备名单或概率文案。
     */
    private function buildArenaDropRecords(catalog:Object):Void {
        if (catalog == null) {
            trace("[ItemObtainIndex] 竞技场掉落目录为空，跳过");
            return;
        }
        var sources:Array = catalog.sources;
        if (catalog.schemaVersion !== 1 || !(sources instanceof Array)) {
            trace("[ItemObtainIndex] 竞技场掉落目录非法，跳过");
            return;
        }

        var count:Number = 0;
        for (var i:Number = 0; i < sources.length; i++) {
            var source:Object = sources[i];
            if (source == null || typeof source.itemName != "string"
                    || typeof source.arenaId != "string"
                    || typeof source.arenaLabel != "string"
                    || typeof source.profileId != "string"
                    || typeof source.ruleId != "string"
                    || (source.carrierScope != "carrier"
                        && source.carrierScope != "specific_carrier")) continue;
            var itemName:String = source.itemName;
            if (!this.obtainIndex[itemName]) this.obtainIndex[itemName] = [];
            this.obtainIndex[itemName].push({
                kind:KIND_DROP,
                dropType:DROP_TYPE_ARENA,
                arenaId:source.arenaId,
                arenaLabel:source.arenaLabel,
                mode:source.profileId,
                modeLabel:source.modeLabel,
                ruleId:source.ruleId,
                carrierScope:source.carrierScope,
                equipmentSlot:source.slot,
                chanceModel:source.chanceModel,
                probability:Number(source.conditionalChancePercent),
                conditionalChancePercent:Number(source.conditionalChancePercent),
                selectionWeight:source.selectionWeight,
                totalWeight:source.totalWeight,
                selectedDropChancePercent:source.selectedDropChancePercent,
                quantityMin:1,
                quantityMax:1
            });
            count++;
        }
        trace("[ItemObtainIndex] 竞技场掉落来源记录构建完成，共 " + count + " 条");
    }

    /**
     * 构建合成来源记录
     */
    private function buildCraftingRecords(data:Object):Void {
        if (!data) {
            trace("[ItemObtainIndex] 合成数据为空，跳过");
            return;
        }

        var count:Number = 0;

        for (var category:String in data) {
            if (ObjectUtil.isInternalKey(category)) continue;

            var list:Array = data[category];
            if (!list || !(list instanceof Array)) continue;

            for (var i:Number = 0; i < list.length; i++) {
                var recipe:Object = list[i];
                if (!recipe || !recipe.name) continue;

                var itemName:String = recipe.name;

                // 初始化数组
                if (!this.obtainIndex[itemName]) {
                    this.obtainIndex[itemName] = [];
                }

                var existingArr:Array = this.obtainIndex[itemName];
                // recipe occurrence 才是 identity；同 category 的同名产物不能去重。
                existingArr.push({
                    kind: KIND_CRAFT,
                    category: category,
                    recipeIndex: i,
                    productName: itemName,
                    price: isNaN(Number(recipe.price)) ? 0 : Number(recipe.price),
                    kprice: isNaN(Number(recipe.kprice)) ? 0 : Number(recipe.kprice)
                });
                count++;
            }
        }

        trace("[ItemObtainIndex] 合成记录构建完成，共 " + count + " 条");
    }

    /**
     * 构建商店来源记录
     * 保留 requiredInfo 语义信息
     */
    private function buildShopRecords(data:Object):Void {
        if (!data) {
            trace("[ItemObtainIndex] 商店数据为空，跳过");
            return;
        }

        var count:Number = 0;

        for (var npcName:String in data) {
            if (ObjectUtil.isInternalKey(npcName)) continue;

            var shopItems:Object = data[npcName];
            if (!shopItems) continue;

            var slots:Array = [];
            for (var slot:String in shopItems) {
                if (ObjectUtil.isInternalKey(slot)) continue;
                var slotIndex:Number = Number(slot);
                if (isNaN(slotIndex) || Math.floor(slotIndex) != slotIndex
                        || slotIndex < 0) continue;
                slots.push(slotIndex);
            }
            slots.sort(Array.NUMERIC);

            for (var slotOffset:Number = 0; slotOffset < slots.length; slotOffset++) {
                var catalogIndex:Number = Number(slots[slotOffset]);

                var itemEntry = shopItems[String(catalogIndex)];
                if (itemEntry == undefined) itemEntry = shopItems[catalogIndex];
                var itemName:String;
                var requiredInfo:String = null;

                // 兼容两种格式
                if (typeof itemEntry === "string") {
                    itemName = itemEntry;
                } else if (itemEntry && itemEntry.name) {
                    itemName = itemEntry.name;
                    // 保留解锁条件信息
                    if (itemEntry.requiredInfo != undefined) {
                        requiredInfo = String(itemEntry.requiredInfo);
                    }
                } else {
                    continue;
                }

                // 初始化数组
                if (!this.obtainIndex[itemName]) {
                    this.obtainIndex[itemName] = [];
                }

                var existingArr:Array = this.obtainIndex[itemName];
                var record:Object = {
                    kind: KIND_SHOP,
                    // npc 保留给 v1 projector；shopId 是 A1 occurrence identity。
                    npc: npcName,
                    shopId: npcName,
                    itemName: itemName,
                    catalogIndex: catalogIndex
                };
                // 只在有值时添加 requiredInfo
                if (requiredInfo) {
                    record.requiredInfo = requiredInfo;
                }
                existingArr.push(record);
                count++;
            }
        }

        trace("[ItemObtainIndex] 商店记录构建完成，共 " + count + " 条");
    }

    /**
     * 构建K点商店来源记录
     */
    private function buildKShopRecords(data:Array):Void {
        if (!data || !(data instanceof Array)) {
            trace("[ItemObtainIndex] K点商店数据为空，跳过");
            return;
        }

        var count:Number = 0;

        for (var i:Number = 0; i < data.length; i++) {
            var entry:Object = data[i];
            if (!entry || !entry.item) continue;

            var itemName:String = entry.item;

            // 初始化数组
            if (!this.obtainIndex[itemName]) {
                this.obtainIndex[itemName] = [];
            }

            // K点商店支持同物品多条记录（可能type不同）
            this.obtainIndex[itemName].push({
                kind: KIND_KSHOP,
                catalogIndex: i,
                type: entry.type || "",
                priceK: isNaN(Number(entry.price)) ? 0 : Number(entry.price),
                id: entry.id || "",
                entryId: entry.id || ""
            });
            count++;
        }

        trace("[ItemObtainIndex] K点商店记录构建完成，共 " + count + " 条");
    }

    // ===== 查询方法 =====

    /**
     * 查询物品的 v1 兼容获取方式。
     * craft/shop/quest 保持旧 consumer 的逻辑来源去重，避免 A1 将新增 identity
     * 作为半套 wire 泄漏给现役 Crafting/tooltip；drop 已在内部按来源分组。
     * @param itemName 物品名称
     * @return Array<ObtainRecord>，若无记录返回空数组
     */
    public function getObtainRecords(itemName:String):Array {
        var exact:Array = this.obtainIndex[itemName];
        if (!exact) return [];
        var result:Array = [];
        for (var i:Number = 0; i < exact.length; i++) {
            var record:Object = exact[i];
            var duplicate:Boolean = false;
            for (var j:Number = 0; j < result.length; j++) {
                var existing:Object = result[j];
                if (record.kind === KIND_CRAFT && existing.kind === KIND_CRAFT
                        && record.category === existing.category) duplicate = true;
                else if (record.kind === KIND_SHOP && existing.kind === KIND_SHOP
                        && record.npc === existing.npc) duplicate = true;
                else if (record.kind === KIND_QUEST && existing.kind === KIND_QUEST
                        && record.questId === existing.questId) duplicate = true;
                if (duplicate) break;
            }
            if (!duplicate) result.push(record);
        }
        return result;
    }

    /**
     * A1 internal exact occurrence view；仅供后续 v2 producer 与 focused tests。
     * 返回内部引用，调用方不得修改。
     */
    public function getExactObtainRecords(itemName:String):Array {
        return this.obtainIndex[itemName] || [];
    }

    /**
     * 查询物品的所有获取方式（返回安全拷贝）
     * 性能较低，仅在需要修改返回数据时使用
     * @param itemName 物品名称
     * @return Array<ObtainRecord> 的浅拷贝
     */
    public function getObtainRecordsCopy(itemName:String):Array {
        return this.getObtainRecords(itemName).slice(0);
    }

    /**
     * 按类型筛选获取方式
     * @param itemName 物品名称
     * @param kind 来源类型（使用 KIND_* 常量）
     * @return Array<ObtainRecord> 筛选后的记录
     */
    public function getObtainRecordsByKind(itemName:String, kind:String):Array {
        var all:Array = this.getObtainRecords(itemName);

        var result:Array = [];
        for (var i:Number = 0; i < all.length; i++) {
            if (all[i].kind === kind) {
                result.push(all[i]);
            }
        }
        return result;
    }

    /**
     * 检查物品是否有任何获取方式
     * @param itemName 物品名称
     * @return Boolean
     */
    public function hasObtainMethod(itemName:String):Boolean {
        var records:Array = this.obtainIndex[itemName];
        return records != null && records.length > 0;
    }

    /**
     * 获取索引构建状态
     */
    public function isIndexBuilt():Boolean {
        return this._isBuilt;
    }

    /**
     * 重置索引（用于重新加载数据时）
     * 注意：此方法会清空静态索引（craft/shop/kshop），需要重新调用 buildIndex()
     * 如果只需清空动态发现集合，请使用 clearDynamicDiscoveries()
     * @param clearDiscoveredSets 是否同时清除发现集合，默认 false
     */
    public function reset(clearDiscoveredSets:Boolean):Void {
        this.obtainIndex = {};
        this._isBuilt = false;
        // 运行时缓存总是清空
        this.stageDropCache = {};
        this.enemyDropCache = {};
        this.questRewardCache = {};
        if (clearDiscoveredSets) {
            // 同时清除发现集合（用于新建角色/清档）
            this.discoveredStages = {};
            this.discoveredEnemies = {};
            this.discoveredQuests = {};
            this.completedChallengeQuests = {};
            trace("[ItemObtainIndex] 索引及发现集合已重置");
        } else {
            trace("[ItemObtainIndex] 索引已重置（保留发现集合）");
        }
    }

    /**
     * 清空动态发现集合（用于新建角色）
     * 保留静态索引（craft/shop/kshop/drop:arena），只清空发现制来源
     * 这是新建角色时应该调用的方法，而非 reset()
     */
    public function clearDynamicDiscoveries():Void {
        // 清空发现集合
        this.discoveredStages = {};
        this.discoveredEnemies = {};
        this.discoveredQuests = {};
        this.completedChallengeQuests = {};
        // 清空运行时缓存
        this.stageDropCache = {};
        this.enemyDropCache = {};
        this.questRewardCache = {};
        // 清理 obtainIndex 中的发现制来源，保留 authored 竞技场来源
        this.clearDynamicRecordsFromIndex();
        trace("[ItemObtainIndex] 动态发现集合已清空（静态索引保留）");
    }

    // ===== 动态缓存更新方法 =====

    /**
     * 更新关卡掉落缓存
     * 在关卡XML解析完成后调用，记录该关卡的掉落物
     * 同时标记该关卡为"已发现"（用于存档）
     *
     * @param stageName 关卡名称
     * @param rewards 掉落物数组，格式为 [[物品名, 概率, 最大数量], ...]
     *                或 [{Name, AcquisitionProbability, QuantityMax}, ...]
     * @return Boolean 是否有新增发现（首次发现返回true）
     */
    public function updateStageDrops(stageName:String, rewards:Array):Boolean {
        if (!stageName || !rewards || rewards.length == 0) return false;

        // 标记为已发现
        var isNewDiscovery:Boolean = !this.discoveredStages[stageName];
        this.discoveredStages[stageName] = true;

        // 总是重新构建运行时缓存（确保使用最新数据）
        this.rebuildStageCacheFromData(stageName, rewards);

        if (isNewDiscovery) {
            trace("[ItemObtainIndex] 关卡首次发现: " + stageName);
        }
        return isNewDiscovery;
    }

    /**
     * 从掉落数据重建关卡的运行时缓存
     * @private
     */
    private function rebuildStageCacheFromData(stageName:String, rewards:Array):Void {
        // 先清理该关卡的旧记录
        this.clearStageRecordsFromIndex(stageName);

        var dropList:Array = [];
        // exact projection 必须以“关卡 + 物品”整个逻辑来源为失败关闭单元。
        // 先收集并验证全部 occurrence，避免一个坏档被跳过后仍投影半条来源，
        // 让 A2 strict producer 无法知道 XML occurrence 已经丢失。
        var pendingSources:Array = [];
        for (var i:Number = 0; i < rewards.length; i++) {
            var reward = rewards[i];
            var itemName:String;
            var prob:Number;
            var qty:Number;

            // 兼容两种格式
            if (reward instanceof Array) {
                itemName = reward[0];
                prob = Number(reward[1]);
                qty = Number(reward[2]);
            } else if (reward && reward.Name) {
                itemName = reward.Name;
                prob = Number(reward.AcquisitionProbability);
                qty = Number(reward.QuantityMax);
            } else {
                continue;
            }

            if (!itemName) continue;

            var pending:Object = null;
            for (var pendingIndex:Number = 0;
                    pendingIndex < pendingSources.length; pendingIndex++) {
                if (pendingSources[pendingIndex].itemName === itemName) {
                    pending = pendingSources[pendingIndex];
                    break;
                }
            }
            if (pending == null) {
                pending = {itemName:itemName, valid:true, variants:[]};
                pendingSources.push(pending);
            }

            // cache 完全保留现役输入/default；grouped projection 另走严格规范化。
            var legacyDivisor:Number = isNaN(prob) ? 1 : prob;
            var legacyQty:Number = isNaN(qty) ? 1 : qty;
            dropList.push({
                name: itemName,
                prob: legacyDivisor,
                qty: legacyQty
            });

            var normalizedDivisor = normalizeStageDivisor(prob);
            var normalizedQty = normalizeStageQuantity(qty);
            if (normalizedDivisor == null || normalizedQty == null) {
                pending.valid = false;
                trace("[ItemObtainIndex] 非法关卡掉落 occurrence，逻辑来源失败关闭: "
                    + stageName + " / " + itemName + " / index=" + i);
            } else {
                pending.variants.push({divisor:normalizedDivisor, qty:normalizedQty});
            }
        }

        for (var sourceIndex:Number = 0;
                sourceIndex < pendingSources.length; sourceIndex++) {
            var source:Object = pendingSources[sourceIndex];
            if (!source.valid || source.variants.length == 0) continue;
            for (var variantIndex:Number = 0;
                    variantIndex < source.variants.length; variantIndex++) {
                var variant:Object = source.variants[variantIndex];
                this.addStageDropRecord(source.itemName, stageName,
                    variant.divisor, variant.qty);
            }
        }

        if (dropList.length > 0) {
            this.stageDropCache[stageName] = dropList;
        }
    }

    /**
     * 清理 obtainIndex 中指定关卡的掉落记录
     * @private
     */
    private function clearStageRecordsFromIndex(stageName:String):Void {
        for (var itemName:String in this.obtainIndex) {
            if (ObjectUtil.isInternalKey(itemName)) continue;
            var records:Array = this.obtainIndex[itemName];
            if (!records) continue;

            for (var i:Number = records.length - 1; i >= 0; i--) {
                var rec:Object = records[i];
                if (rec.kind === KIND_DROP && rec.dropType === DROP_TYPE_STAGE && rec.stageName === stageName) {
                    records.splice(i, 1);
                }
            }
        }
        delete this.stageDropCache[stageName];
    }

    /**
     * 更新敌人掉落缓存
     * 在首次遭遇敌人时调用，记录该敌人的掉落物
     * 同时标记该敌人为"已发现"（用于存档）
     *
     * @param enemyType 敌人兵种
     * @param drops 掉落物数组，格式为 [{名字, 概率, 最小逆向等级, 最大逆向等级}, ...]
     * @return Boolean 是否有新增发现（首次发现返回true）
     */
    public function updateEnemyDrops(enemyType:String, drops:Array):Boolean {
        if (!enemyType || !drops || drops.length == 0) return false;
        // enemyType 必须是敌人属性表中的 exact identity；展示名、剥前缀短名与
        // portrait alias 都不能反向创建已发现来源。
        var enemyTable:Object = _root.敌人属性表;
        if (enemyTable == null || typeof enemyTable.hasOwnProperty != "function"
                || !enemyTable.hasOwnProperty(enemyType)) return false;

        // 性能优化：如果已发现且已有缓存，跳过重建
        // 这样避免每只敌人初始化时都触发全索引扫描
        if (this.discoveredEnemies[enemyType] && this.enemyDropCache[enemyType]) {
            return false;
        }

        // 标记为已发现
        var isNewDiscovery:Boolean = !this.discoveredEnemies[enemyType];
        this.discoveredEnemies[enemyType] = true;

        // 仅在首次发现或缓存丢失时重建
        this.rebuildEnemyCacheFromData(enemyType, drops);

        if (isNewDiscovery) {
            trace("[ItemObtainIndex] 敌人首次发现: " + enemyType);
        }
        return isNewDiscovery;
    }

    /**
     * 从掉落数据重建敌人的运行时缓存
     * @private
     */
    private function rebuildEnemyCacheFromData(enemyType:String, drops:Array):Void {
        // 先清理该敌人的旧记录
        this.clearEnemyRecordsFromIndex(enemyType);

        var dropList:Array = [];
        // exact projection 以“敌人 + 物品”整个逻辑来源为失败关闭单元；
        // 任一 occurrence 非法时，不允许留下只含合法 siblings 的部分来源。
        var pendingSources:Array = [];
        for (var i:Number = 0; i < drops.length; i++) {
            var drop = drops[i];
            if (!drop || !drop.名字) continue;

            var itemName:String = drop.名字;
            var pending:Object = null;
            for (var pendingIndex:Number = 0;
                    pendingIndex < pendingSources.length; pendingIndex++) {
                if (pendingSources[pendingIndex].itemName === itemName) {
                    pending = pendingSources[pendingIndex];
                    break;
                }
            }
            if (pending == null) {
                pending = {itemName:itemName, valid:true, variants:[]};
                pendingSources.push(pending);
            }
            var prob:Number = Number(drop.概率);
            var minLv:Number = Number(drop.最小逆向等级);
            var maxLv:Number = Number(drop.最大逆向等级);
            var quantity:Object = normalizeEnemyQuantity(drop);
            var hasChance:Boolean = typeof drop.hasOwnProperty == "function"
                && drop.hasOwnProperty("概率");
            var chance:Object = normalizeEnemyChance(hasChance, prob);
            var minBound:Object = normalizeReverseLevel(minLv);
            var maxBound:Object = normalizeReverseLevel(maxLv);

            dropList.push({
                名字: itemName,
                // enemyDropCache 保持现役 v1 shape/默认值；A1 的 100% 缺省
                // 语义只进入 grouped obtain variant，不借正确性修复改变旧 cache。
                概率: isNaN(prob) ? 1 : prob,
                最小逆向等级: isNaN(minLv) ? 0 : minLv,
                最大逆向等级: isNaN(maxLv) ? 999 : maxLv
            });

            var validBounds:Boolean = minBound.valid && maxBound.valid
                && (minBound.value == null || maxBound.value == null
                    || Number(minBound.value) <= Number(maxBound.value));
            if (chance == null || quantity == null || !validBounds) {
                pending.valid = false;
                trace("[ItemObtainIndex] 非法敌人掉落 occurrence，逻辑来源失败关闭: "
                    + enemyType + " / " + itemName + " / index=" + i);
            } else {
                pending.variants.push({
                    chance:chance,
                    minReverseLevel:minBound.value,
                    maxReverseLevel:maxBound.value,
                    quantity:quantity
                });
            }
        }

        for (var sourceIndex:Number = 0;
                sourceIndex < pendingSources.length; sourceIndex++) {
            var source:Object = pendingSources[sourceIndex];
            if (!source.valid || source.variants.length == 0) continue;
            for (var variantIndex:Number = 0;
                    variantIndex < source.variants.length; variantIndex++) {
                var variant:Object = source.variants[variantIndex];
                this.addEnemyDropRecord(source.itemName, enemyType,
                    variant.chance, variant.minReverseLevel,
                    variant.maxReverseLevel, variant.quantity);
            }
        }

        if (dropList.length > 0) {
            this.enemyDropCache[enemyType] = dropList;
        }
    }

    /**
     * 清理 obtainIndex 中指定敌人的掉落记录
     * @private
     */
    private function clearEnemyRecordsFromIndex(enemyType:String):Void {
        for (var itemName:String in this.obtainIndex) {
            if (ObjectUtil.isInternalKey(itemName)) continue;
            var records:Array = this.obtainIndex[itemName];
            if (!records) continue;

            for (var i:Number = records.length - 1; i >= 0; i--) {
                var rec:Object = records[i];
                if (rec.kind === KIND_DROP && rec.dropType === DROP_TYPE_ENEMY && rec.enemyType === enemyType) {
                    records.splice(i, 1);
                }
            }
        }
        delete this.enemyDropCache[enemyType];
    }

    /**
     * 更新任务奖励缓存
     * 在任务接取或完成时调用，记录该任务的奖励
     * 同时标记该任务为"已发现"（用于存档）
     *
     * @param questId 任务ID
     * @param questTitle 任务标题
     * @param rewards 奖励数组，格式为 ["物品名#数量", ...] 或 [{item, qty}, ...]
     * @return Boolean 是否有新增发现（首次发现返回true）
     */
    public function updateQuestRewards(questId:String, questTitle, rewards:Array):Boolean {
        if (!questId || !rewards || rewards.length == 0) return false;

        // 标记为已发现
        var isNewDiscovery:Boolean = !this.discoveredQuests[questId];
        this.discoveredQuests[questId] = true;

        // 总是重新构建运行时缓存（确保使用最新数据）
        this.rebuildQuestCacheFromData(questId, questTitle, rewards);

        if (isNewDiscovery) {
            trace("[ItemObtainIndex] 任务首次发现: " + questId);
        }
        return isNewDiscovery;
    }

    /**
     * 从奖励数据重建任务的运行时缓存
     * @private
     */
    private function rebuildQuestCacheFromData(questId:String, questTitle, rewards:Array):Void {
        var existing:Object = this.questRewardCache[questId];
        var challengeRewards:Array = existing != null
                && existing.challengeRewards instanceof Array
            ? existing.challengeRewards : [];
        this.questRewardCache[questId] = {
            // 保留“是否真的有展示标题”的来源信息；展示回填只允许在
            // CraftingPanelService 的 authority projection 边界发生。
            title: questTitle == undefined && existing != null
                ? existing.title : questTitle,
            baseRewards: this.parseQuestRewards(rewards, "base"),
            challengeRewards: challengeRewards,
            rewards: []
        };
        this.rebuildQuestRecordsFromCache(questId);
    }

    /** 解析一个 authored reward set；authoredIndex 永远使用原数组下标。 */
    private function parseQuestRewards(rewards:Array, rewardSet:String):Array {
        var result:Array = [];
        if (!(rewards instanceof Array)) return result;
        for (var i:Number = 0; i < rewards.length; i++) {
            var reward = rewards[i];
            var itemName:String;
            var qty:Number;
            if (typeof reward === "string") {
                var parts:Array = reward.split("#");
                itemName = parts[0];
                qty = parts.length > 1 ? Number(parts[1]) : 1;
            } else if (reward && reward.item) {
                itemName = reward.item;
                qty = Number(reward.qty);
            } else {
                continue;
            }
            if (!itemName) continue;
            var normalizedQty = normalizeQuestQuantity(qty);
            if (normalizedQty == null) {
                trace("[ItemObtainIndex] 忽略非法任务奖励 occurrence: "
                    + rewardSet + " / " + itemName + " / index=" + i);
                continue;
            }
            result.push({item:itemName, qty:normalizedQty,
                rewardSet:rewardSet, authoredIndex:i});
        }
        return result;
    }

    private function normalizeQuestQuantity(value:Number) {
        if (isNaN(value)) return 1;
        if ((value - value) != 0 || value <= 0 || Math.floor(value) != value) return null;
        return value;
    }

    /** base 始终先于 challenge 投影；只替换指定 set 时不会吞掉另一个 set。 */
    private function rebuildQuestRecordsFromCache(questId:String):Void {
        var cache:Object = this.questRewardCache[questId];
        if (cache == null) return;
        this.clearQuestRecordsFromIndex(questId);
        var combined:Array = [];
        var sets:Array = [cache.baseRewards || [], cache.challengeRewards || []];
        for (var setIndex:Number = 0; setIndex < sets.length; setIndex++) {
            var rewards:Array = sets[setIndex];
            for (var i:Number = 0; i < rewards.length; i++) {
                var reward:Object = rewards[i];
                combined.push(reward);
                this.addQuestRecord(String(reward.item), questId, cache.title,
                    Number(reward.qty), String(reward.rewardSet),
                    Number(reward.authoredIndex));
            }
        }
        cache.rewards = combined;
    }

    private function sameQuestRewardSet(left:Array, right:Array):Boolean {
        if (left.length != right.length) return false;
        for (var i:Number = 0; i < left.length; i++) {
            if (left[i].item !== right[i].item
                    || Number(left[i].qty) != Number(right[i].qty)
                    || left[i].rewardSet !== right[i].rewardSet
                    || Number(left[i].authoredIndex) != Number(right[i].authoredIndex)) {
                return false;
            }
        }
        return true;
    }

    /**
     * 清理 obtainIndex 中指定任务的奖励记录
     * @private
     */
    private function clearQuestRecordsFromIndex(questId:String):Void {
        for (var itemName:String in this.obtainIndex) {
            if (ObjectUtil.isInternalKey(itemName)) continue;
            var records:Array = this.obtainIndex[itemName];
            if (!records) continue;

            for (var i:Number = records.length - 1; i >= 0; i--) {
                var rec:Object = records[i];
                if (rec.kind === KIND_QUEST && rec.questId === questId) {
                    records.splice(i, 1);
                }
            }
        }
    }

    /**
     * 追加任务奖励到已有记录（用于挑战奖励等后续发现的奖励）
     * 如果任务不存在则建立仅含 challenge 的 cache；按 authored occurrence
     * identity 幂等追加，不再按 itemName 吞掉重复奖励。
     *
     * @param questId 任务ID
     * @param questTitle 任务标题
     * @param additionalRewards 追加的奖励数组，格式同 updateQuestRewards
     * @param markChallengeCompleted 是否标记为挑战已完成（用于存档恢复），默认 true
     * @return Boolean 是否有新增记录
     */
    public function appendQuestRewards(questId:String, questTitle, additionalRewards:Array, markChallengeCompleted:Boolean):Boolean {
        if (!questId || !additionalRewards || additionalRewards.length == 0) return false;

        // 默认标记挑战完成（用于交任务时的挑战奖励追加）
        if (markChallengeCompleted == undefined || markChallengeCompleted == true) {
            this.completedChallengeQuests[questId] = true;
        }

        this.discoveredQuests[questId] = true;

        // challenge 可能在 base cache 不可用时恢复；不能把它误标成 base。
        if (!this.questRewardCache[questId]) {
            this.questRewardCache[questId] = {
                title:questTitle, baseRewards:[], challengeRewards:[], rewards:[]};
        }

        var existingCache:Object = this.questRewardCache[questId];
        var parsed:Array = this.parseQuestRewards(additionalRewards, "challenge");
        var changed:Boolean = !this.sameQuestRewardSet(
            existingCache.challengeRewards || [], parsed);
        var titleChanged:Boolean = questTitle != undefined
            && questTitle !== existingCache.title;
        existingCache.challengeRewards = parsed;
        if (questTitle != undefined) existingCache.title = questTitle;
        if (changed || titleChanged) this.rebuildQuestRecordsFromCache(questId);
        if (changed) {
            trace("[ItemObtainIndex] 挑战奖励 occurrence 已同步: "
                + questId + ", " + parsed.length + " 项");
        }
        return changed;
    }

    /** 查找同一逻辑掉落来源；不同 occurrence 进入同一记录的 variants。 */
    private function findDropRecord(arr:Array, dropType:String, sourceName:String):Object {
        for (var i:Number = 0; i < arr.length; i++) {
            var rec:Object = arr[i];
            if (rec.kind !== KIND_DROP || rec.dropType !== dropType) continue;
            if (dropType === DROP_TYPE_STAGE && rec.stageName === sourceName) return rec;
            if (dropType === DROP_TYPE_ENEMY && rec.enemyType === sourceName) return rec;
        }
        return null;
    }

    /** 添加一个关卡掉落 occurrence；v1 scalar 永远镜像首档。 */
    private function addStageDropRecord(itemName:String, stageName:String,
                                        divisor:Number, qty:Number):Void {
        if (!this.obtainIndex[itemName]) {
            this.obtainIndex[itemName] = [];
        }

        var arr:Array = this.obtainIndex[itemName];
        var record:Object = findDropRecord(arr, DROP_TYPE_STAGE, stageName);
        if (record == null) {
            record = {
                kind: KIND_DROP,
                dropType: DROP_TYPE_STAGE,
                stageName: stageName,
                chanceModel: "stage_roll_divisor_with_legacy_domain_branch",
                legacyConditionId: "andylaw_domain_bonus",
                probability: divisor,
                quantityMax: qty,
                variants: []
            };
            arr.push(record);
        }
        var occurrenceIndex:Number = record.variants.length;
        record.variants.push({
            occurrenceIndex: occurrenceIndex,
            rollDivisor: divisor,
            defaultBranchChancePercent: round6(100 / divisor),
            quantityMin: 1,
            quantityMax: qty
        });
    }

    /** 添加一个敌人掉落 occurrence；保留概率输入状态与 nullable 逆向边界。 */
    private function addEnemyDropRecord(itemName:String, enemyType:String,
                                        chance:Object, minReverseLevel, maxReverseLevel,
                                        quantity:Object):Void {
        if (!this.obtainIndex[itemName]) {
            this.obtainIndex[itemName] = [];
        }

        var arr:Array = this.obtainIndex[itemName];
        var record:Object = findDropRecord(arr, DROP_TYPE_ENEMY, enemyType);
        if (record == null) {
            record = {
                kind: KIND_DROP,
                dropType: DROP_TYPE_ENEMY,
                enemyType: enemyType,
                chanceModel: "enemy_prd_with_reverse_bonus",
                probability: chance.nominalChancePercent,
                minLevel: minReverseLevel == null ? 0 : minReverseLevel,
                maxLevel: maxReverseLevel == null ? 999 : maxReverseLevel,
                quantityMin: quantity.min,
                quantityMax: quantity.max,
                variants: []
            };
            arr.push(record);
        }
        var occurrenceIndex:Number = record.variants.length;
        record.variants.push({
            occurrenceIndex: occurrenceIndex,
            chanceRaw: chance.chanceRaw,
            chanceInputState: chance.chanceInputState,
            nominalChancePercent: chance.nominalChancePercent,
            minReverseLevel: minReverseLevel,
            maxReverseLevel: maxReverseLevel,
            quantityMin: quantity.min,
            quantityMax: quantity.max
        });
    }

    /** 关卡奖励概率是 random(N)==0 的正整数分母；非法值不进入 exact projection。 */
    private function normalizeStageDivisor(value:Number) {
        if (isNaN(value) || (value - value) != 0
                || value <= 0 || Math.floor(value) != value) return null;
        return value;
    }

    /** 关卡配置仅给最大数量；缺省按 1，非法 finite 值 fail closed。 */
    private function normalizeStageQuantity(value:Number) {
        if (isNaN(value)) return 1;
        if ((value - value) != 0 || value <= 0 || Math.floor(value) != value) return null;
        return value;
    }

    private function round6(value:Number):Number {
        return Math.round(value * 1000000) / 1000000;
    }

    /** 敌人概率按 DropLuckRoller：缺失/NaN 按 100% 默认；Infinity/越界失败关闭。 */
    private function normalizeEnemyChance(hasChance:Boolean, value:Number):Object {
        if (!hasChance) {
            return {chanceRaw:null, chanceInputState:"absent_defaulted",
                nominalChancePercent:100};
        }
        if (isNaN(value)) {
            return {chanceRaw:null, chanceInputState:"invalid_defaulted",
                nominalChancePercent:100};
        }
        if ((value - value) != 0 || value < 0 || value > 100) return null;
        return {chanceRaw:value, chanceInputState:"explicit",
            nominalChancePercent:value};
    }

    /** 未配置逆向边界表示无界；非法 finite 值不能伪装为 null。 */
    private function normalizeReverseLevel(value:Number):Object {
        if (isNaN(value)) return {valid:true, value:null};
        if ((value - value) != 0 || value < 0 || Math.floor(value) != value) {
            return {valid:false, value:null};
        }
        return {valid:true, value:value};
    }

    /** 与现役敌人掉落一致：任一数量端不可数时，整对回落 1/1。 */
    private function normalizeEnemyQuantity(drop:Object):Object {
        var minQty:Number = Number(drop.最小数量);
        var maxQty:Number = Number(drop.最大数量);
        if (isNaN(minQty) || isNaN(maxQty)) return {min:1, max:1};
        if ((minQty - minQty) != 0 || (maxQty - maxQty) != 0
                || minQty <= 0 || maxQty <= 0
                || Math.floor(minQty) != minQty || Math.floor(maxQty) != maxQty
                || minQty > maxQty) return null;
        return {min:minQty, max:maxQty};
    }

    /**
     * 添加任务奖励记录到运行时索引
     * @private
     */
    private function addQuestRecord(itemName:String, questId:String, questTitle, qty:Number,
                                    rewardSet:String, authoredIndex:Number):Void {
        if (!this.obtainIndex[itemName]) {
            this.obtainIndex[itemName] = [];
        }

        // 相同任务中 base/challenge 各自按 authoredIndex 保留 occurrence。
        var arr:Array = this.obtainIndex[itemName];
        for (var i:Number = 0; i < arr.length; i++) {
            if (arr[i].kind === KIND_QUEST && arr[i].questId === questId
                    && arr[i].rewardSet === rewardSet
                    && Number(arr[i].authoredIndex) == authoredIndex) return;
        }

        arr.push({
            kind: KIND_QUEST,
            questId: questId,
            // 不在索引层把内部 ID 伪装成展示标题，否则 projection 无法
            // 区分“合法显式同值”与“缺失后猜测内部 ID”。
            questTitle: questTitle,
            quantity: isNaN(qty) ? 1 : qty,
            rewardSet: rewardSet,
            authoredIndex: authoredIndex
        });
    }

    // ===== 存档导入导出 =====

    /**
     * 导出发现集合用于存档（v2：只存ID，不存明细）
     * @return Object 可序列化的发现集合数据
     */
    public function exportToSave():Object {
        // 将 Object 形式的集合转为 Array 形式（节省存档空间）
        var stageList:Array = [];
        for (var stageName:String in this.discoveredStages) {
            if (ObjectUtil.isInternalKey(stageName)) continue;
            stageList.push(stageName);
        }

        var enemyList:Array = [];
        for (var enemyType:String in this.discoveredEnemies) {
            if (ObjectUtil.isInternalKey(enemyType)) continue;
            enemyList.push(enemyType);
        }

        var questList:Array = [];
        for (var questId:String in this.discoveredQuests) {
            if (ObjectUtil.isInternalKey(questId)) continue;
            questList.push(questId);
        }

        // 已完成挑战的任务列表（用于恢复挑战奖励来源）
        var challengeList:Array = [];
        for (var challengeQuestId:String in this.completedChallengeQuests) {
            if (ObjectUtil.isInternalKey(challengeQuestId)) continue;
            challengeList.push(challengeQuestId);
        }

        return {
            version: CACHE_VERSION,
            discoveredStages: stageList,
            discoveredEnemies: enemyList,
            discoveredQuests: questList,
            completedChallengeQuests: challengeList
        };
    }

    /**
     * 从存档加载发现集合，并从最新配置数据重建运行时缓存
     *
     * v2策略：存档只保存"已发现"的来源ID列表，运行时从最新配置重建明细。
     * 这样配置更新后，玩家能看到最新的掉落/奖励信息。
     *
     * 重建时机：
     * - 敌人：直接从 _root.敌人属性表 获取掉落数据
     * - 任务：直接从 TaskUtil.tasks 获取奖励数据
     * - 关卡：标记已发现，等进入关卡时按需重建（关卡数据较大，不预加载）
     *
     * @param data 存档中的发现集合数据（可为null，此时仅清空动态数据）
     */
    public function loadFromSave(data:Object):Void {
        var startTime:Number = getTimer();

        // ===== 1. 无条件清理所有动态数据 =====
        this.discoveredStages = {};
        this.discoveredEnemies = {};
        this.discoveredQuests = {};
        this.completedChallengeQuests = {};
        this.stageDropCache = {};
        this.enemyDropCache = {};
        this.questRewardCache = {};
        this.clearDynamicRecordsFromIndex();

        if (!data) {
            trace("[ItemObtainIndex] 存档中无发现集合数据，已清空动态记录");
            return;
        }

        // ===== 2. 版本检查与迁移 =====
        var version:Number = data.version || 0;
        if (version < 2) {
            // v1 迁移到 v2：从旧格式提取发现集合
            trace("[ItemObtainIndex] 检测到v1存档，正在迁移到v2格式...");
            this.migrateFromV1(data);
        } else {
            // v2 格式：直接加载发现集合
            this.loadDiscoveredSetsFromV2(data);
        }

        // ===== 3. 从最新配置数据重建运行时缓存 =====
        var enemyCount:Number = this.rebuildEnemyDropsFromConfig();
        var questCount:Number = this.rebuildQuestRewardsFromConfig();
        // 关卡掉落延迟重建（进入关卡时触发）
        var stageCount:Number = this.countDiscoveredStages();

        // ===== 4. 从 completedChallengeQuests 恢复挑战奖励 =====
        var challengeCount:Number = this.rebuildChallengeRewardsFromSavedSet();

        var endTime:Number = getTimer();
        trace("[ItemObtainIndex] 从存档加载发现集合完成: "
            + stageCount + " 关卡(待重建), "
            + enemyCount + " 敌人(已重建), "
            + questCount + " 任务(已重建), "
            + challengeCount + " 挑战奖励(已恢复), "
            + "耗时 " + (endTime - startTime) + "ms");
    }

    /**
     * 在 boot 的任务表与敌人配置均已就绪后，按当前配置幂等恢复发现制来源。
     * 存档恢复早于这些异步 provider 时，loadFromSave() 会保留发现集合但跳过
     * 记录重建；S9 handoff 前必须补跑本方法。关卡继续维持进入关卡时延迟重建。
     */
    public function rehydrateDiscoveredRecordsFromCurrentConfig():Void {
        var enemyCount:Number = this.rebuildEnemyDropsFromConfig();
        var questCount:Number = this.rebuildQuestRewardsFromConfig();
        var challengeCount:Number = this.rebuildChallengeRewardsFromSavedSet();
        trace("[ItemObtainIndex] 当前配置发现来源恢复完成: "
            + enemyCount + " 敌人, " + questCount + " 任务, "
            + challengeCount + " 挑战奖励; 关卡保持延迟重建");
    }

    /**
     * 从v1格式迁移到v2格式
     * v1存储完整的掉落/奖励明细，v2只存发现集合
     * @private
     */
    private function migrateFromV1(data:Object):Void {
        // 从 stages 对象键提取关卡名
        if (data.stages) {
            for (var stageName:String in data.stages) {
                if (ObjectUtil.isInternalKey(stageName)) continue;
                this.discoveredStages[stageName] = true;
            }
        }

        // 从 enemies 对象键提取敌人兵种
        if (data.enemies) {
            for (var enemyType:String in data.enemies) {
                if (ObjectUtil.isInternalKey(enemyType)) continue;
                this.discoveredEnemies[enemyType] = true;
            }
        }

        // 从 quests 对象键提取任务ID
        if (data.quests) {
            for (var questId:String in data.quests) {
                if (ObjectUtil.isInternalKey(questId)) continue;
                this.discoveredQuests[questId] = true;
            }
        }

        trace("[ItemObtainIndex] v1->v2迁移完成");
    }

    /**
     * 从v2格式加载发现集合
     * @private
     */
    private function loadDiscoveredSetsFromV2(data:Object):Void {
        // 加载关卡发现集合
        if (data.discoveredStages && data.discoveredStages instanceof Array) {
            for (var i:Number = 0; i < data.discoveredStages.length; i++) {
                var stageName:String = data.discoveredStages[i];
                if (stageName) this.discoveredStages[stageName] = true;
            }
        }

        // 加载敌人发现集合
        if (data.discoveredEnemies && data.discoveredEnemies instanceof Array) {
            for (var j:Number = 0; j < data.discoveredEnemies.length; j++) {
                var enemyType:String = data.discoveredEnemies[j];
                if (enemyType) this.discoveredEnemies[enemyType] = true;
            }
        }

        // 加载任务发现集合
        if (data.discoveredQuests && data.discoveredQuests instanceof Array) {
            for (var k:Number = 0; k < data.discoveredQuests.length; k++) {
                var questId:String = data.discoveredQuests[k];
                if (questId) this.discoveredQuests[questId] = true;
            }
        }

        // 加载已完成挑战的任务集合
        if (data.completedChallengeQuests && data.completedChallengeQuests instanceof Array) {
            for (var c:Number = 0; c < data.completedChallengeQuests.length; c++) {
                var challengeQuestId:String = data.completedChallengeQuests[c];
                if (challengeQuestId) this.completedChallengeQuests[challengeQuestId] = true;
            }
        }
    }

    /**
     * 从最新的敌人配置数据重建已发现敌人的掉落缓存
     * @private
     * @return Number 重建的敌人数量
     */
    private function rebuildEnemyDropsFromConfig():Number {
        var count:Number = 0;
        var enemyPropsTable:Object = _root.敌人属性表;

        if (!enemyPropsTable) {
            trace("[ItemObtainIndex] 敌人属性表未加载，跳过敌人掉落重建");
            return 0;
        }

        for (var enemyType:String in this.discoveredEnemies) {
            if (ObjectUtil.isInternalKey(enemyType)) continue;

            var enemyProps:Object = enemyPropsTable[enemyType];
            if (!enemyProps || !enemyProps.掉落物 || enemyProps.掉落物 == "null") continue;

            // 解析掉落物配置
            var dropsArr:Array;
            if (enemyProps.掉落物 instanceof Array) {
                dropsArr = enemyProps.掉落物;
            } else if (typeof _root.配置数据为数组 == "function") {
                dropsArr = _root.配置数据为数组(enemyProps.掉落物);
            } else {
                dropsArr = [enemyProps.掉落物];
            }
            if (!dropsArr || dropsArr.length == 0) continue;

            // 重建缓存（使用内部方法，不重复标记发现）
            this.rebuildEnemyCacheFromData(enemyType, dropsArr);
            count++;
        }

        return count;
    }

    /**
     * 从最新的任务配置数据重建已发现任务的奖励缓存
     * @private
     * @return Number 重建的任务数量
     */
    private function rebuildQuestRewardsFromConfig():Number {
        var count:Number = 0;

        // 尝试获取任务数据（兼容不同的全局变量名）
        var tasksData:Array = null;
        if (_global.org && _global.org.flashNight && _global.org.flashNight.arki &&
            _global.org.flashNight.arki.task && _global.org.flashNight.arki.task.TaskUtil) {
            tasksData = _global.org.flashNight.arki.task.TaskUtil.tasks;
        }

        if (!tasksData) {
            trace("[ItemObtainIndex] 任务数据未加载，跳过任务奖励重建");
            return 0;
        }

        for (var questIdStr:String in this.discoveredQuests) {
            if (ObjectUtil.isInternalKey(questIdStr)) continue;

            var questId:Number = Number(questIdStr);
            if (isNaN(questId) || questId < 0 || questId >= tasksData.length) continue;

            var taskData:Object = tasksData[questId];
            if (!taskData || !taskData.rewards || taskData.rewards.length == 0) continue;

            // 保留展示标题的原始来源状态，不把内部 questId 预先伪装成标题，
            // 也不让 TaskUtil 的错误类型结果在进入 projection 前被 String 强转。
            var rawQuestTitle = taskData.title;
            var questTitle = undefined;
            if (typeof rawQuestTitle == "string") {
                questTitle = rawQuestTitle;
                if (_global.org.flashNight.arki.task.TaskUtil.getTaskText) {
                    var resolvedQuestTitle = _global.org.flashNight.arki.task.TaskUtil
                        .getTaskText(rawQuestTitle);
                    questTitle = typeof resolvedQuestTitle == "string"
                        ? resolvedQuestTitle : undefined;
                }
            }

            // 只使用基础奖励重建缓存
            // 挑战奖励只有在玩家完成挑战时通过 appendQuestRewards() 动态添加
            // 这样可以避免提前剧透挑战奖励内容
            var baseRewards:Array = taskData.rewards.slice(0);

            // 重建缓存（仅基础奖励）
            this.rebuildQuestCacheFromData(questIdStr, questTitle, baseRewards);
            count++;
        }

        return count;
    }

    /**
     * 从保存的 completedChallengeQuests 集合恢复挑战奖励
     * 在 loadFromSave() 中调用，此时任务配置数据应已就绪
     * @private
     * @return Number 恢复的挑战奖励任务数量
     */
    private function rebuildChallengeRewardsFromSavedSet():Number {
        var count:Number = 0;

        // 尝试获取任务配置数据
        var tasksData:Array = null;
        var TaskUtil:Object = null;
        if (_global.org && _global.org.flashNight && _global.org.flashNight.arki &&
            _global.org.flashNight.arki.task && _global.org.flashNight.arki.task.TaskUtil) {
            TaskUtil = _global.org.flashNight.arki.task.TaskUtil;
            tasksData = TaskUtil.tasks;
        }

        if (!tasksData) {
            trace("[ItemObtainIndex] 任务数据未加载，跳过挑战奖励恢复");
            return 0;
        }

        // 遍历已完成挑战的任务ID集合
        for (var questIdStr:String in this.completedChallengeQuests) {
            if (ObjectUtil.isInternalKey(questIdStr)) continue;

            var questId:Number = Number(questIdStr);
            if (isNaN(questId) || questId < 0 || questId >= tasksData.length) continue;

            var taskData:Object = tasksData[questId];
            if (!taskData || !taskData.challenge ||
                !taskData.challenge.rewards || taskData.challenge.rewards.length == 0) continue;

            // 保留展示标题的原始来源状态，不把内部 questId 预先伪装成标题，
            // 也不让 TaskUtil 的错误类型结果在进入 projection 前被 String 强转。
            var rawQuestTitle = taskData.title;
            var questTitle = undefined;
            if (typeof rawQuestTitle == "string") {
                questTitle = rawQuestTitle;
                if (TaskUtil.getTaskText) {
                    var resolvedQuestTitle = TaskUtil.getTaskText(rawQuestTitle);
                    questTitle = typeof resolvedQuestTitle == "string"
                        ? resolvedQuestTitle : undefined;
                }
            }

            // 追加挑战奖励（不再重复标记，因为已在集合中）
            var added:Boolean = this.appendQuestRewards(
                questIdStr,
                questTitle,
                taskData.challenge.rewards,
                false  // 不重复标记，只恢复奖励
            );
            if (added) {
                count++;
            }
        }

        return count;
    }

    /**
     * 统计已发现的关卡数量
     * @private
     */
    private function countDiscoveredStages():Number {
        var count:Number = 0;
        for (var stageName:String in this.discoveredStages) {
            if (ObjectUtil.isInternalKey(stageName)) continue;
            count++;
        }
        return count;
    }

    /**
     * 清理 obtainIndex 中的所有动态来源记录
     * 保留静态来源（craft/shop/kshop/drop:arena），移除发现制来源
     * @private
     */
    private function clearDynamicRecordsFromIndex():Void {
        var itemsCleared:Number = 0;
        var recordsRemoved:Number = 0;

        for (var itemName:String in this.obtainIndex) {
            if (ObjectUtil.isInternalKey(itemName)) continue;

            var records:Array = this.obtainIndex[itemName];
            if (!records || records.length == 0) continue;

            // stage/enemy/quest 依赖发现集合；arena 是启动期 authored 静态来源。
            var filtered:Array = [];
            for (var i:Number = 0; i < records.length; i++) {
                var record:Object = records[i];
                var isDynamicDrop:Boolean = record.kind === KIND_DROP
                    && record.dropType !== DROP_TYPE_ARENA;
                if (!isDynamicDrop && record.kind !== KIND_QUEST) {
                    filtered.push(record);
                } else {
                    recordsRemoved++;
                }
            }

            if (filtered.length !== records.length) {
                itemsCleared++;
                if (filtered.length > 0) {
                    this.obtainIndex[itemName] = filtered;
                } else {
                    delete this.obtainIndex[itemName];
                }
            }
        }

        if (recordsRemoved > 0) {
            trace("[ItemObtainIndex] 已清理动态来源记录: " + recordsRemoved + " 条 (涉及 " + itemsCleared + " 个物品)");
        }
    }

    /**
     * 检查关卡是否已被发现
     */
    public function isStageDiscovered(stageName:String):Boolean {
        return this.discoveredStages[stageName] == true;
    }

    /**
     * 检查敌人是否已被发现
     */
    public function isEnemyDiscovered(enemyType:String):Boolean {
        return this.discoveredEnemies[enemyType] == true;
    }

    /**
     * 检查任务是否已被发现
     */
    public function isQuestDiscovered(questId:String):Boolean {
        return this.discoveredQuests[questId] == true;
    }

    // ===== 兼容性方法（便于 tooltip 等消费方使用） =====

    /**
     * 获取分组后的获取方式（兼容旧接口）
     * @param itemName 物品名称
     * @return {crafting: Array, shops: Array, kshop: Array}
     * @deprecated 建议直接使用 getObtainRecords() 或 getObtainRecordsByKind()
     */
    public function getObtainMethods(itemName:String):Object {
        var all:Array = this.getObtainRecords(itemName);
        var crafting:Array = [];
        var shops:Array = [];
        var kshop:Array = [];

        for (var i:Number = 0; i < all.length; i++) {
            var record:Object = all[i];
            switch (record.kind) {
                case KIND_CRAFT:
                    crafting.push({
                        category: record.category,
                        price: record.price,
                        kprice: record.kprice
                    });
                    break;
                case KIND_SHOP:
                    shops.push(record.npc);
                    break;
                case KIND_KSHOP:
                    kshop.push({
                        type: record.type,
                        price: record.priceK,
                        id: record.id
                    });
                    break;
            }
        }

        return {
            crafting: crafting,
            shops: shops,
            kshop: kshop
        };
    }
}
