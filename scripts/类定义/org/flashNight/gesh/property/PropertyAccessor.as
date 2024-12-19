import org.flashNight.gesh.property.*;

class org.flashNight.gesh.property.PropertyAccessor implements IProperty {
    private var _value:Number;
    private var _cache:Number;
    private var _cacheValid:Boolean;
    private var _computeFunc:Function;
    private var _onSetCallback:Function;
    private var _validationFunc:Function; // 验证函数
    private var _propName:String;
    private var _obj:Object;

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
        defaultValue:Number,
        computeFunc:Function,
        onSetCallback:Function,
        validationFunc:Function
    ) {
        this._value = defaultValue;
        this._computeFunc = computeFunc;
        this._onSetCallback = onSetCallback;
        this._validationFunc = validationFunc; // 初始化验证函数
        this._propName = propName;
        this._obj = obj;

        if (this._computeFunc != null) {
            this._cacheValid = false;
        } else {
            this._cache = this._value;
            this._cacheValid = true;
        }

        var self:PropertyAccessor = this;

        // 添加属性访问器
        obj.addProperty(
            propName,
            function() {
                return self.get();
            },
            this._computeFunc == null ? function(newVal:Number) {
                self.set(newVal);
            } : null
        );
    }

    /**
     * 获取属性值（惰性优化）
     * @return 属性值
     */
    public function get():Number {
        if (!this._cacheValid) {
            this.get = this._computeFunc != null ? function():Number {
                this._cache = this._computeFunc();
                this._cacheValid = true;
                return this._cache;
            } : function():Number {
                return this._value;
            };
            return this.get();
        }
        return this._cache;
    }

    /**
     * 设置属性值（惰性优化）
     * @param newVal 新值
     */
    public function set(newVal:Number):Void {
        if (this._computeFunc != null) {
            this.set = function(newVal:Number):Void {
                // 只读属性，无操作
            };
            return;
        }

        if (this._validationFunc == null || this._validationFunc(newVal)) {
            this._value = newVal;
            this._cacheValid = false;
            if (this._onSetCallback != null) {
                this._onSetCallback();
            }
        } else {
            trace("Invalid value: " + newVal + " for property '" + this._propName + "'.");
        }
    }

    /**
     * 使缓存失效
     */
    public function invalidate():Void {
        this._cacheValid = false;
        this.get = this._computeFunc != null ? function():Number {
            this._cache = this._computeFunc();
            this._cacheValid = true;
            return this._cache;
        } : function():Number {
            return this._value;
        };
    }

    /**
     * 获取属性名称
     * @return 属性名称
     */
    public function getPropName():String {
        return this._propName;
    }
}
