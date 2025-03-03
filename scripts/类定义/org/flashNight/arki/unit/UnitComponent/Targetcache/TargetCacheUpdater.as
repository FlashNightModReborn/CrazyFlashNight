// 文件路径: org/flashNight/arki/unit/UnitComponent/targetcache/TargetCacheUpdater.as

import org.flashNight.naki.Sort.InsertionSort;

class org.flashNight.arki.unit.UnitComponent.Targetcache.TargetCacheUpdater {
    
    // 缓存池对象（键为缓存类型，值为缓存数据对象）
    // 用于存储不同类型的目标缓存数据
    private static var _cachePool:Object = {};
    
    // 全局版本号（任何单位变动时递增）
    // 用于标识全局更新版本，每当单位变化时，版本号递增
    private static var _globalVersion:Number = 0;
    
    // 配置常量
    private static var _SORT_KEY:String = "right"; // 排序使用的关键字
    private static var _ENEMY_TYPE:String = "敌人"; // 敌人类型标识
    private static var _ALLY_TYPE:String = "友军"; // 友军类型标识
    
    /**
     * 核心更新方法
     * 用于更新目标缓存数据，包括目标的有效性检查、排序、缓存重建等操作
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
        // 生成复合缓存键（由请求类型和目标状态组成）
        var cacheKey:String = requestType + "_" + targetIsEnemy.toString();
        
        // 获取或创建缓存类型数据
        var cacheTypeData:Object = _getCacheTypeData(cacheKey);
        
        // 版本检查，如果缓存数据的版本小于全局版本，则需要重新收集有效单位
        if(cacheTypeData.tempVersion < _globalVersion) {
            // 清空临时列表并重新收集有效单位
            cacheTypeData.tempList.length = 0;
            _collectValidUnits(
                gameWorld,
                targetIsEnemy,
                requestType == _ENEMY_TYPE,  // 判断是否为敌人请求
                cacheTypeData.tempList
            );
            // 更新临时缓存版本号
            cacheTypeData.tempVersion = _globalVersion;
        }

        // 获取缓存类型的临时列表
        var list:Array = cacheTypeData.tempList;
        
        // 排序处理，按指定的排序关键字进行排序
        InsertionSort.sort(list, function(a:Object, b:Object):Number {
            return a.aabbCollider[_SORT_KEY] - b.aabbCollider[_SORT_KEY];
        });
        
        // 构建并更新缓存数据结构
        _rebuildCacheData(list, cacheEntry, currentFrame);
    }

    /**
     * 缓存类型数据工厂
     * 用于获取缓存类型的临时数据，若缓存类型数据不存在则创建
     * @param {String} key - 缓存的复合键
     * @return {Object} 返回缓存类型的数据对象
     */
    private static function _getCacheTypeData(key:String):Object {
        // 如果缓存池中没有该类型的缓存数据，则创建并存入缓存池
        if(!_cachePool[key]) {
            _cachePool[key] = {
                tempList: [],    // 该缓存类型的临时目标列表
                tempVersion: 0   // 该缓存类型的临时版本
            };
        }
        return _cachePool[key];
    }

    /**
     * 全局版本控制方法
     * 用于增加全局版本号，通常在单位发生变化时调用
     * @param {MovieClip} target - 变动的单位
     */
    public static function addUnit(target:MovieClip):Void {
        _globalVersion++;  // 增加全局版本号
    }

    /**
     * 全局版本控制方法
     * 用于减少全局版本号，通常在单位移除时调用
     * @param {MovieClip} target - 移除的单位
     */
    public static function removeUnit(target:MovieClip):Void {
        _globalVersion++;  // 增加全局版本号
    }

    /**
     * 收集有效单位（性能优化版）
     * 遍历游戏世界中的所有单位，筛选符合条件的单位并加入目标列表
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
        // 提前确定敌我关系判断方式
        var shouldCheckOpposite:Boolean = isEnemyRequest;
        var unitKey:String;
        var unit:Object;
        var unitIsEnemy:Boolean;

        // 遍历游戏世界中的所有单位
        for(unitKey in gameWorld) {
            unit = gameWorld[unitKey];
            
            // 内联有效性检查，死亡单位跳过
            if(unit.hp <= 0) continue;  // 死亡单位不参与缓存
            
            unitIsEnemy = unit.是否为敌人;  // 获取单位是否为敌人
            
            // 根据请求条件判断该单位是否有效
            if(!(shouldCheckOpposite ? 
                (requesterIsEnemy != unitIsEnemy) :  // 请求的敌人或友军，判断对立关系
                (requesterIsEnemy == unitIsEnemy)))   // 判断相同关系（敌人或友军）
                continue;
            
            // 更新碰撞体信息并加入目标列表
            unit.aabbCollider.updateFromUnitArea(targetList[targetList.length] = unit);
        }
    }

    /**
     * 构建缓存数据结构（优化版）
     * 根据排序后的单位列表重建缓存数据，并更新缓存项
     * @param {Array} sourceList - 源单位列表（已排序）
     * @param {Object} cacheEntry - 目标缓存项
     * @param {Number} currentFrame - 当前帧数，用于更新缓存的时间戳
     */
    private static function _rebuildCacheData(sourceList:Array, cacheEntry:Object, currentFrame:Number):Void {
        var newNameIndex:Object = {};  // 用于存储单位名称的索引
        var len:Number = sourceList.length;  // 获取源列表长度
        var unit:Object;

        // 直接复用已排序的源数组，避免不必要的数组复制
        for (var i:Number = 0; i < len; i++) {
            unit = sourceList[i];
            newNameIndex[unit._name] = i;  // 通过单位名称建立索引
        }
        
        // 原子更新（直接引用已排序数组），避免多次操作
        cacheEntry.data = sourceList;       // 直接引用源数组
        cacheEntry.nameIndex = newNameIndex;  // 更新名称索引
        cacheEntry.lastUpdatedFrame = currentFrame;  // 更新缓存的最后更新时间
    }
}
