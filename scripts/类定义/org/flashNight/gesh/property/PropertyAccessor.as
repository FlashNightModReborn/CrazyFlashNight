import org.flashNight.gesh.property.*;

class org.flashNight.gesh.property.PropertyAccessor implements IProperty {
    private var _value; // 属性值，对于非计算属性使用
    private var _cache; // 缓存值，对于计算属性使用
    private var _cacheValid:Boolean; // 缓存是否有效
    private var _computeFunc:Function; // 计算函数（用于派生属性）
    private var _onSetCallback:Function; // 设置回调函数（当属性值改变时调用）
    private var _validationFunc:Function; // 验证函数（用于验证设置值是否合法）
    private var _propName:String; // 属性名
    private var _obj:Object; // 目标对象

    private var _originalGet:Function; // 用于在invalidate后恢复get方法
    private var _originalInvalidate:Function; // 用于不同模式下的invalidate替换

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
        this._value = defaultValue;
        this._computeFunc = computeFunc;
        this._onSetCallback = onSetCallback;
        this._validationFunc = validationFunc;

        // 根据是否为计算属性初始化缓存状态
        if (this._computeFunc != null) {
            this._cacheValid = false;
        } else {
            this._cache = this._value; 
            this._cacheValid = true;
        }

        // 根据计算函数和回调函数情况优化方法实现
        if (this._computeFunc != null) {
            // 计算属性的惰性加载逻辑
            this.get = function() {
                if (!this._cacheValid) {
                    this._cache = this._computeFunc();
                    this._cacheValid = true;
                }
                this.get = function() { return this._cache; }; // 替换为快速返回
                return this._cache;
            };

            // invalidate逻辑用于重新计算
            this.invalidate = function():Void {
                this._cacheValid = false;
                this.get = function() {
                    if (!this._cacheValid) {
                        this._cache = this._computeFunc();
                        this._cacheValid = true;
                        this.get = function() { return this._cache; }; // 替换为快速返回
                    }
                    return this._cache;
                };
            };

        } else {
            // 非计算属性直接返回值，无需缓存
            this.get = function() { return this._value; };

            // invalidate对于非计算属性无意义
            this.invalidate = function():Void {
                // 无操作
            };
        }

        // 根据验证函数和回调函数优化set逻辑
        if (this._computeFunc != null) {
            // 如果是计算属性，不允许设置值
            this.set = function(newVal):Void {
                // 只读属性，无操作
            };
        } else {
            if (this._validationFunc == null && this._onSetCallback == null) {
                // 无验证函数和回调函数
                this.set = function(newVal):Void {
                    this._value = newVal;
                    this._cacheValid = true; // 非计算属性直接赋值
                };
            } else if (this._validationFunc == null && this._onSetCallback != null) {
                // 无验证函数但有回调函数
                this.set = function(newVal):Void {
                    this._value = newVal;
                    this._cacheValid = true;
                    this._onSetCallback();
                };
            } else if (this._validationFunc != null && this._onSetCallback == null) {
                // 有验证函数但无回调函数
                this.set = function(newVal):Void {
                    if (this._validationFunc(newVal)) {
                        this._value = newVal;
                        this._cacheValid = true;
                    }
                };
            } else {
                // 有验证函数且有回调函数
                this.set = function(newVal):Void {
                    if (this._validationFunc(newVal)) {
                        this._value = newVal;
                        this._cacheValid = true;
                        this._onSetCallback();
                    }
                };
            }
        }

        // 在目标对象上添加属性访问器
        var self:PropertyAccessor = this;
        obj.addProperty(
            propName,
            function() {
                return self.get();
            },
            this._computeFunc == null ? function(newVal) {
                self.set(newVal);
            } : null
        );
    }

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

    /**
     * 获取属性名称
     * @return 属性名称
     */
    public function getPropName():String {
        return this._propName;
    }
}
