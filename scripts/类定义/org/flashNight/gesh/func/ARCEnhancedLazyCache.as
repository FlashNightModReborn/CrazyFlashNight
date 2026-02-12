import org.flashNight.naki.Cache.ARCCache;

/**
 * ARCEnhancedLazyCache v3.0 — 继承自 ARCCache 的懒加载缓存
 *
 * 当 get(key) 缓存未命中时，自动调用 evaluator(key) 计算并缓存结果。
 *
 * v3.0 变更：
 * ──────────
 * [P0] ARCH-1     : 继承 ARCCache v3.0 原始键语义，无内部 UID 转换。
 * [P1] OPT-7      : === 严格比较替代 ==。
 * [P3] SAFE-1     : ghost hit 路径增加 try/catch —— evaluator 异常时
 *                    调用 super.remove(key) 清除 T2 中的空值僵尸节点后重抛。
 *                    MISS 路径无需 catch（super.put 尚未执行，无副作用）。
 *
 * 保留自 v2.0 的修复：
 *   CRITICAL-1 : _hitType 判断命中类型（消除 null 值语义漏洞）
 *   HIGH-2     : MISS 走 super.put() 触发正常淘汰
 *   OPT-5      : ghost hit 通过 _lastNode.value 直赋
 */
class org.flashNight.gesh.func.ARCEnhancedLazyCache extends ARCCache {
    private var evaluator:Function;

    /**
     * @param evaluator 计算函数 (key => value)
     * @param capacity  ARC 缓存容量
     */
    public function ARCEnhancedLazyCache(evaluator:Function, capacity:Number) {
        super(capacity);
        if (typeof(evaluator) != "function") {
            throw new Error("ARCEnhancedLazyCache requires a function as an evaluator.");
        }
        this.evaluator = evaluator;
    }

    /**
     * 重写 get：缓存命中直接返回，未命中则调用 evaluator 计算后缓存。
     *
     * 通过 _hitType 区分三种情况：
     *   HIT (1)        → 直接返回缓存值
     *   MISS (0)       → evaluator + super.put()（触发淘汰）
     *   GHOST (2/3)    → evaluator + _lastNode.value 直赋（OPT-5）
     *
     * SAFE-1：ghost hit 时 super.get() 已将节点移入 T2（value = undefined）。
     *   若 evaluator 抛异常，该节点成为 T2 中的僵尸（HIT 返回 undefined）。
     *   catch 中调用 super.remove(key) 清除后重抛，确保缓存一致性。
     *   MISS 路径无此风险：异常时 super.put() 未执行，cache 状态不变。
     *
     * 可重入安全：_lastNode 在调用 evaluator 之前存入局部变量 node。
     */
    public function get(key:Object):Object {
        var result:Object = super.get(key);
        var hitType:Number = this._hitType;

        // 缓存命中：直接返回（无论值是什么，包括 null/undefined）
        if (hitType === 1) {
            return result;
        }

        var node:Object = this._lastNode;
        var computed:Object;

        if (hitType === 0) {
            // MISS：evaluator 失败无副作用（put 未调用）
            computed = this.evaluator(key);
            super.put(key, computed);
        } else {
            // GHOST (2/3)：节点已在 T2，evaluator 失败需清除僵尸
            try {
                computed = this.evaluator(key);
            } catch (e) {
                super.remove(key);
                throw e;
            }
            node.value = computed;
        }

        return computed;
    }

    /**
     * 重置 evaluator 和/或清空缓存。
     *
     * @param newEvaluator 新的计算函数（null/undefined 则保持不变）
     * @param clearCache   是否清空缓存（默认/undefined/true = 清空；显式 false = 保留）
     */
    public function reset(newEvaluator:Function, clearCache:Boolean):Void {
        if (typeof(newEvaluator) == "function") {
            this.evaluator = newEvaluator;
        }
        if (clearCache !== false) {
            this._clear();
        }
    }

    /**
     * 创建转换缓存：新缓存的 evaluator 先从本缓存取值，再应用 transformer。
     *
     * 注意（GC）：返回的缓存通过闭包持有对本缓存的引用。
     * 多层 map 链形成引用链，所有层级都不会被 GC。
     * 如需释放，应手动将不再使用的中间缓存引用置为 null。
     *
     * @param transformer 转换函数 (baseValue => newValue)
     * @param capacity    新缓存容量（默认继承本缓存容量）
     * @return 新的 ARCEnhancedLazyCache 实例
     */
    public function map(transformer:Function, capacity:Number):ARCEnhancedLazyCache {
        var self:ARCEnhancedLazyCache = this;
        var newCap:Number = (capacity != undefined && capacity != null)
                            ? capacity : this.getCapacity();

        var newEvaluator:Function = function(k:Object):Object {
            var baseValue:Object = self.get(k);
            return transformer(baseValue);
        };
        return new ARCEnhancedLazyCache(newEvaluator, newCap);
    }
}
