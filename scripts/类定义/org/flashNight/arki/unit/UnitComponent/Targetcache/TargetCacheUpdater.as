// ============================================================================
// 目标缓存更新器（增强版 - 支持坐标值数组优化和自适应阈值）
// ----------------------------------------------------------------------------
// 功能概述：
// 1. 收集、排序并写入 cacheEntry
// 2. 自动生成 nameIndex，支持 O(1) 索引定位
// 3. 新增 rightValues/leftValues 数组，优化坐标值访问性能
// 4. 维持 enemy / ally / all 三大版本号 + 复合键缓存
// 5. 自适应阈值调整，根据单位分布特征动态优化查询性能
// 
// 性能优化：
// - 预缓存 aabbCollider.right/left 值到独立数组，减少多层属性访问
// - 二分查找时直接访问数值数组，提升查询性能
// - 保持数据局部性，优化 CPU 缓存命中率
// - 自适应阈值，平衡缓存命中率和扫描效率
// ============================================================================
import org.flashNight.naki.Sort.InsertionSort;

class org.flashNight.arki.unit.UnitComponent.Targetcache.TargetCacheUpdater {

    // ========================================================================
    // 静态成员定义
    // ========================================================================
    
    /**
     * 缓存池对象
     * 存储不同类型的临时目标列表和版本号
     * 结构: {cacheKey: {tempList: Array, tempVersion: Number}}
     * - cacheKey: 缓存键，格式为 "敌人_true"、"友军_false" 或 "全体"
     * - tempList: 临时单位列表，用于减少重复收集
     * - tempVersion: 版本号，用于判断是否需要重新收集
     */
    private static var _cachePool:Object = {};
    
    /**
     * 敌人阵营版本号
     * 当敌人单位发生增删时递增，用于缓存失效判断
     */
    private static var _enemyVersion:Number = 0;
    
    /**
     * 友军阵营版本号
     * 当友军单位发生增删时递增，用于缓存失效判断
     */
    private static var _allyVersion:Number = 0;

    /**
     * 缓存有效性阈值（单位：像素）
     * 用于描述当前单位分布的空间特征
     * 当本次查询的 queryLeft 与上次相差在此阈值内时，认为可以使用缓存
     * 该值根据单位分布特征自适应调整
     */
    public static var _THRESHOLD:Number = 100;

    /**
     * 自适应阈值参数
     */
    private static var _adaptiveParams:Object = {
        // EMA平滑系数 (0.1 = 慢速适应, 0.3 = 快速适应)
        alpha: 0.2,
        
        // 密度倍数因子 (平均间距的倍数)
        densityFactor: 3.0,
        
        // 阈值边界限制
        minThreshold: 30,
        maxThreshold: 300,
        
        // 历史平均密度（初始值）
        avgDensity: 100
    };

    /**
     * 请求类型常量定义
     * 使用常量避免字符串硬编码，提高代码可维护性
     */
    private static var _ENEMY_TYPE:String = "敌人"; // 敌人类型标识
    private static var _ALLY_TYPE:String  = "友军"; // 友军类型标识
    private static var _ALL_TYPE:String   = "全体"; // 全体类型标识

    // ========================================================================
    // 核心更新方法（含自适应阈值调整）
    // ========================================================================
    
