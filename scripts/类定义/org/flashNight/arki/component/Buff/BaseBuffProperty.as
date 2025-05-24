// org/flashNight/arki/component/Buff/BaseBuffProperty.as
import org.flashNight.arki.component.Buff.*;
import org.flashNight.arki.component.Buff.BuffHandle.*;
import org.flashNight.gesh.property.PropertyAccessor;
import org.flashNight.naki.DataStructures.Dictionary;

class org.flashNight.arki.component.Buff.BaseBuffProperty implements IBuffProperty {
    private var _obj:Object;         // 目标对象
    private var _propName:String;    // 属性名（buffed属性名）
    private var _basePropName:String; // 基础属性名

    private var _buffTable:Object;   // {type: {uid: buff}} 存储结构

    private var _baseAccessor:PropertyAccessor;   // 管理基础值
    private var _buffedAccessor:PropertyAccessor; // 管理 buffed 值（通过计算函数获取）

    // 累积变量（默认实现对 addition 和 multiplier 的优化）
    private var _totalAddition:Number;
    private var _totalMultiplier:Number;
    private var _zeroMultiplierCount:Number; // 记录乘数为0的 Buff 数量

    /**
     * 构造函数
     * @param obj             目标对象
     * @param propName        属性名称（buffed属性名）
     * @param defaultBaseValue 基础值默认值
     * @param computeFunc      可选计算函数，如果不传则使用默认实现（对 addition 和 multiplier 优化）
     */
    public function BaseBuffProperty(obj:Object, propName:String, defaultBaseValue:Number, computeFunc:Function) {
        this._obj = obj;
        this._propName = propName;
        this._basePropName = propName + "_base";

        // 初始化存储结构
        this._buffTable = {};  // {type: {uid: buff}}

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
            function(value:Number):Boolean {
                // 基础值验证函数，确保非负值
                if (value < 0) {
                    trace("Invalid value: " + value + "! '" + self._basePropName + "' must be non-negative.");
                    return false;
                }
                return true;
            }
        );

        // 创建 buffed 值访问器（如果未提供 computeFunc，则使用默认逻辑）
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
     * 默认实现的 computeBuffed，仅示范性处理 addition 和 multiplier 两种类型的优化。
     * 对其他类型的 Buff，无默认逻辑，需要子类在覆写时追加处理。
     */
    public function computeBuffed():Number {
        var baseValue:Number = this.getBaseValue();
        var result:Number;

        // 若存在零乘数 Buff，则总乘数为0
        if (this._zeroMultiplierCount > 0) {
            result = (baseValue + this._totalAddition) * 0;
        } else {
            result = (baseValue + this._totalAddition) * this._totalMultiplier;
        }

        // 子类可以在这里覆写，并在计算结束后对其他类型 Buff 做额外处理
        return result;
    }

    /**
     * 添加 Buff 的默认逻辑
     * 默认对 addition 和 multiplier 类型做优化处理：
     * - addition: 调整 _totalAddition
     * - multiplier: 调整 _totalMultiplier 与 _zeroMultiplierCount
     * 对其他类型的 Buff 不做特殊处理，子类可在覆写时增加逻辑。
     */
    public function addBuff(buff:IBuff):Void {
        var uid:Number = Dictionary.getStaticUID(buff);
        var buffType:String = buff.getType();

        if (this._buffTable[buffType] == undefined) {
            this._buffTable[buffType] = {};
        }

        if (this._buffTable[buffType][uid] == undefined) {
            this._buffTable[buffType][uid] = buff;

            // 对 addition 和 multiplier 优化逻辑
            if (buffType === BuffTypes.ADDITION) {
                this._totalAddition += AdditionBuff(buff).getAddition();
            } else if (buffType === BuffTypes.MULTIPLIER) {
                var multiplier:Number = MultiplierBuff(buff).getMultiplier();
                if (multiplier === 0) {
                    this._zeroMultiplierCount += 1;
                    this._totalMultiplier = 0;
                } else if (this._zeroMultiplierCount === 0) {
                    this._totalMultiplier *= multiplier;
                }
            } else {
                // 对其他类型不做默认处理，子类可在覆写本方法时加入逻辑
            }

            this.invalidate();
        }
    }

