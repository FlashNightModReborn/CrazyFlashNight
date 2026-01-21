/**
 * ArgumentsUtil 工具类提供对 arguments 对象的各种操作。
 *
 * 版本历史:
 * v2.1 (2026-01) - 三方交叉审查修复
 *   [DOC] 添加 sliceArgs 方法的行为警告文档
 *
 * 重要警告 - sliceArgs 方法:
 *   sliceArgs 返回的数组是【逆序】的（从右到左提取）。
 *   这是为了与 Function.apply() 配合使用时的性能优化设计。
 *   如需正序结果，请使用 toArray() 或 slice() 方法代替。
 *
 *   技术细节：内联展开分支 (len 1-10) 返回逆序，但循环分支 (len > 10) 返回正序。
 *   这是历史遗留的不一致行为，为保持向后兼容性而保留。
 */
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
     * sliceArgs 方法用于从给定的函数参数对象中提取一部分参数，并返回一个新的数组。
     *
     * ⚠️ 警告：此方法返回【逆序】数组！
     * 内联展开分支 (len 1-10) 从右向左提取，返回逆序结果。
     * 例如：args=[a,b,c,d], startIndex=1 → 返回 [d,c,b] 而非 [b,c,d]
     *
     * 注意：循环分支 (len > 10) 由于实现差异，实际返回正序。
     * 这是历史遗留的不一致行为。如需可靠的正序结果，请使用 toArray() 或 slice()。
     *
     * @param args FunctionArguments - 函数的 arguments 对象，包含所有传递的参数。
     * @param startIndex Number - 要提取参数的起始索引（从 0 开始计数）。
     * @return Array - 包含从起始索引开始的参数的新数组（逆序，见警告）。
     */
    public static function sliceArgs(args:FunctionArguments, startIndex:Number):Array {
        var i:Number = args.length; // 从参数列表的末尾开始向前操作
        var len:Number = i - startIndex; // 需要提取的参数个数,外界需要做好数值控制以防len小于等于0

        // 针对参数数量为 1-10 的情况展开逻辑
        // 优化：通过手动展开逻辑避免循环开销
        // 注意：使用 --i 操作符，自减操作会先递减索引再使用，以从右到左提取参数
        if (len == 1) return [args[--i]]; // 提取 1 个参数
        if (len == 2) return [args[--i], args[--i]]; // 提取 2 个参数
        if (len == 3) return [args[--i], args[--i], args[--i]]; // 提取 3 个参数
        if (len == 4) return [args[--i], args[--i], args[--i], args[--i]]; // 提取 4 个参数
        if (len == 5) return [args[--i], args[--i], args[--i], args[--i], args[--i]]; // 提取 5 个参数
        if (len == 6) return [args[--i], args[--i], args[--i], args[--i], args[--i], args[--i]]; // 提取 6 个参数
        if (len == 7) return [args[--i], args[--i], args[--i], args[--i], args[--i], args[--i], args[--i]]; // 提取 7 个参数
        if (len == 8) return [args[--i], args[--i], args[--i], args[--i], args[--i], args[--i], args[--i], args[--i]]; // 提取 8 个参数
        if (len == 9) return [args[--i], args[--i], args[--i], args[--i], args[--i], args[--i], args[--i], args[--i], args[--i]]; // 提取 9 个参数
        if (len == 10) return [args[--i], args[--i], args[--i], args[--i], args[--i], args[--i], args[--i], args[--i], args[--i], args[--i]]; // 提取 10 个参数

        // 对于参数数量大于 10 的情况，使用通用循环逻辑
        // 优化：从右到左（数组末尾到起始索引）依次提取参数，填充到新数组中
        var newArgs:Array = new Array(len); // 创建用于存储结果的数组，长度为 len
        for (var j:Number = len - 1; j >= 0; j--) {
            newArgs[j] = args[--i]; // 自减索引，依次填充结果数组
        }

        // 返回提取的参数数组
        return newArgs;
    }


    /**
     * 将固定参数与动态参数组合成一个数组。
     * 
     * @param fixedArgs Array - 固定参数数组
     * @param dynamicArgs Object - 动态参数对象 (通常是 arguments)
     * @param startIndex Number - 动态参数起始索引 (默认从0开始)
     * @return Array 返回组合后的参数数组
     */
    public static function combineArgs(fixedArgs:Array, dynamicArgs:Object, startIndex:Number):Array {
        var len:Number = dynamicArgs.length - startIndex; // 动态参数长度
        if (len <= 0) {
            return fixedArgs.concat(); // 无动态参数，返回固定参数的副本
        }

        // 针对动态参数数量为 1-10 的情况展开逻辑
        if (len == 1) return fixedArgs.concat([dynamicArgs[startIndex]]);
        if (len == 2) return fixedArgs.concat([dynamicArgs[startIndex], dynamicArgs[startIndex + 1]]);
        if (len == 3) return fixedArgs.concat([dynamicArgs[startIndex], dynamicArgs[startIndex + 1], dynamicArgs[startIndex + 2]]);
        if (len == 4) return fixedArgs.concat([dynamicArgs[startIndex], dynamicArgs[startIndex + 1], dynamicArgs[startIndex + 2], dynamicArgs[startIndex + 3]]);
        if (len == 5) return fixedArgs.concat([dynamicArgs[startIndex], dynamicArgs[startIndex + 1], dynamicArgs[startIndex + 2], dynamicArgs[startIndex + 3], dynamicArgs[startIndex + 4]]);
        if (len == 6) return fixedArgs.concat([dynamicArgs[startIndex], dynamicArgs[startIndex + 1], dynamicArgs[startIndex + 2], dynamicArgs[startIndex + 3], dynamicArgs[startIndex + 4], dynamicArgs[startIndex + 5]]);
        if (len == 7) return fixedArgs.concat([dynamicArgs[startIndex], dynamicArgs[startIndex + 1], dynamicArgs[startIndex + 2], dynamicArgs[startIndex + 3], dynamicArgs[startIndex + 4], dynamicArgs[startIndex + 5], dynamicArgs[startIndex + 6]]);
        if (len == 8) return fixedArgs.concat([dynamicArgs[startIndex], dynamicArgs[startIndex + 1], dynamicArgs[startIndex + 2], dynamicArgs[startIndex + 3], dynamicArgs[startIndex + 4], dynamicArgs[startIndex + 5], dynamicArgs[startIndex + 6], dynamicArgs[startIndex + 7]]);
        if (len == 9) return fixedArgs.concat([dynamicArgs[startIndex], dynamicArgs[startIndex + 1], dynamicArgs[startIndex + 2], dynamicArgs[startIndex + 3], dynamicArgs[startIndex + 4], dynamicArgs[startIndex + 5], dynamicArgs[startIndex + 6], dynamicArgs[startIndex + 7], dynamicArgs[startIndex + 8]]);
        if (len == 10) return fixedArgs.concat([dynamicArgs[startIndex], dynamicArgs[startIndex + 1], dynamicArgs[startIndex + 2], dynamicArgs[startIndex + 3], dynamicArgs[startIndex + 4], dynamicArgs[startIndex + 5], dynamicArgs[startIndex + 6], dynamicArgs[startIndex + 7], dynamicArgs[startIndex + 8], dynamicArgs[startIndex + 9]]);

        // 对于参数数量大于 10 的情况，使用通用循环逻辑
        var result:Array = fixedArgs.concat(); // 复制固定参数到结果数组
        for (var k:Number = startIndex; k < dynamicArgs.length; k++) {
            result.push(dynamicArgs[k]);
        }
        return result;
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
