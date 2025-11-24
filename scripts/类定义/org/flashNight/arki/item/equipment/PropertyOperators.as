import org.flashNight.gesh.object.ObjectUtil;

/**
 * PropertyOperators - 装备属性运算工具类
 *
 * 提供所有属性运算的纯函数实现，从 EquipmentUtil 中提取
 * 所有方法为静态方法，无副作用，便于测试和复用
 *
 * @author 重构自 EquipmentUtil
 */
class org.flashNight.arki.item.equipment.PropertyOperators {

    // 需要保留小数点的属性字典（从 EquipmentUtil 复制）
    private static var decimalPropDict:Object = {
        weight: 1,
        rout: 1,
        vampirism: 1
    };

    /**
     * 设置小数精度字典
     * @param dict 小数精度配置
     */
    public static function setDecimalPropDict(dict:Object):Void {
        decimalPropDict = dict;
    }

    /**
     * 输入2个存放装备属性的Object对象，将后者每个属性的值增加到前者。
     * 如果键在两个Object中都存在，则值相加；
     * 如果键只在后一个Object中存在，则取该Object的值 + 初始值。
     *
     * @param prop 要被修改的属性对象。
     * @param addProp 用于相加的属性对象。
     * @param initValue prop 不存在对应属性时的初始值。
     */
    public static function add(prop:Object, addProp:Object, initValue:Number):Void {
        if (!addProp) return;

        for (var key:String in addProp) {
            var addVal:Number = addProp[key];
            if (isNaN(addVal)) continue;

            if (prop[key] !== undefined) {
                prop[key] += addVal;
            } else {
                prop[key] = initValue + addVal;
            }
        }
    }

    /**
     * 输入2个存放装备属性的Object对象，将后者每个属性的值对前者相乘，并四舍五入，远离原点取整。
     * 不校验浮点数的精度，对于非常小的浮点数可能会有误差，但边界行为对装备数值来说可接受
     * 如果键在两个Object中都存在，则值相乘，然后通过位运算去除小数位；
     * 如果键只在后一个Object中存在，不作处理。
     *
     * @param prop 要被修改的属性对象。
     * @param multiProp 用于相乘的属性对象。
     */
    public static function multiply(prop:Object, multiProp:Object):Void {
        if (!multiProp) return;

        var dpd:Object = decimalPropDict; // 需要保留一位小数的键

        for (var key:String in multiProp) {
            var a:Number = prop[key];
            var b:Number = multiProp[key];
            var val:Number = a * b;

            // 保持原语义：val 为 0/NaN/undefined 时不写回
            if (!val) continue;

            // 一条路径搞定整数/一位小数
            var dec:Boolean = dpd[key];             // 是否保留一位小数
            var scale:Number = dec ? 10 : 1;        // 放大倍数
            var t:Number = val * scale;

            // 0.5 远离 0：正数 +0.5，负数 -0.5
            t += (t >= 0) ? 0.5 : -0.5;

            // 位运算转 int32，向0截断
            var n:Number = (t | 0);

            // 写回（小数则缩回）
            prop[key] = dec ? (n * 0.1) : n;

            // 消除 -0
            if (prop[key] == 0) prop[key] = 0;
        }
    }

    /**
     * 输入2个存放装备属性的Object对象，将后者的每个属性覆盖前者。
     *
     * @param prop 要被修改的属性对象。
     * @param overProp 用于覆盖的属性对象。
     */
    public static function override(prop:Object, overProp:Object):Void {
        if (!overProp) return;

        for (var key:String in overProp) {
            prop[key] = overProp[key];
        }
    }

    /**
     * 深度合并属性对象（智能合并）。
     * 递归处理嵌套对象，对于数字类型采用智能合并策略：
     * - 如果存在负数，取最小值（保留最不利的debuff）
     * - 如果都是正数，取最大值（保留最有利的buff）
     *
     * 使用场景：
     * - magicdefence等嵌套对象的部分更新
     * - skillmultipliers的多技能倍率合并
     *
     * @param prop 目标属性对象（会被修改）
     * @param mergeProp 要合并的属性对象
     */
    public static function merge(prop:Object, mergeProp:Object):Void {
        if (!mergeProp) return;

        for (var key:String in mergeProp) {
            var mergeVal = mergeProp[key];
            var propVal = prop[key];

            // 情况1：目标属性不存在，直接添加（深度克隆）
            if (propVal == undefined) {
                prop[key] = ObjectUtil.clone(mergeVal);
                continue;
            }

            // 情况2：两个都是对象（且不是null），递归合并
            if (typeof mergeVal == "object" && mergeVal != null &&
                typeof propVal == "object" && propVal != null) {
                merge(propVal, mergeVal); // 递归调用
                continue;
            }

            // 情况3：都是数字，智能合并
            if (typeof mergeVal == "number" && typeof propVal == "number") {
                // 有负数存在：取最小值（负数debuff优先）
                if (mergeVal < 0 || propVal < 0) {
                    prop[key] = Math.min(propVal, mergeVal);
                } else {
                    // 都是正数：取最大值（正数buff优先）
                    prop[key] = Math.max(propVal, mergeVal);
                }
                continue;
            }

            // 情况4：其他类型（字符串等），直接覆盖
            prop[key] = mergeVal;
        }
    }

