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
 * 存档结构（动态缓存）：
 * obtainCache = {
 *   version: 1,
 *   stages: { stageName: [{name, prob, qty}] },
 *   enemies: { enemyType: [{名字, 概率, 最小逆向等级, 最大逆向等级}] },
 *   quests: { questId: [{item, qty}] }
 * }
 *
 * 使用示例：
 * ```actionscript
 * var index:ItemObtainIndex = ItemObtainIndex.getInstance();
 * index.buildIndex(_root.改装清单, _root.shops, _root.kshop_list);
 * index.loadFromSave(mysave.data.obtainCache); // 加载存档中的动态缓存
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
    private static var CACHE_VERSION:Number = 1;

    // ===== 状态标记 =====
    private var _isBuilt:Boolean = false;

    // ===== 核心索引数据结构 =====
    /**
     * 统一索引（运行时查询用）
     * 键: 物品名称(String)
     * 值: Array<ObtainRecord>，包含该物品的所有获取方式
     */
    private var obtainIndex:Object;

    // ===== 动态缓存（存档持久化用） =====
    /**
     * 关卡掉落缓存
     * 键: 关卡名称(String)
     * 值: Array<{name:物品名, prob:概率, qty:最大数量}>
     */
    private var stageDropCache:Object;

    /**
     * 敌人掉落缓存
     * 键: 敌人兵种(String)
     * 值: Array<{名字, 概率, 最小逆向等级, 最大逆向等级}>
     */
    private var enemyDropCache:Object;

    /**
     * 任务奖励缓存
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
     * @param clearDynamicCache 是否同时清除动态缓存，默认 false
     */
    public function reset(clearDynamicCache:Boolean):Void {
        this.obtainIndex = {};
        this._isBuilt = false;
        if (clearDynamicCache) {
            this.stageDropCache = {};
            this.enemyDropCache = {};
            this.questRewardCache = {};
            trace("[ItemObtainIndex] 索引及动态缓存已重置");
        } else {
            trace("[ItemObtainIndex] 索引已重置（保留动态缓存）");
        }
    }

    // ===== 动态缓存更新方法 =====

    /**
     * 更新关卡掉落缓存
     * 在关卡XML解析完成后调用，记录该关卡的掉落物
     *
     * @param stageName 关卡名称
     * @param rewards 掉落物数组，格式为 [[物品名, 概率, 最大数量], ...]
     *                或 [{Name, AcquisitionProbability, QuantityMax}, ...]
     * @return Boolean 是否有新增记录
     */
    public function updateStageDrops(stageName:String, rewards:Array):Boolean {
        if (!stageName || !rewards || rewards.length == 0) return false;

        // 检查是否已记录该关卡
        if (this.stageDropCache[stageName]) {
            return false; // 已存在，不重复记录
        }

        var dropList:Array = [];
        for (var i:Number = 0; i < rewards.length; i++) {
            var reward = rewards[i];
            var itemName:String;
            var prob:Number;
            var qty:Number;

            // 兼容两种格式
            if (reward instanceof Array) {
                // 格式: [物品名, 概率, 最大数量]
                itemName = reward[0];
                prob = Number(reward[1]);
                qty = Number(reward[2]);
            } else if (reward && reward.Name) {
                // 格式: {Name, AcquisitionProbability, QuantityMax}
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

            // 同时更新运行时索引
            this.addDropRecord(itemName, DROP_TYPE_STAGE, stageName, prob, qty, NaN, NaN);
        }

        if (dropList.length > 0) {
            this.stageDropCache[stageName] = dropList;
            trace("[ItemObtainIndex] 关卡掉落缓存更新: " + stageName + ", " + dropList.length + " 项");
            return true;
        }
        return false;
    }

    /**
     * 更新敌人掉落缓存
     * 在首次遭遇敌人时调用，记录该敌人的掉落物
     *
     * @param enemyType 敌人兵种
     * @param drops 掉落物数组，格式为 [{名字, 概率, 最小逆向等级, 最大逆向等级}, ...]
     * @return Boolean 是否有新增记录
     */
    public function updateEnemyDrops(enemyType:String, drops:Array):Boolean {
        if (!enemyType || !drops || drops.length == 0) return false;

        // 检查是否已记录该敌人
        if (this.enemyDropCache[enemyType]) {
            return false; // 已存在，不重复记录
        }

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

            // 同时更新运行时索引
            this.addDropRecord(itemName, DROP_TYPE_ENEMY, enemyType, prob, NaN, minLv, maxLv);
        }

        if (dropList.length > 0) {
            this.enemyDropCache[enemyType] = dropList;
            trace("[ItemObtainIndex] 敌人掉落缓存更新: " + enemyType + ", " + dropList.length + " 项");
            return true;
        }
        return false;
    }

    /**
     * 更新任务奖励缓存
     * 在任务接取或完成时调用，记录该任务的奖励
     *
     * @param questId 任务ID
     * @param questTitle 任务标题
     * @param rewards 奖励数组，格式为 ["物品名#数量", ...] 或 [{item, qty}, ...]
     * @return Boolean 是否有新增记录
     */
    public function updateQuestRewards(questId:String, questTitle:String, rewards:Array):Boolean {
        if (!questId || !rewards || rewards.length == 0) return false;

        // 检查是否已记录该任务
        if (this.questRewardCache[questId]) {
            return false; // 已存在，不重复记录
        }

        var rewardList:Array = [];
        for (var i:Number = 0; i < rewards.length; i++) {
            var reward = rewards[i];
            var itemName:String;
            var qty:Number;

            if (typeof reward === "string") {
                // 格式: "物品名#数量"
                var parts:Array = reward.split("#");
                itemName = parts[0];
                qty = parts.length > 1 ? Number(parts[1]) : 1;
            } else if (reward && reward.item) {
                // 格式: {item, qty}
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

            // 同时更新运行时索引
            this.addQuestRecord(itemName, questId, questTitle, qty);
        }

        if (rewardList.length > 0) {
            this.questRewardCache[questId] = {
                title: questTitle || questId,
                rewards: rewardList
            };
            trace("[ItemObtainIndex] 任务奖励缓存更新: " + questId + ", " + rewardList.length + " 项");
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
     * 导出动态缓存用于存档
     * @return Object 可序列化的缓存数据
     */
    public function exportToSave():Object {
        return {
            version: CACHE_VERSION,
            stages: this.stageDropCache,
            enemies: this.enemyDropCache,
            quests: this.questRewardCache
        };
    }

    /**
     * 从存档加载动态缓存
     * 加载后会自动重建运行时索引中的动态来源记录
     *
     * @param data 存档中的缓存数据
     */
    public function loadFromSave(data:Object):Void {
        if (!data) {
            trace("[ItemObtainIndex] 存档中无动态缓存数据");
            return;
        }

        // 版本检查（预留迁移逻辑）
        var version:Number = data.version || 0;
        if (version < CACHE_VERSION) {
            trace("[ItemObtainIndex] 缓存版本较旧 (" + version + " -> " + CACHE_VERSION + ")，将迁移");
            // 目前版本1，无需迁移
        }

        var startTime:Number = getTimer();
        var stageCount:Number = 0;
        var enemyCount:Number = 0;
        var questCount:Number = 0;

        // 加载关卡掉落缓存
        if (data.stages) {
            this.stageDropCache = {};
            for (var stageName:String in data.stages) {
                if (ObjectUtil.isInternalKey(stageName)) continue;
                var stageDrops:Array = data.stages[stageName];
                if (!stageDrops) continue;

                this.stageDropCache[stageName] = stageDrops;
                stageCount++;

                // 重建运行时索引
                for (var i:Number = 0; i < stageDrops.length; i++) {
                    var sd = stageDrops[i];
                    this.addDropRecord(sd.name, DROP_TYPE_STAGE, stageName, sd.prob, sd.qty, NaN, NaN);
                }
            }
        }

        // 加载敌人掉落缓存
        if (data.enemies) {
            this.enemyDropCache = {};
            for (var enemyType:String in data.enemies) {
                if (ObjectUtil.isInternalKey(enemyType)) continue;
                var enemyDrops:Array = data.enemies[enemyType];
                if (!enemyDrops) continue;

                this.enemyDropCache[enemyType] = enemyDrops;
                enemyCount++;

                // 重建运行时索引
                for (var j:Number = 0; j < enemyDrops.length; j++) {
                    var ed = enemyDrops[j];
                    this.addDropRecord(ed.名字, DROP_TYPE_ENEMY, enemyType, ed.概率, NaN, ed.最小逆向等级, ed.最大逆向等级);
                }
            }
        }

        // 加载任务奖励缓存
        if (data.quests) {
            this.questRewardCache = {};
            for (var questId:String in data.quests) {
                if (ObjectUtil.isInternalKey(questId)) continue;
                var questData = data.quests[questId];
                if (!questData || !questData.rewards) continue;

                this.questRewardCache[questId] = questData;
                questCount++;

                // 重建运行时索引
                for (var k:Number = 0; k < questData.rewards.length; k++) {
                    var qr = questData.rewards[k];
                    this.addQuestRecord(qr.item, questId, questData.title, qr.qty);
                }
            }
        }

        var endTime:Number = getTimer();
        trace("[ItemObtainIndex] 从存档加载动态缓存完成: "
            + stageCount + " 关卡, "
            + enemyCount + " 敌人, "
            + questCount + " 任务, "
            + "耗时 " + (endTime - startTime) + "ms");
    }

    /**
     * 检查关卡是否已被发现
     */
    public function isStageDiscovered(stageName:String):Boolean {
        return this.stageDropCache[stageName] != null;
    }

    /**
     * 检查敌人是否已被发现
     */
    public function isEnemyDiscovered(enemyType:String):Boolean {
        return this.enemyDropCache[enemyType] != null;
    }

    /**
     * 检查任务是否已被发现
     */
    public function isQuestDiscovered(questId:String):Boolean {
        return this.questRewardCache[questId] != null;
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
