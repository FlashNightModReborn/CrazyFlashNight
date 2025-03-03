// 文件路径: org/flashNight/arki/unit/UnitComponent/targetcache/TargetCacheUpdater.as
import org.flashNight.naki.Sort.InsertionSort;

class org.flashNight.arki.unit.UnitComponent.Targetcache.TargetCacheUpdater {
    // 静态临时列表用于缓存计算
    private static var _tempList:Array = [];
    
    // 配置常量
    private static var _SORT_KEY:String = "right";
    private static var _ENEMY_TYPE:String = "敌人";
    private static var _ALLY_TYPE:String = "友军";
    
    // 核心更新方法
    public static function updateCache(
        gameWorld:Object,
        currentFrame:Number,
        requestType:String,
        targetIsEnemy:Boolean,
        cacheEntry:Object
    ):Void {
        // 清空临时列表
        _tempList.length = 0;
        
        // 阶段1：收集存活单位
        _collectValidUnits(gameWorld, targetIsEnemy, requestType == _ENEMY_TYPE);
        
        // 阶段2：版本对比
        var newVersion:String = _generateDataVersion(_tempList);
        if (_shouldSkipUpdate(cacheEntry, newVersion)) {
            cacheEntry.lastUpdatedFrame = currentFrame; // 保持帧数更新
            return;
        }
        
        // 阶段3：排序处理
        _performSorting();
        
        // 阶段4：构建缓存结构
        _rebuildCacheData(cacheEntry, currentFrame, newVersion);
    }

    // 收集有效单位（保持独立扩展性）
    private static function _collectValidUnits(
        gameWorld:Object,
        requesterIsEnemy:Boolean,
        isEnemyRequest:Boolean
    ):Void {
        for (var unitKey:String in gameWorld) {
            var unit:Object = gameWorld[unitKey];
            if (!_isUnitValid(unit, requesterIsEnemy, isEnemyRequest)) continue;
            
            unit.aabbCollider.updateFromUnitArea(unit);
            _tempList.push(unit);
        }
    }

    // 单位有效性验证
    private static function _isUnitValid(
        unit:Object,
        requesterIsEnemy:Boolean,
        isEnemyRequest:Boolean
    ):Boolean {
        if (unit.hp <= 0) return false;
        var unitIsEnemy:Boolean = unit.是否为敌人;
        return isEnemyRequest ? 
            (requesterIsEnemy != unitIsEnemy) : 
            (requesterIsEnemy == unitIsEnemy);
    }

    // 生成数据版本标识（后续可改为增量更新）
    private static function _generateDataVersion(units:Array):String {
        var versionBuffer:Array = [];
        for (var i:Number = 0; i < units.length; i++) {
            var u:Object = units[i];
            versionBuffer.push(
                u._name, 
                u.hp, 
                u.aabbCollider.right
            );
        }
        return versionBuffer.join("|");
    }

    // 更新决策逻辑（分离便于后续扩展）
    private static function _shouldSkipUpdate(cache:Object, newVersion:String):Boolean {
        return cache.dataVersion === newVersion;
    }

    // 排序处理
    private static function _performSorting():Void {
        InsertionSort.sort(_tempList, function(a:Object, b:Object):Number {
            return a.aabbCollider[_SORT_KEY] - b.aabbCollider[_SORT_KEY];
        });
    }

    // 重建缓存数据结构
    private static function _rebuildCacheData(
        cacheEntry:Object, 
        currentFrame:Number,
        newVersion:String
    ):Void {
        var newData:Array = [];
        var newNameIndex:Object = {};
        
        for (var i:Number = 0; i < _tempList.length; i++) {
            newData.push(_tempList[i]);
            newNameIndex[_tempList[i]._name] = i;
        }
        
        // 原子性更新
        cacheEntry.data = newData;
        cacheEntry.nameIndex = newNameIndex;
        cacheEntry.lastUpdatedFrame = currentFrame;
        cacheEntry.dataVersion = newVersion;
    }
}
