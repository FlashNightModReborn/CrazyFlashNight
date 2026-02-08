// ============================================================================
// 目标缓存更新器（集成FactionManager版本）
// ----------------------------------------------------------------------------
// 功能概述：
// 1. 收集、排序并写入 cacheEntry
// 2. 自动生成 nameIndex，支持 O(1) 索引定位
// 3. 新增 rightValues/leftValues 数组，优化坐标值访问性能
// 4. 【重构改进】集成 FactionManager 进行阵营关系判断
// 5. 使用 AdaptiveThresholdOptimizer 处理阈值逻辑
// ============================================================================
import org.flashNight.arki.unit.UnitComponent.Targetcache.AdaptiveThresholdOptimizer;
import org.flashNight.arki.unit.UnitComponent.Targetcache.FactionManager;
import org.flashNight.naki.Sort.TimSort;

class org.flashNight.arki.unit.UnitComponent.Targetcache.TargetCacheUpdater {

    // ========================================================================
    // 静态成员定义
    // ========================================================================
    
    /**
     * 缓存池对象
     * 【重构】现在使用阵营ID作为缓存键的一部分
     * 结构: {cacheKey: {tempList: Array, tempVersion: Number, leftValues:Array, rightValues:Array, nameIndex:Object}}
     * - cacheKey: 缓存键，格式为 "敌人_FACTION_ID" 或 "友军_FACTION_ID" 或 "全体"
     * - tempList: 临时单位列表，用于减少重复收集
     * - tempVersion: 版本号，用于判断是否需要重新收集
     * - leftValues/rightValues/nameIndex: 复用的数据结构，避免每帧分配导致GC抖动
     */
    private static var _cachePool:Object = {};
    
    /**
     * 【重构】基于阵营的版本控制
     * 不再使用简单的敌人/友军二分法，而是为每个阵营维护独立的版本号
     * 结构: {factionId: versionNumber}
     */
    private static var _factionVersions:Object = {};

    // ========================================================================
    // 阵营分桶注册表
    // ========================================================================

    /**
     * 阵营分桶注册表
     * 结构: {factionId: [unit, unit, ...]}
     * 作为 gameWorld 全量扫描的加速索引，由 addUnit/removeUnit 维护，
     * 定期通过 _reconcile 与 gameWorld 权威数据源同步。
     */
    private static var _registry:Object = {};

    /**
     * 单位名 → 阵营映射
     * 结构: {unitName: factionId}
     * 用于 removeUnit 时 O(1) 定位目标桶，避免遍历所有桶查找。
     */
    private static var _registryMap:Object = {};

    /**
     * 注册表单位总数
     * 用于校验时异常检测（与 gameWorld 扫描结果对比）。
     */
    private static var _registryCount:Number = 0;

    /**
     * 上次校验帧号
     * -1 表示从未校验，强制首次 updateCache 时触发校验。
     */
    private static var _lastReconcileFrame:Number = -1;

    /**
     * 校验间隔（帧数）
     * 约 10 秒 @30fps。定期全量扫描 gameWorld 重建注册表并预排序。
     */
    private static var RECONCILE_INTERVAL:Number = 300;

    /**
     * 缓存有效性阈值访问器
     * 委托给 AdaptiveThresholdOptimizer 管理
     */
    public static function get _THRESHOLD():Number {
        return AdaptiveThresholdOptimizer.getThreshold();
    }

    /**
     * 请求类型常量定义
     */
    private static var _ENEMY_TYPE:String = "敌人";
    private static var _ALLY_TYPE:String  = "友军";
    private static var _ALL_TYPE:String   = "全体";

    /**
     * TimSort 比较器复用（避免每次 updateCache new Function）
     * @private
     */
    private static function _compareByLeft(a:Object, b:Object):Number {
        return a.aabbCollider.left - b.aabbCollider.left;
    }

    /**
     * 初始化标志
     */
    private static var _initialized:Boolean = initialize();

    // ========================================================================
    // 初始化方法
    // ========================================================================
    
