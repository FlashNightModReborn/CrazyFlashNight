import org.flashNight.arki.component.Buff.*;
import org.flashNight.arki.component.Buff.BuffHandle.*;
import org.flashNight.gesh.property.PropertyAccessor;
import org.flashNight.naki.DataStructures.Dictionary;

class org.flashNight.arki.component.Buff.BuffPropertyHandle.BasicBuffProperty extends BaseBuffProperty{
    private var _globalUpperLimit:Number;
    private var _globalLowerLimit:Number;
    private var _haveLimits:Boolean;

    private var _buffUpperLimits:Object;
    private var _buffLowerLimits:Object;

    function BasicBuffProperty(obj:Object, propName:String, defaultBaseValue:Number, computeFunc:Function) {
        super(obj, propName, defaultBaseValue, computeFunc);
        this._globalUpperLimit = Number.POSITIVE_INFINITY;
        this._globalLowerLimit = Number.NEGATIVE_INFINITY;
        this._haveLimits = false;
        this._buffUpperLimits = {};
        this._buffLowerLimits = {};
    }

    public function computeBuffed():Number {
        var baseValue:Number = this.getBaseValue();
        var rawValue:Number;

        // 正确计算顺序：先乘后加
        if (this._zeroMultiplierCount > 0) {
            rawValue = (baseValue * 0) + this._totalAddition;
        } else {
            rawValue = (baseValue * this._totalMultiplier) + this._totalAddition;
        }

        // 应用上下限
        if (this._haveLimits) {
            if (rawValue > this._globalUpperLimit) {
                rawValue = this._globalUpperLimit;
            }
            if (rawValue < this._globalLowerLimit) {
                rawValue = this._globalLowerLimit;
            }
        }

        return rawValue;
    }

    /**
     * 重写 addBuff：增加 upperLimit、lowerLimit 可选参数以接收测试时传入的上下限
     */
    public function addBuff(buff:IBuff, upperLimit:Number, lowerLimit:Number):Void {
        // 调用基类逻辑对 addition 和 multiplier 进行处理
        var uid:Number = Dictionary.getStaticUID(buff);
        var buffType:String = buff.getType();

        if (this._buffTable[buffType] == undefined) {
            this._buffTable[buffType] = {};
        }

        if (this._buffTable[buffType][uid] == undefined) {
            this._buffTable[buffType][uid] = buff;

            // 根据类型更新累积变量（复用 BaseBuffProperty 中的逻辑）
            if (buffType === BuffTypes.ADDITION) {
                var addVal:Number = AdditionBuff(buff).getAddition();
                this._totalAddition += addVal;
            } else if (buffType === BuffTypes.MULTIPLIER) {
                var mulVal:Number = MultiplierBuff(buff).getMultiplier();
                if (mulVal === 0) {
                    this._zeroMultiplierCount += 1;
                    this._totalMultiplier = 0;
                } else if (this._zeroMultiplierCount === 0) {
                    this._totalMultiplier *= mulVal;
                }
            }

            // 存储 Buff 特有的上下限信息
            if (upperLimit != undefined) {
                this._buffUpperLimits[uid] = upperLimit;
            }
            if (lowerLimit != undefined) {
                this._buffLowerLimits[uid] = lowerLimit;
            }

            // 重新计算全局上下限
            this.recalculateGlobalLimits();

            this.invalidate();
        }
    }

    /**
     * 重写 removeBuff：移除对应 buff 的上下限信息并重算全局上下限
     */
    public function removeBuff(buff:IBuff):Void {
        var uid:Number = Dictionary.getStaticUID(buff);
        var buffType:String = buff.getType();
        var typeTable:Object = this._buffTable[buffType];

        if (typeTable != undefined && typeTable[uid] != undefined) {
            // 移除 buff 本体
            delete typeTable[uid];

            // 更新累积变量
            if (buffType === BuffTypes.ADDITION) {
                var addVal:Number = AdditionBuff(buff).getAddition();
                this._totalAddition -= addVal;
            } else if (buffType === BuffTypes.MULTIPLIER) {
                var mulVal:Number = MultiplierBuff(buff).getMultiplier();
                if (mulVal === 0) {
                    this._zeroMultiplierCount -= 1;
                    if (this._zeroMultiplierCount === 0) {
                        this._totalMultiplier = 1;
                        var multiplierTable:Object = this._buffTable[BuffTypes.MULTIPLIER];
                        if (multiplierTable != undefined) {
                            for (var mUid in multiplierTable) {
                                var currentMulBuff:MultiplierBuff = MultiplierBuff(multiplierTable[mUid]);
                                var currentMultiplier:Number = currentMulBuff.getMultiplier();
                                if (currentMultiplier != 0) {
                                    this._totalMultiplier *= currentMultiplier;
                                }
                            }
                        }
                    }
                } else if (this._zeroMultiplierCount === 0 && mulVal != 0) {
                    this._totalMultiplier /= mulVal;
                }
            }

            // 移除上下限信息
            delete this._buffUpperLimits[uid];
            delete this._buffLowerLimits[uid];

            // 如果该类型 Buff 已空则删除该类型表
            var empty:Boolean = true;
            for (var _ in typeTable) {
                empty = false;
                break;
            }
            if (empty) {
                delete this._buffTable[buffType];
            }

            // 重算上下限
            this.recalculateGlobalLimits();

            this.invalidate();
        }
    }

    private function recalculateGlobalLimits():Void {
        this._globalUpperLimit = Number.POSITIVE_INFINITY;
        this._globalLowerLimit = Number.NEGATIVE_INFINITY;
        this._haveLimits = false;

        // 基于所有 buff 上下限计算全局上下限
        for (var uid in this._buffUpperLimits) {
            var upper:Number = this._buffUpperLimits[uid];
            if (upper < this._globalUpperLimit) {
                this._globalUpperLimit = upper;
            }
            this._haveLimits = true;
        }

        for (var uid2 in this._buffLowerLimits) {
            var lower:Number = this._buffLowerLimits[uid2];
            if (lower > this._globalLowerLimit) {
                this._globalLowerLimit = lower;
            }
            this._haveLimits = true;
        }
    }

    public function clearAllBuffs():Void {
        super.clearAllBuffs();
        this._globalUpperLimit = Number.POSITIVE_INFINITY;
        this._globalLowerLimit = Number.NEGATIVE_INFINITY;
        this._haveLimits = false;
        this._buffUpperLimits = {};
        this._buffLowerLimits = {};
        this.invalidate();
    }
}
