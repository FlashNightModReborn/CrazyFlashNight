// ============================================================================
// 目标缓存更新器（升级版）
// ----------------------------------------------------------------------------
// 1. 收集、排序并写入 cacheEntry
// 2. 重新启用 _rebuildCacheData：自动生成 nameIndex，支持 O(1) 索引定位
// 3. 维持 enemy / ally / all 三大版本号 + 复合键缓存
// ============================================================================
import org.flashNight.naki.Sort.InsertionSort;

class org.flashNight.arki.unit.UnitComponent.Targetcache.TargetCacheUpdater {

    // ----------- 内部缓存池  -------------------------------------------------
    /**
     * 缓存池对象
     * 存储不同类型的临时目标列表和版本号
     * 结构: {cacheKey: {tempList: Array, tempVersion: Number}}
     */
    private static var _cachePool:Object = {};
    
    /**
     * 敌人阵营版本号
     * 当敌人单位发生变化时递增
     */
    private static var _enemyVersion:Number = 0;
    
    /**
     * 友军阵营版本号
     * 当友军单位发生变化时递增
     */
    private static var _allyVersion:Number = 0;

    /**
     * 请求类型常量
     */
    private static var _ENEMY_TYPE:String = "敌人"; // 敌人类型标识
    private static var _ALLY_TYPE:String  = "友军"; // 友军类型标识
    private static var _ALL_TYPE:String   = "全体"; // 全体类型标识

    // ------------------------------------------------------------------------
    // 核心 · 更新入口
    // ------------------------------------------------------------------------
    /**
     * 更新缓存的核心方法
     * 根据请求类型和目标阵营收集、排序单位，并更新缓存项
     * @param {Object} gameWorld - 游戏世界对象，包含所有单位
     * @param {Number} currentFrame - 当前帧数
     * @param {String} requestType - 请求类型: "敌人"、"友军"或"全体"
     * @param {Boolean} targetIsEnemy - 目标是否为敌人
     * @param {Object} cacheEntry - 要更新的缓存项
     */
    public static function updateCache(
        gameWorld:Object,
        currentFrame:Number,
        requestType:String,
        targetIsEnemy:Boolean,
        cacheEntry:Object
    ):Void {
        // 判断请求类型
        var isAllRequest:Boolean   = (requestType == _ALL_TYPE);
        var isEnemyRequest:Boolean = (requestType == _ENEMY_TYPE);

        // (1) 判定需收集的阵营
        var effectiveFaction:Boolean;
        if (!isAllRequest) {
            // 敌人请求: 收集与请求者相反阵营的单位
            // 友军请求: 收集与请求者相同阵营的单位
            effectiveFaction = isEnemyRequest ? !targetIsEnemy : targetIsEnemy;
        }

        // (2) 生成复合键 -> 对应 tempList
        var cacheKey:String = isAllRequest
            ? _ALL_TYPE
            : requestType + "_" + effectiveFaction.toString();

        // 获取或创建缓存类型数据
        if (!_cachePool[cacheKey]) {
            _cachePool[cacheKey] = { tempList: [], tempVersion: 0 };
        }
        var cacheTypeData:Object = _cachePool[cacheKey];

        // (3) 版本号判定 —— 只在需要时重新收集
        // 全体请求: 使用敌人+友军版本号总和
        // 敌人/友军请求: 使用对应阵营的版本号
        var currentVersion:Number = isAllRequest
            ? _enemyVersion + _allyVersion
            : (effectiveFaction ? _enemyVersion : _allyVersion);

        // 检查是否需要更新临时列表
        if (cacheTypeData.tempVersion < currentVersion) {
            // -------- 重新收集有效单位 --------
            cacheTypeData.tempList.length = 0; // 清空列表

            // 根据请求类型收集单位
            if (isAllRequest) {
                // 收集所有有效单位
                _collectAllValidUnits(gameWorld, cacheTypeData.tempList);
            } else {
                // 根据请求类型和目标阵营收集敌人或友军
                _collectValidUnits(
                    gameWorld,
                    targetIsEnemy,   // 请求者阵营
                    isEnemyRequest,  // 是否请求敌人
                    cacheTypeData.tempList
                );
            }
            // 更新临时列表版本号
            cacheTypeData.tempVersion = currentVersion;
        }

        // (4) 插入排序（按 left 升序）
        var list:Array = cacheTypeData.tempList;
        var len:Number = list.length;
        if (len > 1) {
            var i:Number = 1;
            do {
                var key:Object = list[i];
                var keyVal:Number = key.aabbCollider.left;
                var j:Number = i - 1;
                // 将大于当前值的元素后移
                while (j >= 0 && list[j].aabbCollider.left > keyVal) {
                    list[j + 1] = list[j--];
                }
                list[j + 1] = key;
            } while (++i < len);
        }

        // (5) 构建最终 cacheEntry（含 nameIndex）
        _rebuildCacheData(list, cacheEntry, currentFrame);
    }

