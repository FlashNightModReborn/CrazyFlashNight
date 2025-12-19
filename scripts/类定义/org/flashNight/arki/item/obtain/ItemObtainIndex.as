import org.flashNight.gesh.object.ObjectUtil;

/**
 * ItemObtainIndex - 物品来源/经济数据索引
 *
 * 职责：
 * - 在游戏启动时构建反向索引，将物品名映射到其所有获取方式
 * - 提供O(1)复杂度的查询接口
 * - 支持合成、NPC商店、K点商店三种获取来源（可扩展）
 * - 支持动态来源：关卡掉落、敌人掉落、任务奖励（运行时增量发现）
 * - 保留完整语义信息（如商店的解锁条件）
 *
 * 数据模型：
 * - 统一使用 ObtainRecord 格式，每条记录带 kind 标识类型
 * - 静态来源（craft/shop/kshop）：启动时一次性构建
 * - 动态来源（drop/quest）：运行时增量发现，存档持久化
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
 *   // ===== 动态来源字段 =====
 *   dropType: String,       // [drop] "stage" | "enemy"
 *   stageName: String,      // [drop:stage] 关卡名称
 *   enemyType: String,      // [drop:enemy] 敌人兵种
 *   probability: Number,    // [drop] 掉落概率
 *   quantityMax: Number,    // [drop:stage] 最大数量
 *   minLevel: Number,       // [drop:enemy] 最小逆向等级
 *   maxLevel: Number,       // [drop:enemy] 最大逆向等级
 *   questId: String,        // [quest] 任务ID
 *   questTitle: String,     // [quest] 任务标题
 *   quantity: Number        // [quest] 奖励数量
 * }
 *
 * 使用示例：
 * ```actionscript
 * var index:ItemObtainIndex = ItemObtainIndex.getInstance();
 * index.buildIndex(_root.改装清单, _root.shops, _root.kshop_list);
 * index.loadFromSave(mysave.data.obtainCache); // 加载发现集合并从最新数据重建
 * var records:Array = index.getObtainRecords("SAPS12");
 * // records = [{kind:"craft", category:"武器合成", price:10000, kprice:0}]
 * ```
 *
 * 注意：
 * - getObtainRecords() 返回的是内部数组的引用，调用方请勿修改
 * - 如需安全拷贝，请使用 getObtainRecordsCopy()
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
     * @param shopData       商店数据 (_root.shops)，结构为 {NPC名: {序号: 物品名或{name:物品名, requiredInfo_disabled:...}}}
     * @param kshopData      K点商店数据 (_root.kshop_list)，结构为 [{id, item, type, price}, ...]
     */
    public function buildIndex(craftingData:Object, shopData:Object, kshopData:Array):Void {
        if (this._isBuilt) {
            trace("[ItemObtainIndex] 索引已构建，跳过重复构建");
            return;
        }

        var startTime:Number = getTimer();

        this.buildCraftingRecords(craftingData);
        this.buildShopRecords(shopData);
        this.buildKShopRecords(kshopData);

        this._isBuilt = true;

        var endTime:Number = getTimer();
        trace("[ItemObtainIndex] 索引构建完成，耗时 " + (endTime - startTime) + "ms");
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

                // 检查是否已存在相同类别的 craft 记录（去重）
                var existingArr:Array = this.obtainIndex[itemName];
                var found:Boolean = false;
                for (var j:Number = 0; j < existingArr.length; j++) {
                    if (existingArr[j].kind === KIND_CRAFT && existingArr[j].category === category) {
                        found = true;
                        break;
                    }
                }

                if (!found) {
                    existingArr.push({
                        kind: KIND_CRAFT,
                        category: category,
                        price: isNaN(Number(recipe.price)) ? 0 : Number(recipe.price),
                        kprice: isNaN(Number(recipe.kprice)) ? 0 : Number(recipe.kprice)
                    });
                    count++;
                }
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

            for (var slot:String in shopItems) {
                if (ObjectUtil.isInternalKey(slot)) continue;

                var itemEntry = shopItems[slot];
                var itemName:String;
                var requiredInfo:String = null;

                // 兼容两种格式
                if (typeof itemEntry === "string") {
                    itemName = itemEntry;
                } else if (itemEntry && itemEntry.name) {
                    itemName = itemEntry.name;
                    // 保留解锁条件信息
                    if (itemEntry.requiredInfo_disabled) {
                        requiredInfo = itemEntry.requiredInfo_disabled;
                    }
                } else {
                    continue;
                }

                // 初始化数组
                if (!this.obtainIndex[itemName]) {
                    this.obtainIndex[itemName] = [];
                }

                // 检查是否已存在相同NPC的 shop 记录（去重）
                var existingArr:Array = this.obtainIndex[itemName];
                var npcFound:Boolean = false;
                for (var k:Number = 0; k < existingArr.length; k++) {
                    if (existingArr[k].kind === KIND_SHOP && existingArr[k].npc === npcName) {
                        npcFound = true;
                        break;
                    }
                }

                if (!npcFound) {
                    var record:Object = {
                        kind: KIND_SHOP,
                        npc: npcName
                    };
                    // 只在有值时添加 requiredInfo
                    if (requiredInfo) {
                        record.requiredInfo = requiredInfo;
                    }
                    existingArr.push(record);
                    count++;
                }
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
                type: entry.type || "",
                priceK: isNaN(Number(entry.price)) ? 0 : Number(entry.price),
                id: entry.id || ""
            });
            count++;
        }

        trace("[ItemObtainIndex] K点商店记录构建完成，共 " + count + " 条");
    }

    // ===== 查询方法 =====

    /**
     * 查询物品的所有获取方式（返回内部引用，请勿修改）
     * @param itemName 物品名称
     * @return Array<ObtainRecord>，若无记录返回空数组
     */
    public function getObtainRecords(itemName:String):Array {
        return this.obtainIndex[itemName] || [];
    }

    /**
     * 查询物品的所有获取方式（返回安全拷贝）
     * 性能较低，仅在需要修改返回数据时使用
     * @param itemName 物品名称
     * @return Array<ObtainRecord> 的浅拷贝
     */
    public function getObtainRecordsCopy(itemName:String):Array {
        var original:Array = this.obtainIndex[itemName];
        if (!original) return [];
        return original.slice(0);
    }

    /**
     * 按类型筛选获取方式
     * @param itemName 物品名称
     * @param kind 来源类型（使用 KIND_* 常量）
     * @return Array<ObtainRecord> 筛选后的记录
     */
    public function getObtainRecordsByKind(itemName:String, kind:String):Array {
        var all:Array = this.obtainIndex[itemName];
        if (!all) return [];

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
            trace("[ItemObtainIndex] 索引及发现集合已重置");
        } else {
            trace("[ItemObtainIndex] 索引已重置（保留发现集合）");
        }
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

            dropList.push({
                name: itemName,
                prob: isNaN(prob) ? 1 : prob,
                qty: isNaN(qty) ? 1 : qty
            });

            this.addDropRecord(itemName, DROP_TYPE_STAGE, stageName, prob, qty, NaN, NaN);
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

        // 标记为已发现
        var isNewDiscovery:Boolean = !this.discoveredEnemies[enemyType];
        this.discoveredEnemies[enemyType] = true;

        // 总是重新构建运行时缓存（确保使用最新数据）
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
        for (var i:Number = 0; i < drops.length; i++) {
            var drop = drops[i];
            if (!drop || !drop.名字) continue;

            var itemName:String = drop.名字;
            var prob:Number = Number(drop.概率);
            var minLv:Number = Number(drop.最小逆向等级);
            var maxLv:Number = Number(drop.最大逆向等级);

            dropList.push({
                名字: itemName,
                概率: isNaN(prob) ? 1 : prob,
                最小逆向等级: isNaN(minLv) ? 0 : minLv,
                最大逆向等级: isNaN(maxLv) ? 999 : maxLv
            });

            this.addDropRecord(itemName, DROP_TYPE_ENEMY, enemyType, prob, NaN, minLv, maxLv);
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
    public function updateQuestRewards(questId:String, questTitle:String, rewards:Array):Boolean {
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
    private function rebuildQuestCacheFromData(questId:String, questTitle:String, rewards:Array):Void {
        // 先清理该任务的旧记录
        this.clearQuestRecordsFromIndex(questId);

        var rewardList:Array = [];
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

            rewardList.push({
                item: itemName,
                qty: isNaN(qty) ? 1 : qty
            });

            this.addQuestRecord(itemName, questId, questTitle, qty);
        }

        if (rewardList.length > 0) {
            this.questRewardCache[questId] = {
                title: questTitle || questId,
                rewards: rewardList
            };
        }
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
        delete this.questRewardCache[questId];
    }

    /**
     * 追加任务奖励到已有记录（用于挑战奖励等后续发现的奖励）
     * 如果任务不存在则先创建，如果奖励已存在则跳过
     *
     * @param questId 任务ID
     * @param questTitle 任务标题
     * @param additionalRewards 追加的奖励数组，格式同 updateQuestRewards
     * @return Boolean 是否有新增记录
     */
    public function appendQuestRewards(questId:String, questTitle:String, additionalRewards:Array):Boolean {
        if (!questId || !additionalRewards || additionalRewards.length == 0) return false;

        // 如果该任务不存在，调用 updateQuestRewards 创建
        if (!this.questRewardCache[questId]) {
            return this.updateQuestRewards(questId, questTitle, additionalRewards);
        }

        // 获取已有的奖励列表
        var existingCache:Object = this.questRewardCache[questId];
        var existingRewards:Array = existingCache.rewards;

        // 构建已存在物品的快速查找表
        var existingItems:Object = {};
        for (var e:Number = 0; e < existingRewards.length; e++) {
            existingItems[existingRewards[e].item] = true;
        }

        var newCount:Number = 0;
        for (var i:Number = 0; i < additionalRewards.length; i++) {
            var reward = additionalRewards[i];
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

            // 检查是否已存在该物品
            if (existingItems[itemName]) continue;

            // 添加到缓存
            existingRewards.push({
                item: itemName,
                qty: isNaN(qty) ? 1 : qty
            });
            existingItems[itemName] = true;

            // 同时更新运行时索引
            this.addQuestRecord(itemName, questId, questTitle || existingCache.title, qty);
            newCount++;
        }

        if (newCount > 0) {
            trace("[ItemObtainIndex] 任务奖励追加: " + questId + ", 新增 " + newCount + " 项");
            return true;
        }
        return false;
    }

    /**
     * 添加掉落记录到运行时索引
     * @private
     */
    private function addDropRecord(itemName:String, dropType:String, sourceName:String,
                                   prob:Number, qty:Number, minLv:Number, maxLv:Number):Void {
        if (!this.obtainIndex[itemName]) {
            this.obtainIndex[itemName] = [];
        }

        // 检查是否已存在相同来源的记录
        var arr:Array = this.obtainIndex[itemName];
        for (var i:Number = 0; i < arr.length; i++) {
            var rec = arr[i];
            if (rec.kind === KIND_DROP && rec.dropType === dropType) {
                if (dropType === DROP_TYPE_STAGE && rec.stageName === sourceName) return;
                if (dropType === DROP_TYPE_ENEMY && rec.enemyType === sourceName) return;
            }
        }

        var record:Object = {
            kind: KIND_DROP,
            dropType: dropType,
            probability: isNaN(prob) ? 1 : prob
        };

        if (dropType === DROP_TYPE_STAGE) {
            record.stageName = sourceName;
            record.quantityMax = isNaN(qty) ? 1 : qty;
        } else {
            record.enemyType = sourceName;
            record.minLevel = isNaN(minLv) ? 0 : minLv;
            record.maxLevel = isNaN(maxLv) ? 999 : maxLv;
        }

        arr.push(record);
    }

    /**
     * 添加任务奖励记录到运行时索引
     * @private
     */
    private function addQuestRecord(itemName:String, questId:String, questTitle:String, qty:Number):Void {
        if (!this.obtainIndex[itemName]) {
            this.obtainIndex[itemName] = [];
        }

        // 检查是否已存在相同任务的记录
        var arr:Array = this.obtainIndex[itemName];
        for (var i:Number = 0; i < arr.length; i++) {
            if (arr[i].kind === KIND_QUEST && arr[i].questId === questId) return;
        }

        arr.push({
            kind: KIND_QUEST,
            questId: questId,
            questTitle: questTitle || questId,
            quantity: isNaN(qty) ? 1 : qty
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

        return {
            version: CACHE_VERSION,
            discoveredStages: stageList,
            discoveredEnemies: enemyList,
            discoveredQuests: questList
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

        var endTime:Number = getTimer();
        trace("[ItemObtainIndex] 从存档加载发现集合完成: "
            + stageCount + " 关卡(待重建), "
            + enemyCount + " 敌人(已重建), "
            + questCount + " 任务(已重建), "
            + "耗时 " + (endTime - startTime) + "ms");
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
            var dropsArr:Array = _root.配置数据为数组(enemyProps.掉落物);
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

            // 获取任务标题
            var questTitle:String = taskData.title || String(questId);
            if (_global.org.flashNight.arki.task.TaskUtil.getTaskText) {
                questTitle = _global.org.flashNight.arki.task.TaskUtil.getTaskText(taskData.title);
            }

            // 合并基础奖励和挑战奖励（如果玩家曾完成过挑战）
            var allRewards:Array = taskData.rewards.slice(0);
            if (taskData.challenge && taskData.challenge.rewards && taskData.challenge.rewards.length > 0) {
                // 挑战奖励也加入（玩家至少曾接取过该任务，可能已完成挑战）
                allRewards = allRewards.concat(taskData.challenge.rewards);
            }

            // 重建缓存
            this.rebuildQuestCacheFromData(questIdStr, questTitle, allRewards);
            count++;
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
     * 保留静态来源（craft/shop/kshop），移除动态来源（drop/quest）
     * @private
     */
    private function clearDynamicRecordsFromIndex():Void {
        var itemsCleared:Number = 0;
        var recordsRemoved:Number = 0;

        for (var itemName:String in this.obtainIndex) {
            if (ObjectUtil.isInternalKey(itemName)) continue;

            var records:Array = this.obtainIndex[itemName];
            if (!records || records.length == 0) continue;

            // 过滤掉动态来源记录，只保留静态来源
            var filtered:Array = [];
            for (var i:Number = 0; i < records.length; i++) {
                var record:Object = records[i];
                if (record.kind !== KIND_DROP && record.kind !== KIND_QUEST) {
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
        var all:Array = this.obtainIndex[itemName] || [];
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
