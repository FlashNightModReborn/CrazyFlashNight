// ============================================================================
// 阵营关系管理器 (FactionManager) - 性能优化版
// ----------------------------------------------------------------------------
// 优化要点：
// 1. 消除 isValidFaction 循环，改用哈希表 O(1) 查找
// 2. 内联 getRelationship，减少函数调用开销
// 3. 重写 getFactionFromUnit，避免类型转换
// 4. 预计算并缓存阵营列表，避免重复遍历
// 5. 关键路径方法进一步内联优化
// ============================================================================

class org.flashNight.arki.unit.UnitComponent.Targetcache.FactionManager {

    // ========================================================================
    // 阵营常量定义 (The "Who")
    // ========================================================================
    
    public static var FACTION_PLAYER:String = "PLAYER";
    public static var FACTION_ENEMY:String = "ENEMY"; 
    public static var FACTION_HOSTILE_NEUTRAL:String = "HOSTILE_NEUTRAL";
    
    private static var _allFactions:Array = [
        FACTION_PLAYER, 
        FACTION_ENEMY, 
        FACTION_HOSTILE_NEUTRAL
    ];

    // ========================================================================
    // 关系状态常量 (The "How they feel")
    // ========================================================================
    
    public static var RELATION_ALLY:String = "ALLY";
    public static var RELATION_ENEMY:String = "ENEMY";
    public static var RELATION_NEUTRAL:String = "NEUTRAL";
    public static var RELATION_SELF:String = "SELF";

    // ========================================================================
    // 核心数据结构 + 性能优化缓存
    // ========================================================================
    
    private static var _relationMatrix:Object;
    private static var _factionMetadata:Object;
    
    // 【优化1】用哈希表替代循环查找，O(N) -> O(1)
    private static var _validFactionsMap:Object;
    
    // 【优化2】缓存阵营列表查询结果，避免重复遍历
    private static var _enemyFactionsCache:Object;
    private static var _allyFactionsCache:Object;
    private static var _cacheValid:Boolean = false;
    
    private static var _initialized:Boolean = initialize();

    // ========================================================================
    // 初始化方法
    // ========================================================================
    
    public static function initialize():Boolean {
        try {
            _relationMatrix = {};
            _factionMetadata = {};
            _validFactionsMap = {};
            _enemyFactionsCache = {};
            _allyFactionsCache = {};
            
            registerDefaultFactions();
            setupDefaultRelations();
            rebuildCaches();
            
            return true;
        } catch (error:Error) {
            trace("FactionManager初始化失败: " + error.message);
            return false;
        }
    }
    
    private static function registerDefaultFactions():Void {
        registerFaction(FACTION_PLAYER, {
            name: "玩家阵营",
            description: "玩家控制的单位",
            color: 0x0066FF,
            legacyValue: false
        });
        
        registerFaction(FACTION_ENEMY, {
            name: "敌对阵营", 
            description: "传统敌人单位",
            color: 0xFF0000,
            legacyValue: true
        });
        
        registerFaction(FACTION_HOSTILE_NEUTRAL, {
            name: "中立敌对",
            description: "对所有阵营都敌对的中立单位",
            color: 0x808080,
            legacyValue: null
        });
    }
    
    private static function setupDefaultRelations():Void {
        // 玩家阵营关系
        setRelationship(FACTION_PLAYER, FACTION_PLAYER, RELATION_ALLY);
        setRelationship(FACTION_PLAYER, FACTION_ENEMY, RELATION_ENEMY);
        setRelationship(FACTION_PLAYER, FACTION_HOSTILE_NEUTRAL, RELATION_ENEMY);
        
        // 敌对阵营关系
        setRelationship(FACTION_ENEMY, FACTION_PLAYER, RELATION_ENEMY);
        setRelationship(FACTION_ENEMY, FACTION_ENEMY, RELATION_ALLY);
        setRelationship(FACTION_ENEMY, FACTION_HOSTILE_NEUTRAL, RELATION_ENEMY);
        
        // 中立敌对阵营关系
        setRelationship(FACTION_HOSTILE_NEUTRAL, FACTION_PLAYER, RELATION_ENEMY);
        setRelationship(FACTION_HOSTILE_NEUTRAL, FACTION_ENEMY, RELATION_ENEMY);
        setRelationship(FACTION_HOSTILE_NEUTRAL, FACTION_HOSTILE_NEUTRAL, RELATION_ALLY);
    }

    // ========================================================================
    // 阵营注册与管理 + 缓存管理
    // ========================================================================
    
