class org.flashNight.gesh.string.RLE {

    /**
     * 压缩字符串使用扩展的 Run-Length Encoding (RLE)
     * 支持多字节字符和序列的压缩
     * 
     * @param input 要压缩的字符串
     * @param maxSequenceLength 最大序列长度，用于控制压缩的最大字符组长度
     * @return 压缩后的字符串
     */
    public static function compress(input:String, maxSequenceLength:Number):String {
        if (input == null || input.length == 0) {
            return ""; // 如果输入为空，直接返回空字符串
        }

        if (maxSequenceLength == null || maxSequenceLength <= 1) {
            maxSequenceLength = 10; // 如果没有提供或提供无效的最大序列长度，默认为 10
        }

        var compressedParts:Array = []; // 用于存储压缩后的字符串片段，提高性能
        var i:Number = 0;
        var inputLength:Number = input.length;

        // 遍历整个字符串，找到重复序列并进行压缩
        while (i < inputLength) {
            var maxMatchLength:Number = 1; // 记录当前最大匹配的字符数
            var maxSequenceObj:Object = getSequence(input, i, 1);
            var maxSequence:String = maxSequenceObj.sequence; // 获取当前序列（支持多字节字符）
            var maxSequenceCodeUnits:Number = maxSequenceObj.codeUnits; // 当前序列的代码单元长度
            var maxCount:Number = 1; // 当前序列的重复次数

            // 尝试不同的序列长度，寻找重复序列
            for (var seqLen:Number = 1; seqLen <= maxSequenceLength; seqLen++) {
                var sequenceObj:Object = getSequence(input, i, seqLen);
                if (sequenceObj == null) {
                    break; // 无法获取到有效长度的序列，跳出
                }
                var sequence:String = sequenceObj.sequence;
                var sequenceCodeUnits:Number = sequenceObj.codeUnits;
                var count:Number = 1;
                var j:Number = i + sequenceCodeUnits;

                // 计算当前序列重复的次数
                while (j + sequenceCodeUnits <= inputLength) {
                    var nextSequenceObj:Object = getSequence(input, j, seqLen);
                    if (nextSequenceObj == null || nextSequenceObj.sequence != sequence) {
                        break; // 序列不再重复，退出循环
                    }
                    count++;
                    j += sequenceCodeUnits;
                }

                // 更新最大匹配序列
                if (count > maxCount || (count == maxCount && seqLen > maxMatchLength)) {
                    maxMatchLength = seqLen;
                    maxSequence = sequence;
                    maxSequenceCodeUnits = sequenceCodeUnits;
                    maxCount = count;
                }
            }

            // 转义特殊字符
            var escapedSequence:String = escapeSpecialChars(maxSequence);
            // 添加压缩后的部分（例如 "a#3;"）
            compressedParts.push(escapedSequence + "#" + maxCount + ";");
            // 更新索引，跳过已经压缩的字符
            i += maxSequenceCodeUnits * maxCount;
        }

        // 将压缩后的字符串片段连接成最终的压缩结果
        var compressed:String = compressedParts.join("");
        trace("RLE 压缩完成。原长度: " + input.length + ", 压缩后长度: " + compressed.length);
        return compressed;
    }

    /**
     * 获取指定长度的序列，支持多字节字符。
     * 
     * @param input 输入的字符串
     * @param index 当前处理的起始位置
     * @param length 要获取的字符序列长度
     * @return 包含序列和代码单元长度的对象，如果长度不够则返回 null
     */
    private static function getSequence(input:String, index:Number, length:Number):Object {
        var sequence:String = ""; // 用于存储当前序列
        var codeUnits:Number = 0; // 记录序列的代码单元长度
        var i:Number = index;
        var count:Number = 0;

        // 循环获取指定长度的字符，支持处理多字节字符
        while (count < length && i < input.length) {
            var char:String = getNextChar(input, i);
            sequence += char;
            codeUnits += char.length; // 累加字符的代码单元长度
            i += char.length;
            count++;
        }

        if (count < length) {
            return null; // 如果无法获取到指定长度的序列，则返回 null
        }

        return {sequence: sequence, codeUnits: codeUnits};
    }

    /**
     * 转义特殊字符（如 '#'、';' 和 '\'）
     * 
     * @param str 要转义的字符串
     * @return 转义后的字符串
     */
    private static function escapeSpecialChars(str:String):String {
        var escaped:String = "";
        for (var i:Number = 0; i < str.length; i++) {
            var char:String = str.charAt(i);
            if (char == "#" || char == ";" || char == "\\") {
                escaped += "\\" + char; // 为特殊字符添加反斜杠进行转义
            } else {
                escaped += char;
            }
        }
        return escaped;
    }

