// 文件路径：org/flashNight/arki/bullet/BulletComponent/Movement/Util/SearchForTargetCallbacks.as

/**
 * 目标搜索回调生成器
 * ================
 * 使用配置对象中的参数限定每帧处理的目标数量和搜索范围
 * 
 * 职责：
 *   - 按帧批量搜索目标
 *   - 处理目标优先级逻辑
 *   - 维护搜索状态缓存
 * 
 * 性能优化：
 *   - 使用分帧搜索避免单帧性能峰值
 *   - 缓存搜索结果减少重复计算
 */
class org.flashNight.arki.bullet.BulletComponent.Movement.Util.SearchForTargetCallbacks {
    /**
     * 构造目标搜索回调函数
     * @param config 导弹配置对象
     * @return Function 目标搜索回调，返回 Boolean 表示本帧是否锁定目标
     */
    public static function create(config:Object):Function {
        return function():Boolean {
            var gw:MovieClip = _root.gameworld;
            var currentShooter:MovieClip = gw[this.shooter];

            // 验证发射者状态
            if (!currentShooter || currentShooter.hp <= 0) {
                this.target = null;
                this.hasTarget = false;
                this._searchTargetCache = null;
                this._searchIndex = 0;
                this._bestTargetSoFar = null;
                this._minDistanceSoFar = Infinity;
                return false;
            }

            // 优先锁定发射者已指定的攻击目标
            var attackTargetName:String = currentShooter.攻击目标;
            var primaryTarget:MovieClip = gw[attackTargetName];
            if (attackTargetName != "无" && primaryTarget && primaryTarget.hp > 0) {
                this.target = primaryTarget;
                this.hasTarget = true;
                this._searchTargetCache = null;
                this._searchIndex = 0;
                this._bestTargetSoFar = null;
                this._minDistanceSoFar = Infinity;
                return true;
            }

            // 限帧搜索逻辑
            if (this._searchTargetCache == null) {
                // 使用配置中的搜索范围
                this._searchTargetCache = _root.帧计时器.获取敌人缓存(currentShooter, config.searchRange);
                this._searchIndex = 0;
                this._bestTargetSoFar = null;
                this._minDistanceSoFar = Infinity;
                if (this._searchTargetCache.length == 0) {
                    this.target = null;
                    this.hasTarget = false;
                    return false;
                }
            }

            // 使用配置中的批处理大小
            var endIndex:Number = Math.min(this._searchIndex + config.searchBatchSize, this._searchTargetCache.length);
            for (var i:Number = this._searchIndex; i < endIndex; i++) {
                var potentialTarget:MovieClip = this._searchTargetCache[i];
                if (potentialTarget && potentialTarget.hp > 0) {
                    var dx:Number = potentialTarget._x - this.targetObject._x;
                    var dy:Number = potentialTarget._y - this.targetObject._y;
                    var dSq:Number = dx * dx + dy * dy;
                    if (dSq < this._minDistanceSoFar) {
                        this._minDistanceSoFar = dSq;
                        this._bestTargetSoFar = potentialTarget;
                    }
                }
            }
            this._searchIndex = endIndex;

            if (this._searchIndex >= this._searchTargetCache.length) {
                this.target = this._bestTargetSoFar;
                this.hasTarget = (this.target != null);
                this._searchTargetCache = null;
                this._searchIndex = 0;
                this._bestTargetSoFar = null;
                this._minDistanceSoFar = Infinity;
                return this.hasTarget;
            } else {
                return false;
            }
        };
    }
}