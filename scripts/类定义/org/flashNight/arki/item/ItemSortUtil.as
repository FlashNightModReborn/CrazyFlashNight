import org.flashNight.gesh.object.ObjectUtil;
import org.flashNight.arki.item.itemCollection.*;
import org.flashNight.arki.item.*;

/**
 * ItemSortUtil 物品栏排序工具类（AS2优化版）
 * 
 * 实现特点：
 * 1. 多维度排序：支持8种排序策略，可自动处理主/次级排序条件
 * 2. 数据安全：内置元数据和属性安全访问机制，防止空值导致的排序异常
 * 3. 类型感知：自动区分数值型和字符串型数据的比较逻辑
 * 4. 策略显式配置：每个排序策略的优先级链清晰可见，便于维护扩展
 * 5. 模块化设计：对特殊属性value进行独立处理模块封装
 * 
 * 排序策略清单：
 * - byType   : 物品类型 -> 用途 -> 总价 -> 等级 -> ID
 * - byUse    : 物品用途 -> 类型 -> 总价 -> 等级 -> ID 
 * - byPrice  : 总价（单价×数量）-> 类型 -> 用途 -> 等级 -> ID
 * - byLevel  : 需求等级 -> 类型 -> 用途 -> 总价 -> ID
 * - byID     : 物品ID直接排序
 * - byName   : 物品名称字母序排序
 * - byValue  : 物品数量数值排序（特殊安全处理）
 * - byTime   : 最后更新时间戳排序
 */
class org.flashNight.arki.item.ItemSortUtil {
    
    /*------------------------- 公共接口 -------------------------*/
    
    /**
     * 执行物品栏排序操作
     * 
     * @param inventory  需要排序的物品栏实例（ArrayInventory类型）
     * @param methodName 排序策略名称（可选，默认"byType"）
     * @param callback   排序完成后的回调函数（可选）
     */
    public static function sortInventory(
        inventory:ArrayInventory, 
        methodName:String, 
        callback:Function
    ):Void {
        methodName = validateSortMethod(methodName);
        inventory.rebuildOrder(getComparatorChain(methodName));
        if (typeof callback === "function") callback(inventory);
    }

    /*------------------------- 核心比较模块 ----------------------*/
    
    // ----------------- 总价比较模块 -----------------
    /**
     * 生成总价比较器（单价×数量）
     * 
     * 实现特性：
     * - 使用安全数值获取模块处理数量值
     * - 自动处理非数值类型的数量值
     */
    private static function totalPriceComparator():Function {
        return function(a:Object, b:Object):Number {
            return compareNumbers(
                calculateTotalValue(a),
                calculateTotalValue(b)
            );
        };
    }

    /**
     * 计算物品总价值
     * 
     * @param item 物品对象
     * @return Number 总价值（单价×安全数量）
     */
    private static function calculateTotalValue(item:Object):Number {
        var price:Number = safeGetMeta(item.name, "price", true);
        var count:Number = safeGetNumber(item, "value", true);
        return price * count;
    }

    // ----------------- 元数据比较模块 -----------------
    /**
     * 生成元数据比较器
     * 
     * @param field    要比较的元数据字段名
     * @param numeric  是否按数值类型比较
     */
    private static function metaComparator(field:String, numeric:Boolean):Function {
        return function(a:Object, b:Object):Number {
            var aMeta = safeGetMeta(a.name, field, numeric);
            var bMeta = safeGetMeta(b.name, field, numeric);
            return numeric ? compareNumbers(aMeta, bMeta) : compareStrings(aMeta, bMeta);
        };
    }

    // ----------------- 属性比较模块 -----------------
    /**
     * 生成通用属性比较器
     * 
     * 特殊处理：
     * - 自动识别value属性并切换专用获取方法
     */
    private static function propComparator(prop:String, numeric:Boolean):Function {
        return function(a:Object, b:Object):Number {
            // 属性名称标准化处理
            var normalizedProp:String = prop.toLowerCase();
            
            // 选择获取方法
            var getMethod:Function = (normalizedProp == "value") ? 
                safeGetNumber : 
                safeGetProp;

            var aVal = getMethod(a, prop, numeric);
            var bVal = getMethod(b, prop, numeric);
            
            return numeric ? compareNumbers(aVal, bVal) : compareStrings(aVal, bVal);
        };
    }

    // ----------------- 专用数值比较模块 -----------------
    /**
     * 生成安全数值比较器（专用于value属性）
     */
    private static function valueComparator():Function {
        return function(a:Object, b:Object):Number {
            return compareNumbers(
                safeGetNumber(a, "value", true),
                safeGetNumber(b, "value", true)
            );
        };
    }

    /*------------------------- 安全访问模块 ----------------------*/
    