    /**
     * 移除 Buff 的默认逻辑
     * 同样默认对 addition 和 multiplier 做相应处理:
     * - addition: 更新 _totalAddition
     * - multiplier: 更新 _totalMultiplier 与 _zeroMultiplierCount
     * 其他类型无默认逻辑，子类可覆写拓展。
     */
    public function removeBuff(buff:IBuff):Void {
        var uid:Number = Dictionary.getStaticUID(buff);
        var buffType:String = buff.getType();
        var typeTable:Object = this._buffTable[buffType];

        if (typeTable != undefined && typeTable[uid] != undefined) {
            // 从存储中移除 Buff
            delete typeTable[uid];

            // 对 addition 和 multiplier 做相应处理
            if (buffType === BuffTypes.ADDITION) {
                var addVal:Number = AdditionBuff(buff).getAddition();
                this._totalAddition -= addVal;
            } else if (buffType === BuffTypes.MULTIPLIER) {
                var mulVal:Number = MultiplierBuff(buff).getMultiplier();
                if (mulVal === 0) {
                    this._zeroMultiplierCount -= 1;
                    if (this._zeroMultiplierCount === 0) {
                        // 无零乘数 Buff 时重新计算 _totalMultiplier
                        this._totalMultiplier = 1;
                        var multiplierTable:Object = this._buffTable[BuffTypes.MULTIPLIER];
                        if (multiplierTable != undefined) {
                            for (var mUid in multiplierTable) {
                                var currentMulBuff:MultiplierBuff = MultiplierBuff(multiplierTable[mUid]);
                                var currentMultiplier:Number = currentMulBuff.getMultiplier();
                                if (currentMultiplier !== 0) {
                                    this._totalMultiplier *= currentMultiplier;
                                }
                            }
                        }
                    }
                } else if (this._zeroMultiplierCount === 0 && mulVal != 0) {
                    // 除去非零乘数
                    this._totalMultiplier /= mulVal;
                }
            } else {
                // 对其他类型不做处理，子类可在覆写本方法加入逻辑
            }

            // 若该类型表已空，则删除该类型表项
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

    /**
     * 清空所有 Buff
     * 重置累积变量与存储结构，并使缓存失效
     */
    public function clearAllBuffs():Void {
        // 重置累积变量
        this._totalAddition = 0;
        this._totalMultiplier = 1;
        this._zeroMultiplierCount = 0;

        // 清空 Buff 存储
        this._buffTable = {};

        this.invalidate();
    }

    /**
     * 使属性缓存失效
     * 当基础值或 Buff 变更时调用，以确保下次访问重新计算
     */
    public function invalidate():Void {
        // 初次调用时动态决定 invalidate 方法的行为
        if (this._obj.invalidateDependents != undefined && this._obj.invalidateDependents instanceof Function) {
            // 如果依赖的缓存失效逻辑存在
            this.invalidate = function():Void {
                this._buffedAccessor.invalidate();
                this._obj.invalidateDependents();
            };
        } else {
            // 如果不存在依赖的缓存失效逻辑
            this.invalidate = function():Void {
                this._buffedAccessor.invalidate();
            };
        }

        // 调用动态修改后的方法
        this.invalidate();
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
     * 遍历 _buffTable，将所有类型的 Buff 合并到一个数组中返回
     */
    public function getBuffs():Array {
        var buffs:Array = [];
        for (var t in this._buffTable) {
            var typeTable:Object = this._buffTable[t];
            for (var uid in typeTable) {
                buffs.push(typeTable[uid]);
            }
        }
        return buffs;
    }
}
