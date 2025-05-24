class org.flashNight.gesh.string.Hex16Encoder {
    
    /**
     * 将十六进制字符串转换为压缩的16位编码的字符串
     * @param hexString 要转换的十六进制字符串，通常由 '0'-'9' 和 'A'-'F' 或 'a'-'f' 组成
     * @return 转换后的压缩字符串，包含头部的补齐长度信息，用于在解码时准确恢复原字符串
     * @throws Error 如果输入的十六进制字符串包含无效字符，将抛出异常
     */
    public static function encode(hexString:String):String {
        // 用于存储最终结果的数组
        var resultArray:Array = [];
        
        // 用于记录补齐的长度，初始化为0
        var paddingLength:Number = 0;
        
        // 验证输入字符串中的每个字符，确保都是合法的十六进制字符
        for (var i:Number = 0; i < hexString.length; i++) {
            var c:String = hexString.charAt(i);  // 获取当前字符
            var code:Number = c.charCodeAt(0);   // 将字符转换为其ASCII编码值
            
            // 判断该字符是否在合法的十六进制字符范围内
            if (!((code >= 48 && code <= 57) ||    // '0'-'9'，对应ASCII码48到57
                  (code >= 65 && code <= 70) ||    // 'A'-'F'，对应ASCII码65到70
                  (code >= 97 && code <= 102))) {  // 'a'-'f'，对应ASCII码97到102
                // 如果不符合十六进制字符要求，抛出异常并终止函数执行
                throw new Error("输入字符串包含无效的十六进制字符: " + c);
            }
        }
        
        // 计算补齐的长度。为了使十六进制字符数能被4整除，需要补齐相应的字符
        // 补齐长度 = (4 - (当前字符串长度 % 4)) % 4，可以保证补齐的字符数是 0 到 3 之间
        paddingLength = (4 - (hexString.length % 4)) % 4;
        
        // 通过补齐字符 '0' 使十六进制字符串的长度变为4的倍数
        for (var j:Number = 0; j < paddingLength; j++) {
            hexString += "0"; // 在字符串末尾添加 '0'
        }
        
        // 将补齐的长度信息添加到结果的开头，使用字符表示，而非数字直接存储
        // 加1是为了避免与0冲突，补齐长度+1后的值存储为第一个字符
        resultArray.push(String.fromCharCode(paddingLength + 1));
        
        // 将每4个十六进制字符组合为一个Unicode字符，并添加到结果数组中
        for (i = 0; i < hexString.length; i += 4) {
            var hexChunk:String = hexString.substr(i, 4);  // 取出4个十六进制字符
            var hexValue:Number = parseInt(hexChunk, 16);  // 将这4个字符解析为整数 (基于16进制)
            
            // 避免使用Unicode中的特殊值 \u0000 和 \uFFFF，这些值可能在某些场景中有特殊含义
            if (hexValue == 0x0000) {
                hexValue = 0x0001;  // \u0000 转换为 \u0001
            } else if (hexValue == 0xFFFF) {
                hexValue = 0xFFFE;  // \uFFFF 转换为 \uFFFE
            }
            
            // 将计算出的整数转换为Unicode字符，并添加到结果数组
            resultArray.push(String.fromCharCode(hexValue));
        }
        
        // 使用 join 方法将数组中的元素连接成一个字符串，最终返回压缩结果
        return resultArray.join("");
    }

    /**
     * 将压缩的16位编码字符串解码回原始的十六进制字符串
     * @param encodedString 压缩的字符串，其中包含头部的补齐长度信息
     * @return 解码后的十六进制字符串
     * @throws Error 如果输入的压缩字符串格式不正确，将抛出异常
     */
    public static function decode(encodedString:String):String {
        // 用于存储解码后的十六进制字符串
        var resultArray:Array = [];
        
        // 如果输入的字符串为空，则直接返回空字符串
        if (encodedString.length == 0) {
            return "";
        }
        
        // 提取字符串的第一个字符作为补齐长度信息，减去1得到实际补齐的字符数
        var paddingLength:Number = encodedString.charCodeAt(0) - 1;
        
        // 从第2个字符开始，处理每个Unicode字符，将其转换为4个十六进制字符
        for (var i:Number = 1; i < encodedString.length; i++) {
            var charCode:Number = encodedString.charCodeAt(i);  // 获取当前字符的Unicode码值
            
            // 恢复特殊字符 \u0000 和 \uFFFF，分别对应压缩时的 \u0001 和 \uFFFE
            if (charCode == 0x0001) {
                charCode = 0x0000;  // 恢复 \u0000
            } else if (charCode == 0xFFFE) {
                charCode = 0xFFFF;  // 恢复 \uFFFF
            }
            
            // 将Unicode码值转换为16进制字符串，并转为大写形式
            var hexChunk:String = charCode.toString(16).toUpperCase();
            
            // 保证每个块是4个字符长，如果不够，前面补齐 '0'
            while (hexChunk.length < 4) {
                hexChunk = "0" + hexChunk;
            }
            
            // 将该4字符的十六进制块添加到结果数组中
            resultArray.push(hexChunk);
        }
        
        // 将数组中的所有十六进制块连接成一个完整的字符串
        var result:String = resultArray.join("");
        
        // 如果存在补齐的 '0' 字符，按照补齐长度从末尾去掉多余的字符
        if (paddingLength > 0) {
            result = result.slice(0, result.length - paddingLength);
        }
        
        // 返回解码后的十六进制字符串
        return result;
    }
}


