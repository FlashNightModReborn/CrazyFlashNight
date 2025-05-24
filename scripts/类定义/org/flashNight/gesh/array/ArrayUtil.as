// 文件: org/flashNight/gesh/array/ArrayUtil.as
/**
 * ArrayUtil 类提供了一系列静态方法，用于操作和处理数组。
 * 这些方法模拟了现代 JavaScript 数组 API 的功能，适用于 ActionScript 2 (AS2) 环境。
 * 
 * @author 
 * @version 1.0
 */
class org.flashNight.gesh.array.ArrayUtil {
    
    // ===========================
    // ====== 基础/已有方法 =======
    // ===========================
    
    /**
     * 检查给定的对象是否为数组。
     * 
     * @param obj 要检查的对象。
     * @return 如果对象是数组，返回 true；否则返回 false。
     * 
     * @example
     * <pre>
     * ArrayUtil.isArray([1, 2, 3]); // 返回 true
     * ArrayUtil.isArray({a:1}); // 返回 false
     * </pre>
     */
    public static function isArray(obj:Object):Boolean {
        return (obj instanceof Array);
    }
    
    /**
     * 对数组的每个元素执行一次提供的回调函数。
     * 
     * @param arr 要遍历的数组。
     * @param callback 对每个元素执行的函数，接受三个参数：当前元素、索引和数组本身。
     * 
    * @example
    * <pre>
    * var arr:Array = [1, 2, 3];
    * ArrayUtil.forEach(arr, function(element:Object, index:Number, array:Array):Void {
    *     trace("Element at index " + index + ": " + element);
    * });
    * // 输出:
    * // Element at index 0: 1
    * // Element at index 1: 2
    * // Element at index 2: 3
    * </pre>
     */
    public static function forEach(arr:Array, callback:Function):Void {
        var len:Number = arr.length;
        for (var i:Number = 0; i < len; i++) {
            callback(arr[i], i, arr);
        }
    }
    
    /**
     * 创建一个新数组，其中包含调用提供的函数后返回的每个元素的结果。
     * 
     * @param arr 要映射的数组。
     * @param callback 对每个元素执行的函数，接受三个参数：当前元素、索引和数组本身。
     * @return 一个新数组，每个元素是回调函数的结果。
     * 
    * @example
    * <pre>
    * var arr:Array = [1, 2, 3];
    * var mapped:Array = ArrayUtil.map(arr, function(element:Object):Object {
    *     return element * 2;
    * });
    * trace(mapped); // 输出: 2,4,6
    * </pre>
     */
    public static function map(arr:Array, callback:Function):Array {
        var result:Array = [];
        var len:Number = arr.length;
        for (var i:Number = 0; i < len; i++) {
            result.push(callback(arr[i], i, arr));
        }
        return result;
    }
    
    /**
     * 创建一个新数组，其中包含所有通过提供的回调函数测试的元素。
     * 
     * @param arr 要过滤的数组。
     * @param callback 测试每个元素的函数，接受三个参数：当前元素、索引和数组本身。
     * @return 一个新数组，包含通过测试的元素。
     * 
    * @example
    * <pre>
    * var arr:Array = [1, 2, 3, 4, 5];
    * var filtered:Array = ArrayUtil.filter(arr, function(element:Object):Boolean {
    *     return element % 2 === 0;
    * });
    * trace(filtered); // 输出: 2,4
    * </pre>
     */
    public static function filter(arr:Array, callback:Function):Array {
        var result:Array = [];
        var len:Number = arr.length;
        for (var i:Number = 0; i < len; i++) {
            if (callback(arr[i], i, arr)) {
                result.push(arr[i]);
            }
        }
        return result;
    }
    