    public static function registerFaction(factionId:String, metadata:Object):Boolean {
        if (!factionId || factionId.length == 0) {
            trace("FactionManager: 无效的阵营ID");
            return false;
        }
        
        // 初始化关系行
        if (!_relationMatrix[factionId]) {
            _relationMatrix[factionId] = {};
        }
        
        // 【优化1】更新有效阵营哈希表
        _validFactionsMap[factionId] = true;
        
        if (metadata && metadata.hasOwnProperty("legacyValue")) {
            metadata.legacyValue = String(metadata.legacyValue);
        }
        
        _factionMetadata[factionId] = metadata || {};
        
        // 添加到阵营列表
        var found:Boolean = false;
        for (var i:Number = 0; i < _allFactions.length; i++) {
            if (_allFactions[i] == factionId) {
                found = true;
                break;
            }
        }
        if (!found) {
            _allFactions.push(factionId);
        }
        
        // 【优化2】标记缓存失效
        _cacheValid = false;
        
        return true;
    }
    
    public static function getAllFactions():Array {
        return _allFactions.slice();
    }
    
    public static function getFactionMetadata(factionId:String):Object {
        return _factionMetadata[factionId] || {};
    }

    // ========================================================================
    // 关系设置与查询 + 内联优化
    // ========================================================================
    
    public static function setRelationship(
        fromFaction:String, 
        toFaction:String, 
        relationStatus:String
    ):Boolean {
        // 【优化1】用哈希查找替代循环，isValidFaction 内联
        if (!fromFaction || fromFaction.length == 0 || !_validFactionsMap[fromFaction] ||
            !toFaction || toFaction.length == 0 || !_validFactionsMap[toFaction]) {
            trace("FactionManager: 无效的阵营ID - " + fromFaction + " 或 " + toFaction);
            return false;
        }
        
        if (relationStatus != RELATION_ALLY && 
            relationStatus != RELATION_ENEMY && 
            relationStatus != RELATION_NEUTRAL && 
            relationStatus != RELATION_SELF) {
            trace("FactionManager: 无效的关系状态 - " + relationStatus);
            return false;
        }
        
        if (!_relationMatrix[fromFaction]) {
            _relationMatrix[fromFaction] = {};
        }
        
        _relationMatrix[fromFaction][toFaction] = relationStatus;
        
        // 【优化2】标记缓存失效
        _cacheValid = false;
        
        return true;
    }
    
    /**
     * 【优化2】高性能版 getRelationship - 内联所有验证逻辑
     */
    public static function getRelationship(fromFaction:String, toFaction:String):String {
        // 快速路径：自身关系
        if (fromFaction == toFaction) {
            return RELATION_SELF;
        }
        
        // 快速路径：直接查表，不做额外验证
        // 假设：_relationMatrix 中的键都是有效阵营
        return _relationMatrix[fromFaction][toFaction] || RELATION_NEUTRAL;
    }

    // ========================================================================
    // 便捷查询方法 + 进一步内联优化
    // ========================================================================
    
    /**
     * 【优化3】超高性能版 areEnemies - 完全内联
     */
    public static function areEnemies(factionA:String, factionB:String):Boolean {
        // 自身不是敌人
        // 默认中立，不是敌人

        return (_relationMatrix[factionA][factionB] == RELATION_ENEMY) || false;
    }
    
    /**
     * 【优化3】超高性能版 areAllies - 完全内联  
     */
    public static function areAllies(factionA:String, factionB:String):Boolean {
        // 自身是盟友
        // 默认中立，不是盟友
        return (_relationMatrix[factionA][factionB] == RELATION_ALLY) || false;
    }
    
    public static function areNeutral(factionA:String, factionB:String):Boolean {
        return getRelationship(factionA, factionB) == RELATION_NEUTRAL;
    }
    
    /**
     * 【优化2】缓存版 getEnemyFactions
     */
    public static function getEnemyFactions(observerFaction:String):Array {
        if (!_validFactionsMap[observerFaction]) {
            return [];
        }
        
        // 如果缓存有效，直接返回
        if (_cacheValid && _enemyFactionsCache[observerFaction]) {
            return _enemyFactionsCache[observerFaction].slice(); // 返回副本
        }
        
        // 重建缓存
        if (!_cacheValid) {
            rebuildCaches();
        }
        
        return _enemyFactionsCache[observerFaction] ? 
               _enemyFactionsCache[observerFaction].slice() : [];
    }
    
    /**
     * 【优化2】缓存版 getAllyFactions
     */
    public static function getAllyFactions(observerFaction:String):Array {
        if (!_validFactionsMap[observerFaction]) {
            return [];
        }
        
        if (_cacheValid && _allyFactionsCache[observerFaction]) {
            return _allyFactionsCache[observerFaction].slice();
        }
        
        if (!_cacheValid) {
            rebuildCaches();
        }
        
        return _allyFactionsCache[observerFaction] ? 
               _allyFactionsCache[observerFaction].slice() : [];
    }
    
