// 文件: org/flashNight/gesh/array/ArrayUtil.as
class org.flashNight.gesh.array.ArrayUtil {
    
    /**
     * 检查对象是否为数组。
     * @param obj 要检查的对象。
     * @return 如果对象是数组，则返回 true，否则返回 false。
     */
    public static function isArray(obj:Object):Boolean {
        return (obj instanceof Array);
    }

    /**
     * 对数组的每个元素执行一次提供的函数。
     * @param arr 要遍历的数组。
     * @param callback 对每个元素执行的函数。
     */
    public static function forEach(arr:Array, callback:Function):Void {
        var len:Number = arr.length;
        for (var i:Number = 0; i < len; i++) {
            callback(arr[i], i, arr);
        }
    }

    /**
     * 创建一个新数组，其中包含调用提供的函数后返回的每个元素的结果。
     * @param arr 要映射的数组。
     * @param callback 对每个元素执行的函数。
     * @return 一个新数组，每个元素是回调函数的结果。
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
     * 创建一个新数组，其中包含所有通过提供的函数测试的元素。
     * @param arr 要过滤的数组。
     * @param callback 测试每个元素的函数。
     * @return 一个新数组，包含通过测试的元素。
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
     * 使用提供的函数对数组的累加器和每个元素执行操作，以将数组简化为单个值。
     * @param arr 要简化的数组。
     * @param callback 对每个元素执行的函数。
     * @param initialValue 用于开始累加的初始值。
     * @return 累加后的结果。
     */
    public static function reduce(arr:Array, callback:Function, initialValue:Object):Object {
        var len:Number = arr.length;
        var accumulator:Object;
        var startIndex:Number;

        if (arguments.length >= 3) {
            accumulator = initialValue;
            startIndex = 0;
        } else {
            if (len === 0) {
                throw new Error("Reduce of empty array with no initial value");
            }
            accumulator = arr[0];
            startIndex = 1;
        }

        for (var i:Number = startIndex; i < len; i++) {
            accumulator = callback(accumulator, arr[i], i, arr);
        }

        return accumulator;
    }

    /**
     * 测试数组中是否至少有一个元素通过了提供的函数测试。
     * @param arr 要测试的数组。
     * @param callback 测试每个元素的函数。
     * @return 如果任何元素通过测试，则返回 true，否则返回 false。
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
     * 测试数组中的所有元素是否都通过了提供的函数测试。
     * @param arr 要测试的数组。
     * @param callback 测试每个元素的函数。
     * @return 如果所有元素都通过测试，则返回 true，否则返回 false。
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
     * 返回数组中第一个满足提供的测试函数的元素的值。
     * @param arr 要搜索的数组。
     * @param callback 测试每个元素的函数。
     * @return 第一个符合条件的元素值，如果没有找到则返回 null。
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
     * 返回数组中第一个满足提供的测试函数的元素的索引。
     * @param arr 要搜索的数组。
     * @param callback 测试每个元素的函数。
     * @return 第一个符合条件的元素索引，如果没有找到则返回 -1。
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
     * 返回数组中最后一个满足提供的测试函数的元素的值。
     * @param arr 要搜索的数组。
     * @param callback 测试每个元素的函数。
     * @return 最后一个符合条件的元素值，如果没有找到则返回 null。
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
     * 返回数组中最后一个满足提供的测试函数的元素的索引。
     * @param arr 要搜索的数组。
     * @param callback 测试每个元素的函数。
     * @return 最后一个符合条件的元素索引，如果没有找到则返回 -1。
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
     * @param arr 要搜索的数组。
     * @param searchElement 要查找的元素。
     * @return 第一个匹配元素的索引，如果未找到则返回 -1。
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
     * @param arr 要搜索的数组。
     * @param searchElement 要查找的元素。
     * @return 最后一个匹配元素的索引，如果未找到则返回 -1。
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
     * @param arr 要搜索的数组。
     * @param searchElement 要查找的元素。
     * @return 如果数组包含该元素，则返回 true，否则返回 false。
     */
    public static function includes(arr:Array, searchElement:Object):Boolean {
        if (isNaN(searchElement)) {
            for (var i:Number = 0; i < arr.length; i++) {
                if (isNaN(arr[i])) {
                    return true;
                }
            }
            return false;
        } else {
            return (ArrayUtil.indexOf(arr, searchElement) !== -1);
        }
    }

    /**
     * 使用指定值填充数组中的所有元素或指定范围的元素。
     * @param arr 要填充的数组。
     * @param value 用于填充的值。
     * @param start 开始填充的索引（默认为 0）。
     * @param end 结束填充的索引（不包括，默认为数组长度）。
     * @return 填充后的数组。
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
     * @param arr 要重复的数组。
     * @param count 重复的次数。
     * @return 重复后的新数组。
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
     * @param arr 要展平的数组。
     * @param depth 展平的深度（默认为 1）。
     * @return 展平后的新数组。
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
     * @param arr 要处理的数组。
     * @param callback 对每个元素执行的函数，应该返回一个数组。
     * @return 映射并展平后的新数组。
     */
    public static function flatMap(arr:Array, callback:Function):Array {
        var result:Array = [];
        var len:Number = arr.length;
        for (var i:Number = 0; i < len; i++) {
            var mapped:Array = callback(arr[i], i, arr);
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
     * @param iterable 要转换的类数组对象或可迭代对象。
     * @return 转换后的数组。
     */
    public static function from(iterable:Object):Array {
        var result:Array = [];
        if (ArrayUtil.isArray(iterable)) {
            return iterable.concat();
        } else {
            for (var key in iterable) {
                result.push(iterable[key]);
            }
        }
        return result;
    }

    /**
     * 创建包含任意元素的新数组。
     * @return 包含传入参数的数组。
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
     * @param arrs 要合并的多个数组。
     * @return 合并并去重后的新数组。
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
     * 返回存在于第一个数组但不存在于其他数组的元素。
     * @param arr1 第一个数组。
     * @param arrs 其他数组。
     * @return 差集后的新数组。
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
     * 返回数组中唯一的元素。
     * @param arr 要去重的数组。
     * @return 去重后的新数组。
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
     * @param length 数组的长度。
     * @param value 用于填充的值（默认为 undefined）。
     * @return 创建并填充后的新数组。
     */
    public static function create(length:Number, value:Object):Array {
        var result:Array = [];
        for (var i:Number = 0; i < length; i++) {
            result.push(value);
        }
        return result;
    }
}