    /**
     * 使用提供的回调函数对数组的累加器和每个元素执行操作，以将数组简化为单个值。
     * 
     * @param arr 要简化的数组。
     * @param callback 对每个元素执行的函数，接受四个参数：累加器、当前元素、索引和数组本身。
     * @param initialValue 用于开始累加的初始值（可选）。
     * @return 累加后的结果。
     * 
    * @example
    * <pre>
    * var arr:Array = [1, 2, 3, 4, 5];
    * var sum:Object = ArrayUtil.reduce(arr, function(acc:Object, curr:Object):Object {
    *     return acc + curr;
    * }, 0);
    * trace(sum); // 输出: 15
    * </pre>
     * 
     * @throws Error 如果数组为空且未提供初始值。
     */
    public static function reduce(arr:Array, callback:Function, initialValue:Object):Object {
        var len:Number = arr.length;
        if (len == 0 && arguments.length < 3) {
            throw new Error("Reduce of empty array with no initial value");
        }
        
        var accumulator:Object;
        var startIndex:Number;
        
        if (arguments.length >= 3) {
            accumulator = initialValue;
            startIndex = 0;
        } else {
            accumulator = arr[0];
            startIndex = 1;
        }
        
        for (var i:Number = startIndex; i < len; i++) {
            accumulator = callback(accumulator, arr[i], i, arr);
        }
        return accumulator;
    }
    
    /**
     * 测试数组中是否至少有一个元素通过了提供的回调函数测试。
     * 
     * @param arr 要测试的数组。
     * @param callback 测试每个元素的函数，接受三个参数：当前元素、索引和数组本身。
     * @return 如果任何元素通过测试，则返回 true；否则返回 false。
     * 
    * @example
    * <pre>
    * var arr:Array = [1, 3, 5, 7, 8];
    * var hasEven:Boolean = ArrayUtil.some(arr, function(element:Object):Boolean {
    *     return element % 2 === 0;
    * });
    * trace(hasEven); // 输出: true
    * </pre>
     */
    public static function some(arr:Array, callback:Function):Boolean {
        var len:Number = arr.length;
        for (var i:Number = 0; i < len; i++) {
            if (callback(arr[i], i, arr)) {
                return true;
            }
        }
        return false;
    }
    
    /**
     * 测试数组中的所有元素是否都通过了提供的回调函数测试。
     * 
     * @param arr 要测试的数组。
     * @param callback 测试每个元素的函数，接受三个参数：当前元素、索引和数组本身。
     * @return 如果所有元素都通过测试，则返回 true；否则返回 false。
     * 
    * @example
    * <pre>
    * var arr:Array = [2, 4, 6, 8];
    * var allEven:Boolean = ArrayUtil.every(arr, function(element:Object):Boolean {
    *     return element % 2 === 0;
    * });
    * trace(allEven); // 输出: true
    * </pre>
     */
    public static function every(arr:Array, callback:Function):Boolean {
        var len:Number = arr.length;
        for (var i:Number = 0; i < len; i++) {
            if (!callback(arr[i], i, arr)) {
                return false;
            }
        }
        return true;
    }
    
    /**
     * 返回数组中第一个满足提供的回调函数的元素的值。
     * 
     * @param arr 要搜索的数组。
     * @param callback 测试每个元素的函数，接受三个参数：当前元素、索引和数组本身。
     * @return 第一个符合条件的元素值，如果没有找到则返回 null。
     * 
    * @example
    * <pre>
    * var arr:Array = [1, 3, 5, 7, 8];
    * var found:Object = ArrayUtil.find(arr, function(element:Object):Boolean {
    *     return element > 5;
    * });
    * trace(found); // 输出: 7
    * </pre>
     */
    public static function find(arr:Array, callback:Function):Object {
        var len:Number = arr.length;
        for (var i:Number = 0; i < len; i++) {
            if (callback(arr[i], i, arr)) {
                return arr[i];
            }
        }
        return null;
    }
    
    /**
     * 返回数组中第一个满足提供的回调函数的元素的索引。
     * 
     * @param arr 要搜索的数组。
     * @param callback 测试每个元素的函数，接受三个参数：当前元素、索引和数组本身。
     * @return 第一个符合条件的元素索引，如果没有找到则返回 -1。
     * 
    * @example
    * <pre>
    * var arr:Array = [1, 3, 5, 7, 8];
    * var index:Number = ArrayUtil.findIndex(arr, function(element:Object):Boolean {
    *     return element > 5;
    * });
    * trace(index); // 输出: 3
    * </pre>
     */
    public static function findIndex(arr:Array, callback:Function):Number {
        var len:Number = arr.length;
        for (var i:Number = 0; i < len; i++) {
            if (callback(arr[i], i, arr)) {
                return i;
            }
        }
        return -1;
    }
    
