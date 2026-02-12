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
 * [—]  SAFE-1     : (v3.1 移除) 不再使用 try/catch，改为契约优先。
 *                    evaluator MUST NOT throw（C8）/ MUST NOT 对同一实例递归调用（C9）。
 *                    与项目全局规范（避免异常影响性能）对齐。
 * [P0] OPT-9      : MISS 路径使用 super._putNew() 替代 super.put()，
 *                    省一次 nodeMap 存在性检查（hash 查找）。
 *
 * 保留自 v2.0 的修复：
 *   CRITICAL-1 : _hitType 判断命中类型（消除 null 值语义漏洞）
 *   HIGH-2     : MISS 走 super._putNew() 触发正常淘汰（v3.1 升级为 OPT-9）
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
     *   MISS (0)       → evaluator + super._putNew()（OPT-9 省一次 hash 查找）
     *   GHOST (2/3)    → evaluator + _lastNode.value 直赋（OPT-5）
     *
     * 契约 C8（evaluator 安全）：
     *   evaluator MUST NOT 抛出异常。违反时 GHOST 路径将产生 T2 僵尸节点
     *   （value=undefined 的 HIT），直到该节点被淘汰或手动 remove(key)。
     *   MISS 路径天然安全（super._putNew 未调用，cache 状态不变）。
     *
     * 契约 C9（可重入禁止）：
     *   evaluator MUST NOT 对同一缓存实例调用 get()/put()/remove()。
     *   违反将导致 _lastNode 被覆盖、静默数据损坏（use-after-pool）。
     *   通过 map() 链访问父缓存是安全的（不同实例，_lastNode 独立）。
     */
    public function get(key:Object):Object {
        var result:Object = super.get(key);
        var hitType:Number = this._hitType;

        // 缓存命中：直接返回（无论值是什么，包括 null/undefined）
        if (hitType === 1) {
            return result;
        }

        var node:Object = this._lastNode;
        var computed:Object = this.evaluator(key);

        if (hitType === 0) {
            // MISS：OPT-9 _putNew 跳过存在性检查
            super._putNew(key, computed);
        } else {
            // GHOST (2/3)：OPT-5 直赋（evaluator MUST NOT throw — C8）
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
