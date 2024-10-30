// 文件: org/flashNight/gesh/array/ArrayUtil.as
class org.flashNight.gesh.array.ArrayUtil {
    
    /**
     * 对数组的每个元素执行一次提供的函数。
     * @param arr 要遍历的数组。
     * @param callback 对每个元素执行的函数。
     */
    public static function forEach(arr:Array, callback:Function):Void {
        var len:Number = arr.length;
        for (var i:Number = len - 1; i >= 0; i--) {
            callback(arr[i], i, arr);
        }
    }

    /**
     * 创建一个新数组，其中包含调用提供的函数后返回的每个元素的结果。
     * 优化：使用 push 代替 unshift，并在遍历结束后反转数组，以提高性能。
     * @param arr 要映射的数组。
     * @param callback 对每个元素执行的函数。
     * @return 一个新数组，每个元素是回调函数的结果。
     */
    public static function map(arr:Array, callback:Function):Array {
        var result:Array = [];
        var len:Number = arr.length;
        for (var i:Number = len - 1; i >= 0; i--) {
            result.push(callback(arr[i], i, arr));
        }
        result.reverse(); // 反转数组以保持原有顺序
        return result;
    }

    /**
     * 创建一个新数组，其中包含所有通过提供的函数测试的元素。
     * 优化：使用 push 代替 unshift，并在遍历结束后反转数组，以提高性能。
     * @param arr 要过滤的数组。
     * @param callback 测试每个元素的函数。
     * @return 一个新数组，包含通过测试的元素。
     */
    public static function filter(arr:Array, callback:Function):Array {
        var result:Array = [];
        var len:Number = arr.length;
        for (var i:Number = len - 1; i >= 0; i--) {
            if (callback(arr[i], i, arr)) {
                result.push(arr[i]);
            }
        }
        result.reverse(); // 反转数组以保持原有顺序
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
        // 检查是否提供了 initialValue 参数
        var hasInitialValue:Boolean = (initialValue != undefined);
        
        // 如果有初始值，则 accumulator 是 initialValue，否则是数组的最后一个元素
        var accumulator:Object = hasInitialValue ? initialValue : arr[arr.length - 1];
        
        // 如果有初始值，从最后一个元素开始迭代；否则，从倒数第二个元素开始
        var startIndex:Number = hasInitialValue ? arr.length - 1 : arr.length - 2;
        
        // 逆向遍历数组，并应用回调函数
        for (var i:Number = startIndex; i >= 0; i--) {
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
        for (var i:Number = len - 1; i >= 0; i--) {
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
        for (var i:Number = len - 1; i >= 0; i--) {
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
        for (var i:Number = len - 1; i >= 0; i--) {
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
        for (var i:Number = len - 1; i >= 0; i--) {
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
        var len:Number = arr.length;
        for (var i:Number = len - 1; i >= 0; i--) {
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
        return ArrayUtil.indexOf(arr, searchElement) !== -1;
    }
}