    /**
     * 【优化2】重建阵营列表缓存
     */
    private static function rebuildCaches():Void {
        _enemyFactionsCache = {};
        _allyFactionsCache = {};
        
        for (var i:Number = 0; i < _allFactions.length; i++) {
            var observerFaction:String = _allFactions[i];
            var enemies:Array = [];
            var allies:Array = [];
            
            for (var j:Number = 0; j < _allFactions.length; j++) {
                var targetFaction:String = _allFactions[j];
                
                if (areEnemies(observerFaction, targetFaction)) {
                    enemies.push(targetFaction);
                } else if (areAllies(observerFaction, targetFaction)) {
                    allies.push(targetFaction);
                }
            }
            
            _enemyFactionsCache[observerFaction] = enemies;
            _allyFactionsCache[observerFaction] = allies;
        }
        
        _cacheValid = true;
    }

    // ========================================================================
    // 适配器方法 + 极致性能优化
    // ========================================================================

    /**
     * 【优化3】极高性能版 getFactionFromUnit - 避免类型转换和哈希查找
     */
    public static function getFactionFromUnit(unit:Object):String {
        if (!unit) {
            return FACTION_HOSTILE_NEUTRAL;
        }
        
        var isEnemy = unit.是否为敌人;
        
        // 直接分支判断，避免 String() 转换和哈希查找
        if (isEnemy === true) {
            return FACTION_ENEMY;
        } else if (isEnemy === false) {
            return FACTION_PLAYER;
        } else {
            // null, undefined, 或其他值都映射到中立敌对
            return FACTION_HOSTILE_NEUTRAL;
        }
    }
    
    public static function getLegacyValueFromFaction(factionId:String) {
        var metadata:Object = getFactionMetadata(factionId);
        return metadata.legacyValue;
    }
    
    /**
     * 【优化3】超高性能版 areUnitsEnemies - 内联 getFactionFromUnit
     */
    public static function areUnitsEnemies(unitA:Object, unitB:Object):Boolean {
        // 内联单位阵营获取，避免函数调用
        var factionA:String;
        var factionB:String;
        
        var isEnemyA = unitA.是否为敌人;
        if (isEnemyA === true) {
            factionA = FACTION_ENEMY;
        } else {
            factionA = (isEnemyA === false) ? FACTION_PLAYER : FACTION_HOSTILE_NEUTRAL;
        }
    
        var isEnemyB = unitB.是否为敌人;
        if (isEnemyB === true) {
            factionB = FACTION_ENEMY;
        } else {
            factionB = (isEnemyB === false) ? FACTION_PLAYER : FACTION_HOSTILE_NEUTRAL;
        }
        
        // 内联 areEnemies 逻辑
        return (_relationMatrix[factionA][factionB] == RELATION_ENEMY) || false;
    }
    
    /**
     * 【优化3】超高性能版 areUnitsAllies - 内联所有逻辑
     */
    public static function areUnitsAllies(unitA:Object, unitB:Object):Boolean {
        // 内联单位阵营获取
        var factionA:String;
        var factionB:String;

        var isEnemyA = unitA.是否为敌人;
        if (isEnemyA === true) {
            factionA = FACTION_ENEMY;
        } else  {
            factionA = (isEnemyA === false) ? FACTION_PLAYER : FACTION_HOSTILE_NEUTRAL;
        }
        
        var isEnemyB = unitB.是否为敌人;
        if (isEnemyB === true) {
            factionB = FACTION_ENEMY;
        } else  {
            factionB = (isEnemyB === false) ? FACTION_PLAYER : FACTION_HOSTILE_NEUTRAL;
        }
        
        // 内联 areAllies 逻辑
        return _relationMatrix[factionA][factionB] == RELATION_ALLY || false
    }

    // ========================================================================
    // 缓存系统集成方法
    // ========================================================================
    
    public static function shouldIncludeInEnemyQuery(requester:Object, target:Object):Boolean {
        return areUnitsEnemies(requester, target);
    }
    
    public static function shouldIncludeInAllyQuery(requester:Object, target:Object):Boolean {
        return areUnitsAllies(requester, target);
    }
    
    public static function getCacheKeySuffix(unit:Object):String {
        return getFactionFromUnit(unit);
    }

    // ========================================================================
    // 高级功能方法 + 缓存失效处理
    // ========================================================================
    
