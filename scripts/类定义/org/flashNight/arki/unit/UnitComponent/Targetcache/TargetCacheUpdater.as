// 文件路径: org/flashNight/arki/unit/UnitComponent/targetcache/TargetCacheUpdater.as

import org.flashNight.naki.Sort.InsertionSort;

class org.flashNight.arki.unit.UnitComponent.Targetcache.TargetCacheUpdater {
    
    // 缓存池对象（键为缓存类型，值为缓存数据对象）
    // 用于存储不同类型的目标缓存数据
    private static var _cachePool:Object = {};
    
    // 分阵营的版本号（单位变动时分别递增）
    // 用于标识敌人和友军各自的更新版本
    private static var _enemyVersion:Number = 0;
    private static var _allyVersion:Number = 0;
    
    // 配置常量
    private static var _SORT_KEY:String = "right"; // 排序使用的关键字
    private static var _ENEMY_TYPE:String = "敌人";  // 敌人类型标识
    private static var _ALLY_TYPE:String = "友军";   // 友军类型标识
    private static var _ALL_TYPE:String = "全体";
    
    /**
     * 核心更新方法
     * 用于更新目标缓存数据，包括目标的有效性检查、排序、缓存重建等操作。
     * 此版本对版本号进行了阵营细化，并采用内联展开的插入排序，避免匿名函数带来的性能损耗。
     * 
     * @param {Object} gameWorld - 当前游戏世界对象，包含所有单位信息
     * @param {Number} currentFrame - 当前帧数，用于判断缓存是否过时
     * @param {String} requestType - 请求类型（如“敌人”或“友军”）
     * @param {Boolean} targetIsEnemy - 目标是否为敌人
     * @param {Object} cacheEntry - 目标缓存项
     */
    public static function updateCache(
        gameWorld:Object,
        currentFrame:Number,
        requestType:String,
        targetIsEnemy:Boolean,
        cacheEntry:Object
    ):Void {
        var isAllRequest:Boolean = (requestType == _ALL_TYPE);
        // 生成复合缓存键（由请求类型和目标状态组成）
        var cacheKey:String = isAllRequest ? _ALL_TYPE : requestType + "_" + targetIsEnemy.toString();
        
        // 获取或创建缓存类型数据
        var cacheTypeData:Object = _getCacheTypeData(cacheKey);
        
        // 根据阵营细化的版本号，判断是否需要更新缓存
        var currentVersion:Number;
        if (isAllRequest) {
            // “全体”请求以敌人和友军中较高的版本号为准
            currentVersion = (_enemyVersion > _allyVersion) ? _enemyVersion : _allyVersion;
        } else {
            currentVersion = targetIsEnemy ? _enemyVersion : _allyVersion;
        }
        
        // 版本检查：如果缓存数据的版本小于当前版本，则需要重新收集有效单位
        if(cacheTypeData.tempVersion < currentVersion) {
            // 通知重建索引（消息可能触发其它逻辑，需注意是否引入额外开销）
            _root.发布消息("重建索引 " + _root.帧计时器.当前帧数);
            // 清空临时列表并重新收集有效单位
            cacheTypeData.tempList.length = 0;
            if(isAllRequest) {
                _collectAllValidUnits(gameWorld, cacheTypeData.tempList);
            } else {
                _collectValidUnits(
                    gameWorld,
                    targetIsEnemy,
                    requestType == _ENEMY_TYPE,  // 判断是否为敌人请求
                    cacheTypeData.tempList
                );
            }
            // 更新临时缓存版本号
            cacheTypeData.tempVersion = currentVersion;
        }
        
        // 获取缓存类型的临时列表
        var list:Array = cacheTypeData.tempList;
        
        // 内联展开排序处理，按指定的排序关键字进行排序
        var len:Number = list.length;
        if(len > 1) {
            for (var i:Number = 1; i < len; i++) {
                var key:Object = list[i];
                var keyVal:Number = key.aabbCollider[_SORT_KEY];
                var j:Number = i - 1;
                while(j >= 0 && list[j].aabbCollider[_SORT_KEY] > keyVal) {
                    list[j + 1] = list[j];
                    j--;
                }
                list[j + 1] = key;
            }
        }
        
        // 构建并更新缓存数据结构
        _rebuildCacheData(list, cacheEntry, currentFrame);
    }
    