    /**
     * 返回数组中最后一个满足提供的回调函数的元素的值。
     * 
     * @param arr 要搜索的数组。
     * @param callback 测试每个元素的函数，接受三个参数：当前元素、索引和数组本身。
     * @return 最后一个符合条件的元素值，如果没有找到则返回 null。
     * 
    * @example
    * <pre>
    * var arr:Array = [1, 3, 5, 7, 8, 9];
    * var found:Object = ArrayUtil.findLast(arr, function(element:Object):Boolean {
    *     return element % 2 === 0;
    * });
    * trace(found); // 输出: 8
    * </pre>
     */
    public static function findLast(arr:Array, callback:Function):Object {
        for (var i:Number = arr.length - 1; i >= 0; i--) {
            if (callback(arr[i], i, arr)) {
                return arr[i];
            }
        }
        return null;
    }
    
    /**
     * 返回数组中最后一个满足提供的回调函数的元素的索引。
     * 
     * @param arr 要搜索的数组。
     * @param callback 测试每个元素的函数，接受三个参数：当前元素、索引和数组本身。
     * @return 最后一个符合条件的元素索引，如果没有找到则返回 -1。
     * 
    * @example
    * <pre>
    * var arr:Array = [1, 3, 5, 7, 8, 9];
    * var index:Number = ArrayUtil.findLastIndex(arr, function(element:Object):Boolean {
    *     return element % 2 === 0;
    * });
    * trace(index); // 输出: 4
    * </pre>
     */
    public static function findLastIndex(arr:Array, callback:Function):Number {
        for (var i:Number = arr.length - 1; i >= 0; i--) {
            if (callback(arr[i], i, arr)) {
                return i;
            }
        }
        return -1;
    }
    
    /**
     * 返回数组中第一个匹配指定元素的索引。
     * 
     * @param arr 要搜索的数组。
     * @param searchElement 要查找的元素。
     * @return 第一个匹配元素的索引，如果未找到则返回 -1。
     * 
    * @example
    * <pre>
    * var arr:Array = [1, 2, 3, 2, 1];
    * var index:Number = ArrayUtil.indexOf(arr, 2);
    * trace(index); // 输出: 1
    * </pre>
     */
    public static function indexOf(arr:Array, searchElement:Object):Number {
        var len:Number = arr.length;
        for (var i:Number = 0; i < len; i++) {
            if (arr[i] === searchElement) {
                return i;
            }
        }
        return -1;
    }
    
    /**
     * 返回数组中最后一个匹配指定元素的索引。
     * 
     * @param arr 要搜索的数组。
     * @param searchElement 要查找的元素。
     * @return 最后一个匹配元素的索引，如果未找到则返回 -1。
     * 
    * @example
    * <pre>
    * var arr:Array = [1, 2, 3, 2, 1];
    * var index:Number = ArrayUtil.lastIndexOf(arr, 2);
    * trace(index); // 输出: 3
    * </pre>
     */
    public static function lastIndexOf(arr:Array, searchElement:Object):Number {
        for (var i:Number = arr.length - 1; i >= 0; i--) {
            if (arr[i] === searchElement) {
                return i;
            }
        }
        return -1;
    }
    
    /**
     * 确定数组是否包含指定的元素。
     * 
     * @param arr 要搜索的数组。
     * @param searchElement 要查找的元素。
     * @return 如果数组包含该元素，则返回 true；否则返回 false。
     * 
    * @example
    * <pre>
    * var arr:Array = [1, 2, 3, NaN];
    * ArrayUtil.includes(arr, 2); // 返回 true
    * ArrayUtil.includes(arr, 4); // 返回 false
    * ArrayUtil.includes(arr, NaN); // 返回 true
    * </pre>
     */
    public static function includes(arr:Array, searchElement:Object):Boolean {
        // 1) 如果是 undefined，单独处理
        if (searchElement === undefined) {
            for (var u:Number = 0; u < arr.length; u++) {
                if (arr[u] === undefined) {
                    return true;
                }
            }
            return false;
        }
        
        // 2) 如果是 NaN，使用 isNaN 检测数组中是否含 NaN
        if (typeof(searchElement) == "number" && isNaN(Number(searchElement))) {
            for (var i:Number = 0; i < arr.length; i++) {
                if (isNaN(arr[i])) {
                    return true;
                }
            }
            return false;
        }
        
        // 3) 否则，使用 indexOf 进行严格比较
        return (ArrayUtil.indexOf(arr, searchElement) !== -1);
    }

    
    /**
     * 使用指定值填充数组中的所有元素或指定范围的元素。
     * 
     * @param arr 要填充的数组。
     * @param value 用于填充的值。
     * @param start 开始填充的索引（默认为 0）。
     * @param end 结束填充的索引（不包括，默认为数组长度）。
     * @return 填充后的数组。
     * 
    * @example
    * <pre>
    * var arr:Array = [1, 2, 3, 4, 5];
    * var filled:Array = ArrayUtil.fill(arr, 0, 1, 3);
    * trace(filled); // 输出: 1,0,0,4,5
    * </pre>
     */
    public static function fill(arr:Array, value:Object, start:Number, end:Number):Array {
        var len:Number = arr.length;
        start = (start == undefined) ? 0 : Math.max(0, start);
        end = (end == undefined) ? len : Math.min(len, end);
        for (var i:Number = start; i < end; i++) {
            arr[i] = value;
        }
        return arr;
    }
    