    /**
     * 反转义特殊字符
     * 
     * @param str 要反转义的字符串
     * @return 反转义后的字符串
     */
    private static function unescapeSpecialChars(str:String):String {
        var unescaped:String = "";
        var i:Number = 0;
        while (i < str.length) {
            var char:String = str.charAt(i);
            if (char == "\\") {
                i++; // 跳过转义字符 \
                if (i < str.length) {
                    var nextChar:String = str.charAt(i);
                    // 如果是特殊字符，则将其反转义
                    if (nextChar == "#" || nextChar == ";" || nextChar == "\\") {
                        unescaped += nextChar;
                    } else {
                        // 如果不是特殊字符，则保留反斜杠
                        unescaped += "\\" + nextChar;
                    }
                }
            } else {
                unescaped += char;
            }
            i++;
        }
        return unescaped;
    }

    /**
     * 查找未被转义的分隔符位置
     * 
     * @param input 输入的字符串
     * @param separator 要查找的分隔符
     * @param startIndex 开始查找的索引
     * @return 分隔符的位置，如果未找到则返回 -1
     */
    private static function findUnescapedSeparator(input:String, separator:String, startIndex:Number):Number {
        var index:Number = input.indexOf(separator, startIndex);
        while (index != -1) {
            var backslashCount:Number = 0;
            var k:Number = index - 1;
            // 计算分隔符前面的反斜杠数量
            while (k >= 0 && input.charAt(k) == "\\") {
                backslashCount++;
                k--;
            }
            // 如果反斜杠数量为偶数，则分隔符未被转义
            if (backslashCount % 2 == 0) {
                return index;
            }
            // 否则继续查找下一个分隔符
            index = input.indexOf(separator, index + 1);
        }
        return -1;
    }

    /**
     * 获取下一个字符，处理单字节和双字节字符
     * @param input 输入的字符串
     * @param index 当前字符的起始位置
     * @return 完整的字符
     */
    private static function getNextChar(input:String, index:Number):String {
        var charCode:Number = input.charCodeAt(index);
        // 如果是代理项对（surrogate pair），需要合并两个字符
        if (charCode >= 0xD800 && charCode <= 0xDBFF && index + 1 < input.length) {
            var nextCharCode:Number = input.charCodeAt(index + 1);
            // 判断下一个字符是否为低代理项
            if (nextCharCode >= 0xDC00 && nextCharCode <= 0xDFFF) {
                return input.substr(index, 2); // 返回两个字符的组合
            }
        }
        return input.charAt(index); // 返回单字符
    }

    /**
     * 解压缩使用 Run-Length Encoding (RLE) 编码的字符串
     * 
     * @param input 要解压的字符串
     * @return 解压后的字符串
     */
    public static function decompress(input:String):String {
        if (input == null || input.length == 0) {
            return ""; // 如果输入为空，直接返回空字符串
        }

        var decompressedParts:Array = []; // 使用数组存储解压后的字符串片段，提高性能
        var i:Number = 0;
        var inputLength:Number = input.length;

        while (i < inputLength) {
            // 查找未被转义的 '#' 分隔符
            var seqEnd:Number = findUnescapedSeparator(input, "#", i);
            if (seqEnd == -1) {
                trace("RLE 解压缩错误: 无法找到未转义的 '#' 分隔符");
                return undefined;
            }

            var sequenceEscaped:String = input.substring(i, seqEnd);
            var sequence:String = unescapeSpecialChars(sequenceEscaped);
            i = seqEnd + 1;

            // 查找未被转义的 ';' 分隔符
            var countEnd:Number = findUnescapedSeparator(input, ";", i);
            if (countEnd == -1) {
                trace("RLE 解压缩错误: 无法找到未转义的 ';' 分隔符");
                return undefined;
            }

            var countStr:String = input.substring(i, countEnd);
            var count:Number = Number(countStr);
            if (isNaN(count) || count < 1) {
                trace("RLE 解压缩错误: 无效的计数 '" + countStr + "'");
                return undefined;
            }

            // 将重复的序列添加到解压结果
            for (var j:Number = 0; j < count; j++) {
                decompressedParts.push(sequence);
            }

            i = countEnd + 1;
        }

        var decompressed:String = decompressedParts.join(""); // 将片段合并成最终的解压结果
        trace("RLE 解压缩完成。解压后长度: " + decompressed.length);
        return decompressed;
    }
}