    // ------------------------------------------------------------------------
    // ★ 重建缓存数据（生成 nameIndex）★
    // ------------------------------------------------------------------------
    /**
     * 重建缓存数据结构
     * 将排序后的单位列表写入缓存项，并构建名称索引
     * @param {Array} sourceList - 已排序的单位列表
     * @param {Object} cacheEntry - 目标缓存项
     * @param {Number} currentFrame - 当前帧数
     */
    private static function _rebuildCacheData(
        sourceList:Array,
        cacheEntry:Object,
        currentFrame:Number
    ):Void {
        // 构建新的名称索引
        var newNameIndex:Object = {};
        var len:Number = sourceList.length;
        
        // 为每个单位创建名称到索引的映射
        for (var i:Number = 0; i < len; i++) {
            newNameIndex[sourceList[i]._name] = i;
        }
        
        // 更新缓存项
        cacheEntry.data              = sourceList;       // 设置数据数组
        cacheEntry.nameIndex         = newNameIndex;     // 设置名称索引
        cacheEntry.lastUpdatedFrame  = currentFrame;     // 更新时间戳
    }

    // ------------------------------------------------------------------------
    // 全局版本控制
    // ------------------------------------------------------------------------
    /**
     * 添加单位时更新版本号
     * 根据单位阵营递增对应的版本号
     * @param {Object} unit - 新增的单位
     */
    public static function addUnit(unit:Object):Void {
        if (unit.是否为敌人) _enemyVersion++; else _allyVersion++;
    }
    
    /**
     * 移除单位时更新版本号
     * 根据单位阵营递增对应的版本号
     * @param {Object} unit - 移除的单位
     */
    public static function removeUnit(unit:Object):Void {
        if (unit.是否为敌人) _enemyVersion++; else _allyVersion++;
    }

    // ------------------------------------------------------------------------
    // 内部 · 收集函数
    // ------------------------------------------------------------------------
    /**
     * 收集有效单位(敌人/友军)
     * 根据请求类型和请求者阵营筛选符合条件的单位
     * @param {Object} gameWorld - 游戏世界对象
     * @param {Boolean} requesterIsEnemy - 请求者是否为敌人
     * @param {Boolean} isEnemyRequest - 是否请求敌人数据
     * @param {Array} targetList - 存储符合条件的单位
     */
    private static function _collectValidUnits(
        gameWorld:Object,
        requesterIsEnemy:Boolean,
        isEnemyRequest:Boolean,
        targetList:Array
    ):Void {
        var key:String, u:Object, uIsEnemy:Boolean;
        if (isEnemyRequest) {
            // 敌人请求：收集与请求者阵营相反的单位
            for (key in gameWorld) {
                u = gameWorld[key];
                if (u.hp <= 0) continue; // 跳过已死亡单位
                uIsEnemy = u.是否为敌人;
                if (requesterIsEnemy != uIsEnemy) {
                    // 更新碰撞器并添加到目标列表
                    u.aabbCollider.updateFromUnitArea(targetList[targetList.length] = u);
                }
            }
        } else {
            // 友军请求：收集与请求者阵营相同的单位
            for (key in gameWorld) {
                u = gameWorld[key];
                if (u.hp <= 0) continue; // 跳过已死亡单位
                uIsEnemy = u.是否为敌人;
                if (requesterIsEnemy == uIsEnemy) {
                    // 更新碰撞器并添加到目标列表
                    u.aabbCollider.updateFromUnitArea(targetList[targetList.length] = u);
                }
            }
        }
    }

    /**
     * 收集所有有效单位
     * 不区分阵营，收集所有未死亡的单位
     * @param {Object} gameWorld - 游戏世界对象
     * @param {Array} targetList - 存储所有有效单位
     */
    private static function _collectAllValidUnits(
        gameWorld:Object,
        targetList:Array
    ):Void {
        var key:String, u:Object;
        for (key in gameWorld) {
            u = gameWorld[key];
            if (u.hp <= 0) continue; // 跳过已死亡单位
            // 更新碰撞器并添加到目标列表
            u.aabbCollider.updateFromUnitArea(targetList[targetList.length] = u);
        }
    }
}