    /**
     * 将数组重复指定次数后拼接。
     * 
     * @param arr 要重复的数组。
     * @param count 重复的次数。
     * @return 重复后的新数组。
     * 
    * @example
    * <pre>
    * var arr:Array = [1, 2];
    * var repeated:Array = ArrayUtil.repeat(arr, 3);
    * trace(repeated); // 输出: 1,2,1,2,1,2
    * </pre>
     */
    public static function repeat(arr:Array, count:Number):Array {
        var result:Array = [];
        for (var i:Number = 0; i < count; i++) {
            result = result.concat(arr);
        }
        return result;
    }
    
    /**
     * 将嵌套数组“展平”为一个单层数组。
     * 
     * @param arr 要展平的数组。
     * @param depth 展平的深度（默认为 1）。
     * @return 展平后的新数组。
     * 
    * @example
    * <pre>
    * var nested:Array = [1, [2, [3, 4]], 5];
    * var flattened:Array = ArrayUtil.flat(nested, 2);
    * trace(flattened); // 输出: 1,2,3,4,5
    * </pre>
     */
    public static function flat(arr:Array, depth:Number):Array {
        var result:Array = [];
        depth = (depth == undefined) ? 1 : depth;
        
        function flatten(subArr:Array, d:Number):Void {
            for (var i:Number = 0; i < subArr.length; i++) {
                if (ArrayUtil.isArray(subArr[i]) && d > 0) {
                    flatten(subArr[i], d - 1);
                } else {
                    result.push(subArr[i]);
                }
            }
        }
        
        flatten(arr, depth);
        return result;
    }
    
    /**
     * 将 map 与 flat 结合，在映射每个元素后展平。
     * 
     * @param arr 要处理的数组。
     * @param callback 对每个元素执行的函数，应该返回一个数组或单个元素。
     * @return 映射并展平后的新数组。
     * 
    * @example
    * <pre>
    * var arr:Array = [1, 2, 3];
    * var flatMapped:Array = ArrayUtil.flatMap(arr, function(element:Object):Array {
    *     return [element, element * 2];
    * });
    * trace(flatMapped); // 输出: 1,2,2,4,3,6
    * </pre>
     */
    public static function flatMap(arr:Array, callback:Function):Array {
        var result:Array = [];
        var len:Number = arr.length;
        for (var i:Number = 0; i < len; i++) {
            var mapped:Object = callback(arr[i], i, arr);
            if (ArrayUtil.isArray(mapped)) {
                result = result.concat(mapped);
            } else {
                result.push(mapped);
            }
        }
        return result;
    }
    
