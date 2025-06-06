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
        var cacheKey:String = isAllRequest
            ? _ALL_TYPE
            : requestType + "_" + effectiveFaction.toString();

        // 获取或创建缓存类型数据
        if (!_cachePool[cacheKey]) {
            _cachePool[cacheKey] = { tempList: [], tempVersion: 0 };
        }
        var cacheTypeData:Object = _cachePool[cacheKey];

        // (3) 版本号判定
        var currentVersion:Number = isAllRequest
            ? _enemyVersion + _allyVersion
            : (effectiveFaction ? _enemyVersion : _allyVersion);

        // 检查是否需要更新临时列表
        if (cacheTypeData.tempVersion < currentVersion) {
            // 重新收集有效单位
            cacheTypeData.tempList.length = 0;

            // 根据请求类型收集单位
            if (isAllRequest) {
                _collectAllValidUnits(gameWorld, cacheTypeData.tempList);
            } else {
                _collectValidUnits(
                    gameWorld,
                    targetIsEnemy,
                    isEnemyRequest,
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
                var leftVal:Number = key.aabbCollider.left;
                var j:Number = i - 1;
                while (j >= 0 && list[j].aabbCollider.left > leftVal) {
                    list[j + 1] = list[j--];
                }
                list[j + 1] = key;
            } while (++i < len);
        }

        // ========================================================================
        // ===== 核心优化：单循环完成所有数据提取 =====
        // ========================================================================
        var leftValues:Array = [];      // left 坐标值数组
        var rightValues:Array = [];     // right 坐标值数组  
        var newNameIndex:Object = {};   // 名称到索引的映射
        
        // 单次遍历，一次性完成所有数据提取
        // 性能优势：最大化数据局部性，最小化循环开销
        for (var k:Number = 0; k < len; k++) {
            var unit:Object = list[k];
            var collider:Object = unit.aabbCollider;
            
            // 一次访问单位对象，完成所有数据提取
            leftValues[k] = collider.left;          // 用于自适应阈值分析
            rightValues[k] = collider.right;        // 用于查询性能优化
            newNameIndex[unit._name] = k;           // 用于O(1)名称索引
        }

        // (5) 分析单位分布特征并自适应调整阈值
        _updateAdaptiveThreshold(leftValues);

        // (6) 直接更新缓存项
        // 所有数据已在上面的单循环中准备完毕
        cacheEntry.data              = list;           // 单位数组引用
        cacheEntry.nameIndex         = newNameIndex;   // 名称索引映射
        cacheEntry.rightValues       = rightValues;    // right 值数组
        cacheEntry.leftValues        = leftValues;     // left 值数组
        cacheEntry.lastUpdatedFrame  = currentFrame;   // 更新时间戳
    }


    // ========================================================================
    // 自适应阈值调整
    // ========================================================================
    
    /**
     * 根据单位分布特征更新自适应阈值
     * 接收 leftValues 数组
     * 使用指数移动平均（EMA）来平滑阈值变化
     * 
     * 算法说明：
     * 1. 计算相邻单位的平均间距（密度指标）
     * 2. 使用 EMA 更新历史平均密度
     * 3. 根据密度计算新阈值
     * 4. 应用边界限制确保阈值在合理范围内
     * 
     * @param {Array} leftValues - 已按 left 升序排序的单位列表
     * @private
     */
    private static function _updateAdaptiveThreshold(leftValues:Array):Void {
        var len:Number = leftValues.length;
        // 需要至少 2 个单位才能计算相邻间距
        if (len < 2) return;

        // ===== 计算当前分布密度 =====
        var totalSpacing:Number = 0;
        var spacingCount:Number = 0;

        // 计算所有相邻单位的间距
        for (var i:Number = 1; i < len; i++) {
            // 直接用数字数组计算差值
            var spacing:Number = leftValues[i] - leftValues[i - 1];
            // 只统计有效间距（排除重叠单位）
            if (spacing > 0) {
                totalSpacing += spacing;
                spacingCount++;
            }
        }
        // 如果没有有效间距，就保持当前阈值不变
        if (spacingCount == 0) return;

        // 计算平均间距
        var currentDensity:Number = totalSpacing / spacingCount;

        // ===== 使用 EMA 更新历史平均密度 =====
        var params:Object = _adaptiveParams;
        params.avgDensity = params.alpha * currentDensity +
                            (1 - params.alpha) * params.avgDensity;

        // ===== 计算新阈值 =====
        // 阈值 = 平均密度 × 密度因子
        var newThreshold:Number = params.avgDensity * params.densityFactor;

        // ===== 应用边界限制 =====
        if (newThreshold < params.minThreshold) {
            newThreshold = params.minThreshold;
        } else if (newThreshold > params.maxThreshold) {
            newThreshold = params.maxThreshold;
        }

        // ===== 更新全局阈值 =====
        _THRESHOLD = newThreshold;

        // =====（可选）输出调试信息 =====
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