/*
import org.flashNight.gesh.string.RLE;

trace("===== 测试 RLE 编码和解压 =====");

// Test 1: 基本的重复字符测试
var testStr1:String = "aaabbbcc";
var compressed1:String = RLE.compress(testStr1, 10);
var decompressed1:String = RLE.decompress(compressed1);
trace("Test 1 - 原始字符串: " + testStr1);
trace("Test 1 - 压缩后的字符串: " + compressed1);
trace("Test 1 - 解压后的字符串: " + decompressed1);
trace("Test 1 - 是否匹配: " + (testStr1 == decompressed1));

// Test 2: 含有表情符号和特殊字符的字符串
var testStr2:String = "hello 🌍 world";
var compressed2:String = RLE.compress(testStr2, 10);
var decompressed2:String = RLE.decompress(compressed2);
trace("Test 2 - 原始字符串: " + testStr2);
trace("Test 2 - 压缩后的字符串: " + compressed2);
trace("Test 2 - 解压后的字符串: " + decompressed2);
trace("Test 2 - 是否匹配: " + (testStr2 == decompressed2));

// Test 3: 边界测试 - 空字符串
var testStr3:String = "";
var compressed3:String = RLE.compress(testStr3, 10);
var decompressed3:String = RLE.decompress(compressed3);
trace("Test 3 - 空字符串测试");
trace("Test 3 - 压缩后的字符串: " + compressed3);
trace("Test 3 - 解压后的字符串: " + decompressed3);
trace("Test 3 - 是否匹配: " + (testStr3 == decompressed3));

// Test 4: 含有中文字符的字符串
var testStr4:String = "你好你好你好你好";
var compressed4:String = RLE.compress(testStr4, 10);
var decompressed4:String = RLE.decompress(compressed4);
trace("Test 4 - 原始字符串: " + testStr4);
trace("Test 4 - 压缩后的字符串: " + compressed4);
trace("Test 4 - 解压后的字符串: " + decompressed4);
trace("Test 4 - 是否匹配: " + (testStr4 == decompressed4));

// Test 5: 含有特殊字符（#、; 和 \）的字符串
var testStr5:String = "##;;\\##;;\\";
var compressed5:String = RLE.compress(testStr5, 10);
var decompressed5:String = RLE.decompress(compressed5);
trace("Test 5 - 原始字符串: " + testStr5);
trace("Test 5 - 压缩后的字符串: " + compressed5);
trace("Test 5 - 解压后的字符串: " + decompressed5);
trace("Test 5 - 是否匹配: " + (testStr5 == decompressed5));

// Test 6: 长字符串测试，包含多种字符
var testStr6:String = "hello你好🌍🌍🌍🌍🌍🌍🌍🌍🌍🌍🌍🌍🌍🌍world世界";
var compressed6:String = RLE.compress(testStr6, 10);
var decompressed6:String = RLE.decompress(compressed6);
trace("Test 6 - 原始字符串: " + testStr6);
trace("Test 6 - 压缩后的字符串: " + compressed6);
trace("Test 6 - 解压后的字符串: " + decompressed6);
trace("Test 6 - 是否匹配: " + (testStr6 == decompressed6));

// Test 7: 单个重复字符的长字符串
var testStr7:String = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
var compressed7:String = RLE.compress(testStr7, 10);
var decompressed7:String = RLE.decompress(compressed7);
trace("Test 7 - 原始字符串: " + testStr7);
trace("Test 7 - 压缩后的字符串: " + compressed7);
trace("Test 7 - 解压后的字符串: " + decompressed7);
trace("Test 7 - 是否匹配: " + (testStr7 == decompressed7));

// Test 8: 边界测试 - 没有重复的字符串
var testStr8:String = "abcdefgh";
var compressed8:String = RLE.compress(testStr8, 10);
var decompressed8:String = RLE.decompress(compressed8);
trace("Test 8 - 原始字符串: " + testStr8);
trace("Test 8 - 压缩后的字符串: " + compressed8);
trace("Test 8 - 解压后的字符串: " + decompressed8);
trace("Test 8 - 是否匹配: " + (testStr8 == decompressed8));

trace("===== 测试完成 =====");
trace("===== 所有测试完成 =====");

*/