    /**
     * 将类数组对象或可迭代对象转换为数组。
     * 
     * @param iterable 要转换的类数组对象或可迭代对象。
     * @return 转换后的数组。
     * 
    * @example
    * <pre>
    * var str:String = "hello";
    * var fromArr:Array = ArrayUtil.from(str);
    * trace(fromArr); // 输出: h,e,l,l,o
    * 
    * var obj:Object = {a:1, b:2, c:3};
    * var fromObj:Array = ArrayUtil.from(obj);
    * trace(fromObj); // 输出: 1,2,3
    * </pre>
     */
    public static function from(iterable:Object):Array {
        // 如果传入数组，直接复制一份
        if (ArrayUtil.isArray(iterable)) {
            return iterable.concat();
        }
        
        // 如果传入字符串
        if (typeof(iterable) == "string") {
            var str:String = String(iterable);
            var result:Array = [];
            for (var i:Number = 0; i < str.length; i++) {
                result.push(str.charAt(i));
            }
            return result;
        }
        
        // 如果传入的是对象 (Key-Value)
        var result2:Array = [];
        for (var key in iterable) {
            result2.push(iterable[key]);
        }
        return result2;
    }

    
    /**
     * 创建包含任意元素的新数组。
     * 
     * @return 包含传入参数的数组。
     * 
    * @example
    * <pre>
    * var ofArr:Array = ArrayUtil.of(1, "a", true);
    * trace(ofArr); // 输出: 1,a,true
    * 
    * var emptyOf:Array = ArrayUtil.of();
    * trace(emptyOf); // 输出: 
    * </pre>
     */
    public static function of():Array {
        var result:Array = [];
        for (var i:Number = 0; i < arguments.length; i++) {
            result.push(arguments[i]);
        }
        return result;
    }
    
    /**
     * 将多个数组合并并去重。
     * 
     * @param arrs 要合并的多个数组。
     * @return 合并并去重后的新数组。
     * 
    * @example
    * <pre>
    * var unionArr:Array = ArrayUtil.union([1, 2], [2, 3], [3, 4]);
    * trace(unionArr); // 输出: 1,2,3,4
    * </pre>
     */
    public static function union():Array {
        var result:Array = [];
        for (var i:Number = 0; i < arguments.length; i++) {
            var arr:Array = arguments[i];
            for (var j:Number = 0; j < arr.length; j++) {
                if (ArrayUtil.indexOf(result, arr[j]) === -1) {
                    result.push(arr[j]);
                }
            }
        }
        return result;
    }
    
    /**
     * 返回存在于第一个数组但不存在于第二个数组的元素。
     * 
     * @param arr1 第一个数组。
     * @param arrs 第二个数组。
     * @return 差集后的新数组。
     * 
    * @example
    * <pre>
    * var diffArr:Array = ArrayUtil.difference([1,2,3,4], [2,4]);
    * trace(diffArr); // 输出: 1,3
    * </pre>
     */
    public static function difference(arr1:Array, arrs:Array):Array {
        var result:Array = [];
        for (var i:Number = 0; i < arr1.length; i++) {
            var found:Boolean = false;
            for (var j:Number = 0; j < arrs.length; j++) {
                if (arr1[i] === arrs[j]) {
                    found = true;
                    break;
                }
            }
            if (!found) {
                result.push(arr1[i]);
            }
        }
        return result;
    }
    
    /**
     * 返回数组中唯一的元素，去除重复项。
     * 
     * @param arr 要去重的数组。
     * @return 去重后的新数组。
     * 
    * @example
    * <pre>
    * var arr:Array = [1,2,2,3,4,4,5];
    * var uniqueArr:Array = ArrayUtil.unique(arr);
    * trace(uniqueArr); // 输出: 1,2,3,4,5
    * </pre>
     */
    public static function unique(arr:Array):Array {
        var result:Array = [];
        for (var i:Number = 0; i < arr.length; i++) {
            if (ArrayUtil.indexOf(result, arr[i]) === -1) {
                result.push(arr[i]);
            }
        }
        return result;
    }
    
    /**
     * 创建一个指定长度并用指定值填充的数组。
     * 
     * @param length 数组的长度。
     * @param value 用于填充的值（默认为 undefined）。
     * @return 创建并填充后的新数组。
     * 
    * @example
    * <pre>
    * var createdArr:Array = ArrayUtil.create(5, "x");
    * trace(createdArr); // 输出: x,x,x,x,x
    * </pre>
     */
    public static function create(length:Number, value:Object):Array {
        var result:Array = [];
        for (var i:Number = 0; i < length; i++) {
            result.push(value);
        }
        return result;
    }

    // ===========================
    // ====== 新增扩展方法 ========
    // ===========================
    