    public static function setBatchRelationships(relationshipData:Array):Number {
        var successCount:Number = 0;
        
        for (var i:Number = 0; i < relationshipData.length; i++) {
            var data:Object = relationshipData[i];
            if (setRelationship(data.from, data.to, data.relation)) {
                successCount++;
            }
        }
        
        return successCount;
    }
    
    public static function getRelationshipMatrix():Object {
        var matrix:Object = {};
        
        for (var fromFaction:String in _relationMatrix) {
            matrix[fromFaction] = {};
            var fromRow:Object = _relationMatrix[fromFaction];
            
            for (var toFaction:String in fromRow) {
                matrix[fromFaction][toFaction] = fromRow[toFaction];
            }
        }
        
        return matrix;
    }
    
    public static function loadRelationshipMatrix(matrixData:Object):Boolean {
        if (!matrixData) return false;
        
        try {
            _relationMatrix = {};
            
            for (var fromFaction:String in matrixData) {
                _relationMatrix[fromFaction] = {};
                var fromRow:Object = matrixData[fromFaction];
                
                for (var toFaction:String in fromRow) {
                    _relationMatrix[fromFaction][toFaction] = fromRow[toFaction];
                }
            }
            
            // 【优化2】重建缓存
            _cacheValid = false;
            
            return true;
        } catch (error:Error) {
            trace("FactionManager: 加载关系矩阵失败 - " + error.message);
            return false;
        }
    }

    // ========================================================================
    // 验证和工具方法 - 保持向后兼容
    // ========================================================================
    
    // 保留原有的验证方法，但内部使用哈希查找
    private static function isValidFaction(factionId:String):Boolean {
        return factionId && factionId.length > 0 && _validFactionsMap[factionId];
    }
    
    private static function isValidRelation(relationStatus:String):Boolean {
        return relationStatus == RELATION_ALLY || 
               relationStatus == RELATION_ENEMY || 
               relationStatus == RELATION_NEUTRAL || 
               relationStatus == RELATION_SELF;
    }

    // ========================================================================
    // 调试和诊断方法 - 性能友好版本  
    // ========================================================================
    
    public static function getRelationshipReport():String {
        var report:String = "=== FactionManager 关系报告 ===\n\n";
        
        report += "已注册阵营 (" + _allFactions.length + " 个):\n";
        for (var i:Number = 0; i < _allFactions.length; i++) {
            var factionId:String = _allFactions[i];
            var metadata:Object = getFactionMetadata(factionId);
            report += "  " + factionId + ": " + (metadata.name || "未命名") + "\n";
        }
        
        report += "\n关系矩阵:\n";
        report += "From\\To\t";
        for (var j:Number = 0; j < _allFactions.length; j++) {
            report += _allFactions[j].substr(0, 8) + "\t";
        }
        report += "\n";
        
        for (var k:Number = 0; k < _allFactions.length; k++) {
            var fromFaction:String = _allFactions[k];
            report += fromFaction.substr(0, 8) + "\t";
            
            for (var l:Number = 0; l < _allFactions.length; l++) {
                var toFaction:String = _allFactions[l];
                var relation:String = getRelationship(fromFaction, toFaction);
                var shortRelation:String = relation.substr(0, 4).toUpperCase();
                report += shortRelation + "\t\t";
            }
            report += "\n";
        }
        
        report += "\n缓存状态: " + (_cacheValid ? "有效" : "失效");
        
        return report;
    }
    
    public static function validateMatrix():Object {
        var result:Object = {
            isValid: true,
            errors: [],
            warnings: []
        };
        
        for (var i:Number = 0; i < _allFactions.length; i++) {
            var fromFaction:String = _allFactions[i];
            
            if (!_relationMatrix[fromFaction]) {
                result.errors.push("阵营 " + fromFaction + " 缺少关系定义");
                result.isValid = false;
                continue;
            }
            
            for (var j:Number = 0; j < _allFactions.length; j++) {
                var toFaction:String = _allFactions[j];
                var relation:String = _relationMatrix[fromFaction][toFaction];
                
                if (!relation) {
                    result.warnings.push("阵营关系未定义: " + fromFaction + " -> " + toFaction);
                } else if (!isValidRelation(relation)) {
                    result.errors.push("无效关系: " + fromFaction + " -> " + toFaction + " = " + relation);
                    result.isValid = false;
                }
            }
        }
        
        return result;
    }
    
    public static function getStatus():Object {
        return {
            initialized: _initialized,
            factionCount: _allFactions.length,
            allFactions: _allFactions.slice(),
            matrixValidation: validateMatrix(),
            cacheValid: _cacheValid
        };
    }
    
    /**
     * 【新增】手动刷新缓存的公共方法
     */
    public static function refreshCaches():Void {
        rebuildCaches();
    }
}