// 文件路径: org/flashNight/arki/unit/UnitComponent/targetcache/TargetCacheUpdater.as
import org.flashNight.naki.Sort.InsertionSort;

class org.flashNight.arki.unit.UnitComponent.Targetcache.TargetCacheUpdater {
    // 缓存池对象（键为缓存类型，值为缓存数据对象）
    private static var _cachePool:Object = {};
    
    // 全局版本号（任何单位变动时递增）
    private static var _globalVersion:Number = 0;
    
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
        // 生成复合缓存键
        var cacheKey:String = requestType + "_" + targetIsEnemy.toString();
        
        // 获取或创建缓存类型数据
        var cacheTypeData:Object = _getCacheTypeData(cacheKey);
        
        // 版本检查
        if(cacheTypeData.tempVersion < _globalVersion) {
            cacheTypeData.tempList.length = 0;
            _collectValidUnits(
                gameWorld,
                targetIsEnemy,
                requestType == _ENEMY_TYPE,
                cacheTypeData.tempList
            );
            cacheTypeData.tempVersion = _globalVersion;
        }

        var list:Array = cacheTypeData.tempList;
        
        // 排序处理
        InsertionSort.sort(list, function(a:Object, b:Object):Number {
            return a.aabbCollider[_SORT_KEY] - b.aabbCollider[_SORT_KEY];
        });
        
        // 构建缓存结构
        _rebuildCacheData(list, cacheEntry, currentFrame);
    }

    // 缓存类型数据工厂
    private static function _getCacheTypeData(key:String):Object {
        if(!_cachePool[key]) {
            _cachePool[key] = {
                tempList: [],    // 该缓存类型的临时列表
                tempVersion: 0   // 该缓存类型的临时版本
            };
        }
        return _cachePool[key];
    }

    // 全局版本控制
    public static function addUnit(target:MovieClip):Void {
        _globalVersion++;
    }

    public static function removeUnit(target:MovieClip):Void {
        _globalVersion++;
    }

    // 收集有效单位（性能优化版）
    private static function _collectValidUnits(
        gameWorld:Object,
        requesterIsEnemy:Boolean,
        isEnemyRequest:Boolean,
        targetList:Array
    ):Void {
        // 提前确定敌我关系判断方式
        var shouldCheckOpposite:Boolean = isEnemyRequest;
        
        for(var unitKey:String in gameWorld) {
            var unit:Object = gameWorld[unitKey];
            
            // 内联有效性检查（消除函数调用）
            if(unit.hp <= 0) continue; // 死亡单位跳过
            
            var unitIsEnemy:Boolean = unit.是否为敌人;
            var isValidRelation:Boolean = shouldCheckOpposite ? 
                (requesterIsEnemy != unitIsEnemy) : 
                (requesterIsEnemy == unitIsEnemy);
            
            if(!isValidRelation) continue;
            
            // 更新碰撞体并加入列表
            unit.aabbCollider.updateFromUnitArea(unit);
            targetList.push(unit);
        }
    }


    // 构建缓存数据结构（更新后版本）
    private static function _rebuildCacheData(sourceList:Array, cacheEntry:Object, currentFrame:Number):Void {
        var newData:Array = [];
        var newNameIndex:Object = {};
        
        for(var i:Number = 0; i < sourceList.length; i++) {
            newData.push(sourceList[i]);
            newNameIndex[sourceList[i]._name] = i;
        }
        
        // 原子更新
        cacheEntry.data = newData;
        cacheEntry.nameIndex = newNameIndex;
        cacheEntry.lastUpdatedFrame = currentFrame;
    }
}