    /**
     * 根据回调函数的返回值对数组元素进行分组。
     * 类似于 Lodash 的 groupBy。
     * 
     * @param arr 要处理的数组。
     * @param callback 对每个元素执行的分组函数，返回分组key。
     * @return 一个对象，以分组key为键，分组元素数组为值。
     * 
    * @example
    * <pre>
    * var arr:Array = [6.1, 4.2, 6.3];
    * var grouped:Object = ArrayUtil.groupBy(arr, function(num:Number):String {
    *     return Math.floor(num);
    * });
    * trace(grouped); // 输出: { "4": [4.2], "6": [6.1, 6.3] }
    * </pre>
     */
    public static function groupBy(arr:Array, callback:Function):Object {
        var grouped:Object = {};
        var len:Number = arr.length;
        for (var i:Number = 0; i < len; i++) {
            var element:Object = arr[i];
            var key:String = String(callback(element, i, arr));
            if (grouped[key] == undefined) {
                grouped[key] = [];
            }
            grouped[key].push(element);
        }
        return grouped;
    }
    
    /**
     * 根据回调函数的返回值统计次数。
     * 类似于 Lodash 的 countBy。
     * 
     * @param arr 要处理的数组。
     * @param callback 对每个元素执行的分组函数，返回分组key。
     * @return 一个对象，以分组key为键，出现次数为值。
     * 
    * @example
    * <pre>
    * var arr:Array = [6.1, 4.2, 6.3];
    * var counts:Object = ArrayUtil.countBy(arr, function(num:Number):String {
    *     return Math.floor(num);
    * });
    * trace(counts); // 输出: { "4": 1, "6": 2 }
    * </pre>
     */
    public static function countBy(arr:Array, callback:Function):Object {
        var counts:Object = {};
        var len:Number = arr.length;
        for (var i:Number = 0; i < len; i++) {
            var element:Object = arr[i];
            var key:String = String(callback(element, i, arr));
            if (counts[key] == undefined) {
                counts[key] = 0;
            }
            counts[key]++;
        }
        return counts;
    }
    
    /**
     * 将数组按照回调函数切分为两个部分：符合条件的放在第一个数组，不符合条件的放在第二个数组。
     * 类似于 Lodash 的 partition。
     * 
     * @param arr 要拆分的数组。
     * @param callback 判断条件函数，返回 true 或 false。
     * @return [ 符合条件的数组, 不符合条件的数组 ]。
     * 
    * @example
    * <pre>
    * var arr:Array = [1,2,3,4,5,6];
    * var partitioned:Array = ArrayUtil.partition(arr, function(num:Number):Boolean {
    *     return num % 2 === 0;
    * });
    * trace(partitioned); // 输出: [ [2,4,6], [1,3,5] ]
    * </pre>
     */
    public static function partition(arr:Array, callback:Function):Array {
        var pass:Array = [];
        var fail:Array = [];
        var len:Number = arr.length;
        for (var i:Number = 0; i < len; i++) {
            if (callback(arr[i], i, arr)) {
                pass.push(arr[i]);
            } else {
                fail.push(arr[i]);
            }
        }
        return [pass, fail];
    }
    
    /**
     * 将数组分块，每个分块的大小为指定的 size。
     * 类似于 Lodash 的 chunk。
     * 
     * @param arr 要分块的数组。
     * @param size 每个分块的大小。
     * @return 分块后的二维数组。
     * 
    * @example
    * <pre>
    * var arr:Array = [1,2,3,4,5,6,7];
    * var chunked:Array = ArrayUtil.chunk(arr, 3);
    * trace(chunked); // 输出: [ [1,2,3], [4,5,6], [7] ]
    * </pre>
     */
    public static function chunk(arr:Array, size:Number):Array {
        var len:Number = arr.length;
        var result:Array = [];
        var index:Number = 0;

        if (size < 1) {
            // size < 1 不合法，返回空数组
            return [];
        }

        while (index < len) {
            result.push(arr.slice(index, index + size));
            index += size;
        }
        return result;
    }
    
    /**
     * 将多个数组对应索引的元素组合在一起。
     * 类似于 Lodash 的 zip。
     * 
     * @param arrs 多个数组。
     * @return 组合后的二维数组。
     * 
    * @example
    * <pre>
    * var zipped:Array = ArrayUtil.zip([1,2], ["a","b"], [true, false]);
    * trace(zipped); // 输出: [ [1,"a",true], [2,"b",false] ]
    * </pre>
     */
    public static function zip():Array {
        var arrays:Array = arguments;
        var length:Number = 0;

        // 找出最大的数组长度
        for (var i:Number = 0; i < arrays.length; i++) {
            if (!ArrayUtil.isArray(arrays[i])) {
                continue;
            }
            if (arrays[i].length > length) {
                length = arrays[i].length;
            }
        }

        var result:Array = [];
        for (var idx:Number = 0; idx < length; idx++) {
            var group:Array = [];
            for (var j:Number = 0; j < arrays.length; j++) {
                var currentArray:Array = arrays[j];
                group.push((idx < currentArray.length) ? currentArray[idx] : undefined);
            }
            result.push(group);
        }
        return result;
    }
    
