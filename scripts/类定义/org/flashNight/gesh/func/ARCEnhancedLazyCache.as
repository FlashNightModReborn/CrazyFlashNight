import org.flashNight.naki.Cache.ARCCache;

/**
 * ARCEnhancedLazyCache v2.0 — 继承自 ARCCache 的懒加载缓存
 *
 * 当 get(key) 缓存未命中时，自动调用 evaluator(key) 计算并缓存结果。
 *
 * v2.0 修复：
 * ──────────
 * [P0] CRITICAL-1 : 使用 _hitType 判断命中类型，不再依赖 cachedValue == null
 *                    （消除 null 值语义漏洞 + putNoEvict 虚调用无限递归）
 * [P0] HIGH-2     : 完全未命中走 super.put() 触发正常淘汰
 *                    幽灵命中通过 _lastNode.value 直接赋值（OPT-5，不再走 putNoEvict）
 * [P2] reset()    : clearCache 参数语义明确化（!== false 时清空）
 * [P3] 封装       : 使用基类 _clear() 代替直接访问私有字段
 * [P3] map() GC   : 文档标注闭包引用链，建议手动置 null 断链
 */
class org.flashNight.gesh.func.ARCEnhancedLazyCache extends ARCCache {
    private var evaluator:Function;

    /**
     * 构造函数
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
     *   GHOST (2/3)    → evaluator + _lastNode.value 直接赋值（OPT-5，跳过 putNoEvict）
     *
     * OPT-5：ghost hit 时 super.get() 已完成结构调整（p 自适应 + REPLACE + 移入 T2），
     *        _lastNode 持有该节点引用。直接 node.value = computed 即可，
     *        完全省去 putNoEvict 的 UID 生成 + nodeMap 查找 + 分支判断。
     *
     * 可重入安全：_lastNode 在调用 evaluator 之前存入局部变量 node，
     *            即使 evaluator 内部再次调用本缓存的 get() 覆盖 _lastNode，
     *            本次赋值仍然指向正确的节点。
     */
    public function get(key:Object):Object {
        var result:Object = super.get(key);
        var hitType:Number = this._hitType;

        // 缓存命中：直接返回（无论值是什么，包括 null/undefined）
        if (hitType == 1) {
            return result;
        }

        // 幽灵命中：先保存节点引用（必须在 evaluator 调用之前）
        var node:Object = this._lastNode;

        // 未命中或幽灵命中：调用 evaluator 计算
        var computed:Object = this.evaluator(key);

        if (hitType == 0) {
            // 完全未命中：需要正常淘汰流程（HIGH-2 fix）
            super.put(key, computed);
        } else {
            // 幽灵命中（2 或 3）：super.get() 已完成结构调整，直接赋值（OPT-5）
            node.value = computed;
        }

        return computed;
    }

    /**
     * 重置 evaluator 和/或清空缓存。
     *
     * @param newEvaluator 新的计算函数（null/undefined 则保持不变）
     * @param clearCache   是否清空缓存。
     *                     默认/undefined/true = 清空；
     *                     显式传 false = 保留现有缓存。
     */
    public function reset(newEvaluator:Function, clearCache:Boolean):Void {
        if (typeof(newEvaluator) == "function") {
            this.evaluator = newEvaluator;
        }
        if (clearCache !== false) {
            this._clear(); // P3: 使用基类方法代替直接访问私有字段
        }
    }

    /**
     * 创建转换缓存：新缓存的 evaluator 先从本缓存取值，再应用 transformer。
     *
     * 注意（P3 GC）：返回的缓存通过闭包持有对本缓存的引用。
     * 多层 map 链（a.map(f1).map(f2)...）形成引用链，所有层级都不会被 GC。
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
