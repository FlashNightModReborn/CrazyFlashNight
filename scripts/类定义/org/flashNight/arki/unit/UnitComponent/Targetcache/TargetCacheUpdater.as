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
    // private static var _SORT_KEY:String = "left"; // 排序使用的关键字
    private static var _ENEMY_TYPE:String = "敌人";  // 敌人类型标识
    private static var _ALLY_TYPE:String = "友军";   // 友军类型标识
    private static var _ALL_TYPE:String = "全体";


    // 脏标记用于强制刷新
    // public static var dirtyMark:Boolean = true;
    
    /**
     * 核心更新方法（方案1重写版）
     * 用于更新目标缓存数据，包括有效性检查、排序、缓存重建等操作。
     * 根据请求类型和请求者阵营，确定实际要收集的单位阵营，并使用对应版本号判断是否需要更新缓存。
     *
     * @param {Object} gameWorld - 当前游戏世界对象，包含所有单位信息
     * @param {Number} currentFrame - 当前帧数，用于更新缓存的时间戳
     * @param {String} requestType - 请求类型（如“敌人”、“友军”或“全体”）
     * @param {Boolean} targetIsEnemy - 发起请求的单位是否为敌人（true表示敌人，false表示友军）
     * @param {Object} cacheEntry - 目标缓存项
     */
    public static function updateCache(
        gameWorld:Object,
        currentFrame:Number,
        requestType:String,
        targetIsEnemy:Boolean,
        cacheEntry:Object
    ):Void {
        // 判断是否为全体请求
        var isAllRequest:Boolean = (requestType == _ALL_TYPE);
        // 判断请求类型是否为“敌人”
        var isEnemyRequest:Boolean = (requestType == _ENEMY_TYPE);

        // _root.发布消息("frame: " + _root.帧计时器.当前帧数);
        
        // 根据请求类型确定实际要收集的阵营：
        // - 如果是“全体”，则不分阵营
        // - 如果是“敌人”，则要收集与请求者相反的单位（即：effectiveFaction = !targetIsEnemy）
        // - 如果是“友军”，则收集与请求者相同的单位（effectiveFaction = targetIsEnemy）
        var effectiveFaction:Boolean;
        if (isAllRequest) {
            // 此时不需要区分敌友，effectiveFaction无效
        } else {
            effectiveFaction = isEnemyRequest ? !targetIsEnemy : targetIsEnemy;
        }
        
        // 生成复合缓存键
        var cacheKey:String = isAllRequest ? _ALL_TYPE : requestType + "_" + effectiveFaction.toString();
        
        // 获取或创建缓存类型数据
        // 内联展开 _getCacheTypeData 的核心逻辑 (性能关键优化点)
        var cacheTypeData:Object; // 原函数返回值
        if(!_cachePool[cacheKey]) { // 原函数条件判断
            // 原函数创建逻辑
            _cachePool[cacheKey] = { 
                tempList: [], 
                tempVersion: 0 
            };
        }
        cacheTypeData = _cachePool[cacheKey]; // 原函数返回语句
        
        // 根据实际要收集的阵营选择对应的版本号：
        // - 对于全体请求，采用 ( _enemyVersion + _allyVersion )
        // - 否则：如果 effectiveFaction 为 true，则代表敌人（使用 _enemyVersion），否则使用 _allyVersion
        var currentVersion:Number;
        if (isAllRequest) {
            currentVersion = _enemyVersion + _allyVersion;
        } else {
            currentVersion = effectiveFaction ? _enemyVersion : _allyVersion;
        }
        
        // 如果缓存中记录的版本低于当前版本，或者全局脏标记 dirtyMark 为 true，则需要重新收集有效单位
        // if (cacheTypeData.tempVersion < currentVersion || dirtyMark) {
        if (cacheTypeData.tempVersion < currentVersion) {
            // 清空临时列表
            cacheTypeData.tempList.length = 0;
            if (isAllRequest) {
                _collectAllValidUnits(gameWorld, cacheTypeData.tempList);
            } else {
                // 注意：_collectValidUnits 参数中的 isEnemyRequest 表示是否收集敌方单位，
                // 此处如果请求类型为“敌人”，则收集与请求者相反的一边
                _collectValidUnits(
                    gameWorld,
                    targetIsEnemy,         // 请求者的阵营
                    isEnemyRequest,        // 收集敌人（true）或友军（false）
                    cacheTypeData.tempList
                );
            }
            // 更新缓存的临时版本号为当前版本
            cacheTypeData.tempVersion = currentVersion;
        }
        
        // 获取缓存类型的临时列表
        var list:Array = cacheTypeData.tempList;
        
        // 内联展开插入排序（直接点索引属性进行排序）
        var len:Number = list.length;
        if (len > 1) {
            var i:Number = 1;
            do {
                var key:Object = list[i];
                var keyVal:Number = key.aabbCollider.left;
                var j:Number = i - 1;
                do {
                    // 若 j 有效且前一个元素的 left 大于当前 key 的 left，则后移
                    if (j >= 0 && list[j].aabbCollider.left > keyVal) {
                        list[j + 1] = list[j--];
                    } else {
                        break;
                    }
                } while (j >= 0);
                list[j + 1] = key;
            } while (++i < len);
        }
        
        // 根据排序后的列表构建并更新缓存数据结构
        //_rebuildCacheData(list, cacheEntry, currentFrame);
        cacheEntry.data = list;
        cacheEntry.lastUpdatedFrame = currentFrame;
        
        // 重置全局脏标记（标记已被刷新）
        // dirtyMark = false;
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
     * @param {Object} target - 新增的单位
     */
    public static function addUnit(target:Object):Void {
        if(target.是否为敌人) {
            _enemyVersion++;
        } else {
            _allyVersion++;
        }

        // dirtyMark = true;
    }
    
    /**
     * 全局版本控制方法 - 单位移除时更新对应阵营的版本号
     * 
     * @param {Object} target - 移除的单位
     */
    public static function removeUnit(target:Object):Void {
        if(target.是否为敌人) {
            _enemyVersion++;
        } else {
            _allyVersion++;
        }

        // dirtyMark = true;
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
        var unitKey:String;
        var unit:Object;
        var unitIsEnemy:Boolean;
        
        // 将核心判断逻辑提升到循环外
        if (isEnemyRequest) {
            // 敌人请求分支：收集与请求者阵营不同的单位
            for (unitKey in gameWorld) {
                unit = gameWorld[unitKey];
                if (unit.hp <= 0) continue;
                unitIsEnemy = unit.是否为敌人;
                if (requesterIsEnemy != unitIsEnemy) {
                    unit.aabbCollider.updateFromUnitArea(targetList[targetList.length] = unit);
                }
            }
        } else {
            // 友军请求分支：收集与请求者阵营相同的单位
            for (unitKey in gameWorld) {
                unit = gameWorld[unitKey];
                if (unit.hp <= 0) continue;
                unitIsEnemy = unit.是否为敌人;
                if (requesterIsEnemy == unitIsEnemy) {
                    unit.aabbCollider.updateFromUnitArea(targetList[targetList.length] = unit);
                }
            }
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
        cacheEntry.nameIndex = newNameIndex;

        cacheEntry.data = sourceList;
        cacheEntry.lastUpdatedFrame = currentFrame;
    }
}