    /**
     * 将由 zip 创建的分组数组拆分成多个数组。
     * 类似于 Lodash 的 unzip。
     * 
     * @param arr 要拆分的分组数组。
     * @return 拆分后的多个数组。
     * 
    * @example
    * <pre>
    * var grouped:Array = [ [1,"a",true], [2,"b",false] ];
    * var unzipped:Array = ArrayUtil.unzip(grouped);
    * trace(unzipped); // 输出: [ [1,2], ["a","b"], [true, false] ]
    * </pre>
     */
    public static function unzip(arr:Array):Array {
        // 假设 arr = [[val11, val12], [val21, val22], ...]
        var result:Array = [];
        var maxLen:Number = 0;
        
        for (var i:Number = 0; i < arr.length; i++) {
            var group:Array = arr[i];
            if (group.length > maxLen) {
                maxLen = group.length;
            }
        }

        for (var idx:Number = 0; idx < maxLen; idx++) {
            var sub:Array = [];
            for (var j:Number = 0; j < arr.length; j++) {
                var groupArr:Array = arr[j];
                sub.push((idx < groupArr.length) ? groupArr[idx] : undefined);
            }
            result.push(sub);
        }
        return result;
    }
    
    /**
     * 返回多个数组的交集元素。
     * 
     * @param arrs 多个数组。
     * @return 交集元素数组。
     * 
    * @example
    * <pre>
    * var inter:Array = ArrayUtil.intersection([1,2,3], [2,3,4], [3,4,5]);
    * trace(inter); // 输出: 3
    * </pre>
     */
    public static function intersection():Array {
        var args:Array = arguments;
        if (args.length == 0) {
            return [];
        }
        
        var result:Array = args[0].concat(); // 复制第一个数组
        for (var i:Number = 1; i < args.length; i++) {
            var current:Array = args[i];
            // 在 result 中只保留 current 中也存在的元素
            var tmp:Array = [];
            for (var j:Number = 0; j < result.length; j++) {
                if (ArrayUtil.indexOf(current, result[j]) !== -1) {
                    tmp.push(result[j]);
                }
            }
            result = tmp;
        }
        return ArrayUtil.unique(result);
    }
    
    /**
     * 返回多个数组的对称差集 (xor)。
     * 即仅在其中一个数组中出现，而不在多个数组中重复出现的元素。
     * 
     * @param arrs 多个数组。
     * @return 对称差集数组。
     * 
    * @example
    * <pre>
    * var xorRes:Array = ArrayUtil.xor([1,2], [2,3], [3,4]);
    * trace(xorRes); // 输出: [1,4]
    * </pre>
     */
    public static function xor():Array {
        var args:Array = arguments;
        var map:Object = {};
        var i:Number, j:Number;
        
        for (i = 0; i < args.length; i++) {
            // 若要与测试保持一致，可对每个数组先去重
            var arr:Array = ArrayUtil.unique(args[i]);
            for (j = 0; j < arr.length; j++) {
                var valStr:String = String(arr[j]);
                if (map[valStr] == undefined) {
                    map[valStr] = { value: arr[j], count: 0 };
                }
                map[valStr].count++;
            }
        }
        
        var result:Array = [];
        for (var key in map) {
            if (map[key].count == 1) {
                result.push(map[key].value);
            }
        }
        
        // 排序以使输出顺序稳定
        // 注：如果元素都是数字或可比较值，使用 sort() 即可；若包含对象，需自定义比较器
        result.sort();
        return result;
    }

    
    /**
     * 将数组随机打乱 (Fisher-Yates Shuffle)。
     * 
     * @param arr 要打乱的数组。
     * @return 打乱后的数组（原数组也会被修改，若不希望修改原数组可先复制一份）。
     * 
    * @example
    * <pre>
    * var arr:Array = [1,2,3,4,5];
    * var shuffled:Array = ArrayUtil.shuffle(arr.concat()); // 复制数组后打乱
    * trace(shuffled); // 输出: 数组元素的随机顺序
    * </pre>
     */
    public static function shuffle(arr:Array):Array {
        var len:Number = arr.length;
        for (var i:Number = len - 1; i > 0; i--) {
            var randIndex:Number = Math.floor(Math.random() * (i + 1));
            // 交换元素
            var temp:Object = arr[i];
            arr[i] = arr[randIndex];
            arr[randIndex] = temp;
        }
        return arr;
    }
    
