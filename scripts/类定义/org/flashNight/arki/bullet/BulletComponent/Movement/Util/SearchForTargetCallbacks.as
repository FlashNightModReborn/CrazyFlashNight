// 文件路径：org/flashNight/arki/bullet/BulletComponent/Movement/Util/SearchForTargetCallbacks.as

/**
 * 目标搜索回调生成器
 * ================
 * 使用配置对象中的参数限定每帧处理的目标数量和搜索范围
 *
 * 职责：
 *   - 按帧批量搜索目标
 *   - 处理目标优先级逻辑
 *   - 维护搜索状态（仅标量，不持有数组引用）
 *
 * 性能优化：
 *   - 使用分帧搜索避免单帧性能峰值
 *   - 每帧重新获取缓存快照，版本命中时接近 O(1)
 *
 * 契约：
 *   C1: getCachedEnemy 返回的数组为缓存内部数据，调用方禁止跨帧持有引用。
 *       本回调每帧重取，仅在当前调用栈内消费。
 *   C2: 缓存刷新（长度变化）时自动重置搜索进度，保证一致性。
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
                this._searchIndex = 0;
                this._searchLen = 0;
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
                this._searchIndex = 0;
                this._searchLen = 0;
                this._bestTargetSoFar = null;
                this._minDistanceSoFar = Infinity;
                return true;
            }

            // ===== 契约化分帧搜索：每帧重取缓存，不持有数组引用 =====
            var searchCache:Array = _root.帧计时器.获取敌人缓存(currentShooter, config.searchRange);
            var len:Number = searchCache.length;

            if (len == 0) {
                this.target = null;
                this.hasTarget = false;
                this._searchIndex = 0;
                this._searchLen = 0;
                this._bestTargetSoFar = null;
                this._minDistanceSoFar = Infinity;
                return false;
            }

            // 缓存刷新检测：长度变化意味着底层数据已重建，旧进度无效
            if (this._searchLen != len) {
                this._searchIndex = 0;
                this._bestTargetSoFar = null;
                this._minDistanceSoFar = Infinity;
                this._searchLen = len;
            }

            // 批量遍历（searchCache 为局部变量，帧结束后自动释放）
            var endIndex:Number = Math.min(this._searchIndex + config.searchBatchSize, len);
            for (var i:Number = this._searchIndex; i < endIndex; i++) {
                var potentialTarget:MovieClip = searchCache[i];
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

            if (this._searchIndex >= len) {
                this.target = this._bestTargetSoFar;
                this.hasTarget = (this.target != null);
                this._searchIndex = 0;
                this._searchLen = 0;
                this._bestTargetSoFar = null;
                this._minDistanceSoFar = Infinity;
                return this.hasTarget;
            } else {
                return false;
            }
        };
    }
}