    // ----------------- 元数据安全访问 -----------------
    /**
     * 安全获取物品元数据
     * 
     * @param itemName 物品名称
     * @param field    元数据字段名
     * @param numeric  是否返回数值类型
     * @return 获取到的数据或默认值（数值返回0，字符串返回空）
     */
    private static function safeGetMeta(itemName:String, field:String, numeric:Boolean) {
        var itemData = ItemUtil.itemDataDict[itemName];
        if (!itemData) return numeric ? 0 : "";
        return itemData[field] != undefined ? itemData[field] : (numeric ? 0 : "");
    }

    // ----------------- 通用属性安全访问 -----------------
    /**
     * 安全获取普通属性值
     * 
     * @param item    物品对象
     * @param prop    属性名称
     * @param numeric 是否返回数值类型
     * @return 获取到的属性值或默认值
     */
    private static function safeGetProp(item:Object, prop:String, numeric:Boolean) {
        return item[prop] != undefined ? item[prop] : (numeric ? 0 : "");
    }

    // ----------------- 专用数值安全访问 -----------------
    /**
     * 安全获取物品数量值（value属性专用）
     * 
     * 实现特性：
     * 1. 自动转换机制：非数值类型强制转换为1
     * 2. 空值保护：属性不存在时返回1
     * 3. 类型安全：确保返回值符合预期类型
     * 
     * @param item    物品对象
     * @param prop    属性名称（自动识别value属性）
     * @param numeric 是否返回数值类型
     * @return 安全处理后的数值
     */
    private static function safeGetNumber(item:Object, prop:String, numeric:Boolean) {
        // 属性名称标准化
        var normalizedProp:String = prop.toLowerCase();
        
        // 仅对value属性特殊处理
        if (normalizedProp == "value") {
            var val = item[prop];
            
            // 类型检测与转换
            if (typeof val != "number") {
                logInvalidValue(item, val); // 记录非常规数值
                return numeric ? 1 : "1";
            }
            return val;
        }
        
        // 其他属性走标准流程
        return safeGetProp(item, prop, numeric);
    }

    /*------------------------- 工具模块 -------------------------*/
    
    // ----------------- 核心比较工具 -----------------
    /**
     * 数值比较核心方法
     */
    private static function compareNumbers(a:Number, b:Number):Number {
        return a > b ? 1 : (a < b ? -1 : 0);
    }

    /**
     * 字符串比较核心方法（不区分大小写）
     */
    private static function compareStrings(a:String, b:String):Number {
        var strA:String = a != null ? a.toUpperCase() : "";
        var strB:String = b != null ? b.toUpperCase() : "";
        return strA > strB ? 1 : (strA < strB ? -1 : 0);
    }

    // ----------------- 调试工具 -----------------
    /**
     * 记录无效value值
     */
    private static function logInvalidValue(item:Object, value):Void {
        trace("[ItemSortUtil] 检测到非数值value属性 -" +
              "物品名称:" + item.name +
              "当前值:" + value +
              "已自动转换为1");
    }

    /*------------------------- 策略配置模块 ----------------------*/
    
    /**
     * 排序策略链配置中心
     * 配置说明：
     * - 每个键对应一种排序策略
     * - 数组顺序表示比较优先级（从主到次）
     */
    private static var STRATEGY_CHAINS:Object = initChain();

    private static function initChain():Object{
        return {
            // 类型优先策略链
            byType: [
                metaComparator("type", false),
                metaComparator("use", false),
                totalPriceComparator(),
                metaComparator("level", true),
                metaComparator("id", true)
            ],
            
            // 用途优先策略链
            byUse: [
                metaComparator("use", false),
                metaComparator("type", false),
                totalPriceComparator(),
                metaComparator("level", true),
                metaComparator("id", true)
            ],
            
            // 总价优先策略链
            byPrice: [
                totalPriceComparator(),
                metaComparator("type", false),
                metaComparator("use", false),
                metaComparator("level", true),
                metaComparator("id", true)
            ],
            
            // 等级优先策略链
            byLevel: [
                metaComparator("level", true),
                metaComparator("type", false),
                metaComparator("use", false),
                totalPriceComparator(),
                metaComparator("id", true)
            ],
            
            // 简单策略
            byID:    [metaComparator("id", true)],
            byName:  [propComparator("name", false)],
            byValue: [valueComparator()], // 使用专用比较器
            byTime:  [propComparator("lastUpdate", true)]
        };
    }

    /*------------------------- 策略选择模块 ----------------------*/
    
    /**
     * 获取指定策略的比较链
     */
    private static function getComparatorChain(method:String):Function {
        return createComparatorChain(STRATEGY_CHAINS[method]);
    }

    /**
     * 创建链式比较器
     */
    private static function createComparatorChain(chain:Array):Function {
        return function(a:Object, b:Object):Number {
            for (var i:Number = 0; i < chain.length; i++) {
                var result:Number = chain[i](a, b);
                if (result != 0) return result;
            }
            return 0;
        };
    }

    /**
     * 验证排序策略有效性
     */
    private static function validateSortMethod(method:String):String {
        var DEFAULT_METHOD:String = "byType";
        return (method && STRATEGY_CHAINS[method] != undefined) ? method : DEFAULT_METHOD;
    }
}