    /**
     * 过滤掉数组中 falsy 的值 (undefined, null, 0, "", false, NaN)。
     * 类似于 Lodash 的 compact。
     * 
     * @param arr 要过滤的数组。
     * @return 过滤后的新数组。
     * 
    * @example
    * <pre>
    * var arr:Array = [0, 1, false, 2, "", 3, null, 4, undefined, NaN];
    * var compacted:Array = ArrayUtil.compact(arr);
    * trace(compacted); // 输出: 1,2,3,4
    * </pre>
     */
    public static function compact(arr:Array):Array {
        var result:Array = [];
        for (var i:Number = 0; i < arr.length; i++) {
            if (arr[i]) { // 这里只要值不为 falsy，即可保留
                result.push(arr[i]);
            }
        }
        return result;
    }
    
    /**
     * 返回一个包含从 start 到 end 的连续整数数组。
     * 相当于 Python 的 range 或 Lodash 的 range。
     * 
     * @param start 起始值（包含）。
     * @param end 结束值（不包含）。
     * @param step 步进值（默认为 1）。
     * @return 生成的数组。
     * 
    * @example
    * <pre>
    * var rangeArr:Array = ArrayUtil.range(0, 5);
    * trace(rangeArr); // 输出: 0,1,2,3,4
    * 
    * var rangeArr2:Array = ArrayUtil.range(5, 0, -1);
    * trace(rangeArr2); // 输出: 5,4,3,2,1
    * </pre>
     */
    public static function range(start:Number, end:Number, step:Number):Array {
        var result:Array = [];
        if (step == undefined) step = 1;
        if (step == 0) {
            return []; // 避免无限循环
        }

        if (start < end) {
            for (var i:Number = start; i < end; i += step) {
                result.push(i);
            }
        } else {
            // 反向生成
            for (var j:Number = start; j > end; j += step) {
                result.push(j);
            }
        }
        return result;
    }
    
    /**
     * 随机从数组中返回一个或多个元素。
     * 
     * @param arr 要采样的数组。
     * @param n 采样个数，默认为 1。
     * @return 采样得到的元素（当 n=1 时，直接返回元素；n>1 时，返回数组）。
     * 
    * @example
    * <pre>
    * var arr:Array = [1,2,3,4,5];
    * var singleSample:Object = ArrayUtil.sample(arr);
    * trace(singleSample); // 输出: 随机一个元素，例如: 3
    * 
    * var multiSample:Array = ArrayUtil.sample(arr, 3);
    * trace(multiSample); // 输出: 随机三个元素，例如: 2,4,5
    * </pre>
     */
    public static function sample(arr:Array, n:Number):Object {
        if (n == undefined || n == 1) {
            // 随机返回一个元素
            var index:Number = Math.floor(Math.random() * arr.length);
            return arr[index];
        } else {
            // 返回多个元素
            var copy:Array = arr.concat();
            ArrayUtil.shuffle(copy);
            return copy.slice(0, n);
        }
    }
    
    /**
     * 合并多个数组或对象中的值到目标数组中（浅合并）。
     * 用于简化多数组或多对象合并场景。
     * 
     * @param target 目标数组。
     * @param sources 要合并的多个数组或对象。
     * @return 合并后的目标数组。
     * 
    * @example
    * <pre>
    * var target:Array = [1, 2];
    * var merged:Array = ArrayUtil.merge(target, [3,4], {a:5, b:6});
    * trace(merged); // 输出: 1,2,3,4,5,6
    * </pre>
     */
    public static function merge(target:Array):Array {
        for (var i:Number = 1; i < arguments.length; i++) {
            var source:Object = arguments[i];
            if (ArrayUtil.isArray(source)) {
                // 直接拼接到 target
                target = target.concat(source);
            } else {
                // 假设 source 是对象
                for (var key in source) {
                    target.push(source[key]);
                }
            }
        }
        return target;
    }
}
