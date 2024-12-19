// org/flashNight/gesh/property/PropertyAccessor.as
import org.flashNight.gesh.property.IProperty;

class org.flashNight.gesh.property.PropertyAccessor implements IProperty {
    private var _value:Number;
    private var _cache:Number;
    private var _cacheValid:Boolean;
    private var _computeFunc:Function;
    private var _onSetCallback:Function;
    private var _propName:String;
    private var _obj:Object;

    /**
     * 构造函数
     * @param obj           目标对象
     * @param propName      属性名称
     * @param defaultValue  默认值
     * @param computeFunc   计算函数（可选，用于派生属性）
     * @param onSetCallback 设置回调（可选，用于通知依赖属性）
     */
    public function PropertyAccessor(obj:Object, propName:String, defaultValue:Number, computeFunc:Function, onSetCallback:Function) {
        this._value = defaultValue;
        this._cache = defaultValue;
        this._cacheValid = true;
        this._computeFunc = computeFunc;
        this._onSetCallback = onSetCallback;
        this._propName = propName;
        this._obj = obj;

        var self:PropertyAccessor = this;

        // 添加属性访问器
        obj.addProperty(
            propName,
            function() {
                return self.get();
            },
            computeFunc == null ? function(newVal:Number) {
                self.set(newVal);
            } : null
        );
    }

    /**
     * 获取属性值
     * @return 属性值
     */
    public function get():Number {
        if (!this._cacheValid) {
            if (this._computeFunc != null) {
                this._cache = this._computeFunc();
            } else {
                this._cache = this._value;
            }
            this._cacheValid = true;
            trace("Computed property '" + this._propName + "': " + this._cache);
        } else {
            trace("Cache hit for property '" + this._propName + "': " + this._cache);
        }
        return this._cache;
    }

    /**
     * 设置属性值
     * @param newVal 新值
     */
    public function set(newVal:Number):Void {
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

    /**
     * 获取属性名称
     * @return 属性名称
     */
    public function getPropName():String {
        return this._propName;
    }
}