/*

// 自定义的 repeat 函数
function repeatString(str:String, count:Number):String {
    var result:String = "";
    for (var i:Number = 0; i < count; i++) {
        result += str;
    }
    return result;
}

// 辅助函数：将字符串转换为可见的Unicode编码表示（用于显示）
function toVisibleUnicode(str:String):String {
    var visibleStr:String = "";
    for (var i:Number = 0; i < str.length; i++) {
        var code:String = str.charCodeAt(i).toString(16).toUpperCase();
        while (code.length < 4) {
            code = "0" + code;
        }
        visibleStr += "\\u" + code;
    }
    return visibleStr;
}

// 测试函数
function runTests():Void {
    var testCases:Array = [
        {
            input: "FFFF",
            expectedDecode: "FFFF",
            description: "测试最大4位十六进制值"
        },
        {
            input: "0000",
            expectedDecode: "0000",
            description: "测试最小4位十六进制值"
        },
        {
            input: "1A3",
            expectedDecode: "1A3",
            description: "测试3个字符的十六进制字符串"
        },
        {
            input: "ABC1234",
            expectedDecode: "ABC1234",
            description: "测试7个字符的十六进制字符串"
        },
        {
            input: "aBcDeF",
            expectedDecode: "ABCDEF",
            description: "测试混合大小写的十六进制字符串"
        },
        {
            input: repeatString("1234", 10), // 重复次数减少到10
            expectedDecode: repeatString("1234", 10),
            description: "较长字符串测试"
        }
    ];

    for (var i:Number = 0; i < testCases.length; i++) {
        var testCase:Object = testCases[i];
        trace("运行: " + testCase.description);

        // 测试编码
        try {
            var encoded:String = org.flashNight.gesh.string.Hex16Encoder.encode(testCase.input);
            var encodedVisible:String = toVisibleUnicode(encoded);
            trace("编码结果 (转义): " + encodedVisible);
            trace("编码结果 (正常): " + encoded);
            trace("编码测试通过");
        } catch (e:Error) {
            trace("编码测试失败，错误信息: " + e.message);
            continue;
        }

        // 测试解码
        try {
            var decoded:String = org.flashNight.gesh.string.Hex16Encoder.decode(encoded);
            trace("解码结果: " + decoded);
            if (decoded.toUpperCase() == testCase.expectedDecode.toUpperCase()) {
                trace("解码测试通过");
            } else {
                trace("解码测试失败");
            }
        } catch (e:Error) {
            trace("解码测试失败，错误信息: " + e.message);
        }

        trace("-----------------------------------");
    }
}

// 调用测试函数
runTests();

*/