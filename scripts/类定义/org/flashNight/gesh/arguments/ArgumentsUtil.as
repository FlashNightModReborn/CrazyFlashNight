

class org.flashNight.gesh.arguments.ArgumentsUtil {

    /**
     * 获取 arguments 的长度。
     * @param args arguments对象
     * @return Number 返回 arguments 的长度
     */
    public static function length(args:Object):Number {
        // arguments 对象有 length 属性
        return args.length;
    }

    /**
     * 将 arguments 对象从指定的起始索引转换为一个数组。
     * @param args arguments 对象。
     * @param startIndex 从该索引开始提取参数（默认0）。
     * @return Array 提取的数组。
     */
    public static function toArray(args:Object, startIndex:Number):Array {
        var arr:Array = [];
        var len:Number = args.length;
        if (startIndex == null || startIndex < 0) {
            startIndex = 0;
        } else if (startIndex > len) {
            startIndex = len;
        }
        // 从 startIndex 开始拷贝 
        var j:Number = 0;
        for (var i:Number = startIndex; i < len; i++) {
            arr[j++] = args[i];
        }
        return arr;
    }

    /**
     * 从 arguments 对象中提取一部分为数组，类似 slice 功能。
     * @param args arguments 对象。
     * @param startIndex 起始索引（包含）。
     * @param endIndex 结束索引（不包含）。若未指定，则到 args 的末尾。
     * @return Array 包含从 startIndex 到 endIndex-1 的元素。
     */
    public static function slice(args:Object, startIndex:Number, endIndex:Number):Array {
        var len:Number = args.length;
        if (startIndex == null) {
            startIndex = 0;
        } else if (startIndex < 0) {
            startIndex = Math.max(0, len + startIndex);
        } else if (startIndex > len) {
            startIndex = len;
        }

        if (endIndex == null) {
            endIndex = len;
        } else if (endIndex < 0) {
            endIndex = Math.max(0, len + endIndex);
        } else if (endIndex > len) {
            endIndex = len;
        }

        var arr:Array = [];
        var j:Number = 0;
        for (var i:Number = startIndex; i < endIndex; i++) {
            arr[j++] = args[i];
        }
        return arr;
    }

    /**
     * 对 arguments 的每个元素从 startIndex 开始执行一次提供的函数。
     * @param args arguments 对象。
     * @param callback 对每个元素执行的函数，函数签名为 callback(element, index, argumentsObject)。
     * @param startIndex 起始索引。若未提供则为0。
     */
    public static function forEach(args:Object, callback:Function, startIndex:Number):Void {
        var len:Number = args.length;
        if (startIndex == null || startIndex < 0) {
            startIndex = 0;
        } else if (startIndex > len) {
            startIndex = len;
        }

        for (var i:Number = startIndex; i < len; i++) {
            callback(args[i], i, args);
        }
    }

    /**
     * 创建一个新数组，其中包含调用 callback 后返回的每个元素的结果。
     * 类似于 Array.map，但针对 arguments 对象。
     * @param args arguments 对象。
     * @param callback 对每个元素执行的函数，签名为 callback(element, index, argumentsObject)。
     * @param startIndex 起始索引。若未提供则为0。
     * @return Array 一个新数组，每个元素是 callback 的结果。
     */
    public static function map(args:Object, callback:Function, startIndex:Number):Array {
        var len:Number = args.length;
        if (startIndex == null || startIndex < 0) {
            startIndex = 0;
        } else if (startIndex > len) {
            startIndex = len;
        }

        var result:Array = new Array(len - startIndex);
        var j:Number = 0;
        for (var i:Number = startIndex; i < len; i++) {
            result[j++] = callback(args[i], i, args);
        }
        return result;
    }

    /**
     * 对 arguments 从 startIndex 开始执行回调函数，生成累积值。
     * 类似 reduce 功能的简化实现。
     * @param args arguments 对象。
     * @param callback 累加函数，签名为 callback(accumulator, currentElement, index, argumentsObject)。
     * @param initialValue 初始值，可选。
     * @param startIndex 起始索引。若未提供则为0。
     * @return 累加后的结果值。
     */
    public static function reduce(args:Object, callback:Function, initialValue:Object, startIndex:Number):Object {
        var len:Number = args.length;
        if (startIndex == null || startIndex < 0) {
            startIndex = 0;
        } else if (startIndex > len) {
            startIndex = len;
        }

        var i:Number = startIndex;
        var accumulator:Object;
        var hasInitial:Boolean = (initialValue != undefined);
        if (hasInitial) {
            accumulator = initialValue;
        } else {
            if (startIndex >= len) {
                // 无元素可用于累加，且没有初始值时，应抛出错误或返回 undefined
                // 这里选择抛出错误，与原生 reduce 一致
                throw new Error("Reduce of empty arguments with no initial value");
            }
            accumulator = args[i++];
        }

        for (; i < len; i++) {
            accumulator = callback(accumulator, args[i], i, args);
        }
        return accumulator;
    }
}
