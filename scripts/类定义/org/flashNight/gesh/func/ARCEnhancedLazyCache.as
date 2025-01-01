import org.flashNight.naki.Cache.ARCCache;

/**
 * 继承自 ARCCache 的增强版懒加载缓存：
 * 当 get(key) 缓存未命中(或命中幽灵队列)时，自动调用 evaluator(key) 进行计算并缓存。
 * 修复点：若父类已经在 "get" 中做过淘汰，则用 putNoEvict，避免二次淘汰。
 */
class org.flashNight.gesh.func.ARCEnhancedLazyCache extends ARCCache {
    private var evaluator:Function; // 计算逻辑，用于当缓存未命中时产生值

    /**
     * 构造函数
     * @param evaluator  计算函数(key => value)
     * @param capacity   ARCCache 容量
     */
    public function ARCEnhancedLazyCache(evaluator:Function, capacity:Number) {
        super(capacity);
        if (typeof(evaluator) != "function") {
            throw new Error("ARCEnhancedLazyCache requires a function as an evaluator.");
        }
        this.evaluator = evaluator;
    }

    /**
     * 重写父类的 get 方法：
     * 1. 调用父类 get，如果返回 null，说明未命中或命中B1/B2（幽灵队列）导致单次淘汰已进行
     * 2. 此时我们只需 putNoEvict(key,value)，避免再次淘汰
     */
    public function get(key:Object):Object {
        var cachedValue:Object = super.get(key);
        if (cachedValue == null) {
            // 父类 get => 已进行一次淘汰 (若命中B1/B2) 或啥都没做 (真正的未命中)
            var result:Object = evaluator(key);
            // 用 putNoEvict 避免重复淘汰
            super.putNoEvict(key, result);
            return result;
        } else {
            return cachedValue;
        }
    }

    /**
     * 重写 reset
     */
    public function reset(newEvaluator:Function, clearCache:Boolean):Void {
        if (typeof(newEvaluator) == "function") {
            this.evaluator = newEvaluator;
        }
        if (clearCache == undefined || clearCache == true) {
            this.initCacheData();
        }
    }

    /**
     * map 功能：新 evaluator = 先从当前 get(key) 拿值，再 transformer
     */
    public function map(transformer:Function, capacity:Number):ARCEnhancedLazyCache {
        var self:ARCEnhancedLazyCache = this;
        var newCap:Number = (capacity != null) ? capacity : this.maxCapacity;

        var newEvaluator:Function = function(k:Object):Object {
            var baseValue:Object = self.get(k);
            return transformer(baseValue);
        };
        return new ARCEnhancedLazyCache(newEvaluator, newCap);
    }

    /**
     * 清空父类队列和映射
     */
    private function initCacheData():Void {
        this.p = 0;
        this.T1 = { head: null, tail: null, size: 0 };
        this.T2 = { head: null, tail: null, size: 0 };
        this.B1 = { head: null, tail: null, size: 0 };
        this.B2 = { head: null, tail: null, size: 0 };
        this.cacheStore = {};
        this.nodeMap = {};
    }
}