    /**
     * 更新缓存的核心方法
     * 根据请求类型和目标阵营收集、排序单位，并更新缓存项
     * 新增：根据单位分布特征自适应调整查询阈值
     * 
     * 处理流程：
     * 1. 确定需要收集的阵营类型
     * 2. 生成缓存键并获取或创建缓存数据
     * 3. 检查版本号决定是否需要重新收集
     * 4. 对收集的单位进行插入排序
     * 5. 分析单位分布特征并调整阈值
     * 6. 构建最终缓存数据（包含 nameIndex 和 rightValues）
     * 
     * @param {Object} gameWorld - 游戏世界对象，包含所有单位
     * @param {Number} currentFrame - 当前帧数，用于更新时间戳
     * @param {String} requestType - 请求类型: "敌人"、"友军"或"全体"
     * @param {Boolean} targetIsEnemy - 目标（请求者）是否为敌人
     * @param {Object} cacheEntry - 要更新的缓存项对象
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

        // (2) 生成复合键以对应临时列表
        // 使用复合键可以避免重复收集相同类型的数据
        var cacheKey:String = isAllRequest
            ? _ALL_TYPE
            : requestType + "_" + effectiveFaction.toString();

        // 获取或创建缓存类型数据
        if (!_cachePool[cacheKey]) {
            _cachePool[cacheKey] = { tempList: [], tempVersion: 0 };
        }
        var cacheTypeData:Object = _cachePool[cacheKey];

        // (3) 版本号判定 —— 只在版本号变化时重新收集
        // 全体请求: 使用敌人+友军版本号总和（任一阵营变化都需要更新）
        // 敌人/友军请求: 使用对应阵营的版本号
        var currentVersion:Number = isAllRequest
            ? _enemyVersion + _allyVersion
            : (effectiveFaction ? _enemyVersion : _allyVersion);

        // 检查是否需要更新临时列表
        if (cacheTypeData.tempVersion < currentVersion) {
            // -------- 重新收集有效单位 --------
            cacheTypeData.tempList.length = 0; // 清空列表，准备重新收集

            // 根据请求类型收集单位
            if (isAllRequest) {
                // 收集所有有效单位（不区分阵营）
                _collectAllValidUnits(gameWorld, cacheTypeData.tempList);
            } else {
                // 根据请求类型和目标阵营收集特定阵营单位
                _collectValidUnits(
                    gameWorld,
                    targetIsEnemy,   // 请求者阵营
                    isEnemyRequest,  // 是否请求敌人
                    cacheTypeData.tempList
                );
            }
            // 更新临时列表版本号，标记为最新
            cacheTypeData.tempVersion = currentVersion;
        }

        // (4) 插入排序（按 left 升序）
        // 使用插入排序因为单位列表通常是部分有序的
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

        // (5) 分析单位分布特征并自适应调整阈值
        _updateAdaptiveThreshold(list);

        // (6) 构建最终 cacheEntry（含 nameIndex 和 rightValues）
        _rebuildCacheData(list, cacheEntry, currentFrame);
    }

    // ========================================================================
    // 自适应阈值调整
    // ========================================================================
    
    /**
     * 根据单位分布特征更新自适应阈值
     * 使用指数移动平均（EMA）来平滑阈值变化
     * 
     * 算法说明：
     * 1. 计算相邻单位的平均间距（密度指标）
     * 2. 使用 EMA 更新历史平均密度
     * 3. 根据密度计算新阈值
     * 4. 应用边界限制确保阈值在合理范围内
     * 
     * @param {Array} sortedList - 已按 left 升序排序的单位列表
     * @private
     */
    private static function _updateAdaptiveThreshold(sortedList:Array):Void {
        var len:Number = sortedList.length;
        
        // 需要至少2个单位才能计算间距
        if (len < 2) return;
        
        // ===== 计算当前分布密度 =====
        var totalSpacing:Number = 0;
        var spacingCount:Number = 0;
        
        // 计算所有相邻单位的间距
        for (var i:Number = 1; i < len; i++) {
            var spacing:Number = sortedList[i].aabbCollider.left - 
                               sortedList[i-1].aabbCollider.left;
            // 只统计有效间距（排除重叠的单位）
            if (spacing > 0) {
                totalSpacing += spacing;
                spacingCount++;
            }
        }
        
        // 如果没有有效间距，保持当前阈值
        if (spacingCount == 0) return;
        
        // 计算平均间距
        var currentDensity:Number = totalSpacing / spacingCount;
        
        // ===== 使用EMA更新历史平均密度 =====
        var params:Object = _adaptiveParams;
        params.avgDensity = params.alpha * currentDensity + 
                           (1 - params.alpha) * params.avgDensity;
        
        // ===== 计算新阈值 =====
        // 阈值 = 平均密度 × 密度因子
        // 密度因子越大，阈值越大，缓存命中率越高但扫描距离可能增加
        var newThreshold:Number = params.avgDensity * params.densityFactor;
        
        // ===== 应用边界限制 =====
        if (newThreshold < params.minThreshold) {
            newThreshold = params.minThreshold;
        } else if (newThreshold > params.maxThreshold) {
            newThreshold = params.maxThreshold;
        }
        
        // ===== 更新全局阈值 =====
        _THRESHOLD = newThreshold;
        
        // ===== 可选：输出调试信息 =====
        // _root.发布消息("自适应阈值: " + Math.round(_THRESHOLD) + 
        //               " (密度: " + Math.round(params.avgDensity) + ")");
    }

    /**
     * 手动调整自适应参数
     * 允许根据不同游戏场景微调算法行为
     * 
     * @param {Number} alpha - EMA平滑系数 (0.1-0.5)
     * @param {Number} densityFactor - 密度倍数因子 (1.0-5.0)
     * @param {Number} minThreshold - 最小阈值限制
     * @param {Number} maxThreshold - 最大阈值限制
     */
    public static function setAdaptiveParams(
        alpha:Number,
        densityFactor:Number,
        minThreshold:Number,
        maxThreshold:Number
    ):Void {
        var params:Object = _adaptiveParams;
        if (!isNaN(alpha) && alpha > 0 && alpha <= 1) {
            params.alpha = alpha;
        }
        if (!isNaN(densityFactor) && densityFactor > 0) {
            params.densityFactor = densityFactor;
        }
        if (!isNaN(minThreshold) && minThreshold > 0) {
            params.minThreshold = minThreshold;
        }
        if (!isNaN(maxThreshold) && maxThreshold > minThreshold) {
            params.maxThreshold = maxThreshold;
        }
    }

    // ========================================================================
    // 缓存数据重建（核心优化）
    // ========================================================================
    
