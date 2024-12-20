// org/flashNight/arki/component/Buff/BaseBuffProperty.as
import org.flashNight.arki.component.Buff.*;
import org.flashNight.gesh.property.PropertyAccessor;
import org.flashNight.naki.DataStructures.Dictionary;

class org.flashNight.arki.component.Buff.BaseBuffProperty implements IBuffProperty {
    private var _obj:Object; // 目标对象
    private var _propName:String; // 属性名（buffed属性名）
    private var _basePropName:String; // 基础属性名
    private var _buffTable:Object; // 使用 {type: {uid: buff}} 结构存储 Buff
    private var _baseAccessor:PropertyAccessor; // 用于管理基础值
    private var _buffedAccessor:PropertyAccessor; // 用于管理 buffed 值（通过计算函数获取）

    // 累积变量
    private var _totalAddition:Number;
    private var _totalMultiplier:Number;
    private var _zeroMultiplierCount:Number; // 记录乘数为0的Buff数量

    /**
     * 构造函数
     * @param obj             目标对象
     * @param propName        属性名称（buffed的属性名）
     * @param defaultBaseValue 基础值默认值
     * @param computeFunc      可选的计算函数，如果不传则由子类实现 computeBuffed
     */
    public function BaseBuffProperty(obj:Object, propName:String, defaultBaseValue:Number, computeFunc:Function) {
        this._obj = obj;
        this._propName = propName;
        this._basePropName = propName + "_base";

        // 初始化 buffTable 为一个空对象，当添加buff时会动态添加类型
        this._buffTable = {};

        // 初始化累积变量
        this._totalAddition = 0;
        this._totalMultiplier = 1;
        this._zeroMultiplierCount = 0;

        var self:BaseBuffProperty = this;

        // 创建基础值访问器
        this._baseAccessor = new PropertyAccessor(
            obj,
            this._basePropName,
            defaultBaseValue,
            null,
            function() { self.invalidate(); },
            function(value:Number):Boolean { // 验证函数，基础值必须非负
                if (value < 0) {
                    trace("Invalid value: " + value + "! '" + self._basePropName + "' must be non-negative.");
                    return false;
                }
                return true;
            }
        );

        // 创建 buffed 值访问器
        var calcFunc:Function = computeFunc != null ? computeFunc : function():Number {
            return self.computeBuffed();
        };

        this._buffedAccessor = new PropertyAccessor(
            obj,
            this._propName,
            0,
            calcFunc,
            null,
            null
        );
    }

    /**
     * 子类可覆盖此方法，实现具体的 Buff 计算逻辑。
     * 基类仅示例性处理 addition 和 multiplier 两种类型。
     * 对于其他类型，子类应在覆写本方法时增加处理逻辑。
     */
    public function computeBuffed():Number {
        var baseValue:Number = this.getBaseValue();
        var result:Number;

        if (this._zeroMultiplierCount > 0) {
            // 任何乘数为0的Buff都将总乘数设为0
            result = (baseValue + this._totalAddition) * 0;
        } else {
            result = (baseValue + this._totalAddition) * this._totalMultiplier;
        }

        // 对于其他类型的 Buff，子类可以在覆写此方法时追加逻辑

        return result;
    }

    // ------------------ IBuffProperty 接口实现 ------------------

    public function addBuff(buff:IBuff):Void {
        var uid:Number = Dictionary.getStaticUID(buff);
        var buffType:String = buff.getType();

        // 如果该类型还没有表项，则创建一个空哈希表存储该类型的buff
        if (this._buffTable[buffType] == undefined) {
            this._buffTable[buffType] = {};
        }

        // 将buff存入对应类型的哈希表中
        this._buffTable[buffType][uid] = buff;

        // 更新累积变量
        if (buffType === "addition") {
            this._totalAddition += AdditionBuff(buff).getAddition();
        } else if (buffType === "multiplier") {
            var multiplier:Number = MultiplierBuff(buff).getMultiplier();
            if (multiplier === 0) {
                this._zeroMultiplierCount += 1;
                this._totalMultiplier = 0;
            } else if (this._zeroMultiplierCount === 0) {
                this._totalMultiplier *= multiplier;
            }
        }

        this.invalidate();
    }

    public function removeBuff(buff:IBuff):Void {
        var uid:Number = Dictionary.getStaticUID(buff);
        var buffType:String = buff.getType();

        var typeTable:Object = this._buffTable[buffType];
        if (typeTable != undefined && typeTable[uid] != undefined) {
            // 更新累积变量
            if (buffType === "addition") {
                this._totalAddition -= AdditionBuff(buff).getAddition();
            } else if (buffType === "multiplier") {
                var multiplier:Number = MultiplierBuff(buff).getMultiplier();
                if (multiplier === 0) {
                    this._zeroMultiplierCount -= 1;
                    if (this._zeroMultiplierCount === 0) {
                        // 重新计算 _totalMultiplier
                        this._totalMultiplier = 1;
                        for (var mUid in this._buffTable["multiplier"]) {
                            var mBuff:MultiplierBuff = MultiplierBuff(this._buffTable["multiplier"][mUid]);
                            this._totalMultiplier *= mBuff.getMultiplier();
                        }
                    }
                } else if (this._zeroMultiplierCount === 0) {
                    this._totalMultiplier /= multiplier;
                }
            }

            // 删除 buff
            delete typeTable[uid];

            // 如果该类型表已经空了，可以选择删除该类型表以保持整洁
            var empty:Boolean = true;
            for (var _ in typeTable) {
                empty = false;
                break;
            }
            if (empty) {
                delete this._buffTable[buffType];
            }

            this.invalidate();
        }
    }

    public function clearAllBuffs():Void {
        // 重置累积变量
        this._totalAddition = 0;
        this._totalMultiplier = 1;
        this._zeroMultiplierCount = 0;

        // 将 _buffTable 清空
        this._buffTable = {};
        this.invalidate();
    }

    public function invalidate():Void {
        this._buffedAccessor.invalidate();
        // 通知依赖属性缓存失效
        if (this._obj.invalidateDependents != undefined && this._obj.invalidateDependents instanceof Function) {
            this._obj.invalidateDependents();
        }
    }

    public function getBaseValue():Number {
        return this._baseAccessor.get();
    }

    public function setBaseValue(value:Number):Void {
        this._baseAccessor.set(value);
    }

    public function getBuffedValue():Number {
        return this._buffedAccessor.get();
    }

    public function getPropName():String {
        return this._propName;
    }

    /**
     * 获取当前所有 Buff 的列表
     * 注意：因为现在是按类型分类存储，因此需要遍历每个类型的哈希表。
     */
    public function getBuffs():Array {
        var buffs:Array = [];
        for (var buffType in this._buffTable) {
            var typeTable:Object = this._buffTable[buffType];
            for (var uid in typeTable) {
                buffs.push(typeTable[uid]);
            }
        }
        return buffs;
    }
}
