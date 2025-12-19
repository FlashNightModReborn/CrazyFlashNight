import org.flashNight.gesh.object.ObjectUtil;

/**
 * ItemObtainIndex - 物品获取方式反向索引
 *
 * 职责：
 * - 在游戏启动时构建反向索引，将物品名映射到其获取方式
 * - 提供O(1)复杂度的查询接口
 * - 支持合成、NPC商店、K点商店三种获取来源
 *
 * 使用示例：
 * ```actionscript
 * var index:ItemObtainIndex = ItemObtainIndex.getInstance();
 * index.buildIndex(_root.改装清单, _root.shops, _root.kshop_list);
 * var methods:Object = index.getObtainMethods("SAPS12");
 * // methods = {crafting: [{category:"武器合成", price:10000, kprice:0}], shops: [], kshop: []}
 * ```
 */
class org.flashNight.gesh.tooltip.ItemObtainIndex {

    // ===== 单例实例 =====
    private static var instance:ItemObtainIndex = null;

    // ===== 状态标记 =====
    private var _isBuilt:Boolean = false; 

    // ===== 核心索引数据结构 =====

    /**
     * 合成来源索引
     * 键: 物品名称(String)
     * 值: Array，每个元素为 {
     *   category: String,   // 合成分类，如"武器合成"、"饰品合成"
     *   price: Number,      // 金币价格
     *   kprice: Number      // K点价格
     * }
     * 同物品同类别去重
     */
    private var craftingIndex:Object;

    /**
     * 商店来源索引
     * 键: 物品名称(String)
     * 值: Array<String>，包含售卖该物品的NPC名称列表（去重）
     */
    private var shopIndex:Object;

    /**
     * K点商店来源索引
     * 键: 物品名称(String)
     * 值: Array，每个元素为 {
     *   type: String,    // 分类，如"新品推荐"、"特价商品"
     *   price: Number,   // K点价格
     *   id: String       // 商品ID
     * }
     * 支持同物品多条记录
     */
    private var kshopIndex:Object;

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
        this.craftingIndex = {};
        this.shopIndex = {};
        this.kshopIndex = {};
    }

    // ===== 索引构建方法 =====

    /**
     * 构建全部索引
     * 支持部分数据缺失，任一数据源为null时仍构建其他索引
     *
     * @param craftingData   合成数据 (_root.改装清单)，结构为 {分类名: [{name, title, price, kprice, materials}, ...]}
     * @param shopData       商店数据 (_root.shops)，结构为 {NPC名: {序号: 物品名或{name:物品名}}}
     * @param kshopData      K点商店数据 (_root.kshop_list)，结构为 [{id, item, type, price}, ...]
     */
    public function buildIndex(craftingData:Object, shopData:Object, kshopData:Array):Void {
        if (this._isBuilt) {
            trace("[ItemObtainIndex] 索引已构建，跳过重复构建");
            return;
        }

        var startTime:Number = getTimer();

        this.buildCraftingIndex(craftingData);
        this.buildShopIndex(shopData);
        this.buildKShopIndex(kshopData);

        this._isBuilt = true;

        var endTime:Number = getTimer();
        trace("[ItemObtainIndex] 索引构建完成，耗时 " + (endTime - startTime) + "ms");
    }

    /**
     * 构建合成来源索引
     * @param data _root.改装清单 结构为 {分类名: [{name, title, price, kprice, materials}, ...]}
     */
    private function buildCraftingIndex(data:Object):Void {
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
                if (!this.craftingIndex[itemName]) {
                    this.craftingIndex[itemName] = [];
                }

                // 检查是否已存在相同类别（去重）
                var existingArr:Array = this.craftingIndex[itemName];
                var found:Boolean = false;
                for (var j:Number = 0; j < existingArr.length; j++) {
                    if (existingArr[j].category === category) {
                        found = true;
                        break;
                    }
                }

                if (!found) {
                    // 添加来源信息
                    existingArr.push({
                        category: category,
                        price: isNaN(Number(recipe.price)) ? 0 : Number(recipe.price),
                        kprice: isNaN(Number(recipe.kprice)) ? 0 : Number(recipe.kprice)
                    });
                    count++;
                }
            }
        }

        trace("[ItemObtainIndex] 合成索引构建完成，共 " + count + " 条记录");
    }

    /**
     * 构建商店来源索引
     * @param data _root.shops 结构为 {NPC名: {序号: 物品名或物品对象}}
     */
    private function buildShopIndex(data:Object):Void {
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

                // 兼容两种格式: 直接字符串 或 {name: "物品名", ...}
                if (typeof itemEntry === "string") {
                    itemName = itemEntry;
                } else if (itemEntry && itemEntry.name) {
                    itemName = itemEntry.name;
                } else {
                    continue;
                }

                // 初始化数组
                if (!this.shopIndex[itemName]) {
                    this.shopIndex[itemName] = [];
                }

                // 避免重复添加同一NPC（去重）
                var npcArr:Array = this.shopIndex[itemName];
                var npcFound:Boolean = false;
                for (var k:Number = 0; k < npcArr.length; k++) {
                    if (npcArr[k] === npcName) {
                        npcFound = true;
                        break;
                    }
                }

                if (!npcFound) {
                    npcArr.push(npcName);
                    count++;
                }
            }
        }

        trace("[ItemObtainIndex] 商店索引构建完成，共 " + count + " 条记录");
    }

    /**
     * 构建K点商店来源索引
     * @param data _root.kshop_list 数组，每个元素为 {id, item, type, price}
     */
    private function buildKShopIndex(data:Array):Void {
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
            if (!this.kshopIndex[itemName]) {
                this.kshopIndex[itemName] = [];
            }

            // K点商店支持同物品多条记录（可能type不同）
            this.kshopIndex[itemName].push({
                type: entry.type || "",
                price: isNaN(Number(entry.price)) ? 0 : Number(entry.price),
                id: entry.id || ""
            });
            count++;
        }

        trace("[ItemObtainIndex] K点商店索引构建完成，共 " + count + " 条记录");
    }

    // ===== 查询方法 =====

    /**
     * 查询物品的所有获取方式
     * @param itemName 物品名称
     * @return {crafting: Array, shops: Array, kshop: Array}
     *         若无任何来源则对应字段为空数组
     */
    public function getObtainMethods(itemName:String):Object {
        return {
            crafting: this.craftingIndex[itemName] || [],
            shops: this.shopIndex[itemName] || [],
            kshop: this.kshopIndex[itemName] || []
        };
    }

    /**
     * 检查物品是否有任何获取方式
     * @param itemName 物品名称
     * @return Boolean
     */
    public function hasObtainMethod(itemName:String):Boolean {
        return (this.craftingIndex[itemName] != null) ||
               (this.shopIndex[itemName] != null) ||
               (this.kshopIndex[itemName] != null);
    }

    /**
     * 获取索引构建状态
     */
    public function isIndexBuilt():Boolean {
        return this._isBuilt;
    }

    /**
     * 重置索引（用于重新加载数据时）
     */
    public function reset():Void {
        this.craftingIndex = {};
        this.shopIndex = {};
        this.kshopIndex = {};
        this._isBuilt = false;
        trace("[ItemObtainIndex] 索引已重置");
    }
}