    /**
     * 初始化方法
     * 【重构】为所有注册的阵营初始化版本号
     */
    public static function initialize():Boolean {

        FactionManager.initialize();
        var arr:Array = FactionManager.getAllFactions();
        // trace("initialize" + arr);
        // 确保 FactionManager 已初始化
        if (!FactionManager || !arr) {
            // trace("TargetCacheUpdater: FactionManager 未初始化");
            return false;
        }
        
        // 为所有阵营初始化版本号和注册表桶
        var allFactions:Array = FactionManager.getAllFactions();
        for (var i:Number = 0; i < allFactions.length; i++) {
            var factionId:String = allFactions[i];
            if (!_factionVersions[factionId]) {
                _factionVersions[factionId] = 0;
            }
            if (!_registry[factionId]) {
                _registry[factionId] = [];
            }
        }

        // 强制首次 updateCache 时触发校验
        _lastReconcileFrame = -1;

        return true;
    }

    // ========================================================================
    // 核心更新方法（集成FactionManager版本）
    // ========================================================================
    
    /**
     * 更新缓存的核心方法（集成FactionManager版本）
     * 
     * 【重构改进】：
     * 1. 使用 FactionManager 判断阵营关系
     * 2. 支持多阵营系统，不再局限于敌人/友军二分法
     * 3. 使用阵营ID而非布尔值构建缓存键
     * 
     * @param {Object} gameWorld - 游戏世界对象，包含所有单位
     * @param {Number} currentFrame - 当前帧数，用于更新时间戳
     * @param {String} requestType - 请求类型: "敌人"、"友军"或"全体"
     * @param {Boolean} targetIsEnemy - 目标（请求者）是否为敌人（向后兼容参数）
     * @param {Object} cacheEntry - 要更新的缓存项对象
     */
    public static function updateCache(
        gameWorld:Object,
        currentFrame:Number,
        requestType:String,
        targetIsEnemy:Boolean,
        cacheEntry:Object
    ):Void {
        // 定期校验：首次强制（_lastReconcileFrame == -1）+ 定期间隔
        if (_lastReconcileFrame < 0 ||
            (currentFrame - _lastReconcileFrame >= RECONCILE_INTERVAL)) {
            _reconcile(gameWorld, currentFrame);
        }

        // 判断请求类型
        var isAllRequest:Boolean   = (requestType == _ALL_TYPE);
        var isEnemyRequest:Boolean = (requestType == _ENEMY_TYPE);

        // 请求者阵营（向后兼容：由 legacy 的“是否为敌人”布尔值映射得到）
        // 避免每次 updateCache new 临时对象造成 GC 压力。
        var requesterFaction:String;
        if (targetIsEnemy === true) {
            requesterFaction = FactionManager.FACTION_ENEMY;
        } else if (targetIsEnemy === false) {
            requesterFaction = FactionManager.FACTION_PLAYER;
        } else {
            requesterFaction = FactionManager.FACTION_HOSTILE_NEUTRAL;
        }

        // 生成缓存键
        var cacheKey:String = isAllRequest
            ? _ALL_TYPE
            : requestType + "_" + requesterFaction;

        // 获取或创建缓存类型数据
        if (!_cachePool[cacheKey]) {
            _cachePool[cacheKey] = {
                tempList: [],
                tempVersion: -1,
                leftValues: [],
                rightValues: [],
                nameIndex: {}
            };
        }
        var cacheTypeData:Object = _cachePool[cacheKey];

        // 【重构】计算版本号 - 基于阵营版本控制
        var currentVersion:Number = _calculateVersion(requestType, requesterFaction);

        // 检查是否需要更新临时列表
        if (cacheTypeData.tempVersion < currentVersion) {
            // 重新收集有效单位
            cacheTypeData.tempList.length = 0;

            // 根据请求类型收集单位
            if (isAllRequest) {
                _collectAllValidUnits(gameWorld, cacheTypeData.tempList);
            } else {
                // 【重构】使用新的基于FactionManager的收集方法
                _collectValidUnitsWithFactionManager(
                    gameWorld,
                    requesterFaction,
                    isEnemyRequest,
                    cacheTypeData.tempList
                );
            }
            // 更新临时列表版本号
            cacheTypeData.tempVersion = currentVersion;
        }

        // 插入排序（按 left 升序）
        var list:Array = cacheTypeData.tempList;
        var len:Number = list.length;
        if (len > 64) {
            TimSort.sort(list, _compareByLeft);
        } else if (len > 1) {
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

        // 单循环完成所有数据提取
        var leftValues:Array = cacheTypeData.leftValues;
        var rightValues:Array = cacheTypeData.rightValues;
        var newNameIndex:Object = cacheTypeData.nameIndex;

        // 复用数组：缩短到当前长度，避免保留旧数据
        leftValues.length = len;
        rightValues.length = len;

        // 复用索引对象：清空旧键，避免 stale 映射（不新建对象以减少分配）
        for (var oldKey:String in newNameIndex) {
            delete newNameIndex[oldKey];
        }
        
        for (var k:Number = 0; k < len; k++) {
            var unit:Object = list[k];
            var collider:Object = unit.aabbCollider;
            
            leftValues[k] = collider.left;
            rightValues[k] = collider.right;
            newNameIndex[unit._name] = k;
        }

        // 使用 AdaptiveThresholdOptimizer 更新阈值
        AdaptiveThresholdOptimizer.updateThreshold(leftValues);

        // 更新缓存项
        cacheEntry.data              = list;
        cacheEntry.nameIndex         = newNameIndex;
        cacheEntry.rightValues       = rightValues;
        cacheEntry.leftValues        = leftValues;
        cacheEntry.lastUpdatedFrame  = currentFrame;
    }

    /**
     * 获取指定请求在当前阵营关系下的“相关版本号”
     * - 用于 Provider 做精细化版本检查，避免无关阵营变化导致缓存误失效。
     *
     * @param {String} requestType       请求类型: "敌人"、"友军"或"全体"
     * @param {String} requesterFaction  请求者阵营ID
     * @return {Number} 版本号
     */
    public static function getVersionForRequest(requestType:String, requesterFaction:String):Number {
        return _calculateVersion(requestType, requesterFaction);
    }

    // ========================================================================
    // 【新增】基于阵营的版本号计算
    // ========================================================================
    
    /**
     * 计算当前版本号
     * 【重构】基于阵营系统计算版本号
     * 
     * @param {String} requestType - 请求类型
     * @param {String} requesterFaction - 请求者阵营
     * @return {Number} 计算得出的版本号
     * @private
     */
    private static function _calculateVersion(requestType:String, requesterFaction:String):Number {
        if (requestType == _ALL_TYPE) {
            // 全体请求：所有阵营版本号之和
            var totalVersion:Number = 0;
            for (var faction:String in _factionVersions) {
                totalVersion += _factionVersions[faction];
            }
            return totalVersion;
        } else if (requestType == _ENEMY_TYPE) {
            // 敌人请求：所有敌对阵营版本号之和
            // 使用 Ref 版本避免 slice 分配（高频路径）
            var enemyFactions:Array = FactionManager.getEnemyFactionsRef(requesterFaction);
            var enemyVersion:Number = 0;
            if (enemyFactions != null) {
                for (var i:Number = 0; i < enemyFactions.length; i++) {
                    enemyVersion += _factionVersions[enemyFactions[i]] || 0;
                }
            }
            return enemyVersion;
        } else {
            // 友军请求：所有友好阵营版本号之和
            // 使用 Ref 版本避免 slice 分配（高频路径）
            var allyFactions:Array = FactionManager.getAllyFactionsRef(requesterFaction);
            var allyVersion:Number = 0;
            if (allyFactions != null) {
                for (var j:Number = 0; j < allyFactions.length; j++) {
                    allyVersion += _factionVersions[allyFactions[j]] || 0;
                }
            }
            return allyVersion;
        }
    }

    // ========================================================================
    // 【重构】基于FactionManager的单位收集方法
    // ========================================================================
    
    /**
     * 从注册表收集有效单位（按阵营关系）
     *
     * 【优化】遍历相关阵营桶而非 gameWorld 全量扫描：
     * - 消除非单位对象的无效迭代
     * - 消除每单位的 getFactionFromUnit / areEnemies / areAllies 调用
     * - 阵营分桶已隐式完成关系过滤
     *
     * hp > 0 检查仍保留，作为校验间隔内的安全网（过滤已死亡但未移除的条目）。
     *
     * @param {Object} gameWorld - 游戏世界对象（保留参数签名兼容性）
     * @param {String} requesterFaction - 请求者的阵营ID
     * @param {Boolean} isEnemyRequest - 是否请求敌人数据
     * @param {Array} targetList - 存储符合条件的单位（输出参数）
     * @private
     */
    private static function _collectValidUnitsWithFactionManager(
        gameWorld:Object,
        requesterFaction:String,
        isEnemyRequest:Boolean,
        targetList:Array
    ):Void {
        // 确定目标阵营列表（零拷贝引用）
        var factions:Array;
        if (isEnemyRequest) {
            factions = FactionManager.getEnemyFactionsRef(requesterFaction);
        } else {
            factions = FactionManager.getAllyFactionsRef(requesterFaction);
        }

        if (!factions) return;

        // 遍历相关阵营桶
        for (var f:Number = 0; f < factions.length; f++) {
            var bucket:Array = _registry[factions[f]];
            if (!bucket) continue;
            for (var i:Number = 0; i < bucket.length; i++) {
                var u:Object = bucket[i];
                if (u.hp > 0) {
                    u.aabbCollider.updateFromUnitArea(targetList[targetList.length] = u);
                }
            }
        }
    }

    /**
     * 从注册表收集所有有效单位
     * 遍历所有阵营桶而非 gameWorld 全量扫描。
     *
     * @param {Object} gameWorld - 游戏世界对象（保留参数签名兼容性）
     * @param {Array} targetList - 存储所有有效单位（输出参数）
     * @private
     */
    private static function _collectAllValidUnits(
        gameWorld:Object,
        targetList:Array
    ):Void {
        for (var factionId:String in _registry) {
            var bucket:Array = _registry[factionId];
            for (var i:Number = 0; i < bucket.length; i++) {
                var u:Object = bucket[i];
                if (u.hp > 0) {
                    u.aabbCollider.updateFromUnitArea(targetList[targetList.length] = u);
                }
            }
        }
    }

    // ========================================================================
    // 校验重排（Reconciliation）
    // ========================================================================

    /**
     * 定期校验：全量扫描 gameWorld 重建注册表并预排序
     *
     * 1. 清空现有注册表
     * 2. 遍历 gameWorld 重建 _registry / _registryMap（仅 hp > 0 的单位）
     * 3. 异常检测：如果数量与 _registryCount 不一致，强制 bump 所有版本刷新缓存
     * 4. 对每个桶按 aabbCollider.left 预排序（插入排序），
     *    使后续 "全体" 查询拼接时 TimSort 可识别 natural runs → O(n) 归并
     *
     * @param {Object} gameWorld - 游戏世界对象
     * @param {Number} currentFrame - 当前帧号
     * @private
     */
    private static function _reconcile(gameWorld:Object, currentFrame:Number):Void {
        // 1. 清空注册表
        for (var fid:String in _registry) {
            _registry[fid].length = 0;
        }
        for (var oldName:String in _registryMap) {
            delete _registryMap[oldName];
        }
        var newCount:Number = 0;

        // 2. 全量扫描 gameWorld 重建注册表
        for (var key:String in gameWorld) {
            var u:Object = gameWorld[key];
            if (u.hp > 0) {
                var faction:String = FactionManager.getFactionFromUnit(u);
                if (!_registry[faction]) {
                    _registry[faction] = [];
                }
                _registry[faction].push(u);
                _registryMap[u._name] = faction;
                newCount++;
            }
        }

        // 3. 异常检测：数量不一致时强制刷新所有缓存
        if (newCount != _registryCount) {
            for (var f:String in _factionVersions) {
                _factionVersions[f]++;
            }
        }
        _registryCount = newCount;

        // 4. 预排序每个桶（按 left 升序，插入排序）
        for (var fid2:String in _registry) {
            var bucket:Array = _registry[fid2];
            var bLen:Number = bucket.length;
            if (bLen > 1) {
                for (var i:Number = 1; i < bLen; i++) {
                    var keyUnit:Object = bucket[i];
                    var leftVal:Number = keyUnit.aabbCollider.left;
                    var j:Number = i - 1;
                    while (j >= 0 && bucket[j].aabbCollider.left > leftVal) {
                        bucket[j + 1] = bucket[j];
                        j--;
                    }
                    bucket[j + 1] = keyUnit;
                }
            }
        }

        // 5. 更新校验时间戳
        _lastReconcileFrame = currentFrame;
    }

    // ========================================================================
    // 【重构】基于阵营的版本控制
    // ========================================================================

    /**
     * 从指定阵营桶中移除单位（swap-and-pop）
     * 不保序，由 _reconcile 定期重排恢复顺序。
     * 桶大小典型 < 50，线性扫描足够快。
     *
     * @param {String} name - 单位名称
     * @param {String} faction - 目标阵营ID
     * @private
     */
    private static function _removeFromBucket(name:String, faction:String):Void {
        var bucket:Array = _registry[faction];
        if (!bucket) return;
        var len:Number = bucket.length;
        for (var i:Number = 0; i < len; i++) {
            if (bucket[i]._name == name) {
                bucket[i] = bucket[len - 1];
                bucket.length = len - 1;
                return;
            }
        }
    }

    /**
     * 添加单位时更新版本号并维护注册表
     * 处理重复注册（如 respawn）和阵营变更。
     *
     * @param {Object} unit - 新增的单位对象
     */
    public static function addUnit(unit:Object):Void {
        var faction:String = FactionManager.getFactionFromUnit(unit);
        var name:String = unit._name;

        // 处理重复注册：检查是否已在注册表中
        var oldFaction:String = _registryMap[name];
        if (oldFaction !== undefined) {
            if (oldFaction == faction) {
                // 同阵营重复注册（如 respawn），仅 bump 版本
                if (!_factionVersions[faction]) {
                    _factionVersions[faction] = 0;
                }
                _factionVersions[faction]++;
                return;
            }
            // 阵营变更，从旧桶移除
            _removeFromBucket(name, oldFaction);
            _registryCount--;
        }

        // 添加到对应阵营桶
        if (!_registry[faction]) {
            _registry[faction] = [];
        }
        _registry[faction].push(unit);
        _registryMap[name] = faction;
        _registryCount++;

        // 版本 bump
        if (!_factionVersions[faction]) {
            _factionVersions[faction] = 0;
        }
        _factionVersions[faction]++;
    }
    
    /**
     * 移除单位时更新版本号并从注册表中删除
     *
     * @param {Object} unit - 被移除的单位对象
     */
    public static function removeUnit(unit:Object):Void {
        var faction:String = FactionManager.getFactionFromUnit(unit);
        var name:String = unit._name;

        // 从注册表移除（使用 registryMap 定位正确的桶）
        var registeredFaction:String = _registryMap[name];
        if (registeredFaction !== undefined) {
            _removeFromBucket(name, registeredFaction);
            delete _registryMap[name];
            _registryCount--;
        }

        // 版本 bump
        if (!_factionVersions[faction]) {
            _factionVersions[faction] = 0;
        }
        _factionVersions[faction]++;
    }

    /**
     * 批量添加单位
     * 维护注册表并批量更新版本号。
     *
     * @param {Array} units - 要添加的单位数组
     */
    public static function addUnits(units:Array):Void {
        var factionCounts:Object = {};

        for (var i:Number = 0; i < units.length; i++) {
            var unit:Object = units[i];
            var faction:String = FactionManager.getFactionFromUnit(unit);
            var name:String = unit._name;

            // 注册表维护：处理重复注册
            var oldFaction:String = _registryMap[name];
            if (oldFaction !== undefined) {
                if (oldFaction == faction) {
                    // 同阵营重复，跳过注册表操作，仅统计版本
                    if (!factionCounts[faction]) factionCounts[faction] = 0;
                    factionCounts[faction]++;
                    continue;
                }
                // 阵营变更
                _removeFromBucket(name, oldFaction);
                _registryCount--;
            }

            if (!_registry[faction]) {
                _registry[faction] = [];
            }
            _registry[faction].push(unit);
            _registryMap[name] = faction;
            _registryCount++;

            if (!factionCounts[faction]) factionCounts[faction] = 0;
            factionCounts[faction]++;
        }

        // 批量更新版本号
        for (var factionId:String in factionCounts) {
            if (!_factionVersions[factionId]) {
                _factionVersions[factionId] = 0;
            }
            _factionVersions[factionId] += factionCounts[factionId];
        }
    }

    /**
     * 批量移除单位
     * 维护注册表并批量更新版本号。
     *
     * @param {Array} units - 要移除的单位数组
     */
    public static function removeUnits(units:Array):Void {
        var factionCounts:Object = {};

        for (var i:Number = 0; i < units.length; i++) {
            var unit:Object = units[i];
            var faction:String = FactionManager.getFactionFromUnit(unit);
            var name:String = unit._name;

            // 注册表维护
            var registeredFaction:String = _registryMap[name];
            if (registeredFaction !== undefined) {
                _removeFromBucket(name, registeredFaction);
                delete _registryMap[name];
                _registryCount--;
            }

            if (!factionCounts[faction]) factionCounts[faction] = 0;
            factionCounts[faction]++;
        }

        // 批量更新版本号
        for (var factionId:String in factionCounts) {
            if (!_factionVersions[factionId]) {
                _factionVersions[factionId] = 0;
            }
            _factionVersions[factionId] += factionCounts[factionId];
        }
    }

    /**
     * 获取版本号信息
     * 【重构】返回基于阵营的版本信息
     * 
     * @return {Object} 包含所有版本号的对象
     */
    public static function getVersionInfo():Object {
        var info:Object = {
            factionVersions: {},
            totalVersion: 0
        };
        
        for (var faction:String in _factionVersions) {
            info.factionVersions[faction] = _factionVersions[faction];
            info.totalVersion += _factionVersions[faction];
        }
        
        // 【向后兼容】提供旧版本号映射
        info.enemyVersion = _factionVersions[FactionManager.FACTION_ENEMY] || 0;
        info.allyVersion = _factionVersions[FactionManager.FACTION_PLAYER] || 0;
        
        return info;
    }

    /**
     * 重置所有版本号
     * 【重构】重置所有阵营的版本号
     */
    public static function resetVersions():Void {
        // 重置所有阵营版本号
        for (var faction:String in _factionVersions) {
            _factionVersions[faction] = 0;
        }

        // 清空缓存池
        for (var key:String in _cachePool) {
            delete _cachePool[key];
        }
        _cachePool = {};

        // 清空注册表
        for (var fid:String in _registry) {
            _registry[fid].length = 0;
        }
        for (var rName:String in _registryMap) {
            delete _registryMap[rName];
        }
        _registryCount = 0;
        _lastReconcileFrame = -1; // 强制下次 updateCache 时重新校验
    }

    /**
     * 获取当前版本号
     * 【新增】用于外部查询当前的全局版本号
     * 
     * @return {Number} 当前的全局版本号
     */
    public static function getCurrentVersion():Number {
        var totalVersion:Number = 0;
        for (var faction:String in _factionVersions) {
            totalVersion += _factionVersions[faction];
        }
        return totalVersion;
    }

    // ========================================================================
    // 以下方法保持不变，继承自原版本
    // ========================================================================
    
    public static function setAdaptiveParams(
        alpha:Number,
        densityFactor:Number,
        minThreshold:Number,
        maxThreshold:Number
    ):Void {
        AdaptiveThresholdOptimizer.setParams(alpha, densityFactor, minThreshold, maxThreshold);
    }

    public static function applyThresholdPreset(presetName:String):Boolean {
        return AdaptiveThresholdOptimizer.applyPreset(presetName);
    }

    public static function getCurrentThreshold():Number {
        return AdaptiveThresholdOptimizer.getThreshold();
    }

    public static function getThresholdStatus():Object {
        return AdaptiveThresholdOptimizer.getStatus();
    }

    public static function getCachePoolStats():Object {
        var stats:Object = {
            totalPools: 0,
            poolDetails: {},
            memoryUsage: 0,
            registryCount: _registryCount,
            registryBuckets: {},
            lastReconcileFrame: _lastReconcileFrame
        };

        for (var key:String in _cachePool) {
            var pool:Object = _cachePool[key];
            stats.totalPools++;
            stats.poolDetails[key] = {
                listLength: pool.tempList.length,
                version: pool.tempVersion
            };
            stats.memoryUsage++;
        }

        for (var fid:String in _registry) {
            stats.registryBuckets[fid] = _registry[fid].length;
        }

        return stats;
    }

    public static function clearCachePool(requestType:String):Void {
        if (requestType) {
            for (var key:String in _cachePool) {
                if (key.indexOf(requestType) == 0) {
                    delete _cachePool[key];
                }
            }
        } else {
            for (var key2:String in _cachePool) {
                delete _cachePool[key2];
            }
            _cachePool = {};
        }
    }

    public static function getDetailedStatusReport():String {
        var versionInfo:Object = getVersionInfo();
        var poolStats:Object = getCachePoolStats();
        var thresholdStatus:Object = getThresholdStatus();
        
        var report:String = "=== TargetCacheUpdater Status Report ===\n\n";
        
        // 版本信息（基于阵营）
        report += "Faction Version Numbers:\n";
        for (var faction:String in versionInfo.factionVersions) {
            report += "  " + faction + ": " + versionInfo.factionVersions[faction] + "\n";
        }
        report += "  Total Updates: " + versionInfo.totalVersion + "\n\n";
        
        // 缓存池信息
        report += "Cache Pool Stats:\n";
        report += "  Active Pools: " + poolStats.totalPools + "\n";
        report += "  Total Units Cached: " + poolStats.memoryUsage + "\n";
        for (var key:String in poolStats.poolDetails) {
            var detail:Object = poolStats.poolDetails[key];
            report += "  " + key + ": " + detail.listLength + " units (v" + detail.version + ")\n";
        }
        report += "\n";
        
        // 阈值优化器信息
        report += "Threshold Optimizer:\n";
        report += "  Current Threshold: " + Math.round(thresholdStatus.currentThreshold) + "px\n";
        report += "  Avg Density: " + Math.round(thresholdStatus.avgDensity) + "px\n";
        report += "  Optimizer Version: " + thresholdStatus.version + "\n";
        
        // 注册表状态
        report += "\nUnit Registry:\n";
        report += "  Total Units: " + _registryCount + "\n";
        report += "  Last Reconcile Frame: " + _lastReconcileFrame + "\n";
        report += "  Reconcile Interval: " + RECONCILE_INTERVAL + " frames\n";
        for (var fid:String in _registry) {
            report += "  " + fid + ": " + _registry[fid].length + " units\n";
        }

        // FactionManager 状态
        report += "\nFactionManager Integration:\n";
        report += "  Status: Integrated\n";
        report += "  Registered Factions: " + FactionManager.getAllFactions().length + "\n";

        return report;
    }

    public static function performSelfCheck():Object {
        var result:Object = {
            passed: true,
            errors: [],
            warnings: [],
            performance: {}
        };
        
        // 检查FactionManager是否可用
        if (!FactionManager) {
            result.errors.push("FactionManager not available");
            result.passed = false;
        } else {
            try {
                var testFactions:Array = FactionManager.getAllFactions();
                if (!testFactions || testFactions.length == 0) {
                    result.warnings.push("No factions registered in FactionManager");
                }
            } catch (e:Error) {
                result.errors.push("FactionManager access error: " + e.message);
                result.passed = false;
            }
        }
        
        // 检查AdaptiveThresholdOptimizer是否可用
        try {
            var threshold:Number = AdaptiveThresholdOptimizer.getThreshold();
            if (isNaN(threshold) || threshold <= 0) {
                result.errors.push("Invalid threshold value: " + threshold);
                result.passed = false;
            }
        } catch (e2:Error) {
            result.errors.push("AdaptiveThresholdOptimizer not accessible: " + e2.message);
            result.passed = false;
        }
        
        // 检查缓存池完整性
        var poolStats:Object = getCachePoolStats();
        if (poolStats.totalPools > 10) {
            result.warnings.push("Large number of cache pools (" + poolStats.totalPools + "), consider cleanup");
        }
        
        // 检查版本号一致性
        var allPositive:Boolean = true;
        for (var faction:String in _factionVersions) {
            if (_factionVersions[faction] < 0) {
                result.errors.push("Negative version number for faction: " + faction);
                result.passed = false;
                allPositive = false;
            }
        }
        
        // 检查注册表一致性
        var registryMapCount:Number = 0;
        for (var rName:String in _registryMap) {
            registryMapCount++;
        }
        var bucketTotal:Number = 0;
        for (var fid:String in _registry) {
            bucketTotal += _registry[fid].length;
        }
        if (registryMapCount != _registryCount || bucketTotal != _registryCount) {
            result.warnings.push("Registry count mismatch: counter=" + _registryCount
                + " map=" + registryMapCount + " buckets=" + bucketTotal);
        }

        result.performance.cachePoolCount = poolStats.totalPools;
        result.performance.totalCachedUnits = poolStats.memoryUsage;
        result.performance.currentThreshold = threshold;
        result.performance.factionManagerIntegrated = true;
        result.performance.registryCount = _registryCount;
        result.performance.lastReconcileFrame = _lastReconcileFrame;

        return result;
    }
}