    /**
     * 缓存类型数据工厂
     * 用于获取缓存类型的临时数据，若缓存类型数据不存在则创建。
     * 
     * @param {String} key - 缓存的复合键
     * @return {Object} 返回缓存类型的数据对象
     */
    private static function _getCacheTypeData(key:String):Object {
        if(!_cachePool[key]) {
            _cachePool[key] = {
                tempList: [],    // 该缓存类型的临时目标列表
                tempVersion: 0   // 该缓存类型的临时版本号
            };
        }
        return _cachePool[key];
    }
    
    /**
     * 全局版本控制方法 - 单位添加时更新对应阵营的版本号
     * 
     * @param {MovieClip} target - 新增的单位
     */
    public static function addUnit(target:MovieClip):Void {
        if(target.是否为敌人) {
            _enemyVersion++;
        } else {
            _allyVersion++;
        }
    }
    
    /**
     * 全局版本控制方法 - 单位移除时更新对应阵营的版本号
     * 
     * @param {MovieClip} target - 移除的单位
     */
    public static function removeUnit(target:MovieClip):Void {
        if(target.是否为敌人) {
            _enemyVersion++;
        } else {
            _allyVersion++;
        }
    }
    
    /**
     * 收集有效单位（性能优化版）
     * 遍历游戏世界中的所有单位，筛选符合条件的单位并加入目标列表。
     * 
     * @param {Object} gameWorld - 当前游戏世界对象，包含所有单位信息
     * @param {Boolean} requesterIsEnemy - 请求者是否为敌人
     * @param {Boolean} isEnemyRequest - 是否请求敌人数据
     * @param {Array} targetList - 存储有效单位的目标列表
     */
    private static function _collectValidUnits(
        gameWorld:Object,
        requesterIsEnemy:Boolean,
        isEnemyRequest:Boolean,
        targetList:Array
    ):Void {
        var shouldCheckOpposite:Boolean = isEnemyRequest;
        var unitKey:String;
        var unit:Object;
        var unitIsEnemy:Boolean;
    
        for(unitKey in gameWorld) {
            unit = gameWorld[unitKey];
            // 内联有效性检查，跳过血量小于等于0的死亡单位
            if(unit.hp <= 0) continue;
            unitIsEnemy = unit.是否为敌人;
            // 根据请求条件判断单位是否有效
            if(!(shouldCheckOpposite ? 
                (requesterIsEnemy != unitIsEnemy) :  // 判断对立关系（敌人请求）
                (requesterIsEnemy == unitIsEnemy)))   // 判断相同关系（友军请求）
                continue;
            // 更新碰撞体信息并加入目标列表
            unit.aabbCollider.updateFromUnitArea(targetList[targetList.length] = unit);
        }
    }
    
    /**
     * 收集有效单位（性能优化版） - 全体单位收集
     * 遍历游戏世界中的所有单位，筛选符合条件的单位并加入目标列表。
     * 
     * @param {Object} gameWorld - 当前游戏世界对象，包含所有单位信息
     * @param {Array} targetList - 存储有效单位的目标列表
     */
    private static function _collectAllValidUnits(
        gameWorld:Object,
        targetList:Array
    ):Void {
        var unitKey:String;
        var unit:Object;
        for(unitKey in gameWorld) {
            unit = gameWorld[unitKey];
            if(unit.hp <= 0) continue;
            unit.aabbCollider.updateFromUnitArea(targetList[targetList.length] = unit);
        }
    }
    
    /**
     * 构建缓存数据结构（优化版）
     * 根据排序后的单位列表重建缓存数据，并更新缓存项信息。
     * 
     * @param {Array} sourceList - 已排序的源单位列表
     * @param {Object} cacheEntry - 目标缓存项
     * @param {Number} currentFrame - 当前帧数，用于更新缓存的时间戳
     */
    private static function _rebuildCacheData(sourceList:Array, cacheEntry:Object, currentFrame:Number):Void {
        var newNameIndex:Object = {};
        var len:Number = sourceList.length;
        var unit:Object;
        for (var i:Number = 0; i < len; i++) {
            unit = sourceList[i];
            newNameIndex[unit._name] = i;
        }
        cacheEntry.data = sourceList;
        cacheEntry.nameIndex = newNameIndex;
        cacheEntry.lastUpdatedFrame = currentFrame;
    }
}
