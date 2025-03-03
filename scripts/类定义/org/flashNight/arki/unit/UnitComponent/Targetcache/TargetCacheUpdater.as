// 文件路径: org/flashNight/arki/unit/UnitComponent/targetcache/TargetCacheUpdater.as
import org.flashNight.naki.Sort.InsertionSort;

class org.flashNight.arki.unit.UnitComponent.targetcache.TargetCacheUpdater {
    // 静态临时列表用于缓存计算（后续可拓展环形缓冲区等优化）
    private static var _tempList:Array = [];
    
    // 配置常量
    private static var _SORT_KEY:String = "right";
    private static var _ENEMY_TYPE:String = "敌人";
    private static var _ALLY_TYPE:String = "友军";
    
    // 核心更新方法
    public static function updateCache(
        gameWorld:Object,        // 游戏世界对象
        currentFrame:Number,     // 当前帧数
        requestType:String,      // 请求类型（敌人/友军）
        targetIsEnemy:Boolean,   // 请求者的敌我状态
        cacheEntry:Object       // 要更新的缓存条目
    ):Void {
        // 清空临时列表（保持数组引用避免GC）
        _tempList.length = 0;
        
        // 阶段1：收集存活单位
        _collectValidUnits(gameWorld, targetIsEnemy, requestType == _ENEMY_TYPE);
        
        // 阶段2：排序处理
        _performSorting();
        
        // 阶段3：构建缓存结构
        _rebuildCacheData(cacheEntry, currentFrame);
    }

    // 收集有效单位（独立为方法便于后续扩展过滤条件）
    private static function _collectValidUnits(
        gameWorld:Object,
        requesterIsEnemy:Boolean,
        isEnemyRequest:Boolean
    ):Void {
        for (var unitKey:String in gameWorld) {
            var unit:Object = gameWorld[unitKey];
            if (!_isUnitValid(unit, requesterIsEnemy, isEnemyRequest)) continue;
            
            // 更新碰撞体并加入列表
            unit.aabbCollider.updateFromUnitArea(unit);
            _tempList.push(unit);
        }
    }

    // 单位有效性验证（独立为方法便于后续扩展验证逻辑）
    private static function _isUnitValid(
        unit:Object,
        requesterIsEnemy:Boolean,
        isEnemyRequest:Boolean
    ):Boolean {
        // 基础状态检查
        if (unit.hp <= 0) return false;
        
        // 敌我关系判断
        var unitIsEnemy:Boolean = unit.是否为敌人;
        return isEnemyRequest ? 
            (requesterIsEnemy != unitIsEnemy) : 
            (requesterIsEnemy == unitIsEnemy);
    }

    // 排序处理（独立为方法便于后续更换排序策略）
    private static function _performSorting():Void {
        InsertionSort.sort(_tempList, function(a:Object, b:Object):Number {
            return a.aabbCollider[_SORT_KEY] - b.aabbCollider[_SORT_KEY];
        });
    }

    // 重建缓存数据结构（独立为方法便于后续数据结构变更）
    private static function _rebuildCacheData(cacheEntry:Object, currentFrame:Number):Void {
        var newData:Array = [];
        var newNameIndex:Object = {};
        
        for (var i:Number = 0; i < _tempList.length; i++) {
            newData.push(_tempList[i]);
            newNameIndex[_tempList[i]._name] = i;
        }
        
        // 原子性更新缓存
        cacheEntry.data = newData;
        cacheEntry.nameIndex = newNameIndex;
        cacheEntry.lastUpdatedFrame = currentFrame;
    }
}
