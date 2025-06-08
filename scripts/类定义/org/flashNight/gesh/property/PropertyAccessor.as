import org.flashNight.gesh.property.*;

class org.flashNight.gesh.property.PropertyAccessor implements IProperty {
    // 公开的函数接口，由工厂方法动态生成
    /**
     * 获取属性值
     * @return 属性值
     */
    public function get() {
        // 占位方法，在构造函数中动态替换
        return null;
    }

    /**
     * 设置属性值
     * @param newVal 新值
     */
    public function set(newVal):Void {
        // 占位方法，在构造函数中动态替换
    }

    /**
     * 使缓存失效
     */
    public function invalidate():Void {
        // 占位方法，在构造函数中动态替换
    }
    
    // 保留必要的实例状态
    private var _obj:Object;
    private var _propName:String;

    /**
     * 构造函数
     * @param obj             目标对象
     * @param propName        属性名称
     * @param defaultValue    默认值
     * @param computeFunc     计算函数（可选，用于派生属性）
     * @param onSetCallback   设置回调（可选，用于通知依赖属性）
     * @param validationFunc  验证函数（可选，用于验证值是否合法）
     */
    public function PropertyAccessor(
        obj:Object,
        propName:String,
        defaultValue,
        computeFunc:Function,
        onSetCallback:Function,
        validationFunc:Function
    ) {
        this._obj = obj;
        this._propName = propName;
        
        // 调用工厂创建自包含且可自我优化的函数
        var funcs = this._createSelfOptimizingPropertyFunctions(
            defaultValue, computeFunc, onSetCallback, validationFunc
        );
        
        // 将生成的函数赋给实例
        this.get = funcs.get;
        this.set = funcs.set;
        this.invalidate = funcs.invalidate;
        
        // 将自包含的函数传递给addProperty，避免引用环
        obj.addProperty(propName, funcs.get, computeFunc == null ? funcs.set : null);
    }

    /**
     * 终极工厂方法: 创建一组自包含的、可自我优化的函数
     * @param defaultValue    默认值
     * @param computeFunc     计算函数
     * @param onSetCallback   设置回调函数
     * @param validationFunc  验证函数
     * @return Object {get:Function, set:Function, invalidate:Function}
     */
    private function _createSelfOptimizingPropertyFunctions(
        defaultValue,
        computeFunc:Function,
        onSetCallback:Function,
        validationFunc:Function
    ):Object {
        
        var getter:Function, setter:Function, invalidator:Function;
        
        if (computeFunc != null) {
            // --- 计算属性：带自我优化的惰性求值 ---
            var cache;
            var cacheValid:Boolean = false;
            
            // 容器间接层：用于实现动态方法替换而不产生内存泄漏
            var getterImplContainer:Array = [];
            
            // 慢版本getter：首次调用时计算并自我优化
            var lazyGetter = function() {
                if (!cacheValid) {
                    cache = computeFunc();
                    cacheValid = true;
                    // 关键：用快速版本替换容器中的实现
                    getterImplContainer[0] = function() { return cache; };
                    return cache;
                }
                // 这行代码实际不会执行到
                return cache;
            };
            
            // 将初始实现放入容器
            getterImplContainer[0] = lazyGetter;
            
            // 最终的getter：永不改变的代理，调用容器中当前的实现
            getter = function() {
                return getterImplContainer[0]();
            };
            
            // invalidator：重置缓存并恢复慢版本getter
            invalidator = function():Void {
                cacheValid = false;
                getterImplContainer[0] = lazyGetter;
            };
            
            // 计算属性是只读的
            setter = function(newVal):Void {
                // 只读属性，无操作
            };
            
        } else {
            // --- 简单属性：预编译setter优化 ---
            var value = defaultValue;
            
            // 简单的getter
            getter = function() {
                return value;
            };
            
            // 简单属性的invalidate无意义
            invalidator = function():Void {
                // 无操作
            };
            
            // 预编译setter：根据验证和回调函数的组合，生成4种最优版本
            if (validationFunc == null && onSetCallback == null) {
                // 版本1：无验证，无回调
                setter = function(newVal):Void {
                    value = newVal;
                };
            } else if (validationFunc == null && onSetCallback != null) {
                // 版本2：无验证，有回调
                setter = function(newVal):Void {
                    value = newVal;
                    onSetCallback();
                };
            } else if (validationFunc != null && onSetCallback == null) {
                // 版本3：有验证，无回调
                setter = function(newVal):Void {
                    if (validationFunc(newVal)) {
                        value = newVal;
                    }
                };
            } else {
                // 版本4：有验证，有回调
                setter = function(newVal):Void {
                    if (validationFunc(newVal)) {
                        value = newVal;
                        onSetCallback();
                    }
                };
            }
        }
        
        return {get: getter, set: setter, invalidate: invalidator};
    }

    /**
     * 获取属性名称
     * @return 属性名称
     */
    public function getPropName():String {
        return this._propName;
    }

    /**
     * 销毁方法：清理内存，解除引用
     */
    public function destroy():Void {
        if (this._obj != null && this._propName != null) {
            // 删除目标对象上的属性
            delete this._obj[this._propName];
            
            // 清理实例引用
            this._obj = null;
            this._propName = null;
            this.get = null;
            this.set = null;
            this.invalidate = null;
        }
    }
}