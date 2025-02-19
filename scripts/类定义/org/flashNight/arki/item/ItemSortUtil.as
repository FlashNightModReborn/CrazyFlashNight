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
 * 
 * 排序策略清单：
 * - byType   : 物品类型 -> 用途 -> 价格 -> 等级 -> ID
 * - byUse    : 物品用途 -> 类型 -> 价格 -> 等级 -> ID 
 * - byPrice  : 物品价格 -> 类型 -> 用途 -> 等级 -> ID
 * - byLevel  : 需求等级 -> 类型 -> 用途 -> 价格 -> ID
 * - byID     : 物品ID直接排序
 * - byName   : 物品名称字母序排序
 * - byValue  : 物品价值数值排序
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

    /*------------------------- 核心比较逻辑 ----------------------*/
    
    /**
     * 生成元数据比较器
     * 
     * @param field    要比较的元数据字段名
     * @param numeric  是否按数值类型比较
     * @return Function 生成的具体比较函数
     */
    private static function metaComparator(field:String, numeric:Boolean):Function {
        return function(a:Object, b:Object):Number {
            var aMeta = safeGetMeta(a.name, field, numeric);
            var bMeta = safeGetMeta(b.name, field, numeric);
            return numeric ? compareNumbers(aMeta, bMeta) : compareStrings(aMeta, bMeta);
        };
    }

    /**
     * 生成物品属性比较器
     * 
     * @param prop     要比较的物品属性名
     * @param numeric  是否按数值类型比较
     * @return Function 生成的具体比较函数
     */
    private static function propComparator(prop:String, numeric:Boolean):Function {
        return function(a:Object, b:Object):Number {
            var aVal = safeGetProp(a, prop, numeric);
            var bVal = safeGetProp(b, prop, numeric);
            return numeric ? compareNumbers(aVal, bVal) : compareStrings(aVal, bVal);
        };
    }

    /*------------------------- 工具方法 -------------------------*/
    
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

    /**
     * 安全获取物品属性值
     * 
     * @param item    物品对象
     * @param prop    属性名称
     * @param numeric 是否返回数值类型
     * @return 获取到的属性值或默认值
     */
    private static function safeGetProp(item:Object, prop:String, numeric:Boolean) {
        return item[prop] != undefined ? item[prop] : (numeric ? 0 : "");
    }

    /**
     * 数值比较核心方法
     * 
     * @param a 第一个数值
     * @param b 第二个数值
     * @return Number 比较结果：1(a>b), -1(a<b), 0(相等)
     */
    private static function compareNumbers(a:Number, b:Number):Number {
        if (a > b) return 1;
        if (a < b) return -1;
        return 0;
    }

    /**
     * 字符串比较核心方法（不区分大小写）
     * 
     * @param a 第一个字符串
     * @param b 第二个字符串
     * @return Number 比较结果：1(a>b), -1(a<b), 0(相等)
     */
    private static function compareStrings(a:String, b:String):Number {
        a = a != null ? a.toUpperCase() : "";
        b = b != null ? b.toUpperCase() : "";
        if (a > b) return 1;
        if (a < b) return -1;
        return 0;
    }

    /*------------------------- 策略配置 -------------------------*/
    
    /**
     * 排序策略链配置中心
     * - 每个键值对表示一个排序策略
     * - 数组顺序表示比较优先级（从主到次）
     */
    private static var STRATEGY_CHAINS:Object = initChain();

    private static function initChain():Object{
        var obj:Object = {
            // 类型优先策略链
            byType: [
                metaComparator("type", false),
                metaComparator("use", false),
                metaComparator("price", true),
                metaComparator("level", true),
                metaComparator("id", true)
            ],
            
            // 用途优先策略链
            byUse: [
                metaComparator("use", false),
                metaComparator("type", false),
                metaComparator("price", true),
                metaComparator("level", true),
                metaComparator("id", true)
            ],
            
            // 价格优先策略链
            byPrice: [
                metaComparator("price", true),
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
                metaComparator("price", true),
                metaComparator("id", true)
            ],
            
            // 简单策略（单条件排序）
            byID:    [metaComparator("id", true)],
            byName:  [propComparator("name", false)],
            byValue: [propComparator("value", true)],
            byTime:  [propComparator("lastUpdate", true)]
        };

        return obj;
    }

    /*------------------------- 策略选择 -------------------------*/
    
    /**
     * 获取指定策略的比较链
     * 
     * @param method 策略名称
     * @return Function 组装好的比较链函数
     */
    private static function getComparatorChain(method:String):Function {
        return createComparatorChain(STRATEGY_CHAINS[method]);
    }

    /**
     * 创建链式比较器
     * 
     * @param chain 比较器数组（按优先级排序）
     * @return Function 可执行链式比较的函数
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
     * 
     * @param method 输入的策略名称
     * @return String 有效的策略名称（无效时返回默认策略）
     */
    private static function validateSortMethod(method:String):String {
        var DEFAULT_METHOD:String = "byType";
        return (method && STRATEGY_CHAINS[method] != undefined) ? method : DEFAULT_METHOD;
    }
}