    /**
     * 应用属性上限过滤。对最终计算结果应用上限约束。
     * 正数cap表示属性的最大值（上限），负数cap表示属性的最小值（下限，绝对值）。
     *
     * @param prop 要被限制的属性对象。
     * @param capProp 上限配置对象。
     * @param baseProp 基础属性对象（用于计算变化量）。如果为null，则直接限制绝对值。
     */
    public static function applyCap(prop:Object, capProp:Object, baseProp:Object):Void {
        if (!capProp) return;

        for (var key:String in capProp) {
            var capValue:Number = capProp[key];
            if (capValue == undefined || capValue == 0) continue;

            var currentVal:Number = prop[key];
            if (currentVal == undefined) continue;

            if (baseProp && baseProp[key] != undefined) {
                // 基于基础值计算变化量
                var baseVal:Number = baseProp[key];
                var change:Number = currentVal - baseVal;

                if (capValue > 0) {
                    // 正数cap = 增益上限（最多增加capValue）
                    if (change > capValue) {
                        prop[key] = baseVal + capValue;
                    }
                } else if (capValue < 0) {
                    // 负数cap = 减益下限（最多减少|capValue|）
                    if (change < capValue) {
                        prop[key] = baseVal + capValue;  // capValue本身是负数
                    }
                }
            } else {
                // 没有基础值，直接限制绝对值
                if (capValue > 0) {
                    // 正数cap = 最大值上限
                    if (currentVal > capValue) {
                        prop[key] = capValue;
                    }
                } else if (capValue < 0) {
                    // 负数cap = 最小值下限（绝对值）
                    var minValue:Number = -capValue;  // 转换为正数
                    if (currentVal < minValue) {
                        prop[key] = minValue;
                    }
                }
            }
        }
    }

    // ========================= 测试辅助方法 =========================

    /**
     * 运行属性运算符的单元测试
     * @return 测试结果字符串
     */
    public static function runTests():String {
        var results:Array = [];

        // 测试 add 方法
        results.push(testAdd());

        // 测试 multiply 方法
        results.push(testMultiply());

        // 测试 override 方法
        results.push(testOverride());

        // 测试 merge 方法
        results.push(testMerge());

        // 测试 applyCap 方法
        results.push(testApplyCap());

        // 汇总结果
        var allPassed:Boolean = true;
        var summary:String = "\n===== PropertyOperators 单元测试结果 =====\n";

        for (var i:Number = 0; i < results.length; i++) {
            summary += results[i] + "\n";
            if (results[i].indexOf("✗") != -1) {
                allPassed = false;
            }
        }

        summary += allPassed ? "\n所有测试通过！" : "\n有测试失败，请检查！";
        return summary;
    }

    private static function testAdd():String {
        var prop:Object = {damage: 10, defence: 20};
        var addProp:Object = {damage: 5, hp: 100};

        add(prop, addProp, 0);

        var passed:Boolean = (prop.damage == 15 && prop.defence == 20 && prop.hp == 100);
        return passed ? "✓ add 测试通过" : "✗ add 测试失败";
    }

    private static function testMultiply():String {
        var prop:Object = {damage: 100, weight: 1.5};
        var multiProp:Object = {damage: 1.5, weight: 2};

        multiply(prop, multiProp);

        // damage应该是150（整数），weight应该是3.0（保留1位小数）
        var passed:Boolean = (prop.damage == 150 && prop.weight == 3);
        return passed ? "✓ multiply 测试通过" : "✗ multiply 测试失败";
    }

    private static function testOverride():String {
        var prop:Object = {damage: 100, defence: 50};
        var overProp:Object = {damage: 200};

        override(prop, overProp);

        var passed:Boolean = (prop.damage == 200 && prop.defence == 50);
        return passed ? "✓ override 测试通过" : "✗ override 测试失败";
    }

    private static function testMerge():String {
        var prop:Object = {
            damage: 100,
            magicdefence: {fire: 10, ice: 20}
        };
        var mergeProp:Object = {
            damage: 150,
            magicdefence: {fire: 15, poison: 5}
        };

        merge(prop, mergeProp);

        // damage取最大值150，fire取最大值15，ice保持20，新增poison为5
        var passed:Boolean = (
            prop.damage == 150 &&
            prop.magicdefence.fire == 15 &&
            prop.magicdefence.ice == 20 &&
            prop.magicdefence.poison == 5
        );
        return passed ? "✓ merge 测试通过" : "✗ merge 测试失败";
    }

    private static function testApplyCap():String {
        var prop:Object = {damage: 150, defence: 30};
        var capProp:Object = {damage: 20, defence: -10};  // damage最多增加20，defence最多减少10
        var baseProp:Object = {damage: 100, defence: 50};

        applyCap(prop, capProp, baseProp);

        // damage从100增加到150，但cap限制为+20，所以变为120
        // defence从50减少到30，减少了20，但cap限制为-10，所以变为40
        var passed:Boolean = (prop.damage == 120 && prop.defence == 40);
        return passed ? "✓ applyCap 测试通过" : "✗ applyCap 测试失败";
    }
}