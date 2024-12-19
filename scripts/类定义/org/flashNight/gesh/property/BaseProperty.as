// File: org/flashNight/gesh/property/BaseProperty.as
class org.flashNight.gesh.property.BaseProperty {
    private var _value:Number;
    private var _cache:Number;
    private var _cacheValid:Boolean;
    private var _computeFunc:Function;
    private var _onSetCallback:Function;
    private var _propName:String;

    /**
     * 构造函数
     * @param obj           目标对象
     * @param propName      属性名称
     * @param defaultValue  默认值
     * @param computeFunc   计算函数（可选，用于派生属性）
     * @param onSetCallback 设置回调函数（可选，用于通知依赖属性）
     */
    public function BaseProperty(obj:Object, propName:String, defaultValue:Number, computeFunc:Function, onSetCallback:Function) {
        this._propName = propName;
        this._value = defaultValue;
        this._cache = defaultValue;
        this._cacheValid = true;
        this._computeFunc = computeFunc;
        this._onSetCallback = onSetCallback;

        var self:BaseProperty = this;

        // 定义属性访问器
        obj.addProperty(
            propName,
            function():Number {
                return self.getValue();
            },
            (computeFunc == null) ? function(newVal:Number):Void {
                self.setValue(newVal);
            } : null
        );
    }

    /**
     * 获取属性值
     * @return 属性值
     */
    public function getValue():Number {
        if (!this._cacheValid) {
            if (this._computeFunc != null) {
                this._cache = this._computeFunc();
                trace("Computed '" + this._propName + "': " + this._cache);
            } else {
                this._cache = this._value;
                trace("Retrieved '" + this._propName + "': " + this._cache);
            }
            this._cacheValid = true;
        } else {
            trace("Cache hit for '" + this._propName + "': " + this._cache);
        }
        return this._cache;
    }

    /**
     * 设置属性值
     * @param newVal 新值
     */
    public function setValue(newVal:Number):Void {
        if (this._computeFunc != null) {
            trace("Property '" + this._propName + "' is read-only.");
            return;
        }
        if (newVal >= 0) {
            this._value = newVal;
            this._cacheValid = false;
            trace("Set '" + this._propName + "' to " + this._value);
            if (this._onSetCallback != null) {
                this._onSetCallback();
            }
        } else {
            trace("Invalid value: " + newVal + "! '" + this._propName + "' must be non-negative.");
        }
    }

    /**
     * 使缓存失效
     */
    public function invalidate():Void {
        this._cacheValid = false;
        trace("Cache for property '" + this._propName + "' invalidated.");
    }
}