    /**
     * 重建缓存数据结构（增强版）
     * 将排序后的单位列表写入缓存项，并构建名称索引和坐标值数组
     * 
     * 新增功能：
     * - rightValues 数组：预缓存所有单位的 aabbCollider.right 值
     * - leftValues 数组：预缓存所有单位的 aabbCollider.left 值
     * 
     * 性能优势：
     * - 减少查询时的多层属性访问（unit.aabbCollider.right -> rightValues[i]）
     * - 提高数据局部性，优化 CPU 缓存命中率
     * - 支持更高效的二分查找和线性扫描
     * 
     * @param {Array} sourceList - 已排序的单位列表（按 left 升序）
     * @param {Object} cacheEntry - 目标缓存项，将被更新
     * @param {Number} currentFrame - 当前帧数，用作时间戳
     */
    private static function _rebuildCacheData(
        sourceList:Array,
        cacheEntry:Object,
        currentFrame:Number
    ):Void {
        // 初始化数据结构
        var newNameIndex:Object = {};    // 名称到索引的映射
        var rightValues:Array = [];      // right 坐标值数组
        var leftValues:Array = [];       // left 坐标值数组（可选，备用）
        var len:Number = sourceList.length;
        
        // 构建索引和坐标值数组
        // 一次遍历完成所有数据提取，避免多次迭代
        for (var i:Number = 0; i < len; i++) {
            var unit:Object = sourceList[i];
            var collider:Object = unit.aabbCollider;
            
            // 构建名称索引，支持 O(1) 查找
            newNameIndex[unit._name] = i;
            
            // 缓存坐标值，避免查询时的属性访问开销
            rightValues[i] = collider.right;
            leftValues[i] = collider.left;
        }
        
        // 更新缓存项的所有字段
        cacheEntry.data              = sourceList;       // 单位数组引用
        cacheEntry.nameIndex         = newNameIndex;     // 名称索引映射
        cacheEntry.rightValues       = rightValues;      // right 值数组（新增）
        cacheEntry.leftValues        = leftValues;       // left 值数组（新增）
        cacheEntry.lastUpdatedFrame  = currentFrame;     // 更新时间戳
    }

    // ========================================================================
    // 全局版本控制
    // ========================================================================
    
    /**
     * 添加单位时更新版本号
     * 根据单位阵营递增对应的版本号，触发相关缓存失效
     * 
     * @param {Object} unit - 新增的单位对象
     */
    public static function addUnit(unit:Object):Void {
        if (unit.是否为敌人) {
            _enemyVersion++;  // 敌人阵营版本号递增
        } else {
            _allyVersion++;   // 友军阵营版本号递增
        }
    }
    
    /**
     * 移除单位时更新版本号
     * 根据单位阵营递增对应的版本号，触发相关缓存失效
     * 
     * @param {Object} unit - 被移除的单位对象
     */
    public static function removeUnit(unit:Object):Void {
        if (unit.是否为敌人) {
            _enemyVersion++;  // 敌人阵营版本号递增
        } else {
            _allyVersion++;   // 友军阵营版本号递增
        }
    }

    // ========================================================================
    // 内部收集方法
    // ========================================================================
    
    /**
     * 收集有效单位（敌人或友军）
     * 根据请求类型和请求者阵营筛选符合条件的单位
     * 
     * 筛选逻辑：
     * - 敌人请求：收集与请求者阵营相反的单位
     * - 友军请求：收集与请求者阵营相同的单位
     * 
     * @param {Object} gameWorld - 游戏世界对象，包含所有单位
     * @param {Boolean} requesterIsEnemy - 请求者是否为敌人
     * @param {Boolean} isEnemyRequest - 是否请求敌人数据
     * @param {Array} targetList - 存储符合条件的单位（输出参数）
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
                // 检查是否为相反阵营
                if (requesterIsEnemy != uIsEnemy) {
                    // 更新碰撞器并添加到目标列表
                    // 使用链式赋值优化代码
                    u.aabbCollider.updateFromUnitArea(targetList[targetList.length] = u);
                }
            }
        } else {
            // 友军请求：收集与请求者阵营相同的单位
            for (key in gameWorld) {
                u = gameWorld[key];
                if (u.hp <= 0) continue; // 跳过已死亡单位
                
                uIsEnemy = u.是否为敌人;
                // 检查是否为相同阵营
                if (requesterIsEnemy == uIsEnemy) {
                    // 更新碰撞器并添加到目标列表
                    u.aabbCollider.updateFromUnitArea(targetList[targetList.length] = u);
                }
            }
        }
    }

    /**
     * 收集所有有效单位
     * 不区分阵营，收集所有存活的单位
     * 
     * @param {Object} gameWorld - 游戏世界对象，包含所有单位
     * @param {Array} targetList - 存储所有有效单位（输出参数）
     */
    private static function _collectAllValidUnits(
        gameWorld:Object,
        targetList:Array
    ):Void {
        var key:String, u:Object;
        
        // 遍历游戏世界中的所有单位
        for (key in gameWorld) {
            u = gameWorld[key];
            if (u.hp <= 0) continue; // 跳过已死亡单位
            
            // 更新碰撞器并添加到目标列表
            u.aabbCollider.updateFromUnitArea(targetList[targetList.length] = u);
        }
    }
}